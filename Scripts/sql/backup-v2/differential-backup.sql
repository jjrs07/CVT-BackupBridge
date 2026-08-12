/*
    CVT BackupBridge v2 - DIFF backup example

    SQLCMD variables:
      DatabaseName  Database to back up.
      BackupRoot    Existing root directory visible to SQL Server.


    Directory convention:
      <BackupRoot>\<Server>\<Database>\DIFF

    This script does not create directories or change the recovery model.
*/

:On Error exit

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @DatabaseName sysname = N'$(DatabaseName)';
DECLARE @BackupRoot nvarchar(2048) = N'$(BackupRoot)';

IF @DatabaseName IS NULL
   OR LEN(LTRIM(RTRIM(@DatabaseName))) = 0
   OR @DatabaseName = N'$(DatabaseName)'
BEGIN
    THROW 51000, 'DatabaseName SQLCMD variable is required.', 1;
END;

IF @BackupRoot IS NULL
   OR LEN(LTRIM(RTRIM(@BackupRoot))) = 0
   OR @BackupRoot = N'$(BackupRoot)'
BEGIN
    THROW 51001, 'BackupRoot SQLCMD variable is required.', 1;
END;

IF DB_ID(@DatabaseName) IS NULL
BEGIN
    THROW 51003, 'The requested database does not exist.', 1;
END;

DECLARE @DatabaseState nvarchar(60);
DECLARE @RecoveryModel nvarchar(60);

SELECT
    @DatabaseState = state_desc,
    @RecoveryModel = recovery_model_desc
FROM sys.databases
WHERE name = @DatabaseName;

IF @DatabaseState <> N'ONLINE'
BEGIN
    THROW 51006, 'The requested database is not ONLINE.', 1;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM msdb.dbo.backupset
    WHERE database_name = @DatabaseName
      AND [type] = 'D'
      AND is_copy_only = 0
)
BEGIN
    THROW 51005, 'No conventional full backup was found in msdb. A differential requires a valid differential base.', 1;
END;

DECLARE @ServerComponent nvarchar(128) =
    COALESCE(CONVERT(nvarchar(128), SERVERPROPERTY('MachineName')), N'SQLSERVER');
DECLARE @DatabaseComponent nvarchar(128) = @DatabaseName;

-- Replace Windows-invalid filename characters in path components.
DECLARE @InvalidCharacters nvarchar(20) = N'<>:"/\|?*';
DECLARE @Position int = 1;
WHILE @Position <= LEN(@InvalidCharacters)
BEGIN
    SET @ServerComponent = REPLACE(@ServerComponent, SUBSTRING(@InvalidCharacters, @Position, 1), N'_');
    SET @DatabaseComponent = REPLACE(@DatabaseComponent, SUBSTRING(@InvalidCharacters, @Position, 1), N'_');
    SET @Position += 1;
END;

SET @BackupRoot = RTRIM(@BackupRoot);
WHILE RIGHT(@BackupRoot, 1) IN (N'\', N'/')
BEGIN
    SET @BackupRoot = LEFT(@BackupRoot, LEN(@BackupRoot) - 1);
END;

DECLARE @UtcNow datetime2(3) = SYSUTCDATETIME();
DECLARE @Timestamp char(18) =
    CONVERT(char(8), @UtcNow, 112)
    + '_'
    + REPLACE(CONVERT(char(12), @UtcNow, 114), ':', '');
DECLARE @UniqueSuffix char(8) = LEFT(REPLACE(CONVERT(char(36), NEWID()), '-', ''), 8);
DECLARE @Directory nvarchar(2048) =
    @BackupRoot + N'\' + @ServerComponent + N'\' + @DatabaseComponent + N'\DIFF';
DECLARE @FileName nvarchar(512) =
    @ServerComponent + N'_' + @DatabaseComponent + N'_DIFF_'
    + @Timestamp + N'Z_' + @UniqueSuffix + N'.bak';
DECLARE @BackupFile nvarchar(2600) = @Directory + N'\' + @FileName;
DECLARE @BackupName nvarchar(128) =
    @DatabaseName + N' DIFF backup'
    ;
DECLARE @Description nvarchar(255) =
    N'CVT BackupBridge v2 DIFF backup; UTC='
    + CONVERT(nvarchar(33), @UtcNow, 126) + N'Z';
DECLARE @Sql nvarchar(max);

PRINT N'BackupType: DIFF';
PRINT N'Database: ' + QUOTENAME(@DatabaseName);
PRINT N'RecoveryModel: ' + @RecoveryModel;
PRINT N'Destination: ' + @BackupFile;

PRINT N'Checksum: ENABLED';
PRINT N'Compression: ENABLED';

BEGIN TRY
    SET @Sql =
        N'BACKUP DATABASE ' + QUOTENAME(@DatabaseName)
        + N' TO DISK = N''' + REPLACE(@BackupFile, N'''', N'''''') + N''''
        + N' WITH INIT, COMPRESSION, CHECKSUM'
        , DIFFERENTIAL
        + N', NAME = N''' + REPLACE(@BackupName, N'''', N'''''') + N''''
        + N', DESCRIPTION = N''' + REPLACE(@Description, N'''', N'''''') + N''''
        + N', STATS = 10;';

    EXEC sys.sp_executesql @Sql;

    PRINT N'FinalResult: BACKUP_SUCCEEDED';
    PRINT N'BackupFile: ' + @BackupFile;
    PRINT N'CompletedTimeUtc: ' + CONVERT(nvarchar(33), SYSUTCDATETIME(), 126) + N'Z';
END TRY
BEGIN CATCH
    PRINT N'FinalResult: BACKUP_FAILED';
    PRINT N'BackupFile: ' + @BackupFile;
    PRINT N'ErrorNumber: ' + CONVERT(nvarchar(12), ERROR_NUMBER());
    PRINT N'ErrorMessage: ' + ERROR_MESSAGE();
    THROW;
END CATCH;
