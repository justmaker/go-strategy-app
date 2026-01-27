# Go Strategy App - Windows Build Guide (UTM/VM)

由於 Flutter 的 Windows 應用程式必須在 Windows 系統上建置，如果您使用的是 macOS，建議使用 **UTM** 建立 Windows 11 ARM64 虛擬機來進行開發與編譯。

## 1. 虛擬機安裝環境 (UTM)

1. **下載 ISO**: 從微軟官網下載 [Windows 11 ARM64 ISO](https://www.microsoft.com/software-download/windows11arm64)。
2. **建立虛擬機**: 
   - UTM -> Create New -> Virtualize -> Windows -> 選擇 ISO。
   - **重要**: 勾選 "Install drivers and SPICE tools"。
3. **完成安裝**: 進入 Windows 桌面並確保網路連線正常。

## 2. 自動化環境配置

進入 Windows 桌面後，請執行以下步驟：

1. **以管理員身分開啟 PowerShell**:
   - 在開始選單搜尋 `PowerShell`，右鍵點擊 **「以系統管理員身分執行」**。

2. **取得專案代碼**:
   - 如果您有掛載共用的資料夾 (Shared Directory)，直接進入該目錄。
   - 或者使用 Git 複製：
     ```powershell
     git clone https://github.com/justmaker/go-strategy-app.git
     cd go-strategy-app
     ```

3. **執行環境配置腳本**:
   ```powershell
   cd scripts
   PowerShell -ExecutionPolicy Bypass -File .\windows_setup.ps1
   ```
   *此腳本會自動安裝：Git, Flutter SDK, Visual Studio Build Tools, 以及 Windows 版 KataGo。*

4. **重啟環境**:
   - 關閉 PowerShell 並重新開啟（或重新開機），確保環境變數生效。

## 3. 編譯 Windows 版本

1. **進入 Flutter 目錄**:
   ```powershell
   cd mobile
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
`mobile\build\windows\x64\runner\Release`

您可以將整個 `Release` 資料夾壓縮後發布給其他 Windows 使用者。

---

## 常見問題 (Troubleshooting)

### Q: 出現 Permissions/Security 錯誤
A: 請務必以 **管理員身分** 執行 PowerShell，並使用 `-ExecutionPolicy Bypass` 參數。

### Q: Flutter 命令找不到
A: 腳本會安裝 Flutter 到 `C:\src\flutter`。如果找不到指令，請手動確認各項路徑是否已加入系統的 PATH 環境變數中。
