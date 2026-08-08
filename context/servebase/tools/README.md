# 工具說明

servebase 專案使用兩個關鍵工具來管理前端開發流程：

## fedep - 前端依賴管理

將 node_modules 中的前端套件複製到靜態資源目錄。

**主要功能:**
- 從 node_modules 自動複製套件
- 透過 package.json 設定管理
- 保持套件目錄結構

**詳細說明:** [fedep.md](./fedep.md)

**典型使用:**
```bash
# 複製所有設定的套件
fedep

# 複製特定套件
fedep bootstrap @plotdb/block
```

## @plotdb/srcbuild - 前端編譯工具

編譯和打包前端資源（LiveScript, Stylus, Pug）。

**主要功能:**
- LiveScript → JavaScript
- Stylus → CSS
- Pug → Render Function
- 資源打包（bundle）
- 監控模式（開發時自動重編譯）

**詳細說明:** [srcbuild.md](./srcbuild.md)

**典型使用:**
```livescript
# 在 backend/engine/index.ls 中自動啟動
srcbuild.lsp do
  base: ['base']
  logger: backend.log
  i18n: backend.i18n
```

## 工具關係

```
npm install
    ↓
node_modules/
    ↓
fedep → frontend/*/static/assets/lib/
    ↓
bundle.json 參考
    ↓
srcbuild 打包 → vendor.min.js/css
```

## 完整前端流程

### 開發流程
1. **安裝套件** - `npm install @plotdb/block`
2. **設定 fedep** - 在 package.json 加入 frontendDependencies
3. **複製套件** - `fedep`
4. **撰寫程式** - 在 src/ 目錄編輯 .ls, .styl, .pug
5. **自動編譯** - srcbuild 監控並自動編譯
6. **設定打包** - 在 bundle.json 設定需要打包的資源
7. **測試** - 瀏覽器載入編譯後的資源

### 生產部署
1. **安裝套件** - `npm ci --production`
2. **複製套件** - `fedep`
3. **編譯資源** - srcbuild 執行編譯
4. **編譯後端** - `npm run prebuild`
5. **啟動伺服器** - `npm start`

## 其他工具

### 專案內建工具 (tool/)
- **git-hooks/** - Git hooks 設定
- **build.sh** - 建置腳本
- **cannon** - 部署工具

詳細說明請參考 `tool/` 目錄。
