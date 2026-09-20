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

模組只認 `req.mailmerge.scope`, **不在乎它從哪來** - path param、上游的
middleware、子網域、寫死的常數都行. router 底下的每一支
都已經是「這個 user 對這個 scope 有權」, 所以模組不做任何權限判斷, 只負責
確認帶進來的 `key` 真的屬於這個 scope ( 見 `get-batch` ).

`aux.routecatch` 只包 `get/post/put/delete`, 不包 `use` - middleware 裡的
promise 要自己 `.catch next`.

回傳 worker, 讓 host 能程式化觸發 (`worker.tick!`) — 例如另一個排程建好批次後
直接開跑, 不必等下一輪 tick.

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
