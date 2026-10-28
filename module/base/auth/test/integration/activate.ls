# 管理員代建帳號 ( users.system.pending ) 的啟用流程, 打真的 postgres.
# 假的部分: express session, mail-queue ( 只記下寄了什麼 ), captcha. activate.js / passwd.js / user-store 與 db 都是真的.
#
#   npm test -- --integration activate
#   ./node_modules/.bin/lsc module/base/auth/test/integration/activate.ls
#
# 需要本機的 postgres ( 連不上就 exit 77 跳過 ), 會自己建一個 scratch db 再丟掉.

require! <[path child_process pg express body-parser lderror]>
{exec-sync} = child_process

DB = \servebase_activate_test
root = path.join __dirname, \.., \.., \.., \.., \..
auth = path.join __dirname, \.., \..
aux = require \@servebase/backend/aux
user-store = require path.join(root, \backend/engine/db/postgresql/user-store.ls)

psql = (args) ->
  try exec-sync "psql #args", {stdio: <[ignore pipe ignore]>, encoding: \utf8}
  catch e => null

failed = 0
ok = (cond, msg) ->
  console.log "  #{if cond => 'ok  ' else 'FAIL'} #msg"
  if !cond => failed := failed + 1
section = -> console.log "\n#it"

setup = ->
  if psql("-d postgres -tAc 'select 1'") == null
    console.log "postgres 連不上, 跳過這支測試."
    process.exit 77
  psql "-d postgres -q -c 'drop database if exists #DB'"
  psql "-d postgres -q -c 'create database #DB'"
  psql "-d #DB -q -f #{path.join root, 'config/base/db/init.sql'}"

main = ->
  setup!
  pool = new pg.Pool {database: DB, max: 5}
  db = query: (q, p) -> pool.query q, p
  config = domain: \example.test
  db.user-store = new user-store {db, config}
  mails = []

  app = express!
  app.use body-parser.json!
  backend =
    db: db, config: config, i18n: {t: -> it}
    lngs: -> [\en]
    route: auth: aux.routecatch(express.Router!), app: aux.routecatch(app)
    middleware: captcha: (req, res, next) -> next!
    session: sync: (-> Promise.resolve!), delete: (-> Promise.resolve!)
    mail-queue:
      in-blacklist: -> Promise.resolve false
      by-template: (name, email, map) -> mails.push {name, email, token: map.token}; Promise.resolve!
  app.use \/api/auth, backend.route.auth
  activate = require(path.join auth, \dist/lib/activate.js)(backend)
  passwd = require(path.join auth, \dist/lib/passwd.js)(backend, {activate})
  activate.route!
  passwd.route!
  app.use (err, req, res, next) -> res.status(400).send {id: lderror.id(err) or err.message}
  server = app.listen 0
  port = server.address!port

  call = (method, url, json) ->
    fetch "http://127.0.0.1:#port#url", {
      method, headers: {'content-type': 'application/json'}, redirect: \manual
      body: if json => JSON.stringify(json) else undefined
    }
  post = (url, json) -> call(\POST, url, json).then (r) -> r.json!catch -> {}
  # GET 啟用連結: 回傳有沒有拿到 cookie
  visit = (token) ->
    call \GET, "/auth/activate/#token" .then (r) ->
      cookie = r.headers.get(\set-cookie) or ''
      {location: r.headers.get(\location), cookie: /activate-token=[0-9a-f]+/.test(cookie)}
  last-mail = -> mails[* - 1]
  row = (username) -> db.query("select * from users where username = $1", [username]).then -> it.rows.0
  req = {hostname: \example.test}

  run = ->>
    section "建立 pending 帳號"
    u = await activate.create {req, username: 'P@Example.com', displayname: \p, by: 7}
    m = last-mail!
    ok (m.name == \activate and m.email == 'p@example.com' and /^[0-9a-f]{64}$/.test(m.token)), "寄出啟用信"
    r = await row 'p@example.com'
    ok (r.key == u.key and !r.password and r.method == \local and !r.verified), "沒有密碼, 還沒驗證"
    ok (r.system.pending.by == 7 and r.system.pending.at), "system.pending = {by, at}"
    t = (await db.query "select * from activatetoken where owner = $1", [u.key]).rows
    ok (t.length == 1 and t.0.hash != m.token and t.0.hash.length == 64), "db 只存 hash"
    token1 = m.token

    section "pending 帳號不能登入或註冊"
    e = await db.user-store.get({username: 'p@example.com', password: \whatever, method: \local}).catch -> it
    ok lderror.id(e) == 1052, "密碼登入回 1052"
    e = await db.user-store.get({username: 'p@example.com', method: \google, create: true}).catch -> it
    ok lderror.id(e) == 1052, "第三方登入回 1052"
    e = await db.user-store.create({username: 'p@example.com', password: \password123, method: \local}).catch -> it
    ok lderror.id(e) == 1052, "註冊回 1052"
    e = await db.user-store.create({username: 'x@example.com', pending: {by: 1}}).then -> null
    ok !e, "pending 不受 accept-signup 限制"

    section "忘記密碼改寄啟用信"
    n = mails.length
    await post \/api/auth/passwd/reset, {email: 'p@example.com'}
    ok mails.length == n, "剛寄過 ( cooldown 內 ) 不重寄"
    await db.query "update activatetoken set createdtime = now() - interval '2 minutes' where owner = $1", [u.key]
    await post \/api/auth/passwd/reset, {email: 'p@example.com'}
    m = last-mail!
    ok (mails.length == n + 1 and m.name == \activate and m.token != token1), "過了 cooldown 寄出新的啟用信, 不是重設密碼信"
    r = await db.query "select count(*) as c from pwresettoken where owner = $1", [u.key]
    ok +r.rows.0.c == 0, "沒有產生重設密碼 token"
    token2 = m.token

    section "啟用連結 ( GET )"
    x = await visit \deadbeef
    ok (x.location == '/auth/?activate' and !x.cookie), "無效的 token 不給 cookie"
    x = await visit token1
    ok !x.cookie, "重寄後舊的 token 作廢"
    x = await visit token2
    ok (x.location == '/auth/?activate' and x.cookie), "有效的 token 放進 cookie"
    x = await visit token2
    ok x.cookie, "GET 不會用掉 token ( 掃描器先點過也沒關係 )"

    section "設定密碼 ( POST )"
    x = await post "/api/auth/activate/#token1", {password: \password123}
    ok x.id == 403, "舊的 token 不能用"
    x = await post "/api/auth/activate/#token2", {password: \short}
    ok x.id == 1031, "密碼太短回 1031"
    x = await post "/api/auth/activate/#token2", {password: \password123}
    ok !x.id, "啟用成功"
    r = await row 'p@example.com'
    ok (!r.system.pending and r.verified?date and r.method == \local and r.password), "pending 清掉, email 已驗證, 有密碼"
    user = await db.user-store.get({username: 'p@example.com', password: \password123, method: \local}).catch -> null
    ok user?key == u.key, "可以用新密碼登入"
    x = await post "/api/auth/activate/#token2", {password: \password456}
    ok x.id == 403, "token 只能用一次"
    x = await visit token2
    ok !x.cookie, "用過的 token GET 也無效"
    await post \/api/auth/passwd/reset, {email: 'p@example.com'}
    ok last-mail!name == \reset-password, "啟用後忘記密碼寄的是重設密碼信"

    section "過期"
    v = await activate.create {req, username: 'q@example.com', displayname: \q}
    token = last-mail!token
    await db.query "update activatetoken set ttl = now() - interval '1 second' where owner = $1", [v.key]
    x = await visit token
    ok !x.cookie, "過期的 token GET 無效"
    x = await post "/api/auth/activate/#token", {password: \password123}
    ok x.id == 403, "過期的 token POST 無效"

    section "管理員直接設密碼"
    hash = await db.user-store.hashing \password123
    w = await db.user-store.activate {key: v.key, hash, verified: false}
    r = await row 'q@example.com'
    ok (w and !r.system.pending and !r.verified and r.password), "pending 清掉, 但不算 email 驗證"
    r = await db.query "select count(*) as c from activatetoken where owner = $1 and deleted is not true", [v.key]
    ok +r.rows.0.c == 0, "token 一併作廢"
    w = await db.user-store.activate {key: v.key, hash}
    ok w == null, "不是 pending 時 activate 回 null"

    section "system 欄位"
    z = await db.user-store.create {
      username: 'r@example.com', password: \password123, method: \local, system: {renewpw: true}, force: true
    }
    r = await row 'r@example.com'
    ok (r.system.renewpw and z.system.renewpw and !r.config.authinfo), "renewpw 放在 system, 不在 config"

  run!
    .catch (e) -> console.error "\n測試本身爆炸了:", e; failed := failed + 1
    .then ->
      console.log "\n#{if failed => "#failed 項失敗" else '全部通過'}"
      server.close!
      pool.end!
    .then ->
      psql "-d postgres -q -c 'drop database if exists #DB'"
      process.exit(if failed => 1 else 0)

main!
