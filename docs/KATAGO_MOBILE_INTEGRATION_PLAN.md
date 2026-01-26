# KataGo 行動版整合計畫 (Mobile Integration Plan)

> **目標**: 將 KataGo 圍棋引擎整合至 Flutter App (Android/iOS) 中，實現完全斷網、獨立運作的 AI 分析功能。

---

## 📅 階段一：準備工作 (Preparation)

- [ ] **選定 KataGo 版本**
  - 建議使用 [lightvector/KataGo](https://github.com/lightvector/KataGo) 的最新穩定版原始碼。
  - 需要針對移動端進行裁減 (移除不必要的 Training 代碼，僅保留 GTP/Analysis 引擎)。
- [ ] **選擇神經網路模型 (Model Selection)**
  - 移動端算力有限，需選擇輕量化模型 (如 15b 或 18b block network)，或經量化的版本 (Quantized)。
  - 檔案需放入 `assets/katago/`。
- [ ] **評估運算後端 (Backend Backend)**
  - **Android**: 優先嘗試 OpenCL (若 GPU 支援) 或 Eigen (純 CPU，相容性高但較慢)。
  - **iOS**: 強烈建議支援 Apple Metal (以此獲得合理效能)，或 OpenCL。

---

## 🤖 階段二：Android 整合 (NDK)

- [ ] **配置 CMake 建置系統**
  - 在 `android/app/` 下建立 `CMakeLists.txt`。
  - 引入 KataGo C++ 原始碼 dependency。
  - 設定編譯參數 (Flags): `-DUSE_BACKEND=OPENCL` or `EIGEN`。
- [ ] **實作 JNI 介面 (Java Native Interface)**
  - 建立 `native-lib.cpp`。
  - 撰寫 C++ 函數對接 `KataGoEngine` (初始化、載入模型、輸入指令)。
  - 處理 stdout/stderr 輸出重導向 (Redirect to Java Callback)。
- [ ] **修改 `build.gradle`**
  - 加入 `externalNativeBuild` 區塊指向 `CMakeLists.txt`。
  - 設定 `ndkVersion` 與 `abiFilters` (主要支援 `arm64-v8a`)。
- [ ] **更新 `KataGoEngine.kt`**
  - 將原本 `ProcessBuilder` (呼叫外部執行檔) 改為 JNI 呼叫 (直接呼叫 Library 函數)。
    - `external fun initKataGo(...)`
    - `external fun analyze(...)`

---

## 🍎 階段三：iOS 整合 (C++/Objective-C++)

- [ ] **建立 C++ Wrapper (.mm)**
  - `ios/Runner/` 中新增 Objective-C++ 檔案 (`KataGoWrapper.mm`)。
  - 用於橋接 Swift 與 KataGo C++ class。
- [ ] **編譯設定 (Build Settings)**
  - 啟用 C++ 17 或 newer 標準。
  - 修改 `Podfile` 或 Project Settings 以連結必要的 System Frameworks (Accelerate, Metal 等)。
- [ ] **實作 Swift Bridge**
  - 在 `AppDelegate.swift` 中呼叫 Wrapper。
  - 實作 MethodChannel `com.gostratefy.go_strategy_app/katago`。

---

## 📱 階段四：Flutter 端優化

- [ ] **模型管理**
  - App 首次啟動時，將 `assets/` 中的模型檔解壓縮至 `ApplicationDocumentsDirectory` (若是 JNI 直接讀取 Asset 可省略，但通常檔案路徑較穩)。
- [ ] **多執行緒管理 (Isolates)**
  - 確保長時間的 AI 思考不會阻塞 UI Thread。
- [ ] **電量與發熱控制**
  - 在 `analysis.cfg` 中調整 `numSearchThreads` (建議 1-2 threads 即可)。
  - 限制 `maxVisits` 預設值 (例如 50-100 visits) 以避免過度耗電。

---

## 🛠 測試與驗收

- [ ] **Android 模擬器測試** (x86_64 或 arm64) - *目前環境*。
- [ ] **Android 實機測試** (Google Pixel, Samsung 等)。
- [ ] **iOS 模擬器/實機測試**。
- [ ] **斷網測試**: 關閉網路，確認分析功能正常運作。

