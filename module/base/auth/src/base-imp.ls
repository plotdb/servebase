base-imp =
  init: ({ctx, root, data, t}) ->
    {ldview, ldnotify, curegex, ldform} = ctx
    ({core}) <~ servebase.corectx _
    <-(~>it.apply @mod = @mod({core, t} <<< ctx)) _
    @_auth = data.auth
    (g) <~ @_auth.get!then _
    @global = g
    @ldcv = ldcv = {}
    ldcv.authpanel = new ldcover do
      root: root
      zmgr: core.zmgr
      # /* we should consider if `data.zmgr` is a good approach */ zmgr: data.zmgr
      # /* we should unify base-z */ base-z: (if data.zmgr => \modal else 3000)
    ldcv.authpanel.on \toggle.on, ->
      # dont know why we need 100ms delay to make this work. 
      # but indeed modal may still change style due to transition, after toggle.on.
      setTimeout (-> view.get('username').focus! ), 100
    @ <<< {_tab: 'login', _info: \default}
    @view = view = new ldview do
      root: root
      action:
        keyup: input: ({node, evt}) ~> if evt.keyCode == 13 => @submit!
        click:
          oauth: ({node}) ~>
            @_auth.oauth {name: node.getAttribute \data-name}
              .then (g) ~>
                debounce 350, ~> @info \default
                @form.reset!
                @ldcv.authpanel.set g
                ldnotify.send "success", t("login successfully")
          submit: ({node}) ~> @submit!
          switch: ({node}) ~>
            @tab node.getAttribute \data-name
      init:
        submit: ({node}) ~>
          @ldld = new ldloader root: node

      handler:
        oauths: ({node}) ~>
          node.classList.toggle \d-none, ![v for k,v of @global.oauth].filter(->it.enabled).length
        "signin-failed-hint": ({node}) ~> node.classList.toggle \d-none, !@_failed-hint
        "signin-failed-hint-text": ({node}) ~> node.innerText = @_failed-hint-text or ''
        oauth: ({node}) ~>
          node.classList.toggle \d-none, !(@global.oauth[node.getAttribute \data-name] or {}).enabled
        submit: ({node}) ~>
          node.classList.toggle \disabled, !(@ready)
        "submit-text": ({node}) ~>
          node.innerText = t(if @_tab == \login => \login else 'signup')
        displayname: ({node}) ~> node.classList.toggle \d-none, @_tab == \login
        info: ({node}) ~>
          hide = (node.getAttribute(\data-name) != @_info)
          if node.classList.contains(\d-none) or hide => return node.classList.toggle \d-none, hide
          node.classList.toggle \d-none, true
          setTimeout (-> node.classList.toggle \d-none, hide), 0
        switch: ({node}) ~>
          name = node.getAttribute \data-name
          node.classList.toggle \btn-light, (@_tab != name)
          node.classList.toggle \border, (@_tab != name)
          node.classList.toggle \btn-primary, (@_tab == name)
    @form = form = new ldform do
      names: -> <[username password displayname]>
      after-check: (s, f) ~>
        if s.username != 1 and !@is-valid.username(f.username.value) => s.username = 2
        if s.password != 1 =>
          s.password = if !f.password.value => 1 else if !@is-valid.password(f.password.value) => 2 else 0
        if @_tab == \login => s.displayname = 0
        else s.displayname = if !f.displayname.value => 1 else if !!f.displayname.value => 0 else 2
      root: root
    @form.on \readystatechange, ~> @ready = it; @view.render \submit

  interface: -> (toggle = true, opt = {}) ~>
    if opt.tab => @mod.tab opt.tab
    if opt.lock => @mod.ldcv.authpanel.lock!
    if toggle => @mod.ldcv.authpanel.get!
    else @mod.auth.fetch!then (g) -> @mod.ldcv.authpanel.set g

  mod: (ctx) ->
    {core, ldview, ldnotify, curegex, t} = ctx
    tab: (tab) ->
      if /failed/.exec(@_info) => @_info = \default
      @_tab = tab
      @view.render!
    is-valid:
      username: (u) -> curegex.get('email').exec(u)
      password: (p) -> p and p.length >= 8

    info: ->
      @_info = it
      @view.render \info

    submit: ->
      if !@form.ready! => return
      @_failed-hint = false
      @view.render \signin-failed-hint
      val = @form.values!
      body = {} <<< val{username, password, displayname}
      @ldld.on!
        .then -> debounce 1000
        .then ~>
          core.captcha.guard cb: (captcha) ~>
            body <<< {captcha}
            ld$.fetch "#{@_auth.api-root!}#{@_tab}", {method: \POST}, {json: body, type: \json}
        .catch (e) ~>
          if lderror.id(e) != 1005 => return Promise.reject e
          # 1005 csrftoken mismatch - try recoverying directly by reset session
          ld$.fetch "#{@_auth.api-root!}reset", {method: \POST}
            .then ~>
              # now we have our session cleared. fetch global data again.
              @_auth.fetch {renew: true}
            .then ~>
              # try logging in again. if it still fails, fallback to normal error handling process
              ld$.fetch "#{@_auth.api-root!}#{@_tab}", {method: \POST}, {json: body, type: \json}
        .then (ret = {}) ~>
          (g) <~ @_auth.fetch!then _
          if !ret.password-should-renew => return g
          <~ core.ldcvmgr.get {name: "@servebase/auth", path: "passwd-renew"} .then _
          return g
        .finally ~> @ldld.off!
        .then (g) ~>
          debounce 350, ~> @info \default
          @_failed-hint = false
          @view.render!
          @form.reset!
          @ldcv.authpanel.set g
          ldnotify.send "success", t("login successfully")
          return g
        .catch (e) ~>
          console.log e
          id = lderror.id e
          if id >= 500 and id < 599 => return lderror.reject 1007
          # session data corrupted
          if id == 1029 => return Promise.reject e
          # if we want to hint user the account existed.
          # we can handle error id 1014 here (apply existed resource)
          if id == 1004 => return @info "login-exceeded"
          # 1014: apply for a resource that already exists = account exists
          # id == 1012 = permission denied: usually for password incorrect
          # id == 1030 => password mismatched
          @_failed-hint-text = if id == 1014 => t("Account exists. try login")
          else if id in [1012 1030] => t("Password mismatched")
          else if id in [1009 1010] => t("Captcha failed")
          else if id == 1041 => t("Resource issue")
          else t("#{@_tab} failed")
          @info "#{@_tab}-failed"
          @_failed-hint = true
          @view.render!
          @form.fields.password.value = null
          @form.check {n: \password, now: true}
          # 1009, 1010: bot or captcha issue
          # 1041: resource possibly blocked by client (e.g., adblock blocks captcha)
          if !id or (id in [1009 1010 1041]) => throw e
