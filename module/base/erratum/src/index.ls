# window.onerror is not triggered when the console directly generates an error.
# It can be triggered via wrapping test code with setTimeout - however `evt.error` will be null
# alternative to listener: window.onerror = (msg,fn,lineno,colno,error) -> ...
erratum = (o = {}) ->
  if !window? => console.warn "[@servebase/erratum] no window to listen to error/rejection"
  window.addEventListener \error, (evt) ~> @error-handler(evt)
  window.addEventListener \unhandledrejection, (evt) ~>
    try
      @rejection-handler(evt)
    catch e
      # rejection-handler may throw error again, which triggers error event.
      # catch and ignore it to prevent duplicated errors.
  if o.handler => @handler = o.handler
  # armed at most, never engaged - start-up errors are the ordinary kind.
  # see `lockdown` below.
  @_lockdown = o.lockdown or null
  @_locked = false
  @_fired = false
  @

erratum.prototype = Object.create(Object.prototype) <<<
  handler: (e) ->

  # Route EVERY error to one dialog instead of the per-error handling above.
  # Answering each error on its own terms is right while the error is the
  # problem, and wrong once the page itself cannot be trusted - from there every
  # further action runs against a state nobody can vouch for.
  #
  # A toggle because when it is safe to engage is a runtime question: start-up
  # has its own ordinary failures. See README -> Lockdown.
  #
  #     erratum.lockdown -> ldcvmgr.lock {ns: \local, name: \hint-reload}
  #     erratum.lockdown false   # back to per-error handling
  lockdown: (v) ->
    if typeof(v) == \function => [@_lockdown, v] = [v, true]
    @_locked = !!(v and @_lockdown)
    # re-arm on the way down, so it can lock again later
    if !@_locked => @_fired = false
    @_locked

  locked: -> @_locked

  # true when lockdown took the error and normal handling should be skipped
  _lock: (e) ->
    if !@_locked => return false
    # Latched: the page is already declared unsafe, and whatever is failing
    # tends to keep failing - without this it would stack a cover per error.
    if @_fired => return true
    @_fired = true
    try
      @_lockdown e
    catch err
      # the dialog's own throw lands back here through the error event
      console.error "[@servebase/erratum] lockdown handler failed:", err
    true

  error-handler: (evt) ->
    if @_lock evt.error => return
    if !(lderror.event-handler.error evt) => @handler evt.error
  rejection-handler: (evt) ->
    if @_lock evt.reason => return
    if !(lderror.event-handler.rejection evt) => @handler evt.reason
  test: (o = {}) ->
    if o.bare => @_test o
    else ((o) -> setTimeout (~>@_test o), 0) o
  _test: (o) ->
    if o.promise => lderror.reject(1023) else throw lderror 1023

if module? => module.exports = erratum
else window.erratum = erratum
