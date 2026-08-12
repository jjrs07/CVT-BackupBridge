# 05 - Recovery Download

## Objective

Retrieve the configured S3 recovery prefix to `RestoreRootPath` on a separate recovery server, preserve hierarchy, and return the AWS CLI result. This script stages files only; it does not perform SQL restore operations.

## Implemented architecture

`S3_Downloader.ps1`:

1. Loads `Scripts/settings.json`.
2. Validates `S3Bucket`, `AWSRegion`, `RestoreRootPath`, and `LogDirectory`.
3. Creates the recovery directory when absent and confirms it is accessible.
4. Validates AWS CLI v2.
5. Executes one S3-to-local `aws s3 sync` with `--checksum-mode ENABLED` and without `--delete`.
6. Logs start, source, destination, Region, AWS output, exit code, duration, and final result.
7. Returns the AWS CLI exit code.

AWS CLI v2 owns concurrency, multipart behavior, and retry handling. The script has no custom multiprocess queue or retry loop.

## Preconditions

- A separate recovery Windows/SQL Server exists and has sufficient staging/restore capacity.
- Windows PowerShell 5.1+ and AWS CLI v2 are installed.
- Recovery Reader credentials are independent of Backup Writer credentials.
- The reader can list/get only the approved prefix and decrypt SSE-KMS objects when applicable.
- Required Glacier Flexible/Deep Archive objects have completed a temporary S3 restore.
- The correct current object versions are intended. Current `sync` does not select historical version IDs.

## Run and interpret

```powershell
& '.\Scripts\powershell\S3_Downloader.ps1'
$DownloaderExitCode = $LASTEXITCODE
```

- Exit 0: AWS CLI reported sync success.
- Nonzero: retrieval failed; preserve `S3Download.log` and investigate.

The downloader does not decide success from file existence or `Length > 0`.

## Checksum behavior

`--checksum-mode ENABLED` requests validation using compatible S3 checksum metadata. It is useful transfer evidence but has limits:

- older objects may lack compatible stored checksums;
- it does not choose an authoritative historical object version;
- it does not prove SQL backup-set readability, chain continuity, database consistency, or application usability.

Record exact object keys, sizes, VersionIds, storage classes, encryption, and checksum/manifest evidence before retrieval. Do not describe path/size comparison as corruption detection or cryptographic integrity proof.

## Optional path/size comparison

`validation_script.ps1` compares only `.bak` and `.trn` relative paths and exact lengths between `BackupRootPath` and `RestoreRootPath`:

```powershell
& '.\Scripts\powershell\validation_script.ps1'
$ValidationExitCode = $LASTEXITCODE
```

- 0: compared backup sets match in path and size.
- 1: configuration/path/empty-set error.
- 2: missing, extra, or size-mismatched backup file.

This is an optional diagnostic when both directories legitimately exist. It cannot prove source-independent DR because a real source-loss test makes the original path unavailable.

## LAB / POC versus production

### LAB / POC

- Manual retrieval from current object versions.
- Local staging created by the script.
- CLI checksum mode plus documented SQL verification.

### Production-hardened

- Version-aware manifest/inventory and approval of selected versions.
- Temporary Recovery Reader access, MFA/break-glass controls for humans, and KMS recovery testing.
- Capacity, archive-retrieval, download, and integrity monitoring.
- Separate recovery account/Region where required.
- Measured download time as part of end-to-end RTO.

## Next steps

1. Run [SQL backup verification](09-sql-backup-verification.md).
2. Generate the [candidate backup chain](10-get-backup-chain.md).
3. Follow the [end-to-end DR runbook](12-end-to-end-dr-validation-runbook.md).

