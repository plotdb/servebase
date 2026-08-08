# @plotdb/srcbuild - 前端編譯工具

## 概述

srcbuild 是一個前端資源編譯與打包工具，專為 servebase 設計。負責編譯 LiveScript, Stylus, Pug 並管理資源打包。

## 核心功能

- **LiveScript 編譯** - .ls → .js
- **Stylus 編譯** - .styl → .css
- **Pug 編譯** - .pug → render function
- **資源打包** - 合併多個檔案為 bundle
- **監控模式** - 檔案變更自動重編譯
- **i18n 整合** - 多語系支援

## 安裝

```bash
npm install @plotdb/srcbuild
```

## 使用方式

### 程式化使用（servebase 模式）

```livescript
srcbuild = require '@plotdb/srcbuild'

# 初始化並啟動監控
watcher = srcbuild.lsp do
  base: ['base', 'web']        # 前端站點目錄
  logger: backend.log          # Logger 實例
  i18n: backend.i18n           # i18n 實例
  ignored: [/node_modules/]    # 忽略的路徑
```

### 命令列使用

```bash
# 編譯
srcbuild build

# 監控模式
srcbuild watch

# 編譯 Pug
srcbuild pug
```

## 目錄結構要求

每個前端站點需遵循以下結構：

```
frontend/[site]/
├─ src/              # 源碼
│  ├─ ls/            # LiveScript
│  ├─ styl/          # Stylus
│  └─ pug/           # Pug
├─ static/           # 輸出目錄
│  ├─ css/           # 編譯後的 CSS
│  └─ js/            # 編譯後的 JS
├─ .view/            # Pug 編譯輸出
└─ bundle.json       # 打包設定
```

## 編譯器 (Adapters)

### LSC Adapter - LiveScript 編譯

#### 功能
- 編譯 .ls 檔案為 .js
- 支援 Source Map（開發模式）
- 壓縮（生產模式，使用 uglify-js）

#### 檔案對應
```
src/ls/index.ls → static/js/index.js
src/ls/auth/login.ls → static/js/auth/login.js
```

#### 選項
```livescript
lsc:
  minify: true    # 壓縮輸出
  sourcemap: true # 生成 source map
```

### Stylus Adapter - Stylus 編譯

#### 功能
- 編譯 .styl 檔案為 .css
- 支援變數、mixin、函數
- 壓縮（生產模式，使用 uglifycss）

#### 檔案對應
```
src/styl/style.styl → static/css/style.css
src/styl/components/button.styl → static/css/components/button.css
```

#### 選項
```livescript
stylus:
  compress: true  # 壓縮輸出
```

#### Stylus 特性
```stylus
# 變數
primary-color = #007bff

# Mixin
border-radius(n)
  border-radius n

# 使用
.button
  background primary-color
  border-radius(5px)
```

### Pug Adapter - Pug 編譯

#### 功能
- 編譯 .pug 檔案為 render function
- 支援 layout, include, mixin
- 整合 i18n
- 模組 include (`@/module/...`)

#### 檔案對應
```
src/pug/index.pug → .view/index.js
```

#### Pug 編譯輸出
```javascript
// .view/index.js
module.exports = function(locals) {
  // render function
  return html;
};
```

#### 模組 Include
```pug
//- 使用 @ 表示 module 目錄
include @/auth/web/login.pug
include @/consent/web/banner.pug
```

實際解析為：
```
@/auth/web/login.pug
  ↓
module/base/auth/web/login.pug
```

#### Plugin 系統
```livescript
# 自訂 resolve
plugins = [
  resolve: (fn, src, opt) ->
    if /^@\//.exec(fn) =>
      path.resolve fn.replace(/^@\//, 'module/base/')
    else fn
]

pug.render code, {plugins}
```

### Bundle Adapter - 資源打包

#### 功能
- 合併多個 CSS/JS 檔案
- 壓縮輸出
- 打包 Web Components (block)
- 版本控制

#### 設定檔 (bundle.json)
```json
{
  "block": {
    "auth": [
      {"name": "@servebase/auth", "path": "base.html"},
      {"name": "@servebase/auth", "path": "index.html"}
    ]
  },
  "css": {
    "vendor": [
      "static/assets/lib/bootstrap/dist/css/bootstrap.min.css",
      "static/assets/lib/ldloader/main/index.min.css"
    ],
    "core": [
      "static/css/main.css"
    ]
  },
  "js": {
    "vendor": [
      "static/assets/lib/bootstrap.native/dist/bootstrap-native.min.js",
      "static/assets/lib/proxise/main/index.min.js"
    ],
    "core": [
      "static/js/main.js"
    ]
  }
}
```

#### 輸出
```
static/assets/css/vendor.min.css
static/assets/css/core.min.css
static/assets/js/vendor.min.js
static/assets/js/core.min.js
static/assets/block/auth.html
```

#### Block 打包
```json
{
  "block": {
    "auth": [
      {"name": "@servebase/auth", "path": "base.html"}
    ]
  }
}
```

從 node_modules/@servebase/auth/web/base.html 打包為 static/assets/block/auth.html。

### Asset Adapter - 靜態資源

#### 功能
- 複製不需編譯的資源
- 保持目錄結構

#### 檔案類型
- 圖片（.png, .jpg, .svg）
- 字型（.woff, .ttf）
- 其他靜態檔案

## 監控系統 (Watch)

### 功能
- 監控檔案變更
- 自動重新編譯
- 增量編譯（只編譯變更的檔案）
- 錯誤處理

### 運作原理
```livescript
# 使用 chokidar 監控檔案
chokidar.watch ['src/**/*'], {ignored: /node_modules/}
  .on 'change', (path) ->
    adapter = find-adapter-for path
    adapter.compile path
```

### 監控範圍
- `src/ls/**/*.ls`
- `src/styl/**/*.styl`
- `src/pug/**/*.pug`
- `bundle.json` 變更時重新打包

## i18n 整合

### Pug 模板中使用
```pug
h1= t('welcome')
p= t('description', {name: user.name})
```

### 編譯時注入
srcbuild 將 i18n 函數注入 Pug 編譯環境：
```livescript
pug:
  i18n: backend.i18n
```

## 開發 vs 生產

### 開發模式
- 保留 source map
- 不壓縮（易讀）
- 詳細錯誤訊息
- 啟用監控

### 生產模式
- 移除 source map
- 壓縮 CSS/JS
- 精簡錯誤訊息
- 預編譯所有檔案

## 錯誤處理

### 編譯錯誤
srcbuild 捕獲編譯錯誤並記錄：
```
[srcbuild] Error compiling src/ls/index.ls:
  Line 10: Unexpected token
```

### 繼續運行
即使某個檔案編譯失敗，監控繼續運行。

## 擴展性

### 自訂 Adapter
可建立自訂編譯器：
```livescript
class MyAdapter extends base
  @srcdir = 'src/my'
  @desdir = 'static/my'
  @extname = '.myext'

  compile: (file) ->
    # 編譯邏輯
```

### Plugin 系統
Pug 支援 plugin：
```livescript
plugins = [
  resolve: (filename, source, options) ->
    # 自訂路徑解析
]
```

## 原始碼結構

位於 context/srcbuilcd/dist/：

### 核心檔案
- **main.js** - 主入口
- **watch.js** - 監控系統
- **adapter.js** - Adapter 基類
- **aux.js** - 輔助函數
- **i18n.js** - i18n 工具

### 編譯器
- **ext/lsc.js** - LiveScript
- **ext/stylus.js** - Stylus
- **ext/pug.js** - Pug
- **ext/bundle.js** - 打包
- **ext/asset.js** - 靜態資源
- **ext/base.js** - 基類

### CLI
- **cli.js** - 命令列介面
- **pug-cli.js** - Pug 專用 CLI

## API 參考

### srcbuild.lsp(options)
啟動監控模式。

#### 參數
- **base** - 前端站點目錄（字串或陣列）
- **logger** - Logger 實例
- **i18n** - i18n 實例
- **ignored** - 忽略的路徑（正則陣列）
- **bundle** - bundle 選項
- **lsc** - LSC 選項
- **stylus** - Stylus 選項
- **pug** - Pug 選項
- **asset** - Asset 選項

#### 回傳
Watch 實例。

### srcbuild.base(options)
基礎功能。

## 整合到 servebase

### 啟動時載入
```livescript
# backend/engine/index.ls
if !@production =>
  srcbuild.lsp do
    base: [@base]
    logger: @log
    i18n: i18n
    ignored: [/node_modules/, /\.git/]
```

### 只在開發模式啟用
生產環境應預先編譯：
```bash
npm run prebuild  # 編譯後端
# srcbuild 在前端部署前手動執行
```

## 最佳實踐

### 目錄組織
- 源碼按功能分類（auth/, user/, admin/）
- 避免過深的目錄結構
- 使用有意義的檔名

### 效能
- 避免不必要的 import/include
- 將第三方套件放 bundle 中
- 使用 bundle 減少 HTTP 請求

### 維護
- 定期更新 srcbuild 版本
- 檢查編譯警告
- 保持 bundle.json 清晰

### 除錯
- 開發模式啟用 source map
- 檢查編譯輸出的檔案
- 使用 browser DevTools

## 常見問題

### Q: 編譯很慢怎麼辦？
A:
- 檢查 ignored 設定，排除不必要的目錄
- 減少 bundle 中的檔案數量
- 考慮分批編譯

### Q: Pug 模組 include 找不到？
A: 確認 @ 路徑解析正確，模組在 module/base/ 下。

### Q: 監控沒有觸發重編譯？
A: 檢查檔案是否在監控範圍內，確認沒有被 ignored。

### Q: 生產環境需要 srcbuild 嗎？
A: 不需要，應預先編譯所有資源。
