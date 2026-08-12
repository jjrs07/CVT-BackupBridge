# S3 Backup Validation Script
# Description: Compares a source backup directory with a target restore directory to verify 
# that all files were transferred correctly and that their sizes match.

# ============================================================
# CONFIGURATION LOADING
# ============================================================
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptPath "..\settings.json"

if (Test-Path $configPath) {
    $config = Get-Content $configPath | ConvertFrom-Json
    $Source = $config.BackupRootPath
    $Target = $config.RestoreRootPath
} else {
    Write-Error "Configuration file not found at $configPath. Please copy settings.json.template to settings.json and update it."
    exit 1
}

# ============================================================
# UTILITY FUNCTIONS
# ============================================================

function Write-ValidationResult {
    param(
        [string]$Message,
        [ConsoleColor]$Color = "White"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

# ============================================================
# INITIALIZATION & PRE-FLIGHT CHECKS
# ============================================================

Write-ValidationResult "Starting validation comparison..." "Cyan"
Write-ValidationResult "Source: $Source"
Write-ValidationResult "Target: $Target"

# Verify that both paths exist
if (!(Test-Path $Source)) {
    Write-ValidationResult "ERROR: Source path not found: $Source" "Red"
    exit 1
}

if (!(Test-Path $Target)) {
    Write-ValidationResult "ERROR: Target path not found: $Target" "Red"
    exit 1
}

# Recursively discover files in both directories
$SourceFiles = @(Get-ChildItem -LiteralPath $Source -Recurse -File | Where-Object { $_.Extension -in @('.bak', '.trn') })
$TargetFiles = @(Get-ChildItem -LiteralPath $Target -Recurse -File | Where-Object { $_.Extension -in @('.bak', '.trn') })

# Check for empty directories
if ($SourceFiles.Count -eq 0) {
    Write-ValidationResult "ERROR: No .bak or .trn files found in source directory." "Red"
    exit 1
}

if ($TargetFiles.Count -eq 0) {
    Write-ValidationResult "ERROR: No .bak or .trn files found in target directory." "Red"
    exit 1
}

# ============================================================
# COMPARISON LOGIC
# ============================================================

Write-ValidationResult "Comparing $($SourceFiles.Count) source files against $($TargetFiles.Count) target files..."

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
# RESULTS REPORTING
# ============================================================

Write-ValidationResult "=========================================" "Cyan"

if ($null -eq $Diff) {
    Write-ValidationResult "SUCCESS: Source and Target directories are identical." "Green"
    Write-ValidationResult "Verification completed: All backup files match in path and size." "Green"
    exit 0
}
else {
    Write-ValidationResult "WARNING: Differences detected between source and target." "Yellow"
    
    # Beautify the difference output
    $Diff | Select-Object @{N='Difference';E={if($_.SideIndicator -eq '<='){'Missing in Target'}else{'Extra in Target'}}}, RelativePath, @{N='Size(Bytes)';E={$_.Length}} | Format-Table -AutoSize
    
    Write-ValidationResult "Validation failed: Some backup files are missing, extra, or have size discrepancies." "Red"
    Write-ValidationResult "=========================================" "Cyan"
    exit 2
}
