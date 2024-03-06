module.exports =
  pkg:
    i18n:
      en:
        title: "Delete Account"
        desc: [
          "This will delete your account permanently. Once deleted, all your saved data will be deleted all together and won't be able to be accessed."
          "Most important of all, this cannot be undone."
        ]
        sure: "Are you sure?"
        "placeholder": "type your email to confirm deletion",
        "mismatch": "email not matched"
        "no": "Never mind"
        "yes": "Delete!"
      "zh-TW":
        title: "刪除帳號"
        desc: [
          "這會永久的刪除你的帳號。一旦刪除，所有您儲存過的資料都將一併刪除，無法再被存取。"
          "最重要的是，這個動作無法復原。"
        ]
        sure: "您確定嗎？"
        "placeholder": "輸入您的 Email 以確認刪除"
        "mismatch": "Email 不符"
        "no": "算了"
        "yes": "刪除"
    dependencies: [{name: \ldform}, {name: \ldview}]
  init: ({root, ctx}) ->
    {ldform, ldview} = ctx
    ({core}) <- servebase.corectx _
    view = new ldview do
      root: root
      action: click: delete: ({node}) ->
        if node.classList.contains \disabled => return
        core.loader.on!
        core.captcha
          .guard cb: (captcha) ->
            payload = {captcha}
            ld$.fetch \/api/auth/user/delete, {method: \post}, {json: payload}
          .finally -> core.loader.off!
          .then -> core.ldcvmgr.lock name: \@servebase/auth, path: \account-deleted
          .then -> debounce 5000
          .then -> window.location.href = \/
    form = new ldform do
      names: -> <[username]>
      root: view.get(\form)
      submit: '.btn-danger'
      after-check: (s, f) ->
        s.username = if f.username.value == (if core.user.username => that else '') => 0 else 2
        if !f.username.value => s.username = 1
