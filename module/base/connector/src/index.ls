connector = (opt = {}) ->
  @ <<< ws: null, _running: false, _tag: "[@servebase/connector]"
  @_init = opt.init
  # opt.ldcv - ui hooks, named after connection states. backward compatible:
  #   - `(v) ->` or `{toggle}`: offline cover only (original form)
  #   - `{unstable: (v, ctx) ->, offline: (v, ctx) ->}`:
  #     - offline: disconnection is confirmed; toggles the blocking cover
  #       (same contract as the original ldcv form).
  #     - unstable: disconnection is suspected - local changes are not
  #       acknowledged in time. toggled with true / false; the hint ui
  #       tracks elapsed time itself. requires opt.pending.
  #     - ctx: {ws} - connector is the source of ws; take it from here
  #       instead of reaching for closures or `this`.
  # normalized into {offline, hint} regardless of the given form.
  # the original function form was historically invoked as `@_ldcv(v)`, which
  # bound `this` to the connector - consumers exist that rely on it (e.g. `@ws`),
  # so we keep that contract by binding in its wrapper here. new-form callbacks
  # receive everything via arguments and are deliberately NOT this-bound.
  ldcv = opt.ldcv or (->)
  @_ldcv =
    if typeof(ldcv) == \function => {offline: (v, ctx) ~> ldcv.call @, v, ctx}
    else if ldcv.toggle => {offline: (v) -> ldcv.toggle v}
    else {offline: (ldcv.offline or (->)), hint: ldcv.unstable}
  @_error = opt.error or null
  @_reconnect = opt.reconnect
  @_path = opt.path or \/ws
  # opt.pending - enables unstable-connection detection (with ldcv.unstable).
  # either a function or {check, threshold, interval}:
  #   - check (or the function form): -> truthy if there are local changes
  #     not yet acknowledged by remote
  #     (e.g., -> conn.hub.judge.doc?.hasPending()).
  #     consumer-defined, since connector is agnostic of what "pending" means.
  #   - threshold: unstable when pending lasts longer than this (ms). default 3000.
  #   - interval: polling interval (ms). default 1000.
  @_peekcfg = {threshold: 3000, interval: 1000}
  pending = opt.pending or null
  @_pending = if typeof(pending) == \function => pending else (pending or {}).check or null
  if pending and typeof(pending) != \function =>
    for k in <[threshold interval]> => if pending[k]? => @_peekcfg[k] = pending[k]
  @_evthdr = {}
  @hub = {}
  @

connector.prototype = Object.create(Object.prototype) <<<
  on: (n, cb) -> (if Array.isArray(n) => n else [n]).map (n) ~> @_evthdr.[][n].push cb
  fire: (n, ...v) -> for cb in (@_evthdr[n] or []) => cb.apply @, v
  open: ->
    console.log "#{@_tag} ws reconnect ..."
    @ws.connect!
      .then ~> console.log "#{@_tag} object reconnect ..."
      .then ~> if @_reconnect => @_reconnect!
      .then ~> @fire \reconnect
      .then ~> console.log "#{@_tag} connected."
      .catch (e) ~>
        # this may be caused by customized reconnect, which contains initialization code.
        # we should stop and hint user otherwise it may lead to unexpected result.
        # original code, which ignore error if ws connected: /* if @ws.status! == 2 => return */
        # additionally, we may want to customize error info based on returned code
        # so we support a customized error handler here if available.
        if @_error and typeof(@_error) == \function => return @_error(e)
        Promise.reject e
      .catch (e) ~>
        # error handler may simply return a altered error, so we still take care of it here.
        # this may be considered as redundant since we reject a rejection directly in a rejection handler (TBR)
        Promise.reject e
  reopen: ->
    if @_running => return
    @_running = true
    @_ldcv.offline true, {ws: @ws}
    debounce 1000
      .then ~> @open!
      .then -> debounce 350
      .then ~> @_ldcv.offline false, {ws: @ws}
      .then ~> @_running = false
  # poll `pending` and show / hide the hint accordingly.
  # sampling states instead of listening events keeps this robust against
  # reconnect races - we never miss or double-count anything.
  _peek: ->
    pending = false
    try pending = !!@_pending! catch e => pending = false
    now = Date.now!
    if !pending or !(@_peekcfg.last?) => @_peekcfg.last = now
    waited = now - @_peekcfg.last
    # show only in the undetected window; once offline is declared
    # (status != 2), the offline cover takes over and the hint yields.
    # summon / dismiss on transitions only - the hint ui keeps time itself.
    if @ws and @ws.status! == 2 and waited >= @_peekcfg.threshold =>
      if !@_hint-on =>
        @_hint-on = true
        @_ldcv.hint true, {ws: @ws}
    else if @_hint-on =>
      @_hint-on = false
      @_ldcv.hint false, {ws: @ws}
    setTimeout (~> @_peek!), @_peekcfg.interval

  init: ->
    @ws = new ews {path: @_path}
    @ws.on \offline, ~>
      # close event from browser may not be reliable, but offline event is from ews itself.
      # so we also reopen here.
      @reopen!
    @ws.on \close, ~> @reopen!
    if @_init => @_init!
    if @_pending and @_ldcv.hint =>
      @_peekcfg.last = Date.now!
      @_peek!
    @open!


if module? => module.connector = connector
else if window? => window.connector = connector
