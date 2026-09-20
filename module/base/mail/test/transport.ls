#!/usr/bin/env lsc
#
# transport 失效測試.
#
#   npx lsc module/base/mail/test/transport.ls
#
# 不用 mocha - 這支自己跑自己斷言, 失敗時 exit code 非 0.
#
# 為什麼要有這支: 寄信失敗的路徑平常測不到. 開發機的 mail-queue 通常開著
# suppress, send-directly 根本走不到 api.sendMail, 所以 mailgun / nodemailer
# 會丟出來的那些錯誤在一般操作下完全碰不到. 這裡把 mail-queue 換成可程式化
# 的假貨, 用一個獨立的 scratch db, 直接驅動 worker, 看每一種失敗最後在 DB
# 裡長成什麼樣子.
#
# 需要本機的 postgres ( 連不上就 skip, 不當成失敗 ).

require! <[pg child_process path]>
{Pool} = pg
{exec-sync} = child_process

DB = \mailmerge_transport_test
root = path.join __dirname, \..

psql = (args) ->
  try exec-sync "psql #args", {stdio: <[ignore pipe ignore]>, encoding: \utf8}
  catch e => null

# # 準備

setup = ->
  if psql("-d postgres -tAc 'select 1'") == null
    console.log "postgres 連不上, 跳過這支測試."
    process.exit 0
  psql "-d postgres -q -c 'drop database if exists #DB'"
  psql "-d postgres -q -c 'create database #DB'"
  # index.sql 的 owner 欄位 FK 到 users, 這裡只需要一張能對得上的空殼
  psql "-d #DB -q -c 'create table users (key serial primary key, username text)'"
  psql "-d #DB -q -c \"insert into users (username) values ('tester')\""
  psql "-d #DB -q -f #{path.join root, 'index.sql'}"

teardown = (pool) ->
  p = if pool => pool.end! else Promise.resolve!
  p.catch(->).then ->
    psql "-d postgres -q -c 'drop database if exists #DB'"

# # 假的 mail-queue: 每個情境自己決定 send / in-blacklist 怎麼表現

mode = {}
mailq =
  cfg: {default-sender: '"Test" <no-reply@example.org>'}
  in-blacklist: (email) -> if mode.blacklist => mode.blacklist email else Promise.resolve false
  send: (payload, opt) -> mode.send payload, opt

tick-errors = []
backend =
  config: mail: mailmerge:
    # 不讓它自己跑, 由測試呼叫 tick
    interval: 3600000ms
    startup-delay: 3600000ms
    batch-size: 5
    max-retry: 3
    # 卡住的 item 立刻回收, 不然測試要等五分鐘
    stale-minutes: 0
    send-timeout: 500ms
    # 用實際會走到的值: 卡死的那一輪應該是由 send-timeout 解開, 而不是靠
    # stuck-minutes 那道後備. 設成 0 的話等於把鎖關掉, 就測不出東西了.
    stuck-minutes: 1
  i18n: t: (k) -> k
  log-mail:
    info: ->
    error: (o, msg) -> tick-errors.push msg
  mail-queue: mailq

# # 斷言

fails = 0
ok = (cond, name, detail = '') ->
  if cond => return console.log "  ok   #name"
  fails := fails + 1
  console.log "  FAIL #name#{if detail => "\n         #detail" else ''}"

# # 主體

main = ->
  setup!
  pool = new Pool {database: DB, max: 5, connectionTimeoutMillis: 3000}
  backend.db = pool
  # 假 router: 這支只測 worker, 不碰 route
  route = {} <<< {[k, (->)] for k in <[get post put delete use]>}
  mail = require path.join(root, 'dist/lib/index.js')
  worker = mail {backend, route}

  q = (sql, params = []) -> pool.query sql, params

  # 每個情境用自己乾淨的資料, 免得前一個情境沒收尾的 item 被後面的 tick
  # 用新的 mode 重寄 - 那會讓結果互相污染.
  reset = -> q "delete from mailspool"

  mkbatch = (emails) ->
    detail = {subject: 'hi {{who}}', content: '<p>hi</p>', columns: <[email who]>}
    q("""
    insert into mailspool (owner, scope, name, detail, status, record,
      resumable, expected, starttime, expiretime)
    values (1, 'test', 'b', $1, 'sending', 'full', true, $2, now(), now() + interval '1 day')
    returning key
    """, [detail, emails.length])
      .then (r) ->
        key = r.rows.0.key
        vals = emails.map (e, i) -> "($1, #{i}, '#e', 'pending')"
        q "insert into mailspool_item (batch, idx, email, status) values #{vals.join ','}", [key]
          .then -> key

  items = (key) ->
    q "select idx, status, retry, coalesce(error, '') as error from mailspool_item where batch = $1 order by idx", [key]
      .then (r) -> r.rows

  bstat = (key) -> q("select status from mailspool where key = $1", [key]).then (r) -> r.rows.0.status

  # tick 到沒有東西可做為止 ( 有上限, 免得真的無限跑 )
  ticks = (n = 8) -> [0 til n].reduce ((p) -> p.then -> worker.tick!), Promise.resolve!

  # 給「永遠不 settle」那個情境用: tick 不回來也要讓測試往下走
  bounded = (p, ms = 2500ms) ->
    Promise.race [p.then(-> \done), new Promise (res) -> setTimeout (-> res \stuck), ms]

  scenario = (name, fn) -> -> reset!.then -> console.log "\n#name"; fn!

  run = (list) -> list.reduce ((p, f) -> p.then f), Promise.resolve!

  run [
    scenario "transport 每次都 reject ( 401 / 連線被拒 / 5xx )", ->
      mode.send = -> Promise.reject new Error "401 Unauthorized"
      (key) <~ mkbatch(['a@x.com']).then _
      <~ ticks!.then _
      (its) <~ items(key).then _
      (st) <~ bstat(key).then _
      it0 = its.0
      ok it0.status == \failed, "重試到上限後標成 failed", "得到 #{it0.status}"
      ok it0.retry == 3, "retry 停在 max-retry", "得到 #{it0.retry}"
      ok it0.error.match(/401/), "錯誤訊息留下原文", it0.error
      ok st == \done, "批次照常收尾", "得到 #st"

    scenario "send 同步 throw ( 例如 sanitize 時 require jsdom 失敗 )", ->
      mode.send = -> throw new Error "socket hang up"
      (key) <~ mkbatch(['b@x.com']).then _
      <~ ticks!.then _
      (its) <~ items(key).then _
      (st) <~ bstat(key).then _
      it0 = its.0
      ok it0.status == \failed, "同步 throw 也要走進重試 / 放棄的路徑", "得到 #{it0.status}"
      ok it0.retry <= 3, "retry 不會無限往上爬", "得到 #{it0.retry}"
      ok st == \done, "批次不會永遠卡在 sending", "得到 #st"

    scenario "blacklist 查詢自己壞掉", ->
      mode.send = -> Promise.resolve {messageId: \ok}
      mode.blacklist = -> Promise.reject new Error "blacklist backend down"
      (key) <~ mkbatch(['c@x.com']).then _
      <~ ticks!.then _
      (its) <~ items(key).then _
      (st) <~ bstat(key).then _
      mode.blacklist = null
      it0 = its.0
      ok it0.status == \failed, "send 之前的錯誤也要被接住", "得到 #{it0.status}"
      ok st == \done, "批次不會永遠卡在 sending", "得到 #st"

    scenario "只有其中一位失敗", ->
      mode.send = (payload) ->
        if payload.to == 'bad@x.com' => Promise.reject new Error "550 mailbox unavailable"
        else Promise.resolve {messageId: "ok"}
      (key) <~ mkbatch(['ok1@x.com' 'bad@x.com' 'ok2@x.com']).then _
      <~ ticks!.then _
      (its) <~ items(key).then _
      (st) <~ bstat(key).then _
      got = its.map(-> it.status).join ' '
      ok (its.0.status == \sent and its.2.status == \sent), "其他人照常寄出", got
      ok its.1.status == \failed, "只有壞的那一位失敗", its.1.status
      ok st == \done, "批次照常收尾", "得到 #st"

    scenario "transport 永遠不回應", ->
      mode.send = -> new Promise (res, rej) -> void   # 永不 settle
      (key) <~ mkbatch(['d@x.com']).then _
      (r1) <~ bounded(worker.tick!).then _
      ok r1 == \done, "一輪 tick 不會被卡住的 transport 拖住", "得到 #r1"
      (its) <~ items(key).then _
      ok its.0.status == \failed, "逾時的那封標成 failed", "得到 #{its.0.status}"
      ok its.0.error.match(/timed out/), "錯誤訊息講清楚是逾時", its.0.error
      # 逾時不重試: 重試會讓同一個人收到第二封
      ok its.0.retry == 1, "逾時只算一次, 不會自動重寄", "retry=#{its.0.retry}"

    scenario "transport 卡住之後, worker 還接得了新批次", ->
      mode.send = -> new Promise (res, rej) -> void
      (k1) <~ mkbatch(['e@x.com']).then _
      <~ bounded(worker.tick!).then _
      mode.send = -> Promise.resolve {messageId: \ok}
      (k2) <~ mkbatch(['f@x.com']).then _
      <~ bounded(ticks(3)).then _
      (its) <~ items(k2).then _
      ok its.0.status == \sent, "新批次照常寄出 ( worker 沒有被鎖死 )", "得到 #{its.0.status}"
  ]
    .then ->
      console.log "\n#{if fails => "#fails 項失敗" else "全部通過"}"
      teardown pool .then -> process.exit (if fails => 1 else 0)
    .catch (e) ->
      console.error "\n測試本身爆炸了:", e
      teardown pool .then -> process.exit 2

main!
