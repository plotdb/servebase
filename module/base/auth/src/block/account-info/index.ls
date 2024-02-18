module.exports = 
  pkg:
    i18n:
      en:
        title: "Basic Information"
        displayname: "Display Name"
        public: "How we refer to you"
        required: "Required"
        userid: "User ID"
        iddesc: "Your unique ID"
        copied: "Copied"
        verified: "Verified"
        unverified: "Not verified"
        username: "Account Name"
        email: "Your Email Address"
        verify: "Email Verification"
        send: "Send Verification Mail"
        update: "Update Basic Info"
        updated: "Updated"
        'verified at': "verified at: "
      "zh-TW":
        title: "基本資訊"
        displayname: "顯示名稱"
        public: "供他人識別的顯示名稱"
        required: "必要欄位"
        userid: "用戶代碼"
        iddesc: "您專用的用戶代碼"
        copied: "已複製"
        verified: "已認證"
        unverified: "未認證"
        username: "帳號名稱"
        email: "你的電子郵件地址"
        verify: "電子郵箱認證"
        send: "寄發認證信"
        update: "更新基本資訊"
        updated: "更新完成"
        'verified at': "已驗證，時間："
    dependencies: [
      {name: "ldform"}
      {name: "ldview"}
    ]
  init: ({root, ctx, t}) ->
    ({core}) <~ servebase.corectx _
    {auth, ldcvmgr, captcha} = core
    {ldform, ldview} = ctx
    (g) <- auth.ensure!then _
    form = new ldform do
      root: root
      submit: '.btn[ld=updateBasicData]'
      after-check: (s) ->
        s.title = 0
        s.tags = 0
        if @fields.displayname.value => s.displayname = 0
      verify: (n,v,e) ->
        if n == \description => return if !(v and v.length >= 1024) => 0 else 2
        if n == \displayname => return if v => 0 else 2 
    form.values { displayname: core.user.displayname }
    view = new ldview do
      root: root
      init:
        "update-basic-data": ({node, local}) -> local.ldld = new ldloader root: node
        "mail-verify": ({node, local}) -> local.ldld = new ldloader root: node
      action:
        change: "avatar": ({node}) -> return
        click:
          copyuid: ({node}) ->
            navigator.clipboard.writeText view.get(\uid).value
            node.classList.add \tip-on
            debounce 2000 .then -> node.classList.remove \tip-on
          "update-basic-data": ({node, local}) ->
            local.ldld.on!
            val = form.values!
            captcha
              .guard cb: (captcha) ->
                json = {captcha} <<< val{description,displayname,title,tags}
                ld$.fetch "/api/auth/user/" {method: \PUT}, {json, type: \text}
              .finally -> debounce 1000 .then -> local.ldld.off!
              .then -> ldnotify.send \success, t(\updated)
              .then -> auth.fetch {renew: true}
          "mail-verify": ({node, local}) ->
            if node.classList.contains \disabled => return
            local.ldld.on!
            captcha
              .guard cb: (captcha) ->
                ld$.fetch \/api/auth/mail/verify, {method: \POST}, {json: {captcha}, type: \json}
              .finally -> debounce 1000 .then -> local.ldld.off!
              .then (ret = {}) ->
                if ret.result != \sent => return
                ldcvmgr.toggle {name: "@servebase/auth", path: "verification-mail-sent"}
      handler:
        "mail-verify": ({node}) ->
          if !core.user.verified => return
          d = new Date(core.user.verified.date)
          if isNaN(d.getTime!) => return node.innerText = t('verified')
          d = [
            ("#{d.getYear! + 1900}").padStart(4,'0')
            ("#{d.getMonth! + 1}").padStart(2,'0')
            ("#{d.getDate!}").padStart(2,'0')
          ].join(\-)
          node.innerText = t('verified at') + d
        "is-staff": ({node}) -> node.classList.toggle \d-none, !(core.user.staff)
        "is-verified": ({node}) -> node.classList.toggle \d-none, !(core.user.verified)
        "not-verified": ({node}) -> node.classList.toggle \d-none, !!(core.user.verified)
        uid: ({node}) -> node.value = core.user.key
        username: ({node}) -> node.value = core.user.username
