# cloudflare challenge 的前端處理 ( turnstile pre-clearance ), 以 `captcha.cfchallenge` 提供.
#
# fetch / websocket 被 challenge 只會拿到 403 + `cf-mitigated: challenge`, 背景解不了.
# 改跑開了 pre-clearance 的 turnstile: 通過後 cloudflare 種 `cf_clearance`, 之後同網域放行.
#
#  - `wrap(ld$)`: 包 `ld$.fetch`, 被 challenge 就跑 turnstile 後重送一次.
#  - `probe(url)`: GET 探 `url` 是否被 challenge, 是就解. 給拿不到 status 的 websocket 用.
#  - `solve()`: 跑 turnstile. 同時多個請求被擋只跑一次.
#
# opt:
#  - `sitekey`: 開了 pre-clearance 的 widget. 沒給就不作用.
#  - `clear`: 通過後把 token POST 到這裡. 只給本機模擬用 ( 沒有 cloudflare 種 cookie ).
#  - `timeout`: 多久沒結果 ( 也沒進入互動 ) 就放棄, ms. 預設 30 秒.
cfchallenge = (opt = {}) ->
  @sitekey = opt.sitekey or null
  @clear = opt.clear or null
  @timeout = opt.timeout or 30000
  @_solving = null
  @

err = (id) -> new Error! <<< {name: \lderror, id}

cfchallenge.prototype = Object.create(Object.prototype) <<<
  # 有 header ( ldquery >= 3.0.7 ) 就看 header, 沒有就認 challenge 頁的特徵.
  is-challenge: (e) ->
    if !e or (e.id != 403 and e.status != 403) => return false
    if e.headers and e.headers.get => return e.headers.get(\cf-mitigated) == \challenge
    d = if typeof(e.data) == \string => e.data else ''
    return /_cf_chl_opt|\/cdn-cgi\/challenge-platform\//.exec(d)?

  _script: ->
    if @_script-p => return @_script-p
    @_script-p = new Promise (res, rej) ~>
      if window.turnstile => return res!
      s = document.createElement \script
      s.onerror = ~>
        @_script-p = null
        rej err(1041)
      s.onload = -> res!
      s.setAttribute \src, \https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit
      document.body.appendChild s

  _ui: ->
    node = document.createElement \div
    node.classList.add \ldcv
    node.innerHTML = '''
    <div class="base"><div class="inner card"><div class="card-body text-center">
    <div class="mb-2">please confirm you are human to continue.</div>
    <div ld="box" class="d-inline-block"></div>
    </div></div></div>
    '''
    document.body.appendChild node
    # resident: 不然 ldcover 會把 node 移出 document, turnstile 就不會跑.
    {node, box: node.querySelector('[ld=box]'), ldcv: new ldcover(root: node, escape: false, resident: true)}

  solve: ->
    if !@sitekey => return Promise.reject err(1010)
    if @_solving => return @_solving
    ui = null
    wid = null
    timer = null
    @_solving = @_script!
      .then ~>
        ui := @_ui!
        (res, rej) <~ new Promise _
        # 背景階段沒結果就放棄. 進入互動後交給使用者, 逾時由 turnstile 的 timeout-callback 處理.
        timer := setTimeout (-> rej err(1010)), @timeout
        # `interaction-only`: 需要互動才開遮罩.
        wid := turnstile.render ui.box, do
          sitekey: @sitekey
          appearance: \interaction-only
          callback: (token) -> res token
          "error-callback": -> rej err(1010)
          "expired-callback": -> rej err(1010)
          "timeout-callback": -> rej err(1010)
          "unsupported-callback": -> rej err(1010)
          "before-interactive-callback": ->
            clearTimeout timer
            ui.ldcv.toggle true
      .then (token) ~>
        if !@clear => return
        fetch @clear, {method: \POST, headers: {'content-type': 'application/json'}, body: JSON.stringify({token})}
      .finally ~>
        clearTimeout timer
        @_solving = null
        if wid? and window.turnstile => try turnstile.remove wid
        if ui =>
          ui.ldcv.toggle false
          ui.node.parentNode.removeChild ui.node
    @_solving

  # 探 `url` 有沒有被 challenge, 有就解. 回傳是否有解過.
  probe: (url) ->
    if !@sitekey => return Promise.resolve false
    fetch url, {method: \GET, credentials: \same-origin, cache: \no-store}
      .then (r) ~>
        if !(r.status == 403 and r.headers.get(\cf-mitigated) == \challenge) => return false
        @solve!then -> true
      .catch -> false

  # 被 challenge 就解, 再送一次; 還是被擋就回原本的錯誤.
  # ld$.fetch.headers ( 例如 csrf token ) 由 ldquery 讀取, 要沿用同一個物件.
  wrap: (ld$) ->
    if !ld$ or !ld$.fetch or ld$.fetch._cfchallenge => return
    orig = ld$.fetch
    wrapped = (...args) ~>
      orig.apply ld$, args
        .catch (e) ~>
          if !(@sitekey and @is-challenge(e)) => return Promise.reject e
          @solve!
            .catch -> Promise.reject e
            .then -> orig.apply ld$, args
    wrapped <<< orig
    wrapped._cfchallenge = true
    ld$.fetch = wrapped

# 跟 captcha.ls 串在同一個 dist 裡, 掛在 captcha 下, 不另外 export.
(if module? => module.exports else window.captcha).cfchallenge = cfchallenge
