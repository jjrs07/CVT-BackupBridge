# S3 Multi-Threaded Backup Uploader (Path Preserving Version)
# Description: Recursively discovers SQL Server backup files (.bak, .trn) and uploads them to AWS S3.
# Supports multi-threaded processing (max simultaneous uploads) and automatic retries.
# Compatibility: PowerShell 2.0+

# ============================================================
# CONFIGURATION LOADING
# ============================================================
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
# Look for settings.json in the parent directory or same directory
$configPath = Join-Path $scriptPath "..\settings.json"
if (-not (Test-Path $configPath)) {
    $configPath = Join-Path $scriptPath "settings.json"
}

if (Test-Path $configPath) {
    $config = Get-Content $configPath | ConvertFrom-Json
    # Sanitize bucket URL: Ensure it starts with s3:// and ends with a single /
    $bucketUrl = $config.S3Bucket.TrimEnd('/') + '/'
    if (-not $bucketUrl.StartsWith("s3://")) { $bucketUrl = "s3://" + $bucketUrl }
    
    $bucket     = $bucketUrl
    $region     = $config.AWSRegion
    $maxJobs    = $config.MaxSimultaneousJobs
    $backupRoot = $config.BackupRootPath
    $logFile    = Join-Path $config.LogDirectory "S3Upload.log"
} else {
    Write-Error "Configuration file not found. Please ensure settings.json exists."
    exit 1
}

# ============================================================
# PATH RESOLUTION LOGIC
# ============================================================

# Identify the name of the root folder to prepend in S3
$rootFolderName = Split-Path $backupRoot -Leaf

# Handle cases where backupRoot is a drive root (e.g., Z:\) or resolution is needed
if ($backupRoot -match '^[A-Z]:\\?$' -or $rootFolderName -match ':') {
    $driveName = $backupRoot.Substring(0, 1)
    
    # Try multiple ways to get the network name
    $networkPath = ""
    $drive = Get-PSDrive $driveName -ErrorAction SilentlyContinue
    if ($drive -and $drive.DisplayRoot) {
        $networkPath = $drive.DisplayRoot
    }
    
    if (-not $networkPath) {
        # Fallback to WMI (compatible with PS 2.0)
        try {
            # Using ${} to delimit variable name from colon to avoid parser errors
            $filter = "DeviceID='${driveName}:'"
            $wmi = Get-WmiObject Win32_LogicalDisk -Filter $filter -ErrorAction SilentlyContinue
            if ($wmi -and $wmi.ProviderName) { $networkPath = $wmi.ProviderName }
        } catch {}
    }
    
    if ($networkPath) {
        # Extract the leaf name from the network path (e.g., SQL1Test)
        $rootFolderName = Split-Path $networkPath -Leaf
    } else {
        # If it's a local drive or can't be resolved, don't use the drive letter as a folder
        $rootFolderName = ""
    }
}

# Final cleanup: ensure no illegal S3 characters remain in the root folder name
if ($rootFolderName) {
    $rootFolderName = $rootFolderName -replace '[:\\/]', ''
}

Write-Host "Resolved S3 Root Folder: $(if ($rootFolderName) { $rootFolderName } else { "[None - Using subfolders only]" })"

# ============================================================
# UTILITY FUNCTIONS
# ============================================================

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] $Message"
    Write-Host $entry
    
    $logDir = Split-Path $logFile
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    Add-Content -Path $logFile -Value $entry
}

function Format-Duration {
    param([int]$seconds)
    $ts = [TimeSpan]::FromSeconds($seconds)
    if ($ts.Hours -gt 0) {
        return "{0:00}:{1:00}:{2:00}" -f $ts.Hours, $ts.Minutes, $ts.Seconds
    }
    return "{0:00}:{1:00}" -f $ts.Minutes, $ts.Seconds
}

function Get-S3Folder {
    param([string]$FilePath, [string]$RootPath, [string]$RootFolderName)
    
    # Calculate relative path from the backup root
    $relativePath   = $FilePath.Substring($RootPath.Length).TrimStart('\')
    $relativeFolder = Split-Path $relativePath -Parent
    
    # Construct the base S3 path starting with the root folder name
    $s3PathParts = @()
    if ($RootFolderName) { $s3PathParts += $RootFolderName }
    if ($relativeFolder -and $relativeFolder -ne ".") { 
        $s3PathParts += ($relativeFolder -split '\\') 
    }
    
    # Specialized logic for Transaction Logs: <ServerName>\<DatabaseName>\LOG
    # Expected structure for .trn: <ServerName>\<DatabaseName>\<Type>\<File>
    if ($FilePath.EndsWith('.trn')) {
        $parts = $s3PathParts
        if ($parts.Length -ge 3) {
            # parts[0] = Root (Server), parts[1] = DB, parts[2] = Type (usually 'LOG' or 'TRN')
            return "$($parts[0])/$($parts[1])/LOG"
        }
    }
    
    # Join with forward slashes for S3
    $finalPath = $s3PathParts -join '/'
    return $finalPath
}

# ============================================================
# INITIALIZATION
# ============================================================

# Discover backup files (PS 2.0 compatible discovery)
$files = Get-ChildItem -Path $backupRoot -Recurse | 
    Where-Object { (-not $_.PSIsContainer) -and ($_.Extension -in '.bak', '.trn') } |
    Sort-Object FullName |
    Select-Object -ExpandProperty FullName

if (-not $files) {
    Write-Log "No backup files found under $backupRoot"
    exit 1
}

# Initialize log file
if (Test-Path $logFile) { Remove-Item $logFile -Force }

# ============================================================
# PROCESSING QUEUE SETUP
# ============================================================

$queueStartTime = Get-Date
$total          = $files.Count
$completed      = 0
$failed         = 0
$maxRetries     = 3
$activeUploads  = @{}

Write-Log "===== S3 Upload Queue Started (Path Preserving) ====="
Write-Log "Total files to upload: $total"
Write-Log "S3 Root Folder: $rootFolderName"
Write-Log "Destination bucket: $bucket"
Write-Log "========================================="

$queue = [System.Collections.Queue]::new()
foreach ($file in $files) {
    $fileItem = Get-Item $file
    $fileSize = [math]::Round($fileItem.Length / 1GB, 2)
    $queue.Enqueue(@{ 
        File       = $file; 
        FileName   = Split-Path $file -Leaf; 
        FileSizeGB = $fileSize; 
        Retries    = 0 
    })
}

# ============================================================
# MAIN EXECUTION LOOP
# ============================================================

while ($queue.Count -gt 0 -or $activeUploads.Count -gt 0) {

    while ($activeUploads.Count -lt $maxJobs -and $queue.Count -gt 0) {
        $item     = $queue.Dequeue()
        $folder   = Get-S3Folder -FilePath $item.File -RootPath $backupRoot -RootFolderName $rootFolderName
        $outFile  = Join-Path (Split-Path $logFile) "$($item.FileName).log"

        # Construct S3 destination
        $s3Dest = if ($folder) { "$bucket$folder/" } else { "$bucket" }

        $s3Args = @(
            "s3", "cp", 
            $item.File, 
            $s3Dest, 
            "--quiet", 
            "--storage-class", "STANDARD", 
            "--region", $region
        )

        $proc = Start-Process -FilePath "aws" -ArgumentList $s3Args `
            -RedirectStandardOutput $outFile -RedirectStandardError "$outFile.err" `
            -NoNewWindow -PassThru

        $activeUploads[$proc.Id] = @{
            Process    = $proc
            File       = $item.File
            FileName   = $item.FileName
            FileSizeGB = $item.FileSizeGB
            Folder     = $folder
            StartTime  = Get-Date
            OutFile    = $outFile
            Retries    = $item.Retries
            S3Dest     = $s3Dest
        }
        
        $retryLabel = if ($item.Retries -gt 0) { " (Retry $($item.Retries)/$maxRetries)" } else { "" }
        Write-Log "STARTED  | $($item.FileName) -> $($s3Dest) (PID: $($proc.Id))$retryLabel"
    }

    foreach ($procId in @($activeUploads.Keys)) {
        $entry = $activeUploads[$procId]
        $proc  = $entry.Process

        if ($proc.HasExited) {
            $durationSec = [math]::Max(1, ((Get-Date) - $entry.StartTime).TotalSeconds)
            $mbps        = [math]::Round(($entry.FileSizeGB * 1024 * 8) / $durationSec, 1)

            if ($proc.ExitCode -eq 0) {
                $completed++
                Write-Log "COMPLETE | $($entry.FileName) | Size: $($entry.FileSizeGB) GB | Duration: $(Format-Duration $durationSec) | Speed: $mbps Mbps | Progress: $completed/$total"
            } else {
                $errFile = "$($entry.OutFile).err"
                $errOutput = if (Test-Path $errFile) { Get-Content $errFile | ForEach-Object { $_.Trim() } } else { "Exit code: $($proc.ExitCode)" }
                
                if ($entry.Retries -lt $maxRetries) {
                    Write-Log "RETRYING | $($entry.FileName) | Attempt $($entry.Retries + 1)/$maxRetries | Error: $errOutput"
                    $queue.Enqueue(@{ 
                        File       = $entry.File; 
                        FileName   = $entry.FileName; 
                        FileSizeGB = $entry.FileSizeGB; 
                        Retries    = $entry.Retries + 1 
                    })
                } else {
                    $failed++
                    Write-Log "FAILED   | $($entry.FileName) | Max retries reached | Error: $errOutput"
                }
            }
            $activeUploads.Remove($procId)
        }
    }

    Start-Sleep -Seconds 5
}

Write-Log "========================================="
Write-Log "===== Upload Queue Complete ====="
Write-Log "Total: $total | Completed: $completed | Failed: $failed | Elapsed: $(Format-Duration [int]((Get-Date) - $queueStartTime).TotalSeconds)"
Write-Log "========================================="
