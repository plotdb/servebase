# `.view/.@root/` 的產物會過時, 而且是唯一沒有保護網的一類

**狀態 ( 2026/09/19 )**: 分析完成, 方向有共識, **實作方式待討論**。三個未決的問題
列在最後一節。

precompiled pug 會把 `include` / `extends` 進來的內容內聯進產物, 但 view engine 判斷
要不要重編時只看被 render 的那一個 `.pug` 自己的 mtime。所以「entry 沒動, 但它 extends
的 base 改了」這種情況產物不會更新, 也不會自己好起來。

`src/pug` 那類有別的機制兜底 ( 見下 ), 但 `.@root` 那類沒有, 而它的來源恰好是 runtime
部署的 user template —— 改共用 base 正是 template 維護最常做的事。


## 兩個機制, 只有一邊看相依

**builder ( srcbuild )** 有完整的相依追蹤: `dist/ext/pug.js` 的 `getDependencies` 走
`pug.compileClientWithDependenciesTracked`, `dist/adapter.js:49-71` 的 `logDependencies`
把結果建成反向圖 ( `depends.by` / `depends.on` ), watcher 收到 change 就查圖決定重建誰。
實測有效: `touch frontend/base/node_modules/@loadingio/bootstrap.ext/index.pug` ( `base.pug`
include 的檔 ) 會吐 99 行 rebuild。

**view engine ( `dist/view/pug.js` )** 沒有這張圖。整個判斷就是兩個 `statSync`:

```js
mtimeSrc = +fs.statSync(src).mtime;    // src/pug/x.pug
mtime    = +fs.statSync(desv).mtime;   // .view/x.js
if (!mtime || mtimeSrc - mtime > 0) throw new Error("src dirty");
```

`src` 是 entry, 不含任何相依。所以它只朝一個方向自我修復: 產物**不存在**會補, 產物
**過時**不會。


## `.@root` 是什麼, 為什麼特別

`dist/ext/pug.js:460-477` 的 `map()` 依**被 render 的 entry 自己住在哪**決定產物位置:

 - entry 在 `src/pug` 底下 → `.view/x.js`
 - entry 在 `src/pug` 外面 → `.view/.@root/<entry 相對專案根的路徑>/x.js`

跟它 include 了誰無關 —— include 的內容兩種都是內聯進去。實測: 一個在 `src/pug` 底下、
`include @/@loadingio/bootstrap.ext/index.pug` 的檔, 產物落在 `.view/probe-a.js`,
`.@root` 連建都沒建。

grantdash 的 `.@root` 有三類 entry ( 14 個檔 ):

    node_modules/@servebase/payment/view/done/    1 個   套件自帶的 view
    module/grantdash/dart/view/...                9 個   專案 module 提供的 view
    user/template/{dlc,ilic,tccf-sm,tccf-pm,taicca}-*/  4 個   runtime 部署的租戶 template

保護網的差別:

| 產物 | 誰讓它失效 |
|---|---|
| `src/pug` → `.view/x.js` | 本機 build + commit `.view/`, 跟 lockfile 一起 deploy |
| `src/pug` → `static/*.html` | 同上 |
| **`.@root/...`** | **沒有人** |

三條路全斷: 不進版控 ( 含 user data, 這是對的 ); builder 的 `isSupported` 限定
`file.startsWith(srcdir)` 所以 `build.enabled` 開著也不管它; 來源是 runtime 部署的,
根本不經過 build 流程。它是唯一只能靠那兩個 `statSync` 活著的產物。

例外是 `node_modules/@servebase/payment/view/done/` 那類: entry 自己就是 `npm i` 會
重寫的檔, mtime 會變, 現有檢查抓得到。**前提是它自己沒有 include** —— payment 那個
剛好只有兩行。


## 證據

**產物內聯了相依。** grantdash 的 dlc-2026:

    user/template/dlc-2026/view/brd/index.pug               773 bytes
    .@root/user/template/dlc-2026/view/brd/index.js      36,085 bytes   ← 47 倍
        第 2 行: extends ../../../clab/view/brd/base.pug

servebase 自己的 `index.pug` 同樣: 6.7KB 對 46KB 產物, 而 `scriptLoader` 這個字串在
`index.pug` 裡出現 **0 次**、在 `.view/index.js` 裡 **18 次**, 全部來自
`@loadingio/bootstrap.ext/index.pug`。

**改 base 不會重編。** 造一對 `base.pug` / `entry.pug` ( entry `extends base` ), 用
view engine 直接 render:

    1st render      : <div>BASE-V1</div><div>entry</div>
    .@root holds    : .../.@root/module/base/pugutil/probe/entry.js   ← 只有 entry
    2nd render      : <div>BASE-V1</div><div>entry</div>   ← base 改成 V2, entry 沒動
    (rm -rf .view/.@root)
    3rd render      : <div>BASE-V2</div><div>entry</div>

第二行值得注意: `.@root` 裡**只有 extender 的產物**, 被 extends 的 base 從來不在裡面
( 它不是 entry, 沒有自己的產物 )。

**冷編譯的成本。** servebase `index.pug`, 46KB 產物:

    cold  ( 無 .view, compile + write )  173ms
    warm  ( 預編譯在磁碟 )                 3ms
    warm  x20                              4ms total   ( 0.2ms/次, 記憶體快取 )

`pug.compileClient` 是同步的, 那 173ms 整條 event loop 停住。


## 為什麼不能用「部署時清掉 `.@root`」解

清掉整個 `.@root` 確實有效 ( 上面第三次 render 就是 ), 但成本跟規模成正比: 清掉 =
所有**被訪問過**的 entry 下次都要付一次冷編譯。平台上可能有上百個計畫, 更新其中一個
就讓那類頁面全站 cache miss, 173ms × N 全丟給部署後的第一批請求, 而且同步阻塞會讓
它們互相排隊。

而且它依賴部署紀律 —— 現在的部署是 `git pull` 整個 repo, 有人手動 pull 忘了清就中招。

讓 entry 的 mtime 更新也不行: `git pull` 只更新實際變動檔案的 mtime, 改 `clab` 的 base
時 `dlc-2026` 的 entry 一動也沒動。

**所以要避開全站 miss, 就非得有相依資訊不可。**


## 方向

讓 patched srcbuild 管 `.@root` 底下的檔: pug onchange 時自動 track + gen, 重用
builder 已有的 `logDependencies` + `depends.by` / `depends.on` + watcher, 而不是在
view engine 裡再實作一套 deptrack。

比「在 view engine 加相依檢查」好的地方:

 - **DRY** —— 那套邏輯已經在 dev 被驗證過了。
 - **主動重建** —— change 進來就重建, 不是等下次 render 才發現。使用者永遠不會撞到
   那 173ms; 重建發生在部署後幾秒內, 而不是某個人打開頁面的時候。view engine 的被動
   檢查最多只能讓 miss 變精準, miss 的成本還是使用者付。


## 待討論

**1. 解耦怎麼做。** 這套機制現在整個綁在 `config.build.enabled` 底下
( `backend/engine/index.ls:119` 的 early return )。但需要它的 production 是
「build locally, deploy artifacts」形狀, 不該跑 `src/pug` 的 build。所以要讓
「watch + deptrack for `.@root` 來源」能獨立於「build `src/pug`」開關 —— 是兩個
config, 還是 `.@root` 的 watch 根本該歸在 view engine 名下而非 builder?

**2. 沒有 user data 的專案可能根本不需要這個。** servebase 自己是 build-on-server,
builder 在跑; 沒有 runtime template 的專案 `.@root` 可能整個是空的 ( servebase 目前
就是 )。所以 server side building + watch 對它們是純成本。開關的預設值該是什麼, 以及
能不能從「`.@root` 是否為空」自動判斷。

**3. 能否用獨立 process 做。** 這條連回
`doc/base/CHANGELOG.md` 裡那筆啟動時間的改動 —— 當時把 srcbuild / block / jsdom 移出
啟動路徑, 前提正是「只服務的 server 不需要 builder」。如果現在要把 watcher 請回
production, 獨立 process 可以同時保住那個前提: 主 process 不載 srcbuild, builder 在
旁邊跑、寫 `.view/`, 兩邊只透過檔案系統溝通。需要確認的是 view engine 的
`reload(desv)` 能不能可靠地看到另一個 process 寫出來的檔 ( 它有自己的 `pugcache`,
以 mtime 判斷 ), 以及 `localctl` 要不要參一腳。

另外 watch 範圍比想像小: `.@root` 三類來源裡, node_modules 套件 view 那類不用 watch
( 理由見上 ), 真正要 watch 的是 `module/` 和 `user/template/`, 都不含 node_modules 全掃。
它們的 `@/` 相依可以按需加入 —— `dist/watch.js` 的 `relink` 已經是這個模式
( `this.watcher.add(p)` )。


## 順帶: node_modules 不能從 watch 排除

查這件事的路上順便確認的, 記在這裡免得之後又有人想省那筆開銷。

srcbuild 的 watcher root 寫死 `['.']` ( `dist/watch.js`, `lsp` 不傳 root ), 預設 ignored
只有 `aux.junk` ( `.git` / `.DS_Store` / `*.swp` 那幾個 ), node_modules 沒排除。代價是
5265 個 watched 目錄 / 33646 個 entry / 755ms, 排除 node_modules 後是 633 / 3818 / 121ms
—— 89% 的量在 node_modules。

但不能排除: `@/xxx` 的 include 走 `pugResolve` → `require.resolve`, 解析到 node_modules,
而 watcher 對那些檔的 watch 正是 `@/` include 能即時生效的唯一機制。ignore 掉就沒有
change event, 相依圖根本沒機會被查。

注意 `require.resolve` 回傳 **realpath**, 所以兩類套件命運不同:

 - workspace 套件 ( `@servebase/pugutil` → `module/base/pugutil` ) 走 `module/` 路徑被
   watch, 不受 node_modules ignore 影響
 - 真的第三方 ( `@loadingio/bootstrap.ext`, `ldview` ) 解析到 `frontend/base/node_modules/`,
   會受影響

想縮的話要走白名單而不是全排除: 啟動時掃一次 `src/pug/**/*.pug` 的 `@/xxx`, 解析成套件
目錄, ignore 其餘的 node_modules。servebase 實際只用到 3 個套件, 其中 pugutil 還不在
node_modules 路徑上。`config.build.ignored` 是現成入口 ( 一路傳到 watcher 和各 adapter ),
chokidar 的 ignored 支援 function, 所以能在 engine 端做完, 不必改 srcbuild。

這是最佳化, 只影響 dev, 優先度低於上面的 stale 問題。


## 驗證方式

修好之後應該做得到:

 1. production 形狀 ( `build.enabled` off ) 下, 改一個被多個 template extends 的
    共用 base, 不動任何 entry —— 所有受影響的 `.@root` 產物在幾秒內更新, 不必等
    請求進來, 也不必重啟。
 2. 沒被影響的 entry 的產物 mtime 不變 ( 確認是精準重建而不是全清 )。
 3. `.@root` 為空的專案 ( servebase 自己 ) 啟動時不載入 srcbuild —— 用
    `require.cache[require.resolve('@plotdb/srcbuild')]` 確認, 維持
    `doc/base/CHANGELOG.md` 那筆改動的結果。
