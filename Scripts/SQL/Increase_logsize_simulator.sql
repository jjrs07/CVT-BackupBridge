/* ===================================================================
   Transaction Log Growth Simulator
   Description:
      Simulates database activity by performing repeated updates to 
      generate transaction log growth for testing purposes.

   Usage:
      Use this script to test Transaction Log backup frequency, 
      log file growth monitoring, and S3 upload triggers for .trn files.
=================================================================== */

-- Replace <YourDatabaseName> with the actual database name
USE [<YourDatabaseName>];

DECLARE @i INT = 1;
DECLARE @TotalIterations INT = 100;

PRINT 'Starting Transaction Log Growth Simulation...';

WHILE @i <= @TotalIterations
BEGIN
    -- Update batches to generate transaction log entries
    UPDATE TOP (50000) dbo.BackupGrowthData
    SET Col3 = CONVERT(VARCHAR(36), NEWID());

    PRINT CONCAT('Iteration ', @i, ' of ', @TotalIterations, ' completed.');

    -- Pause to allow monitoring/backup processes to run
    WAITFOR DELAY '00:00:02';

    SET @i += 1;
END

PRINT 'Simulation Complete.';
