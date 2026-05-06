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
    
    $networkPath = ""
    $drive = Get-PSDrive $driveName -ErrorAction SilentlyContinue
    if ($drive -and $drive.DisplayRoot) {
        $networkPath = $drive.DisplayRoot
    }
    
    if (-not $networkPath) {
        try {
            $filter = "DeviceID='${driveName}:'"
            $wmi = Get-WmiObject Win32_LogicalDisk -Filter $filter -ErrorAction SilentlyContinue
            if ($wmi -and $wmi.ProviderName) { $networkPath = $wmi.ProviderName }
        } catch {}
    }
    
    if ($networkPath) {
        $rootFolderName = Split-Path $networkPath -Leaf
    } else {
        $rootFolderName = ""
    }
}

if ($rootFolderName) {
    $rootFolderName = $rootFolderName -replace '[:\\/]', ''
}

Write-Host "Resolved S3 Root Folder: $(if ($rootFolderName) { $rootFolderName } else { "[None]" })"

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
    
    $relativePath   = $FilePath.Substring($RootPath.Length).TrimStart('\')
    $relativeFolder = Split-Path $relativePath -Parent
    
    $s3PathParts = @()
    if ($RootFolderName) { $s3PathParts += $RootFolderName }
    if ($relativeFolder -and $relativeFolder -ne ".") { 
        $s3PathParts += ($relativeFolder -split '\\') 
    }
    
    if ($FilePath.EndsWith('.trn')) {
        $parts = $s3PathParts
        if ($parts.Length -ge 3) {
            return "$($parts[0])/$($parts[1])/LOG"
        }
    }
    
    return $s3PathParts -join '/'
}

# ============================================================
# INITIALIZATION
# ============================================================

$files = Get-ChildItem -Path $backupRoot -Recurse | 
    Where-Object { (-not $_.PSIsContainer) -and ($_.Extension -in '.bak', '.trn') } |
    Sort-Object FullName |
    Select-Object -ExpandProperty FullName

if (-not $files) {
    Write-Log "No backup files found under $backupRoot"
    exit 1
}

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
        $s3Dest   = if ($folder) { "$bucket$folder/" } else { "$bucket" }

        # Argument list as string for better PS 2.0 compatibility
        $s3Args = "s3 cp `"$($item.File)`" `"$s3Dest`" --quiet --storage-class STANDARD --region $region"

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

            # Success Verification with S3 Fallback
            $uploadSuccess = ($proc.ExitCode -eq 0)
            if (-not $uploadSuccess) {
                # Small wait for S3 to register the object
                Start-Sleep -Seconds 2
                $s3Path = "$($entry.S3Dest)$($entry.FileName)"
                & aws s3 ls "$s3Path" --region $region | Out-Null
                if ($LASTEXITCODE -eq 0) { $uploadSuccess = $true }
            }

            if ($uploadSuccess) {
                $completed++
                Write-Log "COMPLETE | $($entry.FileName) | Size: $($entry.FileSizeGB) GB | Duration: $(Format-Duration $durationSec) | Speed: $mbps Mbps | Progress: $completed/$total"
            } else {
                $errFile = "$($entry.OutFile).err"
                $errOutput = if (Test-Path $errFile) { Get-Content $errFile | ForEach-Object { $_.Trim() } } else { "Exit code: $($proc.ExitCode)" }
                # Ensure $errOutput is a string for logging
                if ($errOutput -is [array]) { $errOutput = $errOutput -join " " }

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
