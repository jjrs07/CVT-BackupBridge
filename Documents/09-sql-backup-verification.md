# SQL Server Backup Verification Workflow

## 1. Purpose

This stage validates retrieved SQL Server backup files before a complete disaster-recovery restore is attempted. It does not modify or restore a production database.

```text
S3 retrieval
   ↓
Transfer validation
   ↓
RESTORE VERIFYONLY
   ↓
Backup metadata inspection
   ↓
Actual SQL restore
   ↓
DBCC CHECKDB
```

The supplied `Scripts/sql/verify-backup.sql` performs metadata inspection and file verification only. It never executes `RESTORE DATABASE`, `RESTORE LOG`, or `DBCC CHECKDB`.

## 2. Assurance boundaries

| Stage | What it validates | What it does not prove |
|---|---|---|
| S3 retrieval | AWS CLI completed; compatible stored S3 checksum validated | SQL Server can read the backup |
| Transfer validation | Expected path, exact size, and manifest hash where available | Backup set is internally usable |
| `RESTORE HEADERONLY` | Identity, type, LSNs, dates, source version, checksum and damage flags | Pages can be restored and recovered |
| `RESTORE VERIFYONLY` | Media readability and backup-set completeness; SQL checksums when present | Full restore, recovery, consistency, or application usability |
| Actual restore | Files can be created, backup sequence applied, recovery completed, database brought online | Database consistency and business correctness |
| `DBCC CHECKDB` | Physical and logical database consistency | Application and business-data correctness |

Never record a successful `VERIFYONLY` as “restore succeeded” or “fully recoverable.” Record it only as file verification succeeded.

## 3. Architecture and prerequisites

- Use an isolated non-production SQL Server instance capable of restoring the source SQL Server version.
- Retrieve files with `S3_Downloader.ps1` and require AWS CLI exit code 0 and `FinalResult=SUCCESS`.
- Preserve the S3 key, version ID, content length, checksum metadata, and downloader log.
- Give the SQL Server Database Engine service account read access to the retrieved files.
- Use UNC paths rather than mapped drives for remote storage.
- Install `sqlcmd` and use `-b` so SQL errors produce a failing process exit code.
- Reserve sufficient data, log, and `tempdb` capacity for the later actual restore and `DBCC CHECKDB`.
- Protect TDE certificates, private keys, and backup passwords separately and test their recovery.

## 4. Running the verification script

Example with Windows authentication:

```powershell
sqlcmd.exe `
    -S "LABSQL01" `
    -E `
    -b `
    -i ".\Scripts\sql\verify-backup.sql" `
    -v BackupFile="H:\SQLRestore\SQL01\DatabaseA\FULL\DatabaseA_FULL_001.bak" `
       BackupSetPosition="1" `
    -o ".\Logs\DatabaseA_FULL_001.verify.log"
```

- `BackupFile` is the absolute path as seen by the SQL Server service.
- `BackupSetPosition` selects the backup set on the media and is normally `1`.
- `-o` preserves messages and the native `HEADERONLY` result set as evidence.
- `-b` makes verification suitable for automation and acceptance gates.

## 5. Transfer validation

Before SQL inspection:

1. Confirm the expected S3 key and local relative path.
2. Compare exact S3 and local byte lengths.
3. Confirm AWS CLI checksum mode was requested.
4. Where a manifest stores a full-object SHA-256, calculate and compare the local SHA-256.
5. Do not treat an ETag as a full-file MD5 for multipart or SSE-KMS objects.
6. Confirm every required FULL, DIFF, and LOG file was retrieved.

## 6. RESTORE HEADERONLY metadata inspection

The script returns SQL Server’s native `RESTORE HEADERONLY` result set. This avoids a version-fragile temporary table because result columns can vary by SQL Server release.

Review and retain at least:

- `Position`, `DatabaseName`, `BackupType`, start and finish dates.
- `FirstLSN`, `LastLSN`, `CheckpointLSN`, and `DatabaseBackupLSN`.
- `RecoveryModel`, recovery-fork identifiers, and `FamilyGUID`.
- `HasBackupChecksums`, `IsDamaged`, and `IsCopyOnly`.
- Source server, machine, collation, and SQL Server build.

`IsDamaged = 1` fails the operational acceptance decision. Metadata must also show that the selected FULL/DIFF/LOG files belong to the intended database and form a continuous recovery sequence.

## 7. Checksum behavior

The script intentionally uses default `RESTORE VERIFYONLY` checksum behavior and never specifies `NO_CHECKSUM` or `CONTINUE_AFTER_ERROR`.

- If `HasBackupChecksums = 1`, SQL Server validates stored backup checksums and relevant page checksums.
- If `HasBackupChecksums = 0`, SQL Server performs readability and completeness checks without checksum assurance.
- Forcing `WITH CHECKSUM` would cause a checksum-less legacy backup to fail because checksum metadata is absent.

Classify results as either:

- `VERIFIED_WITH_SQL_BACKUP_CHECKSUMS`, or
- `READABLE_WITHOUT_SQL_BACKUP_CHECKSUMS`.

New production backup jobs should create database and log backups using `WITH CHECKSUM`. A readable checksum-less backup has weaker assurance.

## 8. Why RESTORE VERIFYONLY is insufficient

`RESTORE VERIFYONLY` does not:

- Create data and log files.
- Validate destination paths or available disk capacity.
- Apply every backup page to a database.
- Replay the complete log chain.
- Run recovery or bring a database online.
- Detect every logical or physical consistency problem.
- Validate encryption-key availability for the complete procedure.
- Validate logins, jobs, linked servers, application dependencies, or business data.
- Prove the recovery-time objective.

A restore can therefore fail after `VERIFYONLY` succeeds.

## 9. Actual restore is the strongest validation

The strongest practical test is an actual restore to an isolated non-production instance:

1. Restore the selected FULL backup with `NORECOVERY`.
2. Apply the selected differential backup, if used, with `NORECOVERY`.
3. Apply every required transaction-log backup in LSN order.
4. Apply `STOPAT` when testing point-in-time recovery.
5. Restore the final backup with `RECOVERY`.
6. Confirm the test database reaches `ONLINE`.
7. Run full `DBCC CHECKDB`.
8. Run application and business smoke tests.
9. Measure elapsed time against RTO.
10. Retain evidence and clean up only through an approved process.

Do not use `WITH REPLACE` against an existing database without a separate reviewed restore runbook.

## 10. DBCC CHECKDB

After the isolated database is online:

```sql
DBCC CHECKDB (N'<isolated_restored_database>')
WITH NO_INFOMSGS, ALL_ERRORMSGS;
```

Do not use repair options as part of verification. For very large databases, `PHYSICAL_ONLY` can support frequent checks, but it is not a substitute for a periodic full `DBCC CHECKDB`. Disaster-recovery qualification should use the full check unless a documented constraint is accepted.

## 11. Acceptance criteria

### File verification passes when

- Retrieval and transfer validation passed.
- `RESTORE HEADERONLY` completed and identifies the intended backup.
- `IsDamaged` is not set.
- Checksum availability is explicitly recorded.
- LSN and recovery-fork metadata are consistent with the planned chain.
- `RESTORE VERIFYONLY` completed without error.
- SQLCMD returned exit code 0.

### Disaster-recovery validation passes only when

- Every required file passes the file gate.
- The recovery chain is complete.
- The isolated restore and recovery complete.
- The test database is online.
- Full `DBCC CHECKDB` reports no errors.
- Required smoke tests pass.
- The measured restore meets RTO.

## 12. Failure handling

1. Preserve SQLCMD and transfer evidence.
2. Record the local path, S3 key/version, SQL instance, checksum status, and timestamp.
3. Quarantine the failed file from the approved recovery set.
4. Do not use `CONTINUE_AFTER_ERROR`.
5. Retrieve another protected version or known-good chain.
6. Investigate storage, transfer, media, and source backup-job health.
7. Do not delete the failed protected S3 version; preserve it for investigation.

## 13. Validation tests

Before adoption, test:

1. Known-good checksum-bearing backup.
2. Deliberately corrupted disposable copy; require nonzero SQLCMD result.
3. Known checksum-less legacy backup and weaker classification.
4. Invalid backup-set position.
5. Missing file.
6. SQL Server service access denied.
7. Multi-set media with the correct `FILE` position.
8. Complete isolated FULL/DIFF/LOG restore.
9. Full `DBCC CHECKDB`.
10. Confirmation that no production database was created, replaced, or altered.

## 14. Troubleshooting

### Operating system error 5

Grant read access to the SQL Server Database Engine service identity, not only the DBA.

### Operating system error 2

Validate the path from the SQL Server host. Prefer UNC paths over mapped drives.

### Backup created on a newer SQL version

Restore to the same or a newer supported SQL Server version.

### VERIFYONLY succeeds but restore fails

Investigate chain continuity, recovery fork, paths, capacity, version, encryption keys, permissions, and recovery errors. This is why verification is not a restore.

### DBCC CHECKDB reports errors

Preserve evidence and select another known-good protected recovery chain. Repair is not the default response.

## 15. Microsoft references

- [RESTORE VERIFYONLY](https://learn.microsoft.com/en-us/sql/t-sql/statements/restore-statements-verifyonly-transact-sql)
- [RESTORE HEADERONLY](https://learn.microsoft.com/en-us/sql/t-sql/statements/restore-statements-headeronly-transact-sql)
- [RESTORE checksum arguments](https://learn.microsoft.com/en-us/sql/t-sql/statements/restore-statements-arguments-transact-sql)
- [Backup checksums](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/enable-or-disable-backup-checksums-during-backup-or-restore-sql-server)
- [Backup media errors](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/possible-media-errors-during-backup-and-restore-sql-server)
- [DBCC CHECKDB](https://learn.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-checkdb-transact-sql)