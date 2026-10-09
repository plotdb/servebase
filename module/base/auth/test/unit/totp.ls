# 2FA 的純函式: base32 / totp / keyring / recovery. 不碰 db.
#
#   npm test -- auth
#   ./node_modules/.bin/lsc module/base/auth/test/unit/totp.ls

require! <[path]>
{base32, totp, keyring, recovery} = require path.join(__dirname, \../../dist/lib/totp.js)

failed = 0
ok = (cond, msg) ->
  console.log "  #{if cond => 'ok  ' else 'FAIL'} #msg"
  if !cond => failed := failed + 1
throws = (f) -> try (f!; false) catch e => true

console.log "\nbase32"
ok base32.encode(Buffer.from 'foobar') == \MZXW6YTBOI, "RFC 4648 向量 ( foobar )"
ok base32.decode(\MZXW6YTBOI).toString! == \foobar, "decode"
ok base32.decode('mzxw 6ytb-oi======').toString! == \foobar, "忽略大小寫、空白、連字號與 padding"
ok throws(-> base32.decode \MZ1), "非 base32 字元丟錯"
buf = require(\crypto).randomBytes 20
ok base32.decode(base32.encode buf).equals(buf), "20 bytes 來回一致"

console.log "\ntotp"
# RFC 6238 附錄 B ( SHA1 ), 取 8 位數的末 6 位
secret = base32.encode Buffer.from('12345678901234567890')
for [t, code] in [[59, \287082], [1111111109, \081804], [1234567890, \005924], [2000000000, \279037]]
  ok totp.generate({secret, t: t * 1000}) == code, "RFC 6238 向量 T=#t"
t = 1111111109 * 1000
s = totp.step t
ok totp.verify({secret, code: \081804, t}) == s, "驗過回傳 step"
ok totp.verify({secret, code: '081 804', t}) == s, "忽略空白"
ok totp.verify({secret, code: totp.generate({secret, t: t - 30000}), t}) == s - 1, "容許前一個時間窗"
ok totp.verify({secret, code: totp.generate({secret, t: t + 30000}), t}) == s + 1, "容許後一個時間窗"
ok totp.verify({secret, code: totp.generate({secret, t: t - 60000}), t}) == null, "兩個時間窗以外不過"
ok totp.verify({secret, code: \000000, t}) == null, "錯的碼不過"
ok totp.verify({secret, code: \12345, t}) == null, "格式不對不過"
ok totp.secret!length == 32, "新 secret 為 20 bytes / 32 字元"
uri = totp.uri {secret: \ABC, issuer: 'My Site', account: 'a@b.c'}
ok uri == 'otpauth://totp/My%20Site%3Aa%40b.c?secret=ABC&issuer=My%20Site&algorithm=SHA1&digits=6&period=30', "otpauth uri"

console.log "\nkeyring"
ok throws(-> keyring({keys: {}, current: \k1})), "current 不存在丟錯"
ok throws(-> keyring({keys: {'a:b': \x}, current: 'a:b'})), "key 名稱不能有冒號"
k1 = keyring {keys: {k1: \secret-1}, current: \k1}
enc = k1.encrypt \hello
ok /^k1:/.test(enc), "密文帶金鑰名稱"
ok k1.encrypt(\hello) != enc, "每次 iv 不同"
ok k1.decrypt(enc) == \hello, "解密"
[name, iv, tag, ct] = enc.split \:
ok throws(-> k1.decrypt [name, iv, tag, ct.split('').reverse!join('')].join(\:)), "竄改密文解不開"
k2 = keyring {keys: {k1: \secret-1, k2: \secret-2}, current: \k2}
ok k2.decrypt(enc) == \hello, "輪替後舊 key 的密文仍可解"
ok /^k2:/.test(k2.encrypt \x), "新資料用新 key"
ok throws(-> keyring({keys: {k2: \secret-2}, current: \k2}).decrypt enc), "舊 key 移除後解不開"
h = k1.hash \abc
ok (k1.match('abc', h) and !k1.match('abd', h)), "雜湊比對"
ok k2.match('abc', h), "輪替後舊雜湊仍可比對"
ok !keyring({keys: {k1: \other}, current: \k1}).match('abc', h), "key 不同比對不過"

console.log "\nrecovery"
codes = recovery.generate!
ok codes.length == 10, "10 組"
ok codes.every(-> /^[2-9a-hjkmnp-z]{5}-[2-9a-hjkmnp-z]{5}$/.test it), "格式 xxxxx-xxxxx"
ok (new Set codes).size == 10, "不重複"
ok recovery.normalize(' ABCDE-fghjk ') == \abcdefghjk, "正規化"
ok recovery.normalize(\abcde-fghj) == null, "長度不對"
ok recovery.normalize(\abcde-fghj1) == null, "含排除字元"

console.log(if failed => "\n#failed 項失敗" else "\n全部通過")
process.exit(if failed => 1 else 0)
