/* ===================================================================
   SQL Server Database Growth Script
   Description:
      Grows a database data file for backup and performance testing by 
      inserting synthetic data into a dedicated table.

   Features:
      - Targets specific sizes (e.g., 5GB, 10GB, 20GB).
      - Inserts synthetic data in batches to avoid log bloat.
      - Displays progress in the Messages window.
      - Stops automatically when the target size is reached.

   Usage:
      Ideal for POCs, Lab environments, and testing Backup/Restore 
      performance with varied database sizes.
=================================================================== */

-- Replace <YourDatabaseName> with the actual database name
USE [<YourDatabaseName>];
SET NOCOUNT ON;

------------------------------------------------------------
-- CONFIGURATION
------------------------------------------------------------
DECLARE @TargetGB INT = 5;       -- Set target size: 5, 10, 20, etc.
DECLARE @BatchSize INT = 1000;   -- Rows per batch
DECLARE @TargetMB BIGINT = @TargetGB * 1024;

------------------------------------------------------------
-- INITIALIZATION
------------------------------------------------------------
IF OBJECT_ID('dbo.BackupGrowthData','U') IS NULL
BEGIN
    CREATE TABLE dbo.BackupGrowthData
    (
        ID BIGINT IDENTITY(1,1) PRIMARY KEY,
        Col1 VARCHAR(1000) NOT NULL,
        Col2 VARCHAR(1000) NOT NULL,
        Col3 VARCHAR(1000) NOT NULL,
        CreatedDate DATETIME DEFAULT GETDATE()
    );

    PRINT 'Created staging table: dbo.BackupGrowthData';
END
ELSE
BEGIN
    PRINT 'Staging table dbo.BackupGrowthData already exists';
END;

------------------------------------------------------------
-- DATA INSERTION LOOP
------------------------------------------------------------
DECLARE @CurrentMB BIGINT;
DECLARE @Percent DECIMAL(10,2);
DECLARE @Rows BIGINT = 0;

WHILE 1 = 1
BEGIN

    -- Calculate current size of data files (ROWS) in MB
    SELECT @CurrentMB =
        SUM(size) * 8 / 1024
    FROM sys.database_files
    WHERE type_desc = 'ROWS';

    -- Exit loop if target size is reached
    IF @CurrentMB >= @TargetMB
        BREAK;

    -- Insert batch of synthetic data
    ;WITH N AS
    (
        SELECT TOP (1000) 1 AS X
        FROM sys.objects a
        CROSS JOIN sys.objects b
    )
    INSERT INTO dbo.BackupGrowthData (Col1,Col2,Col3)
    SELECT
        LEFT(CONVERT(VARCHAR(36),NEWID()) + REPLICATE('A',1000),1000),
        LEFT(CONVERT(VARCHAR(36),NEWID()) + REPLICATE('B',1000),1000),
        LEFT(CONVERT(VARCHAR(36),NEWID()) + REPLICATE('C',1000),1000)
    FROM N;

    SET @Rows += @BatchSize;

    -- Calculate and print progress
    SET @Percent =
        CAST(@CurrentMB * 100.0 / @TargetMB AS DECIMAL(10,2));

    PRINT CONCAT(
        'Current Size: ', @CurrentMB, ' MB / ',
        'Target: ', @TargetMB, ' MB (',
        @Percent, '%) | Rows Inserted: ', @Rows
    );

END;

PRINT '================================';
PRINT CONCAT('SUCCESS: Reached Target Size of ', @TargetGB, ' GB');
PRINT '================================';

-- Display final space usage
EXEC sp_spaceused;
