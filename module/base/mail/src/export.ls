# 全域名用 sbmail 而非 mail: `mail` 當 window 上的名字太泛, 容易撞.
# `servebase` 這個命名空間是 @servebase/core 自己建的, 不保證先載入, 所以
# 不掛在它底下.
if module? => module.exports = mail
else if window? => window.sbmail = mail
