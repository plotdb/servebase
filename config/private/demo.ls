module.exports = do
  # use this to toggle some features that should only be enabled by a real server.
  # we distinguish this from `backend.mode` and `backend.production`
  # to prevent potential issues of confusion
  real-server: false
  # verbose name for user, such as in mail title, etc.
  #  - if omitted, `hostname` below or `aux.hostname(req)` should be used instead.
  #  - this may be a i18n key so use it with i18n.t unless translation is not necessary.
  sitename: 'servebase'
  # optional domain name.
  #  - dev can still infer domain name in used by `aux.hostname(req)` if omitted,
  #    however this should be used if provided.
  #  - should contain only domain name, without protocol.
  domain: 'serve.base'
  # either a list or a string, email(s) of the one for notifying about admin event.
  admin: email: '...'
  port: 8901
  limit: '20mb'
  i18n:
    # we used `enabled` for i18n object, however this behavior is changed.
    # by default i18n object is necessary even if we don't need translation.
    # thus, `enabled` becomes confusion in semantics.
    # so we deprecated it and add `intl-build`.
    # `enabled` can still be used but will be removed in the future.
    # enabled: true
    intl-build: true
    lng: <[en zh-TW]>
    ns: <[default]>
    fallback-lng: 'en'
  base: 'base'
  srcbuild: [] # value in `base` will be added by default
  redis:
    enabled: false
    url: \redis://localhost:6379
  db:
    postgresql:
      host: \localhost # host.docker.internal
      port: 15432
      database: \servebase
      user: \servebase
      password: \servebase
      poolSize: 20
  build:
    enabled: true
    watcher:
      ignored: ['\/\..*\.swp$', '^static/assets/img']
    # support asset copying from src to static by adding additional ext here
    # note: based on @plotdb/srcbuild, this defaults to image + json
    asset: ext: <[glb jpg png svg gif mp3 mp4]>
    block:
      # the block manager used to find module files. optional, fallback to default one if omitted.
      manager: 'path/to/block/manager'
  session:
    secret: 'this-is-a-sample-secret-please-update-it'
    max-age: 365 * 86400 * 1000
    include-sub-domain: false # set to true to use `.<domain>` in session cookie
  captcha:
    enabled: false
    recaptcha:
      sitekey: '...'
      secret: '...'
      enabled: false
    hcaptcha:
      sitekey: '...'
      secret: '...'
      enabled: false
  log:
    level: \info
    # when true, all errors handled in `@servebase/backend/error-handler` will be logged with `debug` level
    all-error: false
  policy:
    # login policy
    login:
      skip-verify: false # default false. when true, verification mail won't be sent when `signup`.
      # accept-signup: default true. set to `false` or `no` to reject new signup,
      # or `invite` to accept new signup by invitation code.
      accept-signup: true
      logging: false # log logging failure attempt in server log if true.
      oauth-default-verified: false # consider oauth accounts verified by default
    # password renew policy
    password:
      check-unused: '' # either empty (don't check), `renew` (check only for renewal), `all` ( always check )
      renew: 180 # days after last password update to renew password
      track:
        count: 1 # amount of password records to keep at most
        day: 540 # records to keep within this amount of days
    # expiration time of various token
    token-expire:
      mail-verify: 600
      password-reset: 600
  auth:
    # GCP -> API & Services -> Credentials -> OAuth Client ID
    google:
      clientID: '...'
      clientSecret: '...'
    facebook:
      clientID: '...'
      clientSecret: '...'
      scope: <[public_profile openid email]>
    line:
      channelID: '...'
      channelSecret: '...'
    local:
      usernameField: \email
      passwordField: \passwd
  mail:
    # to suppress outgoing mail, enable `suppress` option.
    suppress: false
    # additional information for customizing mail info. possible fields:
    #  - `from`: sender information, can be interpolated. such as:
    #            '"#{sitename} Support" <contact@#{domain}>'
    #            '"test user" <test@plotdb.com>'
    #            'contact@grantdash.io'
    info: null
    # currently we support SMPT or Mailgun
    # SMPT config: {host, port, secure, auth: {user, pass}}
    # check `https://nodemailer.com/about/#example` for sample configuration
    smpt: null
    # Mailgun config: {auth: {domain, api_key}}
    mailgun: null
    # blacklist emails. either an array of domains, or an object with `module` field,
    # pointing to a module with `is(email)` API which return a Promise resolving with `true`
    # if `email` is blacklisted.
    blacklist: []
    # default sender when sending mail. can be overwritten if explicitly set when calling mail APIs.
    default-sender: null
  # client: additional information passing to client side via
  #  - api/auth/info, (acces via `global.config`)
  #  - as locals used in view rendering. (available in `settings.client`)
  # it can be either:
  #  - a string: it will be treated as a module path to load.
  #  - an object with a string in `module` field: the `module` field will be the path of the module to load.
  #  - an object wihtout `module` string field: used directly in `global.config` and `settings.client`
  #  - empty object `{}` otherwise.
  # when we expect a module, it should accept `backend` as parameter and returns the real client config.
  client: {}
