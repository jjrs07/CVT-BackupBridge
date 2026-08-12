#requires -Version 5.1
<#
.SYNOPSIS
    Identifies a candidate SQL Server restore chain from backup metadata.

.DESCRIPTION
    Recursively reads RESTORE HEADERONLY metadata from .bak and .trn files,
    selects a compatible FULL/DIFFERENTIAL base, follows transaction-log LSNs,
    and produces a human-readable restore-order report.

    This utility never executes RESTORE DATABASE or RESTORE LOG.

.NOTES
    Uses Windows integrated authentication. No SQL password is accepted or stored.
    Run against a non-production metadata/verification SQL Server instance.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BackupRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SqlInstance,

    [Parameter()]
    [string]$DatabaseName,

    [Parameter()]
    [Nullable[datetime]]$RecoveryTarget,

    [Parameter()]
    [ValidateRange(1, 3600)]
    [int]$CommandTimeoutSeconds = 120,

    [Parameter()]
    [ValidateRange(1, 300)]
    [int]$ConnectionTimeoutSeconds = 15,

    [Parameter()]
    [switch]$EncryptConnection,

    [Parameter()]
    [switch]$TrustServerCertificate,

    [Parameter()]
    [string]$OutputPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-RowValue {
    param(
        [Parameter(Mandatory = $true)]
        [System.Data.DataRow]$Row,
        [Parameter(Mandatory = $true)]
        [string]$ColumnName
    )

    if (-not $Row.Table.Columns.Contains($ColumnName)) {
        return $null
    }

    $value = $Row[$ColumnName]
    if ($value -eq [DBNull]::Value) {
        return $null
    }

    return $value
}

function Convert-ToNullableDecimal {
    param([object]$Value)

    if ($null -eq $Value -or $Value -eq [DBNull]::Value) {
        return $null
    }

    try {
        return [decimal]$Value
    }
    catch {
        return $null
    }
}

function Convert-ToNullableDateTime {
    param([object]$Value)

    if ($null -eq $Value -or $Value -eq [DBNull]::Value) {
        return $null
    }

    try {
        return [datetime]$Value
    }
    catch {
        return $null
    }
}

function Format-Lsn {
    param([object]$Value)

    if ($null -eq $Value) {
        return '[null]'
    }

    return ([decimal]$Value).ToString('0', [Globalization.CultureInfo]::InvariantCulture)
}

function Escape-SqlLiteral {
    param([string]$Value)
    return $Value.Replace("'", "''")
}

function Get-BackupHeader {
    param(
        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]$Connection,
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    $escapedPath = Escape-SqlLiteral -Value $FilePath
    $command = $Connection.CreateCommand()
    $command.CommandTimeout = $TimeoutSeconds
    $command.CommandText = "RESTORE HEADERONLY FROM DISK = N'$escapedPath';"

    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
    $dataSet = New-Object System.Data.DataSet

    try {
        [void]$adapter.Fill($dataSet)
        if ($dataSet.Tables.Count -eq 0) {
            throw 'RESTORE HEADERONLY returned no result set.'
        }

        return $dataSet.Tables[0]
    }
    finally {
        $adapter.Dispose()
        $command.Dispose()
        $dataSet.Dispose()
    }
}

function Test-DifferentialCompatibility {
    param(
        [Parameter(Mandatory = $true)]$Full,
        [Parameter(Mandatory = $true)]$Differential
    )

    if ($Full.IsCopyOnly) {
        return $false
    }

    if ($null -eq $Full.CheckpointLSN) {
        return $false
    }

    if ($null -ne $Differential.DifferentialBaseLSN -and
        $Differential.DifferentialBaseLSN -eq $Full.CheckpointLSN) {
        return $true
    }

    if ($null -ne $Differential.DatabaseBackupLSN -and
        $Differential.DatabaseBackupLSN -eq $Full.CheckpointLSN) {
        return $true
    }

    return $false
}

function Add-ReportLine {
    param(
        [Parameter(Mandatory = $true)]
        [System.Text.StringBuilder]$Builder,
        [string]$Text = ''
    )
    [void]$Builder.AppendLine($Text)
}

if (-not (Test-Path -LiteralPath $BackupRoot -PathType Container)) {
    throw "BackupRoot does not exist or is not a directory: $BackupRoot"
}

$resolvedRoot = (Resolve-Path -LiteralPath $BackupRoot).ProviderPath
$files = @(
    Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -ErrorAction Stop |
        Where-Object { $_.Extension -in @('.bak', '.trn') } |
        Sort-Object FullName
)

if ($files.Count -eq 0) {
    throw "No .bak or .trn files were found under: $resolvedRoot"
}

$connectionBuilder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$connectionBuilder.DataSource = $SqlInstance
$connectionBuilder.InitialCatalog = 'master'
$connectionBuilder.IntegratedSecurity = $true
$connectionBuilder.ApplicationName = 'CVT BackupBridge Get-BackupChain'
$connectionBuilder.ConnectTimeout = $ConnectionTimeoutSeconds
$connectionBuilder.Encrypt = [bool]$EncryptConnection
$connectionBuilder.TrustServerCertificate = [bool]$TrustServerCertificate

$connection = New-Object System.Data.SqlClient.SqlConnection $connectionBuilder.ConnectionString
$metadata = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[string]
$unreadable = New-Object System.Collections.Generic.List[object]

try {
    $connection.Open()

    foreach ($file in $files) {
        try {
            $table = Get-BackupHeader -Connection $connection -FilePath $file.FullName -TimeoutSeconds $CommandTimeoutSeconds

            foreach ($row in $table.Rows) {
                $backupType = Get-RowValue -Row $row -ColumnName 'BackupType'
                $position = Get-RowValue -Row $row -ColumnName 'Position'
                $isCopyOnlyValue = Get-RowValue -Row $row -ColumnName 'IsCopyOnly'
                $isDamagedValue = Get-RowValue -Row $row -ColumnName 'IsDamaged'
                $hasChecksumsValue = Get-RowValue -Row $row -ColumnName 'HasBackupChecksums'

                $record = [pscustomobject]@{
                    FilePath             = $file.FullName
                    FileName             = $file.Name
                    Position             = if ($null -ne $position) { [int]$position } else { 1 }
                    DatabaseName         = [string](Get-RowValue -Row $row -ColumnName 'DatabaseName')
                    BackupType           = if ($null -ne $backupType) { [int]$backupType } else { -1 }
                    BackupTypeDescription = [string](Get-RowValue -Row $row -ColumnName 'BackupTypeDescription')
                    BackupStartDate      = Convert-ToNullableDateTime (Get-RowValue -Row $row -ColumnName 'BackupStartDate')
                    BackupFinishDate     = Convert-ToNullableDateTime (Get-RowValue -Row $row -ColumnName 'BackupFinishDate')
                    FirstLSN             = Convert-ToNullableDecimal (Get-RowValue -Row $row -ColumnName 'FirstLSN')
                    LastLSN              = Convert-ToNullableDecimal (Get-RowValue -Row $row -ColumnName 'LastLSN')
                    CheckpointLSN        = Convert-ToNullableDecimal (Get-RowValue -Row $row -ColumnName 'CheckpointLSN')
                    DatabaseBackupLSN    = Convert-ToNullableDecimal (Get-RowValue -Row $row -ColumnName 'DatabaseBackupLSN')
                    DifferentialBaseLSN  = Convert-ToNullableDecimal (Get-RowValue -Row $row -ColumnName 'DifferentialBaseLSN')
                    RecoveryModel        = [string](Get-RowValue -Row $row -ColumnName 'RecoveryModel')
                    RecoveryForkID       = [string](Get-RowValue -Row $row -ColumnName 'RecoveryForkID')
                    FirstRecoveryForkID  = [string](Get-RowValue -Row $row -ColumnName 'FirstRecoveryForkID')
                    FamilyGUID           = [string](Get-RowValue -Row $row -ColumnName 'FamilyGUID')
                    IsCopyOnly           = ($null -ne $isCopyOnlyValue -and [bool]$isCopyOnlyValue)
                    IsDamaged            = ($null -ne $isDamagedValue -and [bool]$isDamagedValue)
                    HasBackupChecksums   = ($null -ne $hasChecksumsValue -and [bool]$hasChecksumsValue)
                }

                $metadata.Add($record)
            }
        }
        catch {
            $unreadable.Add([pscustomobject]@{
                FilePath = $file.FullName
                Error    = $_.Exception.Message
            })
        }
    }
}
finally {
    if ($connection.State -ne [System.Data.ConnectionState]::Closed) {
        $connection.Close()
    }
    $connection.Dispose()
}

if ($metadata.Count -eq 0) {
    throw 'No readable SQL Server backup metadata was found.'
}

$databaseNames = @(
    $metadata |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.DatabaseName) } |
        Select-Object -ExpandProperty DatabaseName -Unique |
        Sort-Object
)

if ([string]::IsNullOrWhiteSpace($DatabaseName)) {
    if ($databaseNames.Count -ne 1) {
        $found = $databaseNames -join ', '
        throw "Multiple or zero databases were found. Specify -DatabaseName. Detected: $found"
    }
    $DatabaseName = $databaseNames[0]
}
elseif ($databaseNames -notcontains $DatabaseName) {
    throw "DatabaseName '$DatabaseName' was not found in readable backup metadata."
}

$databaseMetadata = @(
    $metadata |
        Where-Object { $_.DatabaseName -eq $DatabaseName }
)

foreach ($item in $databaseMetadata) {
    if ($item.IsDamaged) {
        $warnings.Add("Backup header is marked damaged: $($item.FilePath) FILE=$($item.Position)")
    }
    if (-not $item.HasBackupChecksums) {
        $warnings.Add("Backup lacks SQL backup checksums: $($item.FilePath) FILE=$($item.Position)")
    }
}

$eligibleBaseCutoff = if ($RecoveryTarget.HasValue) { $RecoveryTarget.Value } else { [datetime]::MaxValue }

$fullBackups = @(
    $databaseMetadata |
        Where-Object {
            $_.BackupType -eq 1 -and
            -not $_.IsDamaged -and
            $null -ne $_.BackupFinishDate -and
            $_.BackupFinishDate -le $eligibleBaseCutoff
        } |
        Sort-Object BackupFinishDate
)

if ($fullBackups.Count -eq 0) {
    throw 'No eligible, undamaged FULL backup was found at or before the requested recovery target.'
}

$differentials = @(
    $databaseMetadata |
        Where-Object {
            $_.BackupType -eq 5 -and
            -not $_.IsDamaged -and
            $null -ne $_.BackupFinishDate -and
            $_.BackupFinishDate -le $eligibleBaseCutoff
        } |
        Sort-Object BackupFinishDate
)

$candidates = New-Object System.Collections.Generic.List[object]
foreach ($full in $fullBackups) {
    $compatibleDifferentials = @(
        $differentials |
            Where-Object {
                $_.BackupFinishDate -ge $full.BackupFinishDate -and
                (Test-DifferentialCompatibility -Full $full -Differential $_)
            } |
            Sort-Object BackupFinishDate
    )

    $selectedDifferential = $null
    if ($compatibleDifferentials.Count -gt 0) {
        $selectedDifferential = $compatibleDifferentials[-1]
    }

    $effectiveFinish = $full.BackupFinishDate
    if ($null -ne $selectedDifferential) {
        $effectiveFinish = $selectedDifferential.BackupFinishDate
    }

    $candidates.Add([pscustomobject]@{
        Full         = $full
        Differential = $selectedDifferential
        EffectiveFinish = $effectiveFinish
    })
}

$selectedCandidate = @($candidates | Sort-Object EffectiveFinish)[-1]
$selectedFull = $selectedCandidate.Full
$selectedDifferential = $selectedCandidate.Differential
$selectedBase = if ($null -ne $selectedDifferential) { $selectedDifferential } else { $selectedFull }

if ($selectedFull.IsCopyOnly -and $null -ne $selectedDifferential) {
    $warnings.Add('Internal selection warning: a differential was associated with a COPY_ONLY full.')
}

$incompatibleDifferentials = @(
    $differentials |
        Where-Object {
            $_.BackupFinishDate -ge $selectedFull.BackupFinishDate -and
            -not (Test-DifferentialCompatibility -Full $selectedFull -Differential $_)
        }
)
if ($incompatibleDifferentials.Count -gt 0) {
    $warnings.Add("$($incompatibleDifferentials.Count) differential backup set(s) after the selected full were incompatible with its differential base.")
}

$selectedLogs = New-Object System.Collections.Generic.List[object]
$gapDetected = $false
$targetCovered = -not $RecoveryTarget.HasValue

if ($null -eq $selectedBase.LastLSN) {
    $warnings.Add('Selected base backup has no LastLSN; a transaction-log chain cannot be established.')
    $gapDetected = $true
}
else {
    $logs = @(
        $databaseMetadata |
            Where-Object {
                $_.BackupType -eq 2 -and
                -not $_.IsDamaged -and
                $null -ne $_.FirstLSN -and
                $null -ne $_.LastLSN -and
                $_.LastLSN -gt $selectedBase.LastLSN -and
                (-not $RecoveryTarget.HasValue -or
                    $null -eq $_.BackupStartDate -or
                    $_.BackupStartDate -le $RecoveryTarget.Value)
            } |
            Sort-Object FirstLSN, LastLSN, BackupFinishDate
    )

    $currentLsn = [decimal]$selectedBase.LastLSN
    $usedKeys = @{}

    while ($true) {
        $nextOptions = @(
            $logs |
                Where-Object {
                    $key = "$($_.FilePath)|$($_.Position)"
                    -not $usedKeys.ContainsKey($key) -and
                    $_.FirstLSN -le $currentLsn -and
                    $_.LastLSN -gt $currentLsn
                } |
                Sort-Object LastLSN, BackupFinishDate
        )

        if ($nextOptions.Count -eq 0) {
            $future = @(
                $logs |
                    Where-Object {
                        $key = "$($_.FilePath)|$($_.Position)"
                        -not $usedKeys.ContainsKey($key) -and
                        $_.LastLSN -gt $currentLsn
                    } |
                    Sort-Object FirstLSN, LastLSN
            )

            if ($future.Count -gt 0) {
                $gapDetected = $true
                $warnings.Add("Obvious LSN gap: current coverage ends at $(Format-Lsn $currentLsn), next candidate begins at $(Format-Lsn $future[0].FirstLSN).")
            }
            break
        }

        if ($nextOptions.Count -gt 1) {
            $warnings.Add("Multiple log backups overlap LSN $(Format-Lsn $currentLsn); selected the candidate with the earliest advancing LastLSN.")
        }

        $next = $nextOptions[0]
        $key = "$($next.FilePath)|$($next.Position)"
        $usedKeys[$key] = $true
        $selectedLogs.Add($next)
        $currentLsn = [decimal]$next.LastLSN

        if ($RecoveryTarget.HasValue -and
            $null -ne $next.BackupFinishDate -and
            $next.BackupFinishDate -ge $RecoveryTarget.Value) {
            $targetCovered = $true
            break
        }
    }
}

if ($RecoveryTarget.HasValue -and -not $targetCovered) {
    $warnings.Add("The continuous log sequence does not demonstrate coverage through recovery target $($RecoveryTarget.Value.ToString('o')).")
}

if ($selectedLogs.Count -eq 0 -and $selectedBase.RecoveryModel -in @('FULL', 'BULK-LOGGED')) {
    $warnings.Add('No transaction-log backup could be chained after the selected base.')
}

$restoreOrder = New-Object System.Collections.Generic.List[object]
$sequence = 1
$restoreOrder.Add([pscustomobject]@{
    Sequence = $sequence
    Type = 'FULL'
    File = $selectedFull.FilePath
    Position = $selectedFull.Position
    FirstLSN = $selectedFull.FirstLSN
    LastLSN = $selectedFull.LastLSN
})
$sequence++

if ($null -ne $selectedDifferential) {
    $restoreOrder.Add([pscustomobject]@{
        Sequence = $sequence
        Type = 'DIFF'
        File = $selectedDifferential.FilePath
        Position = $selectedDifferential.Position
        FirstLSN = $selectedDifferential.FirstLSN
        LastLSN = $selectedDifferential.LastLSN
    })
    $sequence++
}

foreach ($log in $selectedLogs) {
    $restoreOrder.Add([pscustomobject]@{
        Sequence = $sequence
        Type = 'LOG'
        File = $log.FilePath
        Position = $log.Position
        FirstLSN = $log.FirstLSN
        LastLSN = $log.LastLSN
    })
    $sequence++
}

$report = New-Object System.Text.StringBuilder
Add-ReportLine $report 'CVT BackupBridge - Backup Chain Report'
Add-ReportLine $report ('GeneratedUtc: ' + [datetime]::UtcNow.ToString('o'))
Add-ReportLine $report ('MetadataSqlInstance: ' + $SqlInstance)
Add-ReportLine $report ('BackupRoot: ' + $resolvedRoot)
Add-ReportLine $report ('Database: ' + $DatabaseName)
Add-ReportLine $report ('RecoveryTarget: ' + $(if ($RecoveryTarget.HasValue) { $RecoveryTarget.Value.ToString('o') } else { '[latest continuous point]' }))
Add-ReportLine $report ('FilesScanned: ' + $files.Count)
Add-ReportLine $report ('BackupSetsRead: ' + $metadata.Count)
Add-ReportLine $report ('UnreadableFiles: ' + $unreadable.Count)
Add-ReportLine $report ''

Add-ReportLine $report 'Selected base'
Add-ReportLine $report ('  FULL: ' + $selectedFull.FilePath + ' FILE=' + $selectedFull.Position)
Add-ReportLine $report ('    Finish=' + $selectedFull.BackupFinishDate + ' CheckpointLSN=' + (Format-Lsn $selectedFull.CheckpointLSN) + ' LastLSN=' + (Format-Lsn $selectedFull.LastLSN) + ' CopyOnly=' + $selectedFull.IsCopyOnly)
if ($null -ne $selectedDifferential) {
    Add-ReportLine $report ('  DIFF: ' + $selectedDifferential.FilePath + ' FILE=' + $selectedDifferential.Position)
    Add-ReportLine $report ('    Finish=' + $selectedDifferential.BackupFinishDate + ' DifferentialBaseLSN=' + (Format-Lsn $selectedDifferential.DifferentialBaseLSN) + ' LastLSN=' + (Format-Lsn $selectedDifferential.LastLSN))
}
else {
    Add-ReportLine $report '  DIFF: [none selected]'
}
Add-ReportLine $report ''

Add-ReportLine $report 'Restore order (report only; nothing was restored)'
foreach ($step in $restoreOrder) {
    Add-ReportLine $report ("  {0,3}. {1,-4} FILE={2} FirstLSN={3} LastLSN={4}" -f $step.Sequence, $step.Type, $step.Position, (Format-Lsn $step.FirstLSN), (Format-Lsn $step.LastLSN))
    Add-ReportLine $report ('       ' + $step.File)
}
Add-ReportLine $report ''

if ($unreadable.Count -gt 0) {
    Add-ReportLine $report 'Unreadable files'
    foreach ($failure in $unreadable) {
        Add-ReportLine $report ('  WARN: ' + $failure.FilePath)
        Add-ReportLine $report ('        ' + $failure.Error)
    }
    Add-ReportLine $report ''
}

Add-ReportLine $report 'Warnings'
if ($warnings.Count -eq 0) {
    Add-ReportLine $report '  [none]'
}
else {
    foreach ($warning in ($warnings | Select-Object -Unique)) {
        Add-ReportLine $report ('  WARN: ' + $warning)
    }
}
Add-ReportLine $report ''

$chainValid = (-not $gapDetected -and
               ($unreadable.Count -eq 0) -and
               (-not $RecoveryTarget.HasValue -or $targetCovered))

Add-ReportLine $report ('ChainStatus: ' + $(if ($chainValid) { 'CANDIDATE_CHAIN_ESTABLISHED' } else { 'CHAIN_NOT_ESTABLISHED' }))
Add-ReportLine $report 'Important: This report does not prove restore compatibility or recoverability.'
Add-ReportLine $report 'Required next step: RESTORE HEADERONLY/VERIFYONLY evidence, isolated restore, recovery, and DBCC CHECKDB.'

$reportText = $report.ToString()
Write-Output $reportText

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $parent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and
        -not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw "OutputPath parent directory does not exist: $parent"
    }

    Set-Content -LiteralPath $OutputPath -Value $reportText -Encoding UTF8
}

if (-not $chainValid) {
    exit 2
}

exit 0
