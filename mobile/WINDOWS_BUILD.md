# Go Strategy App - Windows Build Guide (UTM/VM)

由於 Flutter 的 Windows 應用程式必須在 Windows 系統上建置，如果您使用的是 macOS，建議使用 **UTM** 建立 Windows 11 ARM64 虛擬機來進行開發與編譯。

## 1. 虛擬機安裝環境 (UTM)

1. **下載 ISO**: 從微軟官網下載 [Windows 11 ARM64 ISO](https://www.microsoft.com/software-download/windows11arm64)。
2. **建立虛擬機**: 
   - UTM -> Create New -> Virtualize -> Windows -> 選擇 ISO。
   - **重要**: 勾選 "Install drivers and SPICE tools"。
3. **完成安裝**: 進入 Windows 桌面並確保網路連線正常。

## 2. 自動化環境配置與專案下載

進入 Windows 桌面後，請依照以下順序操作：

1. **以管理員身分開啟 PowerShell**:
   - 在開始選單搜尋 `PowerShell`，右鍵點擊 **「以系統管理員身分執行」**。

2. **執行環境配置腳本**:
   - 首先進入共用資料夾（例如 `Z:\go-strategy-app\scripts`）執行配置：
   ```powershell
   cd Z:\go-strategy-app\scripts
   PowerShell -ExecutionPolicy Bypass -File .\windows_setup.ps1
   ```
   *此腳本會自動安裝：Git, Flutter SDK, Visual Studio Build Tools, 以及 Windows 版 KataGo。*

3. **搬移專案至本地磁碟 (C 槽) - 重要!**:
   - **注意**: 若直接在 UTM 的共用資料夾 (`Z:`) 建置，會因為檔案系統限制而失敗。
   - **使用腳本同步 (推薦 - 已排掉 iOS/Android 等無效檔案)**:
     在虛擬機內開啟 PowerShell，進入 `Z:` 槽的 mobile 目錄執行：
     ```powershell
     cd Z:\go-strategy-app\mobile
     PowerShell -ExecutionPolicy Bypass -File .\sync_windows.ps1
     ```
   - 進入本地目錄進行後續操作：
     ```powershell
     cd C:\src\go-strategy-app\mobile
     ```

4. **重啟環境**:
   - 建議重新開機，確保 `flutter` 指令與編譯器環境變數生效。

## 3. 編譯 Windows 版本 (全自動版 - 推薦)

在虛擬機中直接執行以下指令，即可完成「同步、編譯、打包」所有步驟：
```powershell
cd Z:\go-strategy-app\mobile
PowerShell -ExecutionPolicy Bypass -File .\build_windows_full.ps1
```

編譯完成後的 `.zip` 檔會自動出現在 Mac 端的 `mobile/build/windows-app.zip`。

---

## 4. 手動編譯步驟 (若自動腳本失敗時使用)

1. **同步專案**:
   ```powershell
   PowerShell -ExecutionPolicy Bypass -File .\sync_windows.ps1
   ```

2. **進入本地專案目錄並編譯**:
   ```powershell
   cd C:\src\go-strategy-app\mobile
   flutter build windows --release
   ```

3. **打包成果**:
   ```powershell
   PowerShell -ExecutionPolicy Bypass -File .\release_windows.ps1
   ```

---

## 常見問題 (Troubleshooting)

### Q: 出現 `ERROR_INVALID_FUNCTION`
A: 這通常是因為在網路驅動器 (Shared Folders) 上執行建置。請依照上述步驟將專案搬移至 `C:` 磁碟本地路徑再建置。

### Q: 出現 Permissions/Security 錯誤
A: 請務必以 **管理員身分** 執行 PowerShell，並使用 `-ExecutionPolicy Bypass` 參數。

### Q: Flutter 命令找不到
A: 腳本會安裝 Flutter 到 `C:\src\flutter`。如果找不到指令，請手動確認各項路徑是否已加入系統的 PATH 環境變數中。
