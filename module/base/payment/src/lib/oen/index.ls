require! <[crypto @plotdb/suuid lderror node-fetch]>

get-url = ({cfg}) ->
  return if cfg.testing => url: \https://payment-api.testing.oen.tw/checkout, method: \POST
  else url: \https://payment-api.oen.tw/checkout, method: \POST

module.exports =
  sign: ({cfg, payload}) ->
    amount = if typeof(payload.amount) != \string => payload.amount
    else parseFloat(payload.amount)
    if isNaN(amount) or amount != Math.floor(amount) => throw lderror 1020
    if !(cfg.merchantId and cfg.token and cfg.successUrl) => throw lderror 400
    obj =
      merchantId: cfg.merchantId
      amount: amount
      platformFee: 0
      currency: \TWD
      orderId: "#{payload.key}"
      successUrl: cfg.successUrl
      failureUrl: cfg.failureUrl or cfg.successUrl
      productDetails: [
      * productionCode: 'n/a'
        description: payload.desc or 'n/a'
        quantity: 1
        unit: '個/piece'
        unitPrice: amount
      ]
      userEmail: payload.email

    {url, method} = get-url {cfg}

    opt =
      method: method
      body: JSON.stringify(obj)
      headers:
        "Content-Type": "application/json; charset=UTF-8"
        "Authorization": "Bearer #{cfg.token}"

    node-fetch url, opt
      .then -> it.json!
      .then (ret) ->
        if ret.code != \S0000 => return lderror.reject 400
        return payload: ret

  endpoint: ({cfg, payload}) ->
    base = if cfg.testing => ".testing.oen.tw" else ".oen.tw"
    id = (payload.data or {}).id or ''
    url: "https://#{cfg.merchantId}#{base}/checkout/#id"
    method: \GET
