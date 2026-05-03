/* ===================================================================
   AdventureWorks Auto Grow Script (Production-Ready Lab Version)
   Purpose:
      Grow database data file for backup testing:
      5 GB / 10 GB / 20 GB / custom size

   Safe Design:
      - Does NOT modify AdventureWorks existing tables
      - Creates dbo.BackupGrowthData only
      - Inserts synthetic data in batches
      - Shows progress
      - Stops when target reached

   Recommended Use:
      POC / Lab / Backup Upload Testing / Restore Testing
=================================================================== */

USE LargeDB;
SET NOCOUNT ON;

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------
DECLARE @TargetGB INT = 5;       -- change to 10 / 20
DECLARE @BatchSize INT = 1000;
DECLARE @TargetMB BIGINT = @TargetGB * 1024;

------------------------------------------------------------
-- CREATE TABLE
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

    PRINT 'Created dbo.BackupGrowthData';
END
ELSE
BEGIN
    PRINT 'dbo.BackupGrowthData already exists';
END;

------------------------------------------------------------
-- LOOP
------------------------------------------------------------
DECLARE @CurrentMB BIGINT;
DECLARE @Percent DECIMAL(10,2);
DECLARE @Rows BIGINT = 0;

WHILE 1 = 1
BEGIN

    SELECT @CurrentMB =
        SUM(size) * 8 / 1024
    FROM sys.database_files
    WHERE type_desc = 'ROWS';

    IF @CurrentMB >= @TargetMB
        BREAK;

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

    SET @Percent =
        CAST(@CurrentMB * 100.0 / @TargetMB AS DECIMAL(10,2));

    PRINT CONCAT(
        'Size: ', @CurrentMB, ' MB / ',
        @TargetMB, ' MB (',
        @Percent, '%) Rows: ',
        @Rows
    );

END;

PRINT '================================';
PRINT CONCAT('Reached Target: ', @TargetGB, ' GB');
PRINT '================================';

EXEC sp_spaceused;