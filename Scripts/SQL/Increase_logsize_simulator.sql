USE LargeDB;

DECLARE @i INT = 1;

WHILE @i <= 100
BEGIN
    UPDATE TOP (50000) dbo.BackupGrowthData
    SET Col3 = CONVERT(VARCHAR(36), NEWID());

    WAITFOR DELAY '00:00:02';

    SET @i += 1;
END