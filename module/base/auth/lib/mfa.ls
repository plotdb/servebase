require! <[lderror qrcode]>
require! <[@servebase/backend/aux @servebase/backend/throttle ./totp]>

# 2FA ( 第二因素 ). 目前只有 totp ( Google Authenticator 等 app ), 加上所有方法共用的復原碼.
#
# 登入分兩段:
#  1. 帳密 / oauth 通過後, 呼叫 `gate`. 使用者有啟用 2FA 的話不登入, 只在 session 記下
#     `mfa-pending`, 回傳要驗的方法; 沒有的話回傳 null, 由呼叫端照常登入.
#  2. POST /api/auth/mfa/verify 驗過第二因素後, 才呼叫 `opt.login` 真正登入.
#
# 之後加 email / sms 時:
#  - 在 `methods` 加一項, 實作 `verify`. 需要寄碼的方法再加 `challenge`, 並開一個
#    POST /mfa/challenge 讓登入第二步可以要求寄送; 寄送對象放 mfa.target.
#  - 綁定流程各自不同 ( sms 要先驗手機 ), 各自開 /mfa/<method>/... 路由.
#  - `gate` / `check` / 復原碼 / 失敗計數都不用改.

(backend, opt = {}) <- ((f) -> module.exports = (b, o) -> f b, o) _
{db,config,route,session} = backend

cfg = (config.auth or {}).mfa or {}
enabled = !!cfg.enabled
# 沒設金鑰就啟用的話, 啟動時就失敗, 不要等到有人綁定才發現
keyring = if enabled => totp.keyring cfg{keys, current} else null

pending-ttl = 5 * 60 * 1000       # 登入第二步的時限
pending-attempt = 5               # 登入第二步最多試幾次, 超過要從帳密重來
setup-ttl = 10 * 60 * 1000        # 綁定時從產生 secret 到輸入驗證碼的時限
# 以帳號為單位的失敗上限. 登入第二步的次數限制可以靠重新登入繞過, 這裡擋住總量.
# 記在記憶體, 多個 process 時各算各的, 仍有上限.
lock = count: 10, span: 15 * 60 * 1000
fails = new throttle.store!
# 同一組 totp 碼 ( 同一個 30 秒窗 ) 用過之後能不能再用:
#  - `session` ( 預設 ): 同一個 session 可以, 別的 session 不行. 剛登入就到設定頁再用同一組碼不會被擋,
#    被偷走的碼在攻擊者自己的 session 裡則擋得住.
#  - `true`: 都可以 ( 例如 npm ). `false`: 都不行 ( RFC 6238 5.2 ).
reuse = -> if cfg.reuse == true => true else if cfg.reuse == false => false else \session
# 記下這個 session 用過的時間窗, 給 reuse = session 判斷
remember = (req, step) ->
  if (step?) and req and req.session => req.session.mfa-step = (req.session.mfa-step or 0) >? step

issuer = ->
  if cfg.issuer => return that
  if config.sitename => return backend.i18n.t(config.sitename)
  config.domain or \servebase

methods =
  totp:
    # `used`: 這個 session 用過的時間窗. 過了回傳 {step}, 由呼叫端記進 session
    verify: ({key, code, used}) ->
      (r={}) <- db.query """
      select key, secret from mfa where owner = $1 and method = 'totp' order by key desc limit 1
      """, [key] .then _
      if !(row = r.[]rows.0) => return lderror.reject 1045
      step = totp.totp.verify {secret: keyring.decrypt(row.secret), code}
      if !(step?) => return lderror.reject 1045
      # 比上次用過的更新的 step 才記下來. 同一組碼 ( 或更早的碼 ) 再用一次時看 `reuse`.
      (r={}) <- db.query """
      update mfa set
        lastused = now(),
        detail = coalesce(detail, '{}'::jsonb) || jsonb_build_object('laststep', $2::bigint)
      where key = $1 and coalesce((detail->>'laststep')::bigint, -1) < $2
      returning key
      """, [row.key, step] .then _
      if r.[]rows.length => return {step}
      if (mode = reuse!) == true or (mode == \session and (used?) and step <= used) => return {step}
      # 1050 code consumed: 碼是對的, 但這個時間窗已經用過 ( 例如在別的 session ). 請使用者等下一組.
      # 不算失敗次數 ( 只有 1045 算 ): 已用過的碼本來就不能再用, 告訴對方也不會多給什麼.
      lderror.reject 1050

recovery =
  verify: ({key, code}) ->
    if !(code = totp.recovery.normalize code) => return lderror.reject 1045
    (r={}) <- db.query """
    select key, hash from mfarecovery where owner = $1 and used is null
    """, [key] .then _
    if !(hit = r.[]rows.filter(-> keyring.match code, it.hash).0) => return lderror.reject 1045
    (r={}) <- db.query """
    update mfarecovery set used = now() where key = $1 and used is null returning key
    """, [hit.key] .then _
    if !r.[]rows.length => return lderror.reject 1045
    recovery.remain {key} .then (remain) -> {recovery: {remain}}
  remain: ({key}) ->
    db.query "select count(key) as count from mfarecovery where owner = $1 and used is null", [key]
      .then (r={}) -> +(r.[]rows.0 or {}).count or 0
  # 整批換新, 回傳明碼. 明碼只在這裡出現一次, 之後只剩雜湊.
  renew: ({key}) ->
    codes = totp.recovery.generate!
    <- db.query "delete from mfarecovery where owner = $1", [key] .then _
    db.query """
    insert into mfarecovery (owner, hash) select $1, unnest($2::text[])
    """, [key, codes.map -> keyring.hash totp.recovery.normalize(it)]
      .then -> codes

# 使用者已啟用的方法
enabled-methods = (key) ->
  db.query "select distinct method from mfa where owner = $1", [key]
    .then (r={}) -> r.[]rows.map(-> it.method).filter(-> methods[it])

load-user = ({req, key}) ->
  (r={}) <- db.query "select * from users where key = $1 and deleted is not true", [key] .then _
  if !(user = r.[]rows.0) => return lderror.reject 1034
  delete user.password
  user <<< {ip: aux.ip(req)}

password-check = ({req, password}) ->
  # 沒有密碼的帳戶 ( 只用 oauth 登入 ) 無從驗起, 只能靠登入狀態
  if req.user.method != \local => return Promise.resolve!
  (r={}) <- db.query "select password from users where key = $1", [req.user.key] .then _
  if !(u = r.[]rows.0) => return lderror.reject 403
  db.user-store.compare("#{password or ''}", u.password).catch -> lderror.reject 1030

mdw = throttle: throttle.kit.login

enabled: enabled

# 登入第一步通過後呼叫. `provider`: local / google / facebook / line.
# 需要 2FA 時回傳 {methods}, 並在 session 記下 pending; 不需要回傳 null.
gate: ({req, user, provider}) ->
  delete req.session.mfa-pending
  if !enabled => return Promise.resolve null
  if provider != \local and !cfg.oauth => return Promise.resolve null
  (list) <- enabled-methods user.key .then _
  if !list.length => return null
  req.session.mfa-pending = {key: user.key, provider, methods: list, exp: Date.now! + pending-ttl, attempt: 0}
  {methods: list}

# 驗證第二因素, `method` 可以是已啟用的方法或 `recovery`. 帶失敗計數.
# 有 `req` 時, totp 用過的時間窗會記進 req.session ( 見 `reuse` ).
check: ({key, method, code, req}) ->
  if !enabled => return lderror.reject 1016
  fkey = "#key"
  # 1049 too many attempts: 失敗太多次, 等 lock.span 過了再試
  if fails.inc(fkey, lock.span, 0).0 >= lock.count => return lderror.reject 1049
  (list) <- enabled-methods key .then _
  m = if method == \recovery => recovery else if method in list => methods[method] else null
  if !m => return lderror.reject 1015
  m.verify {key, code, used: req?session?mfa-step}
    .then (ret = {}) -> fails.reset fkey; remember req, ret.step; ret
    .catch (e) ->
      if lderror.id(e) == 1045 => fails.inc fkey, lock.span
      Promise.reject e

# 清掉一個帳號的所有 2FA 設定. 給管理員重設與刪除帳號用.
reset: ({key}) ->
  <- db.query "delete from mfa where owner = $1", [key] .then _
  db.query "delete from mfarecovery where owner = $1", [key]

route: ->
  # 登入第二步
  route.auth.post \/mfa/verify, mdw.throttle, (req, res) ~>
    if !(p = req.session.mfa-pending) or !p.key => return lderror.reject 1000
    # 逾時 ( 1013 ) 或這次登入的次數用完 ( 1049 ), 都要從帳密重來
    if p.exp < Date.now! or p.attempt >= pending-attempt =>
      delete req.session.mfa-pending
      return lderror.reject(if p.exp < Date.now! => 1013 else 1049)
    {method, code} = req.body or {}
    if !(method in (p.methods ++ [\recovery])) => return lderror.reject 1015
    p.attempt = p.attempt + 1
    # 1050 只是要等下一組碼, 不消耗這次登入的嘗試次數
    (ret = {}) <~ @check {key: p.key, method, code, req}
      .catch (e) ->
        if lderror.id(e) == 1050 => p.attempt = p.attempt - 1
        Promise.reject e
      .then _
    (user) <~ load-user {req, key: p.key} .then _
    # `opt.login` 會 regenerate session, pending 也跟著消失. 用過的時間窗要在新的 session 補記,
    # 不然剛登入就到設定頁再用同一組碼會被擋.
    (payload = {}) <~ opt.login {req, user} .then _
    remember req, ret.step
    delete ret.step
    res.send payload <<< ret

  # 目前狀態. 前端 settings 用.
  route.auth.get \/mfa, aux.signedin, (req, res) ->
    if !enabled or aux.is-anonymous(req.user) => return res.send {enabled: false}
    key = req.user.key
    (r={}) <- db.query """
    select method, createdtime, lastused from mfa where owner = $1 order by key
    """, [key] .then _
    list = r.[]rows.filter -> methods[it.method]
    (remain) <- (if list.length => recovery.remain {key} else Promise.resolve 0) .then _
    # `password`: 啟用時要不要輸入密碼 ( 只用 oauth 登入的帳戶沒有密碼 )
    res.send {enabled: true, methods: list, recovery: {remain}, password: req.user.method == \local}

  # 綁定 totp 第一步: 產生 secret. 先放 session ( 加密 ), 使用者輸入正確的碼才寫入 db.
  route.auth.post \/mfa/totp/setup, aux.signedin, mdw.throttle, (req, res) ->
    if !enabled => return lderror.reject 1016
    if aux.is-anonymous req.user => return lderror.reject 403
    (list) <- enabled-methods req.user.key .then _
    # 要換手機就先停用再重綁, 不讓已登入的人不經驗證直接蓋掉現有的綁定
    if \totp in list => return lderror.reject 1011
    secret = totp.totp.secret!
    req.session.mfa-setup = {secret: keyring.encrypt(secret), exp: Date.now! + setup-ttl}
    uri = totp.totp.uri {secret, issuer: issuer!, account: req.user.username}
    (qr) <- qrcode.toString uri, {type: \svg, margin: 1} .then _
    res.send {secret, uri, qr}

  # 綁定 totp 第二步: 驗證碼與密碼都對才啟用, 並產生復原碼.
  route.auth.post \/mfa/totp/enable, aux.signedin, mdw.throttle, (req, res) ->
    if !enabled => return lderror.reject 1016
    key = req.user.key
    if !((s = req.session.mfa-setup) and s.exp > Date.now!) => return lderror.reject 1013
    {code, password} = req.body or {}
    step = totp.totp.verify {secret: keyring.decrypt(s.secret), code}
    if !(step?) => return lderror.reject 1045
    <- password-check {req, password} .then _
    (list) <- enabled-methods key .then _
    if \totp in list => return lderror.reject 1011
    <- db.query """
    insert into mfa (owner, method, secret, detail) values ($1, 'totp', $2, $3)
    """, [key, s.secret, JSON.stringify({laststep: step})] .then _
    delete req.session.mfa-setup
    # 啟用用掉的時間窗也算這個 session 用過的, 接著馬上做別的事不會被擋
    remember req, step
    (codes) <- recovery.renew {key} .then _
    # 啟用前可能已外洩的其它 session 一律登出, 只留目前這個
    <- session.delete {user: key, except: req.sessionID} .then _
    res.send {recovery: codes}

  # 停用 totp. 要驗目前的碼或復原碼, 證明手上有第二因素, 不能只靠登入狀態.
  route.auth.post \/mfa/totp/disable, aux.signedin, mdw.throttle, (req, res) ~>
    key = req.user.key
    {method, code} = req.body or {}
    <~ @check {key, method: (if method == \recovery => \recovery else \totp), code, req} .then _
    <- db.query "delete from mfa where owner = $1 and method = 'totp'", [key] .then _
    (list) <- enabled-methods key .then _
    <- (if list.length => Promise.resolve! else db.query "delete from mfarecovery where owner = $1", [key]) .then _
    res.send {}

  # 重新產生復原碼, 舊的全部作廢. 同樣要驗目前的碼或復原碼.
  route.auth.post \/mfa/recovery, aux.signedin, mdw.throttle, (req, res) ~>
    key = req.user.key
    {method, code} = req.body or {}
    (list) <~ enabled-methods key .then _
    if !list.length => return lderror.reject 1016
    <~ @check {key, method: (if method == \recovery => \recovery else list.0), code, req} .then _
    (codes) <- recovery.renew {key} .then _
    res.send {recovery: codes}

  # 管理員重設 ( 使用者遺失手機又沒有復原碼 ).
  route.app.post \/api/auth/admin/mfa/reset, aux.is-admin, (req, res) ~>
    {key, username} = req.body or {}
    username = "#{username or ''}".trim!toLowerCase! or null
    key = if isNaN(+key) or !key => null else +key
    if !(key or username) => return lderror.reject 400
    (r={}) <~ db.query """
    select key from users where (key = $1 or $1 is null) and (username = $2 or $2 is null)
    """, [key, username] .then _
    if !(u = r.[]rows.0) => return lderror.reject 404
    <~ @reset {key: u.key} .then _
    res.send {}
