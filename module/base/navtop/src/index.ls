({core}) <- ldc.register \navtop, <[core]>, _
obj =
  toggled: true
  toggle: (v) ->
    @toggled = !!v
    if @view => @view.render!

core.init!then ->
  <-(->it.apply obj) _
  auth = core.auth
  @ <<< core{user, global}

  if !(navtop = ld$.find('[ld-scope="@servebase/navtop"]',0)) => return

  @update = (g) ~>
    p = if g => Promise.resolve(g) else auth.get!
    p.then (g) ~>
      @ <<< {global: g, user: g.user or {}}
      view.render!

  auth.on \update, (g) ~> @update g

  @view = view = new ldview do
    root: navtop
    action:
      click:
        signup: ~> auth.prompt {tab: \signup} .then ~> @update!
        login: ~> auth.prompt {tab: \login} .then ~> @update!
        logout: ~> auth.logout!then ~> @update!
        "set-lng": ({node, views}) ~>
          core.i18n.changeLanguage node.getAttribute \data-name
          views.0.render \lng
    init: t: ({node}) ->
      node.setAttribute(\t, node.textContent)
      node.innerText = ''
    text:
      displayname: ~> @user.displayname or 'User'
      username: ~> @user.username or 'n/a'
      lng: ->
        if !core.i18n => return
        lng = core.i18n.language
        view.getAll(\set-lng)
          .filter (n) -> (lng or '').toLowerCase! == (n.getAttribute(\data-name) or '').toLowerCase!
          .map (n) -> n.getAttribute(\data-alias) or n.innerText.trim!
          .0 or lng
      t: ({node}) ->
        return if core.i18n => core.i18n.t("@servebase/navtop:#{node.getAttribute(\t) or ''}") else ''
      version: ({node}) ~> "#{@global.version}-" + "#{@global.cachestamp}".slice(-4)
    handler:
      "show-version": ({node}) ~> node.classList.toggle \d-none, false
      "@": ({node}) ~> node.style.display = if @toggled => \block else \none
      admin: ({node}) ~> node.classList.toggle \d-none, !@user.staff
      unauthed: ({node}) ~> node.classList.toggle \d-none, !!@user.key
      authed: ({node}) ~> node.classList.toggle \d-none, !@user.key
      # deprecated: use `s/avatar` for dynamic user content, instead of `assets/avatar`
      avatar: ({node}) ~> node.style.backgroundImage = "url(/assets/avatar/#{@user.key})"


  if core.i18n => core.i18n.on \languageChanged, -> view.render \lng, \t

  if !(bar = view.get \root) => return {}
  dotst = (bar.getAttribute(\data-classes) or "").split(';').map(->it.split(' ').filter(->it))
  tst-tgt = if bar.getAttribute(\data-pivot) => ld$.find(document, that, 0) else null
  if !(dotst.length and tst-tgt) => return
  (new IntersectionObserver (->
    if !(n = it.0) => return
    # always toggle off first so we won't remove classes that in both before and after.
    (d,i) <- (if n.isIntersecting => [1,0] else [0,1]).for-each _
    dotst[d].map (c) -> bar.classList.toggle c, (i != 0)
  ), {threshold: 0.1}).observe tst-tgt

  return {}
return obj
