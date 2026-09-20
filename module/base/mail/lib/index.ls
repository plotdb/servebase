require! <[lderror re2js curegex]>
common = require "../common"

# 群發信: 收件清單 + 樣板 -> 逐封個人化的信, 排程寄送並追蹤每封的結果.
#
# 這一層不認識任何 host 的概念, 也不做權限判斷. 批次歸屬只有一個 `scope`
# 字串, 由 host 在掛載的 router 上先設好 `req.mailmerge.scope`:
#
#   route = aux.routecatch express.Router {mergeParams: true}
#   api.use \/mailmerge/:scope, route
#   route.use aux.signedin
#   route.use (req, res, next) ->
#     req.mailmerge = {scope: req.params.scope}
#     myperm.check {slug: req.params.scope, user: req.user, ...} .then -> next!
#   mail {backend, route}
#
# scope 從哪來不關這裡的事 - path param、上游的 middleware、子網域、
# 寫死的常數都行. router 底下的每一支都已經是「這個 user 對這個
# scope 有權」, 所以模組只負責一件事: 帶進來的 key 真的屬於這個 scope
# ( 見 get-batch ).
#
# 回傳 worker, 讓 host 能程式化觸發 ( 建好批次後直接開跑, 不必等下一輪 tick ).
({route, backend} = {}) <- (->module.exports = it) _
{db} = backend
rt = route

re-email = curegex.tw.get('email', re2js.RE2JS)
is-email = -> return !!re-email.exec(it or '')

# worker 參數. batch-size / interval 決定送信速率 ( 預設 1 封 / 6 秒 = 10 封/分 ).
#
# 預設取平均分布而非「一次 N 封再停久一點」: 同樣的每分鐘總量, 突發式的尖峰
# 對收信端來說比較像機器. 需要快的人自己調 - 真正的瓶頸從來不是 API 的每秒
# 上限, 而是寄件網域的信譽與暖機程度.
cfg = ({} <<< ((backend.config.mail or {}).mailmerge or {}))
cfg.interval ?= 6000ms
cfg.batch-size ?= 1
cfg.max-retry ?= 3
# 單封寄送等多久就放棄等待. 這不是效能門檻, 是「別讓 worker 卡死」的保險:
# transport 的 promise 要是永遠不 settle, 整輪 tick 就停在那裡, @running
# 再也放不掉 ( 見 tick ). nodemailer 自己的 socketTimeout 是 10 分鐘, 我們
# 要比它早動手; 正常一封信不管走 SMTP 還是 HTTP API 都遠低於這個值.
#
# 逾時**不重試**: 逾時不代表沒寄出去, 重試會寄出第二封給同一個人. 少寄一封
# 可以人工補, 重複寄不能收回.
cfg.send-timeout ?= 30000ms
# 一輪 tick 跑多久算是卡死, 讓下一輪接手. 見 tick.
cfg.stuck-minutes ?= 10
# `sending` 停在那裡超過這個時間, 視為 process 中途死掉, 回收重寄.
# 代價是極少數情況下可能重寄一封 ( sendMail 成功但回報前 crash ).
cfg.stale-minutes ?= 5
# 寄信紀錄保留多久. email 是個資, 留著不清不只是佔空間的問題;
# 實務上超過一年也幾乎不會再回查. 預設 1.5 年.
cfg.retention-days ?= 548
# 過期紀錄的清理頻率. 這件事不急, 沒必要每輪 tick 都掃一次全表.
cfg.expire-interval ?= 3600000ms
# 不落地批次一次最多幾封. 內容與代換資料整批放在記憶體裡直到寄完,
# 所以要有個上限 - 也順便擋掉「一次寄十萬封」這種一定是誤操作的情況.
cfg.nostore-max ?= 1000
# 開機後多久才跑第一輪. 見 worker.start 的說明.
cfg.startup-delay ?= 15000ms


# 不落地批次 ( record = 'none' ) 的內容. 本文與逐封的代換資料只放在這裡,
# 從不寫進 DB - 那正是「不落地」的意思.
#
#   batch key -> {detail, vars: {item key -> vars}}
#
# 只活在這個 process 的記憶體裡: 重啟就沒了, 那批也就接不下去. worker 每輪
# 都會把「掛著 sending 卻不在這裡」的批次照實收成 aborted ( abort-orphans ),
# 所以狀態不會騙人. 這是刻意的取捨 - 換來的是使用者送出後就能關掉視窗.

vault = new Map!

# # helpers

# 寄件者. 與 mail-queue 的 batch 同一套 fallback 規則.
default-sender = (lng) ->
  mcfg = (backend.mail-queue or {}).cfg or {}
  if mcfg.default-sender => return mcfg.default-sender
  if !(mcfg.sitename and mcfg.domain) => return null
  return "\"#{backend.i18n.t(mcfg.sitename, {lng})}\" <no-reply@#{mcfg.domain}>"

# 清單正規化. TSV 貼上與案件清單帶入最後都收斂成這個形狀,
# 後面的流程只認這一種格式.
normalize-rows = (rows = [], columns = []) ->
  if !Array.isArray(rows) => return []
  rows.map (row = {}, idx) ->
    vars = {}
    for name in columns => if name != \email =>
      v = (row.vars or {})[name]
      vars[name] = if v? => "#{v}" else ''
    email = "#{(row.email or '')}".trim!
    return {idx, email, vars}

normalize-columns = (columns = []) ->
  if !Array.isArray(columns) => return []
  # 第一欄固定是 email, 其餘去重去空.
  seen = {email: true}
  out = [\email]
  for name in columns =>
    name = "#{(name or '')}".trim!
    if !common.is-valid-column(name) => continue
    if seen[name] => continue
    seen[name] = true
    out.push name
  return out

# host 可以在 `req.mailmerge.defaults` 放一組預設的寄件者 / 回信址, 使用者
# 沒填時就用它. 在有 req 的當下 ( 存檔 / 試寄 / 不落地寄送 ) 就寫進 detail,
# 不留到寄送當下才解析 - worker 沒有 req, 而且「送出時看到什麼就寄什麼」
# 比「寄出前一刻的設定說了算」好理解.
normalize-detail = (detail = {}, defaults = {}) ->
  detail = {} <<< detail
  for k in <[sender sendername replyto]>
    if !"#{(detail[k] or '')}".trim! and defaults[k] => detail[k] = defaults[k]
  columns = normalize-columns detail.columns
  return {
    columns
    subject: "#{(detail.subject or '')}".substring(0, 512)
    content: "#{(detail.content or '')}"
    sender: if detail.sender => "#{detail.sender}".substring(0, 256) else null
    sendername: if detail.sendername => "#{detail.sendername}".substring(0, 128) else null
    replyto: if detail.replyto => "#{detail.replyto}".substring(0, 256) else null
    lng: if detail.lng => "#{detail.lng}".substring(0, 16) else null
  }

# 使用者勾了「含敏感資訊」就不保留內容. 只認白名單, 別讓 client 送進
# 未知的值 - 這個欄位決定的是要不要把信件內容留在 DB 裡.
normalize-record = (v) ->
  return if "#{(v or '')}" in <[full metadata none]> => "#{v}" else \full

# 批次只能從自己的 scope 取用. router 那層已經確認 user 對這個 scope 有權,
# 所以這裡把 scope 一起放進 where - 查不到就 404, 不區分「不存在」與
# 「不是這個 scope 的」, 後者若回 400 等於告訴對方那個 key 存在.
get-batch = ({key, scope}) ->
  if !key => return lderror.reject 400
  db.query """
  select * from mailspool where key = $1 and scope = $2 and deleted is not true
  """, [key, scope]
    .then (r = {}) ->
      batch = r.[]rows.0
      if !batch => return lderror.reject 404
      return batch

# record = 'metadata' 的批次到終態後, 把內容清掉. 留下的是「寄給誰 /
# 何時 / 成功或失敗」, 足夠追蹤, 但信件內容與變數不再留存.
#
# 保留 subject: 它跟 `name` 欄位一樣是未代換的樣板 ( {{團隊}} 通知 ),
# 對所有收件者都同一份, 不是個資, 而列表少了它就完全認不出是哪封信.
# 真正要清的是 content ( 本文 ) 與 vars ( 逐人的資料 ).
#
# 收尾與取消都要走這裡 - 取消掉的批次一樣不會再寄, 沒有理由把內容留著.
purge-content = (keys = []) ->
  if !keys.length => return Promise.resolve!
  db.query """
  update mailspool_item set vars = null where batch = any($1)
  """, [keys]
    .then -> db.query """
      update mailspool set detail = (detail - 'content' - 'columns')
      where key = any($1)
      """, [keys]

# 批次的統計, 列表與追蹤畫面都用這個.
stat-of = (keys = []) ->
  if !keys.length => return Promise.resolve {}
  db.query """
  select batch, status, count(*)::int as count from mailspool_item
  where batch = any($1) group by batch, status
  """, [keys]
    .then (r = {}) ->
      ret = {}
      for row in r.[]rows =>
        ret[row.batch] ?= {total: 0}
        ret[row.batch][row.status] = row.count
        ret[row.batch].total += row.count
      return ret


# # api

# 建立或更新草稿.
# 已排程 / 寄送中的批次不能改 - 改了會與已寄出的內容對不起來.
rt.post \/save, (req, res) ->
  {key, name, detail, rows} = req.body
  {scope} = req.mailmerge
  detail = normalize-detail detail, (req.mailmerge.defaults or {})
  rows = normalize-rows rows, detail.columns
  record = normalize-record req.body.record
  expiretime = new Date(Date.now! + cfg.retention-days * 86400000)
  saveparams = [
    (key or null), req.user.key, scope, "#{(name or '')}".substring(0, 256)
    detail, record, expiretime
  ]
  p = if !key => Promise.resolve!
  else
    get-batch {key, scope}
      .then (batch) -> if batch.status != \draft => return lderror.reject 409

  p
    .then -> db.query """
      insert into mailspool (key, owner, scope, name, detail, record, expiretime)
      values (coalesce($1, nextval('mailspool_key_seq')::int), $2, $3, $4, $5, $6, $7)
      on conflict (key) do update set
        name = $4, detail = $5, record = $6, expiretime = $7
      returning *
      """, saveparams
    .then (r = {}) ->
      batch = r.[]rows.0
      # 整批重寫 items: 草稿階段清單可以任意增刪, 逐列 diff 沒有意義.
      db.query "delete from mailspool_item where batch = $1", [batch.key]
        .then ->
          if !rows.length => return
          # email 無效的不丟掉, 標成 skipped 留在清單裡 - 使用者要看得到
          # 是哪幾列有問題, 而不是默默少幾封.
          values = []
          params = []
          for row, i in rows =>
            b = i * 5
            values.push "($#{b+1}, $#{b+2}, $#{b+3}, $#{b+4}, $#{b+5})"
            params ++= [
              batch.key, row.idx, row.email, row.vars
              (if is-email(row.email) => \pending else \skipped)
            ]
          db.query """
          insert into mailspool_item (batch, idx, email, vars, status)
          values #{values.join(',')}
          """, params
        .then -> res.send batch

# 搜尋比對標題 ( name 與 detail.subject ) 與收件者位址.
#
# 不搜內文: 敏感批次根本沒有內文可搜, 搜得到與搜不到會隨批次的保存層級而異,
# 那種「有時找得到」比單純找不到更難用. 標題與收件者則是每種批次都有.
rt.post \/list, (req, res) ->
  q = "#{(req.body.q or '')}".trim!
  like = if q => "%#{q.replace(/[\\%_]/g, '\\$&')}%" else null
  db.query """
  select key, owner, scope, name, status, record, resumable, expected,
    scheduledtime, starttime, donetime, createdtime,
    detail - 'content' as detail
  from mailspool m
  where scope = $1 and deleted is not true
    and ($2::text is null or (
      m.name ilike $2 or coalesce(m.detail->>'subject','') ilike $2
      or exists (select 1 from mailspool_item i where i.batch = m.key and i.email ilike $2)
    ))
  order by key desc
  """, [req.mailmerge.scope, like]
    .then (r = {}) ->
      list = r.[]rows
      stat-of list.map(-> it.key)
        .then (stat) ->
          for b in list => b.stat = stat[b.key] or {total: 0}
          res.send list

rt.post \/get, (req, res) ->
  (batch) <~ get-batch {key: req.body.key, scope: req.mailmerge.scope} .then _
  db.query """
  select * from mailspool_item where batch = $1 order by idx, key
  """, [batch.key]
    .then (r = {}) ->
      batch.items = r.[]rows
      res.send batch

# 送出. `scheduledtime` 為空表示立刻開始.
rt.post \/send, (req, res) ->
  (batch) <~ get-batch {key: req.body.key, scope: req.mailmerge.scope} .then _
  if batch.status != \draft => return lderror.reject 409
  detail = batch.detail or {}
  if !(detail.subject and detail.content) => return lderror.reject 400
  if !(common.format-sender(detail) or default-sender(detail.lng)) => return lderror.reject 1015
  scheduledtime = if req.body.scheduledtime => new Date(req.body.scheduledtime) else null
  if scheduledtime and isNaN(scheduledtime.getTime!) => return lderror.reject 400
  # 標記為敏感的批次不給排程. 內容要等寄完才清得掉, 排到明天就等於讓它在
  # DB 裡多躺一天 ( 期間的任何一次 backup 都會抓到 ).
  if batch.record == \metadata and scheduledtime => return lderror.reject 400
  db.query """
  update mailspool set status = 'scheduled', scheduledtime = $2
  where key = $1 and status = 'draft' returning *
  """, [batch.key, scheduledtime]
    .then (r = {}) ->
      if !r.[]rows.0 => return lderror.reject 409
      # 不等這一輪 tick, 排定時間已到就直接開工.
      if !scheduledtime => worker.tick!
      res.send r.rows.0

# 暫停. worker 只認 scheduled / sending 兩個狀態, 所以改成 paused 就停了.
#
# 已經在途中的那幾封不攔 - 它們在 mail-queue 手上了. 沒送完的會被
# `recover` 收回 pending, 就這樣停在暫停的批次底下等繼續.
rt.post \/pause, (req, res) ->
  (batch) <~ get-batch {key: req.body.key, scope: req.mailmerge.scope} .then _
  # 不落地的批次也能暫停 - 內容在 vault 裡, 停著不會掉. 唯一不能暫停的是
  # 既不可續傳又不在 vault 裡的, 那種本來就已經寄不下去了.
  if !(batch.resumable or vault.has batch.key) => return lderror.reject 409
  if batch.status not in <[scheduled sending]> => return lderror.reject 409
  db.query """
  update mailspool set status = 'paused' where key = $1 and status in ('scheduled','sending')
  returning *
  """, [batch.key]
    .then (r = {}) ->
      if !r.[]rows.0 => return lderror.reject 409
      res.send r.rows.0

# 繼續. 回到哪個狀態看它開工了沒 - 還沒 ( starttime 是空的 ) 就回
# scheduled, 讓 activate 依排定時間處理; 開工過就直接回 sending.
rt.post \/resume, (req, res) ->
  (batch) <~ get-batch {key: req.body.key, scope: req.mailmerge.scope} .then _
  if batch.status != \paused => return lderror.reject 409
  # 暫停期間重啟過的不落地批次: 內容已經不在了, 接不下去.
  if !(batch.resumable or vault.has batch.key) => return lderror.reject 409
  db.query """
  update mailspool
  set status = (case when starttime is null then 'scheduled' else 'sending' end)
  where key = $1 and status = 'paused' returning *
  """, [batch.key]
    .then (r = {}) ->
      if !r.[]rows.0 => return lderror.reject 409
      # 不等下一輪 tick
      worker.tick!
      res.send r.rows.0

# 取消. 已寄出的追不回來, 只能停掉還沒寄的.
rt.post \/cancel, (req, res) ->
  (batch) <~ get-batch {key: req.body.key, scope: req.mailmerge.scope} .then _
  if batch.status not in <[scheduled sending paused]> => return lderror.reject 409
  db.query """
  update mailspool_item set status = 'skipped', error = 'canceled', updatedtime = now()
  where batch = $1 and status = 'pending'
  """, [batch.key]
    .then -> db.query """
      update mailspool set status = 'canceled', donetime = now() where key = $1 returning *
      """, [batch.key]
    .then (r = {}) ->
      # 取消掉的批次不會再走 finalize, 內容得在這裡清 - 不然勾了
      # 「含敏感資料」卻中途取消的信, 本文就永遠留在 DB 裡.
      # 不落地的批次內容在記憶體, 取消時一起丟掉.
      vault.delete batch.key
      p = if batch.record == \metadata => purge-content [batch.key] else Promise.resolve!
      p.then -> res.send (r.[]rows.0 or {})

# 重送失敗的. 把 failed 打回 pending 並重置 retry.
rt.post \/retry, (req, res) ->
  (batch) <~ get-batch {key: req.body.key, scope: req.mailmerge.scope} .then _
  # 不落地的批次收尾時內容就從記憶體丟掉了, 沒有東西可以重寄. 放它過的話
  # item 會被打回 pending, 然後永遠留在那裡 - drain 不收這種批次.
  if !batch.resumable => return lderror.reject 409
  if batch.status not in <[done canceled aborted]> => return lderror.reject 409
  db.query """
  update mailspool_item set status = 'pending', retry = 0, error = null, updatedtime = now()
  where batch = $1 and status = 'failed'
  """, [batch.key]
    .then (r = {}) ->
      if !r.rowCount => return lderror.reject 404
      db.query """
      update mailspool set status = 'sending', donetime = null where key = $1 returning *
      """, [batch.key]
    .then (r = {}) ->
      worker.tick!
      res.send (r.[]rows.0 or {})

# 試寄一封給自己. 用實際的 render 路徑, 所以看到的就是收件者會看到的.
# 內容不落地的寄送. 批次與逐封結果照樣進 DB ( 所以事後查得到寄給誰、
# 誰失敗 ), 但 content 與 vars 從頭到尾不寫進來 - 連一次 backup 的窗口
# 都沒有.
#
# 代價是斷了就補不回來: 沒有內容, worker 無從續傳, 所以這種批次標成
# resumable = false, 中斷時會被收成 `aborted` 而不是 `done`.
#
# 前端逐批呼叫: 第一批不帶 key, 拿回新建的批次 key; 之後每批帶著它,
# 最後一批加上 `final` 收尾.
# 不落地寄送. 內容與代換資料不進 DB, 放進 vault 之後就交給 worker,
# 速率與可續傳批次一致 ( batch-size / interval ).
#
# 呼叫端送出就可以離開 - 內容在 server 的記憶體裡, 不需要瀏覽器留著續推.
# 代價是 process 重啟後這批接不下去, 會被收成 aborted.
#
# 進 DB 的仍然有: 標題、寄件者 / 回信址、每一位收件者的位址與寄送結果.
# 不進 DB 的是本文與逐封的代換資料.
rt.post \/send-now, (req, res) ->
  {scope} = req.mailmerge
  detail = normalize-detail req.body.detail, (req.mailmerge.defaults or {})
  if !(detail.subject and detail.content) => return lderror.reject 400
  rows = normalize-rows req.body.rows, detail.columns
  if !rows.length => return lderror.reject 400
  if rows.length > cfg.nostore-max => return lderror.reject 400
  if !(common.format-sender(detail) or default-sender(detail.lng)) => return lderror.reject 1015

  # 只留得以辨識這批信的欄位.
  meta = detail{subject, sender, sendername, replyto, lng}
  # 先建成 draft: worker 只看 sending, 這樣在 items 與 vault 都就位之前,
  # 中途跑起來的 tick 不會把它當成沒有內容的孤兒收掉.
  db.query """
  insert into mailspool (owner, scope, name, detail, status, record,
    resumable, expected, starttime, expiretime)
  values ($1, $2, $3, $4, 'draft', 'none', false, $5, now(), $6)
  returning *
  """, [
    req.user.key, scope, detail.subject.substring(0, 256), meta, rows.length
    new Date(Date.now! + cfg.retention-days * 86400000)
  ]
    .then (r = {}) ->
      batch = r.[]rows.0
      if !batch => return lderror.reject 500
      values = []
      params = []
      for row, i in rows
        params.push batch.key, i, row.email
        n = params.length
        values.push "($#{n - 2}, $#{n - 1}, $#{n}, 'pending')"
      db.query """
      insert into mailspool_item (batch, idx, email, status)
      values #{values.join(',')}
      returning key, idx
      """, params
        .then (r2 = {}) ->
          vars = {}
          for it in r2.[]rows => vars[it.key] = (rows[it.idx] or {}).vars or {}
          vault.set batch.key, {detail, vars}
          db.query """
          update mailspool set status = 'sending' where key = $1 returning *
          """, [batch.key]
        .then (r3 = {}) ->
          # 不等下一輪 tick
          worker.tick!
          res.send (r3.[]rows.0 or batch)

rt.post \/test, (req, res) ->
  {detail, vars} = req.body
  if !req.user.username => return lderror.reject 400
  detail = normalize-detail detail, (req.mailmerge.defaults or {})
  if !(detail.subject and detail.content) => return lderror.reject 400
  sender = common.format-sender(detail) or default-sender(detail.lng)
  if !sender => return lderror.reject 1015
  payload = common.render detail, (vars or {})
  payload.subject = "[test] #{payload.subject}"
  if detail.replyto => payload.replyTo = detail.replyto
  sending = backend.mail-queue.send do
    {to: req.user.username, from: sender} <<< payload{subject, html, text, replyTo}
    {now: true, strict: true}
  sending.then -> res.send {}


# # worker
#
# queue 放在 DB 而非 mail-queue 的記憶體 @list: 重啟後要能接著跑,
# 而且每封的結果都要留下來給追蹤畫面看.

worker =
  running: false
  timer: null

  start: ->
    if @timer or !backend.mail-queue => return
    # 開機時先讓路. session store 在啟動後 3 秒會跑一次
    # `delete from session where ttl < now()`, 而 pg pool 的
    # connectionTimeoutMillis 只有 2 秒 - 這段時間擠進去很容易拿不到連線,
    # log 就會出現 mailspool_item 的 connection timeout.
    #
    # 這裡不急: 要接手的是上一輪留下的批次, 晚十幾秒開始沒有差別.
    @timer = setTimeout do
      ~>
        @timer = setInterval (~> @tick!), cfg.interval
        # 重啟時上一輪可能留下 sending 中的批次, 讓它自己接下去.
        @tick!
      cfg.startup-delay

  tick: ->
    # @running 是防兩輪重疊, 但它只在鏈的結尾放掉 - 只要有任何一條路徑
    # 永遠不 settle, 這個鎖就再也解不開, 之後每一次 tick 都直接 return,
    # 整個 worker 從此不動. 所以記下開始時間, 卡太久就讓新的一輪接手
    # ( 舊那輪留下的 sending item 由 recover 收拾 ).
    if @running and (Date.now! - (@started-at or 0)) < cfg.stuck-minutes * 60000ms
      return Promise.resolve!
    @running = true
    @started-at = Date.now!
    Promise.resolve!
      .then ~> @recover!
      .then ~> @reopen!
      .then ~> @activate!
      .then ~> @drain!
      .then ~> @finalize!
      .then ~> @abort-orphans!
      .then ~> @expire!
      .catch (err) -> backend.log-mail.error {err}, "mailmerge worker tick failed"
      .then ~> @running = false

  # 被中斷的 item 回收. retry 照加, 免得一封信一直卡在 crash - 重送 - crash.
  #
  # 超過上限的直接判失敗, 不再放回 pending: 沒有這一段的話, 任何讓 send-one
  # 整個逃走 ( 而不是走到它自己的 catch ) 的錯誤, 都會讓那封信在
  # pending -> sending -> pending 之間無限繞圈, retry 一路往上爬卻永遠不會
  # 停下來.
  recover: ->
    db.query """
    update mailspool_item
    set status = (case when retry + 1 >= $2 then 'failed' else 'pending' end),
      retry = retry + 1,
      error = (case when retry + 1 >= $2
        then coalesce(error, 'interrupted repeatedly') else error end),
      updatedtime = now()
    where status = 'sending' and updatedtime < now() - ($1 || ' minutes')::interval
    """, ["#{cfg.stale-minutes}", cfg.max-retry]

  # 已收尾的批次又冒出待處理 item ( 中斷回收, 或 retry 重送 ) 就重新開工.
  # 沒有這段的話, 那些 item 會永遠留在 pending - drain 只看 sending 的批次.
  reopen: ->
    db.query """
    update mailspool set status = 'sending', donetime = null
    where status = 'done' and resumable and exists (
      select 1 from mailspool_item i
      where i.batch = mailspool.key and i.status = 'pending'
    )
    """

  # 到期的排程批次開工.
  activate: ->
    db.query """
    update mailspool set status = 'sending', starttime = coalesce(starttime, now())
    where status = 'scheduled' and deleted is not true
      and (scheduledtime is null or scheduledtime <= now())
    """

  # 撈一批待寄的送出去.
  #
  # `for update ... skip locked` 讓多個 instance 同時跑也不會重複寄同一封.
  # 目前是單一 process, 但這個成本很低, 之後要橫向擴充時不用回頭改。
  #
  # 不落地的批次另外用 vault 的 key 圈住: 它的內容只在某一個 process 的
  # 記憶體裡, 別的 instance 就算認領到也寄不出來.
  drain: ->
    db.query """
    update mailspool_item set status = 'sending', updatedtime = now()
    where key in (
      select i.key from mailspool_item i
      join mailspool m on m.key = i.batch
      where i.status = 'pending' and m.status = 'sending'
        and (m.resumable or m.key = any($2::int[]))
        and m.deleted is not true
      order by i.batch, i.idx
      limit $1
      for update of i skip locked
    )
    returning *
    """, [cfg.batch-size, [...vault.keys!]]
      .then (r = {}) ~>
        # 子查詢的 order by 只決定選中哪幾封, returning 的順序不保證跟著它,
        # 所以這裡自己排 - 不排的話同一批的寄送順序會跳來跳去,
        # 收件者收到信的先後跟清單上的順序對不起來.
        items = r.[]rows.sort (a, b) -> (a.batch - b.batch) or (a.idx - b.idx)
        if !items.length => return
        keys = [...new Set(items.map(-> it.batch))]
        db.query "select * from mailspool where key = any($1)", [keys]
          .then (r = {}) ~>
            batches = {}
            for b in r.[]rows => batches[b.key] = b
            # 逐封依序寄, 不併發: 速率由 batch-size / interval 控制,
            # 併發只會讓 SMTP 更容易擋我們.
            items.reduce do
              (p, item) ~> p.then ~> @send-one item, batches[item.batch]
              Promise.resolve!

  send-one: (item, batch) ->
    if !batch => return @mark item, \failed, "batch missing"
    # 不落地的批次內容在 vault 裡, DB 的 detail 只有標題與寄件資訊.
    held = vault.get batch.key
    detail = if held => held.detail else (batch.detail or {})
    vars = if held => (held.vars[item.key] or {}) else (item.vars or {})
    sender = common.format-sender(detail) or default-sender(detail.lng)
    if !sender => return @mark item, \failed, "no sender available"
    # catch 要包住整條路徑, 不是只包 send 回傳的 promise. 這條路上還有
    # blacklist 查詢、render、以及 send 自己在建 promise 之前做的事
    # ( 例如 sanitize 時才 lazy require 的 jsdom ) - 那些是同步 throw,
    # 只掛在 send 結果上的 catch 接不到. 漏掉的話那一封會繞過重試上限,
    # 卡在 sending 被 recover 一輪一輪打回 pending, 而且那一輪的
    # finalize / expire 也全被跳過.
    sending = Promise.resolve!
      .then ~> backend.mail-queue.in-blacklist item.email
      .then (blocked) ~>
        if blocked => return @mark item, \skipped, "blacklisted"
        payload = common.render detail, vars
        # nodemailer 的欄位是 `replyTo`, 不是 detail 裡存的 `replyto`.
        if detail.replyto => payload.replyTo = detail.replyto
        # 先存成變數再接 .then - 直接接在 `do` 的最後一個參數後面,
        # 會被當成那個參數的方法鏈.
        sent = backend.mail-queue.send do
          {to: item.email, from: sender} <<< payload{subject, html, text, replyTo}
          {now: true, strict: true}
        @wait sent
          .then (info = {}) ~> @mark item, \sent, null, (info or {}).messageId
    sending.catch (err) ~>
      msg = "#{err.message or err}"
      # 逾時不重試 - 信可能已經寄出去了, 只是回應沒回來. 重試會讓同一個人
      # 收到第二封, 那比少寄一封糟. 要補由人決定.
      if err and err.mail-timeout =>
        return @mark item, \failed, msg, null, true
      if item.retry + 1 >= cfg.max-retry =>
        return @mark item, \failed, msg, null, true
      # 還有機會就丟回 pending, 下一輪 tick 再試.
      db.query """
      update mailspool_item set status = 'pending', retry = retry + 1,
        error = $2, updatedtime = now() where key = $1
      """, [item.key, msg]

  # 等 transport, 但不等到天荒地老. 見 cfg.send-timeout 的說明.
  wait: (p) ->
    if !cfg.send-timeout => return p
    timer = null
    guard = new Promise (res, rej) ->
      timer := setTimeout do
        ->
          err = new Error "send timed out after #{cfg.send-timeout}ms (may or may not have been delivered)"
          err.mail-timeout = true
          rej err
        cfg.send-timeout
    racing = Promise.race [p, guard]
    racing
      .then (v) -> clearTimeout timer; return v
      .catch (e) -> clearTimeout timer; throw e

  # `bump`: 這次失敗算一次重試. 設定類錯誤 ( 沒有寄件者等 ) 不該灌 retry,
  # 那不是「試過但失敗」, 修好設定重送就好.
  mark: (item, status, error = null, msgid = null, bump = false) ->
    db.query """
    update mailspool_item set status = $2, error = $3, msgid = $4,
      retry = (case when $5 then retry + 1 else retry end),
      sendtime = (case when $2 = 'sent' then now() else sendtime end),
      updatedtime = now()
    where key = $1
    """, [item.key, status, error, msgid, !!bump]

  # 沒有待處理 item 的批次收尾.
  # 沒有待處理 item 的批次收尾. 不落地的批次也走這裡 - 它的 item 是送出時
  # 一次建好的, 「沒有 pending 也沒有 sending」就真的是寄完了.
  finalize: ->
    db.query """
    update mailspool set status = 'done', donetime = now()
    where status = 'sending' and (resumable or key = any($1::int[]))
      and not exists (
        select 1 from mailspool_item i
        where i.batch = mailspool.key and i.status in ('pending','sending')
      )
    returning key, record
    """, [[...vault.keys!]]
      .then (r = {}) ->
        # 寄完就把內容從記憶體拿掉, 不要留著.
        for row in r.[]rows => vault.delete row.key
        purge-content r.[]rows.filter(-> it.record == \metadata).map(-> it.key)

  # 掛著 sending / paused 的不落地批次, 內容卻不在 vault 裡 - 那只可能是
  # process 重啟過. 沒有內容可以接手, 照實標成 aborted, 不要讓它一直掛著
  # 假裝還寄得下去 ( 暫停中的也一樣, 按繼續也救不回來 ).
  # 每輪都掃, 所以重啟後第一輪 tick 就會把狀態修正, 不必等逾時.
  abort-orphans: ->
    db.query """
    update mailspool set status = 'aborted', donetime = now()
    where status in ('sending','paused') and not resumable and deleted is not true
      and not (key = any($1::int[]))
    returning key
    """, [[...vault.keys!]]
      .then (r = {}) ->
        if r.rowCount => backend.log-mail.info "mailspool: #{r.rowCount} non-resumable batch(es) aborted"

  # 過期紀錄清理. email 是個資, 不該無限期留著.
  # cascade 會一併帶走 items.
  expire: ->
    now = Date.now!
    if @expired-at and (now - @expired-at) < cfg.expire-interval => return Promise.resolve!
    @expired-at = now
    # draft 也要納入: 建好草稿卻一直沒送出的批次, 內容 ( 含勾了敏感資料的 )
    # 已經在 DB 裡了, 不清的話就永遠留著.
    db.query """
    delete from mailspool
    where expiretime is not null and expiretime < now()
      and status in ('draft','done','canceled','aborted')
    """
      .then (r = {}) ~>
        if r.rowCount => backend.log-mail.info "mailspool: #{r.rowCount} expired batch(es) removed"

worker.start!

# 交給 host. 其他模組能程式化觸發 ( 例如「截止前未送件提醒」建好批次後直接
# 開跑, 不必等下一輪 tick ), 測試也從這裡拿到 worker.
return worker
