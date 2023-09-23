require! <[crypto @plotdb/suuid]>

prepare = ({cfg, info}) ->
  TradeInfo =
    MerchantID: cfg.MerchantID
    RespondType: \JSON
    TimeStamp: Date.now!
    Version: \2.0
    LangType: info.lng or \zh-tw
    MerchantOrderNo: suuid!replace(/\./g,'0')
    Amt: info.amount
    ItemDesc: info.desc
    ReturnURL: cfg.ReturnURL
    NotifyURL: cfg.NotifyURL
    Email: cfg.Email
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

  return do
    MerchantID: cfg.MerchantID
    TradeInfo: code
    TradeSha: TradeSha
    Version: \2.0

module.exports = do
  #opt = url: \https://ccore.newebpay.com/MPG/mpg_gateway, form: prepare!
  #request.post opt, (e, r, b) -> res.send!
  sign: ({cfg, info}) -> return {data: prepare({cfg, info})}
