# 啟用管理員代建的帳號: 設定密碼 ( 同時完成 email 驗證 ). token 由 GET /auth/activate/:token 放在 cookie.
module.exports =
  pkg:
    dependencies: [{name: \ldform}]
    i18n:
      en:
        title: "Activate Your Account"
        desc: "Set a password to start using your account. Please be sure to choose a strong enough one."
        enter:
          new: "Enter password"
          again: "Type it again"
          weak: "password too weak"
          min: "8 characters minimal"
          mismatch: "password not matched"
        setup: "Activate Account"
        hint: [
          "Good password should be long enough ( at least 10 chars ). Prevent using your name, phone number or your birthday as password."
          [
            "You can check how"
            "Password Strength"
            "is measured to know how safe your password is."
          ]
        ]
        done:
          title: "Account Activated"
          desc: "Your password is set and your email is verified. You can now log in with this email and password."
        invalid:
          title: "Invalid Activation Link"
          desc: "This link is invalid or expired, or the account has already been activated."
          note: [
            "To get a new activation link, enter your email in the"
            "forgot password page"
            "."
            "If your account is already activated, simply log in."
          ]
        weak: "Password too weak"
        fail: "Failed to activate. Please try again later."
        "login now": "Login Now"
        "homepage": "Home Page"
        "send again": "Send it Again"
        "login": "Login"
      "zh-TW":
        title: "啟用您的帳號"
        desc: "設定密碼後即可開始使用您的帳號。請務必選一個夠強的密碼。"
        enter:
          new: "輸入密碼"
          again: "再輸入一次"
          min: "至少八個字元"
          weak: "密碼太弱了"
          mismatch: "兩組密碼不相符"
        setup: "啟用帳號"
        hint: [
          "好的密碼至少要夠長 ( 至少十個字 )。請不要用姓名、電話或生日當您的密碼。"
          [
            "你可以查閱"
            "Password Strength"
            "這篇文章來了解怎樣算是一個好密碼。"
          ]
        ]
        done:
          title: "帳號已啟用"
          desc: "您的密碼已經設定完成，電子郵件也已完成驗證。現在可以用這個電子郵件與密碼登入了。"
        invalid:
          title: "無效的啟用連結"
          desc: "這個連結無效或已過期，或是帳號已經啟用過了。"
          note: [
            "要取得新的啟用連結，請到"
            "忘記密碼頁"
            "輸入您的電子郵件。"
            "如果帳號已經啟用過了，直接登入即可。"
          ]
        weak: "密碼太弱了"
        fail: "啟用失敗，請稍後再試。"
        "login now": "現在就登入"
        "homepage": "回首頁"
        "send again": "再寄一次"
        "login": "登入"
  init: ({ctx, t}) ->
    ({core}) <~ servebase.corectx _
    <~ core.init!then _
    {auth, loader, ldcvmgr, captcha, error} = core
    {ldform} = ctx
    if !document.querySelector(\#activate) => return
    view = new ldview do
      root: document.body
      action: click: submit: ~>
        if !form.ready! => return
        loader.on!
        captcha
          .guard cb: (captcha) ~>
            ld$.fetch "/api/auth/activate/#{@token}", {method: \POST}, {json: form.values!{password} <<< {captcha}}
          .finally -> loader.off!
          .then -> ldcvmgr.get \activate-done
          .then (v) ->
            if v != \login => return
            auth.ensure {lock: true} .then -> window.location.href = "/"
          .catch (e) ->
            id = lderror.id e
            if id == 403 => return ldcvmgr.get \activate-invalid
            if id == 1031 => return ldnotify.send \danger, t(\weak)
            error e

    form = new ldform do
      names: -> <[password confirm]>
      root: \#activate
      submit: "input[ld='submit']"
      after-check: (s, f) ->
        [p1,p2] = [@fields.password.value, @fields.confirm.value]
        if s.password != 1 and p1.length < 8 => s <<< password: 2, confirm: 1
        if p1 != p2 and (s.confirm != 1 or p2 and s.password == 0) => s.confirm = 2
    Promise.resolve!
      .then ~>
        token = (document.cookie or '').split(\;).filter(->/activate-token=/.exec(it)).0
        @token = token = (token or '').split('=').1
        if !token => return ldcvmgr.get \activate-invalid
        document.cookie = "activate-token=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;"
