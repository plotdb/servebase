require! <[crypto lderror]>
require! <[@servebase/backend/throttle @servebase/backend/aux]>

(backend) <- ((f) -> module.exports = -> f it) _
{db,config,route,session} = backend

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
        db.query(["select users.key from users,pwresettoken"
        "where pwresettoken.token=$1 and users.key=pwresettoken.owner"].join(" "),[token])
      .then (r={}) ->
        if !r.[]rows.length => return lderror.reject 403
        user = r.rows.0
        user.password = password.hashed
        db.query "update users set (password,method) = ($2,$3) where key = $1", [user.key, user.password, \local]
          .then -> db.user-store.password-track {user, hash: password.hashed}
      .then -> db.query "delete from pwresettoken where pwresettoken.token=$1", [token]
      .then -> res.send!

  route.app.get \/auth/passwd/reset/:token, mdw.throttle, (req, res) ->
    token = req.params.token
    if !token => return lderror.reject 400
    db.query "select owner,time from pwresettoken where token = $1", [token]
      .then (r={})->
        if !r.[]rows.length => return lderror.reject 403
        obj = r.rows.0
        tick = parseInt(((config.policy or {}).token-expire or {}).password-reset)
        if isNaN(tick) or tick < 0 => tick = 600
        if new Date!getTime! - new Date(obj.time).getTime! > 1000 * tick =>
          return res.redirect \/auth/?passwd-expire
        res.cookie "password-reset-token", token
        res.redirect "/auth/?passwd-change"

  route.auth.post \/passwd/reset, mdw.throttle, mdw.captcha, (req, res) ->
    email = "#{req.body.email}".trim!toLowerCase!
    if !email => return lderror.reject 400
    obj = {}
    db.query "select key,username from users where username = $1", [email]
      .then (r={}) ->
        if r.[]rows.length == 0 => return lderror.reject 404
        time = new Date!
        obj <<<
          key: r.rows.0.key, email: r.rows.0.username
          hex: "#{r.rows.0.key}" + (crypto.randomBytes(30).toString \hex), time: time
        db.query "delete from pwresettoken where owner=$1", [obj.key]
      .then -> db.query "insert into pwresettoken (owner,token,time) values ($1,$2,$3)", [obj.key, obj.hex, obj.time]
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
        db.query "update users set (password,method) = ($1,'local') where key = $2", [password, req.user.key]
          .then -> db.user-store.password-track {user: req.user, hash: password}
      .then -> session.sync {req, user: req.user.key, obj: req.user}
      .then -> res.send!

