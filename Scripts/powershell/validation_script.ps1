# S3 Backup Validation Script
# Description: Compares a source backup directory with a target restore directory to verify 
# that all files were transferred correctly and that their sizes match.

# ============================================================
# CONFIGURATION
# ============================================================
$Source = "<Input your local backup source path here, e.g. H:\SQLBackups>"
$Target = "<Input your local restore target path here, e.g. H:\SQLRestore>"

# ============================================================
# INITIALIZATION & VALIDATION
# ============================================================

# Verify that both paths exist
if (!(Test-Path $Source)) {
    Write-Host "Source path not found: $Source" -ForegroundColor Red
    exit 1
}

if (!(Test-Path $Target)) {
    Write-Host "Target path not found: $Target" -ForegroundColor Red
    exit 1
}

# Recursively discover files in both directories
$SourceFiles = Get-ChildItem $Source -Recurse -File
$TargetFiles = Get-ChildItem $Target -Recurse -File

# Check for empty directories
if ($SourceFiles.Count -eq 0) {
    Write-Host "No files found in source directory." -ForegroundColor Yellow
    exit 0
}

if ($TargetFiles.Count -eq 0) {
    Write-Host "No files found in target directory." -ForegroundColor Yellow
    exit 0
}

# ============================================================
# COMPARISON LOGIC
# ============================================================

# Map files to objects using relative paths for accurate comparison
$SourceList = $SourceFiles | ForEach-Object {
    [PSCustomObject]@{
        RelativePath = $_.FullName.Substring($Source.Length)
        Length       = $_.Length
    }
}

$TargetList = $TargetFiles | ForEach-Object {
    [PSCustomObject]@{
        RelativePath = $_.FullName.Substring($Target.Length)
        Length       = $_.Length
    }
}

# Perform comparison based on path and file size
$Diff = Compare-Object $SourceList $TargetList -Property RelativePath, Length

# ============================================================
# RESULTS
# ============================================================

if ($null -eq $Diff) {
    Write-Host "SUCCESS: Source and Target directories are identical." -ForegroundColor Green
}
else {
    Write-Host "WARNING: Differences detected between source and target." -ForegroundColor Yellow
    $Diff | Format-Table -AutoSize
}
