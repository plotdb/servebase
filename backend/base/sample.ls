require! <[lderror @servebase/backend/throttle @servebase/backend/aux]>
(backend, {api, app}) <- (->module.exports = it)  _
{config, db} = backend

app.get \/, throttle.kit.generic, (req, res, next) ->
  db.query "select count(key) as count from users"
    .then (r={}) ->
      count = (r.[]rows.0 or {count: 0}).count
      res.render \index.pug, {count}

app.get \/auth-required, (req, res, next) -> return lderror.reject 1000
app.get \/i18n, (req, res, next) -> return res.send({locale: req.get("I18n-Locale")})

# plain Error. unrecgonized, thus trigger exception dump. won't crash. send 500 to client
api.get \/error, (req, res, next) -> throw new Error!
app.get \/error, (req, res, next) -> throw new Error!

# plain Error, in next. unrecgonized, thus trigger exception dump. won't crash. send 500 to client
api.get \/error/next, (req, res, next) -> next new Error!
app.get \/error/next, (req, res, next) -> next new Error!

# lderror. processed by error-handler. send 490 with censored lderror content to client. won't crash
api.get \/lderror, (req, res, next) -> next lderror(1023)
app.get \/lderror, (req, res, next) -> next lderror(1023)

# plain Error + lderror, in rejection. catched by route.app wrapped by routecatch. won't crash
app.get \/error/reject,  (req, res, next) -> Promise.reject(new Error!)
app.get \/lderror/reject,  (req, res, next) -> Promise.reject(lderror 1023)

api.get \/ip, (req, res, next) ->
  res.send aux.ip(req)

api.get \/password-due, (req, res, next) ->
  db.user-store.password-due req{user}
    .then (delta) -> res.send(if delta > 0 => {password-expire: delta} else {})

# Demonstrate using captcha to guard this api.
api.post \/post, backend.middleware.captcha, (req, res, next) ->
  res.send \pass

api.post \/post-test/, (req, res, next) ->
  res.send \pass

app.get \/me/settings, aux.signedin, (req, res, next) -> res.render \me/settings.pug, {user: req.user}
app.get \/verified, aux.verified, (req, res, next) -> res.render \me/verified.pug, {user: req.user}

app.get \/view, (req, res, next) -> res.render \view.pug, {view: true}

app.get \/trigger-notify, (req, res, next) ->
  email = (config.admin or {}).email
  recipients = if Array.isArray(email) => email else [email]
  email = recipients.join(\,)
  if !email => return res.send 'admin email not set'
  name = req.query.name or \notify-test
  if !name or req.query.default =>
    payload =
      subject: "notify test"
      text: "this is a sample notification test"
      html: "[<script>this should be removed</script>]this is a sample notification test"
  backend.mail-queue.batch {
    sender: """\"servebase notifier" <#{recipients.0}>"""
    recipients: recipients
    name: name if !req.query.default
    payload: payload
    params: {name, email, token: Math.random!toString(36)substring(2)}
    batch-size: 1
  }
    .then -> res.send "mail request sent to #email"

app.get \/audit-test, (req, res, next) ->
  if !db.query-audit =>
    console.error "query-audited isn't implemented."
    return lderror.reject 1020
  <- db.query-audit """
  insert into consent (consent_id, owner, ip) values ($1,$2,$3)
  """, [Math.random!toString(36)substring(2), 11, ''], {
    audit: atomic: true, req: req
  } .then _
  console.log "[dev] test audited."
  res.send {}
