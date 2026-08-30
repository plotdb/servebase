# watch the server's version header go by, and say so when it changes.
#
# usage:
#
#     refresh.init!
#     refresh.on \updated, ({from, to}) -> ...show a notice, let the user reload...
#
# design notes:
#
#  - it hooks `fetch` rather than polling. a page that talks to the server at all will
#    notice; a page that never does will not, which is the right trade for a poc - a
#    heartbeat can be added later without changing this interface.
#  - it fires once. the point is to offer a reload, not to nag.
#  - it never reloads by itself. a forced reload loses whatever the user was typing,
#    and the whole reason this exists is that the page is *usable* but stale.

refresh = do
  header: 'x-app-version'
  seen: null
  fired: false
  handler: {}
  _inited: false

  on: (n, cb) -> (@handler[n] or= []).push cb
  fire: (n, ...args) -> for cb in (@handler[n] or []) => cb.apply @, args

  # compare one response's version header against the first one we ever saw.
  observe: (v) ->
    if !v => return
    if !@seen => @seen = v; return
    if v == @seen or @fired => return
    @fired = true
    console.log "[@servebase/refresh] server moved from #{@seen} to #v"
    @fire \updated, {from: @seen, to: v}

  init: (o = {}) ->
    if @_inited => return @
    @_inited = true
    if o.header => @header = o.header.toLowerCase!
    if typeof(fetch) != \function => return @
    orig = fetch
    # wrap rather than replace: anything already holding a reference keeps working,
    # and a failed request must not be swallowed here.
    window.fetch = (...args) ~>
      orig.apply(window, args).then (res) ~>
        try @observe res.headers.get(@header)
        return res
    return @

if typeof(window) != 'undefined' => window.servebaseRefresh = refresh
if typeof(module) != 'undefined' and module? => module.exports = refresh
