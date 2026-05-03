# S3 File Upload Documentation

**Document:** S3-Upload-Documentation
**Date:** 2025
**Author:** James Santos
**Bucket:** aucera-db-backups-10234

---

## 1. Overview

This document covers the process of uploading large SQL Server backup files from a Windows server to an AWS S3 bucket using the AWS CLI. It includes IAM user setup, performance tuning, and multi-file upload procedures.

---

## 2. IAM User & Permissions

### IAM User
**User:** `aucera-s3-user`
**Account:** `193977450329`

### IAM Policy
The user is scoped to a single bucket with minimum required permissions — upload files and list the specific bucket only. It cannot list all buckets in the account by design.

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:PutObjectAcl"
            ],
            "Resource": "arn:aws:s3:::aucera-db-backups-10234/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": "arn:aws:s3:::aucera-db-backups-10234"
        }
    ]
}
```

### What This User Can and Cannot Do
| Action | Allowed |
|---|---|
| Upload files to `aucera-db-backups-10234` | ✅ |
| List contents of `aucera-db-backups-10234` | ✅ |
| List all buckets in the account (`aws s3 ls`) | ❌ by design |
| Access any other bucket | ❌ by design |

> Running `aws s3 ls` without a bucket name will return `AccessDenied` — this is expected and intentional. Always specify the bucket: `aws s3 ls s3://aucera-db-backups-10234/`

---

## 3. Performance Tuning

Before uploading large files, run these two commands once to optimize upload speed. These settings are saved permanently in the AWS config and apply to all future uploads automatically.

```cmd
aws configure set default.s3.max_concurrent_requests 50
aws configure set default.s3.multipart_chunksize 128MB
```

| Setting | Default | Optimized |
|---|---|---|
| `max_concurrent_requests` | 10 | 50 |
| `multipart_chunksize` | 8MB | 128MB |

Verify settings are saved:
```cmd
aws configure list
```

### Multipart Upload
The AWS CLI automatically uses multipart upload for files above 8MB — no extra flags needed. For an 85GB file with 128MB chunk size:
- Total parts: ~664
- Each part: 128MB
- All parts upload in parallel using the concurrent requests setting

### Expected Performance
| Concurrent Requests | Approximate Speed |
|---|---|
| 10 (default) | ~8 Mbps |
| 50 (optimized) | ~400 Mbps |

---

## 4. Uploading a Single File

```cmd
aws s3 cp "F:\backups\Aurora9_0416.bak" s3://aucera-db-backups-10234/
```

The CLI will show a live progress bar with current speed and bytes transferred.

### Monitor Upload Progress
While the upload is running, check how many parts have been uploaded:

```cmd
aws s3api list-multipart-uploads --bucket aucera-db-backups-10234
```

Get the exact part count (replace `<upload-id>` with the UploadId from the command above):
```cmd
aws s3api list-parts --bucket aucera-db-backups-10234 ^
  --key "Aurora9_0416.bak" ^
  --upload-id "<upload-id>" ^
  --query "length(Parts)" --output text
```

Divide the result by the total expected parts (~664 for 85GB) to get percentage complete.

### Verify Upload Completed
```cmd
aws s3 ls s3://aucera-db-backups-10234/ --human-readable
```

> The file will only appear here once the multipart upload is fully complete and assembled.

---

## 5. Uploading Multiple Files Simultaneously

To upload multiple files from different drives at the same time, run this from a single CMD window. It will automatically open a separate CMD window for each file:

```cmd
start cmd /k "aws s3 cp "F:\backups\file1.bak" s3://aucera-db-backups-10234/"
start cmd /k "aws s3 cp "G:\backups\file2.bak" s3://aucera-db-backups-10234/"
start cmd /k "aws s3 cp "H:\backups\file3.bak" s3://aucera-db-backups-10234/"
```

This opens 3 separate CMD windows each showing its own progress bar.

### Window Behavior
| Flag | Behavior |
|---|---|
| `/k` | Keeps the window open after upload finishes so you can see the result |
| `/c` | Closes the window automatically when upload is done |

### Bandwidth Consideration
With 3 files uploading simultaneously, available bandwidth is split between them:

| Uploads Running | Bandwidth Per Upload |
|---|---|
| 1 file | ~400 Mbps |
| 2 files | ~200 Mbps each |
| 3 files | ~133 Mbps each |

All 3 will still finish in a similar total timeframe as uploading one at a time.

---

## 6. Important Notes

### RDP Session Warning
If you are connected to the server via RDP and the session disconnects, the CMD window running the upload will be killed and the upload will stop. To prevent this:

- Keep the RDP session active during the upload
- Disable idle timeout on the server:
```cmd
powercfg /change standby-timeout-ac 0
```
- Alternatively use Task Scheduler to run the upload as a detached background process:
```cmd
schtasks /create /tn "S3Upload" /tr "aws s3 cp \"F:\backups\file.bak\" s3://aucera-db-backups-10234/" /sc once /st 00:00 /ru SYSTEM /f
schtasks /run /tn "S3Upload"
```

### Incomplete Multipart Uploads
If an upload is interrupted, the incomplete parts remain in S3 and incur storage costs. Check for any stuck multipart uploads:
```cmd
aws s3api list-multipart-uploads --bucket aucera-db-backups-10234
```

To abort an incomplete multipart upload (replace `<upload-id>` and `<key>`):
```cmd
aws s3api abort-multipart-upload --bucket aucera-db-backups-10234 ^
  --key "<filename.bak>" ^
  --upload-id "<upload-id>"
```

---

## 7. Quick Reference

| Task | Command |
|---|---|
| Upload single file | `aws s3 cp "F:\backups\file.bak" s3://aucera-db-backups-10234/` |
| List bucket contents | `aws s3 ls s3://aucera-db-backups-10234/ --human-readable` |
| Check active multipart uploads | `aws s3api list-multipart-uploads --bucket aucera-db-backups-10234` |
| Check parts uploaded so far | `aws s3api list-parts --bucket aucera-db-backups-10234 --key "<file>" --upload-id "<id>" --query "length(Parts)" --output text` |
| Set concurrent requests | `aws configure set default.s3.max_concurrent_requests 50` |
| Set chunk size | `aws configure set default.s3.multipart_chunksize 128MB` |
| Verify AWS config | `aws configure list` |

---

## 8. Resource Inventory

| Resource | Value |
|---|---|
| AWS Account ID | 193977450329 |
| S3 Bucket | aucera-db-backups-10234 |
| IAM User | aucera-s3-user |
| Region | us-east-2 |
| Storage Class | STANDARD |
| Multipart Chunk Size | 128MB |
| Max Concurrent Requests | 50 |
