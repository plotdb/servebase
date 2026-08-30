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

    src/ls/index.ls      ->  static/js/index.js  與  index.min.js
    src/styl/style.styl  ->  static/css/style.css  與  style.min.css
    src/pug/index.pug    ->  .view/index.js ( render function ) 與 static/index.html

Pug 檔第一行決定產出什麼：`//- module` 什麼都不產（純 mixin 檔），`//- view` 只產
render function 不產 html，其餘兩者都產。

開發時由 `backend/engine/index.ls` 啟動監看，設定放在 `config.build`。接法、設定、
以及這個專案才會踩到的坑（尤其 `lib.pug` 的版本解析），見
[tools/srcbuild.md](tools/srcbuild.md)。工具本身的完整文件在 srcbuild 的 `README.md`。


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

`+script` / `+css` 產生的 URL 分三種，快取行為完全不同：

    /assets/lib/<name>/<精確版本>/...   內容不會變      可以 immutable
    /assets/lib/<name>/main|local/...   fedep 符號連結  必須 no-cache
    /js /css /assets/bundle 的產出      每次 build 會變 見下

第三種是重點。這些 URL 名字不變而內容會變，所以**預設只能 no-cache**（會走 ETag 拿
304，不是不快取）。要讓它們能被長期快取，得開 content addressing——srcbuild 會依內容
算 hash，給同一個檔第二個名字（`site.<hash>.min.js` 或 `site.min.js?v=<hash>`），
那個名字才能設 immutable。

    config.build.hash.enabled = true

**注意 `cachestamp` 不是拿來做這件事的。**它是執行期的值，static HTML 在建置期就烘好
了，塞不進去；它只用在 block registry 執行期組出來的 URL。同理 `libLoader._v` 是建置
期的手寫 token，不隨內容改變——那正是「改了東西但跑的是舊的」的來源之一。

開關與模式選擇見 [tools/srcbuild.md](tools/srcbuild.md)，nginx 規則與驗證方式見
`doc/base/infrastructure.md` 的 Asset Cache Policy（`npm run cachecheck -- <origin>`
可以直接驗證線上設定是否正確）。


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
