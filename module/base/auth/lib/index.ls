require! <[lderror jsonwebtoken @plotdb/express-session passport passport-local]>
require! <[passport-facebook]>
require! <[passport-google-oauth20]>
require! <[passport-line-auth]>
require! <[@servebase/backend/aux ./passwd ./mail]>

(backend) <- ((f) -> module.exports = -> f.call {}, it) _
{db,app,config,route,session} = backend

captcha = Object.fromEntries [[k,v] for k,v of config.captcha].map ->
  if it.0 == \enabled => [it.0, it.1] else [it.0, it.1{sitekey, enabled}]
oauth = Object.fromEntries(
  [[k,v] for k,v of config.auth]
    .map -> return if it.0 == \local => null else [it.0, {enabled: !(it.1.enabled?) or it.1.enabled }]
    .filter -> it
)
policy = {}
if backend.config.{}policy.{}login.accept-signup? =>
  policy.{}login.accept-signup = backend.config.policy.login.accept-signup

limit-session-amount = false

@user =
  delete: ({key, username}) ->
    if !(key or username) => return lderror.rejrect 400
    if username => username = "#username".trim!toLowerCase!
    (r={}) <- db.query """
    select username,key from users
    where deleted is not true and
    #{if key => 'key = $1' else 'username = $1'}
    """, [if key => key else username] .then _
    if !(u = r.[]rows.0) => return lderror.reject 404
    <- session.delete {user: u.key} .then _
    db.query """
    update users
    set (username,displayname,method,password,deleted)
    = ($2, $3, 'local', '', true)
    where key = $1
    """, [u.key, "deleted(#{u.username})/#{u.key}", "(deleted user #{u.key})"]

get-user = ({username, password, method, detail, create, invite-token, cb, req}) ->
  db.user-store.get {username, password, method, detail, create, invite-token}
    .then (user) !->
      db.query "select count(ip) from session where owner = $1 group by ip", [user.key]
        .then (r={}) ->
          # by default disabled - session amount limitation
          if limit-session-amount and ((r.[]rows.0 or {}).count or 1) > 1 => cb lderror(1004), null, {message: ''}
          else cb null, (user <<< {ip: aux.ip(req)})
    .catch (e) ->
      if e and config.{}policy.{}login.logging =>
        backend.log-security.info "login fail #method method #username eid #{e.id}/#{e.message}"
      # 1012: permission denied;  1004: quota exceeded(won't hit here?)
      # 1000: user not login; 1034: user not found; 1015: bad param; 1043: token required
      # TODO we may need to pass error code to frontend for better error message.
      if lderror.id(e) in [1000,1004,1012,1015,1034,1040,1043] => return cb e, false
      console.log e
      cb lderror(500)

strategy = do
  local: (opt) ->
    passport.use new passport-local.Strategy {
      usernameField: \username, passwordField: \password
      passReqToCallback: true
    }, (req, username,password,cb) ~>
      get-user {
        username, password, method: \local, detail: null, create: false, cb, req
        invite-token: req.session.invite-token
      }

  google: (opt) ->
    passport.use new passport-google-oauth20.Strategy(
      do
        clientID: opt.clientID
        clientSecret: opt.clientSecret
        callbackURL: "/api/auth/google/callback"
        passReqToCallback: true
        userProfileURL: 'https://www.googleapis.com/oauth2/v3/userinfo'
        profileFields: ['id', 'displayName', 'link', 'emails']
      , (req, access-token, refresh-token, profile, cb) !->
        if !profile.emails => cb null, false, {}
        else get-user {
          username: profile.emails.0.value, password: null
          method: \google, detail: profile, create: true, cb, req
          invite-token: req.session.invite-token
        }
    )

  facebook: (opt) ->
    passport.use new passport-facebook.Strategy(
      do
        clientID: opt.clientID
        clientSecret: opt.clientSecret
        passReqToCallback: true
        callbackURL: "/api/auth/facebook/callback"
        profileFields: ['id', 'displayName', 'link', 'emails']
      , (req, access-token, refresh-token, profile, cb) !->
        if !profile.emails => cb null, false, {}
        else get-user {
          username: profile.emails.0.value, password: null
          method: \facebook, detail: profile, create: true, cb, req
          invite-token: req.session.invite-token
        }
    )

  line: (opt) ->
    passport.use new passport-line-auth.Strategy(
      do
        channelID: opt.channelID
        channelSecret: opt.channelSecret
        callbackURL: "/api/auth/line/callback"
        scope: <[profile openid email]>
        botPrompt: \normal
        passReqToCallback: true
        prompt: 'consent'
        uiLocales: \zh-TW
      , (req, access-token, refresh-token, params, profile, cb) !->
        try
          ret = jsonwebtoken.verify params.id_token, opt.channelSecret
          if !(ret and ret.email) => throw new Error('')
          get-user {
            username: ret.email, password: null
            method: \line, detail: profile, create: true, cb, req
            invite-token: req.session.invite-token
          }
        catch e
          console.log e
          cb null, false, {}
    )

# =============== USER DATA, VIA AJAX
# Note: jsonp might lead to exploit since jsonp is not protected by CORS.
# * this cant be protected by CSRF, since it provides CSRF token.
# * this must be protected by CORS Policy, otherwise 3rd website can get user info easily.
# * this is passed via cookie too, but cookie won't be set if user doesn't get files served from express.
#   so, for the first time user we still have to do ajax.
#   cookie will be checked in frontend to see if ajax is needed.
# * user could still alter cookie's content, so it's necessary to force ajax call for important action
#   there is no way to prevent user from altering client side content,
#   so if we want to prevent user from editing our code, we have to go backend for the generation.
route.auth.get \/info, (req, res) ~>
  res.setHeader \content-type, \application/json
  payload = JSON.stringify({
    csrfToken: req.csrfToken!
    production: backend.production
    ip: aux.ip(req)
    user: if req.user => req.user{key, config, plan, displayname, verified, username, staff} else {}
    captcha: captcha
    oauth: oauth
    policy: policy
    version: backend.version
    cachestamp: backend.cachestamp
    config: backend.config.client or {}
  })
  res.cookie 'global', payload, { path: '/', secure: true }
  res.send payload

# we check if invite-token when user sign up
inject-invite-token = (req, res, next) ->
  if req.body and (t = req.body.invite-token) => req.session.invite-token = t
  next!

<[local google facebook line]>.for-each (name) ->
  if !config{}auth[name] => return
  strategy[name](config.auth[name])
  route.auth
    ..post(
      "/#name", inject-invite-token,
      passport.authenticate(name, {scope: config.auth[name].scope or <[profile openid email]>})
    )
    ..get "/#name/callback", ((name) -> (req, res, next) ->
      (
        (e,u,i) <- passport.authenticate name, _
        if e => return res.redirect "/auth?oauth-failed&code=#{lderror.id(e)}"
        if !u => return res.redirect \/auth?oauth-failed
        (e) <- req.logIn u, _
        if e => return next e
        res.redirect \/auth?oauth-done
      )(req, res, next)
    )(name)

passport.serializeUser (u,done) !->
  db.user-store.serialize u .then (v) !-> done null, v
passport.deserializeUser (v,done) !->
  db.user-store.deserialize v .then (u = {}) !-> done null, u

# prevent dupsessionid which may block user from correctly login.
# see https://github.com/expressjs/session/issues/881
app.use (req, res, next) ->
  c = ((req.headers or {}).cookie or '')
  cs = c.split /;/ .filter -> /^connect.sid=/.exec(it.trim!)
  return if cs.length > 1 => next {code: \SESSIONCORRUPTED} else next!

app.use backend.session.middleware(express-session {
  secret: config.session.secret
  resave: true
  saveUninitialized: true
  store: db.session-store
  proxy: true
  cookie: {
    path: \/
    httpOnly: true
    maxAge: config.session.max-age
  } <<< (if config.session.include-sub-domain => {domain: ".#{config.domain}"} else {})
})
app.use passport.initialize!
app.use passport.session!

route.auth
  ..post \/signup, backend.middleware.captcha, (req, res, next) ~>
    # config skipped here to prevent var shadowing of the global config object
    {username,displayname,password,invite-token} = req.body{username,displayname,password,invite-token}
    if !username or !displayname or password.length < 8 => return next(lderror 400)
    db.user-store.create {username, password, invite-token} <<< {
      method: \local, detail: {displayname}, config: (req.body.config or {})
    }
      .then (user) ~>
        # here we use the global config object.
        if config.{}policy.{}login.skip-verify => return user
        @mail.verify {req, user}
          .catch (err) ~>
            if lderror.id(err) == 998 => return user
            # only log here so user can continue to login.
            backend.log-mail.error {err}, "send mail verification mail failed (#username)".red
          .then -> user
      .then (user) !->
        req.login user, (err) !-> if err => next(err) else res.send {}
      .catch (e) !->
        if lderror.id(e) in [1004 1014 1040 1043] => return next(e)
        console.error e
        next(lderror 403)
  ..post \/login, backend.middleware.captcha, (req, res, next) ->
    ((err,user,info) <- passport.authenticate \local, _
    if err or !user => return next(err or lderror(1000))
    (err) <-! req.login user, _
    if err => return next err
    # check if we should notify user to update password
    (span) <- db.user-store.password-due {user} .then _
    res.send if span > 0 => {password-due: span, password-should-renew: (span > 0)} else {}
    )(req, res, next)
  ..post \/logout, (req, res) -> req.logout(!-> res.send!)

route.auth.put \/user, aux.signedin, backend.middleware.captcha, (req, res, next) ->
  [displayname, description, title, tags] = [{k,v} for k,v of req.body{displayname, description, title, tags}]
    .filter -> it.v?
    .map -> ("#{it.v or ''}").trim!
  if !displayname => return lderror.reject 400
  db.query "update users set (displayname,description,title,tags) = ($1,$2,$3,$4) where key = $5",
  [displayname, description, title, tags, req.user.key]
    .then -> req.user <<< {displayname, description, title, tags}
    .then -> session.sync {req, user: req.user.key, obj: req.user}
    .then -> res.send!

route.auth.post \/user/delete, aux.signedin, backend.middleware.captcha, (req, res) ~>
  if !(req.user and req.user.key) => return lderror.rejrect 400
  <- @user.delete {key: req.user.key} .then _
  <- req.logout _
  res.send!

# identical to `/auth` but if it's more semantic clear.
app.get \/auth/reset, (req, res) ->
  aux.clear-cookie req, res
  <-! req.logout _
  # by rendering instead of redirecting, we can keep the URL as is.
  # in this case a reload after authenticaed will help refresh that page
  # frontend should determine current URL and redirect to landing page if necessary to prevent infinite loop
  res.render "auth/index.pug"

app.post \/api/auth/clear, aux.signedin, backend.middleware.captcha, (req, res) ->
  <- session.delete {user: req.user.key} .then _
  aux.clear-cookie req, res
  <-! req.logout _
  res.send!

app.post \/api/auth/clear/:uid, aux.is-admin, (req, res) ->
  session.delete {user: req.params.uid} .then -> res.send!

# this must not be guarded by csrf since it's used to recover csrf token.
app.post \/api/auth/reset, (req, res) ->
  aux.clear-cookie req, res
  <-! req.logout _
  res.send!

@passwd = passwd backend
@mail = mail backend
@passwd.route!
@mail.route!

@
