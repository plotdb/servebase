require! <[crypto lderror]>
require! <[@servebase/backend/aux @servebase/backend/throttle]>

# 啟用管理員代建的帳戶 ( users.system.pending ).
#
#  1. `create` 建好沒有密碼的 pending 帳戶, 寄出啟用信 ( `send` ).
#  2. GET /auth/activate/:token 只檢查連結, 把 token 放進 cookie 後導到設定密碼的畫面 ( block `activate` ).
#     不在這裡用掉 token: 信件的連結掃描 ( 如 Outlook Safe Links ) 會先 GET 一次.
#  3. POST /api/auth/activate/:token 設定密碼, 才用掉 token. 同時標記 email 已驗證, 帳號啟用.
#
# token 只存 sha256, 一次性, 重寄時舊的作廢. pending 帳戶用密碼 / 第三方登入或註冊都回 1052;
# 忘記密碼則改寄啟用信 ( see ./passwd ).

(backend) <- ((f) -> module.exports = -> f it) _

{db,config,route} = backend

mdw = throttle: throttle.kit.login, captcha: backend.middleware.captcha

getmap = (req) ->
  lngs = backend.lngs(req)
  domain = config.domain or aux.hostname(req)
  sitename = if config.sitename => backend.i18n.t(config.sitename, {lngs, lng: lngs.0})
  else config.domain or aux.hostname(req)
  return {sitename, domain}

sha = -> crypto.createHash(\sha256).update("#it").digest(\hex)

# 啟用連結的有效時間 ( 秒 ), 預設 7 天
ttl = ->
  tick = parseInt(((config.policy or {}).token-expire or {}).activate)
  if isNaN(tick) or tick < 0 => 7 * 86400 else tick

# 寄啟用信, 舊的 token 作廢.
#  - `cooldown` ( 秒 ): 這段時間內寄過就不再寄. 給任何人都能觸發的地方 ( 如忘記密碼 ) 用,
#    避免別人一直重寄, 讓用戶手上的連結一直失效.
send: ({req, user, cooldown}) ->
  token = crypto.randomBytes(32).toString \hex
  (ret) <~ backend.mail-queue.in-blacklist user.username .then _
  if ret => return lderror.reject 998
  Promise.resolve!
    .then ->
      if !cooldown => return
      db.query """
      select key from activatetoken
      where owner = $1 and used is null and deleted is not true
      and createdtime > now() - make_interval(secs => $2)
      """, [user.key, cooldown]
    .then (r) ->
      if r and r.[]rows.length => return
      db.query "update activatetoken set deleted = true where owner = $1 and used is null", [user.key]
        .then ->
          db.query """
          insert into activatetoken (owner, hash, ttl) values ($1, $2, now() + make_interval(secs => $3))
          """, [user.key, sha(token), ttl!]
        .then ->
          backend.mail-queue.by-template(
            \activate
            user.username
            ({token} <<< getmap(req))
            {now: true, lng: backend.lngs(req).0}
          )

# 建立 pending 帳戶並寄出啟用信. 角色等設定由呼叫端在之後自行處理.
#  - `by`: 建立者的 user key.
# 回傳建好的 user. 信寄不出去時帳戶還是建好了, 可以再呼叫 `send` 重寄.
create: ({req, username, displayname, detail, by}) ->
  username = "#{username or ''}".trim!toLowerCase!
  detail = {displayname} <<< (detail or {})
  db.user-store.create {username, detail, config: {}, pending: {by}}
    .then (user) ~> @send({req, user}).then -> user

route: ->
  route.app.get \/auth/activate/:token, mdw.throttle, (req, res) ->
    if !(token = req.params.token) => return lderror.reject 400
    db.query """
    select t.owner from activatetoken as t, users as u
    where t.hash = $1 and t.used is null and t.deleted is not true and t.ttl > now()
    and u.key = t.owner and u.system ? 'pending' and u.deleted is not true
    """, [sha(token)]
      .then (r={}) ->
        # 無效 ( 過期 / 用過 / 帳號已啟用 ) 時不放 cookie, block 會顯示連結無效
        if r.[]rows.length => res.cookie "activate-token", token, {path: \/, secure: true, max-age: 1800 * 1000}
        res.redirect "/auth/?activate"

  route.auth.post \/activate/:token, mdw.throttle, mdw.captcha, (req, res) ->
    token = req.params.token
    password = "#{(req.body or {}).password or ''}"
    if password.length < 8 => return lderror.reject 1031
    lc = {}
    db.user-store.hashing password
      .then (hash) ->
        lc.hash = hash
        # 用掉 token 與檢查有效是同一個 query, 同一個 token 只會有一個 request 成功
        db.query """
        update activatetoken set used = now()
        where hash = $1 and used is null and deleted is not true and ttl > now()
        returning owner
        """, [sha(token)]
      .then (r={}) ->
        if !(t = r.[]rows.0) => return lderror.reject 403
        db.user-store.activate {key: t.owner, hash: lc.hash, verified: true}
      .then (user) ->
        # 帳號已經不是 pending ( 例如管理員直接設了密碼 )
        if !user => return lderror.reject 403
        db.user-store.password-track {user, hash: lc.hash}
      .then -> res.send!
