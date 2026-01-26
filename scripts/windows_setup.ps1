# Windows Development Environment Setup Script for Go Strategy App
# Run this script inside your Windows 11 VM as Administrator (PowerShell)

Write-Host "Setting up Windows Development Environment..." -ForegroundColor Cyan

# 1. Install Chocolatey (Package Manager)
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
} else {
    Write-Host "Chocolatey already installed."
}

# Refresh env vars
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# 2. Install Git
Write-Host "Installing Git..."
choco install git -y

# 3. Install Flutter
Write-Host "Installing Flutter..."
choco install flutter -y

# 4. Install Visual Studio 2022 Community with C++ Workload
# This is the heavy part. We need the "Desktop development with C++" workload.
Write-Host "Installing Visual Studio 2022 Community with C++ Desktop Workload..."
choco install visualstudio2022community -y --package-parameters "--add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended --passive --norestart"

# 5. Install KataGo for Windows
Write-Host "Setting up KataGo for Windows..."
$katagoDir = "C:\Program Files\KataGo"
if (-not (Test-Path $katagoDir)) {
    New-Item -ItemType Directory -Path $katagoDir -Force | Out-Null
}

$katagoVersion = "v1.15.3"
# Use OpenCL version for Windows if GPU is available (even virtualized ones might support it)
# Or use Eigen for compatibility
$katagoZips = @{
    "OpenCL" = "katago-$katagoVersion-opencl-windows-x64.zip";
    "Eigen"  = "katago-$katagoVersion-eigen-windows-x64.zip"
}

# Default to Eigen for VM compatibility
$selectedZip = $katagoZips["Eigen"]
$katagoUrl = "https://github.com/lightvector/KataGo/releases/download/$katagoVersion/$selectedZip"
$zipPath = "$env:TEMP\katago.zip"

Write-Host "Downloading KataGo ($selectedZip)..."
Invoke-WebRequest -Uri $katagoUrl -OutFile $zipPath

Write-Host "Extracting KataGo..."
Expand-Archive -Path $zipPath -DestinationPath "$katagoDir\temp" -Force
$extractedFolder = Get-ChildItem -Path "$katagoDir\temp" -Directory | Select-Object -First 1
if ($extractedFolder) {
    Get-ChildItem -Path $extractedFolder.FullName | Move-Item -Destination $katagoDir -Force
} else {
    Get-ChildItem -Path "$katagoDir\temp" | Move-Item -Destination $katagoDir -Force
}
Remove-Item "$katagoDir\temp" -Recurse -Force
Remove-Item $zipPath

# 6. Download Neural Network Model
Write-Host "Downloading Neural Network Model..."
$modelName = "kata1-b18c384nbt-s9996604416-d4316597426.bin.gz"
$modelUrl = "https://media.katagotraining.org/uploaded/networks/models/kata1/$modelName"
$modelPath = "$katagoDir\default_model.bin.gz"

if (-not (Test-Path $modelPath)) {
    Invoke-WebRequest -Uri $modelUrl -OutFile $modelPath
}

# 7. Config Flutter
Write-Host "Configuring Flutter..."
# Assuming flutter is in path after refresh or next login.

Write-Host "----------------------------------------------------------------"
Write-Host "Setup script commands completed."
Write-Host "Please RESTART your Windows VM or log out/in to apply PATH changes."
Write-Host "After restart, open a terminal and run:"
Write-Host "  flutter doctor"
Write-Host "To verify installation."
Write-Host "----------------------------------------------------------------"
