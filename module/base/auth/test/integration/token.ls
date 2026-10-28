# 重設密碼 / email 驗證的 token: 只存 hash, 舊的明文 token 仍可用, 重設密碼送出時也檢查過期. 打真的 postgres.
# 假的部分: mail-queue ( 只記下寄了什麼 ), captcha, session. passwd.js / mail.js / user-store 與 db 都是真的.
#
#   npm test -- --integration token
#   ./node_modules/.bin/lsc module/base/auth/test/integration/token.ls
#
# 需要本機的 postgres ( 連不上就 exit 77 跳過 ), 會自己建一個 scratch db 再丟掉.

require! <[path child_process pg express body-parser lderror]>
{exec-sync} = child_process

DB = \servebase_token_test
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
  passwd = require(path.join auth, \dist/lib/passwd.js)(backend)
  mail = require(path.join auth, \dist/lib/mail.js)(backend)
  passwd.route!
  mail.route!
  app.use (err, req, res, next) -> res.status(400).send {id: lderror.id(err) or err.message}
  server = app.listen 0
  port = server.address!port

  call = (method, url, json) ->
    fetch "http://127.0.0.1:#port#url", {
      method, headers: {'content-type': 'application/json'}, redirect: \manual
      body: if json => JSON.stringify(json) else undefined
    }
  post = (url, json) -> call(\POST, url, json).then (r) -> r.json!catch -> {}
  visit = (url) ->
    call \GET, url .then (r) ->
      r.json!catch(-> {}).then (body = {}) ->
        {location: r.headers.get(\location), cookie: r.headers.get(\set-cookie) or '', id: body.id}
  login = (password) ->
    db.user-store.get({username: 'a@example.com', password, method: \local}).then(-> true).catch(-> false)
  stored = (table) -> db.query("select token from #table where owner = $1", [key]).then -> it.rows.map (.token)

  key = null
  run = ->>
    key := (await db.user-store.create {username: 'a@example.com', password: \password000, method: \local}).key

    section "重設密碼: token 只存 hash"
    await post \/api/auth/passwd/reset, {email: 'a@example.com'}
    token = mails[* - 1].token
    rows = await stored \pwresettoken
    ok (rows.length == 1 and /^sha256:[0-9a-f]{64}$/.test(rows.0) and !rows.0.includes(token)), "db 存的是 sha256, 不是原文"
    x = await visit "/auth/passwd/reset/#token"
    ok (x.location == '/auth/?passwd-change' and /password-reset-token=/.test(x.cookie)), "用信裡的 token 點連結"
    ok /Max-Age=\d+/.test(x.cookie), "cookie 有期限"
    x = await visit "/auth/passwd/reset/#{encodeURIComponent rows.0}"
    ok x.id == 403, "拿 db 裡的 hash 當 token 不行"
    x = await post "/api/auth/passwd/reset/#{encodeURIComponent rows.0}", {password: \password111}
    ok x.id == 403, "拿 hash 送出也不行"
    x = await post "/api/auth/passwd/reset/#token", {password: \password111}
    ok (!x.id and await login(\password111)), "重設成功"
    ok (await stored \pwresettoken).length == 0, "token 刪掉"
    x = await post "/api/auth/passwd/reset/#token", {password: \password222}
    ok x.id == 403, "token 只能用一次"

    section "重設密碼: 過期"
    await post \/api/auth/passwd/reset, {email: 'a@example.com'}
    token = mails[* - 1].token
    await db.query "update pwresettoken set time = now() - interval '15 minutes' where owner = $1", [key]
    x = await visit "/auth/passwd/reset/#token"
    ok x.location == '/auth/?passwd-expire', "超過有效時間 ( 10 分鐘 ), 點連結顯示過期"
    x = await post "/api/auth/passwd/reset/#token", {password: \password333}
    ok (!x.id and await login(\password333)), "已經點開的人, 送出時還在寬限內 ( 30 分鐘 ) 可以重設"
    await post \/api/auth/passwd/reset, {email: 'a@example.com'}
    token = mails[* - 1].token
    await db.query "update pwresettoken set time = now() - interval '41 minutes' where owner = $1", [key]
    x = await post "/api/auth/passwd/reset/#token", {password: \password444}
    ok (x.id == 403 and await login(\password333)), "超過寬限, 直接送出也不行 ( 以前不檢查 )"

    section "重設密碼: 改成 hash 之前發出的明文 token"
    await db.query "delete from pwresettoken where owner = $1", [key]
    legacy = "#{key}#{'ab' * 30}"
    await db.query "insert into pwresettoken (owner, token, time) values ($1, $2, now())", [key, legacy]
    x = await visit "/auth/passwd/reset/#legacy"
    ok x.location == '/auth/?passwd-change', "點連結可以用"
    x = await post "/api/auth/passwd/reset/#legacy", {password: \password555}
    ok (!x.id and await login(\password555)), "送出可以用"

    section "email 驗證"
    await mail.verify {req: {hostname: \example.test}, user: {key, username: 'a@example.com'}}
    token = mails[* - 1].token
    rows = await stored \mailverifytoken
    ok (rows.length == 1 and /^sha256:[0-9a-f]{64}$/.test(rows.0)), "db 存的是 sha256"
    x = await visit "/auth/mail/verify/#{encodeURIComponent rows.0}"
    ok x.location == '/auth/?mail-expire', "拿 hash 當 token 不行"
    x = await visit "/auth/mail/verify/#token"
    u = (await db.query "select verified from users where key = $1", [key]).rows.0
    ok (x.location == '/auth/?mail-verified' and u.verified?date), "用信裡的 token 驗證成功"
    await db.query "update users set verified = null where key = $1", [key]
    legacy = "#{key}-#{'cd' * 30}"
    await db.query "insert into mailverifytoken (owner, token, time) values ($1, $2, now())", [key, legacy]
    x = await visit "/auth/mail/verify/#legacy"
    ok x.location == '/auth/?mail-verified', "改成 hash 之前發出的明文 token 也可以"

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
