# Go Strategy App - Windows Packaging Script
# Purpose: Zip the Windows release build and copy it back to the shared Z: drive.

# 1. Setup paths
$releaseDir = "C:\src\go-strategy-app\mobile\build\windows\x64\runner\Release"
$sharedDir = "Z:\go-strategy-app\mobile\build"
$zipName = "windows-app.zip"
$tempZipPath = "C:\src\go-strategy-app\mobile\$zipName"

Write-Host "----------------------------------------------------" -ForegroundColor Cyan
Write-Host "Packaging Windows Release..." -ForegroundColor Cyan

# 2. Check if build exists
if (-not (Test-Path $releaseDir)) {
    Write-Host "Error: Build output not found at $releaseDir" -ForegroundColor Red
    Write-Host "Please run 'flutter build windows --release' first."
    exit
}

# 3. Create build directory on Z: if it doesn't exist
if (-not (Test-Path $sharedDir)) {
    New-Item -ItemType Directory -Path $sharedDir -Force | Out-Null
}

# 4. Remove old zip if exists
if (Test-Path $tempZipPath) { Remove-Item $tempZipPath -Force }

# 5. Zip the Release folder
Write-Host "Zipping Release folder to $zipName..." -ForegroundColor Yellow
Compress-Archive -Path "$releaseDir\*" -DestinationPath $tempZipPath -Force

# 6. Copy to Z: drive
Write-Host "Copying zip to shared folder (Z:)..." -ForegroundColor Yellow
Copy-Item -Path $tempZipPath -Destination "$sharedDir\$zipName" -Force

Write-Host "----------------------------------------------------" -ForegroundColor Green
Write-Host "Success! You can now find the zip on your Mac at:" -ForegroundColor White
Write-Host "mobile/build/$zipName" -ForegroundColor Green
Write-Host "----------------------------------------------------"
