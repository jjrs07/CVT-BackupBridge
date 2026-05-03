# S3 Multi-Threaded Backup Downloader
# Description: Discovers backup files in an AWS S3 bucket and downloads them to a local directory.
# Supports multi-threaded processing, automatic directory creation, and retries.

# ============================================================
# CONFIGURATION
# ============================================================
$bucket         = "<Input your S3 bucket name here, e.g. s3://my-backups>"
$region         = "<Input your AWS region here, e.g. us-east-1>"
$maxJobs        = 4
$localBackupDir = "<Input your local restore root path here, e.g. H:\SQLRestore>"
$logFile        = "<Input your log file path here, e.g. C:\Logs\S3Download.log>"

# ============================================================
# INITIALIZATION
# ============================================================

# Discover objects in the S3 bucket recursively
$s3Objects = aws s3 ls $bucket --recursive | 
    Where-Object { $_ -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\s+\d+\s+(.+)$' } | 
    ForEach-Object { $matches[1] }

if (-not $s3Objects) {
    Write-Host "No files found in S3 bucket $bucket"
    exit 1
}

# Create local directories if they don't exist
$logDir = Split-Path $logFile
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
if (-not (Test-Path $localBackupDir)) { New-Item -ItemType Directory -Path $localBackupDir -Force | Out-Null }

# Initialize log file
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

# ============================================================
# PROCESSING QUEUE
# ============================================================

$downloadStartTime = Get-Date

Write-Log "===== S3 Download Queue Started ====="
Write-Log "Total files to download: $($s3Objects.Count)"
Write-Log "Max simultaneous downloads: $maxJobs"
Write-Log "Source bucket: $bucket"
Write-Log "Local destination: $localBackupDir"
Write-Log "========================================="

# Build queue with file metadata and ensure local subdirectories exist
$queue = [System.Collections.Queue]::new()
foreach ($s3File in $s3Objects) {
    $localPath = Join-Path $localBackupDir $s3File
    $localDir  = Split-Path $localPath -Parent
    if (-not (Test-Path $localDir)) { New-Item -ItemType Directory -Path $localDir -Force | Out-Null }
    
    $queue.Enqueue(@{ 
        S3File    = $s3File
        LocalPath = $localPath
        Retries   = 0 
    })
}

$activeDownloads = @{}
$completed       = 0
$failed          = 0
$total           = $s3Objects.Count
$maxRetries      = 3

while ($queue.Count -gt 0 -or $activeDownloads.Count -gt 0) {

    # Start new download jobs
    while ($activeDownloads.Count -lt $maxJobs -and $queue.Count -gt 0) {
        $item      = $queue.Dequeue()
        $s3File    = $item.S3File
        $localPath = $item.LocalPath
        $retries   = $item.Retries
        $fileName  = Split-Path $s3File -Leaf
        $outFile   = "$logDir\$fileName.log"

        # Execute AWS CLI download process
        # Multipart downloads are handled automatically by AWS CLI for large files
        $proc = Start-Process -FilePath "aws" `
            -ArgumentList "s3 cp `"$bucket$s3File`" `"$localPath`" --quiet --region $region" `
            -RedirectStandardOutput $outFile `
            -RedirectStandardError "$outFile.err" `
            -NoNewWindow -PassThru

        $activeDownloads[$proc.Id] = @{
            Process   = $proc
            S3File    = $s3File
            LocalPath = $localPath
            StartTime = Get-Date
            OutFile   = $outFile
            Retries   = $retries
        }
        
        $retryLabel = if ($retries -gt 0) { " (Retry $retries/$maxRetries)" } else { "" }
        Write-Log "STARTED  | $s3File (PID: $($proc.Id))$retryLabel | Queue remaining: $($queue.Count)"
    }

    # Monitor active jobs
    foreach ($procId in @($activeDownloads.Keys)) {
        $entry = $activeDownloads[$procId]
        $proc  = $entry.Process

        if ($proc.HasExited) {
            $endTime     = Get-Date
            $durationSec = [math]::Max(1, ($endTime - $entry.StartTime).TotalSeconds)
            $mbps        = ""
            $downloadSuccess = $false

            # Success Verification
            if ((Test-Path $entry.LocalPath) -and (Get-Item $entry.LocalPath).Length -gt 0) {
                $downloadSuccess = $true
                $fileSize = [math]::Round((Get-Item $entry.LocalPath).Length / 1GB, 2)
                $mbps = [math]::Round(($fileSize * 1024 * 8) / $durationSec, 1)
            }

            if ($downloadSuccess) {
                $completed++
                $durationText = Format-Duration $durationSec
                $fileSize = [math]::Round((Get-Item $entry.LocalPath).Length / 1GB, 2)
                Write-Log "COMPLETE | $($entry.S3File) | Size: $fileSize GB | Duration: $durationText | Avg Speed: $mbps Mbps | Progress: $completed/$total"
            } else {
                # Failure Handling and Error Extraction
                $errOutput = ""
                if (Test-Path "$($entry.OutFile).err") {
                    $errOutput = Get-Content "$($entry.OutFile).err" -Raw | ForEach-Object { $_.Trim() }
                }
                if (-not $errOutput -and (Test-Path "$($entry.OutFile)")) {
                    $errOutput = Get-Content "$($entry.OutFile)" -Raw | ForEach-Object { $_.Trim() }
                }
                if (-not $errOutput) { $errOutput = "Exit code: $($proc.ExitCode)" }
                
                if ($entry.Retries -lt $maxRetries) {
                    $nextRetry = $entry.Retries + 1
                    Write-Log "RETRYING | $($entry.S3File) | Attempt $nextRetry/$maxRetries | Error: $errOutput"
                    $queue.Enqueue(@{ 
                        S3File    = $entry.S3File
                        LocalPath = $entry.LocalPath
                        Retries   = $nextRetry 
                    })
                } else {
                    $failed++
                    $durationText = Format-Duration $durationSec
                    Write-Log "FAILED   | $($entry.S3File) | Duration: $durationText | Max retries reached | Error: $errOutput"
                    
                    # Cleanup incomplete file
                    if (Test-Path $entry.LocalPath) {
                        Remove-Item $entry.LocalPath -Force -ErrorAction SilentlyContinue
                    }
                }
            }

            $activeDownloads.Remove($procId)
        }
    }

    Start-Sleep -Seconds 10
}

# ============================================================
# FINAL REPORTING
# ============================================================

Write-Log "========================================="
Write-Log "===== Download Queue Complete ====="
$downloadEndTime     = Get-Date
$downloadDurationSec = [math]::Max(1, ($downloadEndTime - $downloadStartTime).TotalSeconds)
$downloadDurationText = Format-Duration $downloadDurationSec
Write-Log "Total: $total | Completed: $completed | Failed: $failed | Elapsed: $downloadDurationText"
Write-Log "Files saved to: $localBackupDir"
Write-Log "========================================="

if ($failed -gt 0) {
    Write-Log "Check individual log files in: $logDir"
    Write-Log "Diagnostics: Run 'aws sts get-caller-identity' to verify AWS credentials."
}
