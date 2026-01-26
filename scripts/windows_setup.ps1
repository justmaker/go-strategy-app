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

# 5. Config Flutter
Write-Host "Configuring Flutter..."
# We need to refresh path again or call full path, but usually choco handles it.
# Might need a restart of shell.
# Let's try to assume flutter is in path after shell restart, or user handles it.

Write-Host "----------------------------------------------------------------"
Write-Host "Setup script commands completed."
Write-Host "Please RESTART your Windows VM or log out/in to apply PATH changes."
Write-Host "After restart, open a terminal and run:"
Write-Host "  flutter doctor"
Write-Host "To verify installation."
Write-Host "----------------------------------------------------------------"
