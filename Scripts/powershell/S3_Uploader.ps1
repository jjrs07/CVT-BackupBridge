# S3 Multi-Threaded Backup Uploader
# Description: Recursively discovers SQL Server backup files (.bak, .trn) and uploads them to AWS S3.
# Supports multi-threaded processing (max simultaneous uploads) and automatic retries.

# ============================================================
# CONFIGURATION LOADING
# ============================================================
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptPath "..\settings.json"

if (Test-Path $configPath) {
    $config = Get-Content $configPath | ConvertFrom-Json
    $bucket     = $config.S3Bucket
    $region     = $config.AWSRegion
    $maxJobs    = $config.MaxSimultaneousJobs
    $backupRoot = $config.BackupRootPath
    $logFile    = Join-Path $config.LogDirectory "S3Upload.log"
} else {
    Write-Error "Configuration file not found at $configPath. Please copy settings.json.template to settings.json and update it."
    exit 1
}

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
    param([string]$FilePath, [string]$RootPath)
    
    # Map local directory structure to S3 folders
    # Expected structure: <ServerName>\<DatabaseName>\<Type>
    $relativePath   = $FilePath.Substring($RootPath.Length).TrimStart('\')
    $relativeFolder = Split-Path $relativePath -Parent
    $folderParts    = $relativeFolder -split '\\'
    
    if ($folderParts.Length -ge 3 -and $FilePath.EndsWith('.trn')) {
        # Normalize transaction log destination to a standard /LOG folder
        return "$($folderParts[0])/$($folderParts[1])/LOG"
    }
    
    return $relativeFolder -replace '\\', '/'
}

# ============================================================
# INITIALIZATION
# ============================================================

# Discover backup files while preserving directory structure
$files = Get-ChildItem -Path $backupRoot -Recurse -File | 
    Where-Object { $_.Extension -in '.bak', '.trn' } |
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

Write-Log "===== S3 Upload Queue Started ====="
Write-Log "Total files to upload: $total"
Write-Log "Max simultaneous uploads: $maxJobs"
Write-Log "Destination bucket: $bucket"
Write-Log "========================================="

# Build queue with file metadata
$queue = [System.Collections.Queue]::new()
foreach ($file in $files) {
    $fileSize = [math]::Round((Get-Item $file).Length / 1GB, 2)
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

    # 1. Start new upload jobs up to $maxJobs
    while ($activeUploads.Count -lt $maxJobs -and $queue.Count -gt 0) {
        $item     = $queue.Dequeue()
        $folder   = Get-S3Folder -FilePath $item.File -RootPath $backupRoot
        $outFile  = Join-Path (Split-Path $logFile) "$($item.FileName).log"

        # Prepare AWS CLI arguments
        $s3Args = @(
            "s3", "cp", 
            $item.File, 
            "$bucket$folder/", 
            "--quiet", 
            "--storage-class", "STANDARD", 
            "--region", $region
        )

        # Start the background process
        $proc = Start-Process -FilePath "aws" -ArgumentList $s3Args `
            -RedirectStandardOutput $outFile -RedirectStandardError "$outFile.err" `
            -NoNewWindow -PassThru

        # Track active job
        $activeUploads[$proc.Id] = @{
            Process    = $proc
            File       = $item.File
            FileName   = $item.FileName
            FileSizeGB = $item.FileSizeGB
            Folder     = $folder
            StartTime  = Get-Date
            OutFile    = $outFile
            Retries    = $item.Retries
        }
        
        $retryLabel  = if ($item.Retries -gt 0) { " (Retry $($item.Retries)/$maxRetries)" } else { "" }
        $folderLabel = if ($folder) { " to $folder/" } else { "" }
        Write-Log "STARTED  | $($item.FileName) ($($item.FileSizeGB) GB)$folderLabel (PID: $($proc.Id))$retryLabel"
    }

    # 2. Monitor and reap finished jobs
    foreach ($procId in @($activeUploads.Keys)) {
        $entry = $activeUploads[$procId]
        $proc  = $entry.Process

        if ($proc.HasExited) {
            $durationSec = [math]::Max(1, ((Get-Date) - $entry.StartTime).TotalSeconds)
            $mbps        = [math]::Round(($entry.FileSizeGB * 1024 * 8) / $durationSec, 1)

            # Success Verification
            $uploadSuccess = ($proc.ExitCode -eq 0)
            if (-not $uploadSuccess) {
                # Fallback check: verify object exists in S3 if process exit code is non-zero
                $s3Path = if ($entry.Folder) { "$bucket$($entry.Folder)/$($entry.FileName)" } else { "$bucket$($entry.FileName)" }
                & aws s3 ls $s3Path | Out-Null
                if ($LASTEXITCODE -eq 0) { $uploadSuccess = $true }
            }

            if ($uploadSuccess) {
                $completed++
                $folderLabel = if ($entry.Folder) { " | Folder: $($entry.Folder)" } else { "" }
                Write-Log "COMPLETE | $($entry.FileName) | Size: $($entry.FileSizeGB) GB | Duration: $(Format-Duration $durationSec) | Speed: $mbps Mbps$folderLabel | Progress: $completed/$total"
            } else {
                # Handle failure and extract error messages
                $errFile = "$($entry.OutFile).err"
                $errOutput = if (Test-Path $errFile) { Get-Content $errFile -Raw | ForEach-Object { $_.Trim() } } else { "Exit code: $($proc.ExitCode)" }
                
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

    Start-Sleep -Seconds 10
}

# ============================================================
# FINAL REPORTING
# ============================================================

$queueDurationSec = [math]::Max(1, ((Get-Date) - $queueStartTime).TotalSeconds)
Write-Log "========================================="
Write-Log "===== Upload Queue Complete ====="
Write-Log "Total: $total | Completed: $completed | Failed: $failed | Elapsed: $(Format-Duration $queueDurationSec)"
Write-Log "========================================="

if ($failed -gt 0) {
    Write-Log "Check individual log files in: $(Split-Path $logFile)"
    Write-Log "Diagnostics: Run 'aws sts get-caller-identity' to verify AWS credentials."
}
