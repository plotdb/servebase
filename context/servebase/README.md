# @plotdb/servebase - 專案總覽

## 專案定位

servebase 是一個完整的網路服務基板專案，設計為可 fork 後 rebase 的開發模式。提供快速建立網站服務的完整解決方案。

## 技術棧

- Backend: Node.js + Express + LiveScript + PostgreSQL
- Frontend: Pug + Stylus + LiveScript
- Build Tools: @plotdb/srcbuild (前端編譯), fedep (套件管理)
- Infrastructure: Docker, Redis, Nginx

## 核心設計理念

1. **基板模式**: fork 後持續 rebase 以獲取 servebase 更新
2. **模組化架構**: backend 路由、frontend 頁面、功能模組皆可獨立擴展
3. **多站點支援**: 支援同一專案管理多個站點（透過 frontend 子目錄）
4. **工作空間管理**: 使用 npm workspaces 管理內部模組
5. **開發生產分離**: 清楚區分開發與生產環境配置

## 目錄結構速查

- `backend/` - 後端程式碼
  - `engine/` - 核心伺服器（勿直接修改）
  - `base/` - 範例路由
  - 其他目錄 - 自訂路由（自動載入）
- `frontend/` - 前端程式碼
  - `base/` - 範例前端（fork 版通常用 `web/`）
  - 子目錄遵循 srcbuild 結構
- `config/` - 設定檔
  - `base/` - 範例設定
  - `private/` - 私密設定（不進版控）
  - `gen/` - 生成的設定
- `module/base/` - 內部可重用模組（workspace 成員）
- `locales/` - i18n 多語系資源
- `doc/base/` - 文件
- `tool/` - 工具腳本

## 核心工作流程

### 開發流程
1. 設定 `config/private/secret.ls`（參考 demo.ls）
2. 啟動資料庫: `npm run docker-db`
3. 安裝前端套件: fedep（自動將 node_modules 複製到 frontend/*/static/assets/lib）
4. 開發模式: `npm run dev` 或 `./start`
5. 前端自動編譯: srcbuild 監控檔案變化

### 部署流程
1. 前端編譯: srcbuild 將 pug/stylus/ls 編譯
2. 後端編譯: `npm run prebuild` (ls → .backend/js)
3. 生產啟動: `npm start`

## 關鍵模組

### 後端核心 (backend/engine/)
- `index.ls` - 主伺服器啟動與路由載入
- `db/` - PostgreSQL 資料庫抽象層
- `session.ls` - Session 管理（Redis-backed）
- `mail-queue.ls` - 郵件佇列
- `i18n.ls` - 多語系
- `error-handler.ls` - 統一錯誤處理

### 前端工具
- **@plotdb/srcbuild** - 前端資源編譯與打包
  - 編譯 LiveScript, Stylus, Pug
  - bundle.json 管理資源打包
  - 監控模式支援開發時自動重編譯
- **fedep** - 前端套件管理
  - 從 node_modules 複製前端資源到 static/assets/lib
  - 透過 package.json 的 frontendDependencies 設定

### 內部模組 (module/base/)
- `auth` - 認證系統
- `captcha` - 驗證碼
- `consent` - 使用者同意管理
- `core` - 核心前端功能
- `config` - 設定管理
- 其他功能模組（discuss, erratum, navtop, etc）

## 快速參考文件

詳細說明請參考：
- [架構設計](./architecture.md) - 系統整體架構與設計理念
- [目錄結構](./structure.md) - 完整目錄結構說明
- [後端架構](./backend.md) - 後端系統詳細說明
- [前端架構](./frontend.md) - 前端系統詳細說明
- [設定系統](./config.md) - 設定檔架構與使用
- [模組系統](./modules.md) - 內部模組開發與使用
- [工具說明](./tools/) - fedep 與 srcbuild 工具說明

## 開發協作重點

### 修改原則
- 避免直接修改 `backend/engine/` - 這是核心，改動應回饋到 servebase
- 新路由放在 `backend/` 下的新目錄
- 新頁面放在 frontend 對應位置
- 共用模組考慮放在 `module/base/` 並加入 workspaces

### 配置管理
- 公開設定: `config/base/`
- 私密設定: `config/private/secret.ls` (gitignored)
- 生成設定: `config/gen/`
- 可透過 `./start -c <name>` 使用不同設定檔

### 多語系
- 翻譯檔: `locales/{locale}/`
- i18next 自動載入
- 前端透過 i18next.js, 後端透過 i18n middleware

### 版本控制
- 使用 `.version` 檔案追蹤部署版本
- server 監控 `.version` 並更新 cachestamp
- git hooks 位於 `tool/git-hooks/`
