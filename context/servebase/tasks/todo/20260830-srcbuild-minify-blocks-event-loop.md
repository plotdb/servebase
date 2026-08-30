# srcbuild 的 minify 跟 server 搶同一條 event loop

dev server 啟動後幾秒內進來的請求, 有機會拿到資料庫錯誤頁 ( 使用者看到的是
「Ooops, Things Broken」)。追下去發現跟資料庫無關 —— 是 srcbuild 的 minify 把
event loop 佔住, 讓同一個 process 裡的 pg 連線握手來不及在逾時前完成。

與 `20260830-srcbuild-build-graph.md` 同一個套件但不同問題: 那份講的是相依圖與
增量建置的正確性 ( 已在 0.1.0 修掉 ), 這份講的是建置**佔用資源**的方式。
本地 checkout 在 `../srcbuild`, 撰寫時版本 0.1.2, 下面的行號已對 0.1.2 確認過。


## 位置

`src/ext/bundle.ls:384-385`

```livescript
return if type == \js => uglify-js.minify(o.code).code
else if type == \css => uglifycss.processString(o.code, uglyComments: true)
```

兩行都是同步呼叫, 純 JS 的 CPU 工作, 沒有 worker 也沒有 child process。壓一個
1.7MB 的 bundle 要好幾秒, 那幾秒裡整條 event loop 停住, 任何 callback 都不會跑
—— 而同一個 process 正在服務 HTTP 請求。


## 證據

取自 makechart 的 `server.log` ( 涵蓋 1556 天、343 次啟動、64033 筆紀錄 )：

    connection timeout 共                 38 次
    其中前 30 秒內有 build 事件的          38 / 38  (100%)
    距離最近一次啟動 < 30 秒的             28 / 38  ( 中位數 5 秒 )
    距離最近一次啟動 30 ~ 120 秒的          0 / 38
    錯誤前 30 秒內最長的單次 build 耗時     中位數 4483ms, 最高 70736ms
    出事的查詢                             session 查詢 36 次, session 寫入 2 次

30～120 秒那格是 **0**, 這個空洞是關鍵: 不是「啟動後一段時間不穩」, 而是集中在
初次建置那幾秒。剩下 10 次是後來的重建 —— 最近一次是下游跑了 fedep 動到所有
lib 檔案, 觸發連環重建, 期間單一 bundle 就花了 8.6 秒。

出事的都是 session 查詢, 因為那是任何請求的第一個查詢, 最先撞上。


## 為什麼是「逾時」而不只是「慢」

下游用 `pg.Pool` 且設了 `connectionTimeoutMillis: 2000` ( 取得連線的上限, 見
makechart `backend/engine/db/postgresql/index.ls:19` )。剛啟動的 process 沒有
暖連線 ( `idleTimeoutMillis` 30 秒, 開發時多半是冷的 ), 所以要走完整的 TCP +
auth 握手, 而握手需要好幾個 event loop 迴圈。計時器在卡住期間就到期了, loop
恢復時 pg-pool 直接 reject。

會不會出事取決於「loop 恢復時, 是連線完成先被處理, 還是過期的計時器先被處理」
—— 這就是它偶發的原因, 也是它存在很久卻一直沒人追的原因。

**不要用拉長 `connectionTimeoutMillis` 來解。** 已經討論過並否決: 那是遮蔽症狀,
而且會延後真正資料庫故障的回報。要修的是「建置不該跟伺服器搶資源」。


## 方向

把 minify 移出 event loop —— worker_threads 或 child process。

實作時注意:

 - `uglifycss` 那一行同樣是同步的, 一起處理。
 - 同一個 process 裡還有 lsc / stylus / pug 的編譯。先量各自佔比再決定要不要
   一併搬; log 顯示 `editor-base.min.js` 單次 8.6 秒, 那一段以 js minify 為主。
 - 傳輸成本要量: bundle 原始碼可到 1.7MB, 進出 worker 的字串複製不是零成本。
   有可能出現「搬走了阻塞, 但總時間變長」, 需要實測而不是推測。
 - **重建會連發**。這次的觸發就是 fedep 一次動到所有 lib, 同一個 bundle 在數秒
   內被重建好幾輪 ( log 裡看得到 editor-base 連續 8.6s / 6.4s / 3.4s )。搬到
   worker 之後仍應該讓「同一個 bundle 進行中的重建可取消或合併」, 否則只是把
   塞車搬到另一條路上, 啟動期一樣會排隊。


## 順帶

 - 下游 ( makechart `backend/engine/index.ls:294-297`, 這段來自 servebase )
   是 `@listen!` 之後才 `@watch`, 也就是伺服器在初次建置完成前就開始收請求。
   如果 srcbuild 能對外給一個「初次建置完成」的訊號, 下游就能自己選擇要不要等
   —— 這比各自猜要好, 也是這個問題最直接的緩解。
 - `@watch` 沒有依 NODE_ENV 分岔, 所以 production 首次啟動時若 bundle 不是最新的,
   同樣會走這條路。實務上 production 多半是預先建好的, 但那是慣例不是保證。
   ( 未查證實際部署流程, 這是讀 code 的推論。)


## 驗證方式

修好之後應該做得到:

 1. 啟動 dev server, 在第 1 秒內連續請求一個需要資料庫的頁面 —— 不應該再出現
    connection timeout。
 2. 建置期間的頁面回應時間不再有秒級尖峰 ( 這次觀察到首頁一次 9.6 秒 )。
 3. 上面那個 log 分析可以直接重跑當回歸測試: 統計 `module: build` 事件與 db
    錯誤的時間相關性, 修好後應該完全脫鉤。
