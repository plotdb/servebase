# aux.client-ip 與 ipguard 的規則判斷. 不起 server.
#
#   npm test -- ipguard
#   ./node_modules/.bin/lsc test/unit/ipguard.ls

require! <[path lderror]>
engine = path.join __dirname, \../../backend/engine
aux = require path.join(engine, \aux)
ipguard = require path.join(engine, \ipguard)

failed = 0
ok = (cond, msg) ->
  console.log "  #{if cond => 'ok  ' else 'FAIL'} #msg"
  if !cond => failed := failed + 1
throws = (f) -> try (f!; false) catch e => true

fake-req = (remote, headers = {}) ->
  socket = remoteAddress: remote
  {headers, socket, connection: socket}
fake-backend = (policy) ->
  warned = []
  config: {policy: {ip: policy}}
  log: child: -> {info: (->), warn: (o) -> warned.push o}
  warned: warned

console.log "\naux.client-ip"
ok aux.client-ip(fake-req \203.0.113.5) == \203.0.113.5, "直連: socket ip"
ok aux.client-ip(fake-req \203.0.113.5, {'cf-connecting-ip': \1.2.3.4, 'x-real-ip': \1.2.3.4}) == \203.0.113.5,
  "直連時不信 cf-connecting-ip / x-real-ip"
ok aux.client-ip(fake-req \203.0.113.5, {'x-forwarded-for': \1.2.3.4}) == \203.0.113.5,
  "直連時不信 x-forwarded-for"
ok aux.client-ip(fake-req \127.0.0.1, {'x-forwarded-for': '1.2.3.4, 198.51.100.9'}) == \198.51.100.9,
  "經本機 proxy: 取 x-forwarded-for 最後一個 ( proxy 加上的 )"
ok aux.client-ip(fake-req \::ffff:203.0.113.5) == \203.0.113.5, "IPv4-mapped IPv6 轉回 IPv4"
ok aux.client-ip(fake-req \2001:0db8:0000::0001) == \2001:db8::1, "IPv6 轉成標準寫法"
req = fake-req \203.0.113.5
aux.client-ip req
req.socket.remoteAddress = \1.1.1.1
ok aux.client-ip(req) == \203.0.113.5, "算一次後存在 req.client-ip"

console.log "\npolicy 設定"
ok throws(-> ipguard fake-backend(admin: allow: <[1.2.3.400]>)), "不合法的 ip 讓啟動失敗"
ok throws(-> ipguard fake-backend(admin: allow: \1.2.3.4)), "allow 不是陣列讓啟動失敗"

g = ipguard fake-backend do
  admin: allow: <[203.0.113.0/24 198.51.100.7 2001:db8::/32]>
  nodeny: deny: <[192.0.2.0/24]>
  both: allow: <[10.0.0.0/8]>, deny: <[10.0.0.1]>

cases =
  * [\admin, \203.0.113.99, true, "allow 網段內"]
  * [\admin, \198.51.100.7, true, "allow 單一 ip"]
  * [\admin, \198.51.100.8, false, "單一 ip 不是網段"]
  * [\admin, \2001:db8::abcd, true, "IPv6 網段內"]
  * [\admin, \::ffff:203.0.113.1, true, "IPv4-mapped 視同 IPv4"]
  * [\admin, \8.8.8.8, false, "不在 allow 內"]
  * [\admin, null, false, "沒有 ip ( 也沒有 request context ) 就擋"]
  * [\admin, \unknown-ip, false, "unknown-ip 擋"]
  * [\nodeny, \8.8.8.8, true, "只有 deny: 其他放行"]
  * [\nodeny, \192.0.2.1, false, "只有 deny: 命中就擋"]
  * [\both, \10.0.0.1, false, "deny 優先於 allow"]
  * [\both, \10.0.0.2, true, "allow 內且未 deny"]
  * [\none, \8.8.8.8, true, "沒設定的 policy 放行"]

Promise.all(cases.map ([policy, ip, expect, msg]) ->
  g.allowed {policy, ip} .then (ret) -> ok ret == expect, msg
)
  .then ->
    console.log "\ncheck / middleware / context"
    g.check {policy: \admin, ip: \8.8.8.8}
      .then -> ok false, "check 被擋時 reject"
      .catch (e) -> ok lderror.id(e) == 1051, "check 被擋時 reject lderror 1051"
  .then -> g.check {policy: \admin, ip: \203.0.113.1} .then -> ok true, "check 通過時 resolve"
  .then ->
    new Promise (res) ->
      ipguard.context.middleware fake-req(\127.0.0.1, {'x-forwarded-for': \203.0.113.1}), {}, ->
        # 模擬權限判斷: 拿不到 req, 只靠 context 取 ip
        setTimeout (-> g.allowed {policy: \admin} .then (r) -> ok r, "沒給 ip 時從 request context 取"; res!), 0
  .then ->
    new Promise (res) ->
      g.middleware(\admin) fake-req(\8.8.8.8), {}, (err) ->
        ok lderror.id(err) == 1051, "middleware 被擋時 next(1051)"
        res!
  .then ->
    new Promise (res) ->
      g.middleware(\admin) fake-req(\203.0.113.1), {}, (err) ->
        ok !err, "middleware 通過時 next()"
        res!
  .then ->
    console.log ""
    process.exit if failed => 1 else 0
