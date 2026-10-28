module.exports =
  pkg: i18n:
    en:
      "title": "Sign in Failed"
      "desc": "You may have already signed up with alternative methods. please try: "
      "opt1": "Try alternative login methods (email, password or use social login)"
      "opt2": "Check spelling of your email / password"
      "reset": "Reset Password"
      "contact": "You can contact us directly and let us help you."
      "pending":
        "title": "Account Not Activated Yet"
        "desc": "This account has been created for you, but is not activated yet. Please check your inbox for the activation mail, and click the link in it to set your password. After that you can log in."
        "hint": "Can't find the mail? Check your spam folder. Only the link in the latest mail works."
        "resend": "Send the activation mail again"
    "zh-TW":
      "title": "登入失敗"
      "desc": "您可能已經用其他方法登入過了。請再試試："
      "opt1": "換一個登入的方式"
      "opt2": "確認您輸入的資訊是否正確"
      "reset": "重設密碼"
      "contact": "您也可以直接與我們聯絡，讓我們協助您取回帳號。"
      "pending":
        "title": "帳號尚未啟用"
        "desc": "已經有人為您建立了這個帳號，但帳號還沒有啟用。請到您的信箱找啟用信，點擊信中的連結設定密碼後，就可以登入了。"
        "hint": "找不到信嗎？請檢查垃圾郵件匣。只有最新一封信的連結有效。"
        "resend": "重寄啟用信"
  # 失敗原因由 callback 帶在網址上 ( `/auth?oauth-failed&code=<lderror id>` )
  init: ({root}) ->
    code = +(new URLSearchParams(window.location.search).get(\code) or 0)
    reason = if code == 1052 => \pending else \default
    Array.from(root.querySelectorAll '[ld~=reason]').map (n) ->
      n.classList.toggle \d-none, n.dataset.name != reason
