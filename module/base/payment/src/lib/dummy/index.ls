require! <[lderror @servebase/backend/aux https path node-fetch]>

module.exports =
  sign: ({cfg, payload}) -> Promise.resolve({payload})
  notified: ({body}) -> return {slug: body.slug, payload: {slug: body.slug}}
  endpoint: ({cfg}) -> {url: \/ext/pay/gw/dummy/, method: \POST}
  # dummy 3rd party payment gateway emulator
  gateway:
    # POST /pay/gateway/dummy/pay
    pay: (req, res, next) ->
      host = aux.hostname req
      if !slug = (req.body or {}).slug => return lderror.reject 404
      agent = new https.Agent rejectUnauthorized: false
      url = "https://#host/extapi/pay/gw/dummy/notify"
      cfg =
        method: \POST, agent: agent
        headers: {"Content-Type": 'application/json; charset=UTF-8'}
        body: JSON.stringify({slug})
      node-fetch url, cfg .then -> res.send!

    # POST /pay/gateway/dummy/
    page: (req, res, next) ->
      locals = {info: info = (req.body or {}){slug, name, amount}}
      if !(info.name and info.amount) => return lderror.reject 400
      # we can't use srcbuild rule (such as `@/@servebase/payment/view/dummy/index.pug`) directly
      # thus we compose the correct path manually
      fn = path.join(path.dirname(__filename), '..', '..', 'view/gateway/dummy/index.pug')
      res.render fn, ({exports: locals}) <<< locals
