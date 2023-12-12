({core}) <- ldc.register <[admin core navtop]>, _
<- core.init!then _
<-(->it.apply core) _
@ldcv = {}
@bd = {}
@view = {}
@view.panel = new ldview do
  root: document.body
  action: click: do
    pay: ({node, evt}) ->
      payment.request do
        gateway: node.getAttribute(\data-name)
        payload:
          scope: \demo
          name: "Generic Goods"
          amount: "13"
    "toggle-block": ~>
      core.ldcvmgr.get JSON.parse(@view.panel.get('block-code').value)
    "toggle-error": ~>
      core.error(lderror +(@view.panel.get('error-code').value or 0) )
    error: ~> @error((new lderror 1023) <<< uuid: Math.random!toString(36)substring(2))
    "unhandled-rejection": ~> Promise.reject(lderror 1023)
    # we need an approch to control authpanel. should be done via auth.
    signup: ~> @auth.prompt {tab: \signup} .then -> update!
    login: ~> @auth.prompt {tab: \login} .then -> update!
    logout: ~> @auth.logout!then -> update!
    "toggle-ldcv": ({node}) ~>
      name = node.getAttribute \data-name
      inner = ld$.find(@ldcv[name].root!, '.inner', 0)
      Promise.resolve!
        .then ~>
          if @bd[name] => return
          core.manager.from {name: "@servebase/auth", path: "#name/index.html"}, {root: inner}
            .then (o) ~> @bd[name] = o
        .then ~> @ldcv[name].get!
    wipe: ~>
      core.captcha
        .guard cb: ->
          ld$.fetch "/api/auth/clear", {method: \POST}
        .then -> window.location.href = \/
    "mail-verify": ->
      core.loader.on!
      core.captcha
        .guard cb: (captcha) ->
          ld$.fetch \/api/auth/mail/verify, {method: \POST}, {json: {captcha}}
        .then -> debounce 1000
        .finally -> core.loader.off!
        .then -> ldnotify.send \success, \sent.
        .catch -> core.ldcvmgr.toggle \error

    reauth: ~> @auth.logout!then ~> update! .then ~> @auth.prompt true, {tab: \login} .then -> update!
    notify: ~> ldnotify.send <[success warning danger dark light]>[Math.floor(Math.random! * 5)], "some test text"
    "password-reset": ~>
      if !(email = @view.panel.get('password-reset-email').value) => return
      ldld.on!
      Promise.resolve!
        .then ~>
          @captcha.guard cb: (captcha) ~>
            ld$.fetch "/api/auth/passwd/reset", {method: \POST}, {json: {email, captcha}}
        .finally -> ldld.off!
        .catch ->
          console.log it
          return lderror.reject it
    "post-test": ->
      ld$.fetch "/api/demo/post-test/", {method: \POST}, {type: \text}
        .then -> console.log it
    "hcaptcha-done": ~>
      console.log "done..."
      #@capobj.get!then -> console.log ">", it
    captcha: ({node}) ~>
      type = node.getAttribute(\data-type)
      console.log "test captcha.guard /api/demo/post ..."
      @auth.get!
        .then (g) ~> @captcha.init g.captcha
        .then ~>
          @captcha.guard do
            cb: (data) ->
              console.log "from captcha we got token obj: ", data
              # if we just somehow test captcha.guard:
              # lderror.reject 1010
              ld$.fetch "/api/demo/post", {method: \POST}, {json: captcha: data}
                .then ->
                  console.log "api response: ", it
                  console.log "accessing /api/demo/post successfully"
                  # if we want to test all captcha verifier...
                  if type == \all =>
                    console.log "intentionally reject to test all captcha verifier ..."
                    return lderror.reject 1010
                .catch ->
                  console.error "accessing /api/demo/post with captcha failed: ", it
                  Promise.reject it
        .catch -> alert "captcha verification failed"
  init:
    ldcv: ({node}) ~>
      name = node.getAttribute \data-name
      @ldcv[name] = new ldcover root: node, resident: true
      inner = ld$.find(node, '.inner', 0)

    discuss: ({node}) ~>
      data =
        host: avatar: -> "/assets/img/avatar/#{Math.ceil(Math.random! * 4)}.png"
        slug: \test
      @manager.from {name: \@servebase/discuss}, {root: node, data} .then ->

  text: do
    username: ~> @user.username or 'n/a'
    userid: ~> @user.key or 'n/a'
  handler: do
    signed: ({node}) ~> node.classList.toggle \d-none, !@user.username
    "not-signed": ({node}) ~> node.classList.toggle \d-none, !!@user.username
    status: ({node}) ~>
      node.innerText = if @user.username => 'Signed in' else 'Not login'
      node.classList.toggle \text-danger, !@user.username

update = ~>
  @auth.get!then (g) ~>
    @global = g
    @user = g.user
    @view.panel.render!

@auth.on \update, update

