# Connector Utility Class

`@servebase/connector` is a tiny helper for reconnecting websocket connection. Usage:

    conn = new connector({ ... });
    conn.init!then -> ...

with following constructor options:

 - `init()`: customized initialization function. optional.
 - `reconnect()`: customized function called when (re)connected. optional.
 - `error(e)`: customized error handler for connecting failures. optional.
   a failed reconnect is terminal: the blocking cover is guaranteed to stay
   up, and the rejection propagates (reaching the page's global handler if
   nothing catches it) rather than being retried into the same failure. a
   `connect` that fails only because the socket is already up is not a
   failure - it is checked by socket state, not by error code.
 - `path`: websocket server path. default `/ws`.
 - `grace`: delay (ms) between disconnection confirmed and `ldcv.offline`
   actually summoned. reconnection starts right away regardless; if it
   completes within the window the blocking cover never shows - no cover
   flash for transient outages. `ldcv.unstable` (if provided) is summoned
   immediately instead, so the window is not silent. safe as long as the
   sync layer queues and resends unacknowledged ops (e.g. sharedb
   pendingOps); set `0` to summon the cover immediately (the pre-grace
   behavior). default 2000.
 - `ldcv`: ui hooks, named after connection states. accepts following forms:
   - `{offline, unstable}`: an object with callbacks per connection state:
     - `offline(v, ctx)`: disconnection is confirmed. toggle the blocking
       cover with `v` (`true` = show). same timing as the original `ldcv`
       function form.
     - `unstable(v, ctx)`: disconnection is suspected - local changes are not
       acknowledged in time. toggle a non-blocking hint with `v`; the hint ui
       should track elapsed time itself, since connector only summons and
       dismisses it on state transitions. requires the `pending` option;
       omit `unstable` (or `pending`) to disable.
     - `stalled(v, ctx)`: local changes have gone unacknowledged past
       `blockAfter` while the socket still reports itself up. toggle a
       blocking cover with `v`. `ctx` additionally carries `{waited, since}`;
       `since` is when the queue last drained, so the ui can keep its own
       clock. requires the `pending` option; omit `stalled` (or `pending`,
       or set `blockAfter: 0`) to disable.
     - `ctx`: `{ws}`. connector is the source of `ws` - take it from here
       instead of reaching for closures or `this`. new-form callbacks are
       deliberately not `this`-bound.
   - `(v) ->`: original form; same as providing only `offline`. for backward
     compatibility this is invoked with `this` bound to the connector
     (existing consumers rely on e.g. `@ws`), and also receives `(v, ctx)`.
   - a ldcover(-like) object: `toggle(v)` is called; same as `offline`.
 - `pending`: enables unstable-connection detection. either a function or
   `{check, threshold, interval}`:
   - `check()` (or the function form): should return truthy if there are
     local changes not yet acknowledged by remote, e.g.:

         pending: -> conn.hub.judge.doc?.hasPending()

     this is consumer-defined, since connector is agnostic of what "pending"
     means at app level. sampled by polling (instead of listening events) so
     it stays robust against reconnect races.
   - `threshold`: report unstable when pending lasts longer than this (ms).
     default 3000.
   - `interval`: polling interval (ms). default 1000.
   - `blockAfter`: escalate from `unstable` to `stalled` when pending lasts
     longer than this (ms). default 15000; set `0` to disable.
   - `guard`: warn when leaving the page while `check()` is truthy - data
     entered may not have reached the server yet. browsers only allow their
     own generic confirm dialog here, no custom message. registered with
     `addEventListener` and acts only when pending, so it coexists with any
     other `beforeunload` handler on the page. default true; set `false` to
     opt out.

A typical modern setup:

    conn = new connector do
      pending: -> conn.hub?judge?doc?hasPending!
      init: -> ...
      reconnect: -> ...
      ldcv:
        offline: (v, {ws}) -> ldcvmgr.toggle {ns: \local, name: \offline-retry}, v, {ws}
        unstable: (v) -> ldcvmgr.toggle {ns: \local, name: \unstable-hint}, v
        stalled: (v, {since}) ->
          ldcvmgr.toggle {ns: \local, name: \sync-stalled}, v, {since}

Note: prepare (prefetch) the covers used by `offline` / `unstable` / `stalled`
at init time - they can't be fetched once the network is gone.


And following API:

 - `init()`: create a websocket and connect to server through it.
   - return a Promise, which is resolved when connected.
   - customized init will be called before connecting. 
 - `open`: open a socket connection. auto called after `init()` is called.
 - `reopen`: reopen a socket connection. auto called when previous socket was closed.
   - unlike `open`, this triggers `ldcv.offline` for loading indicator.
 - `on(name, cb)`: register an event handler for event `name`.
 - `fire(name, ...args)`: fire an event with `name` and additional options `...args`.
 - `peek()`: actively hint connector to check against pending jobs.
 - `safeguard()`: poke this from your own write path ( e.g. right after each
   update ). debounced, so calling it on every keystroke is free. it watches
   for exactly one thing: local changes still arriving long after the socket
   went down. by that point the unstable hint, the offline cover and the
   stalled cover have each had their chance to stop it and demonstrably did
   not, so the situation is terminal - `ldcv.dead` is called, or an error
   thrown if no such hook was given. shares nothing with `peek` or the polling
   loop: it keeps its own clock, cleared whenever the socket comes back. see
   `_safeguard` in the source.

Available members for customized functions:

 - `ws`: websocket object.
 - `hub`: empty object for storing customized object.


## Unstable, stalled and offline

Disconnection can never be known immediately - a half-open socket accepts
writes that silently go nowhere until heartbeat timeouts declare it dead.
connector thus reports three escalating states:

 - `unstable`: summoned in two situations - (a) `pending()` stays truthy
   beyond `threshold` while the socket still looks connected: data may not
   have been delivered; (b) disconnection just got confirmed and
   reconnection is in progress, through the `grace` window. either way the
   ui should warn without blocking (e.g., a small banner).
 - `stalled`: `pending()` has stayed truthy past `blockAfter` while the
   socket still reports itself up. "some data is not yet confirmed" is an
   honest thing to say for a few seconds; past that it is not - the data is
   not getting through, and everything entered meanwhile is being lost. Note
   that nothing else here will speak up in this situation: reconnection is
   not running, no offline event is coming, and the non-blocking hint has
   been sitting there being ignorable the whole time. The ui should block.
 - `offline`: reconnection did not complete within the `grace` window; the
   blocking cover takes over and `unstable` yields. a transient outage thus
   shows at most the non-blocking hint.

`stalled` differs from the other two in kind: it describes a condition, not a
verdict. It is toggled back off as soon as the queue drains, so the ui should
offer a reload rather than force one - forcing it would discard the very
pendingOps being waited on. It also yields whenever the socket goes down,
leaving that case to `offline` so the two covers never stack.

All are dismissed once reconnection completes and pending drains.
