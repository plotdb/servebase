module.exports =
  pkg:
    dependencies: [{name: \ldform}]
    i18n:
      en:
        title: "Reset Your Password"
        desc: "Please be sure to choose a strong enough one."
        enter:
          new: "Enter new password"
          again: "Type it again"
          weak: "password too weak"
          min: "8 characters minimal"
          mismatch: "password not matched"
        setup: "Set Password"
        hint: [
          "Good password should be long enough ( at least 10 chars ). Prevent using your name, phone number or your birthday as password."
          [
            "You can check how"
            "Password Strength"
            "is measured to know how safe your password is."
          ]
        ]
        done: "Password Updated"
        note: [
          "Your password has been updated. Please remember it and keep it properly somewhere, and try logging in again."
          "If you still can't make it work after trying again, you can"
          [
            "It's probably the the link you used expired. You can still go back to"
            "and send the password reset link again."
          ]
          "If this keeps on happening, you can"
        ]
        letushelp: "and let us help you."
        contact: "contact us directly"
        "login now": "Login Now"
        "homepage": "Home Page"
        invalid:
          title: "Invalid Reset Code"
          desc: "The reset link you use is invalid."
        "reset page": "password reset page"
        "send again": "Send it Again"
      "zh-TW":
        title: "重設您的密碼"
        desc: "請務必選一個夠強的密碼。"
        enter:
          new: "輸入新的密碼"
          again: "再輸入一次"
          min: "至少八個字元"
          weak: "密碼太弱了"
          mismatch: "兩組密碼不相符"
        setup: "設定密碼"
        hint: [
          "好的密碼至少要夠長 ( 至少十個字 )。請不要用姓名、電話或生日當您的密碼。"
          [
            "你可以查閱"
            "Password Strength"
            "這篇文章來了解怎樣算是一個好密碼。"
          ]
        ]
        done: "密碼重設完成"
        note: [
          "您的密碼已經重新設定為新的密碼了，請記住您現在的密碼並妥善保存，並嘗試再次登入。"
          "若您持續無法成功重設您的密碼，您可以"
          [
            "你所使用的這個密碼重設連結應該是過期了。沒關係，您可以回到"
            "再次發送重設密碼信給自己。"
          ]
          "如果這個問題一直發生，您也可以"
        ]
        letushelp: "，由我們為您重新設定。"
        contact: "直接聯絡我們"
        "login now": "現在就登入"
        "homepage": "回首頁"
        invalid:
          title: "無效的重設碼"
          desc: "您所使用的密碼重設連結無效。"
        "reset page": "密碼重設頁"
        "send again": "再寄一次"
  init: ({ctx}) ->
    ({core}) <~ servebase.corectx _
    <~ core.init!then _
    {auth, loader, ldcvmgr, captcha, error} = core
    {ldform} = ctx
    if !document.querySelector(\#password-reset) => return
    view = new ldview do
      root: document.body
      action: click: submit: ~>
        if !pw-reset.ready! => return
        loader.on!
        captcha
          .guard cb: (captcha) ~>
            payload = {}
            payload = pw-reset.values!
            payload <<< {captcha}
            ld$.fetch "/api/auth/passwd/reset/#{@token}", {method: \POST}, {json: payload}
          .finally -> loader.off!
          .then -> ldcvmgr.get \done
          .then (v) ->
            if v != \login => return
            auth.ensure {lock: true} .then -> window.location.href = "/"
          .catch (e) ->
            # 403: 連結無效或過期 ( 送出時多給的時間也過了 ), 請用戶再寄一次
            if lderror.id(e) == 403 => return ldcvmgr.get \invalid
            console.log e
            error e

    pw-reset = new ldform do
      names: -> <[password confirm]>
      root: \#password-reset
      submit: "input[ld='submit']"
      after-check: (s, f) ->
        [p1,p2] = [@fields.password.value, @fields.confirm.value]
        if s.password != 1 and p1.length < 8 => s <<< password: 2, confirm: 1
        if p1 != p2 and (s.confirm != 1 or p2 and s.password == 0) => s.confirm = 2
    Promise.resolve!
      .then ~>
        token = (document.cookie or '').split(\;).filter(->/password-reset-token/.exec(it)).0
        @token = token = (token or '').split('=').1
        if !token => return ldcvmgr.get \invalid
        document.cookie = "password-reset-token=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;";
