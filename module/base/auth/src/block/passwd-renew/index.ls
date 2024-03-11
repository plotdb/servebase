module.exports =
  pkg:
    dependencies: [{name: \ldform}]
    i18n:
      en:
        title: "Update Your Password"
        desc: "You haven't updated your password for a while. We would like to ask you to perform regular password updates."
        skip: "Skip This Time"
        strength: "Password Strength"
        enter:
          old: "Enter old password"
          new: "Enter new password"
          again: "Type it again"
          weak: "password too weak"
          min: "8 characters minimal"
          mismatch: "password not matched"
          nomatch: "Password not matched."
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
        fail: "Incorrect Old Password?"
        no_reused: "recently used passwords not allowed"
        len: "Length"
        bad: "Bad"
        ok: "Okay"
        good: "Good"
      "zh-TW":
        title: "定期密碼更新"
        desc: "您已經有一段時間未更新密碼了，我們要請您進行定期的密碼更新。"
        skip: "這次先略過"
        strength: "密碼強度"
        enter:
          old: "輸入舊的密碼"
          new: "輸入新的密碼"
          again: "再輸入一次"
          min: "至少八個字元"
          weak: "密碼太弱了"
          mismatch: "兩組密碼不相符"
          nomatch: "密碼不符"
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
        fail: "舊的密碼有誤"
        no_reused: "不能使用近期用過的密碼"
        len: "長度"
        bad: "不妙"
        ok: "還好"
        good: "不錯"
  interface: -> @ldcv
  init: ({root, ctx, t}) ->
    ({core}) <~ servebase.corectx _
    <~ core.init!then _
    {auth, loader, ldcvmgr, captcha, error} = core
    {ldform} = ctx
    @ldcv = new ldcover root: root, zmgr: core.zmgr
    view = new ldview do
      root: root
      init: submit: ({node, local}) -> local.ldld = new ldloader root: node
      action: click:
        submit: ({local, node}) ~>
          if node.classList.contains(\disabled) => return
          <~ form.check-all!then _
          if !form.ready! => return
          ldld = local.ldld
          ldld.on!
          val = form.values!
          captcha
            .guard cb: (captcha) ->
              json = {o: val.oldpasswd, n: val.newpasswd1, captcha, renew: true}
              ld$.fetch \/api/auth/passwd/, {
                method: \put
                headers: { 'Content-Type': 'application/json; charset=UTF-8' }
              }, {json}
            .finally -> ldld.off!
            .then -> auth.fetch renew: true
            .then ~>
              ldnotify.send \success, t(\done)
              form.reset!
              @ldcv.set!
            .catch (e) ->
              id = lderror.id e
              ldnotify.send \danger, (
                if id == 1031 => t(\enter.weak)
                else if id == 1030 => t(\enter.nomatch)
                else if id == 1036 => t(\no_reused)
                else t(\fail)
              )

    form = new ldform do
      root: root
      names: -> <[username oldpasswd newpasswd1 newpasswd2]>
      submit: "[ld='submit']"
      after-check: (s) ->
        [p1,p2] = [@fields.newpasswd1.value, @fields.newpasswd2.value]
        s.username = 0
        if s.newpasswd1 != 1 and p1.length < 6 => s <<< newpasswd1: 2, newpasswd2: 1
        if p1 != p2 and (s.newpasswd2 != 1 or p2 and s.newpasswd1 == 0) => s.newpasswd2 = 2
        passwd = ld$.find(@root, '[data-node]', 0)
        if s.newpasswd1 != 1 =>
          len = Math.round(p1.length)
          text = if len < 8 => \bad else if len < 10 => \ok else \good
          width = 100 * ( len <? 12 ) / 12
          color = if len < 8 => \danger else if len < 10 => \warning else \success
          ld$.find(passwd, 'label', 0).textContent = t(\len) + ": " + t(text)
          bar = ld$.find(passwd, '.progress-bar', 0)
          bar.style.width = "#{width}%"
          cls = bar.getAttribute \class
          cls = cls.replace(/bg-\S+/, '').trim! + " bg-#color"
          bar.setAttribute \class, cls
