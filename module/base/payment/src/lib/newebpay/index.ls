require! <[crypto @plotdb/suuid lderror]>

prepare = ({cfg, payload}) ->
  # newebpay only accept integer. so if the result before after rounding is not the same,
  # we should always throw error.
  amt = if typeof(payload.amount) != \string => payload.amount
  else parseFloat(payload.amount)
  if isNaN(amt) or amt != Math.floor(amt) => throw lderror 1020
  TradeInfo =
    MerchantID: cfg.MerchantID
    RespondType: \JSON
    TimeStamp: Date.now!
    Version: \2.0
    LangType: payload.lng or \zh-tw
    MerchantOrderNo: payload.key
    Amt: Math.floor(amt).toFixed(0)
    ItemDesc: payload.desc or 'no description'
    ReturnURL: cfg.ReturnURL
    NotifyURL: cfg.NotifyURL
    Email: payload.email or ''
    LoginType: 0

  code = []
  for k,v of TradeInfo => code.push "#k=#{encodeURIComponent(v)}"
  code = code.join \&
  cipher = crypto.createCipheriv('aes-256-cbc', cfg.hashkey, cfg.hashiv)
  cipher.setAutoPadding true
  code = cipher.update(code, \utf-8, \hex) + cipher.final(\hex)

  recode = "HashKey=#{cfg.hashkey}&#code&HashIV=#{cfg.hashiv}"

  hash = crypto.createHash \sha256
  TradeSha = (hash.update(recode).digest \hex).toUpperCase!

  return
    MerchantID: cfg.MerchantID
    TradeInfo: code
    TradeSha: TradeSha
    Version: \2.0

module.exports = do
  sign: ({cfg, payload}) -> return {payload: prepare({cfg, payload})}
  notified: ({cfg, body}) ->
    code = body.TradeInfo
    decipher = crypto.createDecipheriv('aes-256-cbc', cfg.hashkey, cfg.hashiv)
    decipher.setAutoPadding false
    code = decipher.update(code, \hex, \utf-8) + decipher.final(\utf-8)
    code = code.substring(0, code.length - code.charCodeAt(code.length - 1))
    obj = JSON.parse(code)
    state = if obj.Status == \SUCCESS => \complete else \pending
    return {key: obj.{}Result.MerchantOrderNo, payload: obj, state}
  endpoint: ({cfg}) ->
    return if cfg.testing => url: \https://ccore.newebpay.com/MPG/mpg_gateway, method: \POST
    else url: \https://core.newebpay.com/MPG/mpg_gateway, method: \POST
