require! <[crypto]>

# 第二因素 ( 2FA ) 用到的純函式, 不碰 db / session, 方便單獨測試.
#  - base32: authenticator app 的 secret 只吃 base32 ( RFC 4648 ).
#  - totp: RFC 6238, SHA1 / 6 位數 / 30 秒, 這是 Google Authenticator 等 app 的預設, 別改.
#  - keyring: 加密 totp secret 與雜湊復原碼用的金鑰組. 做成具名金鑰, 可以輪替 ( 同 pepper ).
#  - recovery: 復原碼的產生與正規化.

b32 = \ABCDEFGHIJKLMNOPQRSTUVWXYZ234567

base32 =
  encode: (buf) ->
    [bits, val, out] = [0, 0, '']
    for byte in buf
      # 只需保留還沒輸出的低位元 ( 最多 12 位 ), 遮罩避免 32 位元溢位
      val = ((val .<<. 8) .|. byte) .&. 0xffff
      bits += 8
      while bits >= 5
        out += b32[(val .>>>. (bits - 5)) .&. 31]
        bits -= 5
    if bits > 0 => out += b32[(val .<<. (5 - bits)) .&. 31]
    out
  decode: (str) ->
    str = "#{str or ''}".toUpperCase!replace /[\s=-]/g, ''
    [bits, val, out] = [0, 0, []]
    for c in str
      if (i = b32.indexOf c) < 0 => throw new Error "invalid base32 string"
      val = ((val .<<. 5) .|. i) .&. 0xffff
      bits += 5
      if bits >= 8
        out.push (val .>>>. (bits - 8)) .&. 255
        bits -= 8
    Buffer.from out

safe-equal = (a, b) ->
  [a, b] = [Buffer.from("#a"), Buffer.from("#b")]
  a.length == b.length and crypto.timingSafeEqual(a, b)

hotp = (key, counter) ->
  buf = Buffer.alloc 8
  buf.writeBigUInt64BE BigInt(counter)
  h = crypto.createHmac(\sha1, key).update(buf).digest!
  o = h[h.length - 1] .&. 0xf
  n = h.readUInt32BE(o) .&. 0x7fffffff
  "#{n % 1000000}".padStart 6, \0

totp =
  period: 30
  secret: -> base32.encode crypto.randomBytes(20)
  step: (t = Date.now!) -> Math.floor(t / 1000 / totp.period)
  generate: ({secret, t}) -> hotp base32.decode(secret), totp.step(t)
  # 驗證 `code`, 容許前後 `window` 個時間窗 ( 手機時間誤差 ).
  # 回傳對上的 step, 讓呼叫端記下來防止同一組碼重複使用 ( replay ); 對不上回傳 null.
  verify: ({secret, code, window = 1, t}) ->
    code = "#{code or ''}".replace /\s/g, ''
    if !/^\d{6}$/.test(code) => return null
    key = base32.decode secret
    s = totp.step t
    hit = null
    # 不提早跳出, 每個時間窗都算一次
    for d from -window to window => if safe-equal(hotp(key, s + d), code) and !(hit?) => hit = s + d
    hit
  uri: ({secret, issuer, account}) ->
    label = encodeURIComponent("#issuer:#account")
    "otpauth://totp/#label?secret=#secret&issuer=#{encodeURIComponent issuer}" +
    "&algorithm=SHA1&digits=6&period=#{totp.period}"

# 具名金鑰組, 設定格式同 pepper: `{keys: {name: 'secret string'}, current: name}`.
#  - 加密 / 雜湊結果都帶著金鑰名稱, 輪替時加入新 key 並改 `current`, 舊 key 保留到舊資料都換掉為止.
#  - 用途不同的金鑰用 HKDF 從同一把 key 分出來, 加密與雜湊不共用同一把.
keyring = ({keys = {}, current} = {}) ->
  if !(current and keys[current]) => throw new Error "mfa key '#current' not found in keys"
  for k of keys => if /:/.test(k) => throw new Error "mfa key name '#k' must not contain ':'"
  derive = (name, purpose) ->
    if !keys[name] => throw new Error "mfa key '#name' not found in keys"
    Buffer.from crypto.hkdfSync(\sha256, "#{keys[name]}", '', "servebase-mfa-#purpose", 32)
  hash = (text, name) ->
    "#name:" + crypto.createHmac(\sha256, derive(name, \hash)).update("#text").digest(\base64url)
  encrypt: (text) ->
    iv = crypto.randomBytes 12
    c = crypto.createCipheriv \aes-256-gcm, derive(current, \encrypt), iv
    ct = Buffer.concat [c.update("#text", \utf8), c.final!]
    ([current] ++ [iv, c.getAuthTag!, ct].map(-> it.toString \base64url)).join \:
  decrypt: (str) ->
    [name, iv, tag, ct] = "#{str or ''}".split \:
    d = crypto.createDecipheriv \aes-256-gcm, derive(name, \encrypt), Buffer.from(iv or '', \base64url)
    d.setAuthTag Buffer.from(tag or '', \base64url)
    Buffer.concat([d.update(Buffer.from(ct or '', \base64url)), d.final!]).toString \utf8
  hash: (text) -> hash text, current
  # 用 `hashed` 自己記的金鑰名稱重算再比對, 所以輪替後舊的雜湊仍然可以驗
  match: (text, hashed) ->
    name = "#{hashed or ''}".split(\:).0
    if !keys[name] => return false
    safe-equal hash(text, name), hashed

# 復原碼: 10 碼, 排除易混淆的 0 1 i l o, 約 49 bits.
# 顯示成 `xxxxx-xxxxx`; 使用者輸入時忽略大小寫、空白與連字號.
ra = \23456789abcdefghjkmnpqrstuvwxyz
recovery =
  count: 10
  generate: ->
    for i from 0 til recovery.count
      c = [ra[crypto.randomInt ra.length] for j from 0 til 10].join('')
      "#{c.slice 0, 5}-#{c.slice 5}"
  normalize: (code) ->
    code = "#{code or ''}".toLowerCase!replace /[^0-9a-z]/g, ''
    if code.length == 10 and [c for c in code].every(-> ra.indexOf(it) >= 0) => code else null

module.exports = {base32, totp, keyring, recovery}
