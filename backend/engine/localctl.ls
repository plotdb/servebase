# local control channel: a unix domain socket for developer / ops to talk to a
# running server directly. modules can register handlers via `backend.route.localctl`.
# access is guarded by socket file permission ( 0600 ) so it's also safe in production.
#
# usage ( from project root; url host is a syntax placeholder - routing is by socket file ):
#   curl -s --unix-socket .localctl.sock -X POST http://localhost/<command>
#
# multiple servers on the same machine are distinguished by their own socket file
# under each project root.

require! <[fs path express body-parser]>
require! <[./aux]>

module.exports = (backend) ->
  app = express!
  app.use body-parser.json!
  backend.route.localctl = aux.routecatch app

  # generic engine-level commands, available in every servebase-based project:
  backend.route.localctl.post \/cachestamp, (req, res, next) ->
    res.send "#{backend.cachestamp = new Date!getTime!}"

  # identity of this running server. answering at all already proves liveness
  # ( a stale socket file refuses connection ), so `tool/base/ping` uses this
  # to tell whether a server is up and which project / config it belongs to.
  backend.route.localctl.get \/info, (req, res, next) ->
    addr = if backend.server => backend.server.address! else null
    res.json do
      pid: process.pid
      title: process.title
      home: backend.root
      cfg-name: backend.cfg-name
      port: (addr or {}).port or backend.config.port
      mode: backend.mode or \development
      version: backend.version
      cachestamp: backend.cachestamp
      uptime: new Date!getTime! - backend.start-time

  server = null
  init: -> new Promise (res, rej) ->
    if server => return res!
    sock = path.join(backend.root, '.localctl.sock')
    # remove stale socket file from previous run, if any
    try
      fs.unlink-sync sock
    catch e
      null
    server := app.listen sock, ->
      try
        fs.chmod-sync sock, 8~600
      catch e
        null
      backend.log-server.info "local control channel on #sock"
      res!
