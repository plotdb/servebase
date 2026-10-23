# ipguard: 依 client ip 限制存取.
#
# config ( 沒設定的 policy 一律放行, 所以不設就和沒有這個功能一樣 ):
#
#     policy:
#       ip:
#         admin: allow: <[203.0.113.0/24 2001:db8::/32 198.51.100.7]>
#         # deny: <[...]>   # 先看 deny, 再看 allow; 有 allow 時不在清單內的都擋
#
# 用法:
#
#     route.use backend.ipguard.middleware \admin           # 依路徑擋
#     backend.ipguard.check {policy: \admin}                # 在權限判斷裡擋, 被擋時 reject lderror 1051
#     backend.ipguard.allowed {policy: \admin} .then (ok) -> # 只想知道結果, 不 reject
#
# `check` / `allowed` 沒給 `ip` 時, 取目前 request 的 ip ( 見 `context` 與 engine 裡掛的 middleware ).
# 取不到 ip 一律視為不通過 - 有設 policy 就是要擋, 不能因為 context 斷掉而放行.
#
# 只用 `aux.client-ip`, 不看可偽造的 header. 在 Cloudflare 後面, 要先設好 nginx realip,
# 否則拿到的都是 CF 節點的 ip, 有設 policy 的地方會全部被擋.
#
# 之後要加 org / brd / user 層級的規則: `check` 已收 `user` 與 `scope`, 規則一律疊加 ( AND ) -
# 下層只能比 global 更嚴, 不能放寬.

require! <[lderror async_hooks]>
require! <[./aux]>
ipaddr = require \ipaddr.js

# 目前 request 的 context, 讓拿不到 req 的地方 ( 例如權限判斷 ) 也能取得 ip.
# 由 engine 在 session 之後掛 `context.middleware`; 掛之前的 middleware 讀不到.
store = new async_hooks.AsyncLocalStorage!
context =
  middleware: (req, res, next) -> store.run {req}, next
  req: -> store.getStore!?req

# "1.2.3.4" / "1.2.3.0/24" / "2001:db8::/32" -> [addr, bits]
parse-range = (str) ->
  str = "#str".trim!
  return if /\//.exec(str) => ipaddr.parseCIDR str
  else
    addr = ipaddr.process str
    [addr, if addr.kind! == \ipv4 => 32 else 128]

compile = (name, policy = {}) ->
  ret = {}
  for k in <[allow deny]> =>
    if !(list = policy[k])? => continue
    if !Array.isArray(list) => throw new Error("ipguard: policy `#name`.#k should be an array")
    ret[k] = list.map (str) ->
      try parse-range str
      catch e => throw new Error("ipguard: policy `#name`.#k has an invalid ip / cidr `#str`")
  ret

in-list = (addr, list = []) ->
  list.some ([range, bits]) -> range.kind! == addr.kind! and addr.match(range, bits)

ipguard = (backend) ->
  cfg = ((backend.config.policy or {}).ip) or {}
  # 設定寫錯時直接讓啟動失敗, 不要默默放行
  policies = {[name, compile(name, policy)] for name, policy of cfg}
  log = backend.log.child {module: \ipguard}
  if (names = [k for k of policies]).length =>
    log.info "ip policies: #{names.join(', ')}"

  allowed = ({ip, policy, user, scope} = {}) ->
    if !(rule = policies[policy]) => return Promise.resolve true
    if !ip and (req = context.req!) => ip = aux.client-ip req
    addr = try ipaddr.process ip catch e => null
    if !addr => return Promise.resolve false
    if rule.deny and in-list(addr, rule.deny) => return Promise.resolve false
    if rule.allow and !in-list(addr, rule.allow) => return Promise.resolve false
    return Promise.resolve true

  check = (opt = {}) ->
    allowed opt .then (ok) ->
      if ok => return
      req = context.req!
      ip = opt.ip or (if req => aux.client-ip req else null)
      user = opt.user or (req and req.user)
      user = if user and typeof(user) == \object => user.key else user
      log.warn {
        policy: opt.policy, ip, user: user or 0, scope: opt.scope, url: req?originalUrl
      }, "ip not allowed"
      lderror.reject 1051

  middleware = (policy) -> (req, res, next) ->
    store.run {req}, ->
      check {policy, ip: aux.client-ip(req), user: req.user}
        .then -> next!
        .catch next

  {allowed, check, middleware}

ipguard.context = context

module.exports = ipguard
