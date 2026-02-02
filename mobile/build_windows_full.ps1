# Go Strategy App - Integrated Windows Build Script
# This script automates: Sync -> Build -> Package -> Copy back to Z:

# 1. Setup paths
$sourceDir = $PSScriptRoot
$localDir = "C:\src\go-strategy-app\mobile"
$releaseDir = "$localDir\build\windows\x64\runner\Release"
$sharedOutputDir = "Z:\go-strategy-app\mobile\build"
$zipName = "windows-app.zip"
$tempZipPath = "$localDir\$zipName"

$excludeDirs = @("ios", "macos", "android", ".dart_tool", "build", ".git", ".idea", ".vscode")

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   Windows Automated Build Process Starting..." -ForegroundColor Cyan
Write-Host "===================================================="

# --- STEP 1: SYNC FROM SHARED TO LOCAL ---
Write-Host "`n[1/3] Syncing project to local C: drive..." -ForegroundColor Yellow
if (-not (Test-Path $localDir)) { New-Item -ItemType Directory -Path $localDir -Force | Out-Null }
robocopy $sourceDir $localDir /E /XO /XD $excludeDirs /NP /R:3 /W:5 /MT:8

# --- STEP 2: RUN FLUTTER BUILD ---
Write-Host "`n[2/3] Building Windows Application..." -ForegroundColor Yellow
Set-Location $localDir
flutter pub get
flutter build windows --release

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nError: Flutter build failed!" -ForegroundColor Red
    exit $LASTEXITCODE
}

# --- STEP 3: PACKAGE AND COPY BACK ---
Write-Host "`n[3/3] Packaging and copying back to Z: drive..." -ForegroundColor Yellow

# Create shared output dir if missing
if (-not (Test-Path $sharedOutputDir)) { New-Item -ItemType Directory -Path $sharedOutputDir -Force | Out-Null }

# Remove old zip
if (Test-Path $tempZipPath) { Remove-Item $tempZipPath -Force }

# Zip it
Write-Host "Zipping release files..."
Compress-Archive -Path "$releaseDir\*" -DestinationPath $tempZipPath -Force

# Copy back
Write-Host "Moving zip to $sharedOutputDir..."
Copy-Item -Path $tempZipPath -Destination "$sharedOutputDir\$zipName" -Force

Write-Host "`n====================================================" -ForegroundColor Green
Write-Host "   Build successful! Output: mobile/build/$zipName" -ForegroundColor Green
Write-Host "===================================================="
