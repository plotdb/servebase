# demo: websocket / sharedb server, 給 /editing/ ( connector + sharehub ) 用.
# engine 的 `listen` 會改用這裡設的 `backend.server`.
require! <[lderror http ws @plotdb/ews @plotdb/ews/sdb-server]>
(backend) <- (->module.exports = it) _
{db, app, session} = backend

server = http.createServer app
wss = new ws.Server do
  server: server
  # dev 的 cloudflare challenge 模擬, 開了 `ws` 就也擋握手 ( 見 engine/cf-challenge-mock.ls ).
  verify-client: ({req}, cb) ->
    if backend.cf-challenge-mock?blocks-ws(req) => return cb false, 403, \Forbidden, {'cf-mitigated': \challenge}
    cb true

sharedb = sdb-server do
  wss: wss
  app: app
  io: db.settings!
  session: session.middleware!
  # demo 只開放 `demo` collection. 實際專案要依 user / collection 檢查權限.
  access: ({collection}) -> if collection == \demo => Promise.resolve! else lderror.reject 1012

# connector 的 `ping` scope 靠這個回 pong.
wss.on \connection, (ws, req) ->
  ping = new ews ws: ws, scope: \ping
  ping.addEventListener \message, -> ping.send \pong

# 停機時關掉 websocket ( 1001 going away ), connector 會自己重連. 不關的話 npm stop 要等到 shutdown-timeout
backend.on-stop -> wss.clients.forEach -> it.close 1001, \restarting

backend.sharedb = sharedb
backend.server = server
