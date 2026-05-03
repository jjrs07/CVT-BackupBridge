# 01 - Environment Preparation

This document outlines the initial setup required to build the **CVT BackupBridge** lab environment. The goal is to simulate an on-premises SQL Server workload and prepare AWS cloud storage for offsite backup protection.

---

## Table of Contents
1. [Objective](#objective)
2. [Solution Components](#solution-components)
3. [Step 1 - Build Azure SQL Server VM](#step-1---build-azure-sql-server-vm)
4. [Step 2 - Create Dedicated Backup Storage](#step-2---create-dedicated-backup-storage)
5. [Step 3 - Create Test Databases](#step-3---create-test-databases)
6. [Step 4 - Prepare AWS S3 Bucket](#step-4---prepare-aws-s3-bucket)
7. [Step 5 - Create IAM User for Script Access](#step-5---create-iam-user-for-script-access)
8. [Validation Checklist](#validation-checklist)

---

## Objective

Prepare the following components:
*   SQL Server host environment
*   Test databases (including scaling simulation)
*   Dedicated local backup storage
*   AWS S3 bucket
*   IAM access for automation scripts

---

## Solution Components

### Simulated On-Premises SQL Server
The "on-premises" environment is hosted on an Azure Virtual Machine to simulate a remote corporate data center.

**Platform Details:**
*   **Provider:** Microsoft Azure
*   **OS:** Windows Server 2019
*   **Database:** SQL Server 2019 Developer Edition

> [!NOTE]
> While this lab uses Azure, you can also simulate the "on-premises" environment using a local virtual machine (Oracle VirtualBox, VMware), a local workstation, or even a dedicated physical server. The BackupBridge logic remains identical regardless of the underlying hardware.

---

## Step 1 - Build Azure SQL Server VM

Provision a Windows Server virtual machine in Azure.

> [!TIP]
> Use the **"SQL Server 2019 on Windows Server 2019"** image from the Azure Marketplace to save time. It comes with SQL Server and SSMS pre-installed.

### Recommended Baseline Configuration
*   **Compute:** Minimum 2 vCPU / 8 GB RAM
*   **Storage:** Premium SSD (for consistent IOPS)
*   **Security:** RDP enabled (restricted to your client IP)

### Post-Installation Tasks
1.  Install **SQL Server Management Studio (SSMS)** if not using a pre-configured image.
2.  Verify local connectivity to the SQL instance.
3.  **Update:** Run Windows Update and install the latest SQL Server Cumulative Updates (CU).

---

## Step 2 - Create Dedicated Backup Storage

Create a separate volume or drive dedicated exclusively for SQL backup files.

### Configuration
*   **Drive Letter:** `E:\` (Example)
*   **Path:** `E:\SQLBackups`

> [!IMPORTANT]
> In Azure, you must attach a **Data Disk** to the VM. Once attached, use `diskmgmt.msc` (Disk Management) to initialize the disk, create a simple volume, and format it as NTFS.

### Why This Matters
*   **Separation of Concerns:** Keeps the OS drive clean and prevents it from filling up during large backup operations.
*   **Performance:** Spreads I/O load across multiple physical/virtual disks.
*   **Automation:** Provides a static, predictable path for PowerShell scripts.

---

## Step 3 - Create Test Databases

### A. Initial Database Setup
Create sample databases to validate backup and restore operations.
*   **Option 1:** Restore the [AdventureWorks](https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure) sample database.
*   **Option 2:** Create a new empty database (e.g., `LargeDB`).

### B. Simulating Enterprise Scale (LargeDB)
To benchmark upload/download speeds and bridge performance, we simulate a larger footprint.

1.  **Grow the Database:** Use the provided simulation scripts to insert records and increase file size.
    *   `Scripts/SQL/Increase_logsize_simulator.sql`
    *   `Scripts/SQL/AutoGrow_DBsize.sql`
2.  **Testing Goals:**
    *   Validate **Backup Duration**.
    *   Measure **S3 Transfer Performance**.
    *   Benchmark **Disaster Recovery (DR) Restore Timing**.

---

## Step 4 - Prepare AWS S3 Bucket

Create an Amazon S3 bucket to serve as the offsite "vault."

### Setup Guide
*   **Bucket Name:** e.g., `cvt-backupbridge-backups`
*   **Access:** Block all public access.
*   **Versioning:** Optional (useful for ransomware protection).

---

## Step 5 - Create IAM User for Script Access

Create a dedicated IAM user with "Programmatic Access" for the automation scripts.

### Security Configuration
1.  **Least Privilege:** Attach the policy template located at: `Scripts/cvt-s3-policy.json`.
2.  **Credentials:** Generate an `Access Key ID` and `Secret Access Key`.

> [!WARNING]
> **NEVER** commit your AWS Access Keys or Secrets to source control. Use environment variables or a secure local credential store.

---

## Validation Checklist

Before moving to the next phase, ensure:
- [ ] Azure VM is accessible via RDP.
- [ ] SQL Server instance is responsive.
- [ ] Test databases (`AdventureWorks`/`LargeDB`) are online.
- [ ] Dedicated `E:\SQLBackups` drive is formatted and ready.
- [ ] AWS S3 bucket is created and private.
- [ ] IAM User has been created with the correct policy applied.

---

## Output of This Phase

You now have a fully functional "On-Premises" SQL environment and a secure Cloud Storage target. You are ready to automate the bridge.

**Next Step:** [02 - Backup Generation](02-backup-generation.md)
