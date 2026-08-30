# @plotdb/srcbuild - 前端編譯工具

編譯 LiveScript / Stylus / Pug，管理 bundle 與 content addressing。

**工具本身的完整文件在 srcbuild 自己的 `README.md`**（選項、adapter、pug 擴充、
content addressing 的兩種模式與 manifest 結構）。這份只記 servebase 專屬的部分——
怎麼接上去、設定放哪裡、以及在這個專案裡才會踩到的坑。


## 在 servebase 怎麼接

`backend/engine/index.ls` 的 `watch` 裡：

    @srcbuild = srcbuild.lsp((@config.build or {}) <<< {
      logger, i18n
      base: [@feroot] ++ (@config.srcbuild or [])
      bundle: {configFile: 'bundle.json', relativePath: true, manager: mgr}
      ...
    })

兩個要點：

 - **整包 `config.build` 會傳進 `lsp`**，所以 srcbuild 的任何選項（`hash`、`bundle`、
   `lsc` ...）直接寫在 `config.build` 底下就會生效，不用改 wiring。
 - **`config.build.enabled` 為 false 時整段不執行**——不監看也不編譯。生產環境若在別處
   建好再部署，就是這個設定。

express view engine 另外拿到同一個 content-hash store：

    app.engine 'pug', pug({..., store: ~> @srcbuild?.stores?.0})

傳的是 getter 不是實例，因為 `@watch` 比 `app.engine` 晚跑。沒有它也能動（view engine
會退回讀磁碟上的 manifest），只是每次重建都要重讀。


## 目錄

    frontend/<site>/src/pug/    ->  static/*.html  與  .view/*.js
    frontend/<site>/src/ls/     ->  static/js/
    frontend/<site>/src/styl/   ->  static/css/
    frontend/<site>/bundle.json ->  static/assets/bundle/
    frontend/<site>/.bundle-dep/    建置記憶（.dep 與 manifest.json）

哪些該進版控、為什麼，見 `doc/base/infrastructure.md` 的 Build Artifacts 一節。
簡短版：`static/` 與 `.bundle-dep/manifest.json` 同進退，`*.dep` 可有可無，
`.view/` 不用（會自癒）。


## content addressing

預設關閉，開關在 `config.build.hash`：

    build:
      enabled: true
      hash:
        enabled: true
        mode: 'query'      # 或 'filename'

**開之前 nginx 要先設對**，否則沒有任何效益（`query` 模式少了 `map $arg_v` 的話，
每個資產都是 `no-cache`，而且看起來像在運作，因為 URL 上確實帶著 hash）。規則與驗證
方式見 `doc/base/infrastructure.md` 的 Asset Cache Policy，驗證用
`npm run cachecheck -- <origin>`。

模式的取捨在 srcbuild README。對 servebase 衍生專案特別相關的一點：**會 commit
`static/` 的專案應該用 `query`**——`filename` 每次內容變動都新增一個檔名，git history
會永久保存。


## 這個專案才會踩到的坑

**`lib.pug` 是從 frontend root 解析的。**`+script` / `+css` 這些 mixin 來自
`lib.pug`，而它是用路徑注入、用 `require.resolve(..., {paths: [feroot]})` 解析的——
所以 `frontend/<site>/node_modules` 裡的那份**永遠贏過根目錄的**，跟正在跑的是哪個
srcbuild 無關。

實際發生過：`frontend/base/node_modules` 裡留著 2023 年的 0.0.61，注入的 `lib.pug`
沒有 `asseturl`，於是 content addressing 完全失效——而頁面正常、`cachecheck` 全過、
沒有任何錯誤。srcbuild 0.1.2 起會在啟動時 warn 並印出兩邊路徑。

所以升 srcbuild 版本時，**根目錄、`module/base/*`、`frontend/<site>` 三處要一起升**。
`frontend/<site>/package.json` 有一筆明確的 `@plotdb/srcbuild` devDependency 就是為此
（它自己不建置，但 `lib.pug` 從那裡解析），不要拿掉。

**`frontend/base/package-lock.json` 有進版控。**上面那次舊版復活就是它造成的——
lockfile 記著 2023 年的解析結果，而 `package.json` 沒有直接提到 srcbuild，npm 就沒有
理由重新解析。


## 生產環境

`config.build.enabled` 開著的話伺服器自己建，`git pull` 就地更新時 `.bundle-dep/` 與
`static/` 都留著，重啟是暖的，什麼都不用安排。

關著的話（在別處建好再部署）：`static/` 與 `.bundle-dep/manifest.json` **都要送到伺服
器上**。少了 manifest，烘好的頁面帶著 hash URL，但 server-rendered 的頁面會退回不帶
hash 的——同一個站台兩種行為，而且無聲。
