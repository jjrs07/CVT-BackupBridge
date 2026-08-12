# S3 Recovery Downloader
# Orchestrates AWS CLI v2 to synchronize an Amazon S3 recovery prefix to a local directory.
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
    'RestoreRootPath',
    'LogDirectory'
)

foreach ($settingName in $requiredSettings) {
    $property = $config.PSObject.Properties[$settingName]
    if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        Write-Error "Required configuration value '$settingName' is missing or empty in '$configPath'."
        exit 1
    }
}

$source = ([string]$config.S3Bucket).Trim()
$region = ([string]$config.AWSRegion).Trim()
$destination = [string]$config.RestoreRootPath
$logDirectory = [string]$config.LogDirectory

if (-not $source.StartsWith('s3://', [System.StringComparison]::OrdinalIgnoreCase)) {
    $source = "s3://$source"
}
$source = $source.TrimEnd('/') + '/'

if ($source -notmatch '^s3:\/\/[^\/\s]+(?:\/.*)?$') {
    Write-Error "S3Bucket is not a valid S3 URI or bucket name: $source"
    exit 1
}

try {
    if (Test-Path -LiteralPath $destination) {
        if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
            throw "RestoreRootPath exists but is not a directory: $destination"
        }
    }
    else {
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
        throw "RestoreRootPath could not be created or accessed: $destination"
    }

    if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}

$logFile = Join-Path $logDirectory 'S3Download.log'

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
    $sanitizedMessage = $sanitizedMessage -replace '"', '\"'
    $entry = '{0} level={1} event={2} message="{3}"' -f $timestamp, $Level, $Event, $sanitizedMessage

    Write-Host $entry
    Add-Content -LiteralPath $logFile -Value $entry -Encoding UTF8
}

# ============================================================
# AWS CLI VALIDATION
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

$previousErrorActionPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $awsVersionOutput = (& $awsExecutable --version 2>&1 | Out-String).Trim()
    $awsVersionExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}

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
    $source,
    $destination,
    '--region',
    $region,
    '--checksum-mode',
    'ENABLED',
    '--no-progress'
)

$startTime = Get-Date
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$exitCode = 1

Write-Log -Level 'INFO' -Event 'SYNC_START' -Message "StartTime=$($startTime.ToString('o')) Source=$source Destination=$destination Region=$region AwsCli=$awsVersionOutput"
Write-Log -Level 'INFO' -Event 'TRANSFER_POLICY' -Message 'Direction=S3-to-local DeleteEnabled=false ChecksumMode=ENABLED TransferEngine=aws-s3-sync'

try {
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    try {
        $awsOutput = & $awsExecutable @syncArguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    foreach ($outputLine in $awsOutput) {
        if (-not [string]::IsNullOrWhiteSpace([string]$outputLine)) {
            Write-Log -Level 'INFO' -Event 'AWS_CLI_OUTPUT' -Message ([string]$outputLine)
        }
    }
}
catch {
    Write-Log -Level 'ERROR' -Event 'AWS_CLI_EXCEPTION' -Message $_.Exception.Message
}
finally {
    $stopwatch.Stop()
}

if ($null -eq $exitCode) {
    $exitCode = 1
}

$duration = $stopwatch.Elapsed.ToString('c')

if ($exitCode -eq 0) {
    Write-Log -Level 'INFO' -Event 'SYNC_COMPLETE' -Message "ExitCode=$exitCode Duration=$duration FinalResult=SUCCESS"
    exit 0
}

Write-Log -Level 'ERROR' -Event 'SYNC_COMPLETE' -Message "ExitCode=$exitCode Duration=$duration FinalResult=FAILED"
exit $exitCode
