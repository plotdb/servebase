require! <[crypto lderror]>
require! <[@servebase/backend/aux @servebase/backend/throttle]>

(backend) <- ((f) -> module.exports = -> f it) _

{db,config,route,session} = backend

mdw = throttle: throttle.kit.login, captcha: backend.middleware.captcha

getmap = (req) ->
  sitename: config.sitename or config.domain or aux.hostname(req)
  domain: config.domain or aux.hostname(req)

verify: ({req, user}) ->
  obj = {}
  (ret) <~ backend.mail-queue.in-blacklist user.username .then _
  if ret => return lderror.reject 998
  Promise.resolve!
    .then ->
      time = new Date!
      obj <<< {key: user.key, hex: "#{user.key}-" + (crypto.randomBytes(30).toString \hex), time: time }
      db.query "delete from mailverifytoken where owner=$1", [obj.key]
    .then -> db.query "insert into mailverifytoken (owner,token,time) values ($1,$2,$3)", [obj.key, obj.hex, obj.time]
    .then ->
      backend.mail-queue.by-template(
        \mail-verify
        user.username
        ({token: obj.hex} <<< getmap(req))
        {now: true}
      )

route: ->
  route.auth.post \/mail/verify, aux.signedin, mdw.throttle, mdw.captcha, (req, res) ~>
    (r={}) <~ db.query """
    select key,verified from users where key = $1 and deleted is not true
    """, [req.user.key] .then _
    if !(u = r.[]rows.0) => return lderror.reject 404
    if u.{}verified.date => return res.send {result: "verified"}
    @verify {req, user: req.user}
      .then -> res.send {result: "sent"}
      .catch (e) ->
        if lderror.id(e) == 998 => res.send {result: "skipped"}
        return Promise.reject e

  route.app.get \/auth/mail/verify/:token, (req, res) ->
    lc = {}
    if !(token = req.params.token) => return lderror.reject 400
    db.query "select owner,time from mailverifytoken where token = $1", [token]
      .then (r={})->
        if !r.[]rows.length => return lderror.reject 1013
        lc.obj = r.rows.0
        db.query "delete from mailverifytoken where owner = $1", [lc.obj.owner]
      .then ->
        if new Date!getTime! - new Date(lc.obj.time).getTime! > 1000 * 600 => return lderror.reject 1013
        lc.verified = verified = {date: Date.now!}
        db.query "update users set verified = $2 where key = $1", [lc.obj.owner, JSON.stringify(verified)]
      .then ->
        db.query "select * from users where key = $1", [lc.obj.owner]
          .then (r={}) ->
            if !(u = r.[]rows.0) => return
            u.verified = lc.verified
            session.sync {req, user: lc.obj.owner, obj: u}
      .then -> res.redirect \/auth/?mail-verified
      .catch (e) ->
        if lderror.id(e) != 1013 => Promise.reject e
        else res.redirect \/auth/?mail-expire
