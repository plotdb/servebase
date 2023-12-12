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
      else mods[cfg.gateway].notified {body: req.body or {}}
    .then (ret = {}) ->
      if !(slug = ret.slug) => return lderror.reject 400
      obj = name: cfg.gateway, payload: (ret.payload or {})
      db.query """
      update payment set (state, gateway, paidtime) = ('complete', $2, now()) where slug = $1
      returning key
      """, [slug, obj]
    .then (r={}) ->
      if r.[]rows.length < 1 => return lderror.reject 400
      res.send!

backend.route.extapi.post \/pay/notify, (req, res, next) -> notify-handler req, res, next

# generic route for accepting 3rd payment gateway redirection or notification
done-handler = (route or {}).done or (req, res) ->
  fn = path.join(path.dirname(__filename), '..', 'view/paid/index.pug')
  res.render fn, {}

backend.route.extapp.post \/pay/done, done-handler

# this should return a prepared data for passing to 3rd party payment gateway,
# based on the given gateway name.
backend.route.api.post \/pay/sign, aux.signedin, ((perm or {}).sign or ((q,s,n)->n!)), (req, res, next) ->
  {payload, gateway} = (req.body or {})
  payload.slug = suuid!
  endpoint = mods[gateway].endpoint or (->{})
  endpoint = endpoint({cfg: gwinfo}) or {}
  ret = { state: \pending, slug: payload.slug } <<< endpoint{url, method}
  Promise.resolve!
    .then ->
      if !(payload and gateway and mods[gateway] and mods[gateway].sign) => return lderror.reject 1020
      db.query """
      insert into payment (owner, scope, slug, gateway, state) values ($1,$2,$3,$4,$5)
      returning key
      """, [req.user.key, payload.scope, payload.slug, {gateway}, \pending]
    .then (r={}) ->
      ret.key = r.[]rows.0.key
      mods[gateway].sign {cfg: gwinfo, payload}
    .then ({payload}) -> res.send(ret <<< {payload})

backend.route.api.post \/pay/check, aux.signedin, (req, res, next) ->
  if !(payload = req.body.payload) => return lderror.reject 400
  # TODO permission control
  db.query "select state,createdtime,paidtime from payment where slug = $1", [payload.slug]
    .then (r={}) -> res.send(r.[]rows.0 or {})

if cfg.gateway == \dummy =>
  gw = mods.dummy.gateway
  # we consider these endpoints as 3rd parties and thus CSRF token is not needed.
  backend.route.extapi.post \/pay/gw/dummy/pay, gw.pay
  backend.route.extapi.post \/pay/gw/dummy/notify, (gw.notify or (q,s,n)->n!), notify-handler
  backend.route.extapi.post \/pay/gw/dummy/done, (gw.done or (q,s,n)->n!), done-handler
  backend.route.extapp.post \/pay/gw/dummy/, gw.page

