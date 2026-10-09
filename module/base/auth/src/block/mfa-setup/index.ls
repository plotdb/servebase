# 帳號設定裡的 2FA 區塊: 啟用 ( 掃 QR code、輸入驗證碼 ) / 顯示復原碼 / 重新產生復原碼 / 停用.
# 伺服器沒開 2FA ( config.auth.mfa.enabled ) 或是匿名帳戶時整個區塊隱藏 ( 後端 GET /mfa 回 enabled: false ).
module.exports =
  pkg:
    i18n:
      en:
        title: "Two-Factor Authentication"
        off:
          desc: "Protect your account with an authenticator app ( e.g., Google Authenticator ). After enabling, you'll need a code from the app in addition to your password when logging in."
          enable: "Enable Two-Factor Authentication"
        setup:
          step1: "1. Scan this QR code with your authenticator app."
          manual: "Can't scan? Enter this key manually:"
          step2: "2. Enter the 6-digit code shown in the app to finish."
          code: "Verification Code"
          password: "Current Password"
          enable: "Enable"
        codes:
          desc: "Save these recovery codes somewhere safe. If you lose your phone, each code lets you log in once. They will not be shown again."
          copy: "Copy"
          download: "Download"
          done: "I've saved them"
          copied: "Copied"
        on:
          desc: "Two-factor authentication is enabled."
          remain: "Recovery codes left: {{count}}"
          code: "Enter a code from your app ( or a recovery code ) to make changes"
          regen: "Generate New Recovery Codes"
          disable: "Disable Two-Factor Authentication"
          disabled: "Two-factor authentication disabled"
        invalid: "Incorrect code"
        consumed: "This code was just used. Please wait for the next code in your app."
        nomatch: "Password not matched."
        expire: "This setup has expired. please start again."
        "too-many": "Too many attempts. Please try again later."
        cancel: "Cancel"
        fail: "Operation failed. Please try again later."
      "zh-TW":
        title: "兩步驟驗證"
        off:
          desc: "使用驗證器 App ( 如 Google Authenticator ) 保護您的帳號。啟用後，登入時除了密碼，還需要輸入 App 上的驗證碼。"
          enable: "啟用兩步驟驗證"
        setup:
          step1: "1. 用驗證器 App 掃描這個 QR code。"
          manual: "無法掃描的話，請手動輸入這組金鑰："
          step2: "2. 輸入 App 上顯示的 6 位數驗證碼以完成設定。"
          code: "驗證碼"
          password: "目前的密碼"
          enable: "啟用"
        codes:
          desc: "請將這些復原碼存放在安全的地方。手機遺失時，每組復原碼可以用來登入一次。這些復原碼之後不會再顯示。"
          copy: "複製"
          download: "下載"
          done: "我已經存好了"
          copied: "已複製"
        on:
          desc: "已啟用兩步驟驗證。"
          remain: "剩餘復原碼：{{count}} 組"
          code: "輸入 App 上的驗證碼 ( 或復原碼 ) 以進行變更"
          regen: "重新產生復原碼"
          disable: "停用兩步驟驗證"
          disabled: "已停用兩步驟驗證"
        invalid: "驗證碼不正確"
        consumed: "這組驗證碼剛剛用過了，請等 App 顯示下一組再輸入。"
        nomatch: "密碼不符"
        expire: "設定已逾時，請重新開始。"
        "too-many": "嘗試次數過多，請稍後再試。"
        cancel: "取消"
        fail: "操作失敗，請稍後再試。"
  init: ({root, t}) ->
    ({core}) <~ servebase.corectx _
    <~ core.init!then _
    {auth} = core
    (g) <~ auth.ensure!then _
    api = auth.api-root!
    lc = {state: null, remain: 0, setup: {}, codes: [], invalid: {}}
    root.classList.toggle \d-none, true
    if !(g.{}policy.{}mfa.enabled) => return

    fetch = ->
      ld$.fetch "#{api}mfa", {method: \GET}, {type: \json}
        .then (r = {}) ->
          if !r.enabled => return
          lc <<< state: (if r.methods.length => \on else \off), remain: r.recovery.remain, password: r.password
          root.classList.toggle \d-none, false
          view.render!
    post = (path, json) -> ld$.fetch "#{api}#path", {method: \POST}, {json, type: \json}
    fail = (e) ->
      id = lderror.id e
      ldnotify.send \danger, t(if id == 1013 => \expire else if id == 1049 => \too-many else \fail)
      if id == 1013 => lc.state = \off; view.render!
    # `v`: 提示文字的 i18n key, false 清掉
    invalid = (n, v = \invalid) -> lc.invalid[n] = v; view.render n; view.render \verify-feedback
    # 停用 / 重新產生的驗證碼錯誤: 1045 碼不對, 1050 碼剛用過 ( 等下一組 )
    code-error = (e) ->
      id = lderror.id e
      if id in [1045 1050] => invalid \verify-code, (if id == 1050 => \consumed else \invalid)
      else fail e
    # 6 位數字是 app 上的驗證碼, 其餘當復原碼
    with-code = (code) ->
      code = "#{code or ''}".replace /\s/g, ''
      {method: (if /^\d{6}$/.test(code) => \totp else \recovery), code}
    show-codes = (codes) ->
      lc <<< codes: codes, state: \codes
      view.render!

    busy = ({node, local}, cb) ->
      if local.busy => return
      local.busy = true
      local.ldld.on!
      cb!finally -> local.busy = false; local.ldld.off!

    view = new ldview do
      root: root
      init:
        setup: ({node, local}) -> local.ldld = new ldloader root: node
        enable: ({node, local}) -> local.ldld = new ldloader root: node
        regen: ({node, local}) -> local.ldld = new ldloader root: node
        disable: ({node, local}) -> local.ldld = new ldloader root: node
      action:
        input:
          code: -> invalid \code, false
          password: -> invalid \password, false
          "verify-code": -> invalid \verify-code, false
        click:
          setup: (o) ->
            busy o, ->
              post \mfa/totp/setup, {}
                .then (r = {}) ->
                  lc <<< setup: r, state: \setup
                  view.get(\code).value = ''
                  view.get(\password).value = ''
                  view.render!
                .catch fail
          cancel: -> lc.state = \off; view.render!
          enable: (o) ->
            busy o, ->
              json = {code: view.get(\code).value.trim!, password: view.get(\password).value}
              post \mfa/totp/enable, json
                .then (r = {}) ->
                  lc.remain = r.recovery.length
                  show-codes r.recovery
                .catch (e) ->
                  id = lderror.id e
                  if id == 1045 => return invalid \code
                  if id == 1030 => return invalid \password
                  fail e
          copy: ->
            navigator.clipboard.writeText lc.codes.join('\n')
              .then -> ldnotify.send \success, t(\codes.copied)
          download: ->
            href = URL.createObjectURL new Blob([lc.codes.join('\n') + '\n'], {type: 'text/plain'})
            a = document.createElement \a
            a <<< {href, download: "recovery-codes-#{window.location.hostname}.txt"}
            document.body.appendChild a
            a.click!
            document.body.removeChild a
            URL.revokeObjectURL href
          done: -> lc <<< codes: [], state: \on; view.render!
          regen: (o) ->
            busy o, ->
              post \mfa/recovery, with-code(view.get(\verify-code).value)
                .then (r = {}) ->
                  view.get(\verify-code).value = ''
                  lc.remain = r.recovery.length
                  show-codes r.recovery
                .catch code-error
          disable: (o) ->
            busy o, ->
              post \mfa/totp/disable, with-code(view.get(\verify-code).value)
                .then ->
                  view.get(\verify-code).value = ''
                  ldnotify.send \success, t(\on.disabled)
                  fetch!
                .catch code-error
      handler:
        state: ({node}) -> node.classList.toggle \d-none, node.dataset.state != lc.state
        qr: ({node}) -> node.innerHTML = lc.setup.qr or ''
        secret: ({node}) -> node.textContent = (lc.setup.secret or '').replace /(.{4})/g, '$1 '
        "need-password": ({node}) -> node.classList.toggle \d-none, !lc.password
        codes: ({node}) -> node.textContent = lc.codes.join('\n')
        remain: ({node}) -> node.textContent = t(\on.remain, {count: lc.remain})
        code: ({node}) -> node.classList.toggle \is-invalid, !!lc.invalid.code
        password: ({node}) -> node.classList.toggle \is-invalid, !!lc.invalid.password
        "verify-code": ({node}) -> node.classList.toggle \is-invalid, !!lc.invalid["verify-code"]
        "verify-feedback": ({node}) -> node.textContent = if lc.invalid["verify-code"] => t(that) else ''
    fetch!
