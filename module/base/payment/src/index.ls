# used to fetch required info for making payment from our backend
payment =
  check: ({scope, slug}) ->
    ld$.fetch \/api/pay/check, {method: \POST}, {type: \json, json: {payload: {slug}}}
  request: ({gateway, url, payload, method}) ->
    ({core}) <~ servebase.corectx _
    # need a way to retrieve gateway info from configuration.
    if !url =>
      {url,method} = {
        dummy: {url: \/ext/pay/gw/dummy/, method: \POST}
      }[gateway] or {}
    if !(url and gateway) => return lderror.reject 1200
    core.loader.on!
    @prepare {payload, gateway}
      .finally -> core.loader.off!
      .then (ret = {}) ~> 
        @open {url: url, method: (method or \POST), data: ret.payload}
        return ret{slug, state, key}

  prepare: ({payload, gateway}) ->
    ld$.fetch \/api/pay/sign, {method: \POST}, {json: {gateway, payload}, type: \json}
      .then (ret = {}) -> return ret{payload, slug, state, key}

  # based on newebpay document, iframe / backend http post is not allowed due to certain regulation.
  # form post
  open: ({url, method, data}) ->
    form = document.createElement \form
    attrs = method: method or \post, action: url, target: \_blank
    for k,v of attrs => form.setAttribute k, v
    for k,v of data =>
      input = document.createElement \input
      input.setAttribute \type, \hidden
      input.setAttribute \name, k
      input.value = v
      form.appendChild input
    document.body.appendChild form
    form.submit!

if module? => module.exports = payment
else if window? => window.payment = payment
