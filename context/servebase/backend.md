# 後端架構

## 核心元件 (backend/engine/)

### index.ls - 主伺服器
負責啟動和初始化整個後端系統。

#### 主要功能
- 載入設定檔（config/private/secret.ls）
- 初始化 Express 應用
- 載入中介層（middleware）
- 自動載入路由模組
- 啟動 HTTP 伺服器

#### Backend 物件結構
```livescript
backend =
  mode: 'production' | 'development'
  production: boolean
  version: string           # 部署版本
  cachestamp: number        # 快取時間戳
  config: {...}             # 設定物件
  feroot: string            # 前端根目錄
  root: string              # 專案根目錄
  base: string              # 前端目錄名稱
  server: http.Server
  app: express.Application
  log: pino.Logger
  mail-queue: MailQueue
  auth: Auth                # @servebase/auth
  route:
    api: express.Router     # /api/* 路由
    app: express.Router     # /* 路由
  store: {}                 # Redis store
  session: {}               # Session 管理
  mod: {}                   # 自訂擴展
```

#### 路由自動載入
```livescript
# 掃描 backend/ 目錄
routes = fs.readdir-sync path.join(libdir, '..')
  .filter -> !(it in <[engine README.md ext]>)  # 排除特定目錄
  .map -> path.join(libdir, '..', it)
  .filter -> fs.exists-sync path.join(it, 'index.js') or ...
  .map -> require it  # 載入模組
```

### session.ls - Session 管理
使用 @plotdb/express-session（Redis-backed）。

#### 功能
- Session 儲存在 Redis
- 支援 cookie 設定
- 自動過期管理

#### 設定
```livescript
session:
  secret: 'your-secret-key'
  max-age: 365 * 86400 * 1000  # 1年
```

### db/postgresql/ - 資料庫層
PostgreSQL 資料庫抽象層。

#### 主要 API
```livescript
db.query(sql, params)      # 執行查詢
db.exec(sql, params)       # 執行指令（無回傳）
db.get-one(sql, params)    # 取得單一結果
```

#### 連接池
使用 pg-pool 管理連接。

### mail-queue.ls - 郵件佇列
非同步郵件發送系統。

#### 功能
- 支援多種傳輸（SMTP, Mailgun）
- 範本系統（config/base/mail/）
- i18n 支援
- 重試機制

#### 使用
```livescript
backend.mail-queue.send do
  template: 'reset-password'
  locale: 'zh-TW'
  data: {email, token}
```

### i18n.ls - 多語系
基於 i18next。

#### 功能
- 載入 locales/ 翻譯檔
- HTTP middleware 自動偵測語言
- 前後端共用翻譯

### error-handler.ls - 錯誤處理
統一錯誤處理中介層。

#### 錯誤格式
```livescript
# 使用 lderror
throw new lderror(message, id: error-id, status: http-status)
```

#### 處理流程
1. 捕獲錯誤
2. 記錄到 log
3. 根據 Accept header 回傳 JSON 或 HTML
4. 開發模式顯示 stack trace

### aux.ls - 輔助函數
常用工具函數集合。

#### 主要函數
- `routecatch(router)` - 自動捕獲路由錯誤
- `escape-html(str)` - HTML escape
- 其他工具函數

## 路由系統

### 路由結構
```livescript
backend.route =
  api: express.Router()  # /api/* 路由
  app: express.Router()  # 應用路由
```

### 路由模組範例 (backend/base/index.ls)
```livescript
(backend) <- (-> module.exports = it) _
{config, route: {api, app}} = backend
if config.base != \base => return  # 只在 base 模式載入

require! <[express @servebase/backend/aux]>

demo-api = aux.routecatch express.Router {mergeParams: true}
demo-app = aux.routecatch express.Router {mergeParams: true}

api.use \/demo, demo-api
app.use \/demo, demo-app

# 自動載入子模組
fs.readdir-sync __dirname
  .filter -> !/^index\./.exec(it)
  .filter -> !/^\./.exec(it)
  .map -> require(it) backend, {api: demo-api, app: demo-app}
```

### API vs App 路由

#### API 路由 (/api/*)
- 回傳 JSON
- 用於 AJAX 請求
- RESTful 設計

```livescript
api.get '/users/:id', (req, res) ->
  user = await db.get-one "SELECT * FROM users WHERE id=$1", [req.params.id]
  res.json {user}
```

#### App 路由 (/*)
- 回傳 HTML
- Pug 模板渲染
- SSR

```livescript
app.get '/about', (req, res) ->
  res.render 'about', {title: 'About'}
```

## 中介層 (Middleware)

### 載入順序
1. pino-http (logging)
2. express.static (靜態檔案)
3. i18next-http-middleware (i18n)
4. body-parser (解析 body)
5. cookie-parser (解析 cookie)
6. session (session 管理)
7. csurf (CSRF 保護)
8. passport (認證)
9. 自訂 middleware
10. 路由
11. error-handler (錯誤處理)

### CSRF 保護
```livescript
# GET 請求取得 token
app.get '/form', (req, res) ->
  res.render 'form', {csrfToken: req.csrfToken!}

# POST 請求驗證
app.post '/submit', (req, res) ->
  # csurf 自動驗證 _csrf 欄位或 header
```

## 認證系統 (@servebase/auth)

### 功能
- 本地認證（email + 密碼）
- OAuth（Facebook, Google, Line）
- Session 管理
- 權限檢查

### 使用
```livescript
# 登入
backend.auth.login(email, password)

# 註冊
backend.auth.signup(email, password, user-data)

# 檢查權限
backend.auth.require-login(req, res, next)
```

## 資料庫操作

### 查詢
```livescript
# 單一結果
user = await db.get-one "SELECT * FROM users WHERE id=$1", [id]

# 多筆結果
users = await db.query "SELECT * FROM users WHERE role=$1", [role]

# 執行（無回傳）
await db.exec "UPDATE users SET name=$1 WHERE id=$2", [name, id]
```

### Transaction
```livescript
client = await db.connect!
try
  await client.query 'BEGIN'
  await client.query 'INSERT INTO ...'
  await client.query 'UPDATE ...'
  await client.query 'COMMIT'
finally
  client.release!
```

## Redis 操作

### 使用
```livescript
# 取得
value = await backend.store.get(key)

# 設定
await backend.store.set(key, value, expire-seconds)

# 刪除
await backend.store.del(key)
```

## 檔案上傳

使用 multer 處理檔案上傳。

```livescript
require! <[multer]>

upload = multer dest: './uploads/'

api.post '/upload', upload.single('file'), (req, res) ->
  file = req.file
  res.json {filename: file.filename}
```

## 限流 (Throttle)

位於 backend/engine/throttle/。

### 使用
```livescript
throttle = require 'backend/engine/throttle'

# 限制每 IP 每分鐘 10 次請求
api.post '/api/submit',
  throttle.check(ip: {count: 10, duration: 60000})
  (req, res) -> ...
```

## Log 系統

使用 Pino。

### Log Level
- silent - 無輸出
- trace - 追蹤訊息
- debug - 除錯訊息
- info - 資訊（生產預設）
- warn - 警告
- error - 錯誤
- fatal - 致命錯誤

### 使用
```livescript
backend.log.info "Server started"
backend.log.error {err}, "Error occurred"
backend.log.debug {data}, "Debug info"
```

## 環境變數

### NODE_ENV
- `production` - 生產模式
- 其他 - 開發模式

### 影響
- Log level (info vs debug)
- 快取行為
- 錯誤訊息詳細程度
- srcbuild 編譯行為

## 啟動流程

1. 載入 livescript
2. 解析命令列參數（config name）
3. 載入設定檔（config/private/secret.ls）
4. 建立 backend 物件
5. 初始化 log
6. 連接資料庫
7. 連接 Redis
8. 初始化 mail queue
9. 載入 i18n
10. 建立 Express app
11. 載入中介層
12. 載入路由模組
13. 啟動 srcbuild (開發模式)
14. 監控 .version 檔案
15. 啟動 HTTP server
16. 監聽 port

## 開發建議

### 新增路由模組
1. 在 `backend/` 建立目錄（如 `backend/mymodule/`）
2. 建立 `index.ls`:
```livescript
(backend) <- (-> module.exports = it) _
{config, route: {api, app}} = backend

api.get '/myapi', (req, res) ->
  res.json {message: 'Hello'}
```
3. engine 自動載入

### 錯誤處理
使用 lderror 拋出結構化錯誤：
```livescript
if !user =>
  throw new lderror "User not found",
    id: 404
    status: 404
```

### 異步處理
使用 async/await + routecatch：
```livescript
api.get '/data', (req, res) ->
  data = await fetch-data!  # routecatch 自動捕獲錯誤
  res.json {data}
```

### 測試
```bash
npm test                 # 執行測試
npm run coverage         # 測試覆蓋率
```
