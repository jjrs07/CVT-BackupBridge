$Source = "H:\SQLBackups"
$Target = "H:\SQLRestore"

if (!(Test-Path $Source)) {
    Write-Host "Source path not found: $Source" -ForegroundColor Red
    exit
}

if (!(Test-Path $Target)) {
    Write-Host "Target path not found: $Target" -ForegroundColor Red
    exit
}

$SourceFiles = Get-ChildItem $Source -Recurse -File
$TargetFiles = Get-ChildItem $Target -Recurse -File

if ($SourceFiles.Count -eq 0) {
    Write-Host "No files in source folder." -ForegroundColor Yellow
    exit
}

if ($TargetFiles.Count -eq 0) {
    Write-Host "No files in target folder." -ForegroundColor Yellow
    exit
}

$SourceList = $SourceFiles | ForEach-Object {
    [PSCustomObject]@{
        RelativePath = $_.FullName.Substring($Source.Length)
        Length = $_.Length
    }
}

$TargetList = $TargetFiles | ForEach-Object {
    [PSCustomObject]@{
        RelativePath = $_.FullName.Substring($Target.Length)
        Length = $_.Length
    }
}

$Diff = Compare-Object $SourceList $TargetList -Property RelativePath, Length

if ($Diff.Count -eq 0) {
    Write-Host "MATCH SUCCESS - folders identical" -ForegroundColor Green
}
else {
    Write-Host "Differences found:" -ForegroundColor Yellow
    $Diff | Format-Table
}