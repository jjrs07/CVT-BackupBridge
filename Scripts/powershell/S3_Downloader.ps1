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

# ============================================================
# INITIALIZATION
# ============================================================

# Discover objects in the S3 bucket recursively
$s3Objects = aws s3 ls $bucket --recursive | 
    Where-Object { $_ -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\s+\d+\s+(.+)$' } | 
    ForEach-Object { $matches[1] }

if (-not $s3Objects) {
    Write-Log "No files found in S3 bucket $bucket"
    exit 1
}

# Initialize log file
if (Test-Path $logFile) { Remove-Item $logFile -Force }

# Ensure local restore root exists
if (-not (Test-Path $localBackupDir)) { New-Item -ItemType Directory -Path $localBackupDir -Force | Out-Null }

# ============================================================
# PROCESSING QUEUE SETUP
# ============================================================

$downloadStartTime = Get-Date
$total             = $s3Objects.Count
$completed         = 0
$failed            = 0
$maxRetries        = 3
$activeDownloads   = @{}

Write-Log "===== S3 Download Queue Started ====="
Write-Log "Total files to download: $total"
Write-Log "Max simultaneous downloads: $maxJobs"
Write-Log "Source bucket: $bucket"
Write-Log "Local destination: $localBackupDir"
Write-Log "========================================="

# Build queue and ensure local subdirectories exist
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

# ============================================================
# MAIN EXECUTION LOOP
# ============================================================

while ($queue.Count -gt 0 -or $activeDownloads.Count -gt 0) {

    # 1. Start new download jobs up to $maxJobs
    while ($activeDownloads.Count -lt $maxJobs -and $queue.Count -gt 0) {
        $item     = $queue.Dequeue()
        $fileName = Split-Path $item.S3File -Leaf
        $outFile  = Join-Path (Split-Path $logFile) "$fileName.log"

        # Prepare AWS CLI arguments
        $s3Args = @(
            "s3", "cp", 
            "$bucket$($item.S3File)", 
            $item.LocalPath, 
            "--quiet", 
            "--region", $region
        )

        $startParams = @{
            FilePath               = "aws"
            ArgumentList           = $s3Args
            RedirectStandardOutput = $outFile
            RedirectStandardError  = "$outFile.err"
            NoNewWindow            = $true
            PassThru               = $true
        }

        # Start background download
        $proc = Start-Process @startParams

        $activeDownloads[$proc.Id] = @{
            Process   = $proc
            S3File    = $item.S3File
            LocalPath = $item.LocalPath
            StartTime = Get-Date
            OutFile   = $outFile
            Retries   = $item.Retries
        }
        
        $retryLabel = if ($item.Retries -gt 0) { " (Retry $($item.Retries)/$maxRetries)" } else { "" }
        Write-Log "STARTED  | $($item.S3File) (PID: $($proc.Id))$retryLabel"
    }

    # 2. Monitor and reap finished jobs
    foreach ($procId in @($activeDownloads.Keys)) {
        $entry = $activeDownloads[$procId]
        $proc  = $entry.Process

        if ($proc.HasExited) {
            $durationSec = [math]::Max(1, ((Get-Date) - $entry.StartTime).TotalSeconds)
            $downloadSuccess = $false

            # Verification: Check if file exists and has content
            if ((Test-Path $entry.LocalPath) -and (Get-Item $entry.LocalPath).Length -gt 0) {
                $downloadSuccess = $true
            }

            if ($downloadSuccess) {
                $completed++
                $fileSize = [math]::Round((Get-Item $entry.LocalPath).Length / 1GB, 2)
                $mbps     = [math]::Round(($fileSize * 1024 * 8) / $durationSec, 1)
                Write-Log "COMPLETE | $($entry.S3File) | Size: $fileSize GB | Duration: $(Format-Duration $durationSec) | Speed: $mbps Mbps | Progress: $completed/$total"
            } else {
                # Handle failure and extract error messages
                $errFile = "$($entry.OutFile).err"
                $errOutput = if (Test-Path $errFile) { Get-Content $errFile -Raw | ForEach-Object { $_.Trim() } } else { "Exit code: $($proc.ExitCode)" }
                
                if ($entry.Retries -lt $maxRetries) {
                    Write-Log "RETRYING | $($entry.S3File) | Attempt $($entry.Retries + 1)/$maxRetries | Error: $errOutput"
                    $queue.Enqueue(@{ 
                        S3File    = $entry.S3File
                        LocalPath = $entry.LocalPath
                        Retries   = $entry.Retries + 1 
                    })
                } else {
                    $failed++
                    Write-Log "FAILED   | $($entry.S3File) | Max retries reached | Error: $errOutput"
                    
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

$totalDurationSec = [math]::Max(1, ((Get-Date) - $downloadStartTime).TotalSeconds)
Write-Log "========================================="
Write-Log "===== Download Queue Complete ====="
Write-Log "Total: $total | Completed: $completed | Failed: $failed | Elapsed: $(Format-Duration $totalDurationSec)"
Write-Log "Files saved to: $localBackupDir"
Write-Log "========================================="

if ($failed -gt 0) {
    Write-Log "Check individual log files in: $(Split-Path $logFile)"
    Write-Log "Diagnostics: Run 'aws sts get-caller-identity' to verify AWS credentials."
}
