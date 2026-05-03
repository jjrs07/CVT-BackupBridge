# S3 Upload Queue Script - Documentation

**Script:** S3-Upload-Queue.ps1
**Date:** 2025
**Author:** James Santos

---

## 1. Overview

`S3-Upload-Queue.ps1` is a reusable PowerShell script that uploads files to an AWS S3 bucket with a controlled concurrency limit. It maintains a set number of simultaneous uploads at all times — as soon as one file finishes, the next one in the queue automatically starts.

It works with **any file type** — SQL backups, videos, documents, images, logs, zip files, etc.

### Key Features
- Maintains exactly N simultaneous uploads (default: 3)
- Auto-retry on failure — up to 3 attempts per file
- Logs all activity with timestamps, file size, duration, and average Mbps
- Works with individual files, mixed files, entire folders, and multiple folders
- Survives RDP disconnection when run via Task Scheduler
- Inherits AWS CLI config (multipart chunk size, concurrency settings)

---

## 2. Requirements

### AWS CLI
Must be installed and configured on the server with valid credentials:
```powershell
aws configure
```

### New Server Setup Checklist

> Run these steps once on every new server before using the script.

#### Step 1 — Install AWS CLI
Download and install from: https://aws.amazon.com/cli/

Verify installation:
```powershell
aws --version
```

#### Step 2 — Configure Credentials
```powershell
aws configure
```
Enter the following when prompted:

| Prompt | Value |
|---|---|
| AWS Access Key ID | `<aucera-s3-user access key>` |
| AWS Secret Access Key | `<aucera-s3-user secret key>` |
| Default region | `us-east-2` |
| Default output format | `json` |

#### Step 3 — Set Multipart Upload Performance Settings
These settings are stored locally on each server and must be configured once per server:
```powershell
aws configure set default.s3.max_concurrent_requests 50
aws configure set default.s3.multipart_chunksize 128MB
```

| Setting | Default | Optimized | Purpose |
|---|---|---|---|
| `max_concurrent_requests` | 10 | 50 | Number of parallel upload threads |
| `multipart_chunksize` | 8MB | 128MB | Size of each upload part |

> Without these settings the upload speed will be significantly slower (around 8Mbps vs 400Mbps).

#### Step 4 — Verify Everything is Configured
```powershell
aws configure list
```

#### Step 5 — Test Bucket Access
```powershell
aws s3 ls s3://aucera-db-backups-10234/ --human-readable
```
If this returns results or an empty list you're good to go. If you get `AccessDenied` check the IAM credentials.

### IAM Permissions
The AWS user must have at minimum:
```json
{
    "Effect": "Allow",
    "Action": ["s3:PutObject", "s3:PutObjectAcl"],
    "Resource": "arn:aws:s3:::<your-bucket>/*"
}
```

---

## 3. Configuration

Open the script and edit the top section only. Do not modify anything below the `SCRIPT - Do not modify below this line` comment.

### Settings
```powershell
$bucket  = "s3://aucera-db-backups-10234/"   # Destination S3 bucket
$maxJobs = 3                                  # Max simultaneous uploads
$logFile = "C:\s3_logs\s3-upload-log.txt"    # Log file path (auto-created)
```

| Setting | Description |
|---|---|
| `$bucket` | S3 destination — can be root of bucket or a subfolder |
| `$maxJobs` | Number of simultaneous uploads — recommended 3 to 5 |
| `$logFile` | Full path to log file — directory is created automatically |

---

## 4. How to Add Files

### Example 1 — Individual Files from Different Drives
```powershell
$files = @(
    "D:\backup\Aurora1_0416.bak",
    "E:\backup\Aurora2_0416.bak",
    "F:\backup\Aurora3_0416.bak"
)
```

### Example 2 — All Files in a Single Folder
```powershell
$files = @(
    (Get-ChildItem "C:\Movies\" -File | Select-Object -ExpandProperty FullName)
)
```

### Example 3 — All Files in a Folder Including Subfolders (Recursive)
```powershell
$files = @(
    (Get-ChildItem "C:\Movies\" -File -Recurse | Select-Object -ExpandProperty FullName)
)
```
> Note: Recursive mode flattens all files into the root of the S3 bucket — subfolder structure is not preserved. See Section 6 for preserving folder structure.

### Example 4 — All Files of a Specific Type in a Folder
```powershell
$files = @(
    # Only .bak files
    (Get-ChildItem "D:\backup\" -Filter "*.bak" -File | Select-Object -ExpandProperty FullName)
)
```

```powershell
$files = @(
    # Only .pdf files
    (Get-ChildItem "C:\Reports\" -Filter "*.pdf" -File | Select-Object -ExpandProperty FullName)
)
```

### Example 5 — Multiple Folders Combined
```powershell
$files = @(
    (Get-ChildItem "C:\Movies\" -File | Select-Object -ExpandProperty FullName)
    (Get-ChildItem "D:\Reports\" -File | Select-Object -ExpandProperty FullName)
    (Get-ChildItem "E:\Logs\" -File | Select-Object -ExpandProperty FullName)
)
```

### Example 6 — Mix of Folders and Individual Files
```powershell
$files = @(
    # All files from a folder
    (Get-ChildItem "C:\Movies\" -File | Select-Object -ExpandProperty FullName)

    # Plus specific individual files
    "D:\backup\Aurora1_0416.bak"
    "E:\backup\Aurora2_0416.bak"
)
```

### Example 7 — Upload to a Subfolder in S3
Change the `$bucket` variable to include a folder path:
```powershell
$bucket = "s3://aucera-db-backups-10234/sql-backups/"
$bucket = "s3://aucera-db-backups-10234/reports/2025/"
$bucket = "s3://aucera-db-backups-10234/videos/"
```

### Example 8 — SQL Backups (Original Use Case)
```powershell
$bucket  = "s3://aucera-db-backups-10234/"
$maxJobs = 3

$files = @(
    "D:\backup\Aurora1_0416.bak",
    "D:\backup\Aurora2_0416.bak",
    "D:\backup\Aurora3_0416.bak",
    "E:\backup\Aurora4_0416.bak",
    "F:\backup\Aurora5_0416.bak"
)
```

---

## 5. How to Run

### Option A — Run Directly in PowerShell
```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\jsantos\Documents\S3-Upload-Queue.ps1"
```
> Warning: If your RDP session disconnects the script will stop. Use Option B for long running uploads.

### Option B — Run via Task Scheduler (Survives RDP Disconnect)
```powershell
# Create and immediately run the task as SYSTEM
schtasks /create /tn "S3UploadQueue" /tr "powershell.exe -ExecutionPolicy Bypass -File C:\Users\jsantos\Documents\S3-Upload-Queue.ps1" /sc once /st 00:00 /ru SYSTEM /f

schtasks /run /tn "S3UploadQueue"
```
Runs as SYSTEM — completely independent of your RDP session. Safe to disconnect.

### Option C — Run as Detached Background Process
```powershell
Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File C:\Users\jsantos\Documents\S3-Upload-Queue.ps1" -WindowStyle Hidden
```

---

## 6. Verify Files Before Running

Always verify all files exist before starting the upload to avoid failures mid-queue:
```powershell
$files | ForEach-Object {
    if (Test-Path $_) { Write-Host "OK: $_" -ForegroundColor Green }
    else              { Write-Host "MISSING: $_" -ForegroundColor Red }
}
```

---

## 7. Monitor Progress

### Watch the Log in Real Time
```powershell
Get-Content "C:\s3_logs\s3-upload-log.txt" -Tail 20 -Wait
```

### Check Last 20 Lines
```powershell
Get-Content "C:\s3_logs\s3-upload-log.txt" -Tail 20
```

### Check What's in S3
```powershell
aws s3 ls s3://aucera-db-backups-10234/ --human-readable
```

### Check for Stuck Multipart Uploads
```powershell
aws s3api list-multipart-uploads --bucket aucera-db-backups-10234
```

### Check Task Scheduler Status (if running via Task Scheduler)
```powershell
schtasks /query /tn "S3UploadQueue" /fo list
```

---

## 8. Understanding the Log Output

```
[2026-04-24 12:05:38] ===== S3 Upload Queue Started =====
[2026-04-24 12:05:38] Total files to upload: 12
[2026-04-24 12:05:38] Max simultaneous uploads: 3
[2026-04-24 12:05:38] Destination bucket: s3://aucera-db-backups-10234/
[2026-04-24 12:05:38] =========================================
[2026-04-24 12:05:38] STARTED  | Aurora1_0416.bak (81.43 GB) (PID: 10616) | Queue remaining: 11
[2026-04-24 12:05:38] STARTED  | Aurora2_0416.bak (81.36 GB) (PID: 8504)  | Queue remaining: 10
[2026-04-24 12:05:39] STARTED  | Aurora3_0416.bak (81.73 GB) (PID: 62556) | Queue remaining: 9
[2026-04-24 12:08:01] RETRYING | Aurora2_0416.bak | Attempt 1/3 | Error: SSL validation failed...
[2026-04-24 12:10:22] COMPLETE | Aurora1_0416.bak | Size: 81.43 GB | Duration: 4.7 mins | Avg Speed: 46.8 Mbps | Progress: 1/12
[2026-04-24 12:10:32] STARTED  | Aurora4_0416.bak (81.26 GB) (PID: 81848) | Queue remaining: 8
[2026-04-24 12:45:00] ===== Upload Queue Complete =====
[2026-04-24 12:45:00] Total: 12 | Completed: 11 | Failed: 1
```

| Log Entry | Meaning |
|---|---|
| `STARTED` | File upload has begun — shows file size, process ID, and queue count |
| `COMPLETE` | File uploaded successfully — shows size, duration, avg Mbps, and progress |
| `RETRYING` | Upload failed, automatically retrying — shows attempt number and error |
| `FAILED` | Upload failed after 3 retry attempts — needs manual intervention |

---

## 9. If an Upload Fails

### Check the Log for the Error
```powershell
Get-Content "C:\s3_logs\s3-upload-log.txt" | Select-String "FAILED"
```

### Clean Up Stuck Multipart Uploads
```powershell
# List stuck uploads
aws s3api list-multipart-uploads --bucket aucera-db-backups-10234

# Abort a stuck upload (replace <key> and <upload-id>)
aws s3api abort-multipart-upload --bucket aucera-db-backups-10234 `
  --key "<filename>" `
  --upload-id "<upload-id>"
```

### Rerun Only the Failed Files
Update the `$files` array with only the failed files and rerun the script.

---

## 10. Preserving Folder Structure (aws s3 sync)

If you want to upload an entire folder and **preserve the subfolder structure** in S3, use `aws s3 sync` instead of the queue script:

```powershell
# Sync entire folder to S3 preserving structure
aws s3 sync "C:\Movies\" s3://aucera-db-backups-10234/Movies/ --no-verify-ssl

# Sync only specific file types
aws s3 sync "C:\Reports\" s3://aucera-db-backups-10234/Reports/ --exclude "*" --include "*.pdf" --no-verify-ssl
```

Use the queue script when you need **controlled concurrency and detailed logging per file**. Use `aws s3 sync` when you just want to mirror a folder to S3.

---

## 11. Quick Reference

| Task | Command |
|---|---|
| Run script directly | `powershell -ExecutionPolicy Bypass -File "C:\Users\jsantos\Documents\S3-Upload-Queue.ps1"` |
| Run via Task Scheduler | `schtasks /create /tn "S3UploadQueue" /tr "powershell.exe -ExecutionPolicy Bypass -File C:\Users\jsantos\Documents\S3-Upload-Queue.ps1" /sc once /st 00:00 /ru SYSTEM /f` |
| Start scheduled task | `schtasks /run /tn "S3UploadQueue"` |
| Monitor log live | `Get-Content "C:\s3_logs\s3-upload-log.txt" -Tail 20 -Wait` |
| Check S3 contents | `aws s3 ls s3://aucera-db-backups-10234/ --human-readable` |
| Check stuck uploads | `aws s3api list-multipart-uploads --bucket aucera-db-backups-10234` |
| Verify files exist | `$files \| ForEach-Object { if (Test-Path $_) { Write-Host "OK: $_" } else { Write-Host "MISSING: $_" } }` |
| Set concurrency | `aws configure set default.s3.max_concurrent_requests 50` |
| Set chunk size | `aws configure set default.s3.multipart_chunksize 128MB` |
