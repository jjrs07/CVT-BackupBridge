# S3 Upload Queue - Max 3 Simultaneous Uploads
# Usage: Edit the $files array with your file paths then run the script

$bucket  = "s3://aucera-db-backups-10234/"
$maxJobs = 3
$logFile = "C:\s3_logs\s3-upload-log.txt"

# ============================================================
# ADD YOUR FILES HERE
# ============================================================
$files = @(
    "D:\backup\Aurora1_0416.bak",
    "D:\backup\Aurora2_0416.bak",
    "D:\backup\Aurora3_0416.bak",
    "D:\backup\Aurora4_0416.bak",
    "D:\backup\Aurora5_0416.bak",
    "E:\backup\Aurora6_0416.bak",
    "E:\backup\Aurora7_0416.bak",
    "E:\backup\Aurora8_0416.bak",
    "F:\backup\Aurora9_0416.bak",
    "F:\backup\Aurora10_0416.bak",
    "G:\backup\Aurora11_0416.bak",
    "T:\backup\Aurora12_0416.bak"
)

# ============================================================
# SCRIPT - Do not modify below this line
# ============================================================

# Create log directory if it doesn't exist
$logDir = Split-Path $logFile
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] $Message"
    Write-Host $entry
    Add-Content -Path $logFile -Value $entry
}

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

        # Suppress InsecureRequestWarning from --no-verify-ssl
        $env:PYTHONWARNINGS = "ignore"
        $proc = Start-Process -FilePath "aws" `
            -ArgumentList "s3 cp `"$file`" $bucket --no-verify-ssl" `
            -RedirectStandardOutput $outFile `
            -RedirectStandardError "$outFile.err" `
            -NoNewWindow -PassThru

        $activeUploads[$proc.Id] = @{
            Process    = $proc
            File       = $file
            FileName   = $fileName
            FileSizeGB = $fileSize
            StartTime  = Get-Date
            OutFile    = $outFile
            Retries    = $retries
        }
        $retryLabel = if ($retries -gt 0) { " (Retry $retries/$maxRetries)" } else { "" }
        Write-Log "STARTED  | $fileName ($fileSize GB) (PID: $($proc.Id))$retryLabel | Queue remaining: $($queue.Count)"
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

            if ($proc.ExitCode -eq 0) {
                $completed++
                Write-Log "COMPLETE | $($entry.FileName) | Size: $($entry.FileSizeGB) GB | Duration: $duration mins | Avg Speed: $mbps Mbps | Progress: $completed/$total"
            } else {
                $errOutput = if (Test-Path "$($entry.OutFile).err") { Get-Content "$($entry.OutFile).err" -Raw } else { "Unknown error" }
                if ($entry.Retries -lt $maxRetries) {
                    $nextRetry = $entry.Retries + 1
                    Write-Log "RETRYING | $($entry.FileName) | Attempt $nextRetry/$maxRetries | Error: $errOutput"
                    $queue.Enqueue(@{ File = $entry.File; FileName = $entry.FileName; FileSizeGB = $entry.FileSizeGB; Retries = $nextRetry })
                } else {
                    $failed++
                    Write-Log "FAILED   | $($entry.FileName) | Duration: $duration mins | Max retries reached | Error: $errOutput"
                }
            }

            # Cleanup temp log files
            Remove-Item $entry.OutFile -ErrorAction SilentlyContinue
            Remove-Item "$($entry.OutFile).err" -ErrorAction SilentlyContinue

            $activeUploads.Remove($procId)
        }
    }

    Start-Sleep -Seconds 10
}

Write-Log "========================================="
Write-Log "===== Upload Queue Complete ====="
Write-Log "Total: $total | Completed: $completed | Failed: $failed"
Write-Log "========================================="
