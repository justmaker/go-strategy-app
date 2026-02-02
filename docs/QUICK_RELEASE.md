# 🚀 Quick Release Guide for Developers

**目標讀者:** 開發者  
**用途:** 修改程式碼後，快速發布全平台新版本的最少步驟

---

## ⚡ 最少步驟（5 分鐘內完成）

### Step 1: 確認程式碼沒問題
```bash
cd mobile
flutter analyze      # 應該顯示 0 issues
flutter test         # 應該全部 PASS
```

### Step 2: Commit 你的修改
```bash
git add -A
git commit -m "feat: 你的修改描述"
```

### Step 3: 升版號（擇一）
```bash
./version.sh bump patch   # 小修正: 1.0.0 → 1.0.1
./version.sh bump minor   # 新功能: 1.0.0 → 1.1.0
./version.sh bump major   # 大改版: 1.0.0 → 2.0.0
```

### Step 4: Commit 版號 & Push
```bash
git add pubspec.yaml
git commit -m "release: v$(grep 'version:' pubspec.yaml | cut -d' ' -f2 | cut -d'+' -f1)"
git push origin main
```

### Step 5: 一鍵建置全平台
```bash
./build_all.sh
```

---

## 📦 建置產物位置

| 平台 | 產物位置 | 用途 |
|------|----------|------|
| **Web** | `build/web/` | 部署至網頁伺服器 |
| **Android** | `build/app/outputs/flutter-apk/app-release.apk` | 直接安裝或上傳 Play Store |
| **iOS** | `build/ios/iphoneos/Runner.app` | 需透過 Xcode 打包 IPA |
| **macOS** | `build/macos/Build/Products/Release/go_strategy_app.app` | 直接執行或壓縮分發 |

---

## 🪟 Windows 版（需要 Windows 電腦或 VM）

由於 Flutter 的限制，Windows 版只能在 Windows 上建置。

### 使用 UTM 虛擬機 (macOS 上)
1. 開啟 UTM，啟動 Windows 11 VM
2. 在 VM 中開啟 PowerShell
3. 執行：
   ```powershell
   cd "Z:\mobile"   # 共享資料夾
   .\sync_windows.ps1
   ```
4. 取回建置產物：`Z:\windows-release.zip`

詳細說明請見 [mobile/WINDOWS_BUILD.md](mobile/WINDOWS_BUILD.md)

---

## ☁️ 發布 GitHub Release（Android）

```bash
cd mobile
./release_android.sh
```

這會自動：
1. 建置 Release APK
2. 建立 Git Tag
3. 上傳至 GitHub Releases

---

## 🔧 常用環境變數

如果遇到 Java 或 Android SDK 問題：
```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools
```

---

## ✅ Checklist（發布前確認）

- [ ] `flutter analyze` - 0 issues
- [ ] `flutter test` - All passed
- [ ] 版號已升級且 commit
- [ ] `git push` 完成
- [ ] 各平台建置成功

---

**最後更新:** 2026-01-28
