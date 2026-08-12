# 06 - Restore and Validation

## Objective

Validate retrieved backup media, identify the correct SQL restore sequence, restore on a separate non-production SQL Server, and establish database/application usability. This is a manual, approval-gated workflow.

## Validation workflow

```text
S3 retrieval
  -> transfer evidence
  -> RESTORE HEADERONLY / FILELISTONLY / VERIFYONLY
  -> metadata-based chain report and DBA review
  -> FULL / optional DIFF / LOG restores with NORECOVERY
  -> RECOVERY
  -> DBCC CHECKDB
  -> application/data smoke validation
```

Each layer has a different assurance boundary. No single layer proves full recoverability.

## 1. Transfer evidence

Require downloader exit 0 plus exact object-version/local-file reconciliation and compatible checksum or manifest evidence. Path and file size can demonstrate expected shape, but not cryptographic content equality.

Do not require the original backup share during the source-independent DR test.

## 2. SQL media verification

Run `Scripts/sql/verify-backup.sql` for every candidate set. Capture:

- `RESTORE HEADERONLY` metadata;
- `RESTORE FILELISTONLY` layout; and
- `RESTORE VERIFYONLY` results and `HasBackupChecksums`.

VERIFYONLY checks readability/completeness and stored SQL backup checksums when present. It does not execute crash recovery, apply the chain, run CHECKDB, or test the application.

## 3. Chain identification

Run `Get-BackupChain.ps1` with an explicit database and recovery target. Review FULL selection, differential base, FirstLSN/LastLSN continuity, recovery fork, FILE position, warnings, and target coverage. The tool reports a candidate sequence; it never restores anything and must not be treated as a guarantee.

## 4. Restore sequence

On the approved recovery instance:

1. Run FILELISTONLY and define a MOVE for every logical file.
2. Restore the selected FULL with `NORECOVERY`, `CHECKSUM`, and explicit MOVE paths.
3. Restore the selected compatible DIFFERENTIAL with `NORECOVERY`, if present.
4. Restore every required LOG in metadata order with `NORECOVERY`; use a reviewed `STOPAT` only on the containing log for point-in-time recovery.
5. Run `RESTORE DATABASE [name] WITH RECOVERY` only after final review.

Avoid `REPLACE`. Use it only for an explicitly approved disposable target after independent instance/database verification. Never drop a source or production database as part of a routine validation exercise.

## 5. Database and application validation

Run:

```sql
DBCC CHECKDB (N'<RecoveryDatabaseName>') WITH NO_INFOMSGS, ALL_ERRORMSGS;
```

Do not run repair options during validation. Then execute approved data markers, critical row/value assertions, schema checks, and isolated application smoke tests. Row counts alone are not sufficient.

## Success criteria

- Source SQL Server, source share, and source credentials remained unavailable after the isolation gate.
- Selected objects/versions and transfer integrity evidence reconcile.
- Every required SQL backup set passes verification.
- Metadata establishes a continuous compatible chain through the target.
- FULL, optional DIFF, all LOGs, and RECOVERY succeed.
- Database reaches ONLINE.
- CHECKDB reports no allocation/consistency errors.
- Mandatory data/application checks pass.
- Measured RPO and validated-service RTO meet approved targets.
- Evidence package is complete.

## LAB / POC versus production

### LAB / POC implementation

The repository supplies verification SQL, a chain-reporting utility, example restore guidance, and a repeatable manual runbook. Screenshots show a prior lab and are not evidence of every v2 control.

### Production-hardened recommendation

Use a separate recovery environment/account, temporary credentials, protected manifests/version IDs, recurring isolated restores, monitored RPO/RTO, approval gates, application dependency orchestration, and retained evidence. Automating preparation and evidence collection can improve consistency; destructive restore decisions should remain protected by explicit controls.

BackupBridge currently implements repeatable DR, not fully automated DR.

Follow [the end-to-end runbook](12-end-to-end-dr-validation-runbook.md) and record results with [the measurement template](../Results/dr-validation-results-template.md).

