# 前端資產的快取策略 ( 版本字串 / cachestamp / nginx )

2026/08/30 在 makechart 上開發 wagent 整合時，一整天反覆遇到「改了東西但跑的是舊的」，
每次症狀都不一樣，追出來是同一組問題。這裡把量測到的事實與已經做掉的部分記下來，
剩下的待決事項在最後。

失敗模式的共同點是**沒有跡象**：行為沒變，於是人會去猜下一個原因，而不是懷疑
自己看的是舊版。當天光是這一類就踩了五次（bundle、block html、runtime js、
worker 的靜態 import、頁面 HTML 本身）。


## 量到的事實

nginx（makechart 的設定，servebase 衍生專案應該都類似）：

    /assets/bundle/*.js        expires 1d      ← 被那條副檔名規則接走
    /assets/lib/**             無 cache-control ← 更前面的 location 先匹配, 沒有任何 header
    /modules/block/**          無 cache-control ← 落到 generic location
    app render 的頁面           只有 weak ETag

「無 cache-control」不等於不快取：有 `Last-Modified` 時瀏覽器會用**啟發式新鮮度**
（約為 `(now - Last-Modified)` 的 10%），一個三小時前改過的檔案會被當成新鮮約 18 分鐘。

版本字串的來源：

 - `+script` / `+css` 用的是 `libLoader._v`，來自 `src/pug/modules/version.pug`
 - 那個檔只有 `npm run pug-rebuild`（`tool/build.sh`）會重寫
 - **bundle 重建不會改它** —— 所以「內容變了、URL 沒變、nginx 說 max-age=86400」，
   對已經來過的使用者最長一天無效
 - `cachestamp`（`npm run cachestamp`，走 localctl socket）是另一套，只用在
   block registry 組出來的 URL 與 navtop 的版本顯示，跟 `libLoader._v` 無關

srcbuild 的 in-process view cache（`view/pug.js`）**不是問題來源**：實測改 `.ls`
後 2 秒 `.view` 就重建，且 `fetch(cache:'no-store')` 立刻拿到新內容。
（`lc.useCache = true || opt.settings['view cache']` 這行讓 express 的 `view cache`
設定失效，但因為 mtime 比對正確，實務上沒造成問題。仍建議清掉那個 `true ||`。）


## 為什麼 cachestamp 不能拿來當 `+script` / `+css` 的版本

cachestamp 是**執行期**的值，static HTML 是建置期烘好的。要讓 static 頁面反映新的
cachestamp 就得重建全部 static 頁面 —— 那正好抵消掉「執行期可 bump、不必重建」
這個唯一的好處。

`version.pug` 之所以能扮演這個角色，是因為它是**建置期的輸入**：它在 pug 的相依圖裡，
一變就自動觸發所有引用它的頁面重建。cachestamp 沒有這個性質。

所以現有的分工其實是對的，只是有一個缺陷：

    libLoader._v   建置期   給烘進 HTML 的 <script> / <link>
    cachestamp     執行期   給 block manager 執行期組出來的 URL ( 不在任何 HTML 裡 )

缺陷是 **`libLoader._v` 不是內容導出的** —— 它是一個手寫 token，只有跑 pug-rebuild
才換。


## 已經做掉的（makechart，2026/08/30）

nginx 依「URL 會不會隨內容改變」分類，正確性交給 ETag：

    /assets/lib/<name>/<精確版本>/...   public, max-age=31536000, immutable
    /assets/lib/<name>/main|local/...  no-cache      ( fedep 的符號連結, 內容會換 )
    /assets/bundle/*                   no-cache      ( 內容會變而 ?v= 不會 )
    /modules/*                         no-cache      ( 本地 block, 路徑上沒有版本 )
    其餘 ( 圖片 / 字型 )                 維持 expires 1d

實測 revalidate 走 304。精確版本目錄從「完全沒快取」變成永久快取，是淨賺。

實作上兩個容易漏的點：

 - nginx 的 `add_header` **有就不繼承** —— location 裡加了任何 add_header，server 層
   那組安全 header 會整組消失。新加的 location 都要把它們重寫一次。
   （makechart 的 `/assets/bundle/*.js` 在此之前就已經因為副檔名規則而少了
   `X-Frame-Options`，一直沒人發現。）
 - regex location 依出現順序比對，先匹配先贏。`/assets/lib` 那條在副檔名規則之前，
   所以 lib 底下的 js 從來沒吃到 `expires 1d` —— 這也是為什麼兩者行為不同。


## 待決

**一、`libLoader._v` 改成內容導出。** 有了 nginx 那層之後這件事**不再是正確性問題**，
只是「能不能安全地用長 max-age」的效能問題，所以可以慢慢做。方向：

 - bundle 建置時寫一份 manifest（url -> 內容 hash），`lib.pug` 的 `+script` / `+css`
   查表。static 烘進去、view 每次 render 查表，兩種模式同一套規則。
 - 殘留的洞：static 頁面不會因為 bundle 內容變了而重新 render（bundle 不在頁面的
   pug 相依圖裡），所以烘進去的 hash 會過時。srcbuild 現有的 `hashfile` 已經記錄了
   頁面 -> bundle 的關係，補一條反向索引（bundle 重建 -> 標記引用它的頁面 dirty）
   可以解，但那是工程。
 - 便宜的替代：讓 bundle 建置也順手更新 `version.pug`。粒度粗（動一個 bundle 全站
   版本都跳），但把失敗模式整個消除。

順帶一提，srcbuild 現有的 `hashfile` **不是**內容 hash —— `pack` 模式下檔名是
`md5(URL 清單)`，清單沒變而內容變了，檔名一樣。

**二、static / view 兩種模式的判準。** srcbuild 已經分得出來，判準寫在 pug 檔第一行
（`src/ext/pug.ls`）：

    //- module          什麼都不產
    ( 一律 )             編成 .view/*.js
    非 //- view          額外 pug.render 成 static html

兩條路徑用的是同一份 `@extapi`，所以上面的 manifest helper 一次加好、兩邊都會生效。

**三、`view/pug.js` 的 `lc.useCache = true || ...`** 清掉，讓 express 的 `view cache`
設定真的有作用（dev 模式應該不快取）。目前因為 mtime 比對是對的所以沒出事，
但那是巧合不是設計。

**四、worker 的靜態 import 繞不過版本化。** 這是這次踩到的一個一般性問題：
`new Worker(url + '?v=x')` 的 query **不會**傳遞到 worker 內部的 `import './x.js'`，
所以任何用 worker 的前端模組，其子模組都必須靠 HTTP 層的快取策略處理（也就是上面
那條 `no-cache`）。加在 URL 上的版本對它們無效。


## bundle content hash 的具體設計 ( 2026/08/30 補 )

讀過 srcbuild 之後, 待決一可以講得更具體。相關的 srcbuild bug 另記在
`20260830-srcbuild-build-graph.md`, 其中第三、四點是這個設計的前置條件。

先釐清兩個 hash 不要混在一起：

 - **spec 名稱**。`lib.pug` 的 `+script(..., {pack:true})` 算 `md5(url 清單)` 當 `name`,
   `:bundle` filter 也是 ( `pug.ls:65-68` ) 。這是**身分**, 必須跨建置穩定,
   因為它同時是 `.bundle-dep/<type>/<name>.dep` 的檔名與 specmgr 的 key。不要動它。
 - **內容 hash**。新加的, 放在檔名的第二段：`assets/bundle/<name>.<hash>.min.js`。

雞生蛋問題是：pug 在 compile time 就要寫出 `<script src>`, 但內容 hash 要等 bundle
建完才知道。解法是 manifest 加一層間接。

### 步驟一：bundler 產 manifest ( 立刻可做, 對 view 模式就直接解決 )

`build-by-spec` 寫完檔之後算 `md5(minified)`, 除了現有的 `<name>.min.js` 之外
再寫一份 `<name>.<hash>.min.js`, 並更新 bundler 記憶體中的一張表

    "js/vendor" -> {min: "/assets/bundle/vendor.a1b2c3d4.min.js", raw: "..."}

同時 dump 成 `assets/bundle/manifest.json` 供重啟後 warm start。

在 `pug.ls` 的 `get-extapi` 裡加一個 local, 例如 `bundleurl({type, name, min})`,
查不到就回退到現有的 `<name>.min.js` ( 冷啟動、bundle 還沒建出來時 ) 。

關鍵是 `@extapi` 是 static build 與 `view/pug.js` 共用的同一份 ( 待決二已經確認 ) ,
所以：

 - **view 模式**：每次 render 都查表, 永遠拿到當下正確的 hash。這一段沒有任何 staleness,
   也不需要重建任何東西。server render 的頁面立刻可以吃 `max-age=31536000, immutable`。
 - **static 模式**：hash 被烘進 HTML, 會過時 —— 需要步驟二。

所以步驟一單獨出貨就已經有意義, 而且風險很低。

### 步驟二：static 頁面的反向失效

待決一原本寫「補一條反向索引 ( bundle 重建 → 標記引用它的頁面 dirty )」, 實際上
**這條索引已經存在** —— `specmgr.specsrc` ( `bundle.ls:39-41, 43` ) 記的就是
「哪些 pug 檔宣告了這個 spec」, `add-spec` / `load-cfg` 每次都在維護它。

所以要做的只是：`build-by-spec` 完成時, 若 hash 與前一次不同, 就發一個事件帶著
`Array.from(spec.specsrc)`, 讓 pug adapter 對這些檔案跑
`change(files, {force: true, non-recursive: true})` ( 跟 `watch.demand` 同一條路 ) 。

必須是「hash 有變才發」。否則 page → bundle → page 就是無窮迴圈, 而
`build-by-spec` 目前完全沒有 dirty 判斷 ( srcbuild 文件第四點 ) , 一定會踩到。
這是為什麼那一項是前置條件。

還要處理的：

 - **舊 hash 檔的清理**。至少保留前一代, 讓已經拿到舊 HTML 的瀏覽器還能載到。
   簡單作法是每個 spec 保留最近 N 代, 更舊的刪掉。
 - **`.bundle-dep` 與 manifest 的一致性**。spec 被刪除的路徑目前是死的
   ( srcbuild 文件第三點 ) , 幽靈 spec 會在 manifest 裡留下永遠不再更新的 entry。

### 與 `libLoader._v` 的關係

有了上面兩步, `+script` / `+css` 的 pack 分支不再需要 `libLoader._v`
( 檔名本身就帶版本 ) 。非 pack 分支 ( `/assets/lib/<name>/<version>/...` ) 也不需要 ——
那些路徑上已經有精確版本, nginx 那層已經給了 `immutable`。

真正還需要 `_v` 的只剩 `main` / `local` 這種符號連結路徑, 而那些已經被 nginx 設成
`no-cache` 了。所以結論是：**`libLoader._v` 在這個設計完成後可以整個拿掉**,
而不是「改成內容導出」。這比原本待決一的描述乾淨。

### 不建議的替代方案

待決一提到的「讓 bundle 建置順手更新 `version.pug`」不建議做：`version.pug` 在
pug 相依圖裡而且幾乎每一頁都 include 它, 一次更新等於全站重建 —— 而全站重建又會
重新分析每一頁、重新註冊 spec、可能再觸發 bundle 重建。在 srcbuild 文件第二點
( `adapter.change` 沒有 visited set ) 修好之前, 這件事本身就是個災難。


## 已實作（srcbuild 0.1.0，2026/08/30）

做完了，但**形狀跟上面的設計不一樣**，以這一節為準。

### 一、是 opt-in 的，預設關閉

    build:
      hash:
        enabled: true       # 不設就是關的，行為完全等同 0.0.71
        mode: 'filename'    # 或 'query'
        keep: 3             # filename 模式：保留幾代
        keepDays: 0         # filename 模式：外加時間下限，0 = 不設

`config.build` 整包會傳進 `lsp`，所以加一個 `hash` key 就通了，不用改 wiring。
opt-in 是因為它會改掉每一頁裡每一個生成資產的 URL，而且在 edge 還沒設好之前一點好處
都沒有——所以由專案在做好 nginx 之後自己打開。

### 二、兩種模式

    filename   另外寫 <name>.<hash>[.min].<ext>，頁面指這個。
               一個 URL 只對應一份 bytes，可以 immutable；代價是要清舊檔，
               而比保留期更老的 HTML 會 404（靠 nginx try_files 退回 plain 檔兜住）。
    query      不多產檔，指向 <name>.min.js?v=<hash>。
               不累積、不 404；代價是過期 HTML 靜默拿到當下的 bytes，
               而且有些 CDN 快取時會忽略 query string。

兩種模式下**plain 檔都一定會寫、而且一定是最新的**——已部署的 HTML、第一次 build
之前 render 出去的頁面、nginx 的 try_files，全都落在它身上。有測試釘住這件事。

### 三、涵蓋範圍比原本設計大

不只 bundle。經過 `+script` / `+css` mixin 的都算：

    lsc 產出 /js/*.js .min.js        ✓
    stylus 產出 /css/*.css .min.css  ✓
    bundle（pack 與 :bundle filter）  ✓
    直接寫 script(src="...") 不走 mixin  ✗
    asset adapter 複製的圖片 / json      ✗
    /modules/** 的 block html            ✗

### 四、manifest 是 URL-keyed 的，不是 spec-keyed

    "/js/site.min.js" -> {url: "/js/site.4b6ac41e1bea.min.js", generations: [{files, at}]}

`bundleurl({type, name, min, src})` 只是「算出 plain URL 再查表」。另外有
`asseturl(url, src)` 給一般檔案用。兩者都會記下「哪個 pug 檔嵌了哪個 URL」
（`get-dependencies` 會跑 filter，所以 init 就建好了），hash 一變就靠這個回頭
重 render 那些頁——**不是**原本設計的 `specsrc`，因為 `specsrc` 只對 bundle 有效。

### 五、實作時才發現的三件事

 - **view engine 拿不到 bundler。**`view/pug.js` 自己 new 一個 pugbuild，建構參數裡
   沒有 bundler。而且 `@watch` 比 `app.engine 'pug'` 晚跑，所以連 store 都還不存在。
   最後是傳一個 getter（`store: ~> @srcbuild?.stores?.0`），沒有 store 時退而讀
   `<base>/.bundle-dep/manifest.json`（mtime 當快取鍵）。副作用是跨 process 也成立。

 - **view engine 本來會再跑一次完整 init scan。**整棵 pug 被建兩次，誰晚寫完誰贏。
   pre-existing bug，0.0.71 冷啟動時 `[view]` logger 有 52 行 build。已修
   （`init-scan: false`），現在是 0。

 - **`frontend/base/node_modules` 是 2023/09 的舊安裝。**`lib.pug` 是用
   `require.resolve(..., {paths: [feroot]})` 解析的，所以落在 frontend root 的那個
   版本永遠贏，跟 root 的相依無關。第一次跑 servebase 就是被它擋住，URL 全是
   不帶 hash 的。兩邊版本要一起管。

### 六、GC

只藏在 `hashstore.put` 裡，**沒有任何人定期掃描**。某個 URL 的舊檔只有在那個 URL
自己下次被重建時才會被 trim。所以穩態不會長（每個 URL ≤ `keep` 代），不再變動的
檔案就凍住，production 啟動後幾乎不跑 GC——但同理也沒東西累積。

唯一會漏的是「manifest 被砍、但 static 輸出還在」：那些舊 hash 檔沒人認領。有界
（≤ keep 代），一行 `find ... -regex '.*\.[0-9a-f]\{12\}\(\.min\)?\.\(js\|css\)$' -delete`
可清，而且有 try_files 兜著。暫時不做自動 sweep——啟動時掃會把「還沒輪到建置的」
誤判成孤兒。

### 七、實測

`alt` fixture 的完整生命週期：

    1. 冷啟動第一次 render   /assets/bundle/0410....min.js               ← 還沒 build，fallback
    2. bundle 建好後         /assets/bundle/0410....20907e49dd9a.min.js
    3. 原樣覆寫來源檔        /assets/bundle/0410....20907e49dd9a.min.js  ← 內容沒變，不動
    4. 內容真的變了          /assets/bundle/0410....a1a7f8e412a3.min.js
    5. 暖重啟                完全沒有重建

servebase 實跑三種狀態：

    off      href="/css/reset.min.css"                  static/js: site.js site.min.js
    filename href="/css/reset.42de0aa9daf1.min.css"     static/js: site.4b6ac....min.js site.dbfd....js site.js site.min.js
    query    href="/css/reset.min.css?v=42de0aa9daf1"   static/js: site.js site.min.js

冷啟動 32 次 html build、暖啟動 0 次。


## nginx（已做，已在本機驗證）

規則寫進 `config/base/nginx/config.ngx`（範本）、`doc/base/infrastructure.md`
（Asset Cache Policy 一節）與 `doc/base/migration-note.md`。**實際跑的是專案自己的
`config/web/nginx/`，而且 `config/gen/` 是 gitignored，所以 merge 進來不會自動生效**
——要改設定、重跑 `npm run config`、reload nginx。

在本機 nginx 上驗過（`npm run cachecheck -- -k https://serve.base`）：

    10 ok, 0 warn, 0 fail
    過期的 hash    -> 200，內容等同 plain 檔（try_files）
    真的不存在     -> 404
    hashed asset 上三個安全 header 都在

`tool/base/cachecheck` 檢查的 URL 是從 build 自己的 manifest 讀出來的，不是寫死的。


## servebase 這邊還沒做的

 - **`.bundle-dep/` 跨部署保留。**砍掉的話冷啟動每頁 render 兩次（先烘 fallback，
   hash 出來後再一次），而且 GC 會失憶。部署時原地更新、掛 volume、或 rsync 排除刪除。

 - **決定用哪個模式，然後打開 `hash.enabled`。**目前全站都是關的。

 - **「網站已更新，請重新整理」的提示。**這是 retention 的另一半：拿著舊 HTML 的用戶
   本來就可能因為後端 API 變了而爆，保留檔案只是掩蓋。有了這個提示，`query` 模式
   （不累積、不 404）就是比較合適的選擇。

 - **`libLoader._v` 還不能拿掉。**hash 關閉時、以及 hash 開啟但 bundle 還沒建出來的
   空窗期，都還在用它。
