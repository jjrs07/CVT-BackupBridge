# PowerShell Scripts Usage Guide

This guide covers the usage of the PowerShell scripts included in the CVT BackupBridge project for managing SQL Server backups with AWS S3.

---

## 📋 General Prerequisites
- **AWS CLI** must be installed and configured.
- **settings.json** must exist in the `Scripts/` folder (use `settings.json.template` as a base).
- **Permissions:** The user running the scripts must have appropriate IAM permissions for S3 actions (`s3:PutObject`, `s3:ListBucket`, `s3:GetObject`).

---

## 📤 S3_Uploader.ps1
This script recursively discovers SQL Server backup files (`.bak`, `.trn`) and uploads them to S3 while preserving the folder structure.

### Basic Usage
To upload **all** backups found in your configured `BackupRootPath`:
```powershell
.\S3_Uploader.ps1
```

### Selective Upload Features
- **Filter by Filename (`-IncludeFilter`):** Specify wildcards to target certain files.
  ```powershell
  .\S3_Uploader.ps1 -IncludeFilter "*db101*", "*db202*"
  ```
- **Latest Only (`-LatestOnly`):** Sync only the most recent backup file in each sub-directory.
  ```powershell
  .\S3_Uploader.ps1 -LatestOnly
  ```

### Key Logic
- **Path Preservation:** Local structure like `C:\Backups\DB01\Full\` becomes `s3://bucket/DB01/Full/`.
- **Log Redirection:** Transaction logs (`.trn`) are automatically moved to a `/LOG` folder in S3.

---

## 📥 S3_Downloader.ps1
This script discovers backup files in your AWS S3 bucket and downloads them to your local `RestoreRootPath`.

### Basic Usage
To download **everything** from the configured bucket:
```powershell
.\S3_Downloader.ps1
```

### Key Features
- **Automatic Directory Creation:** Recreates the S3 folder structure locally on your machine.
- **Verification:** Automatically checks if the downloaded file exists and has content before marking it as complete.
- **Multi-threaded:** Downloads multiple files simultaneously based on `MaxSimultaneousJobs` in `settings.json`.

---

## 📝 Common Features
- **Multi-threading:** Both scripts use the `MaxSimultaneousJobs` setting to run parallel AWS CLI processes.
- **Retry Logic:** Failed operations are automatically retried up to 3 times.
- **Logging:** Detailed logs are generated in the directory specified by `LogDirectory` in `settings.json`.
  - Uploader Log: `S3Upload.log`
  - Downloader Log: `S3Download.log`

---

## 🛠️ Troubleshooting
- **AWS CLI Errors:** Run `aws s3 ls` manually to verify your connection and permissions.
- **Path Issues:** Ensure `BackupRootPath` and `RestoreRootPath` in `settings.json` use double backslashes (e.g., `C:\\Backups\\`).
- **Log Files:** If a specific file fails, check the individual `.log` and `.log.err` files generated in the log directory for that specific filename.
