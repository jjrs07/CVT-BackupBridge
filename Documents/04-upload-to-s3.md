# 04 - Upload to S3

This document describes the synchronization process that bridges local SQL Server backups to AWS S3. This automation ensures that offsite protection is maintained without manual intervention.

---

## Table of Contents
1. [Objective](#objective)
2. [Script Overview (S3_Uploader.ps1)](#script-overview-s3_uploaderps1)
3. [Prerequisites](#prerequisites)
4. [Implementation Logic](#implementation-logic)
5. [Automation and Scheduling](#automation-and-scheduling)
6. [Next Step](#next-step)

---

## Objective

The objective of this phase is to:
*   Automate the transfer of local backup files to AWS S3.
*   Ensure secure handling of AWS credentials.
*   Implement verification and local cleanup to manage disk space.

---

## Script Overview (S3_Uploader.ps1)

The synchronization is powered by the `S3_Uploader.ps1` script located in the `Scripts/powershell/` directory.

### Key Features
*   **Recursive Uploads:** Monitors the `Full`, `Differential`, and `Logs` directories.
*   **Validation:** Confirms the file exists locally before attempting an upload.
*   **Error Handling:** Logs errors to the console (or a log file) if the transfer fails.
*   **Retention Enforcement:** Purges local files only after a successful upload confirmation.

---

## Prerequisites

Before running the synchronization script, ensure the following are configured on the Azure SQL VM:

1.  **AWS Tools for PowerShell:** Installed and updated.
2.  **IAM Credentials:** Access Key and Secret Key for the dedicated IAM user.
3.  **Connectivity:** Outbound HTTPS (Port 443) access to AWS S3 endpoints.

---

## Implementation Logic

The uploader follows a strict workflow to ensure data integrity:

1.  **Identity Check:** Authenticates with AWS using the scoped IAM user.
2.  **Staging Scan:** Scans `H:\SQLBackups` for new files matching the naming convention.
3.  **S3 Transfer:** Executes the `Write-S3Object` command to push files to the `cvt-backupbridge-backups` bucket.
4.  **Verification:** Checks the S3 bucket to confirm the object size matches the local file.
5.  **Local Cleanup:** Deletes the local backup file to free up staging space.

---

## Automation and Scheduling

To achieve a true "Bridge" experience, the uploader must run on a schedule.

### Option 1: Windows Task Scheduler
*   **Frequency:** Every 15-30 minutes.
*   **Trigger:** Repeat task indefinitely.
*   **Action:** `powershell.exe -ExecutionPolicy Bypass -File "C:\Path\To\Scripts\S3_Uploader.ps1"`

### Option 2: SQL Server Agent
*   **Type:** PowerShell Step.
*   **Frequency:** Scheduled to run immediately after the SQL Backup jobs complete.
*   **Benefit:** Centralized management within SQL Server Management Studio.

> [!WARNING]
> Ensure the service account running the scheduled task has "Modify" permissions on the `H:\SQLBackups` folder and access to the AWS credential store.

---

## Next Step

With backups safely in the cloud, the project can address recovery scenarios:

[05 - Recovery Download](05-recovery-download.md)
