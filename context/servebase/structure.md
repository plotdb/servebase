# 目錄結構說明

## 根目錄結構

```
servebase/
├─ backend/          # 後端程式碼
├─ frontend/         # 前端程式碼
├─ config/           # 設定檔
├─ module/           # 內部模組（workspaces）
├─ locales/          # i18n 多語系
├─ doc/              # 文件
├─ tool/             # 工具腳本
├─ script/           # 部署腳本
├─ dev/              # 開發用工具
├─ test/             # 測試
├─ .backend/         # 編譯後的後端 JS（生成）
├─ node_modules/     # 依賴套件
├─ package.json      # 專案設定
├─ start             # 啟動腳本
├─ .version          # 版本標記
└─ server.log        # 伺服器 log
```

## Backend 結構

```
backend/
├─ engine/           # 核心伺服器（勿修改）
│  ├─ index.ls       # 主入口
│  ├─ session.ls     # Session 管理
│  ├─ i18n.ls        # 多語系
│  ├─ mail-queue.ls  # 郵件佇列
│  ├─ error-handler.ls  # 錯誤處理
│  ├─ aux.ls         # 輔助函數
│  ├─ redis-node.ls  # Redis 客戶端
│  ├─ db/            # 資料庫層
│  │  └─ postgresql/ # PostgreSQL 實作
│  ├─ throttle/      # 限流機制
│  └─ utils/         # 工具函數
├─ base/             # 範例路由
│  ├─ index.ls       # 路由註冊
│  ├─ sample.ls      # 範例 API
│  ├─ manager.ls     # 管理功能
│  └─ ...
├─ admin/            # 管理後台路由
└─ [custom]/         # 自訂路由（自動載入）
```

### 路由自動載入機制
- engine/index.ls 掃描 backend/ 下所有目錄
- 排除 `engine`, `README.md`, `ext`
- 尋找 `index.js` 或 `index.ls`
- require 並傳入 backend 實例

## Frontend 結構

```
frontend/
├─ base/             # 範例站點
│  ├─ src/           # 源碼
│  │  ├─ ls/         # LiveScript
│  │  ├─ styl/       # Stylus
│  │  └─ pug/        # Pug 模板
│  ├─ static/        # 靜態資源
│  │  ├─ assets/     # 資源檔
│  │  │  └─ lib/     # 前端套件（fedep 產生）
│  │  ├─ s/          # 使用者上傳（可為 symlink）
│  │  ├─ index.html  # 主頁
│  │  └─ ...
│  ├─ .view/         # 編譯後的 Pug（生成）
│  ├─ bundle.json    # 資源打包設定
│  └─ package.json   # 前端依賴（可選）
├─ web/              # 生產站點（fork 版常用）
└─ alt/              # 其他站點
```

### 前端資源組織
- **src/** - 開發時編輯
  - `ls/` - 編譯為 `static/js/`
  - `styl/` - 編譯為 `static/css/`
  - `pug/` - 編譯為 `.view/*.js`
- **static/** - 瀏覽器可存取
  - `assets/lib/` - 第三方套件
  - `assets/img/` - 圖片資源
  - `js/`, `css/` - 編譯產出

## Config 結構

```
config/
├─ base/             # 範例設定（進版控）
│  ├─ nginx/         # Nginx 設定
│  │  ├─ default     # 預設站點
│  │  └─ ssl         # SSL 設定
│  ├─ docker/        # Docker 設定
│  │  ├─ compose.yaml
│  │  └─ Dockerfile
│  ├─ db/            # 資料庫 schema
│  │  ├─ schema.sql
│  │  └─ init.sql
│  └─ mail/          # 郵件範本
│     └─ intl/       # 多語系郵件
│        ├─ en/
│        └─ zh-TW/
├─ private/          # 私密設定（不進版控）
│  ├─ secret.ls      # 主設定檔
│  ├─ demo.ls        # 範例設定
│  └─ key/           # 金鑰檔案
├─ gen/              # 生成的設定
└─ tool/             # 設定工具
```

### secret.ls 結構
```livescript
module.exports =
  base: 'base'           # 前端目錄名稱
  url: 'http://localhost:3000'
  port: 3000
  session:
    secret: 'your-secret'
  db:
    io-pg:
      uri: 'postgresql://...'
  redis:
    enabled: true
    host: 'localhost'
  mail:
    provider: 'mailgun'
    config: {...}
```

## Module 結構

```
module/base/
├─ auth/             # 認證模組
│  ├─ src/           # 源碼
│  ├─ dist/          # 編譯產出
│  ├─ web/           # 前端元件
│  └─ package.json   # 模組設定
├─ captcha/          # 驗證碼
├─ consent/          # 使用者同意
├─ core/             # 核心功能
├─ config/           # 設定管理
├─ discuss/          # 討論功能
├─ erratum/          # 錯誤回報
└─ ...
```

### 模組特性
- 每個模組都是獨立的 npm package
- 在根 package.json 的 workspaces 中註冊
- 可同時提供前端和後端功能
- 使用 `@servebase/*` 命名空間

## Locales 結構

```
locales/
├─ en/               # 英文
│  └─ translation.json
└─ zh-TW/            # 繁體中文
   └─ translation.json
```

### 翻譯檔格式
```json
{
  "key": "翻譯文字",
  "nested": {
    "key": "巢狀翻譯"
  }
}
```

## Doc 結構

```
doc/
└─ base/
   ├─ README.md            # 專案說明
   ├─ index.md             # 文件首頁
   ├─ architect.md         # 架構說明
   ├─ api.md               # API 文件
   ├─ security.md          # 安全說明
   ├─ repo-structure/      # 結構說明
   │  ├─ main.md
   │  ├─ config.md
   │  └─ user.md
   └─ modules/             # 模組文件
      ├─ backend.md
      ├─ database.md
      ├─ permission.md
      └─ ...
```

## Tool 結構

```
tool/
├─ base/             # 基礎工具
├─ git-hooks/        # Git hooks
│  ├─ pre-commit
│  └─ post-merge
├─ build.sh          # 建置腳本
└─ cannon            # 部署工具
```

## Dev 結構

```
dev/
├─ browser/          # 瀏覽器測試工具
├─ item/             # 開發項目
├─ json-to-query/    # JSON 轉查詢工具
├─ srcbuild/         # srcbuild 開發
└─ upload/           # 上傳測試
```

## 檔案命名慣例

### LiveScript 檔案
- 使用 kebab-case: `mail-queue.ls`, `error-handler.ls`
- 入口檔案命名為 `index.ls`

### 設定檔
- 使用 kebab-case: `secret.ls`, `compose.yaml`
- 範本檔案加 `.example`: `secret.ls.example`

### 前端資源
- CSS: `style.css`, `index.css`
- JS: `index.js`, `main.js`
- Pug: `index.pug`, `layout.pug`

## 重要檔案說明

### 根目錄檔案

- **start** - 啟動腳本
  - 支援 `-c <config>` 指定設定檔
  - 設定 NODE_ENV
  - 執行 node .backend/engine/index.js

- **.version** - 版本標記
  - 部署時更新
  - server 監控此檔案並更新 cachestamp

- **package.json** - 專案設定
  - workspaces 定義內部模組
  - scripts 定義常用指令
  - dependencies 包含所有依賴

- **server.log** - 伺服器 log
  - Pino 格式
  - 包含所有請求和錯誤記錄

### Git 相關

- **.gitignore** - 版本控制排除
  - node_modules/
  - .backend/
  - config/private/
  - config/gen/
  - server.log

## 路徑解析

### Backend 模組解析
```livescript
# 使用 backend/ 相對路徑
require! <[backend/engine/aux]>

# 使用 @servebase 命名空間（module/base/）
require! <[@servebase/auth]>
```

### Frontend 模組解析
```pug
//- 使用 @ 表示 module 目錄
include @/auth/web/login.pug
```

### 設定檔解析
```livescript
# config.from 自動加上 config/ 前綴
config.from "private/secret"
# 實際路徑: config/private/secret.ls
```
