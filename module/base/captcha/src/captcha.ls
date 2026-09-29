captcha = (opt = {}) ->
  @_cfg = opt.cfg
  @mgr = opt.manager
  @init = proxise.once (cfg = {}) ~> @_init cfg
  @_zmgr = opt.zmgr
  @

captcha.prototype = Object.create(Object.prototype) <<< do
  _init: (cfg) ->
    if cfg => @_cfg = cfg
    Promise.resolve!
      .then ~> @mgr.get {name: '@servebase/captcha'}
      .then (bc) -> bc.create!
      .then (bi) -> bi.attach {root: document.body} .then -> bi.interface!
      .then (cap) ~> @captcha = cap
      .then ~> @captcha.init {cfg: @_cfg, zmgr: @_zmgr}
  guard: ({cb}) ->
    if (@_cfg and (!@_cfg.enabled? or @_cfg.enabled)) => @captcha.guard {cb}
    else Promise.resolve!then -> cb {captcha: {}}
  # 搭配後端的 `backend.middleware.captcha.once`: 先不帶 captcha 送出, 後端回 1048
  # ( captcha required, 這個 session 還沒驗過或已過期 ) 才跑 guard 帶 captcha 重送一次.
  # `cb(captcha)` 要把 captcha 放進請求並回傳 promise; 第一次呼叫時 captcha 為 null.
  once: ({cb}) ->
    Promise.resolve!
      .then -> cb null
      .catch (e) ~>
        if lderror.id(e) != 1048 => return Promise.reject e
        @guard {cb}

if module? => module.exports = captcha
else window.captcha = captcha
