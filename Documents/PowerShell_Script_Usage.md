# PowerShell Scripts Usage Guide

## Compatibility and common prerequisites

- Windows PowerShell 5.1 or later. PowerShell 7 is not the documented validation baseline.
- AWS CLI v2 in `PATH` for uploader/downloader.
- `Scripts/settings.json` copied from the template.
- Separate least-privilege Backup Writer and Recovery Reader identities.
- No credentials in scripts or settings.

AWS CLI v2 internally manages request concurrency, multipart transfers, and retries. The PowerShell scripts do not create parallel AWS processes and do not consume `MaxSimultaneousJobs` or other concurrency settings.

## S3_Uploader.ps1

```powershell
& '.\Scripts\powershell\S3_Uploader.ps1'
$ExitCode = $LASTEXITCODE
```

Behavior:

- syncs only `.bak` and `.trn` recursively;
- preserves relative hierarchy;
- does not accept selective/latest-only parameters;
- does not use `--delete` or delete objects;
- logs to `S3Upload.log`; and
- returns the AWS CLI exit code.

Exit 0 means the CLI transfer command succeeded. It is not proof that SQL can restore the backup.

## S3_Downloader.ps1

```powershell
& '.\Scripts\powershell\S3_Downloader.ps1'
$ExitCode = $LASTEXITCODE
```

Behavior:

- syncs the configured current S3 prefix to `RestoreRootPath`;
- creates the destination when necessary;
- preserves hierarchy;
- enables compatible stored S3 checksum validation;
- does not use `--delete`; and
- logs to `S3Download.log` and returns the CLI exit code.

The script does not select historical VersionIds, restore archived objects, or execute SQL restores.

## validation_script.ps1

```powershell
& '.\Scripts\powershell\validation_script.ps1'
$ExitCode = $LASTEXITCODE
```

Compares `.bak`/`.trn` relative paths and byte lengths using configured source/target paths.

- 0: matching path/size sets.
- 1: missing configuration/path or empty backup set.
- 2: mismatch.

This is completeness evidence, not a checksum and not suitable as the source-independent DR proof when the source is unavailable.

## Get-BackupChain.ps1

```powershell
& '.\Scripts\powershell\Get-BackupChain.ps1' `
  -BackupRoot 'H:\SQLRestore' `
  -SqlInstance '<RecoveryInstance>' `
  -DatabaseName '<Database>' `
  -RecoveryTarget '<ISO-8601 timestamp with offset>' `
  -OutputPath 'C:\Evidence\backup-chain.txt'
$ExitCode = $LASTEXITCODE
```

- 0: candidate chain established.
- 2: chain not established.
- Other terminating error: invalid input, connection, metadata, or filesystem failure.

The utility uses integrated SQL authentication and embeds no password. Review the report; it never restores a database.

## Configuration fields

| Field | Used by |
|---|---|
| `S3Bucket` | uploader and downloader; may include a prefix |
| `AWSRegion` | uploader and downloader |
| `BackupRootPath` | uploader and optional validator |
| `RestoreRootPath` | downloader and optional validator |
| `LogDirectory` | uploader and downloader |

## Monitoring and troubleshooting

```powershell
Get-Content 'C:\Logs\S3Upload.log' -Tail 50 -Wait
Get-Content 'C:\Logs\S3Download.log' -Tail 50 -Wait
```

Use the logged AWS CLI output and exit code. A successful `aws s3 ls` call does not prove a failed transfer succeeded. Do not use `--no-verify-ssl` or broaden IAM permissions as a troubleshooting shortcut.

For production, add centralized log collection, alerts, overlap prevention, timeouts, capacity monitoring, temporary credential delivery, and recurring DR tests.

