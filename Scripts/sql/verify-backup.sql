/*
    CVT BackupBridge - SQL Server Backup Verification

    Purpose:
      1. Read backup-set metadata with RESTORE HEADERONLY.
      2. Verify backup readability and structural completeness with RESTORE VERIFYONLY.
      3. Validate backup and page checksums automatically when the backup contains them.

    IMPORTANT:
      - This script DOES NOT restore a database.
      - RESTORE VERIFYONLY does not prove full recoverability.
      - The strongest practical validation remains an actual restore to an isolated
        non-production SQL Server, followed by DBCC CHECKDB and application checks.

    SQLCMD variables:
      BackupFile         Absolute path visible to the SQL Server service account.
      BackupSetPosition  Backup-set FILE number on the media. Usually 1.
*/

:On Error exit

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @BackupFile nvarchar(4000) = N'$(BackupFile)';
DECLARE @BackupSetPosition int = TRY_CONVERT(int, N'$(BackupSetPosition)');
DECLARE @StartedAt datetime2(3) = SYSUTCDATETIME();
DECLARE @Command nvarchar(max);

IF @BackupFile IS NULL
   OR LEN(LTRIM(RTRIM(@BackupFile))) = 0
   OR @BackupFile = N'$(BackupFile)'
BEGIN
    THROW 50001, 'BackupFile SQLCMD variable is required.', 1;
END;

IF @BackupSetPosition IS NULL OR @BackupSetPosition < 1
BEGIN
    THROW 50002, 'BackupSetPosition must be a positive integer.', 1;
END;

PRINT N'============================================================';
PRINT N'CVT BackupBridge backup verification started';
PRINT N'StartTimeUtc: ' + CONVERT(nvarchar(33), @StartedAt, 126) + N'Z';
PRINT N'Server: ' + CONVERT(nvarchar(128), SERVERPROPERTY('ServerName'));
PRINT N'SQLVersion: ' + CONVERT(nvarchar(128), SERVERPROPERTY('ProductVersion'));
PRINT N'BackupFile: ' + @BackupFile;
PRINT N'BackupSetPosition: ' + CONVERT(nvarchar(12), @BackupSetPosition);
PRINT N'OperationType: VERIFY_ONLY_NO_DATABASE_RESTORE';
PRINT N'============================================================';

BEGIN TRY
    /*
        Preserve this native HEADERONLY result set as evidence. Review:
          Position, DatabaseName, BackupType, BackupStartDate, BackupFinishDate,
          FirstLSN, LastLSN, CheckpointLSN, DatabaseBackupLSN, RecoveryModel,
          HasBackupChecksums, IsDamaged, IsCopyOnly, source SQL version,
          MachineName, ServerName, and recovery-fork identifiers.

        HasBackupChecksums = 1 means VERIFYONLY can validate the backup and
        relevant page checksums recorded in the backup.
    */
    PRINT N'Stage: RESTORE HEADERONLY - capturing backup metadata';

    SET @Command =
        N'RESTORE HEADERONLY FROM DISK = N'''
        + REPLACE(@BackupFile, N'''', N'''''')
        + N''' WITH FILE = '
        + CONVERT(nvarchar(12), @BackupSetPosition)
        + N';';

    EXEC sys.sp_executesql @Command;

    PRINT N'StageResult: RESTORE HEADERONLY completed';
    PRINT N'ChecksumPolicy: verify checksums when present; inspect HasBackupChecksums in header output';

    /*
        Do not specify NO_CHECKSUM or CONTINUE_AFTER_ERROR.

        Default RESTORE behavior validates backup/page checksums when checksum
        metadata is present. If absent, VERIFYONLY performs its other readability
        and backup-completeness checks without checksum assurance.
    */
    PRINT N'Stage: RESTORE VERIFYONLY - verifying media readability and backup completeness';

    SET @Command =
        N'RESTORE VERIFYONLY FROM DISK = N'''
        + REPLACE(@BackupFile, N'''', N'''''')
        + N''' WITH FILE = '
        + CONVERT(nvarchar(12), @BackupSetPosition)
        + N';';

    EXEC sys.sp_executesql @Command;

    DECLARE @CompletedAt datetime2(3) = SYSUTCDATETIME();

    PRINT N'StageResult: RESTORE VERIFYONLY completed';
    PRINT N'FinalResult: FILE_VERIFICATION_SUCCEEDED';
    PRINT N'CompletedTimeUtc: ' + CONVERT(nvarchar(33), @CompletedAt, 126) + N'Z';
    PRINT N'DurationMilliseconds: '
        + CONVERT(nvarchar(30), DATEDIFF_BIG(millisecond, @StartedAt, @CompletedAt));
    PRINT N'Limitation: This result is not proof of full recoverability.';
    PRINT N'NextRequiredValidation: isolated restore, recovery, DBCC CHECKDB, and application tests.';
END TRY
BEGIN CATCH
    DECLARE @FailedAt datetime2(3) = SYSUTCDATETIME();

    PRINT N'FinalResult: FILE_VERIFICATION_FAILED';
    PRINT N'FailedTimeUtc: ' + CONVERT(nvarchar(33), @FailedAt, 126) + N'Z';
    PRINT N'DurationMilliseconds: '
        + CONVERT(nvarchar(30), DATEDIFF_BIG(millisecond, @StartedAt, @FailedAt));
    PRINT N'ErrorNumber: ' + CONVERT(nvarchar(12), ERROR_NUMBER());
    PRINT N'ErrorSeverity: ' + CONVERT(nvarchar(12), ERROR_SEVERITY());
    PRINT N'ErrorState: ' + CONVERT(nvarchar(12), ERROR_STATE());
    PRINT N'ErrorLine: ' + CONVERT(nvarchar(12), ERROR_LINE());
    PRINT N'ErrorMessage: ' + ERROR_MESSAGE();

    THROW;
END CATCH;
