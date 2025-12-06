require! <[axios lderror @servebase/backend/aux]>

captcha = (opt = {}) ->
  @cfg = opt or {}
  @middleware = @_middleware!
  @

fetch = ({url, form}) ->
  p = axios.post(
    url, new URLSearchParams(form),
    headers: 'Content-Type': 'application/x-www-form-urlencoded'
  )
  p
    .then (ret) -> ret.data
    .catch (e) -> rej e

captcha.prototype = Object.create(Object.prototype) <<<
  verify: (req, res, next) ->
    obj = if req.body and req.body.captcha => req.body.captcha else if req.fields => req.fields.captcha else null
    # if captcha is not parsed as JSON instread as a string
    # (e.g., passed as multipart field)
    if typeof(obj) == \string =>
      try
        obj = JSON.parse obj
      catch e # simply ignore since string won't pass below checks.
    if !(obj and obj.token) => return Promise.resolve {score: 0, verified: false}
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
        if data.success == false => return reject(lderror 1009)
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
        if data.success == false => return reject(lderror 1009)
        {score: if data.success => 1 else if data.score => that else 0, verified: true}
        {score: data.score, verified: true}
      .catch (e) -> return if lderror.id(e) == 1009 => e else lderror.reject 1010

module.exports = captcha
