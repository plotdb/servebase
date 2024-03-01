module.exports = do
  # use this to toggle some features that should only be enabled by a real server.
  # we distinguish this from `backend.mode` and `backend.production`
  # to prevent potential issues of confusion
  real-server: false
  # verbose name for user, such as in mail title, etc.
  #  - if omitted, `hostname` below or `aux.hostname(req)` should be used instead.
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
    enabled: true
    lng: <[en zh-TW]>
    ns: <[default]>
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
    watcher: do
      ignored: ['\/\..*\.swp$', '^static/assets/img']
    block:
      # the block manager used to find module files. optional, fallback to default one if omitted.
      manager: 'path/to/block/manager'
  session:
    secret: 'this-is-a-sample-secret-please-update-it'
    max-age: 365 * 86400 * 1000
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
      accept-signup: true # default true. set to `false` to reject new signup.
      logging: false # log logging failure attempt in server log if true.
      oauth-default-verified: false # consider oauth accounts verified by default
    # password renew policy
    password:
      check-unused: '' # either empty (don't check), `renew` (check only for renewal), `all` ( always check )
      renew: 180 # days after last password update to renew password
      track:
        count: 1 # amount of password records to keep at most
        day: 540 # records to keep within this amount of days
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
  # additional information passing to client side via api/auth/info.
  # use `global.config` to access this object.
  client: {}
