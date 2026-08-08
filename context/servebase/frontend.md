# 前端架構

## 目錄結構

每個前端站點（frontend/base, frontend/web 等）遵循 srcbuild 標準結構：

```
frontend/[site]/
├─ src/              # 源碼
│  ├─ ls/            # LiveScript
│  ├─ styl/          # Stylus
│  └─ pug/           # Pug 模板
├─ static/           # 靜態資源
│  ├─ assets/
│  │  ├─ lib/        # 前端套件（fedep 產生）
│  │  ├─ img/
│  │  ├─ css/        # 編譯產出
│  │  └─ js/         # 編譯產出
│  ├─ s/             # 使用者上傳（可為 symlink）
│  └─ index.html
├─ .view/            # 編譯後的 Pug 函數
├─ bundle.json       # 打包設定
└─ package.json      # 前端依賴（可選）
```

## 編譯流程 (@plotdb/srcbuild)

### 編譯器類型
- **lsc** - LiveScript → JavaScript
- **stylus** - Stylus → CSS
- **pug** - Pug → Render Function
- **bundle** - 合併多個檔案
- **asset** - 複製靜態資源

### 編譯規則

#### LiveScript
```
src/ls/index.ls
    ↓ srcbuild
static/js/index.js
```

#### Stylus
```
src/styl/style.styl
    ↓ srcbuild
static/css/style.css
```

#### Pug
```
src/pug/index.pug
    ↓ srcbuild
.view/index.js (render function)
```

### 監控模式
開發時 srcbuild 自動監控檔案變化並重新編譯：
```livescript
# backend/engine/index.ls
srcbuild.lsp do
  base: ['base', 'web']  # 監控的站點
  logger: backend.log
  i18n: backend.i18n
```

## 資源打包 (bundle.json)

### 結構
```json
{
  "block": {
    "auth": [
      {"name": "@servebase/auth", "path": "base.html"},
      {"name": "@servebase/auth", "path": "index.html"}
    ]
  },
  "css": {
    "vendor": ["static/assets/lib/bootstrap/..."],
    "core": ["static/assets/lib/@plotdb/block/..."]
  },
  "js": {
    "vendor": ["static/assets/lib/bootstrap.native/..."],
    "core": ["static/assets/lib/@plotdb/block/..."]
  }
}
```

### Bundle 類型

#### block
Web Components 打包。
- 從 module/base/ 載入元件
- 合併為單一 HTML 檔案

#### css
CSS 打包。
- 合併多個 CSS 檔案
- 壓縮（生產模式）
- 輸出 vendor.min.css, core.min.css

#### js
JavaScript 打包。
- 合併多個 JS 檔案
- 壓縮（生產模式）
- 輸出 vendor.min.js, core.min.js

### 使用打包檔案
```pug
//- index.pug
link(rel="stylesheet" href="/assets/css/core.min.css")
script(src="/assets/js/core.min.js")
```

## 前端套件管理 (fedep)

### 運作方式
1. 讀取 package.json 的 frontendDependencies
2. 從 node_modules/ 複製套件到 frontend/*/static/assets/lib/
3. 保持目錄結構

### 設定
```json
{
  "frontendDependencies": {
    "root": "frontend/base/static/assets/lib",
    "modules": [
      "bootstrap",
      "@plotdb/block",
      "ldview"
    ]
  }
}
```

### 執行
```bash
fedep                    # 複製所有套件
fedep bootstrap          # 只複製 bootstrap
```

### 套件結構
```
node_modules/@plotdb/block/
    ↓ fedep
frontend/base/static/assets/lib/@plotdb/block/
```

## 模板系統 (Pug)

### 後端渲染
```livescript
# backend 路由
app.get '/page', (req, res) ->
  res.render 'page', {
    title: 'Page Title'
    user: req.user
  }
```

### Pug 檔案位置
- 前端: `frontend/[site]/src/pug/`
- 編譯後: `frontend/[site]/.view/`

### 模組 include
```pug
//- 使用 @ 表示 module 目錄
include @/auth/web/login.pug
include @/consent/web/banner.pug
```

### Layout
```pug
//- layout.pug
html
  head
    block head
  body
    block content

//- page.pug
extends layout
block content
  h1 Hello
```

## 樣式系統 (Stylus)

### 變數
```stylus
primary-color = #007bff
font-size = 16px

.button
  background primary-color
  font-size font-size
```

### Mixin
```stylus
border-radius(n)
  border-radius n
  -webkit-border-radius n

.box
  border-radius(5px)
```

### Import
```stylus
@import 'variables'
@import 'mixins'
```

## Web Components (@plotdb/block)

### 定義元件
```livescript
# module/base/mycomponent/web/index.ls
block = require '@plotdb/block'

block.create do
  name: 'my-component'
  init: ->
    @view.render!
  handler:
    click: (e) ->
      console.log 'clicked'
```

### 使用元件
```pug
my-component(data-attr="value")
```

```html
<my-component data-attr="value"></my-component>
```

## 前端路由 (ldview)

### 初始化
```livescript
ldview = new ldview do
  root: document.body
  routes:
    '/': -> view: 'home'
    '/about': -> view: 'about'
    '/user/:id': ({id}) -> view: 'user', data: {id}
```

### 導航
```livescript
ldview.go '/about'
ldview.go '/user/123'
```

## AJAX 請求

### 使用 proxise
```livescript
# 封裝 fetch
ld.fetch = (url, opt = {}) ->
  opt.method = opt.method or 'GET'
  opt.headers = opt.headers or {}
  opt.headers['Content-Type'] = 'application/json'
  if opt.body => opt.body = JSON.stringify(opt.body)

  fetch url, opt
    .then -> it.json!

# 使用
data = await ld.fetch '/api/users'
result = await ld.fetch '/api/submit', {
  method: 'POST'
  body: {name, email}
}
```

### CSRF Token
```livescript
# 從 meta tag 取得
csrf-token = document.querySelector('meta[name="csrf-token"]')?.content

# 加入請求
ld.fetch '/api/submit', {
  method: 'POST'
  headers: {'X-CSRF-Token': csrf-token}
  body: {data}
}
```

## 表單處理 (ldform)

### 初始化
```livescript
form = new ldform do
  root: document.querySelector('form')
  submit: (data) ->
    result = await ld.fetch '/api/submit', {
      method: 'POST'
      body: data
    }
    if result.error => throw new Error(result.error)
```

### 驗證
```livescript
form.validator do
  email: (v) -> /^.+@.+$/.test(v)
  password: (v) -> v.length >= 8
```

## 錯誤處理 (lderror)

### 顯示錯誤
```livescript
try
  result = await ld.fetch '/api/submit', {...}
catch error
  lderror.show error
```

### 自訂錯誤訊息
```livescript
lderror.map = {
  404: '找不到資源'
  500: '伺服器錯誤'
}
```

## 通知系統 (ldnotify)

### 顯示通知
```livescript
ldnotify.show do
  message: '操作成功'
  type: 'success'  # success, error, warning, info
  duration: 3000
```

## Modal/覆蓋層 (ldcover/ldcvmgr)

### 建立 Modal
```livescript
modal = new ldcover do
  root: document.body
  base: -> view: 'modal'

modal.get! # 顯示
modal.remove! # 隱藏
```

### 管理器
```livescript
ldcvmgr.global.toggle \my-modal
```

## i18n 前端

### 初始化
```livescript
i18next.init do
  lng: 'zh-TW'
  resources:
    'zh-TW': translation: {...}
    'en': translation: {...}
```

### 使用
```livescript
text = i18next.t('key')
```

```pug
span= t('key')
```

## 靜態資源

### 圖片
```
static/assets/img/logo.png
```

```pug
img(src="/assets/img/logo.png")
```

### 字型
```
static/assets/fonts/custom.woff2
```

```stylus
@font-face
  font-family 'Custom'
  src url('/assets/fonts/custom.woff2')
```

## 使用者上傳檔案

### 儲存位置
```
static/s/
├─ avatar/
├─ upload/
└─ tmp/
```

### 存取
```pug
img(src="/s/avatar/user123.jpg")
```

### Symlink
生產環境可將 static/s 連結到其他儲存位置：
```bash
ln -s /mnt/storage/uploads frontend/base/static/s
```

## 快取策略

### 版本號
使用 cachestamp 避免快取：
```pug
script(src=`/assets/js/core.min.js?v=${cachestamp}`)
```

### Service Worker
可自行實作 Service Worker 進行快取控制。

## 開發建議

### 檔案組織
- 按功能分類: `src/ls/auth/`, `src/styl/components/`
- 共用元件放 module/base/
- 頁面特定程式碼放 frontend/[site]/

### 效能優化
- 使用 bundle 減少 HTTP 請求
- 圖片壓縮
- 延遲載入非必要資源

### 除錯
- 開發模式保留 source map
- 使用 browser DevTools
- 查看 console.log

### 測試
- 單元測試: 使用 mocha
- E2E 測試: 自行選擇工具（Playwright, Cypress）
