# 01 - Environment Preparation

This document outlines the initial setup required to build the CVT BackupBridge lab environment. The goal of this phase is to simulate an on-premises SQL Server workload and prepare AWS cloud storage for offsite backup protection.

---

## Objective

Prepare the following components:

* SQL Server host environment
* Test databases
* Dedicated local backup storage
* AWS S3 bucket
* IAM access for automation scripts

---

## Solution Components

### Simulated On-Premises SQL Server

The on-premises production server was simulated using an Azure Virtual Machine.

**Platform Used:**

* Microsoft Azure Virtual Machine
* Windows Server 2019
* SQL Server 2019 Developer Edition

This environment represents a typical company server hosting SQL Server workloads on-premises.

---

## Step 1 - Build Azure SQL Server VM

Provision a Windows Server virtual machine in Azure.

### Recommended Baseline Configuration

* Windows Server 2019
* Minimum 2 vCPU
* Minimum 8 GB RAM
* Premium SSD preferred
* Public access restricted as needed
* RDP enabled for administration

### Install SQL Server

Install:

* SQL Server 2019 Developer Edition
* SQL Server Management Studio (SSMS)

Verify SQL connectivity after installation.

---

## Step 2 - Create Dedicated Backup Storage

Create a separate volume or drive dedicated for SQL backup files.

### Example

```text
E:\SQLBackups
```

### Why This Matters

* Separates backups from OS drive
* Easier management
* Better storage planning
* Cleaner automation paths

---

## Step 3 - Create Test Databases

Create sample databases to validate backup and restore operations.

### Databases Used

* AdventureWorks
  n- LargeDB

### LargeDB Purpose

LargeDB was created to simulate larger enterprise backup files by inserting dummy records and increasing data size.

This helps test:

* backup duration
* transfer performance
* restore timing

---

## Step 4 - Prepare AWS S3 Bucket

Create an Amazon S3 bucket to serve as offsite backup storage.

### Example Naming Convention

```text
cvt-backupbridge-backups
```

### Recommendations

* Enable versioning if required
* Block public access
* Use private bucket policy
* Choose region nearest workload if practical

---

## Step 5 - Create IAM User for Script Access

Create an IAM user with scoped permissions for the backup automation scripts.

### Minimum Permissions

* List bucket
* Upload objects
* Download objects
* Delete objects (optional if retention cleanup is automated)

### Security Best Practices

* Use least privilege access
* Rotate access keys regularly
* Store credentials securely
* Do not hardcode secrets in public repositories

---

## Validation Checklist

Before moving to the next phase, confirm:

* Azure VM is accessible
* SQL Server instance is running
* Test databases exist
* Backup drive is available
* S3 bucket is created
* IAM credentials are working

---

## Output of This Phase

At the end of this phase, you should have a working SQL Server environment ready to generate backups and a secure AWS S3 bucket ready to receive backup files.

---

## Next Step

Proceed to:

[02 - Backup Generation](02-backup-generation.md)
