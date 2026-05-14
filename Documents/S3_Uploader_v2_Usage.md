# S3_Uploader_v2.ps1 Usage Guide

This guide explains how to use the improved **S3_Uploader_v2.ps1** script. This version maintains all the original functionality (multi-threading, path preservation, retries) while adding powerful new filtering options.

## 📋 Prerequisites
- **AWS CLI** must be installed and configured.
- **settings.json** must exist in the parent folder or the same folder as the script.
- **Permissions:** The user running the script must have read access to the backup folder and write access to the S3 bucket.

---

## 🚀 Basic Usage (Same as v1)
To upload **all** `.bak` and `.trn` files found in your configured backup root:
```powershell
.\S3_Uploader_v2.ps1
```

---

## ✨ New Selective Upload Features

### 1. Filter by Filename (`-IncludeFilter`)
You can now specify exactly which files to upload using wildcards (`*`). You can provide a single pattern or a list of patterns.

**Upload specific databases only:**
```powershell
.\S3_Uploader_v2.ps1 -IncludeFilter "*db1*", "*db2*"
```

**Upload specific backup versions:**
```powershell
.\S3_Uploader_v2.ps1 -IncludeFilter "*10103.bak"
```

### 2. Upload Latest Only (`-LatestOnly`)
If your folders contain many old backups and you only want to sync the most recent one to S3, use this switch. The script will look into every sub-folder and pick only the file with the newest "Last Modified" date.

```powershell
.\S3_Uploader_v2.ps1 -LatestOnly
```

### 3. Combining Filters
You can combine these features for precise control. For example, to upload only the **latest FULL backup** (ignoring logs):

```powershell
.\S3_Uploader_v2.ps1 -IncludeFilter "*.bak" -LatestOnly
```

---

## 📂 Path Preservation Logic
The script automatically preserves your local folder structure in S3. 

**Example:**
- **Local:** `C:\Backups\Production\DB01\Full\DB01_Full.bak`
- **S3:** `s3://your-bucket/Production/DB01/Full/DB01_Full.bak`

*Note: Transaction logs (`.trn`) are automatically redirected to a `/LOG` sub-folder in S3 for cleaner organization.*

---

## 📝 Logging
The script generates a dedicated log file:
- **Location:** Configured in `settings.json` (usually `S3Upload_v2.log`).
- **Details:** Includes start/stop times, file sizes, upload speed (Mbps), and detailed error messages if a retry occurs.

---

## 🛠️ Troubleshooting
- **No files found:** Ensure your `BackupRootPath` in `settings.json` is correct and that the files have `.bak` or `.trn` extensions.
- **Access Denied:** Verify your AWS credentials and S3 bucket permissions.
- **Configuration Error:** Ensure `settings.json` is valid JSON and contains all required fields (`S3Bucket`, `AWSRegion`, `MaxSimultaneousJobs`, `BackupRootPath`, `LogDirectory`).
