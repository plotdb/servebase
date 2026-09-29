# @servebase/mail

群發信: 收件清單 + 樣板 → 逐封個人化的信, 排程寄送並追蹤每封的結果.

寄送本身仍走 `@servebase/backend` 的 `mail-queue`; 這個模組加的是它沒有的
兩件事 — **持久化的 spool** ( 重啟後接得下去 ) 與 **逐封的結果紀錄**.

## 使用

掛在 host 給的 router 底下. 權限不由這個模組判斷 - host 在 router 上先擋:

```livescript
route = aux.routecatch express.Router {mergeParams: true}
api.use \/mailmerge/:scope, route
route.use aux.signedin
route.use (req, res, next) ->
  req.mailmerge = {scope: req.params.scope}
  myperm.check {slug: req.params.scope, user: req.user, action: <[owner admin]>}
    .then -> next!
    .catch next

worker = mail {backend, route}
```

模組認 `req.mailmerge` 的兩個欄位.

`scope` 是必要的, 而且**不在乎它從哪來** - path param、上游的 middleware、
子網域、寫死的常數都行. router 底下的每一支都已經是「這個 user 對這個 scope
有權」, 所以模組不做任何權限判斷, 只負責確認帶進來的 `key` 真的屬於這個
scope ( 見 `get-batch` ).

`defaults` 是選用的: 一組預設的 `sender` / `sendername` / `replyto`, 使用者
沒填時就用它.

```livescript
req.mailmerge = {scope: req.params.scope, defaults: {sender: 'no-reply@...', replyto: ...}}
```

在有 req 的當下 ( `/save`、`/test`、`/send-now` ) 就寫進 detail, 不留到寄送
當下才解析 - worker 沒有 req, 而且「送出時看到什麼就寄什麼」比「寄出前一刻
的設定說了算」好理解.

`aux.routecatch` 只包 `get/post/put/delete`, 不包 `use` - middleware 裡的
promise 要自己 `.catch next`.

回傳 worker, 讓 host 能程式化觸發 (`worker.tick!`) — 例如另一個排程建好批次後
直接開跑, 不必等下一輪 tick.

## API

全部是 POST, 掛在 host 給的 router 底下, 參數走 body.

帶 `key` 的那幾支 ( `/get` `/send` `/pause` `/resume` `/cancel` `/retry` ) 都
先用 `{key, scope}` 查, 查不到就 404 - 不區分「不存在」與「不是這個 scope
的」, 後者若回別的碼等於告訴對方那個 key 存在. `/save` 帶 `key` 時也一樣.

| 端點 | body | 回傳 |
| --- | --- | --- |
| `/save` | `key?` `name` `detail` `rows` `record` | 批次 |
| `/list` | `q?` | 批次陣列 ( 不含 `detail.content` ) |
| `/progress` | `keys` | 批次陣列 ( 精簡欄位 ) |
| `/get` | `key` | 批次 + `items` |
| `/send` | `key` `scheduledtime?` | 批次 |
| `/pause` `/resume` `/cancel` `/retry` | `key` | 批次 |
| `/send-now` | `detail` `rows` | 批次 |
| `/test` | `detail` `vars?` | `{}` |

`/save` 沒有 `key` 就新建, 有就更新; 只有 `draft` 能改 ( 改了會與已寄出的
內容對不起來 ), 其餘回 409. items 每次整批重寫 - 草稿階段清單可以任意增刪,
逐列 diff 沒有意義. email 無效的不丟掉, 存成 `skipped` 留在清單裡, 使用者
要看得到是哪幾列有問題.

`/list` 搜的是標題 ( `name` 與 `detail.subject` ) 與收件者位址, **不搜內文**:
敏感批次根本沒有內文可搜, 搜得到與搜不到會隨保存層級而異.

`/progress` 給清單的自動更新用. 走 `/list` 的話每次都要對整個 scope 的 item
做統計聚合, 那個成本是白付的. `keys` 收陣列或逗號分隔字串.

`/send` 的 `scheduledtime` 為空表示立刻開始. `record` 為 `metadata` 的批次
不給排程 - 內容要等寄完才清得掉, 排到明天等於讓它在 DB 裡多躺一天.

`/send-now` 不落地寄送, 見下面的保存層級. 上限是
`min(nostore-max, batch-max)`.

`/test` 試寄一封給自己 ( `req.user.username` ), 走實際的 render 路徑, 標題
加上 `[test] ` 前綴. 這支用 `strict: true` 送, 所以 transport 失敗會回錯誤
而不是靜默成功.

`/send` `/resume` `/retry` `/send-now` 成功後會直接 `worker.tick!`, 不等
下一輪.

### 回應碼

| 碼 | 什麼時候 |
| --- | --- |
| 400 | 缺 `subject` / `content`; `rows` 超過上限 ( `/save` 是 `batch-max`, `/send-now` 是 `min(nostore-max, batch-max)` 而且不能為空 - 草稿可以存空清單 ); `scheduledtime` 無效; 對 `metadata` 批次排程; `/test` 時 user 沒有 username |
| 404 | 批次不存在, 或不屬於這個 scope; `/retry` 時沒有任何 `failed` 的 item |
| 409 | 狀態不允許 ( 見下方狀態機 ); 或內容已經不在 ( 不可續傳又不在 vault 裡 ) |
| 429 | 超過 `daily-max` |
| 1015 | 算不出寄件者 ( `detail` 沒給, host 的 `defaults` 沒給, mail-queue 的 `default-sender` 或 `sitename`+`domain` 也湊不出來 - 與 mail-queue 的 `batch` 同一套 fallback ) |

### detail 與 rows

`detail` 經 `normalize-detail` 收斂, 未列的欄位會被丟掉:

| 欄位 | 上限 |
| --- | --- |
| `subject` | 512 字 |
| `content` | 無 |
| `sender` `replyto` | 256 字 |
| `sendername` | 128 字 |
| `lng` | 16 字 |
| `columns` | 見下 |

`columns` 第一欄固定是 `email`, 其餘去重去空, 欄位名要過
`is-valid-column` ( ≤64 字, 不含 `{}"'<>` ).

`rows` 是 `[{email, vars}]`. `vars` 只留 `columns` 裡有的欄位, 缺的補空字串.
`email` 一定可以當變數用 ( 「您的帳號 {{email}}」 ), 直接取收件者位址本身,
不從 `row.vars` 拿 - 那才是權威的值, 而且舊樣板沒把 email 列進 `columns` 也
照樣能用.

`record` 只認 `full` / `metadata` / `none` 三個值, 其餘一律當 `full`.

### 狀態

批次 ( `mailspool.status` ) 是 `draft` / `scheduled` / `sending` / `paused` /
`done` / `canceled` / `aborted`. 轉換只有這幾條:

| 從 | 到 | 誰 |
| --- | --- | --- |
| `draft` | `scheduled` | `/send` |
| `draft` | `sending` | `/send-now` ( 建好 items 與 vault 之後才切 ) |
| `scheduled` | `sending` | worker `activate` ( 到排定時間 ) |
| `scheduled` `sending` | `paused` | `/pause` |
| `paused` | `scheduled` / `sending` | `/resume` ( 看 `starttime` 是不是空的 ) |
| `scheduled` `sending` `paused` | `canceled` | `/cancel` |
| `sending` | `done` | worker `finalize` ( 沒有 `pending` 也沒有 `sending` 的 item ) |
| `sending` `paused` | `aborted` | worker `abort-orphans` |
| `done` `canceled` `aborted` | `sending` | `/retry` |
| `done` | `sending` | worker `recover` |

最後一條容易漏看: worker 的 `recover` 會把已經 `done` 但還留著 `pending`
item 的 `resumable` 批次拉回 `sending` - 那是上一輪寄到一半 process 沒了,
item 在同一支 `recover` 裡被收回 pending 的情形. 沒有這段的話那些 item 會
永遠留在 pending, 因為 `drain` 只看 `sending` 的批次.

`abort-orphans` 收的是掛著 `sending` 或 `paused` 卻不在 vault 裡的不可續傳
批次 ( 見保存層級 ) - 那只可能是 process 重啟過, 沒有內容可以接手. 暫停中的
也一樣收, 因為按繼續也救不回來. 每輪都掃, 所以重啟後第一輪 tick 就會把狀態
修正, 不會有假裝還在寄的批次.

逐封 ( `mailspool_item.status` ): `pending` / `sending` / `sent` / `failed` /
`skipped`. 單封失敗會 `retry + 1` 打回 `pending`, 到 `max-retry` 才成
`failed`. 卡在 `sending` 超過 `stale-minutes` 的也走同一套 - `recover` 一樣
加 retry, 超過上限就判 `failed` 而不是放回 pending, 否則任何讓 `send-one`
整個逃走的錯誤都會讓那封信在 pending / sending 之間無限繞圈.

逐封 ( `mailspool_item.status` ): `pending` / `sending` / `sent` / `failed` /
`skipped`.

## 前端

`src/common.ls` 是樣板代換, **前後端共用** - 前端預覽與後端寄送要走同一份
邏輯, 否則會出現「預覽看到一種、收到信是另一種」.

前端透過 fedep 取用 ( `frontend/base/package.json` 已登記 `@servebase/mail`,
`dir: dist` ), 掛成 `window.sbmail`. 不叫 `mail` 是因為那個名字在 window 上
太泛容易撞; 不掛在 `servebase` 底下是因為那個命名空間由 `@servebase/core`
自己建, 不保證先載入.

| 方法 | 用途 |
| --- | --- |
| `render {subject, content}, vars` | 完整代換, 回 `{subject, html, text}` |
| `render-text tpl, vars` | 純文字欄位 ( subject ) 的代換 |
| `render-html tpl, vars` | html 欄位的代換, 值會 escape |
| `used-vars {subject, content}` | 樣板實際用到哪些欄位, 給寄出前的 lint 用 |
| `is-valid-column n` | 欄位名是否合法 |
| `format-sender {sender, sendername}` | 組出 `"名字" <位址>`; `sender` 已經是完整格式就原樣回傳, 沒有名字就只回位址, 沒有 `sender` 回空字串 |
| `escape-html v` / `to-text html` / `tighten html` | 工具 |

**兩個欄位的樣板語法不一樣**, 因為來源不一樣:

| 欄位 | 語法 | 為什麼 |
| --- | --- | --- |
| `subject` | `{{欄位名}}` | 純文字輸入 |
| `content` | `<span data-var="欄位名">…</span>` | 富文字編輯器 ( quill ) 產出, 變數是看得見的 token |

`used-vars` 兩邊都掃, 所以 lint 拿得到完整的欄位清單.

欄位名允許中文與空白 ( 標題列可以直接當欄位名 ), 不能含 `{}"'<>`.
**找不到的欄位代成空字串**而不是報錯 - 寄出前的 lint 會先提醒, 代換當下
不該擋下整批. `render-html` 的值一律 escape.

`render` 順手做了兩件跟正確性有關的事, 所以前端預覽務必走它而不是自己拼:
`tighten` 把 `<p>` 的 `margin:0` 寫成 inline style ( quill 靠自己的 css 讓
p 沒有邊距, email client 沒有那份 css, 不寫死的話寄出去行距就散開 ), 以及
`to-text` 產出純文字版給不吃 html 的 client.

## 資料表

`mailspool` / `mailspool_item`, 定義在這個模組的 `index.sql`, 與
`consent.sql` / `sharedb.sql` 一樣需要手動套用.

app 端建議在自己的 `config/*/db/` 放一個指到這裡的 symlink ( grantdash 的
`config/base/db/mailspool.sql` 就是 ). 建站的人只會看 `config/*/db`,
schema 藏在模組底下很容易被忽略; 但抄成兩份的話, 改了一邊另一邊就會悄悄
過期. `psql -f` 吃得下 symlink.

## 三種保存層級

`mailspool.record` 決定信件內容留不留在 DB:

| 值 | 行為 |
| --- | --- |
| `full` | 內容照常保存, 可排程、可續傳、可重送失敗的 |
| `metadata` | 照常排程, 但到終態 ( 完成或取消 ) 就清掉 content 與 vars |
| `none` | 內容從不寫進 DB, 只放在這個 process 的記憶體裡 |

`none` 是給「使用者可能把密碼打進信裡」這種情境的: 內容連一次 backup 的窗口
都沒有.

送出時整份內容與逐封的代換資料進一個 module-level 的 `vault` ( `Map`,
batch key 為 key ), 之後由 worker 照一般速率寄 — 與 `full` 走同一條
`drain` / `send-one`, 呼叫端送出就能離開.

**進 DB 的仍然有**: 標題、寄件者與回信址、每一位收件者的位址、每封的
寄送結果與 message id. 不進 DB 的是**本文**與**逐封的代換資料**.

代價是 process 重啟後接不下去 — 這種批次 `resumable = false`, 每輪 tick 的
`abort-orphans` 會把「掛著 `sending` 卻不在 vault 裡」的批次收成 `aborted`,
所以重啟後第一輪就會把狀態修正, 不會有假裝還在寄的批次.
`pause` / `resume` / `retry` 都不收這種批次 — 沒有內容可以接手.

## 設定

`config.mail.mailmerge` 底下, 全部可省略:

| 名稱 | 預設 | 說明 |
| --- | --- | --- |
| `interval` | 6000 | worker tick 間隔 (ms) |
| `batch-size` | 1 | 每輪寄幾封. 與 interval 一起決定速率 ( 預設 10 封/分 ) |
| `max-retry` | 3 | 單封重試上限 |
| `send-timeout` | 30000 | 單封等 transport 多久就放棄 (ms). 逾時判失敗且**不重試** - 逾時不代表沒寄出 |
| `stuck-minutes` | 10 | 一輪 tick 跑多久算卡死, 讓下一輪接手 |
| `stale-minutes` | 5 | `sending` 卡住多久視為 process 死掉, 回收重寄 |
| `retention-days` | 548 | 紀錄保留多久. email 是個資, 不該無限期留著 |
| `expire-interval` | 3600000 | 過期清理的頻率 (ms) |
| `nostore-max` | 1000 | 不落地批次的收件者上限. 內容整批留在記憶體, 要有個上限 |
| `batch-max` | 2000 | 一批最多幾位收件者. 擋誤操作 - 貼錯一份十萬列的表格 |
| `daily-max` | 10000 | 同一個 scope 24 小時內最多寄幾封. 超過回 429. 這是拒絕門檻不是排程手段, 要設在正常用途碰不到的位置 |
| `startup-delay` | 15000 | 開機後多久跑第一輪 (ms)。避開 session store 的啟動清理 |

## 測試

```
npx lsc module/base/mail/test/transport.ls
```

不用測試框架, 自己跑自己斷言, 有失敗就 exit 1. 需要本機的 postgres
( 連不上就跳過, 不當成失敗 ), 會自己建一個 scratch db 再丟掉.

測的是**寄信失敗**的那些路徑 - 那是平常碰不到的部分: 開發機的 mail-queue
通常開著 suppress, `send-directly` 根本走不到 `api.sendMail`, 所以 mailgun /
nodemailer 會丟出來的錯誤在一般操作下完全測不到. 這支把 mail-queue 換成可
程式化的假貨, 直接驅動 worker, 涵蓋: transport 一直 reject、同步 throw、
blacklist 查詢壞掉、部分收件者失敗、transport 永遠不回應, 以及卡住之後
worker 還接不接得了新批次.
