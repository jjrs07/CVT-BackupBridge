# 04 - Upload to S3

This document describes the synchronization process that bridges local SQL Server backups to AWS S3. This automation ensures that offsite protection is maintained without manual intervention.

---

## Table of Contents
1. [Objective](#objective)
2. [Script Overview (S3_Uploader.ps1)](#script-overview-s3_uploaderps1)
3. [Prerequisites](#prerequisites)
4. [Script Installation](#script-installation)
5. [Implementation Logic](#implementation-logic)
6. [Automation and Scheduling](#automation-and-scheduling)
7. [Next Step](#next-step)

---

## Objective

The objective of this phase is to:
*   Automate the transfer of local backup files to AWS S3.
*   Ensure secure handling of AWS credentials.
*   Implement verification and local cleanup to manage disk space.

---

## Script Overview (S3_Uploader.ps1)

The synchronization is powered by the `S3_Uploader.ps1` script, a high-performance, multi-threaded automation engine designed to bridge on-premises backups to AWS S3.

### Key Technical Features
*   **Multi-Threaded Concurrent Uploads:** Utilizes a background job queue to process multiple files simultaneously (Max: 4 concurrent streams by default). This ensures maximum saturation of available network bandwidth.
*   **Intelligent Folder Mapping:** Automatically parses the local `H:\SQLBackups` hierarchy and recreates a matching `{ServerName}/{DatabaseName}/{Type}` prefix structure in the S3 bucket.
*   **Fault Tolerance (Automatic Retries):** Implements a robust retry mechanism. If a transfer fails due to transient network issues, the script re-queues the file (up to 3 times) before logging a permanent failure.
*   **Dual-Validation Success Logic:** Beyond checking process exit codes, the script performs a secondary `aws s3 ls` verification to confirm object existence in the cloud vault before marking a task as complete.
*   **Performance Telemetry:** Calculates and logs real-time transfer speeds (Mbps) and precise durations for every file, providing data-driven insights into "Bridge" performance.

---

## Prerequisites

Before running the synchronization script, ensure the following are configured on the Azure SQL VM:

1.  **AWS CLI v2:** Installed and configured with the `cvt-backup-service` credentials.
2.  **IAM Credentials:** Programmatic access keys generated in Phase 01.
3.  **Connectivity:** Outbound HTTPS (Port 443) access to AWS S3 endpoints.

---

## Script Installation

1.  **Download:** Download the `S3_Uploader.ps1` script from the `Scripts/powershell/` directory of this repository.
2.  **Placement:** Save the script to a dedicated automation folder on the SQL Server (e.g., `C:\Scripts\`).
3.  **Configuration:** Open the script in an editor and update the following variables:
    *   `$bucket`: Set to your actual S3 bucket (e.g., `s3://cvtech-sql-backups`).
    *   `$region`: Set to your AWS region (e.g., `ap-southeast-1`).
    *   `$backupRoot`: Set to your local backup drive (e.g., `H:\SQLBackups`).
    *   `$logFile`: Set to your desired log path (e.g., `C:\Logs\S3_Uploader.log`).

---

## Implementation Logic

The uploader follows a thorough workflow for secure cloud synchronization. It is recommended to perform a manual run before automating the task.

### Step-by-Step Workflow
1.  **Object Discovery:** Recursively scans `H:\SQLBackups` for `.bak` and `.trn` files.
2.  **Queue Initialization:** Builds a processing queue with file metadata and size calculations.
3.  **Parallel Execution:** Spawns `aws s3 cp` processes up to the defined concurrency limit.
4.  **Verification:** Validates upload integrity using process exit codes and S3 object listing.
5.  **Manual Execution (Test Run):** Open PowerShell as Administrator and execute the script to verify connectivity and logic:
    ```powershell
    Set-Location "C:\Scripts\"
    .\S3_Uploader.ps1
    ```

![S3 Uploader Running](Images/S3_Uploader_running.png)
*Figure 1: S3 Multi-Threaded Uploader in action, showing parallel transfers and real-time Mbps telemetry.*

6.  **Logging:** Records detailed telemetry to a central `.log` file for audit and troubleshooting.

---

## Automation and Scheduling

To achieve a true "Bridge" experience, the uploader should run on a schedule.

### Option 1: SQL Server Agent (Recommended)
*   **Type:** PowerShell Step.
*   **Frequency:** Scheduled to run immediately after the SQL Backup jobs complete.
*   **Benefit:** Centralized management within SSMS and integration with database alerts.

### Option 2: Windows Task Scheduler
*   **Frequency:** Every 15-30 minutes.
*   **Trigger:** Repeat task indefinitely.
*   **Action:** `powershell.exe -ExecutionPolicy Bypass -File "C:\Path\To\Scripts\S3_Uploader.ps1"`

> [!WARNING]
> Ensure the service account running the scheduled task has **Modify** permissions on the `H:\SQLBackups` folder and access to the AWS credential store.

---

## Output of This Phase

Your on-premises SQL Server backups are now automatically and securely replicated to the AWS cloud.

**Next Step:** [05 - Recovery Download](05-recovery-download.md)
