# 03 - SQL Server Backup Generation

## 1. Objective

CVT BackupBridge v2 creates locally staged SQL Server backups that are subsequently synchronized to protected Amazon S3 storage.

The strategy supports:

- Full database backups.
- Differential database backups.
- Transaction-log backups for point-in-time recovery.
- Backup compression.
- SQL Server backup checksums.
- Unique, timestamped files.
- A stable directory hierarchy consumed by the S3 uploader.
- Independent local and cloud retention policies.

Backup generation, S3 transfer, SQL verification, and an actual disaster-recovery restore are separate stages. A successful backup command or upload does not prove recoverability.

## 2. Architecture overview

```text
SQL Server backup job
   ↓
Local Server/Database/Type hierarchy
   ↓
S3_Uploader.ps1 using aws s3 sync
   ↓
Versioned/immutable S3 protection
   ↓
S3_Downloader.ps1
   ↓
RESTORE HEADERONLY + RESTORE VERIFYONLY
   ↓
Isolated actual restore + DBCC CHECKDB
```

## 3. Recovery model

Use the `FULL` recovery model for databases that require transaction-log backups and point-in-time recovery.

Check the current model:

```sql
SELECT name, recovery_model_desc
FROM sys.databases
WHERE name = N'<DATABASE_NAME>';
```

Changing recovery model is a separately approved database operation and is intentionally not included in the example backup scripts:

```sql
ALTER DATABASE [<DATABASE_NAME>] SET RECOVERY FULL;
```

After switching from `SIMPLE` to `FULL`, take a conventional non-`COPY_ONLY` full backup to establish the backup baseline before relying on transaction-log backups. Schedule log backups immediately afterward and monitor log reuse and growth.

`SIMPLE` recovery does not support transaction-log backups. `BULK_LOGGED` has special point-in-time and bulk-operation considerations and is not the default BackupBridge v2 recommendation.

## 4. Backup strategy

| Type | Illustrative schedule | Recovery purpose |
|---|---|---|
| FULL | Daily or weekly according to RTO and database size | Complete database backup and differential base |
| DIFFERENTIAL | Every 4–12 hours | Changes since the latest conventional full; reduces restore time |
| LOG | Every 5–30 minutes according to RPO | Continuous log chain and point-in-time recovery |

Schedules are examples, not universal defaults. Choose them from measured change rate, backup duration, RPO, RTO, restore-test results, storage capacity, and business criticality.

### Why log-backup frequency affects RPO

Under the FULL recovery model, a log backup captures log records not captured by the preceding log backup. If the latest usable log backup is 15 minutes old and no tail-log backup can be obtained, up to approximately 15 minutes of work may be exposed.

More frequent log backups generally reduce work-loss exposure, make individual log files smaller, and help transaction-log truncation. They also create more files and operational events. Missing or damaged log backups break the usable chain beyond that point, so every required log file must be protected and tested.

## 5. Local directory convention

Canonical layout:

```text
<BackupRoot>\
└── <Server>\
    └── <Database>\
        ├── FULL\
        ├── DIFF\
        └── LOG\
```

Example:

```text
H:\SQLBackups\
└── SQL01\
    └── Accounting\
        ├── FULL\
        ├── DIFF\
        └── LOG\
```

The v2 scripts sanitize Windows-invalid characters in generated server and database path components. The directories must already exist. SQL Server should not be granted authority to create arbitrary directories.

Grant the SQL Server Database Engine or SQL Server Agent execution identity only the filesystem permissions required to write backup files beneath the approved root. `Full Control` is not the default recommendation.

## 6. Filename and backup-set conventions

Generated filenames follow:

```text
<Server>_<Database>_<TYPE>_<YYYYMMDD_HHMMSSmmm>Z_<8-char-id>.<extension>
```

Examples:

```text
SQL01_Accounting_FULL_20260813_021530123Z_a1b2c3d4.bak
SQL01_Accounting_DIFF_20260813_081500456Z_e5f6a7b8.bak
SQL01_Accounting_LOG_20260813_083000789Z_c9d0e1f2.trn
```

The UTC timestamp makes sequencing visible; the short GUID suffix prevents collisions between backups launched in the same millisecond. Each unique file contains one backup set and uses `INIT`.

The media `NAME` and `DESCRIPTION` identify the database, backup type, UTC time, and copy-only status. Meaningful names improve `RESTORE HEADERONLY` evidence and recovery selection.

## 7. Canonical v2 scripts

- `Scripts/sql/backup-v2/full-backup.sql`
- `Scripts/sql/backup-v2/differential-backup.sql`
- `Scripts/sql/backup-v2/log-backup.sql`

All scripts:

- Require SQLCMD variables.
- Validate that the database exists and is online.
- Generate unique UTC filenames.
- Use `COMPRESSION`.
- Use `CHECKSUM`.
- Use `INIT` for the new unique file.
- Use meaningful `NAME` and `DESCRIPTION` metadata.
- Return SQL errors through `:On Error exit` and `THROW`.
- Print destination and final result.
- Do not create directories.
- Do not change recovery model.
- Do not delete old backups.

### Full backup

```powershell
sqlcmd.exe `
  -S "SQL01" -E -b `
  -i ".\Scripts\sql\backup-v2\full-backup.sql" `
  -v DatabaseName="Accounting" BackupRoot="H:\SQLBackups" CopyOnly="0"
```

Use `CopyOnly="0"` for the scheduled full that should establish the differential base.

### Differential backup

```powershell
sqlcmd.exe `
  -S "SQL01" -E -b `
  -i ".\Scripts\sql\backup-v2\differential-backup.sql" `
  -v DatabaseName="Accounting" BackupRoot="H:\SQLBackups"
```

The script requires a conventional full backup recorded in `msdb`.

### Transaction-log backup

```powershell
sqlcmd.exe `
  -S "SQL01" -E -b `
  -i ".\Scripts\sql\backup-v2\log-backup.sql" `
  -v DatabaseName="Accounting" BackupRoot="H:\SQLBackups"
```

The script requires `FULL` recovery and a conventional full backup in `msdb`.

## 8. CHECKSUM

`WITH CHECKSUM` instructs SQL Server to:

- Verify existing page checksums as pages are read where applicable.
- Calculate a checksum over the backup stream.
- Store backup checksum metadata in the backup set.
- Stop the backup when a checksum error is encountered unless an unsafe continue-after-error behavior is explicitly requested.

During restore or `RESTORE VERIFYONLY`, SQL Server can validate stored backup and page checksums. `RESTORE HEADERONLY` exposes `HasBackupChecksums`.

CHECKSUM improves detection of corruption in source pages and backup media. It does not prove that:

- A complete FULL/DIFF/LOG chain exists.
- The backup can be restored on the intended target.
- Database recovery will complete.
- The restored database is logically and physically consistent.
- Application data is correct.

Actual isolated restore plus `DBCC CHECKDB` remains the strongest practical validation.

## 9. COMPRESSION

`WITH COMPRESSION` usually produces smaller backup files and reduces backup-device I/O. For BackupBridge this provides:

- Less local staging capacity.
- Fewer bytes sent through `aws s3 sync`.
- Shorter cloud-transfer windows.
- Lower S3 storage consumption.
- Faster recovery downloads when network bandwidth is limiting.

Compression consumes additional SQL Server CPU. Benchmark backup duration, application impact, compression ratio, and restore throughput. Schedule around workload peaks or use approved workload controls when CPU contention is material.

Compression does not replace encryption or checksums.

## 10. COPY_ONLY

A copy-only full backup is useful for an ad-hoc export, migration test, or one-off recovery exercise because it does not become the differential base and does not disrupt the normal differential strategy.

Run the full example with `CopyOnly="1"` only when that behavior is intended.

Important limitations:

- A copy-only full cannot serve as the differential base.
- `COPY_ONLY` has no useful effect with a differential backup.
- Copy-only log backups are usually unnecessary and do not truncate the transaction log.
- Routine scheduled full backups should not normally be copy-only.

## 11. Review of the previous examples

The previous embedded examples used:

```text
NOFORMAT, NOINIT, SKIP, NOREWIND, NOUNLOAD
```

Assessment:

- `NOREWIND` and `NOUNLOAD` are tape-oriented and unnecessary for disk backup files.
- `NOFORMAT` and `SKIP` add noise for a new unique file and can obscure media-safety intent.
- `NOINIT` appends another backup set when a filename collides, complicating recovery selection. V2 uses unique names and `INIT`.
- Hard-coded timestamps can overwrite or append to unintended files.
- `CHECKSUM` was missing.
- `Full Control` filesystem permission was broader than necessary.
- The previous fixed 24–48-hour local retention recommendation was not tied to upload verification, outage tolerance, RPO/RTO, or restore testing.

The v2 examples deliberately avoid advanced tuning options such as `BUFFERCOUNT`, `MAXTRANSFERSIZE`, or `BLOCKSIZE`. Add them only after measured testing for the exact SQL Server version, storage path, and workload.

## 12. Local retention versus cloud retention

Local staging and protected cloud retention serve different purposes.

Local retention supports:

- Fast retry when S3 synchronization fails.
- Fast operational restore without cloud retrieval.
- Buffering during network or AWS outages.
- Verification before local deletion.

Cloud retention supports:

- Offsite disaster recovery.
- Ransomware dwell-time coverage.
- Version recovery and immutability.
- Legal, contractual, or regulatory retention.
- Longer-term recovery points and archive tiers.

Therefore, local retention must not automatically equal cloud retention. A local policy might retain several successfully uploaded and verified recovery chains, while S3 retains protected versions for weeks, months, or years according to approved policy.

Do not delete a local backup solely because an object with the same name exists in S3. Require:

1. Successful uploader exit code.
2. Expected S3 key and exact size.
3. Checksum/manifest validation where available.
4. SQL backup verification status.
5. At least one complete retained local recovery chain or an approved exception.
6. Confirmation that cloud Versioning/Object Lock retention is effective.

Cleanup must be a separate, auditable process. The uploader does not delete local files.

## 13. Scheduling and monitoring

Use SQL Server Agent or an enterprise scheduler. Separate FULL, DIFF, and LOG jobs so each has independent scheduling, alerts, and retry policy.

Monitor:

- Job outcome and duration.
- Backup size and compression ratio.
- `msdb` backup history.
- Age of latest full, differential, and log backup.
- Log-chain gaps.
- Transaction-log reuse wait and growth.
- Local free space.
- Uploader lag and failed S3 synchronization.
- Verification and restore-test results.

A job is not healthy merely because it ran. Alert when the latest successful backup exceeds its policy threshold.

## 14. Validation workflow

1. Confirm expected recovery model.
2. Run a conventional full backup.
3. Run differential and transaction-log backups according to schedule.
4. Synchronize eligible files to S3.
5. Validate transfer evidence.
6. Retrieve a protected recovery chain.
7. Run `RESTORE HEADERONLY` and `RESTORE VERIFYONLY`.
8. Perform an isolated actual restore.
9. Run full `DBCC CHECKDB`.
10. Record RPO/RTO and evidence.

## 15. Troubleshooting

### Cannot open backup device

Verify the directory exists and the SQL Server service identity has access. Mapped drives are session-specific; prefer a validated local or UNC path.

### Log backup fails after switching to FULL

Take a conventional non-copy-only full backup to establish the baseline, then begin scheduled log backups.

### Differential script reports no full backup

Run the scheduled full example with `CopyOnly="0"`. A copy-only full does not establish the differential base.

### Backup reports checksum error

Do not use `CONTINUE_AFTER_ERROR` as routine policy. Preserve evidence, investigate storage/database integrity, and run appropriate consistency checks.

### Compression affects workload

Benchmark CPU and I/O, move the schedule, or use approved workload controls. Do not silently remove compression without evaluating cloud-transfer and storage impact.

## 16. Assumptions

- SQL Server supports backup compression.
- SQLCMD mode is available.
- Backup directories are pre-created.
- Execution identities are least-privileged.
- S3 and local cleanup are separate workflows.
- TDE certificates/keys are protected independently.
- Retention values are approved from RPO, RTO, ransomware, legal, and cost requirements.

## 17. Microsoft references

- [Recovery models](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/recovery-models-sql-server)
- [Backup overview](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/backup-overview-sql-server)
- [Backup compression](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/backup-compression-sql-server)
- [Backup checksums](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/enable-or-disable-backup-checksums-during-backup-or-restore-sql-server)
- [Copy-only backups](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/copy-only-backups-sql-server)
- [Apply transaction-log backups](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/apply-transaction-log-backups-sql-server)

## 18. Next step

Proceed to [04 - Upload to S3](04-upload-to-s3.md) after local backup generation succeeds.