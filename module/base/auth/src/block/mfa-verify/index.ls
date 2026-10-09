# 登入第二步: 輸入 2FA 驗證碼 ( 或復原碼 ).
# 用 `ldcvmgr.get({name: '@servebase/auth', path: 'mfa-verify'}, {methods})` 開啟, resolve 的值:
#  - 驗過: 後端 /mfa/verify 的回應, 即登入的 payload ( password-should-renew 等 ).
#  - 取消: null.
#  - 無法再試 ( 逾時 1013 / 次數用完 1049 ): `{error: <lderror id>}`, 要從帳密重新登入.
#    原因已經在這裡告訴使用者了, 呼叫端只要回到登入畫面.
module.exports =
  pkg:
    i18n:
      en:
        title: "Two-Factor Authentication"
        totp:
          desc: "Enter the 6-digit code from your authenticator app."
          use: "Use your authenticator app"
        recovery:
          desc: "Enter one of your recovery codes. Each code can be used only once."
          use: "Use a recovery code"
          low: "You have {{count}} recovery codes left. Consider generating new ones in your account settings."
        invalid: "Incorrect code"
        consumed: "This code was just used. Please wait for the next code in your app."
        expire: "Verification timed out. Please login again."
        "too-many": "Too many attempts. Please wait a while and login again."
        fail: "Verification failed. Please login again."
        cancel: "Cancel"
        submit: "Verify"
      "zh-TW":
        title: "兩步驟驗證"
        totp:
          desc: "請輸入驗證器 App 上顯示的 6 位數驗證碼。"
          use: "改用驗證器 App"
        recovery:
          desc: "請輸入一組復原碼。每組復原碼只能使用一次。"
          use: "改用復原碼"
          low: "您只剩 {{count}} 組復原碼，建議到帳號設定重新產生。"
        invalid: "驗證碼不正確"
        consumed: "這組驗證碼剛剛用過了，請等 App 顯示下一組再輸入。"
        expire: "驗證逾時，請重新登入。"
        "too-many": "嘗試次數過多，請稍候再重新登入。"
        fail: "驗證失敗，請重新登入。"
        cancel: "取消"
        submit: "驗證"
  interface: -> @ldcv
  init: ({root, t}) ->
    ({core}) <~ servebase.corectx _
    @ldcv = new ldcover root: root, zmgr: core.zmgr, lock: true
    lc = {mode: \totp, invalid: false, busy: false}
    @ldcv.on \data, ({methods} = {}) ->
      lc <<< mode: ((methods or []).0 or \totp), invalid: false
      view.get(\code).value = ''
      view.render!
    @ldcv.on \toggle.on, -> setTimeout (-> view.get(\code).focus!), 100
    submit = ~>
      code = view.get(\code).value.trim!
      if !code or lc.busy => return
      lc.busy = true
      lc.ldld.on!
      ld$.fetch "#{core.auth.api-root!}mfa/verify", {method: \POST}, {
        json: {method: lc.mode, code}, type: \json
      }
        .finally -> lc.busy = false; lc.ldld.off!
        .then (ret = {}) ~>
          if ret.recovery and ret.recovery.remain <= 3 =>
            ldnotify.send \warning, t(\recovery.low, {count: ret.recovery.remain})
          @ldcv.set ret
        .catch (e) ~>
          if (id = lderror.id e) in [1045 1050] =>
            lc.invalid = if id == 1050 => \consumed else \invalid
            view.get(\code).value = ''
            return view.render <[code feedback]>
          ldnotify.send \danger, t(if id == 1013 => \expire else if id == 1049 => \too-many else \fail)
          @ldcv.set {error: id or 500}
    view = new ldview do
      root: root
      init: submit: ({node}) -> lc.ldld = new ldloader root: node
      action:
        input: code: -> if lc.invalid => lc.invalid = false; view.render <[code feedback]>
        keyup: code: ({evt}) -> if evt.keyCode == 13 => submit!
        click:
          submit: -> submit!
          cancel: ~> @ldcv.set null
          switch: ({node}) ->
            lc <<< mode: node.dataset.mode, invalid: false
            view.get(\code).value = ''
            view.render!
            view.get(\code).focus!
      handler:
        mode: ({node}) -> node.classList.toggle \d-none, node.dataset.mode != lc.mode
        switch: ({node}) -> node.classList.toggle \d-none, node.dataset.mode == lc.mode
        feedback: ({node}) -> node.textContent = if lc.invalid => t(lc.invalid) else ''
        code: ({node}) ->
          node.classList.toggle \is-invalid, !!lc.invalid
          node.setAttribute \inputmode, (if lc.mode == \totp => \numeric else \text)
          node.setAttribute \placeholder, (if lc.mode == \totp => '000000' else 'xxxxx-xxxxx')
