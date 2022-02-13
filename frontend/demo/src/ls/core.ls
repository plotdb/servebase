ldc \core, <[]>, ->
  init: proxise.once ~>
    @ <<<
      global: {}
      user: {}
    @ <<<
      zmgr: new zmgr init: 1000
      auth: new auth!
      manager: new block.manager registry: ->
    @ <<<
      loader: new ldloader class-name: "ldld full", zmgr: @zmgr
      captcha: new captcha manager: @manager
      ldcvmgr: new ldcvmgr manager: @manager

    err = new lderror.handler handler: -> o.ldcvmgr.get it
    @error = (e) -> err e

    manager.init!
      .then ->
        # to optimize, we may delay or completely ignore i18n
        # since not every service need i18n
        i18next.init supportedLng: <[en zh-TW]>, fallbackLng: \zh-TW
      .then -> block.i18n.use i18next
      .then ~>
        # we may provide an anonymous initialization
        # to prevent fetching at loading time to speed up FCP.
        @auth.get!
      .then (g) ~>
        @global = g
        @user = g.user
        @captcha.init g.captcha
      .then ->
        # prepare authpanel. involving @plotdb/block creation.
        # should delay until we really have to trigger ui
