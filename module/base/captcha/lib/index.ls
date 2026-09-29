require! <[axios lderror @servebase/backend/aux]>

captcha = (opt = {}) ->
  @cfg = opt or {}
  @middleware = @_middleware!
  # backend.middleware.captcha.once {scope, ttl}, see `once` below.
  @middleware.once = (o) ~> @once o
  @

fetch = ({url, form}) ->
  p = axios.post(
    url, new URLSearchParams(form),
    headers: 'Content-Type': 'application/x-www-form-urlencoded'
  )
  p
    .then (ret) -> ret.data
    .catch (e) -> Promise.reject e

captcha.prototype = Object.create(Object.prototype) <<<
  _payload: (req) ->
    obj = if req.body and req.body.captcha => req.body.captcha else if req.fields => req.fields.captcha else null
    # if captcha is not parsed as JSON instread as a string
    # (e.g., passed as multipart field)
    if typeof(obj) == \string =>
      try
        obj = JSON.parse obj
      catch e # simply ignore since string won't pass below checks.
    return if obj and obj.token => obj else null

  verify: (req, res, next) ->
    if !(obj = @_payload req) => return Promise.resolve {score: 0, verified: false}
    if !(obj.name in <[hcaptcha recaptcha_v3 recaptcha_v2_checkbox]>) => return lderror.reject 1020
    if !(cfg = @cfg[obj.name]) => return lderror.reject 1020
    if !(!(cfg.enabled?) or cfg.enabled) => return lderror.reject 1020
    captcha.verifier[obj.name](req, res, cfg, obj)

  _middleware: ->
    if !(@cfg and (!(@cfg.enabled?) or @cfg.enabled)) => return (req, res, next) -> next!
    (req, res, next) ~>
      @verify req, res, next
        .then (cap) ->
          if !cap.score or cap.score < 0.5 => return next(lderror 1009)
          next!
        .catch (e) -> next e

  # 驗一次, 之後 `ttl` 內同一個 session 直接放行, 請求不用再帶 captcha.
  #  - 沒有通行證也沒帶 captcha: 1048 ( captcha required ), 前端跑 guard 後重送.
  #    前端用 `core.captcha.once` 就會自動處理.
  #  - 帶了但沒過: 1009, 跟一般的 captcha middleware 一樣.
  #  - `scope` 區分功能, 某個功能驗過不代表別的功能也驗過. 要共用就設同一個 scope.
  # 通行證只證明「一開始是人」, 期間內無法撤銷, 所以要搭配 throttle 擋量, ttl 也不宜長.
  # 通行證記在 session 裡, 以瀏覽器為單位: 換裝置 / 清 cookie 就要重新驗.
  once: (opt = {}) ->
    if !(@cfg and (!(@cfg.enabled?) or @cfg.enabled)) => return (req, res, next) -> next!
    scope = opt.scope or \default
    ttl = opt.ttl or 10 * 60 * 1000
    (req, res, next) ~>
      pass = if req.session and req.session.captcha-pass => that[scope] else 0
      if pass and pass > Date.now! => return next!
      if !@_payload(req) => return next(lderror 1048)
      @verify req, res, next
        .then (cap) ->
          if !cap.score or cap.score < 0.5 => return next(lderror 1009)
          # 沒有 session ( 例如掛在 session 之前的路由 ) 就退化成每次都驗
          if req.session => req.session.{}captcha-pass[scope] = Date.now! + ttl
          next!
        .catch (e) -> next e

captcha.verifier =
  hcaptcha: (req, res, config, capobj) ->
    p = fetch(
      url: \https://hcaptcha.com/siteverify,
      form:
        secret: config.secret
        response: capobj.token
        remoteip: aux.ip req # not required by hcaptcha. keep it for simplicity
    )
    p
      .then (data) -> {score: if data.success => 1 else if data.score => that else 0, verified: true}
      .catch -> return lderror.reject 1010

  recaptcha_v2_checkbox: (req, res, config, capobj) ->
    p = fetch(
      url: \https://www.google.com/recaptcha/api/siteverify
      form:
        secret: config.secret
        response: capobj.token
        remoteip: aux.ip req
    )
    p
      .then (data) ->
        if data.success == false => return lderror.reject 1009
        {score: if data.success => 1 else if data.score => that else 0, verified: true}
      .catch (e) -> return if lderror.id(e) == 1009 => e else lderror.reject 1010

  recaptcha_v3: (req, res, config, capobj) ->
    p = fetch(
      url: \https://www.google.com/recaptcha/api/siteverify
      form:
        secret: config.secret
        response: capobj.token
        remoteip: aux.ip req
    )
    p
      .then (data) ->
        if data.success == false => return lderror.reject 1009
        {score: if data.success => 1 else if data.score => that else 0, verified: true}
      .catch (e) -> return if lderror.id(e) == 1009 => e else lderror.reject 1010

module.exports = captcha
