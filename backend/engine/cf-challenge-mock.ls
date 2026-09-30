# 本機模擬 cloudflare challenge, 用來測前端的 turnstile pre-clearance 流程
# ( @servebase/captcha src/challenge.ls ). 只在非 production 且有設定時才掛上.
#
#   dev: cf-challenge-mock: {paths: <[/api/auth/info /ws]>, ttl: 60}
#
#  - 符合 `paths` ( 前綴比對 ) 的請求, 沒有模擬的 clearance cookie 就回 403 +
#    `cf-mitigated: challenge` + 仿 challenge 頁的 html, 跟 cloudflare 對 fetch 的反應一樣.
#  - `POST /__cf-mock/clear`: 前端 turnstile 通過後打這裡 ( corecfg challenge.clear ),
#    種 clearance cookie, `ttl` 秒後失效. 正式環境是 cloudflare 自己種 `cf_clearance`.
#  - 只管 http. websocket 的 upgrade 不經過 express, 不過 connector 是用 http GET 探路,
#    所以探路那一步還是會被擋到.
module.exports = (backend) ->
  cfg = backend.config.{}dev.cf-challenge-mock
  if backend.production or !cfg => return
  paths = cfg.paths or <[/api/auth/info /ws]>
  ttl = (cfg.ttl or 60) * 1000
  name = \__cf_mock_clearance
  backend.log-server.warn "[cf-challenge-mock] enabled for #{paths.join(', ')} ( ttl #{ttl / 1000}s )".yellow
  backend.app.use (req, res, next) ->
    if req.path == \/__cf-mock/clear and req.method == \POST =>
      res.cookie name, \1, {path: \/, max-age: ttl, http-only: true, secure: true, same-site: \lax}
      return res.send {}
    if !paths.some((p) -> req.path.startsWith p) => return next!
    if req.cookies and req.cookies[name] => return next!
    res.status 403
    res.set \cf-mitigated, \challenge
    res.set \content-type, 'text/html; charset=UTF-8'
    res.send '<!DOCTYPE html><html><head><title>Just a moment...</title></head><body>' +
      '<script>window._cf_chl_opt={cType:"managed"};</script>' +
      '<script src="/cdn-cgi/challenge-platform/h/b/orchestrate/chl_page/v1"></script></body></html>'
