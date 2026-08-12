# CVT BackupBridge v2: End-to-End Disaster Recovery Validation Runbook

## Purpose and proof objective

This is a repeatable manual DR test for the complete BackupBridge path:

```text
Source SQL Server -> FULL / DIFF / LOG -> Amazon S3
-> source unavailable -> separate recovery SQL Server
-> retrieve -> verify -> identify chain -> restore
-> DBCC CHECKDB -> application/data validation
```

A PASS proves that the selected database can be recovered from S3 without the original SQL Server, its disks, backup shares, credentials, or runtime services. It does not prove that every future backup is recoverable or that `RESTORE VERIFYONLY` proves full recoverability. The actual restore, recovery, `DBCC CHECKDB`, and application validation remain mandatory.

This procedure does not provision or modify AWS infrastructure. Never use `aws s3 sync --delete`, delete S3 objects, weaken Object Lock, or expose credentials in evidence.

## Roles

| Role | Responsibility |
|---|---|
| Test coordinator | Approvals, scope, RPO/RTO clock, evidence, disposition |
| Source DBA | Backup generation and source evidence before isolation |
| Backup Writer operator | Upload with the least-privilege writer identity |
| Recovery DBA | Retrieve, verify, sequence, restore, and validate |
| Application owner | Application and data acceptance tests |
| Independent observer | Witness source isolation and final result |

A lab may combine people, but Backup Writer and Recovery Reader credentials must remain separate.

## Test record

| Field | Value |
|---|---|
| Test ID / approval ID | |
| Date and timezone | |
| Database | |
| Source / recovery SQL instances | |
| S3 bucket / prefix / Region | |
| Recovery target | |
| Required RPO / RTO | |
| RTO start and stop events | |
| Repository commit | |
| Evidence directory | |
| Owners | |
| Result | PASS / FAIL / BLOCKED |

Use UTC where practical and document every timezone conversion.

# 1. Preconditions

Confirm before starting:

- an isolated, non-production recovery Windows/SQL Server exists;
- SQL version/edition supports restoring the source backup;
- capacity covers downloads, database and log files, growth, `tempdb`, and verification;
- AWS CLI v2, Windows PowerShell 5.1+, and the approved repository commit are present;
- an approved `settings.json` points to the recovery prefix and local restore root;
- the Recovery Reader can list/download the prefix and decrypt SSE-KMS objects;
- SQL Server's service identity can read downloads and write approved data/log paths;
- required archive-class objects have completed a temporary S3 restore, or archive delay is explicitly included in RTO;
- application smoke tests and isolated dependencies are ready; and
- no automation can connect to or modify the recovered test database.

Define the database(s), recovery target, RPO, RTO, required smoke tests, and authoritative S3 object versions. Maintain a separate chain for each database. Cross-database transactional consistency requires a separate application design and must not be assumed.

Capture source SQL version, database recovery model/state/size, previous backup history, validation baseline, clock state, S3 Versioning/Object Lock/encryption/storage class, and recovery-host capacity. Do not copy source AWS credential files or SQL secrets to recovery.

**Gate:** Proceed only when every prerequisite is satisfied. Otherwise record BLOCKED without weakening controls.

# 2. Backup generation

Use the approved BackupBridge scripts and hierarchy:

```text
<BackupRoot>\<Server>\<Database>\FULL
<BackupRoot>\<Server>\<Database>\DIFF
<BackupRoot>\<Server>\<Database>\LOG
```

1. Confirm FULL recovery model where transaction-log recovery is required.
2. Create a conventional FULL with `COMPRESSION` and `CHECKSUM`.
3. Record a safe, approved data marker.
4. Create a DIFFERENTIAL with `COMPRESSION` and `CHECKSUM`, if in scope.
5. Record another marker.
6. Create LOG backups through the requested recovery target.
7. Record UTC start/finish, path, size, and `msdb` backup history.

Do not use a `COPY_ONLY` FULL as a differential base. Test an ad-hoc copy-only backup separately if desired.

**Gate:** All commands succeed, expected `.bak`/`.trn` files exist, and the LOG sequence covers the target.

# 3. S3 synchronization

Run as Backup Writer:

```powershell
& '<RepositoryRoot>\Scripts\powershell\S3_Uploader.ps1'
$UploaderExitCode = $LASTEXITCODE
```

Capture start/end, source, destination, Region, caller identity (never credentials), AWS CLI version, repository commit, structured log, and exit code. The uploader must preserve hierarchy, include only `.bak` and `.trn`, and omit `--delete`.

**Gate:** Exit code is 0 and the final structured result is success. Continue to independent cloud confirmation.

# 4. Confirmation of cloud backup

Using a read-only/audit identity, inventory the exact prefix:

```powershell
aws s3api list-objects-v2 `
  --bucket '<BucketName>' `
  --prefix '<RecoveryPrefix>/' `
  --region '<AwsRegion>' `
  --output json
$InventoryExitCode = $LASTEXITCODE
```

For every required object record bucket, exact key, size, LastModified, VersionId, storage class, encryption/KMS identifier where permitted, checksum metadata, and Object Lock retention/legal-hold metadata where applicable. Reconcile against the local inventory.

Do not treat ETag as a universal MD5: multipart/encrypted object ETags may differ. Prefer AWS checksum metadata or a separately protected SHA-256 manifest. Exact key and size plus successful transfer logs are the minimum evidence.

**Gate:** Every authoritative object version is identified, integrity-supported, readable by Recovery Reader, and immediately retrievable. Missing, ambiguous, or unrestored archive objects are FAIL/BLOCKED according to when discovered.

# 5. Simulated source loss

After approval, safely make these unavailable to the recovery team:

- source SQL endpoint and database connections;
- source disks, local backup paths, and UNC shares;
- source scripts/configuration/scheduled tasks;
- Backup Writer credentials and source secret stores.

Use approved lab network isolation, shutdown of an expendable source VM, or access removal. Do not disrupt production without a separate authorization. From recovery, capture failed source endpoint/share tests:

```powershell
Test-NetConnection -ComputerName '<SourceSqlHost>' -Port 1433
Test-Path -LiteralPath '\\<SourceHost>\<BackupShare>'
```

The observer must confirm no alternate route remains. Start RTO at the predeclared source-loss event.

**Gate:** Any later read from the original SQL Server or backup storage invalidates the independence claim and fails the attempt.

# 6. Recovery-environment preparation

On the separate recovery host:

1. Run `SELECT @@SERVERNAME, SERVERPROPERTY('ProductVersion'), SERVERPROPERTY('Edition');` and confirm the approved non-production target.
2. Confirm free space, SQL read/write permissions, and approved data/log destinations.
3. Confirm the recovery database name cannot collide with an existing database.
4. Validate AWS CLI v2, PowerShell, repository commit, configuration, Region, time, and Recovery Reader identity.
5. Create a restricted evidence directory outside the backup directory.

```powershell
aws --version
aws sts get-caller-identity --output json
```

**Gate:** Stop if the SQL target, isolation, capacity, or independent identity cannot be positively confirmed.

# 7. Backup retrieval

```powershell
& '<RepositoryRoot>\Scripts\powershell\S3_Downloader.ps1'
$DownloaderExitCode = $LASTEXITCODE
```

Capture source/destination/Region, start/end/duration, identity, CLI version, structured log, and exit code. Inventory `.bak`/`.trn` recursively and reconcile exact relative paths, counts, sizes, versions, and checksums/manifest with cloud evidence.

File existence or `Length > 0` alone never proves success.

**Gate:** Exit code 0, final result success, complete integrity reconciliation, preserved hierarchy, and no source access.

# 8. RESTORE VERIFYONLY and metadata inspection

On the recovery SQL Server, run the repository `verify-backup.sql` workflow for every candidate backup set. Capture:

- `RESTORE HEADERONLY` metadata;
- `RESTORE FILELISTONLY` logical/physical file metadata; and
- `RESTORE VERIFYONLY ... WITH CHECKSUM` results.

Record `HasBackupChecksums`. If false, state the reduced assurance; SQL cannot validate backup checksums that were not stored. `VERIFYONLY` checks readability/completeness and available checksums, but does not execute recovery, validate all database logic, run CHECKDB, or prove application usability.

**Gate:** All selected media are readable, belong to the intended database, and are not marked damaged. Any required failure is a test FAIL.

# 9. Backup-chain identification

```powershell
& '<RepositoryRoot>\Scripts\powershell\Get-BackupChain.ps1' `
  -BackupRoot '<RestoreRootPath>' `
  -SqlInstance '<RecoverySqlInstance>' `
  -DatabaseName '<DatabaseName>' `
  -RecoveryTarget '<ISO-8601 target with offset>' `
  -OutputPath '<EvidenceRoot>\backup-chain-report.txt'
$ChainExitCode = $LASTEXITCODE
```

The DBA must review rather than blindly execute the candidate report. Confirm database, conventional FULL, differential base LSN compatibility, continuous LOG LSN coverage, recovery fork, FILE positions, recovery model, selected S3 versions, and target coverage. Exit 0 / `CANDIDATE_CHAIN_ESTABLISHED` is a prerequisite, not proof.

Create and sign a restore worksheet:

| Seq. | Type | Local file | FILE | FirstLSN | LastLSN | Option |
|---:|---|---|---:|---:|---:|---|
| 1 | FULL | | | | | NORECOVERY |
| 2 | DIFF, if selected | | | | | NORECOVERY |
| 3..n | LOG | | | | | NORECOVERY / STOPAT |
| Final | RECOVERY | N/A | N/A | N/A | N/A | RECOVERY |

**Gate:** Stop on an unresolved warning, gap, fork, base, version, or target ambiguity. Never guess from filenames.

# 10. FULL restore

Use `RESTORE FILELISTONLY` and create a `MOVE` for every file. Restore under an approved test name:

```sql
RESTORE DATABASE [<RecoveryDatabaseName>]
FROM DISK = N'<FullBackupPath>'
WITH FILE = <Position>,
     MOVE N'<LogicalData>' TO N'<ApprovedDataPath>',
     MOVE N'<LogicalLog>'  TO N'<ApprovedLogPath>',
     NORECOVERY, CHECKSUM, STATS = 5;
```

Do not use `REPLACE` unless a separate approval identifies a disposable target and a second DBA verifies it.

**Gate:** Restore succeeds without media/checksum error and database state is `RESTORING`.

# 11. DIFFERENTIAL restore

If the reviewed chain includes one:

```sql
RESTORE DATABASE [<RecoveryDatabaseName>]
FROM DISK = N'<DifferentialBackupPath>'
WITH FILE = <Position>, NORECOVERY, CHECKSUM, STATS = 5;
```

Otherwise mark NOT APPLICABLE. Never choose a DIFF from timestamp/filename alone.

**Gate:** Selected DIFF succeeds and state remains `RESTORING`, or the worksheet explicitly requires none.

# 12. LOG restore

Apply every selected log in exact metadata order:

```sql
RESTORE LOG [<RecoveryDatabaseName>]
FROM DISK = N'<LogBackupPath>'
WITH FILE = <Position>, NORECOVERY, CHECKSUM, STATS = 5;
```

For point-in-time recovery, use an unambiguous approved `STOPAT` on the containing log, retain `NORECOVERY`, and document timezone interpretation. Never skip a failed log.

**Gate:** All logs succeed, no LSN/fork/checksum gap exists, the target is covered, and state remains `RESTORING`.

# 13. RECOVERY

After final worksheet review:

```sql
RESTORE DATABASE [<RecoveryDatabaseName>] WITH RECOVERY;
```

Capture state from `sys.databases`. Additional logs cannot be applied after recovery without restarting the restore.

**Gate:** Database is `ONLINE`, no recovery error occurred, and the recovered point meets RPO.

# 14. DBCC CHECKDB

```sql
DBCC CHECKDB (N'<RecoveryDatabaseName>') WITH NO_INFOMSGS, ALL_ERRORMSGS;
```

Capture complete output and duration. Do not run repair options. Report technical restore RTO and validated-service RTO separately if CHECKDB is not part of the service-release gate.

**Gate:** CHECKDB completes with no allocation or consistency error. Any error is FAIL.

# 15. Data and application validation

Execute pre-approved, deterministic checks:

- critical row counts compared with the recovery-point baseline;
- presence of markers/transactions at or before the target;
- absence of markers after a point-in-time target;
- representative recent business records;
- required schema, views, procedures, and database principals;
- isolated application connection; and
- critical read-only user journeys with no production integrations.

Row counts alone are insufficient. Capture redacted results and stop RTO at the predeclared acceptance event.

**Gate:** All mandatory assertions match the intended recovery point and smoke validation succeeds.

# 16. Evidence collection

Create an access-controlled evidence package with SHA-256 hashes and an independently protected index:

| ID | Evidence |
|---|---|
| E01 | Scope, approvals, RPO/RTO definition, owners |
| E02 | Source version, recovery model, baseline, backup history |
| E03 | Backup output and local inventory |
| E04 | Uploader log, identity, CLI/repository version, exit code |
| E05 | S3 keys, versions, size, checksum, class, encryption/retention metadata |
| E06 | Witnessed source endpoint/share unavailability |
| E07 | Recovery host version, capacity, isolation, identity |
| E08 | Downloader log, exit code, local/cloud reconciliation |
| E09 | HEADERONLY, FILELISTONLY, VERIFYONLY output |
| E10 | Chain report, exit code, signed restore worksheet |
| E11 | FULL/DIFF/LOG/RECOVERY output and restore history |
| E12 | Complete CHECKDB output |
| E13 | Data/application smoke results |
| E14 | RPO/RTO milestones, deviations, owners, sign-off |

Redact credentials, connection secrets, sensitive customer data, and unnecessary account details.

# 17. Success/failure criteria

## PASS

PASS requires every mandatory gate plus all of these:

- upload/download exit 0 and integrity reconciliation;
- original SQL Server, storage, and credentials unavailable throughout recovery;
- separate recovery host and Recovery Reader identity used;
- verified, metadata-derived, continuous chain through the target;
- FULL, optional DIFF, all LOGs, and RECOVERY succeed;
- database ONLINE; RPO and RTO met;
- CHECKDB clean;
- mandatory application/data tests pass; and
- complete approved evidence.

## FAIL

FAIL includes any source dependency after isolation; missing/ambiguous/wrong-version/corrupt object; nonzero transfer; integrity mismatch; wrong database; damaged media; incompatible DIFF; LSN/fork gap; missed target; restore failure; RPO/RTO miss; CHECKDB error; failed smoke test; or evidence unable to substantiate recovery.

Do not turn an undocumented retry into a pass. Close the attempt as FAIL and use a new test ID for a corrected rerun.

## BLOCKED

Use BLOCKED only when an approved external prerequisite prevents safe execution before the recovery path is tested, such as an incomplete scheduled archive retrieval or unavailable lab host. A discovered design failure after execution begins is normally FAIL.

## Measurements

```text
Observed RPO = source-loss time - latest validated recovered transaction time
Observed RTO = validation-complete time - declared source-loss time
```

Break RTO into archive retrieval, download, verification/chain analysis, SQL restore/recovery, CHECKDB, application validation, and total.

## Reset and repeat

After sign-off, protect evidence, disconnect the test application, clean up only through the approved lab process, and retain downloads under local staging policy. Do not delete S3 objects; S3 Lifecycle manages cloud retention. Record lessons and rerun after material SQL, application, IAM, encryption, lifecycle, or tooling changes.

Repeat on a defined cadence with different databases, recovery targets, storage classes, operators, and failure conditions. A paper review does not replace an isolated restore.

## Troubleshooting and mandatory stops

| Condition | Response |
|---|---|
| Access denied | Correct Recovery Reader prefix/KMS access; never grant writer/admin as a shortcut |
| Archived object | Complete approved temporary restore and account for delay |
| Downloader nonzero | Preserve logs and correct cause; local files do not prove success |
| Checksum mismatch | Quarantine evidence and FAIL |
| VERIFYONLY failure | Stop; do not restore that media |
| Chain tool returns 2/gap | Locate the missing/correct object; never guess |
| DIFF base mismatch | Use only a separately reviewed valid FULL+LOG chain or FAIL |
| Restore requests overwrite | Stop and reverify instance, database, and approval |
| Insufficient disk | Stop and provide approved capacity |
| CHECKDB corruption | FAIL; do not repair during validation |
| Smoke mismatch | Investigate target, timezone, chain, and application consistency |
| Any source access after isolation | FAIL the independence proof |

## Final sign-off

| Signatory | Name | Result | UTC time | Signature/reference |
|---|---|---|---|---|
| Recovery DBA | | | | |
| Application owner | | | | |
| Test coordinator | | | | |
| Independent observer | | | | |

There is no overall “pass with exceptions” when an exception affects source independence, recoverability, RPO, RTO, integrity, security, or mandatory application validation.

