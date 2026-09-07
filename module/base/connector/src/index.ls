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
  #     - stalled: local changes have gone unacknowledged past `blockAfter`
  #       while the socket still reports itself up. toggled with true / false
  #       and given {ws, waited, since}; `since` is when the queue last drained,
  #       so the ui can keep its own clock. requires opt.pending.
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
    else {
      offline: (ldcv.offline or (->))
      hint: ldcv.unstable
      stalled: ldcv.stalled
    }
  @_error = opt.error or null
  @_reconnect = opt.reconnect
  @_path = opt.path or \/ws
  # opt.grace - delay (ms) between disconnection confirmed and the offline
  # cover actually summoned. a reconnect within the window stays completely
  # silent - no cover flash for transient outages. local changes made in the
  # window are safe as long as the consumer's sync layer queues and resends
  # unacknowledged ops ( e.g. sharedb pendingOps ). the unstable hint ( if
  # provided ) is summoned right away instead, so the window is not silent.
  # set 0 to summon immediately ( the original behavior ). default 2000.
  @_grace = if opt.grace? => opt.grace else 2000
  @_covered = false
  @_hint-on = false
  @_stalled = false
  # opt.pending - enables unstable-connection detection (with ldcv.unstable).
  # either a function or {check, threshold, interval}:
  #   - check (or the function form): -> truthy if there are local changes
  #     not yet acknowledged by remote
  #     (e.g., -> conn.hub.judge.doc?.hasPending()).
  #     consumer-defined, since connector is agnostic of what "pending" means.
  #   - threshold: unstable when pending lasts longer than this (ms). default 3000.
  #   - interval: polling interval (ms). default 1000.
  #   - guard: warn ( native browser confirm ) when leaving the page while
  #     pending is truthy. default true; set false to opt out.
  #   - blockAfter: how long pending may last before the situation stops being
  #     a hint and becomes `ldcv.stalled` ( ms ). default 15000; 0 disables.
  #
  # On blockAfter: "some data is not yet confirmed" is an honest thing to say
  # for a few seconds. Past that it is no longer true - the data is not getting
  # through, and everything the user does meanwhile is being lost. A
  # non-blocking banner is the wrong shape for that: it reads as a transient
  # network blip, so people keep working, and the longer they keep working the
  # more there is to lose. Past the threshold the consumer gets to escalate.
  #
  # `stalled` is toggled, not fired once: being stalled is a condition, not an
  # event. If the queue drains ( a late flush, a recovered route ) it is toggled
  # back off and the user carries on - nothing here is terminal by itself, so
  # nothing here should force a reload.
  @_peekcfg = {threshold: 3000, interval: 1000, blockAfter: 15000}
  pending = opt.pending or null
  @_pending = if typeof(pending) == \function => pending else (pending or {}).check or null
  @_guard = true
  if pending and typeof(pending) != \function =>
    for k in <[threshold interval blockAfter]> => if pending[k]? => @_peekcfg[k] = pending[k]
    if pending.guard? => @_guard = !!pending.guard
  @_evthdr = {}
  @hub = {}
  @

connector.prototype = Object.create(Object.prototype) <<<
  on: (n, cb) -> (if Array.isArray(n) => n else [n]).map (n) ~> @_evthdr.[][n].push cb
  fire: (n, ...v) -> for cb in (@_evthdr[n] or []) => cb.apply @, v
  open: ->
    console.log "#{@_tag} ws reconnect ..."
    @ws.connect!
      # ews rejects `connect` when there is already a socket ( 1011, a generic
      # "resource conflict" - it is raised from more than one place and does not
      # by itself mean "already connected" ). what we actually need to know is
      # whether the socket ended up usable, so ask the socket rather than read
      # intent into an error code. this catch stays attached to `connect` alone;
      # further down the chain it would swallow `_reconnect` failures too.
      .catch (e) ~> if @ws.status! == 2 => return else Promise.reject e
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
  # toggle the unstable hint, deduped by transition.
  _hint: (v) ->
    if !@_ldcv.hint or @_hint-on == !!v => return
    @_hint-on = !!v
    @_ldcv.hint !!v, {ws: @ws}
  # same contract for the stalled cover. deduped so the consumer sees edges
  # only - it is toggling a cover, and re-toggling it every second would fight
  # whatever animation it has.
  _stall: (v, ctx = {}) ->
    if !@_ldcv.stalled or @_stalled == !!v => return
    @_stalled = !!v
    @_ldcv.stalled !!v, {ws: @ws} <<< ctx
  reopen: ->
    if @_running => return
    @_running = true
    @_covered = false
    # disconnection confirmed. hint immediately, but hold the blocking cover
    # for a grace window - reconnection ( below ) runs in parallel, and a
    # quick recovery stays non-blocking. note ews does not reconnect by
    # itself, so `open` must not wait for the grace debounce.
    # the status check covers ws-up-but-reconnect-still-running: no need to
    # block when the connection is already back.
    @_hint true
    summon = ~>
      if @ws and @ws.status! == 2 => return
      @_covered = true
      @_hint false
      @_ldcv.offline true, {ws: @ws}
    # function-form debounce for `cancel`. delay 0 falls back to 750 in
    # debounce.js, so grace 0 ( immediate cover ) is called directly.
    hold = if @_grace > 0 => debounce(summon, @_grace)! else (summon!; null)
    # short settle delay only - retry pacing ( backoff ) is ews's job.
    debounce 200
      .then ~> @open!
      .then ~>
        if hold => hold.cancel!
        @_hint false
        if !@_covered => return
        debounce 350 .then ~> @_ldcv.offline false, {ws: @ws}
      .then ~> @_covered = false; @_running = false
      .catch (e) ~>
        # Reconnect failed. Treat it as terminal and make sure of one thing: the
        # blocking cover stays up. It is the only thing on screen saying that
        # local changes no longer reach remote, and before this catch existed a
        # rejection here could leave the flow half-done with the cover already
        # dismissed.
        #
        # `_running` deliberately stays set. Releasing it would let the next
        # offline event retry straight back into the same failure and flip the
        # cover on and off; the user's way out of a terminal state is a reload,
        # which is what the rethrow below ends up telling them.
        @_hint false
        if !@_covered =>
          @_covered = true
          @_ldcv.offline true, {ws: @ws}
        @fire \error, e
        # Rethrow rather than swallow. Without a catch here this rejection went
        # unhandled and reached the app's global lderror handler, which is what
        # surfaced the failure to the user - keep that path intact.
        Promise.reject e
  # poll `pending` and show / hide the hint accordingly.
  # sampling states instead of listening events keeps this robust against
  # reconnect races - we never miss or double-count anything.
  _peek: ->
    # during reopen the ui is owned by `reopen` ( hint through the grace
    # window, then the offline cover ) - stand down and just keep ticking.
    # resetting `last` also gives pending a fresh threshold after reconnect,
    # so queued ops get a chance to drain before the hint reappears.
    if @_running =>
      @_peekcfg.last = Date.now!
      # reopen's cover is blocking too, so drop ours or the two stack. The
      # `!up` branch below cannot do this: whenever the socket is down, reopen
      # is running and execution never reaches it.
      @_stall false
    else
      pending = false
      try pending = !!@_pending! catch e => pending = false
      now = Date.now!
      # the queue drained - whatever we were showing about it is no longer true.
      if !pending or !(@_peekcfg.last?) =>
        @_peekcfg.last = now
        @_stall false
      waited = now - @_peekcfg.last
      up = @ws and @ws.status! == 2
      if !up =>
        # socket is down while reopen is not running ( it has already given up,
        # or has not started yet ). nothing of ours belongs on screen here.
        @_stall false
        # reset the clock too: on reconnect the queue gets a fresh window to
        # drain in, instead of being judged on time it spent offline - otherwise
        # the cover flashes for a moment before the flush lands.
        @_peekcfg.last = now
      else if @_peekcfg.blockAfter > 0 and waited >= @_peekcfg.blockAfter =>
        # Pending has outlasted anything a "connection hiccup" can explain,
        # while the socket still reports itself as up - so nothing else in this
        # stack will say a word. `reopen` is not running, no offline event is
        # coming, and the hint has been sitting there being ignorable the whole
        # time. Escalate, and drop the hint: the cover is now the accurate
        # description. Recoverable by design - if the queue drains above, this
        # is toggled straight back off.
        @_hint false
        @_stall true, {waited, since: @_peekcfg.last}
      else if !@_stalled =>
        # only in the undetected window ( socket looks connected );
        # summon / dismiss on transitions only - the hint ui keeps time itself.
        @_hint (waited >= @_peekcfg.threshold)
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
    if @_pending and @_guard and typeof(window) != \undefined =>
      # warn before leaving while local changes are still unacknowledged
      # ( browsers only allow their own generic confirm here ).
      # we may not be the only beforeunload handler on the page, so:
      # addEventListener instead of `window.onbeforeunload =`, and touch the
      # event only when we do have pending data - if another handler already
      # objected ( preventDefault / returnValue ), its decision stands either way,
      # since the dialog shows if any handler objects.
      window.addEventListener \beforeunload, (e) ~>
        p = false
        try p = !!@_pending! catch err => p = false
        if !p => return
        e.preventDefault!
        # for legacy engines; keep any message another handler may have set.
        if !e.returnValue => e.returnValue = true
    @open!


if module? => module.connector = connector
else if window? => window.connector = connector
