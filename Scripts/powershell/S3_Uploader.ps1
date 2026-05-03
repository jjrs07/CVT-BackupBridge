# S3 Upload Queue - Max 4 Simultaneous Uploads
# Usage: Edit the $files array with your file paths then run the script

$bucket  = "<Input your S3 bucket name here, e.g. s3://my-backups>"
$region  = "<Input your AWS region here, e.g. us-east-1>"
$maxJobs = 4
$logFile = "<Input your log file path here, e.g. C:\Logs\S3Upload.log>"

# ============================================================
# ADD YOUR BACKUP ROOT HERE
# ============================================================
$backupRoot = '<Input your backup root path here, e.g. H:\SQLBackups>'

# Discover all .bak and .trn files under H:\SQLBackups and preserve server/database/type structure.
$files = Get-ChildItem -Path $backupRoot -Recurse -File | Where-Object { $_.Extension -in '.bak', '.trn' } |
    Sort-Object FullName |
    Select-Object -ExpandProperty FullName

if (-not $files) {
    Write-Host "No backup files found under $backupRoot"
    exit 1
}

# ============================================================
# SCRIPT - Do not modify below this line
# ============================================================

# Create log directory if it doesn't exist
$logDir = Split-Path $logFile
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

# Clear previous log file on script start
if (Test-Path $logFile) { Remove-Item $logFile -Force }

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] $Message"
    Write-Host $entry
    Add-Content -Path $logFile -Value $entry
}

function Format-Duration {
    param($seconds)
    $ts = [TimeSpan]::FromSeconds($seconds)
    if ($ts.Hours -gt 0) {
        return "{0:00}:{1:00}:{2:00}" -f $ts.Hours, $ts.Minutes, $ts.Seconds
    }
    return "{0:00}:{1:00}" -f $ts.Minutes, $ts.Seconds
}

$queueStartTime = Get-Date

Write-Log "===== S3 Upload Queue Started ====="
Write-Log "Total files to upload: $($files.Count)"
Write-Log "Max simultaneous uploads: $maxJobs"
Write-Log "Destination bucket: $bucket"
Write-Log "========================================="

# Build queue with file metadata
$queue = [System.Collections.Queue]::new()
foreach ($file in $files) {
    $fileSize = [math]::Round((Get-Item $file).Length / 1GB, 2)
    $queue.Enqueue(@{ File = $file; FileName = Split-Path $file -Leaf; FileSizeGB = $fileSize; Retries = 0 })
}

$activeUploads = @{}
$completed     = 0
$failed        = 0
$total         = $files.Count
$maxRetries    = 3

while ($queue.Count -gt 0 -or $activeUploads.Count -gt 0) {

    # Start new uploads if slots are available
    while ($activeUploads.Count -lt $maxJobs -and $queue.Count -gt 0) {
        $item     = $queue.Dequeue()
        $file     = $item.File
        $fileName = $item.FileName
        $fileSize = $item.FileSizeGB
        $retries  = $item.Retries
        $outFile  = "$logDir\$fileName.log"

        # Build S3 upload folder from the backup folder hierarchy:
        # H:\SQLBackups\<ServerName>\<DatabaseName>\<FULL|DIFF|LOG>\<file>.bak
        $relativePath = $file.Substring($backupRoot.Length).TrimStart('\')
        $relativeFolder = Split-Path $relativePath -Parent
        $folderParts = $relativeFolder -split '\\'
        if ($folderParts.Length -ge 3 -and $fileName.EndsWith('.trn')) {
            # For .trn files, force upload to LOG folder
            $folder = "$($folderParts[0])/$($folderParts[1])/LOG"
        } else {
            $folder = $relativeFolder -replace '\\', '/'
        }

        # Use proper AWS CLI credentials with efficiency flags
        $proc = Start-Process -FilePath "aws" `
            -ArgumentList "s3 cp `"$file`" `"$bucket$folder/`" --quiet --storage-class STANDARD --region $region" `
            -RedirectStandardOutput $outFile `
            -RedirectStandardError "$outFile.err" `
            -NoNewWindow -PassThru

        $activeUploads[$proc.Id] = @{
            Process    = $proc
            File       = $file
            FileName   = $fileName
            FileSizeGB = $fileSize
            Folder     = $folder
            StartTime  = Get-Date
            OutFile    = $outFile
            Retries    = $retries
        }
        $retryLabel = if ($retries -gt 0) { " (Retry $retries/$maxRetries)" } else { "" }
        $folderLabel = if ($folder) { " to $folder/" } else { "" }
        Write-Log "STARTED  | $fileName ($fileSize GB)$folderLabel (PID: $($proc.Id))$retryLabel | Queue remaining: $($queue.Count)"
    }

    # Check for completed processes
    foreach ($procId in @($activeUploads.Keys)) {
        $entry   = $activeUploads[$procId]
        $proc    = $entry.Process

        if ($proc.HasExited) {
            $endTime     = Get-Date
            $durationSec = [math]::Max(1, ($endTime - $entry.StartTime).TotalSeconds)
            $duration    = [math]::Round($durationSec / 60, 1)
            $mbps        = [math]::Round(($entry.FileSizeGB * 1024 * 8) / $durationSec, 1)

            # Check if upload succeeded by verifying file exists in S3
            # AWS CLI sometimes returns non-zero exit codes even on success
            $uploadSuccess = $false
            if ($proc.ExitCode -eq 0) {
                $uploadSuccess = $true
                Write-Log "DEBUG | $($entry.FileName) | Process exit code 0 - success"
            } else {
                # Even if exit code is non-zero, check if file is actually in S3
                $s3Path = if ($entry.Folder) { "$bucket$($entry.Folder)/$($entry.FileName)" } else { "$bucket$($entry.FileName)" }
                $checkOutput = & aws s3 ls $s3Path 2>&1
                if ($LASTEXITCODE -eq 0 -and $checkOutput) {
                    $uploadSuccess = $true
                    Write-Log "DEBUG | $($entry.FileName) | Non-zero exit but verified in S3 - success"
                }
            }

            if ($uploadSuccess) {
                $completed++
                $durationText = Format-Duration $durationSec
                $folderLabel = if ($entry.Folder) { " | Folder: $($entry.Folder)" } else { "" }
                Write-Log "COMPLETE | $($entry.FileName) | Size: $($entry.FileSizeGB) GB | Duration: $durationText | Avg Speed: $mbps Mbps$folderLabel | Progress: $completed/$total"
            } else {
                $errOutput = ""
                if (Test-Path "$($entry.OutFile).err") { 
                    $errOutput = Get-Content "$($entry.OutFile).err" -Raw | ForEach-Object { $_.Trim() }
                }
                if (-not $errOutput -and (Test-Path "$($entry.OutFile)")) {
                    $errOutput = Get-Content "$($entry.OutFile)" -Raw | ForEach-Object { $_.Trim() }
                }
                if (-not $errOutput) { $errOutput = "Exit code: $($proc.ExitCode) (Check log files for details)" }
                
                if ($entry.Retries -lt $maxRetries) {
                    $nextRetry = $entry.Retries + 1
                    Write-Log "RETRYING | $($entry.FileName) | Attempt $nextRetry/$maxRetries | Error: $errOutput"
                    $queue.Enqueue(@{ File = $entry.File; FileName = $entry.FileName; FileSizeGB = $entry.FileSizeGB; Retries = $nextRetry })
                } else {
                    $failed++
                    $durationText = Format-Duration $durationSec
                    $folderLabel = if ($entry.Folder) { " | Folder: $($entry.Folder)" } else { "" }
                    Write-Log "FAILED   | $($entry.FileName) | Duration: $durationText$folderLabel | Max retries reached | Error: $errOutput"
                }
            }

            # Keep output and error logs for debugging
            # Uncomment below to auto-cleanup after reviewing
            # Remove-Item $entry.OutFile -ErrorAction SilentlyContinue
            # Remove-Item "$($entry.OutFile).err" -ErrorAction SilentlyContinue

            $activeUploads.Remove($procId)
        }
    }

    Start-Sleep -Seconds 10
}

Write-Log "========================================="
Write-Log "===== Upload Queue Complete ====="
$queueEndTime = Get-Date
$queueDurationSec = [math]::Max(1, ($queueEndTime - $queueStartTime).TotalSeconds)
$queueDurationText = Format-Duration $queueDurationSec
Write-Log "Total: $total | Completed: $completed | Failed: $failed | Elapsed: $queueDurationText"
Write-Log "========================================="
if ($failed -gt 0) {
    Write-Log "Check error logs in: $logDir"
    Write-Log "Run: aws sts get-caller-identity (to verify AWS credentials are working)"
    Write-Log "Run: aws s3 ls $bucket (to test bucket access)"
}
