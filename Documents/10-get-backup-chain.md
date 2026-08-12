# Get-BackupChain.ps1

## Purpose

`Get-BackupChain.ps1` helps a DBA identify a candidate SQL Server restore sequence from a directory containing FULL, DIFFERENTIAL, and TRANSACTION LOG backups.

It uses `RESTORE HEADERONLY` metadata rather than trusting filenames. It never restores a database or transaction log.

## Workflow

```text
Retrieved backup directory
  -> recursive .bak/.trn discovery
  -> RESTORE HEADERONLY for every file and backup-set position
  -> database and target-time filtering
  -> FULL and compatible DIFFERENTIAL selection
  -> transaction-log LSN traversal
  -> gaps, forks, damage, checksum, and ambiguity warnings
  -> human-readable restore-order report
```

## Prerequisites

- Windows PowerShell 5.1 or later.
- A non-production SQL Server instance for metadata inspection.
- Windows integrated authentication to that instance.
- SQL Server service-account read access to every local or UNC backup path.
- Permission to execute `RESTORE HEADERONLY`.
- Certificates or keys required to read encrypted SQL Server backups.

The utility uses `System.Data.SqlClient`; `Invoke-Sqlcmd` is not required. It neither accepts nor embeds a SQL password.

## Parameters

| Parameter | Required | Description |
|---|---:|---|
| `BackupRoot` | Yes | Directory recursively searched for `.bak` and `.trn` files |
| `SqlInstance` | Yes | Non-production SQL instance used for `HEADERONLY` |
| `DatabaseName` | No | Database to analyze; required when metadata contains multiple databases |
| `RecoveryTarget` | No | Target date/time; omit for the latest continuous point |
| `CommandTimeoutSeconds` | No | Per-file metadata command timeout; default 120 |
| `ConnectionTimeoutSeconds` | No | SQL connection timeout; default 15 |
| `EncryptConnection` | No | Requests SQL connection encryption |
| `TrustServerCertificate` | No | Trusts the presented SQL certificate; use only under approved policy |
| `OutputPath` | No | Writes a UTF-8 copy of the report; parent directory must exist |

## Examples

Analyze the only database in a directory:

```powershell
.\Scripts\powershell\Get-BackupChain.ps1 `
  -BackupRoot 'H:\SQLRestore\SQL01\Accounting' `
  -SqlInstance 'LABSQL01' `
  -EncryptConnection
```

Select a database and point-in-time target:

```powershell
.\Scripts\powershell\Get-BackupChain.ps1 `
  -BackupRoot '\\RecoveryShare\SQLRestore\SQL01' `
  -SqlInstance 'LABSQL01' `
  -DatabaseName 'Accounting' `
  -RecoveryTarget '2026-08-13T10:15:00+08:00' `
  -EncryptConnection `
  -OutputPath 'C:\RecoveryEvidence\Accounting-chain.txt'
```

Use an ISO 8601 timestamp with an explicit offset or UTC `Z`. Avoid ambiguous local times.

## Algorithm

### 1. Metadata collection

The utility runs this read-only metadata command against every discovered file:

```sql
RESTORE HEADERONLY FROM DISK = N'<path>';
```

Every returned row becomes a separate backup-set record. This supports media files containing more than one backup set and preserves the required `FILE` position.

Captured fields include:

- `DatabaseName`
- `BackupType` and `BackupTypeDescription`
- `BackupStartDate` and `BackupFinishDate`
- `FirstLSN` and `LastLSN`
- `CheckpointLSN`
- `DatabaseBackupLSN`
- `DifferentialBaseLSN`
- `RecoveryModel`
- `RecoveryForkID` and `FirstRecoveryForkID` when available
- `FamilyGUID`
- `IsCopyOnly`, `IsDamaged`, and `HasBackupChecksums`

Unreadable files are reported. Because an unreadable candidate can hide a required chain member, the final chain status is not established when any scanned backup file cannot be inspected.

### 2. Database selection

If `DatabaseName` is omitted, exactly one database must exist in readable metadata. The utility refuses to choose when several databases are present.

### 3. FULL and DIFFERENTIAL selection

For each eligible undamaged FULL completed at or before the recovery target:

1. Treat a conventional full as a possible differential base.
2. Match differentials using `DifferentialBaseLSN` or `DatabaseBackupLSN` against the full’s `CheckpointLSN`.
3. Do not attach a differential to a copy-only full.
4. Select the latest compatible differential for that full.
5. Compare each resulting effective base and select the one with the latest finish time.

This may choose a slightly older conventional full plus a newer compatible differential over a newer copy-only full when that produces the most advanced valid base.

### 4. Transaction-log traversal

The selected FULL or DIFFERENTIAL contributes the starting `LastLSN`. Candidate log sets must advance beyond it.

For each step, the utility requires:

```text
next.FirstLSN <= current.LastLSN
next.LastLSN  > current.LastLSN
```

When several backups overlap, it chooses the earliest advancing `LastLSN` and warns. When the next candidate starts after current coverage, it reports an obvious LSN gap and stops.

For a target time, traversal stops after a continuous selected log has a finish time at or beyond the target. SQL Server must still validate that the requested `STOPAT` value is usable during an actual restore.

Recovery-fork conflicts among selected records cause `CHAIN_NOT_ESTABLISHED`.

## Report and exit codes

The report contains:

- Scan statistics and unreadable-file count.
- Selected FULL and DIFFERENTIAL metadata.
- Ordered FULL, DIFF, and LOG steps with file path, media position, and LSN range.
- Checksum, damage, incompatibility, overlap, gap, target-coverage, and recovery-fork warnings.
- Final chain status.

| Exit code | Meaning |
|---:|---|
| 0 | A candidate chain was established from the inspected metadata |
| 2 | Metadata was read, but a defensible chain was not established |
| PowerShell failure | Invalid input, SQL connection failure, no metadata, or another terminating error |

Exit code 0 means candidate metadata continuity only. It is not proof that a restore will succeed.

## Assumptions and limitations

- Filenames and folder names do not determine the chain.
- Numeric LSN continuity detects obvious gaps but does not reproduce every SQL Server restore rule.
- Backup finish time is used to select eligible FULL/DIFF sets.
- Time-based log coverage is advisory; `STOPAT` is validated only by an actual restore.
- Encrypted or damaged media may prevent metadata access.
- Availability-group copy preferences and backup location do not replace LSN and recovery-fork checks.
- A valid chain can include logs whose time ranges overlap.
- The tool does not generate or execute final `RESTORE ... MOVE`, `NORECOVERY`, `RECOVERY`, or `STOPAT` commands.
- Restore destinations, file paths, capacity, SQL version compatibility, TDE keys, and application dependencies remain outside this report.

## Required next validation

Use the reported order as DBA-reviewed input to:

1. Preserve `RESTORE HEADERONLY` evidence.
2. Run `RESTORE VERIFYONLY` for every selected set.
3. Confirm the FULL/DIFF/LOG chain and recovery target manually.
4. Restore to an isolated non-production database.
5. Apply logs with `NORECOVERY` until the final recovery step.
6. Run full `DBCC CHECKDB`.
7. Perform application and business smoke tests.
8. Measure the restore against RTO.

## Security

- Windows integrated authentication is mandatory in this implementation.
- No SQL password parameter exists.
- Do not put passwords in script source, command lines, or report files.
- Use a dedicated metadata/verification SQL instance rather than production.
- Grant the SQL Server service read-only access to the recovery share.
- Reports can expose database names, paths, server names, LSNs, and recovery timing; protect them as recovery evidence.
- `TrustServerCertificate` weakens certificate identity validation and should be used only when approved.

## Troubleshooting

### Multiple databases detected

Supply `-DatabaseName`; the utility will not infer intent.

### Operating system error 5

Grant backup-path read permission to the SQL Server Database Engine service identity.

### File works locally but SQL Server cannot read it

SQL Server reads from its own host and service context. Use a valid UNC path rather than a mapped drive.

### No differential selected

Confirm the differential’s base LSN matches the selected conventional full’s checkpoint LSN. A copy-only full is not a differential base.

### LSN gap reported

Locate the missing protected log backup or select an earlier recovery target/base. Do not bypass the warning by sorting filenames.

### Chain report succeeds but restore fails

Investigate SQL version, recovery fork, encryption keys, destination paths, capacity, permissions, media damage, and SQL Server’s restore error. The report is planning evidence, not restore proof.

## Validation plan

Test using synthetic non-production backups:

1. One full only.
2. Full plus compatible differential.
3. Full plus continuous logs.
4. Full, differential, and continuous logs.
5. Multiple databases without `DatabaseName`.
6. Copy-only full adjacent to a conventional chain.
7. Incompatible differential base.
8. Missing middle log.
9. Overlapping duplicate logs.
10. Multiple backup sets in one media file.
11. Damaged or unreadable file.
12. Backup without checksums.
13. Point-in-time target covered and not covered.
14. Recovery-fork conflict.
15. Encrypted backup with and without required key material.

No test should target or overwrite a production database.