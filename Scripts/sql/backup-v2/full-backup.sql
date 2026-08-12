/*
    CVT BackupBridge v2 - FULL backup example

    SQLCMD variables:
      DatabaseName  Database to back up.
      BackupRoot    Existing root directory visible to SQL Server.
      CopyOnly      0 for scheduled full; 1 for an ad-hoc copy-only full.

    Directory convention:
      <BackupRoot>\<Server>\<Database>\FULL

    This script does not create directories or change the recovery model.
*/

:On Error exit

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @DatabaseName sysname = N'$(DatabaseName)';
DECLARE @BackupRoot nvarchar(2048) = N'$(BackupRoot)';

DECLARE @CopyOnlyText nvarchar(10) = UPPER(LTRIM(RTRIM(N'$(CopyOnly)')));
DECLARE @UseCopyOnly bit =
    CASE @CopyOnlyText
        WHEN N'1' THEN 1
        WHEN N'TRUE' THEN 1
        WHEN N'YES' THEN 1
        WHEN N'0' THEN 0
        WHEN N'FALSE' THEN 0
        WHEN N'NO' THEN 0
        ELSE NULL
    END;

IF @UseCopyOnly IS NULL
BEGIN
    THROW 51002, 'CopyOnly must be 0/1, true/false, or yes/no.', 1;
END;

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
    @BackupRoot + N'\' + @ServerComponent + N'\' + @DatabaseComponent + N'\FULL';
DECLARE @FileName nvarchar(512) =
    @ServerComponent + N'_' + @DatabaseComponent + N'_FULL_'
    + @Timestamp + N'Z_' + @UniqueSuffix + N'.bak';
DECLARE @BackupFile nvarchar(2600) = @Directory + N'\' + @FileName;
DECLARE @BackupName nvarchar(128) =
    @DatabaseName + N' FULL backup'
    + CASE WHEN @UseCopyOnly = 1 THEN N' (COPY_ONLY)' ELSE N'' END;
DECLARE @Description nvarchar(255) =
    N'CVT BackupBridge v2 FULL backup; UTC='
    + CONVERT(nvarchar(33), @UtcNow, 126) + N'Z';
DECLARE @Sql nvarchar(max);

PRINT N'BackupType: FULL';
PRINT N'Database: ' + QUOTENAME(@DatabaseName);
PRINT N'RecoveryModel: ' + @RecoveryModel;
PRINT N'Destination: ' + @BackupFile;
PRINT N'CopyOnly: ' + CONVERT(nvarchar(1), @UseCopyOnly);
PRINT N'Checksum: ENABLED';
PRINT N'Compression: ENABLED';

BEGIN TRY
    SET @Sql =
        N'BACKUP DATABASE ' + QUOTENAME(@DatabaseName)
        + N' TO DISK = N''' + REPLACE(@BackupFile, N'''', N'''''') + N''''
        + N' WITH INIT, COMPRESSION, CHECKSUM'
         + CASE WHEN @UseCopyOnly = 1 THEN N', COPY_ONLY' ELSE N'' END
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
