# oauth 登入後需要 2FA 時, 後端把 oauth 視窗導到 `/auth?mfa-required`.
# 在這裡開 mfa-verify 驗第二步, 過了之後比照 oauth-done 通知開啟這個視窗的頁面.
module.exports =
  pkg:
    i18n:
      en:
        ok: "Login Successfully"
        reload: "Please close this window and reload the page."
      "zh-TW":
        ok: "已成功登入"
        reload: "請關閉此窗並重新載入網站"
  init: ({root}) ->
    ({core}) <~ servebase.corectx _
    <~ core.init!then _
    (r) <~ core.ldcvmgr.get {name: "@servebase/auth", path: "mfa-verify"}, {} .then _
    if !r or r.error => return window.location.href = "/auth/?oauth-failed#{if r => '&code=' + r.error else ''}"
    ld$.find(root, '[ld=done]', 0).classList.toggle \d-none, false
    # proxise pending to wait oauth to finish. see oauth-done
    try
      opener.oauth-login.resolve!
      window.close!
    catch e
      console.log "error when trying to resolve oauth-login"
