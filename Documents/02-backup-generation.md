# 02 - Backup Generation

This document details the SQL Server backup strategy and implementation for the CVT BackupBridge project. The goal is to establish a reliable local backup routine that serves as the source for cloud synchronization.

---

## Table of Contents
1. [Objective](#objective)
2. [Recovery Model Configuration](#recovery-model-configuration)
3. [Backup Strategy Overview](#backup-strategy-overview)
4. [T-SQL Implementation](#t-sql-implementation)
5. [Local Retention Policy](#local-retention-policy)
6. [Next Step](#next-step)

---

## Objective

The objective of this phase is to:
*   Ensure databases are configured for point-in-time recovery.
*   Implement a multi-tier backup strategy (Full, Differential, and Log).
*   Standardize backup file naming and storage locations for automation.

---

## Recovery Model Configuration

To support transaction log backups and point-in-time recovery, databases must be set to the **FULL** recovery model.

### SQL Command
```sql
USE [master];
GO
ALTER DATABASE [AdventureWorks] SET RECOVERY FULL;
ALTER DATABASE [LargeDB] SET RECOVERY FULL;
GO
```

> [!NOTE]
> Databases in `SIMPLE` recovery model do not support transaction log backups. If your database is in `SIMPLE`, you will only be able to perform Full and Differential backups.

---

## Backup Strategy Overview

CVT BackupBridge utilizes a standard three-tier backup approach:

| Backup Type | Frequency | Purpose |
| :--- | :--- | :--- |
| **Full** | Weekly / Daily | Complete copy of the database. Base for all subsequent backups. |
| **Differential** | Daily / Every 4-12 hours | Captures changes since the last Full backup. Speeds up recovery. |
| **Log** | Every 15-60 minutes | Captures transaction log changes. Enables point-in-time recovery. |

---

## T-SQL Implementation

All backups are directed to the dedicated storage initialized in Phase 01: `E:\SQLBackups`.

### 1. Full Backup
```sql
BACKUP DATABASE [AdventureWorks]
TO DISK = 'E:\SQLBackups\AdventureWorks_Full.bak'
WITH FORMAT, MEDIANAME = 'SQLServerBackups', NAME = 'Full Backup of AdventureWorks', 
CHECKSUM, STATS = 10;
GO
```

### 2. Differential Backup
```sql
BACKUP DATABASE [AdventureWorks]
TO DISK = 'E:\SQLBackups\AdventureWorks_Diff.bak'
WITH DIFFERENTIAL, FORMAT, NAME = 'Diff Backup of AdventureWorks', 
CHECKSUM, STATS = 10;
GO
```

### 3. Transaction Log Backup
```sql
BACKUP LOG [AdventureWorks]
TO DISK = 'E:\SQLBackups\AdventureWorks_Log.trn'
WITH FORMAT, NAME = 'Log Backup of AdventureWorks', 
CHECKSUM, STATS = 10;
GO
```

---

## Local Retention Policy

To prevent the local `E:\SQLBackups` drive from reaching capacity, a retention policy is required.

*   **Policy:** Maintain 24-48 hours of local backups.
*   **Cleanup:** Older files are deleted locally after successful confirmation of the S3 upload.

---

## Next Step

Once local backups are generated successfully, proceed to:

[03 - Local Backup Storage](03-local-backup-storage.md)
