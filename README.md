Portfolio Project | SQL Server DBA | AWS S3 | PowerShell Automation | Hybrid Cloud Disaster Recovery

# CVT BackupBridge

Hybrid SQL Server backup and recovery solution that uploads on-premises SQL Server backups to AWS S3 for secure offsite disaster recovery storage.

---

## Table of Contents

- [Problem Statement](#problem-statement)
- [Solution Overview](#solution-overview)
- [Architecture](#architecture)
- [Lab Environment](#lab-environment)
- [BackupBridge Workflow](#backupbridge-workflow)
- [Results](#results)
- [Key Benefits for Companies](#key-benefits-for-companies)
- [Lessons Learned](#lessons-learned)
- [Operational Considerations](#operational-considerations)
- [Future Enhancements](#future-enhancements)
- [Author](#author)

---

## Problem Statement

Many companies still run critical SQL Server workloads on-premises and store database backups locally through file shares, SMB storage, NAS devices, tapes, or internal backup servers.

While this provides local backup capability, it also creates a major risk:

* Hardware failure
* Disk corruption
* Ransomware attacks
* Backup server compromise
* Site disasters
* Human error

If both production data and local backups are affected, recovery becomes difficult or impossible.

This project demonstrates how organizations can maintain their existing on-premises environment while adding a reliable offsite backup layer using AWS S3.

AWS S3 provides high durability (11 nines), making it a strong platform for backup retention.

---

## Solution Overview

This Proof of Concept simulates an on-premises SQL Server environment hosted on an Azure Virtual Machine and integrates backup storage with AWS S3.

The solution enables:

* **Tiered Backup Strategy:** Support for Full, Differential, and Transaction Log backups.
* **Cloud Synchronization:** Automated, multi-threaded upload to AWS S3.
* **Disaster Recovery:** High-speed retrieval from S3 during recovery events.
* **Integrity Validation:** Automated file-size and path comparison between source and recovery targets.
* **Scheduled Automation:** Integration with Windows Task Scheduler and SQL Server Agent for autonomous operation.

---

## Architecture

![Architecture](Documents/Images/Architecture.png)

The recovery workflow is modular and can be adapted to either staged file download or direct restore automation based on company requirements.

---

## Usage Guide

To get started with CVT BackupBridge, follow the phased documentation in the `Documents/` folder:

1.  **[Environment Preparation](Documents/01-environment-preparation.md):** Build the Azure VM and S3 Bucket.
2.  **[Backup Generation](Documents/02-backup-generation.md):** Configure T-SQL jobs for Full, Diff, and Log backups.
3.  **[Local Storage](Documents/03-local-backup-storage.md):** Organize the local staging area and naming conventions.
4.  **[S3 Synchronization](Documents/04-upload-to-s3.md):** Configure and schedule the PowerShell uploader.
5.  **[Recovery Retrieval](Documents/05-recovery-download.md):** Use the multi-threaded downloader for DR events.
6.  **[Restore & Validation](Documents/06-restore-validation.md):** Execute the T-SQL restore sequence and verify integrity.

---

## Lab Environment

### Infrastructure
*   **Provider:** Microsoft Azure
*   **OS:** Windows Server 2019
*   **Database:** SQL Server 2019 Developer Edition

### Cloud Services
*   **Storage:** AWS S3 (Standard Storage Class)
*   **Security:** AWS IAM (Least Privilege Scoped Access)

### Automation Stack
*   **Scripting:** PowerShell 5.1+
*   **CLI:** AWS CLI v2
*   **Scheduling:** SQL Server Agent / Windows Task Scheduler

---

## Future Enhancements

* Email alerting and Slack/Discord notifications.
* Encryption at rest (KMS) and in transit.
* Multi-region S3 replication for cross-region DR.
* Terraform/Bicep for Infrastructure as Code (IaC) deployment.
* Support for open-source engines (MySQL, PostgreSQL).
* Lifecycle policies for automatic S3 transition to Glacier.

---

## Author

**James Santos**
Cloud Virtuoso Tech (CVT)

*Tech solutions played in harmony.*
