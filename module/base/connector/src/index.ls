connector = (opt = {}) ->
  @ <<< ws: null, _running: false, _tag: "[@servebase/connector]"
  @_init = opt.init
  @_ldcv = opt.ldcv or (->)
  @_error = opt.error or null
  @_reconnect = opt.reconnect
  @_path = opt.path or \/ws
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
    if @_ldcv.toggle => @_ldcv.toggle(true) else @_ldcv(true)
    debounce 1000
      .then ~> @open!
      .then -> debounce 350
      .then ~> if @_ldcv.toggle => @_ldcv.toggle(false) else @_ldcv(false)
      .then ~> @_running = false
  init: ->
    @ws = new ews {path: @_path}
    @ws.on \offline, ~>
      # close event from browser may not be reliable, but offline event is from ews itself.
      # so we also reopen here.
      @reopen!
    @ws.on \close, ~> @reopen!
    if @_init => @_init!
    @open!


if module? => module.connector = connector
else if window? => window.connector = connector
