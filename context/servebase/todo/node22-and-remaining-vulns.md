# 升 Node 22 + 清剩餘漏洞

2026/08/08 audit fix 後的殘留事項。當時 46 個漏洞修到剩 24 個，
剩下的都需要跨 major 升級或動自家套件，且部分卡在 Node 20。

## 背景

 - 主要 server 還在 Node 20（已 EOL 2026/04），一時不便全面升級
 - `re2` 暫時釘在 `~1.23.0`：1.26.1 要 node-gyp 13 → undici 7 →
   `worker_threads.markAsUncloneable`（Node ≥ 22.10 才有），Node 20 編不過。
   代價：re2 1.23.0 自己有一個 moderate advisory
 - volta pin 已從 20.17.0 升到 20.20.2（20 系列最新）

## 待辦（依優先序）

1. server 環境升 Node 22 LTS 後：
   - volta pin node@22
   - re2 改回 `^1.26.1`，跑 `npm audit fix`
2. 剩餘 critical（都是 major bump，各需一輪測試）：
   - `i18next-fs-backend` → 2.6.7（測 i18n）
   - `argon2` → 0.45.1（測 auth 登入；順帶清掉舊 tar 那串 critical/high）
3. 剩餘 high：`nodemailer` → 9（測寄信）、`canvas` → 3、`@plotdb/srcbuild` → 0.0.70
4. 自家套件：`@plotdb/suuid` 升 uuid 後發版（清 moderate）
5. dev deps 低優先：`mocha` → 11、`nyc` → 18
