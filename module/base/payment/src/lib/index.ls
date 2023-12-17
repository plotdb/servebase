({route, perm, backend}) <- (->module.exports = it)  _

db = backend.db

if !(cfg = backend.config.payment) => return
if !(gwinfo = (cfg.gateways or {})[cfg.gateway]) => return

require! <[path lderror https @servebase/backend/aux @plotdb/suuid]>
fs = require "fs-extra"
fetch = require "node-fetch"

log = backend.log.child {module: \payment}
mods = {}
try
  mods[cfg.gateway] = require "./#{cfg.gateway}"
catch err
  log.error {err}, "payment gateway `#{cfg.gateway}` configured but failed to load.".red
  return

notify-handler = (req, res, next) ->
  Promise.resolve!
    .then ->
      if !mods[cfg.gateway].notified => req.body
      else mods[cfg.gateway].notified {cfg: gwinfo, body: req.body or {}}
    .then (ret = {}) ->
      if !((slug = ret.slug) or (key = ret.key)) => return lderror.reject 400
      obj = name: cfg.gateway, payload: (ret.payload or {})
      db.query """
      update payment set (state, gateway, paidtime) = ($3, $2, now())
      where #{if slug? => 'slug = $1' else 'key = $1'}
      returning key
      """, [(if slug? => slug else key), obj, (ret.state or \pending)]
        .then (r={}) ->
          if r.[]rows.length < 1 => return lderror.reject 400
          return obj

notify-router = (req, res, next) -> notify-handler req, res, next .then -> res.send!
backend.route.extapi.post \/pay/notify, notify-router

# generic route for accepting 3rd payment gateway redirection or notification
done-router = (req, res, next) ->
  notify-handler req, res, next
    .then (obj = {}) ->
      fn = path.join(path.dirname(__filename), '..', 'view/done/index.pug')
      res.render fn, {exports: obj}
backend.route.extapp.post \/pay/done, done-router
backend.route.extapp.get \/pay/done, done-router

# this should return a prepared data for passing to 3rd party payment gateway,
# based on the given gateway name.
backend.route.api.post \/pay/sign, aux.signedin, ((perm or {}).sign or ((q,s,n)->n!)), (req, res, next) ->
  payload = (req.body or {}).payload
  gateway = (req.body or {}).gateway or cfg.gateway
  if !(payload and gateway and (mod = mods[gateway]) and mod.sign) => return lderror.reject 1020
  payload.slug = suuid!
  payload.email = req.user.username
  endpoint = mod.endpoint or (->{})
  ret = { state: \pending, slug: payload.slug }
  Promise.resolve!
    .then ->
      db.query """
      insert into payment (owner, scope, slug, payload, gateway, state) values ($1,$2,$3,$4,$5,$6)
      returning key
      """, [req.user.key, payload.scope, payload.slug, payload, {gateway}, \pending]
    .then (r={}) ->
      ret.key = r.[]rows.0.key
      payload.key = ret.key
      mod.sign {cfg: gwinfo, payload}
    .then ({payload}) ->
      ep = endpoint({cfg: gwinfo, payload}) or {}
      res.send(ret <<< ep{url, method} <<< {payload})

backend.route.api.post \/pay/check, aux.signedin, (req, res, next) ->
  if !(payload = req.body.payload) => return lderror.reject 400
  # TODO permission control
  db.query "select state,createdtime,paidtime from payment where slug = $1", [payload.slug]
    .then (r={}) -> res.send(r.[]rows.0 or {})

if cfg.gateway == \dummy =>
  gw = mods.dummy.gateway
  # we consider these endpoints as 3rd parties and thus CSRF token is not needed.
  backend.route.extapi.post \/pay/gw/dummy/pay, gw.pay
  backend.route.extapi.post \/pay/gw/dummy/notify, (gw.notify or (q,s,n)->n!), notify-router
  backend.route.extapi.post \/pay/gw/dummy/done, (gw.done or (q,s,n)->n!), done-router
  backend.route.extapp.post \/pay/gw/dummy/, gw.page

