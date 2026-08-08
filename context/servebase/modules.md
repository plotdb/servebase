# 模組系統

## 概述

servebase 使用 npm workspaces 管理內部可重用模組，位於 `module/base/` 目錄。

## Workspaces 設定

### package.json
```json
{
  "workspaces": [
    "module/base/version",
    "module/base/auth",
    "module/base/captcha",
    "module/base/consent",
    "module/base/erratum",
    "module/base/core",
    "module/base/navtop",
    "module/base/pugutil",
    "module/base/discuss",
    "module/base/connector",
    "module/base/config",
    "backend/engine",
    "tool/base"
  ]
}
```

### 優點
- 統一依賴管理
- 支援符號連結（symlink）
- 簡化跨模組開發
- 使用 `@servebase/*` 命名空間

## 核心模組

### @servebase/auth - 認證系統

#### 功能
- 本地認證（email + password）
- OAuth（Facebook, Google, Line）
- Session 管理
- 密碼雜湊（bcrypt）

#### 後端 API
```livescript
auth = require '@servebase/auth'

# 初始化
auth.init {backend, config}

# 註冊
user = await auth.signup {email, password, name}

# 登入
user = await auth.login {email, password}

# 登出
await auth.logout {session}

# 中介層
app.use auth.middleware.require-login
app.use auth.middleware.require-role('admin')
```

#### 前端元件
```pug
include @/auth/web/login.pug
include @/auth/web/signup.pug
```

### @servebase/captcha - 驗證碼

#### 功能
- 圖形驗證碼生成
- 驗證碼驗證
- Session 整合

#### 後端 API
```livescript
captcha = require '@servebase/captcha'

# 生成驗證碼
{image, text} = await captcha.generate!
req.session.captcha = text

# 驗證
is-valid = captcha.verify req.session.captcha, user-input
```

#### 前端
```pug
img(src="/api/captcha")
input(name="captcha" placeholder="驗證碼")
```

### @servebase/consent - 同意管理

#### 功能
- Cookie 同意橫幅
- 使用者同意記錄
- GDPR 合規

#### 前端元件
```pug
include @/consent/web/banner.pug
```

```livescript
consent = require '@servebase/consent'

# 檢查同意狀態
if consent.check('analytics') =>
  # 載入 Google Analytics
```

### @servebase/core - 核心功能

#### 功能
- 通用前端工具
- API 客戶端
- 錯誤處理
- 表單驗證

#### 前端
```livescript
core = require '@servebase/core'

# API 請求
data = await core.api.get '/api/users'
result = await core.api.post '/api/submit', {data}

# 表單驗證
validator = core.validator do
  email: core.rules.email
  password: core.rules.min-length(8)
```

### @servebase/config - 設定管理

#### 功能
- 統一設定存取介面
- 範本支援
- 多環境管理

#### 使用
```livescript
config = require '@servebase/config'

# 讀取設定
cfg = config.from "private/secret"

# 讀取範本
template = config.from "mail/intl/zh-TW/welcome.txt"
```

### @servebase/discuss - 討論功能

#### 功能
- 留言板
- 回覆系統
- 權限控制

#### 後端 API
```livescript
discuss = require '@servebase/discuss'

# 建立留言
comment = await discuss.create {
  user-id: req.user.id
  content: 'Hello'
  parent-id: null
}

# 取得留言列表
comments = await discuss.list {target-id: '123'}
```

#### 前端元件
```pug
include @/discuss/web/thread.pug
```

### @servebase/erratum - 錯誤回報

#### 功能
- 使用者錯誤回報
- 管理後台
- 通知系統

#### 後端 API
```livescript
erratum = require '@servebase/erratum'

# 建立錯誤回報
report = await erratum.create {
  user-id: req.user.id
  title: 'Bug report'
  description: '...'
  type: 'bug'
}

# 取得回報列表
reports = await erratum.list {status: 'open'}
```

### @servebase/navtop - 導覽列

#### 功能
- 響應式導覽列
- 使用者選單
- 多語系支援

#### 前端元件
```pug
include @/navtop/web/index.pug
```

### @servebase/pugutil - Pug 工具

#### 功能
- Pug 輔助函數
- 常用 mixin
- 佈局範本

#### 使用
```pug
include @/pugutil/web/mixin.pug

+button('Submit', 'primary')
+card('Title', 'Content')
```

### @servebase/connector - 連接器

#### 功能
- 第三方服務整合
- API 客戶端封裝

### @servebase/version - 版本管理

#### 功能
- 版本號追蹤
- 更新通知

## 建立新模組

### 1. 建立目錄結構
```bash
mkdir -p module/base/mymodule/{src,dist,web}
```

### 2. 建立 package.json
```json
{
  "name": "@servebase/mymodule",
  "version": "1.0.0",
  "main": "dist/index.js",
  "scripts": {
    "build": "lsc -co dist src"
  },
  "dependencies": {}
}
```

### 3. 撰寫源碼
```livescript
# module/base/mymodule/src/index.ls
module.exports =
  init: (backend) ->
    # 初始化邏輯

  do-something: (data) ->
    # 功能實作
```

### 4. 加入 workspaces
```json
{
  "workspaces": [
    "module/base/mymodule"
  ]
}
```

### 5. 安裝依賴
```bash
npm install
```

### 6. 使用模組
```livescript
# 後端
mymodule = require '@servebase/mymodule'
mymodule.init backend

# 前端
include @/mymodule/web/component.pug
```

## 模組開發指南

### 目錄結構
```
module/base/mymodule/
├─ src/              # LiveScript 源碼
│  └─ index.ls
├─ dist/             # 編譯後的 JS
│  └─ index.js
├─ web/              # 前端元件
│  ├─ index.pug
│  ├─ style.styl
│  └─ script.ls
├─ test/             # 測試
│  └─ index.ls
├─ package.json      # 模組設定
└─ README.md         # 說明文件
```

### 命名規範
- 使用 `@servebase/` 命名空間
- 小寫加連字號: `@servebase/my-module`
- 目錄名稱對應模組名稱

### API 設計
- 提供 `init` 函數接收 backend 實例
- 匯出清晰的公開 API
- 避免副作用

### 前端元件
- 放在 `web/` 目錄
- 使用 Pug, Stylus, LiveScript
- 遵循 Web Components 標準（如適用）

### 文件
- 在 README.md 說明用途和 API
- 提供使用範例
- 列出依賴需求

## 模組間依賴

### 依賴其他模組
```json
{
  "dependencies": {
    "@servebase/core": "*",
    "@servebase/auth": "*"
  }
}
```

### 在程式中使用
```livescript
require! <[@servebase/core @servebase/auth]>

module.exports =
  init: (backend) ->
    core.init backend
    auth.init backend
```

## 測試

### 單元測試
```livescript
# module/base/mymodule/test/index.ls
require! <[assert @servebase/mymodule]>

describe 'mymodule', ->
  it 'should work', ->
    result = mymodule.do-something {data}
    assert.equal result, expected
```

### 執行測試
```bash
npm test
```

## 發布

### 私有模組
保持在 module/base/ 目錄，不發布到 npm。

### 公開模組
1. 移到獨立 repo
2. 發布到 npm
3. 在 servebase 中作為 dependency 引用

## 最佳實踐

### 單一職責
每個模組專注於單一功能領域。

### 最小依賴
只依賴必要的外部套件。

### 向後相容
API 變更時保持向後相容，或明確標註 breaking change。

### 文件完整
提供清晰的 API 文件和使用範例。

### 測試覆蓋
關鍵功能要有測試覆蓋。

### 版本管理
遵循 semver 規範。
