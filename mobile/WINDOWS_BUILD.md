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
   - **注意**: 若直接在 UTM 的共用資料夾 (`Z:`) 建置，會因為 `ERROR_INVALID_FUNCTION` (符號連結限制) 而失敗。
   - **首次複製**:
     ```powershell
     mkdir C:\src
     xcopy /E /I Z:\go-strategy-app C:\src\go-strategy-app
     ```
   - **後續更新 (差異同步 - 推薦!)**:
     使用 `robocopy` 僅同步有變動的檔案（類似 rsync）：
     ```powershell
     robocopy Z:\go-strategy-app C:\src\go-strategy-app /E /XO /NP /R:3 /W:5
     ```
   - 進入本地目錄進行後續操作：
     ```powershell
     cd C:\src\go-strategy-app\mobile
     ```

4. **重啟環境**:
   - 建議重新開機，確保 `flutter` 指令與編譯器環境變數生效。

## 3. 編譯 Windows 版本

1. **進入本地專案目錄**:
   ```powershell
   cd C:\src\go-strategy-app\mobile
   ```

2. **取得依賴套件**:
   ```powershell
   flutter pub get
   ```

3. **執行建置**:
   ```powershell
   flutter build windows --release
   ```

## 4. 產出位置

編譯成功的執行檔將位於：
`C:\src\go-strategy-app\mobile\build\windows\x64\runner\Release`

您可以將整個 `Release` 資料夾複製回 `Z:` 槽，以便在 Mac 端存取。

---

## 常見問題 (Troubleshooting)

### Q: 出現 `ERROR_INVALID_FUNCTION`
A: 這通常是因為在網路驅動器 (Shared Folders) 上執行建置。請依照上述步驟將專案搬移至 `C:` 磁碟本地路徑再建置。

### Q: 出現 Permissions/Security 錯誤
A: 請務必以 **管理員身分** 執行 PowerShell，並使用 `-ExecutionPolicy Bypass` 參數。

### Q: Flutter 命令找不到
A: 腳本會安裝 Flutter 到 `C:\src\flutter`。如果找不到指令，請手動確認各項路徑是否已加入系統的 PATH 環境變數中。
