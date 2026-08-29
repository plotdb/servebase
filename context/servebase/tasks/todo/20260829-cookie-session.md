# 淘汰 cookie-based session info

`/api/auth/info` 的回應除了送出，還會整包寫進一個名為 `global` 的 cookie，
原意是讓前端有快取時可略過 ajax。該路徑實際上從未被走到。

2026/08/29 已把讀取端明確停用、並補上內嵌機制作為替代，但寫入端仍在，
內嵌機制也還沒接上。


## 已完成

 - `330aa01`：`/api/auth/info` 標記 `Cache-Control: no-store` 與 `Vary: Cookie`。
   該回應帶有 csrfToken 與使用者資料，先前沒有任何 Cache-Control，
   等於仰賴各層快取的預設行為，而 CDN 設定未必在我們手上
 - `83a0eb9`：內嵌機制就位。`lib/index.ls` 抽出 `global-payload` 並掛上
   `res.locals.servebase.global`；`@servebase/pugutil` 新增 `+register-global`；
   `@servebase/core` 把 `window.servebase` 改為合併而非覆寫
 - `0eb09ff`：前端讀 cookie 的分支加上 `use-cookie = false` 明確停用，
   兩端以 `TODO phasing out cookie-based session info` 互指


## 待辦一：確認後移除 cookie

寫入端在 `module/base/auth/lib/index.ls` 的 `/api/auth/info`。

移除前的確認依據：

 - servebase / grantdash-course / loading-v3 / makechart / xinmeti 五個 repo 中，
   唯一的讀取點是 `module/base/auth/src/auth.ls` 的 `!opt.renew` 分支，已停用
 - `renew: false` 的呼叫只存在於 xinmeti 的 `src/ls/backlog/` ( 無人引用 )
   與 2024 年的打包產物
 - 即使漏了誰，該分支的退路是改打 api，不會壞掉

移除時要動的地方：

 - `lib/index.ls`：刪掉 `res.cookie 'global', payload, ...`
 - `src/auth.ls`：刪掉 `use-cookie` 與整個 cookie 分支
 - `backend/engine/aux.ls`：`clear-cookie` 對 `global` 的清除要保留，
   使用者瀏覽器裡可能還留著舊版設下的那份，且它沒有 `HttpOnly`。
   加註說明，避免日後被當成死碼移除


## 待辦二：接上 register-global

機制已就位，但前端沒有任何地方讀取 `window.servebase.global`。刻意如此：
`fetch` 的語意是「從主機取得」，偷偷改用頁面內嵌的快照會與之矛盾。

接上之前要先處理：

 - boot 流程需要有明確的「先找本地副本」概念，而不是塞在 fetch 背後
 - `renew: false` 的語意要重新定義。目前傳入時會 console 警告，因為它沒有作用
 - 各 app 的 layout 要加 `+register-global()`，一個 layout 加一次

未接上之前，呼叫該 mixin 只會讓那一頁失去快取能力，換不到好處。


## 相關但未處理

 - `+register-locals` 嵌入的 `locals.exports` 同樣含個人資料
   ( `member` / `perms` / `teams` )，但那些頁面沒有任何 `Cache-Control`。
   目前只有 `+register-global` 會自動標記，這個不對稱應該收斂
 - `global-payload` 的 `ip` 欄位，尚未確認前端是否真的用到。
   若無用途，少嵌一項個資較好
 - `src/auth.ls` 的 `get-global` 第一次交出深複本、之後交出 `lc.global` 本體，
   呼叫端可直接修改。已知，暫不處理
