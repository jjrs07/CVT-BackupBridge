Portfolio Project | SQL Server DBA | AWS S3 | PowerShell Automation | Hybrid Cloud Disaster Recovery

# CVT BackupBridge

Hybrid SQL Server backup and recovery solution that uploads on-premises SQL Server backups to AWS S3 for secure offsite disaster recovery storage.

---

## Table of Contents

- [Problem Statement](#problem-statement)
- [Solution Overview](#solution-overview)
- [Architecture](#architecture)
- [Usage Guide](#usage-guide)
- [Results](#results)
- [Key Benefits for Companies](#key-benefits-for-companies)
- [Strategic Value for IT Leaders](#strategic-value-for-it-leaders)
- [Lessons Learned](#lessons-learned)
- [Lab Environment](#lab-environment)
- [Learning Path](#learning-path)
- [Strategic Implementation Drivers](#strategic-implementation-drivers)
- [Future Enhancements](#future-enhancements)
- [Author](#author)

---

## Problem Statement

Modern enterprises often face a critical vulnerability: **local data silos**. While on-premises SQL Server workloads are robust, relying exclusively on local storage (NAS, SMB, or tapes) for backups creates a single point of failure. In the event of a site-wide disaster or a sophisticated ransomware attack targeting the local network, both production data and its corresponding backups are compromised simultaneously, leading to catastrophic data loss and prolonged downtime.

This project demonstrates how organizations can maintain their existing on-premises environment while adding a reliable offsite backup layer using AWS S3, providing high durability (11 nines) for critical backup retention.

---

## Solution Overview

**CVT BackupBridge** serves as a low-friction hybrid cloud gateway. It allows organizations to retain the performance and control of on-premises SQL Server operations while offloading the "heavy lifting" of offsite durability to AWS S3. This solution bridges the gap between traditional database administration and modern cloud storage, providing an automated, scalable vault for critical database assets.

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
2.  **[Local Storage](Documents/02-local-backup-storage.md):** Organize the local staging area and naming conventions.
3.  **[Backup Generation](Documents/03-backup-generation.md):** Configure T-SQL jobs for Full, Diff, and Log backups.
4.  **[S3 Synchronization](Documents/04-upload-to-s3.md):** Configure and schedule the PowerShell uploader.
5.  **[Recovery Retrieval](Documents/05-recovery-download.md):** Use the multi-threaded downloader for DR events.
6.  **[Restore & Validation](Documents/06-restore-validation.md):** Execute the T-SQL restore sequence and verify integrity.

---

## Results

* ✅ Backup files uploaded successfully to AWS S3
* ✅ Download from S3 completed successfully
* ✅ Restore test completed successfully
* ✅ Upload and download performance met lab expectations
* ✅ On-premises to cloud backup model validated

---

## Key Benefits for Companies

*   **Ransomware Resilience (Air-Gapping):** Provides a logical air-gap by moving backups off-premises. Leveraging AWS S3 features like Versioning and Object Lock protects data from local encryption or accidental deletion.
*   **Compliance & Audit Readiness:** Supports "3-2-1" backup strategies (3 copies, 2 media types, 1 offsite) to meet regulatory requirements (SOC2, HIPAA, GDPR) for offsite data redundancy.
*   **Cost Optimization (CapEx to OpEx):** Replaces expensive upfront investments in offsite NAS hardware or tape libraries with a predictable, pay-as-you-go cloud storage model.
*   **Disaster Recovery (DR) Agility:** Drastically reduces Recovery Time Objectives (RTO). In a total site failure, backups are already staged in the cloud, ready for restoration to cloud-based compute.
*   **Zero-Impact Integration:** Modernizes the backup stack without disrupting existing DBA workflows or requiring expensive third-party backup software licenses.

---

## Strategic Value for IT Leaders

*   **Scalability on Demand:** Cloud storage grows automatically with your data footprint, eliminating "disk full" emergencies on local backup infrastructure.
*   **Operational Transparency:** Automated logging and verification provide verifiable proof of offsite protection for management reporting.
*   **Reduced Human Error:** Eliminates manual offsite tasks (like drive swapping or tape rotation) through reliable PowerShell automation.

---

## Lessons Learned

*   **Security as a Foundation:** Scoped IAM permissions aren't just a technical requirement; they are the primary defense against lateral movement. Externalizing configuration via `settings.json` (and ignoring it in Git) further protects environment-specific metadata.
*   **Standards-Driven Automation:** Predictable naming and directory structures are the 'glue' that allows simple automation to handle enterprise-scale data volumes with zero manual touch.
*   **Validation is the True Product:** A backup is merely a liability until it is validated. Automated restoration testing is the only way to transform 'hope' into a guaranteed Business Continuity plan.

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

## Learning Path

**Want to learn how I built the cloud foundation for this project?**
Check out my **[CVT Cloud Labs](https://github.com/jjrs07/cvt-cloud-labs)** for hands-on tutorials on AWS, Linux, and Automation.

---

## Strategic Implementation Drivers

Actual backup upload and recovery performance will vary depending on the environment. Key factors include:

### Network Speed / Bandwidth
Available internet throughput significantly affects upload and download times between on-premises environments and AWS S3.

### Backup File Size
Larger databases require more time to back up, transfer, and restore.

### Backup Type
*   Full backups are largest and slowest to transfer.
*   Differential backups are smaller and faster.
*   Transaction log backups are typically quickest.

### Latency / Geographic Distance
Physical distance between the server location and AWS Region may impact transfer speed.

### Multipart Upload Tuning
For slower or unstable connections, AWS S3 multipart upload settings may require optimization to improve reliability and resume interrupted transfers.

### Disk Performance
Local storage read/write speed can affect both backup generation time and restore performance.

### Compression
Using SQL backup compression can reduce file size and transfer time.

### Scheduling Windows
Large backups should ideally run during off-peak business hours to reduce bandwidth contention.

### Security Controls
Firewalls, proxies, endpoint protection, or deep packet inspection may affect throughput or connectivity.

Production implementations should be benchmarked and tuned according to actual database size, network throughput, and recovery objectives.

---

## Future Enhancements

* Email alerting and Slack/Discord notifications.
* Encryption at rest (KMS) and in transit.
* Multi-region S3 replication for cross-region DR.
* Terraform/Bicep for Infrastructure as Code (IaC) deployment.
* Support for open-source engines (MySQL, PostgreSQL).
* Lifecycle policies for automatic S3 transition to Glacier.

---

## Feedback & Contributions

This project is a continuous work in progress. If you spot any **typos**, notice **discrepancies in screenshots**, or have **suggestions** for improvement, I would love to hear from you! Your feedback helps make this resource better for everyone.

Please feel free to reach out or open an issue:
*   **Issues:** [Open a GitHub Issue](https://github.com/jjrs07/CVT-BackupBridge/issues)
*   **Contact:** [James Santos](https://github.com/jjrs07)

---

## Author

**James Santos**
Cloud Virtuoso Tech (CVT)

*Tech solutions played in harmony.*
