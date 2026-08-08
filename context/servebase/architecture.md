# 架構設計

## 核心設計理念

### 1. Fork & Rebase 模式
- servebase 作為基板，團隊 fork 後進行開發
- 定期從 servebase rebase 以獲取更新和修正
- 核心功能保持在 engine，自訂功能在獨立模組

### 2. 分層架構

```
使用者請求
    ↓
Nginx (反向代理)
    ↓
Express 應用層
    ↓
├─ 中介層 (Middleware)
│  ├─ Session (Redis)
│  ├─ i18n
│  ├─ CSRF Protection
│  ├─ Body Parser
│  └─ Error Handler
    ↓
├─ 路由層 (Routes)
│  ├─ API 路由 (/api/*)
│  └─ 應用路由 (/*)
    ↓
├─ 業務邏輯層
│  ├─ Auth (@servebase/auth)
│  ├─ Database (PostgreSQL)
│  ├─ Cache (Redis)
│  └─ Mail Queue
    ↓
資料儲存層
├─ PostgreSQL (主要資料)
├─ Redis (Session/Cache)
└─ 檔案系統 (上傳檔案)
```

### 3. 模組化設計

#### Backend 模組化
- **engine** - 不可修改的核心
- **路由模組** - backend/* 下的目錄自動載入
- **功能模組** - module/base/* 可重用模組（npm workspaces）
- **擴展點** - backend/ext/ 提供核心擴展

#### Frontend 模組化
- **站點分離** - 每個站點一個子目錄（base, web, alt, ...）
- **資源編譯** - srcbuild 統一編譯流程
- **套件管理** - fedep 管理前端依賴
- **組件化** - @plotdb/block 提供 web component 支援

### 4. 設定管理分層

```
config/
├─ base/        # 範例設定（進版控）
│  ├─ nginx/    # Nginx 設定範本
│  ├─ docker/   # Docker 設定
│  ├─ db/       # 資料庫 schema
│  └─ mail/     # 郵件範本
├─ private/     # 私密設定（不進版控）
│  └─ secret.ls # 主要設定檔
└─ gen/         # 生成的設定
```

## 請求處理流程

### HTTP 請求流程
1. **接收請求** - Express 接收 HTTP 請求
2. **Session 載入** - express-session + Redis
3. **語言偵測** - i18next-http-middleware
4. **CSRF 驗證** - csurf (POST/PUT/DELETE)
5. **路由匹配** - Express Router
6. **業務處理** - 路由處理器
7. **回應生成** - JSON / Pug 模板渲染
8. **錯誤處理** - error-handler 捕獲並處理

### API vs 應用路由
- **API 路由** (`/api/*`)
  - 回傳 JSON
  - RESTful 設計
  - 供前端 AJAX 或外部呼叫

- **應用路由** (`/*`)
  - 回傳 HTML (Pug 渲染)
  - SSR (Server-Side Rendering)
  - 初始頁面載入

## 資料流

### 前端資源編譯流程
```
源碼 (src/)
├─ .ls → srcbuild → .js
├─ .styl → srcbuild → .css
└─ .pug → srcbuild → .js (render function)
    ↓
靜態資源 (static/)
├─ assets/
└─ index.html
    ↓
瀏覽器載入
```

### 前端套件管理流程
```
package.json (dependencies)
    ↓
npm install → node_modules/
    ↓
fedep → 複製到 frontend/*/static/assets/lib/
    ↓
bundle.json 參考
    ↓
srcbuild 打包
    ↓
瀏覽器載入 bundle.min.js/css
```

### 後端編譯流程
```
backend/*.ls
    ↓
npm run prebuild
    ↓
lsc -co .backend backend
    ↓
.backend/*.js
    ↓
Node.js 執行
```

## 核心元件互動

### 認證流程 (Auth)
```
使用者登入
    ↓
POST /api/auth/login
    ↓
@servebase/auth 驗證
    ↓
bcrypt 比對密碼
    ↓
建立 Session (Redis)
    ↓
回傳 Session Cookie
```

### 資料庫操作
```
業務邏輯
    ↓
db.query(sql, params) - backend/engine/db/postgresql
    ↓
pg-pool 連接池
    ↓
PostgreSQL
```

### 郵件發送
```
觸發郵件
    ↓
mail-queue.send(template, data)
    ↓
讀取範本 (config/base/mail/)
    ↓
template-text 填充資料
    ↓
nodemailer 發送
    ↓
SMTP / Mailgun
```

## 擴展性設計

### 新增路由模組
1. 在 `backend/` 建立新目錄（如 `backend/myfeature/`）
2. 建立 `index.ls` 匯出初始化函數
3. engine 自動載入並註冊路由

### 新增前端站點
1. 在 `frontend/` 建立新目錄（如 `frontend/mysite/`）
2. 遵循 srcbuild 結構（src/, static/, bundle.json）
3. 在 `config/private/secret.ls` 設定 `base: 'mysite'`

### 新增內部模組
1. 在 `module/base/` 建立模組目錄
2. 加入 `package.json` 的 workspaces
3. 模組可被 backend 和 frontend 共用

## 效能考量

### 快取策略
- **Session** - Redis 儲存，減少資料庫查詢
- **靜態資源** - Nginx 快取，版本號控制
- **資料庫查詢** - 可在業務層加入快取

### 開發 vs 生產
- **開發模式**
  - srcbuild watch 模式，檔案變更自動編譯
  - 詳細 log (debug level)
  - 不壓縮資源

- **生產模式**
  - 預編譯所有資源
  - 壓縮 CSS/JS (uglifycss, uglify-js)
  - info level log
  - 啟用快取

## 安全設計

### CSRF 防護
- csurf middleware
- 所有 POST/PUT/DELETE 需要 CSRF token

### Session 安全
- httpOnly cookie
- secure flag (HTTPS)
- Redis-backed 避免 session fixation

### SQL Injection 防護
- 使用參數化查詢
- pg library 自動 escape

### XSS 防護
- Pug 自動 escape 輸出
- DOMPurify 清理 HTML 輸入

### 密碼安全
- bcrypt 雜湊
- 不儲存明文密碼
