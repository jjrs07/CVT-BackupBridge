# 06 - Restore Validation

This final phase of the CVT BackupBridge project details the restoration of backup files to a SQL Server instance and the validation procedures to ensure data integrity. A backup is only as good as its last successful restore.

---

## Table of Contents
1. [Objective](#objective)
2. [Phase 1: File-Level Validation](#phase-1-file-level-validation)
3. [Phase 2: SQL Server Restoration](#phase-2-sql-server-restoration)
4. [Phase 3: Database-Level Validation](#phase-3-database-level-validation)
5. [Success Criteria](#success-criteria)
6. [Project Conclusion](#project-conclusion)

---

## Objective

The objective of this phase is to:
*   Verify that the files downloaded from S3 match the source backups.
*   Restore the database to a point-in-time using the tiered backup files.
*   Validate the physical and logical integrity of the restored database.

---

## Phase 1: File-Level Validation

Before initiating a SQL restore, we use the `validation_script.ps1` (located in `Scripts/powershell/`) to compare the source (local) and target (restore) directories.

> [!NOTE]
> Although this validation was performed at the end of [05 - Recovery Download](05-recovery-download.md), it is a best practice to run it again here. This ensures that the staging area is still intact and that no files were accidentally moved or corrupted before the restore begins.

### Validation Logic
*   **Path Mapping:** Compares relative paths in both directories.
*   **Size Matching:** Ensures the byte-count matches exactly between the original and the downloaded copy.
*   **Completeness:** Identifies any missing Log files in the sequence.

```powershell
.\validation_script.ps1 -Source "H:\SQLBackups" -Target "H:\SQLRestore"
```

---

## Phase 2: SQL Server Restoration

In a production environment, disaster recovery (DR) tests are typically performed on a dedicated recovery server. For the purposes of this **Proof of Concept (POC)**, we simulate the restoration on the same server using one of the following two scenarios:

### POC Scenario A: Restore as a New Database (Side-by-Side)
This is the safest method for validation as it does not impact the original database. We restore the backup to a new name (e.g., `AdventureWorks_restore`) and move the physical files to unique paths.

### POC Scenario B: Overwrite the Existing Database
In a true DR event, you would likely delete or drop the corrupted database and recreate it from the S3 "vault."

> [!CAUTION]
> If using **Scenario B**, ensure you have a confirmed backup in S3 before dropping the local database.

---

### T-SQL Restoration Sequence

SQL Server requires a specific sequence of operations to restore a database to its most recent state. 

#### 1. Restore the Full Backup (NORECOVERY)
The `NORECOVERY` option keeps the database in a "Restoring" state, allowing additional backups to be applied.

```sql
-- Example for Scenario A (Restore as New)
USE [master];
RESTORE DATABASE [AdventureWorks_Restore]
FROM DISK = 'H:\SQLRestore\{ServerName}\{DatabaseName}\FULL\SQLServer_AdventureWorks_Full_YYYYMMDD_HHMM.bak'
WITH FILE = 1,
     MOVE 'AdventureWorks2019' TO 'F:\Data\AdventureWorks_Restore.mdf',
     MOVE 'AdventureWorks2019_log' TO 'G:\Logs\AdventureWorks_Restore_log.ldf',
     NORECOVERY, REPLACE, STATS = 5;
GO
```

#### 2. Restore the Differential Backup (NORECOVERY)
```sql
RESTORE DATABASE [AdventureWorks_Restore]
FROM DISK = 'H:\SQLRestore\{ServerName}\{DatabaseName}\DIFF\SQLServer_AdventureWorks_Diff_YYYYMMDD_HHMM.bak'
WITH NORECOVERY;
```

#### 3. Restore Transaction Logs (RECOVERY)
Apply the log sequence. The final log restore uses the `RECOVERY` option to bring the database online.
```sql
RESTORE LOG [AdventureWorks_Restore]
FROM DISK = 'H:\SQLRestore\{ServerName}\{DatabaseName}\LOG\SQLServer_AdventureWorks_Log_YYYYMMDD_HHMM.trn'
WITH RECOVERY;
```

---

## Phase 3: Database-Level Validation

Once the database is online, we must ensure it is free of corruption.

### 1. Physical Integrity Check
```sql
DBCC CHECKDB ('AdventureWorks_Restore') WITH NO_INFOMSGS, ALL_ERRORMSGS;
```

### 2. Logical Validation
*   **Row Count Comparison:** Compare row counts of key tables against the source system.
*   **Application Testing:** Connect a test instance of the application to verify functionality.

---

## Success Criteria

A restoration is considered successful only if:
- [ ] `validation_script.ps1` returns zero discrepancies.
- [ ] All T-SQL restore commands complete without error.
- [ ] `DBCC CHECKDB` reports 0 allocation errors and 0 consistency errors.
- [ ] The database is accessible and matches the expected point-in-time.

---

## Project Conclusion

The CVT BackupBridge successfully demonstrates a hybrid cloud backup architecture. By combining on-premises SQL Server workloads with AWS S3 offsite storage, we achieve:
*   **High Durability:** 99.999999999% durability via Amazon S3.
*   **Cost Efficiency:** Local staging with cloud-only long-term retention.
*   **Automated DR:** A repeatable, documented process for recovery in any AWS-connected environment.
