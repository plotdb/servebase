module.exports =
  pkg: i18n:
    en:
      s1:
        title: "Email Verification Required"
        subtitle: "Please verify your email before continuing"
        desc: [
          "You are about to perform actions that require email verification, because we may need to contact you for the actions in the future. So, please verify your email before continuing."
          "To send a verification email to your address, please click the 'Send Verification Mail' button below. Or, click 'Cancel' to cancel your last action."
        ]
        btn: [ "Cancel", "Send Verification Mail" ]
      s2:
        title: "Verification Mail Sent"
        subtitle: "Please check your mail inbox for verification link."
        desc: [
          "We have sent verification link to your email address, please check your mail inbox and click the verification link in the mail."
          "Instead of going to inbox directly, sometimes mails may be sent into different folder. If you don't see the mail, please also check different folders such as Spam folder."
          "Once you have verified your email, please click the 'OK, Verified' button. To send the verification link again, click 'Re-send.'"
        ]
        btn: ["Cancel", "Re-send", "OK, Verified"]
      s3:
        title: "Not Yet Verified"
        desc: [
          "Based on our record, your email address is not yet verified. Please follow the link in the verification mail you sent you to complete email verification, then click 'OK, Verified'."
        ]
      s4:
        title: "Mail Verified"
        desc: [
          "Your email address is verified. Please click `Continue` to continue your last action."
          "You can check the verification status of your email address at the personal settings page."
        ]
        btn: "Continue"
    "zh-TW":
      s1:
        title: "需要電子郵件驗證"
        subtitle: "在繼續之前請驗證您的電子郵件"
        desc: [
          "您即將進行需要電子郵件驗證的操作，因為我們未來可能需要就這些操作聯繫您。因此在繼續前，請驗證您的電子郵件。"
          "要向您的電子郵件地址發送驗證郵件，請點擊下方的「發送驗證郵件」按鈕，否則請點擊「取消」以取消操作。"
        ]
        btn: [ "取消", "發送驗證郵件" ]
      s2:
        title: "驗證郵件已發送"
        subtitle: "請檢查您的郵件收件箱以獲得驗證連結。"
        desc: [
          "我們已將驗證連結發送至您的電子郵件地址，請檢查您的郵件收件箱並點擊郵件中的驗證連結。"
          "有時郵件會被分到不同的信件匣，而非進入收件匣。若您沒有看到郵件，也請檢查包括垃圾郵件夾在內的其他資料夾。"
          "一旦您驗證了您的電子郵件，請點擊「好的，已驗證」按鈕，或點擊「重新發送」以再次發送驗證連結。"
        ]
        btn: ["取消", "重新發送", "好的，已驗證"]
      s3:
        title: "尚未完成驗證"
        desc: [
          "依照我們所存的紀錄所示，您的電子郵件尚未完成驗證。請點擊我們透過電子郵件寄送給您的郵件驗證連結，然後再點擊下列「好的，已驗證」按鈕。"
        ]
      s4:
        title: "電子郵件地址已驗證"
        desc: [
          "我們已確認您的電子郵件地址。請點擊「繼續」按鈕以接續您先前的動作。"
          "您隨時可以至個人設定頁面確認您電子郵件的驗證狀態。"
        ]
        btn: "繼續"

  interface: -> @ldcv
  init: ({root}) ->
    ({core}) <~ servebase.corectx _
    loader = core.loader
    obj = step: 1
    @ldcv = new ldcover root: root, zmgr: core.zmgr
    @ldcv.on \toggle.on, (~> obj.step = 1; @view.render!)
    verified = ~> obj.step = 4; @view.render!
    @view = new ldview do
      root: root
      handler: step: ({node}) -> node.classList.toggle \d-none, obj.step != +node.getAttribute(\data-step)
      action: click:
        cancel: ~>
          # NOTE we don't use @ldcv.cancel since ldcvmgr intercepts all errors.
          @ldcv.set \cancel
        done: ~>
          if (core.user.verified or {}).date => return @ldcv.set \done
          obj.step = 2
          @view.render!
        verify: ~>
          loader.on!
          debounce 1000
            .then -> core.auth.fetch {renew: true}
            .then (g) ~>
              loader.off!
              if ((g.user or {}).verified or {}).date => return verified!
              obj.step = 3
              @view.render!
            .finally ~> loader.off!
        send: ~> 
          loader.on!
          core.captcha
            .guard cb: (captcha) ->
              ld$.fetch \/api/auth/mail/verify, {method: \POST}, {type: \json, json: {captcha}}
            .then (ret = {}) ~>
              if ret.result == \verified =>
                loader.off!
                return verified!
              <~ debounce 1000 .then _
              obj.step = 2
              @view.render!
            .finally ~> loader.off!
