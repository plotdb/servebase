# 2FA 的 API 與登入流程, 打真的 postgres.
# 假的部分: express session ( 每個 client 一個物件, 用 `x-sid` header 區分 ), passport 的 req.login,
# 以及帳密那一步 ( `/test/login` 直接查 user 後走 mfa.gate ). mfa.js 本身與 db 都是真的.
#
#   npm test -- --integration auth
#   ./node_modules/.bin/lsc module/base/auth/test/integration/mfa.ls
#
# 需要本機的 postgres ( 連不上就 exit 77 跳過 ), 會自己建一個 scratch db 再丟掉.

require! <[path child_process pg express body-parser lderror]>
{exec-sync} = child_process

DB = \servebase_mfa_test
root = path.join __dirname, \.., \.., \.., \.., \..
auth = path.join __dirname, \.., \..
aux = require \@servebase/backend/aux
throttle = require \@servebase/backend/throttle
user-store = require path.join(root, \backend/engine/db/postgresql/user-store.ls)
{totp} = require path.join(auth, \dist/lib/totp.js)

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
  config = auth: mfa: {enabled: true, keys: {k1: \test-key}, current: \k1, issuer: \Test}
  db.user-store = new user-store {db, config}
  deleted = []
  sessions = {}

  app = express!
  app.use body-parser.json!
  app.use (req, res, next) ->
    sid = req.header \x-sid
    req.session-ID = sid
    req.session = sessions[sid] = sessions[sid] or {}
    req.user = req.session.user
    req.login = (u, cb) -> sessions[sid] = req.session = {user: u}; req.user = u; cb!
    next!
  backend =
    db: db, config: config, i18n: {t: -> it}
    route: auth: aux.routecatch(express.Router!), app: aux.routecatch(app)
    session:
      sync: -> Promise.resolve!
      delete: (o) -> deleted.push o; Promise.resolve!
  app.use \/api/auth, backend.route.auth
  login = ({req, user}) -> new Promise((res) -> req.login user, res).then -> {loggedin: true}
  mfa = require(path.join auth, \dist/lib/mfa.js)(backend, {login})
  mfa.route!
  # 帳密那一步的替身: 不驗密碼, 直接走 gate
  app.post \/test/login, (req, res, next) ->
    db.query "select * from users where username = $1", [req.body.username]
      .then (r) ->
        user = r.rows.0
        mfa.gate {req, user, provider: req.body.provider or \local}
          .then (ret) -> if ret => {mfa: ret} else login {req, user}
      .then -> res.send it
      .catch next
  app.use (err, req, res, next) -> res.status(400).send {id: lderror.id(err) or err.message}
  server = app.listen 0
  port = server.address!port

  call = (sid, method, url, json) ->
    fetch "http://127.0.0.1:#port#url", {
      method, headers: {'content-type': 'application/json', 'x-sid': sid}
      body: if json => JSON.stringify(json) else undefined
    }
      .then (r) -> r.json!catch -> {}

  run = ->>
    hash = await db.user-store.hashing \password123
    r = await db.query """
    insert into users (username, password, method, displayname) values ('a@b.c', $1, 'local', 'a') returning key
    """, [hash]
    key = r.rows.0.key

    section "沒有 2FA 的登入"
    x = await call \s1, \POST, \/test/login, {username: 'a@b.c'}
    ok x.loggedin, "直接登入"
    x = await call \s1, \GET, \/api/auth/mfa
    ok (x.enabled and x.methods.length == 0 and x.password == true), "狀態: 未啟用, 啟用時要密碼"

    section "綁定"
    x = await call \s1, \POST, \/api/auth/mfa/totp/enable, {code: \000000, password: \password123}
    ok x.id == 1013, "沒有先 setup 回 1013"
    setup-ret = await call \s1, \POST, \/api/auth/mfa/totp/setup
    secret = setup-ret.secret
    ok (secret and /^otpauth:\/\/totp\/Test%3Aa%40b.c\?secret=/.test(setup-ret.uri) and /<svg/.test(setup-ret.qr)),
      "setup 回傳 secret / uri / svg qr"
    ok /^k1:/.test(sessions.s1.mfa-setup.secret), "session 裡的 secret 有加密"
    x = await call \s1, \POST, \/api/auth/mfa/totp/enable, {code: \000000, password: \password123}
    ok x.id == 1045, "錯的碼回 1045"
    x = await call \s1, \POST, \/api/auth/mfa/totp/enable, {code: totp.generate({secret}), password: \wrong}
    ok x.id == 1030, "錯的密碼回 1030"
    # 啟用時用的碼之後不能再用, 所以這裡用上一個時間窗的碼, 登入時才有碼可用
    prev = -> totp.generate {secret, t: Date.now! - 30000}
    cur = -> totp.generate {secret}
    x = await call \s1, \POST, \/api/auth/mfa/totp/enable, {code: prev!, password: \password123}
    ok (Array.isArray(x.recovery) and x.recovery.length == 10), "啟用, 拿到 10 組復原碼"
    codes = x.recovery
    row = (await db.query "select * from mfa where owner = $1", [key]).rows.0
    ok (row and /^k1:/.test(row.secret) and !row.secret.includes(secret)), "db 裡的 secret 有加密"
    ok (deleted.length == 1 and deleted.0.except == \s1), "其他 session 被登出, 留下目前這個"
    ok !sessions.s1.mfa-setup, "setup 狀態已清掉"
    x = await call \s1, \POST, \/api/auth/mfa/totp/setup
    ok x.id == 1011, "已啟用時再 setup 回 1011"

    section "有 2FA 的登入"
    x = await call \s2, \POST, \/test/login, {username: 'a@b.c'}
    ok (x.mfa and x.mfa.methods.0 == \totp and !sessions.s2.user), "回傳要 2FA, 還沒登入"
    x = await call \s2, \GET, \/api/auth/mfa
    ok x.id == 1000, "pending 狀態不算登入"
    x = await call \s2, \POST, \/api/auth/mfa/verify, {method: \totp, code: \000000}
    ok (x.id == 1045 and !sessions.s2.user), "錯的碼回 1045, 沒有登入"
    x = await call \s2, \POST, \/api/auth/mfa/verify, {method: \recovery, code: 'aaaaa-aaaaa'}
    ok (x.id == 1045 and !sessions.s2.user), "錯的復原碼回 1045, 沒有登入"
    x = await call \s2, \POST, \/api/auth/mfa/verify, {method: \sms, code: \1}
    ok x.id == 1015, "沒啟用的方法回 1015"
    x = await call \s2, \POST, \/api/auth/mfa/verify, {method: \totp, code: prev!}
    ok x.id == 1050, "啟用時用過的碼不能再用, 回 1050 code consumed"
    ok sessions.s2.mfa-pending.attempt == 2, "1050 不消耗這次登入的嘗試次數 ( 只算前面兩次錯的 )"
    x = await call \s2, \POST, \/api/auth/mfa/verify, {method: \totp, code: cur!}
    ok (x.loggedin and sessions.s2.user.key == key and !sessions.s2.mfa-pending), "目前的碼可以登入"
    await call \s3, \POST, \/test/login, {username: 'a@b.c'}
    x = await call \s3, \POST, \/api/auth/mfa/verify, {method: \totp, code: cur!}
    ok x.id == 1050, "同一組碼在別的 session 也不能再用 ( 1050 )"

    section "重複使用同一組碼 ( config.auth.mfa.reuse )"
    # 預設 session: s2 剛用 cur! 登入, 登入時 session 換新, 同一組碼在 s2 仍可再用
    x = await call \s2, \POST, \/api/auth/mfa/recovery, {code: cur!}
    ok x.recovery?length == 10, "reuse = session: 同一個 session 可以再用 ( 跨過登入時的 session 換新 )"
    codes = x.recovery
    config.auth.mfa.reuse = false
    x = await call \s2, \POST, \/api/auth/mfa/recovery, {code: cur!}
    ok x.id == 1050, "reuse = false: 同一個 session 也不行"
    config.auth.mfa.reuse = true
    await call \s7, \POST, \/test/login, {username: 'a@b.c'}
    x = await call \s7, \POST, \/api/auth/mfa/verify, {method: \totp, code: cur!}
    ok (x.loggedin and sessions.s7.user), "reuse = true: 別的 session 也可以"
    delete config.auth.mfa.reuse

    section "復原碼"
    x = await call \s3, \POST, \/api/auth/mfa/verify, {method: \recovery, code: codes.0.toUpperCase!replace(\-, ' ')}
    ok (x.loggedin and x.recovery.remain == 9), "復原碼可以登入 ( 忽略大小寫與分隔 ), 剩 9 組"
    await call \s4, \POST, \/test/login, {username: 'a@b.c'}
    x = await call \s4, \POST, \/api/auth/mfa/verify, {method: \recovery, code: codes.0}
    ok x.id == 1045, "用過的復原碼不能再用"

    section "一次登入的限制"
    for i from 0 til 4 => await call \s4, \POST, \/api/auth/mfa/verify, {method: \totp, code: \000000}
    x = await call \s4, \POST, \/api/auth/mfa/verify, {method: \recovery, code: codes.1}
    ok (x.id == 1049 and !sessions.s4.mfa-pending), "第 6 次回 1049, pending 清掉"
    await call \s5, \POST, \/test/login, {username: 'a@b.c'}
    sessions.s5.mfa-pending.exp = Date.now! - 1
    x = await call \s5, \POST, \/api/auth/mfa/verify, {method: \recovery, code: codes.1}
    ok x.id == 1013, "逾時回 1013"
    x = await call \s9, \POST, \/api/auth/mfa/verify, {method: \totp, code: \000000}
    ok x.id == 1000, "沒有 pending 回 1000"

    section "帳號鎖定 ( 15 分鐘 10 次 )"
    throttle.reset!
    # 成功一次就歸零. 上次成功 ( s3 用復原碼登入 ) 之後失敗了 5 次: 用過的復原碼 1 + 錯的碼 4
    for i from 0 til 5
      await call \s6, \POST, \/test/login, {username: 'a@b.c'}
      await call \s6, \POST, \/api/auth/mfa/verify, {method: \totp, code: \000000}
    await call \s6, \POST, \/test/login, {username: 'a@b.c'}
    x = await call \s6, \POST, \/api/auth/mfa/verify, {method: \recovery, code: codes.1}
    ok x.id == 1049, "鎖定後連正確的復原碼也回 1049"

    section "oauth"
    r = await db.query """
    insert into users (username, password, method, displayname) values ('g@b.c', '', 'google', 'g') returning key
    """
    key2 = r.rows.0.key
    await call \o1, \POST, \/test/login, {username: 'g@b.c', provider: \google}
    s2 = await call \o1, \POST, \/api/auth/mfa/totp/setup
    x = await call \o1, \GET, \/api/auth/mfa
    ok x.password == false, "oauth 帳戶啟用時不用密碼"
    x = await call \o1, \POST, \/api/auth/mfa/totp/enable, {code: totp.generate({secret: s2.secret})}
    ok x.recovery?length == 10, "oauth 帳戶不用密碼也能啟用"
    x = await call \o2, \POST, \/test/login, {username: 'g@b.c', provider: \google}
    ok x.loggedin, "config.auth.mfa.oauth 沒開時 oauth 登入不驗 2FA"
    config.auth.mfa.oauth = true
    x = await call \o3, \POST, \/test/login, {username: 'g@b.c', provider: \google}
    ok x.mfa, "config.auth.mfa.oauth 開了就要驗"

    section "重新產生復原碼 / 停用"
    x = await call \o2, \POST, \/api/auth/mfa/recovery, {code: \000000}
    ok x.id == 1045, "錯的碼不能重新產生"
    x = await call \o2, \POST, \/api/auth/mfa/recovery, {code: totp.generate({secret: s2.secret, t: Date.now! + 30000})}
    ok x.recovery?length == 10, "用下一個時間窗的碼重新產生"
    x = await call \o2, \POST, \/api/auth/mfa/totp/disable, {method: \recovery, code: x.recovery.0}
    ok (x and !x.id), "用復原碼停用"
    r = await db.query "select count(*) as c from mfarecovery where owner = $1", [key2]
    ok +r.rows.0.c == 0, "復原碼一併刪除"
    x = await call \o4, \POST, \/test/login, {username: 'g@b.c', provider: \google}
    ok x.loggedin, "停用後登入不再驗 2FA"

    section "管理員重設"
    x = await call \s1, \POST, \/api/auth/admin/mfa/reset, {key}
    ok x.id == 404, "非管理員回 404"
    sessions.s1.user.staff = 1
    x = await call \s1, \POST, \/api/auth/admin/mfa/reset, {username: 'A@B.C'}
    ok (x and !x.id), "管理員用 username 重設"
    r = await db.query "select count(*) as c from mfa where owner = $1", [key]
    ok +r.rows.0.c == 0, "mfa 資料已清掉"

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
