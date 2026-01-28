# Go Strategy App - Windows Sync Script
# Purpose: Sync Flutter project from shared folder (Z:) to local drive (C:) 
# and exclude unnecessary platform directories to save space and avoid errors.

# 1. Setup paths
# Source is where this script is located
$sourceDir = $PSScriptRoot
# Destination on local C: drive
$destDir = "C:\src\go-strategy-app\mobile"

# 2. Define excluded directories
$excludeDirs = @(
    "ios", 
    "macos", 
    "android", 
    ".dart_tool", 
    "build", 
    ".git", 
    ".idea", 
    ".vscode",
    "windows\build"
)

Write-Host "----------------------------------------------------" -ForegroundColor Cyan
Write-Host "Starting sync to local disk (C:)..." -ForegroundColor Cyan
Write-Host "Source: $sourceDir"
Write-Host "Dest:   $destDir"
Write-Host "Excluding: $($excludeDirs -join ', ')" -ForegroundColor Yellow
Write-Host "----------------------------------------------------"

# 3. Ensure destination directory exists
if (-not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
}

# 4. Execute sync using robocopy
# /E   : Copy subdirectories (including empty ones)
# /XO  : Exclude Older files (only update modified files)
# /XD  : Exclude Directories
# /NP  : No Progress (cleaner logs)
# /R:3 : Retry 3 times on failure
# /W:5 : Wait 5 seconds between retries
# /MT:8: Multi-threaded (8 threads) for speed
robocopy $sourceDir $destDir /E /XO /XD $excludeDirs /NP /R:3 /W:5 /MT:8

Write-Host "`nSync Completed!" -ForegroundColor Green
Write-Host "You can now go to $destDir and run 'flutter build windows'." -ForegroundColor White
Write-Host "----------------------------------------------------"
