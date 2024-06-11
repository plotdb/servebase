module.exports =
  pkg:
    dependencies: [ {name: "ldform"} ]
    i18n:
      "en": 
        title: "Invitation Code Required"
        desc: "Account sign-up is currently available only to users with an invitation code. If you have not obtained an invitation code, please contact the organizer."
        input: hint: "enter the invitation code here", invalid: "invalid invitation code"
        cancel: "Cancel"
        submit: "Submit"
      "zh-TW":
        title: "請輸入邀請碼"
        desc: "目前系統僅提供持有邀請碼的用戶註冊。若您尚未取得邀請碼，請聯絡主辦單位。"
        input: hint: "請在此輸入邀請碼", invalid: "無效的邀請碼"
        cancel: "取消"
        submit: "送出"

  interface: -> @ldcv
  init: ({ctx, root}) ->
    {ldform} = ctx
    ({core}) <~ servebase.corectx _
    @ldcv = new ldcover root: root, zmgr: core.zmgr
    view = new ldview do
      root: root
      action: click: submit: ({node}) ~>
        if !(token = view.get(\token).value) => return
        @ldcv.set {token}



