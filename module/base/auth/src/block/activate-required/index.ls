# 登入 / 註冊時遇到管理員代建、還沒啟用的帳號 ( 1052 ): 提示去收啟用信, 可以重寄.
# 重寄走忘記密碼的 api, 對 pending 帳號會改寄啟用信.
module.exports =
  pkg: i18n:
    en:
      title: "Account Not Activated Yet"
      desc: [
        "This account has been created for you, but is not activated yet. Please check the inbox of"
        "and click the link in the activation mail to set your password."
      ]
      hint: "Can't find the mail? Check your spam folder, or send it again. Only the link in the latest mail works."
      close: "Close"
      resend: "Send Again"
      sent: "Activation mail sent"
    "zh-TW":
      title: "帳號尚未啟用"
      desc: [
        "已經有人為您建立了這個帳號，但帳號還沒有啟用。請到"
        "的信箱，點擊啟用信中的連結來設定密碼。"
      ]
      hint: "找不到信嗎？請檢查垃圾郵件匣，或是再寄一次。只有最新一封信的連結有效。"
      close: "關閉"
      resend: "重寄啟用信"
      sent: "啟用信已寄出"
  interface: -> @ldcv
  init: ({root, t}) ->
    # 不等 core.init: 要在第一次 ldcvmgr.get 帶資料進來之前就聽 `data`
    ({core}) <~ servebase.corectx _
    {captcha, error} = core
    lc = {}
    @ldcv = new ldcover root: root, zmgr: core.zmgr
    @ldcv.on \data, ({username} = {}) ->
      lc.username = username
      view.render!
    view = new ldview do
      root: root
      init: resend: ({node, local}) -> local.ldld = new ldloader root: node
      text: email: -> lc.username or ''
      action: click: resend: ({local}) ->
        if !lc.username or lc.busy => return
        lc.busy = true
        local.ldld.on!
        captcha
          .guard cb: (captcha) ->
            ld$.fetch \/api/auth/passwd/reset, {method: \POST}, {json: {email: lc.username, captcha}}
          .finally -> local.ldld.off!; lc.busy = false
          .then -> ldnotify.send \success, t(\sent)
          .catch error
