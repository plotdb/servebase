require! <[crypto lderror]>
require! <[@servebase/backend/throttle @servebase/backend/aux]>

(backend, opt = {}) <- ((f) -> module.exports = (b, o) -> f b, o) _
{db,config,route,session} = backend

# token 只存 hash ( `sha256:<hex>` ), 原文只在信裡.
# 改成 hash 之前發出的 token 是明文, 一樣查得到; 這些在有效時間過後就失效, 之後可以拿掉明文的比對.
# 帶 `sha256:` 前綴的輸入不收, 否則讀得到 db 的人可以直接拿 hash 當 token 用.
hash-token = -> "sha256:" + crypto.createHash(\sha256).update("#it").digest(\hex)
find-token = (token) ->
  token = "#{token or ''}"
  if !token or /^sha256:/.test(token) => return Promise.resolve null
  db.query "select owner,time from pwresettoken where token = any($1)", [[hash-token(token), token]]
    .then (r={}) -> r.[]rows.0 or null

# 連結的有效時間 ( 秒 ). 點連結時檢查; 送出新密碼時多給 `grace`, 讓接近到期才點開的人還有時間填.
expire = ->
  tick = parseInt(((config.policy or {}).token-expire or {}).password-reset)
  if isNaN(tick) or tick < 0 => 600 else tick
grace = 1800
expired = (obj, extra = 0) -> Date.now! - new Date(obj.time).getTime! > 1000 * (expire! + extra)

route: ->
  mdw = throttle: throttle.kit.login, captcha: backend.middleware.captcha
  getmap = (req) ->
    lngs = backend.lngs(req)
    domain = config.domain or aux.hostname(req)
    sitename = if config.sitename => backend.i18n.t(config.sitename, {lngs, lng: lngs.0})
    else config.domain or aux.hostname(req)
    return {sitename, domain}

  route.auth.post \/passwd/reset/:token, mdw.throttle, mdw.captcha, (req, res) ->
    token = req.params.token
    password = {plain: req.body.password}
    db.user-store.hashing password.plain, true, true
      .then (ret) ->
        password.hashed = ret
        find-token token
      .then (obj) ->
        if !obj or expired(obj, grace) => return lderror.reject 403
        user = {key: obj.owner, password: password.hashed}
        db.query """
        update users
          set (password,method) = ($2,$3),
          config = coalesce(config, '{}'::jsonb) #- '{authinfo,renewpw}',
          system = system - 'renewpw'
        where key = $1
        """, [user.key, user.password, \local]
          .then -> db.user-store.password-track {user, hash: password.hashed}
          .then -> db.query "delete from pwresettoken where owner = $1", [user.key]
      .then -> res.send!

  route.app.get \/auth/passwd/reset/:token, mdw.throttle, (req, res) ->
    token = req.params.token
    if !token => return lderror.reject 400
    find-token token
      .then (obj) ->
        if !obj => return lderror.reject 403
        if expired(obj) => return res.redirect \/auth/?passwd-expire
        res.cookie "password-reset-token", token, {max-age: 1000 * (expire! + grace)}
        res.redirect "/auth/?passwd-change"

  route.auth.post \/passwd/reset, mdw.throttle, mdw.captcha, (req, res) ->
    email = "#{req.body.email}".trim!toLowerCase!
    if !email => return lderror.reject 400
    db.query "select key,username,system from users where username = $1", [email]
      .then (r={}) ->
        if !(u = r.[]rows.0) => return lderror.reject 404
        # 管理員代建、還沒啟用的帳號沒有密碼可以重設, 改寄啟用信. 回應跟重設密碼一樣, 用戶不用分辨兩者.
        if u.{}system.pending =>
          return opt.activate.send {req, user: u, cooldown: 60}
            .catch (e) -> if lderror.id(e) != 998 => Promise.reject e
        obj = key: u.key, email: u.username, hex: "#{u.key}" + (crypto.randomBytes(30).toString \hex), time: new Date!
        db.query "delete from pwresettoken where owner=$1", [obj.key]
          .then -> db.query "insert into pwresettoken (owner,token,time) values ($1,$2,$3)", [obj.key, hash-token(obj.hex), obj.time]
          .then ->
            backend.mail-queue.by-template(
              \reset-password
              obj.email
              ({token: obj.hex} <<< getmap(req))
              {now: true, lng: backend.lngs(req).0}
            )
      .then -> res.send ''

  route.auth.put \/passwd/, mdw.throttle, aux.signedin, (req, res, next) ->
    {n,o,renew} = req.body or {}
    unused = ((config.policy or {}).password or {}).check-unused
    unused = if renew => (unused in <[renew all]>) else unused == \all
    # unused from here will be the flag indicating if a new password should not be used before.
    Promise.resolve!
      .then ->
        if !req.user => return lderror.reject 403
        # 匿名帳戶沒有舊密碼可驗, 升級成正式帳戶要走另一條路 ( 需驗證 email ), 不在這裡.
        if aux.is-anonymous req.user => return lderror.reject 403
        if n.length < 8 => return lderror.reject 1031
        db.query "select password from users where key = $1", [req.user.key]
      .then (r = {}) ->
        if !(u = r.[]rows.0) => return lderror.reject 403
        db.user-store.compare o, u.password
          .catch -> lderror.reject 1030
      .then ->
        if unused => return db.user-store.ensure-password-unused {user: req.user, password: n}
      .then -> db.user-store.hashing n
      .then (password) ->
        req.user <<< {password}
        db.query """
        update users
          set (password,method) = ($1,'local'),
          config = coalesce(config, '{}'::jsonb) #- '{authinfo,renewpw}',
          system = system - 'renewpw'
        where key = $2
        """, [password, req.user.key]
          .then -> db.user-store.password-track {user: req.user, hash: password}
      .then -> session.sync {req, user: req.user.key, obj: req.user}
      .then -> res.send!

