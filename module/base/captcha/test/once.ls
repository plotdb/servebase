# captcha.once: 驗一次, 之後 ttl 內同一個 session 直接放行.
# 不打外部服務: 把 verifier 換成假的, 直接用假的 req / session 驅動 middleware.
#
#   ./node_modules/.bin/lsc module/base/captcha/test/once.ls

require! <[path]>
captcha = require path.join(__dirname, \../dist/lib/index.js)
lderror = require \lderror

score = 1
calls = 0
captcha.verifier.recaptcha_v3 = -> calls := calls + 1; Promise.resolve {score, verified: true}

cfg = recaptcha_v3: {enabled: true, secret: \x}
failed = 0
ok = (cond, msg) ->
  console.log "  #{if cond => 'ok  ' else 'FAIL'} #msg"
  if !cond => failed := failed + 1

# 跑一次 middleware, 回傳 null ( 放行 ) 或錯誤 id
run = (mdw, req) -> new Promise (res) -> mdw req, {}, (e) -> res(if e => lderror.id(e) else null)
token = -> {body: {captcha: {token: \t, name: \recaptcha_v3}}}

main = ->
  cap = new captcha cfg
  mdw = cap.middleware.once {scope: \s, ttl: 1000}
  session = {}

  console.log "\n沒有通行證"
  (r) <- run(mdw, {session}).then _
  ok r == 1048, "沒帶 captcha 回 1048"
  ok calls == 0, "沒帶 captcha 不會去驗"

  console.log "\n帶 captcha 驗過"
  (r) <- run(mdw, {session} <<< token!).then _
  ok r == null, "放行"
  ok (session.captcha-pass and session.captcha-pass.s > Date.now!), "session 記下通行證"

  console.log "\n通行證期間內"
  calls := 0
  (r) <- run(mdw, {session}).then _
  ok r == null, "不帶 captcha 也放行"
  ok calls == 0, "不會再去驗"

  console.log "\nscope 分開"
  other = cap.middleware.once {scope: \other}
  (r) <- run(other, {session}).then _
  ok r == 1048, "別的 scope 仍要驗"

  console.log "\n通行證過期"
  session.captcha-pass.s = Date.now! - 1
  (r) <- run(mdw, {session}).then _
  ok r == 1048, "過期回 1048"

  console.log "\n分數不夠"
  score := 0.1
  s2 = {}
  (r) <- run(mdw, {session: s2} <<< token!).then _
  ok r == 1009, "回 1009"
  ok !(s2.captcha-pass and s2.captcha-pass.s), "不記通行證"
  score := 1

  console.log "\n沒有 session"
  (r) <- run(mdw, token!).then _
  ok r == null, "帶 captcha 照樣可以驗過放行 ( 每次都驗 )"
  (r) <- run(mdw, {}).then _
  ok r == 1048, "不帶就回 1048"

  console.log "\ncaptcha 沒啟用"
  disabled = new captcha({enabled: false}).middleware.once {scope: \s}
  (r) <- run(disabled, {session: {}}).then _
  ok r == null, "直接放行"

  console.log(if failed => "\n#failed 項失敗" else "\n全部通過")
  process.exit(if failed => 1 else 0)

main!
