<-(->it.apply {}) _
lc = {}

# get global object.
# - Sometimes we may access global data before it's available.
#   wrap it with proxise so all callers can wait for init fetch event to finish.
# - put it here so it can't be resolved by user from dev console.
#   user can still modify auth object so we actually can't prevent users from altering this module.
get-global = proxise (a) ->
  if lc.global => return Promise.resolve lc.global
  else if lc.fetching => return
  if a => a.fetch!

auth = (opt={}) ->
  @_ldcvmgr = opt.ldcvmgr
  @_manager = opt.manager
  @timeout = {loader: 1000, failed: 10000}
  @evt-handler = {}
  @ui = do
    loader: opt.loader or {on: ->, off: ->, cancel: ->}
    authpanel: (tgl, o = {}) ~>
      if @_authpanel => return @_authpanel tgl, o
      @ui.loader.on 350
      bid = (opt.authpanel or {name: "@servebase/auth"})
      @_manager.from bid, {autoTransform: \i18n, root: document.body, data: {auth: @, zmgr: opt.zmgr}}
        .then (p) ~> @_authpanel = p.interface
        .then (i) ~>
          @ui.loader.off!
          i tgl, o
    timeout: -> new Promise (res, rej) -> # do nothing

  if !@_api-root => @_api-root = opt.api or "/api/auth"
  if @_api-root[* - 1] != \/ => @_api-root += \/
  if !opt.init-fetch? or opt.init-fetch => @fetch!
  @

auth.prototype = Object.create(Object.prototype) <<< do
  on: (n, cb) -> (if Array.isArray(n) => n else [n]).map (n) ~> @evt-handler.[][n].push cb
  fire: (n, ...v) -> for cb in (@evt-handler[n] or []) => cb.apply @, v
  inject: -> {} # TBD. may need to be customizable
  api-root: -> return @_api-root
  set-ui: -> @ui <<< (it or {}) # TBD. seems not needed anymore.
  logout: ->
    @ui.loader.on!
    ld$.fetch "#{@api-root!}logout", {method: \post}, {}
      .then ~> @fetch {renew: true}
      .finally ~> @ui.loader.off!
      .then ~>
        # even if `@fetch` fires `update` event,
        # we still fire `logout here to indicate this is an intentional logout.
        @fire \logout
      .catch (e) ~> @fire \error, e
  reset: ->
    @ui.loader.on!
    auth.reset!

  # ensure user is authed. shorthand and for readbility for auth.get({authed-only:true})
  ensure: (opt = {}) -> @get(opt <<< {authed-only: true})

  # for retrieving global object in local.
  get: (opt = {authed-only: false}) ->
    get-global @
      .then (g = {}) ~>
        if !opt.authed-only => return g
        # @ui.authpanel may be overwritten and incorrectly return sth other than g
        # thus we fetch it again.
        return if g.user.key => g
        else @ui.authpanel(true, opt).then -> get-global @
      .then (g = {}) ->
        if opt.authed-only and !g.{}user.key => return Promise.reject(new lderror(1000))
        return g

  # for retrieving global object from server ( or cookie ). this won't trigger sign up ui.
  fetch: (opt = {renew: true}) ->
    lc.fetching = true
    # if d/global response later then 1000ms, popup a loader
    @ui.loader.on @timeout.loader
    # if it took too long to respond, just hint user about possibly server issue
    @watchdog = debounce(@timeout.failed, ~>
      @ui.loader.off!
      @ui.timeout!
        .then ~> @ui.loader.on!
        .then -> debounce 10000
        .then ~> @fetch!
    )!

    # if we don't force renew and there is a cache in cookie
    # otherwise we fetch data from server
    ret = if !opt.renew and /global=/.exec(document.cookie) =>
      document.cookie
        .split \;
        .map -> /^global=(.+)/.exec(it.trim!)
        .filter -> it
        .0
    else null

    promise = if ret => Promise.resolve JSON.parse(decodeURIComponent(ret.1))
    else ld$.fetch "#{@api-root!}info", {}, {type: \json}
    promise
      .finally (g) ~>
        @watchdog.cancel!
        @ui.loader.cancel!
        @ui.loader.off!
      .then (g) ~>
        lc.fetching = false
        ld$.fetch.{}headers['X-CSRF-Token'] = g.csrfToken
        g.ext = @inject(g) or {}
        get-global.resolve JSON.parse(JSON.stringify(lc.global = g))
        try
          @fire \update, lc.global
        catch e
          # error after data fetched. prompt, but still return global
          @fire \error, e; console.log e
        return lc.global

      .catch (e) ~>
        if lderror.id(e) == 1029 => return Promise.reject e
        e <<< {name: \lderror, id: 1007}
        @fire \error, e
        console.log "server down: ", e
        # since server is down and we have handled it here,
        # we simply return a promise that won't be resolved
        # to stop further progress of current code.
        new Promise (res, rej) ->

  prompt: (o) -> @ui.authpanel true, o
  oauth: ({name, invite-token}) ->
    @get!
      .then (g = {}) ~>
        if g.{}user.key => return g
        # before oauth login
        @oauth.window = window.open '', '_blank', 'height=640,width=560'
        try
          @oauth.window.opener = null
          @oauth.window.name = 'oauth-login'
        catch e => return Promise.reject(e)
        @oauth.form = form = ld$.create name: \div
        token = if !invite-token => ""
        else """<input type="hidden" name="inviteToken" value="#{encodeURIComponent invite-token}"/>"""
        form.innerHTML = """
        <form target="oauth-login" action="#{@api-root!}#name/" method="post">
          <input type="hidden" name="_csrf" value="#{g.csrf-token}"/>#token
        </form>"""
        document.body.appendChild form
        window.oauth-login = login = proxise(-> ld$.find(form, 'form', 0).submit!)
        login!then ~> @fetch {renew: true}
      .finally ~>
        if !(@oauth.form and @oauth.form.parentNode) => return
        @oauth.form.parentNode.removeChild @oauth.form
      .then (g = {}) -> if !g.{}user.key => Promise.reject new lderror(1000) else return g
      .catch (e) ~> @fire \error, e; return Promise.reject(e)

  ensure-verified: ->
    (g) <~ @fetch {renew: true} .then _
    if ((g.user or {}).verified or {}).date => return \done
    @_ldcvmgr.get({name: \@servebase/auth, path: \ensure-verified})

# auth issue may lead to uninitialized auth.
# in this case, we have to call `auth.reset` so we don't have to pend on a never-inited auth obj.
auth.reset = -> window.location.href = "/auth/reset"

if module? => module.exports = auth
else if window? => window.auth = auth
