# 04 - Upload to S3

## Objective

Transfer only SQL Server `.bak` and `.trn` files from `BackupRootPath` to the configured S3 bucket/prefix while preserving relative hierarchy. PowerShell orchestrates one AWS CLI v2 sync and records its result.

## Implemented architecture

`S3_Uploader.ps1`:

1. Loads `Scripts/settings.json`.
2. Validates `S3Bucket`, `AWSRegion`, `BackupRootPath`, and `LogDirectory`.
3. Validates that the source exists.
4. Validates `aws` is AWS CLI v2.
5. Invokes `aws s3 sync` with exclude/include rules for `.bak` and `.trn`.
6. Logs start time, source, destination, Region, AWS output, exit code, duration, and final result.
7. Returns the AWS CLI exit code.

Equivalent transfer shape:

```text
aws s3 sync <source> <s3-destination>/
  --exclude * --include *.bak --include *.trn
  --region <region> --no-progress
```

The command intentionally omits `--delete`.

## What AWS CLI v2 manages

- recursive comparison and transfer selection;
- concurrent requests/internal thread pool;
- multipart thresholds and parts;
- normal request retry behavior; and
- transfer command exit status.

The script has no `Start-Process` queue, custom file retry loop, `aws s3 ls` fallback success, or DeleteObject workflow. Tune AWS CLI S3 configuration only after measuring the environment; the PowerShell settings file no longer exposes concurrency knobs.

## Prerequisites

- Windows PowerShell 5.1+.
- AWS CLI v2 in `PATH`.
- Source directory accessible to the execution identity; prefer a stable local or UNC path because mapped drives are session-specific.
- Backup Writer permissions from `Scripts/iam/backup-writer-policy.json`.
- Temporary role credentials in production where practical; never embed credentials in settings/scripts.
- Outbound HTTPS to the approved S3 endpoint.

## Configuration

```json
{
  "S3Bucket": "s3://<bucket>/<prefix>",
  "AWSRegion": "<region>",
  "BackupRootPath": "H:\\SQLBackups",
  "RestoreRootPath": "H:\\SQLRestore",
  "LogDirectory": "C:\\Logs"
}
```

## Run and interpret

```powershell
& '.\Scripts\powershell\S3_Uploader.ps1'
$UploaderExitCode = $LASTEXITCODE
```

- Exit 0: AWS CLI reported sync success.
- Nonzero: failed run; preserve `S3Upload.log` and AWS output.

Do not reinterpret a nonzero exit as success merely because a key appears in `aws s3 ls`.

## Transfer verification boundary

Exit 0 is necessary but does not prove SQL backup integrity or full cryptographic equality. Confirm cloud protection with exact key/size/version inventory and compatible stored checksum or protected manifest evidence. Do not use multipart ETag as a universal MD5.

SQL integrity requires `RESTORE HEADERONLY`, `RESTORE VERIFYONLY`, an actual restore, CHECKDB, and application/data validation as separate layers.

## Scheduling

### LAB / POC

Run manually first. Windows Task Scheduler or SQL Server Agent may invoke the script after backups complete. Capture the execution identity and exit code.

### Production-hardened

Use a managed service identity/temporary credentials, centralized logs/alerts, overlap prevention, timeout/capacity monitoring, and cloud inventory reconciliation. Scheduling the uploader automates transfer only; it does not automate DR.

## Retention

The uploader never deletes S3 objects and is not the cloud-retention engine. S3 Lifecycle manages approved cloud transitions/expiration. Local cleanup is a separate chain-aware process after cloud and SQL validation.

## Troubleshooting

| Symptom | Action |
|---|---|
| AWS CLI missing/v1 | Install AWS CLI v2 through the approved process |
| Source not found | Verify local/UNC path and scheduled-task identity |
| AccessDenied listing | Check writer prefix, bucket owner condition, bucket policy/SCP/endpoint policy |
| AccessDenied upload | Check PutObject and, if applicable, KMS key policy |
| Nonzero network result | Preserve logs and rerun after correction; rely on CLI retry behavior |
| Unexpected files absent | Only `.bak` and `.trn` are in scope by design |

Next: [05 - Recovery Download](05-recovery-download.md).

