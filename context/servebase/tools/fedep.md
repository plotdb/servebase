# fedep - 前端依賴管理工具

## 概述

fedep 是一個前端套件管理工具，將 node_modules 中的套件複製到前端靜態資源目錄，供瀏覽器直接存取。

## 問題與解決方案

### 問題
- 前端需要使用 npm 套件
- node_modules 不適合直接暴露給瀏覽器
- 手動複製套件繁瑣且容易出錯

### 解決方案
fedep 自動化套件複製流程：
```
node_modules/
  └─ @plotdb/block/
        ↓ fedep
frontend/base/static/assets/lib/
  └─ @plotdb/block/
```

## 安裝與設定

### 安裝
```bash
npm install -g fedep
# 或在專案中
npm install --save-dev fedep
```

### 設定 package.json
```json
{
  "frontendDependencies": {
    "root": "frontend/base/static/assets/lib",
    "modules": [
      "bootstrap",
      "@plotdb/block",
      "@loadingio/ldquery",
      "ldview",
      "lderror"
    ]
  }
}
```

#### 設定欄位
- **root** - 前端套件目標目錄
- **modules** - 要複製的套件列表（套件名稱）

### 初始化
如果 package.json 尚未有 frontendDependencies 欄位：
```bash
fedep init
```

自動生成設定，包含所有 dependencies 和 devDependencies。

## 使用

### 複製所有套件
```bash
fedep
```

### 複製特定套件
```bash
fedep bootstrap
fedep @plotdb/block ldview
```

### 強制重新複製
```bash
fedep -f
fedep --force
```

## 運作原理

### 1. 讀取設定
從 package.json 讀取 frontendDependencies。

### 2. 解析套件路徑
```livescript
# 一般套件
bootstrap → node_modules/bootstrap

# scoped 套件
@plotdb/block → node_modules/@plotdb/block
```

### 3. 複製檔案
```livescript
# 保持目錄結構
node_modules/@plotdb/block/
├─ main/
│  ├─ index.js
│  └─ index.css
└─ package.json
    ↓
frontend/base/static/assets/lib/@plotdb/block/
├─ main/
│  ├─ index.js
│  └─ index.css
└─ package.json
```

### 4. 保留版本資訊
複製 package.json 以便查詢版本。

## 套件引用

### 在 bundle.json 中引用
```json
{
  "js": {
    "vendor": [
      "static/assets/lib/bootstrap/dist/js/bootstrap.min.js",
      "static/assets/lib/@plotdb/block/main/index.min.js"
    ]
  }
}
```

### 在 HTML 中引用
```html
<script src="/assets/lib/bootstrap/dist/js/bootstrap.min.js"></script>
<link rel="stylesheet" href="/assets/lib/bootstrap/dist/css/bootstrap.min.css">
```

### 在 Pug 中引用
```pug
script(src="/assets/lib/@plotdb/block/main/index.min.js")
link(rel="stylesheet" href="/assets/lib/@plotdb/block/main/index.min.css")
```

## 工作流程整合

### 開發流程
```bash
# 1. 安裝 npm 套件
npm install @plotdb/block

# 2. 加入 frontendDependencies
# （編輯 package.json）

# 3. 執行 fedep
fedep

# 4. 在 bundle.json 或 HTML 中引用
```

### 更新套件
```bash
# 1. 更新 npm 套件
npm update @plotdb/block

# 2. 重新複製
fedep @plotdb/block
```

### CI/CD 整合
```bash
# 在建置腳本中
npm install
fedep
npm run prebuild
```

## 進階使用

### 多個前端站點
可設定多個 root：
```json
{
  "frontendDependencies": {
    "targets": [
      {
        "root": "frontend/base/static/assets/lib",
        "modules": ["bootstrap", "ldview"]
      },
      {
        "root": "frontend/web/static/assets/lib",
        "modules": ["@plotdb/block", "lderror"]
      }
    ]
  }
}
```

### 選擇性複製
只複製套件的特定目錄或檔案：
```json
{
  "frontendDependencies": {
    "root": "frontend/base/static/assets/lib",
    "modules": [
      {
        "name": "bootstrap",
        "files": ["dist/css/**", "dist/js/**"]
      }
    ]
  }
}
```

（注意：此功能需確認 fedep 版本是否支援）

## 常見問題

### Q: 為什麼不直接使用 node_modules？
A:
- node_modules 包含大量開發用檔案
- 目錄結構複雜不適合前端
- 安全考量，避免暴露整個 node_modules

### Q: 如何更新已複製的套件？
A:
```bash
npm update package-name
fedep package-name
```

### Q: fedep 與 npm 套件管理器的關係？
A: fedep 不替代 npm，而是補充。npm 管理套件安裝，fedep 管理前端部署。

### Q: 支援哪些套件？
A: 所有 npm 套件，但主要針對前端套件（有 browser 可用檔案）。

## 替代方案

### Webpack/Rollup
打包工具可以直接從 node_modules import，但：
- 需要建置步驟
- 設定複雜
- fedep 更輕量適合簡單專案

### CDN
使用 CDN 載入套件，但：
- 依賴外部服務
- 網路延遲
- 版本控制問題

### 手動複製
可行但：
- 繁瑣易錯
- 難以維護
- fedep 自動化此流程

## 原始碼結構

### cli.js
命令列介面入口。

### lib/main.ls
主邏輯。

### lib/init.ls
初始化 frontendDependencies。

### lib/default.ls
預設設定。

### lib/load-cmds.ls
載入指令。

## 開發與貢獻

fedep 源碼位於獨立 repo，servebase 在 context/fedep 提供參考版本。

### 本地開發
```bash
cd context/fedep
npm install
npm link
```

### 測試
在專案中測試：
```bash
fedep
```

## 最佳實踐

### 精簡套件列表
只加入前端實際需要的套件。

### 定期更新
保持套件版本更新以獲得安全修正。

### 版本鎖定
使用 package-lock.json 鎖定版本。

### 文件化
在專案 README 說明使用的前端套件。

### .gitignore
考慮是否將 static/assets/lib 加入 .gitignore（通常不加入）。
