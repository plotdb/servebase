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
