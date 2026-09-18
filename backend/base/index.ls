(backend) <- (->module.exports = it)  _
{config,route:{api,app}} = backend
if config.base != \base => return

require! <[fs path express @servebase/backend/aux]>

demo-api = aux.routecatch express.Router {mergeParams: true}
demo-app = aux.routecatch express.Router {mergeParams: true}
api.use \/demo, demo-api
app.use \/demo, demo-app

fs.readdir-sync __dirname
  .filter -> !/^index\./.exec(it)
  .filter -> !/^\./.exec(it)
  # `manager.ls` sits in this folder only so that `config.build.block.manager`
  # has something to point at; it is not a route. loading it as one called it
  # with the backend as its `{base}`, built a block manager nobody kept, and -
  # the reason it is excluded rather than merely harmless - pulled jsdom into
  # the startup path, ~380ms before `listen`. the builder requires it on its
  # own, after `listen`, when the config names it.
  .filter -> !(it in <[manager.ls manager.js]>)
  .map -> path.join(__dirname, it)
  .filter -> /\.(ls|js)$/.exec(it) or fs.stat-sync(it).is-directory!
  .map -> require(it) backend, {api: demo-api, app: demo-app}
