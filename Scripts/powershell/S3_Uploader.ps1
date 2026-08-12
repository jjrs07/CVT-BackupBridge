# S3 Backup Uploader
# Orchestrates AWS CLI v2 to synchronize SQL Server backup files to Amazon S3.
# Requires Windows PowerShell 5.1 or later.

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ============================================================
# CONFIGURATION
# ============================================================

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptPath '..\settings.json'

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    $configPath = Join-Path $scriptPath 'settings.json'
}

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    Write-Error 'Configuration file not found. Copy settings.json.template to settings.json and update it.'
    exit 1
}

try {
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "Unable to read configuration file '$configPath': $($_.Exception.Message)"
    exit 1
}

$requiredSettings = @(
    'S3Bucket',
    'AWSRegion',
    'BackupRootPath',
    'LogDirectory'
)

foreach ($settingName in $requiredSettings) {
    $property = $config.PSObject.Properties[$settingName]
    if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        Write-Error "Required configuration value '$settingName' is missing or empty in '$configPath'."
        exit 1
    }
}

$sourcePath = [string]$config.BackupRootPath
$region = [string]$config.AWSRegion
$logDirectory = [string]$config.LogDirectory
$destination = ([string]$config.S3Bucket).Trim()

if (-not $destination.StartsWith('s3://', [System.StringComparison]::OrdinalIgnoreCase)) {
    $destination = "s3://$destination"
}
$destination = $destination.TrimEnd('/') + '/'

try {
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        throw "Source directory does not exist or is not accessible: $sourcePath"
    }

    if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}

$logFile = Join-Path $logDirectory 'S3Upload.log'

# ============================================================
# LOGGING
# ============================================================

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'ERROR')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Event,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $sanitizedMessage = $Message -replace '[\r\n]+', ' '
    $entry = '{0} level={1} event={2} message="{3}"' -f $timestamp, $Level, $Event, $sanitizedMessage

    Write-Host $entry
    Add-Content -LiteralPath $logFile -Value $entry -Encoding UTF8
}

# ============================================================
# PREREQUISITE VALIDATION
# ============================================================

$awsCommand = Get-Command 'aws' -CommandType Application -ErrorAction SilentlyContinue
if ($null -eq $awsCommand) {
    Write-Log -Level 'ERROR' -Event 'PREREQUISITE_FAILED' -Message 'AWS CLI was not found in PATH.'
    exit 1
}

$awsExecutable = $awsCommand.Source
if ([string]::IsNullOrWhiteSpace($awsExecutable)) {
    $awsExecutable = $awsCommand.Path
}

$awsVersionOutput = (& $awsExecutable --version 2>&1 | Out-String).Trim()
$awsVersionExitCode = $LASTEXITCODE

if ($awsVersionExitCode -ne 0) {
    Write-Log -Level 'ERROR' -Event 'PREREQUISITE_FAILED' -Message "Unable to execute AWS CLI. ExitCode=$awsVersionExitCode Output=$awsVersionOutput"
    exit 1
}

if ($awsVersionOutput -notmatch '^aws-cli\/2\.') {
    Write-Log -Level 'ERROR' -Event 'PREREQUISITE_FAILED' -Message "AWS CLI v2 is required. Detected: $awsVersionOutput"
    exit 1
}

# ============================================================
# AWS CLI SYNCHRONIZATION
# ============================================================

$syncArguments = @(
    's3',
    'sync',
    $sourcePath,
    $destination,
    '--exclude',
    '*',
    '--include',
    '*.bak',
    '--include',
    '*.trn',
    '--region',
    $region,
    '--no-progress'
)

$startTime = Get-Date
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

Write-Log -Level 'INFO' -Event 'SYNC_START' -Message "StartTime=$($startTime.ToString('o')) Source=$sourcePath Destination=$destination Region=$region AwsCli=$awsVersionOutput"
Write-Log -Level 'INFO' -Event 'TRANSFER_POLICY' -Message 'Includes=*.bak,*.trn DeleteEnabled=false TransferEngine=aws-s3-sync'

try {
    $awsOutput = & $awsExecutable @syncArguments 2>&1
    $exitCode = $LASTEXITCODE

    foreach ($outputLine in $awsOutput) {
        if (-not [string]::IsNullOrWhiteSpace([string]$outputLine)) {
            Write-Log -Level 'INFO' -Event 'AWS_CLI_OUTPUT' -Message ([string]$outputLine)
        }
    }
}
catch {
    $exitCode = 1
    Write-Log -Level 'ERROR' -Event 'AWS_CLI_EXCEPTION' -Message $_.Exception.Message
}
finally {
    $stopwatch.Stop()
}

$duration = $stopwatch.Elapsed.ToString('c')

if ($exitCode -eq 0) {
    Write-Log -Level 'INFO' -Event 'SYNC_COMPLETE' -Message "ExitCode=$exitCode Duration=$duration FinalResult=SUCCESS"
    exit 0
}

Write-Log -Level 'ERROR' -Event 'SYNC_COMPLETE' -Message "ExitCode=$exitCode Duration=$duration FinalResult=FAILED"
exit $exitCode
