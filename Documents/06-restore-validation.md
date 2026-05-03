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

### Validation Logic
*   **Path Mapping:** Compares relative paths in both directories.
*   **Size Matching:** Ensures the byte-count matches exactly between the original and the downloaded copy.
*   **Completeness:** Identifies any missing Log files in the sequence.

```powershell
.\validation_script.ps1 -Source "E:\SQLBackups" -Target "H:\SQLRestore"
```

---

## Phase 2: SQL Server Restoration

SQL Server requires a specific sequence of operations to restore a database to its most recent state.

### 1. Restore the Full Backup (NORECOVERY)
The `NORECOVERY` option keeps the database in a "Restoring" state, allowing additional backups to be applied.
```sql
RESTORE DATABASE [AdventureWorks]
FROM DISK = 'H:\SQLRestore\Full\AdventureWorks_Full_20260503_220000.bak'
WITH MOVE 'AdventureWorks' TO 'F:\Data\AdventureWorks.mdf',
     MOVE 'AdventureWorks_log' TO 'G:\Logs\AdventureWorks_log.ldf',
     NORECOVERY, REPLACE;
```

### 2. Restore the Differential Backup (NORECOVERY)
```sql
RESTORE DATABASE [AdventureWorks]
FROM DISK = 'H:\SQLRestore\Differential\AdventureWorks_Diff_20260504_100000.bak'
WITH NORECOVERY;
```

### 3. Restore Transaction Logs (RECOVERY)
Apply the log sequence. The final log restore uses the `RECOVERY` option to bring the database online.
```sql
RESTORE LOG [AdventureWorks]
FROM DISK = 'H:\SQLRestore\Logs\AdventureWorks_Log_20260504_101500.trn'
WITH RECOVERY;
```

---

## Phase 3: Database-Level Validation

Once the database is online, we must ensure it is free of corruption.

### 1. Physical Integrity Check
```sql
DBCC CHECKDB ('AdventureWorks') WITH NO_INFOMSGS, ALL_ERRORMSGS;
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
