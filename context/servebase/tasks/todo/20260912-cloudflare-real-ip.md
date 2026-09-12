# Cloudflare 後面的真實 client IP ( set_real_ip_from )

2026/09/12 處理某個 production site 的 nginx log 時發現。站在 Cloudflare 後面時,
nginx 看到的 `$remote_addr` 是 CF edge 節點的 IP ( e.g. 172.68.106.144 ), 不是訪客的。

`config/base/nginx/config.ngx` 完全沒有處理這件事, 所以每個掛 CF 的 derived project
都在踩, 而且不會有任何徵兆。

## 影響範圍比 log 難看更大

1. **access.log 沒有分析價值** — 全部是 CF 節點 IP。有一台累積了 14G 這種 log
2. **後端拿到的 IP 是錯的** — config.ngx 的 `@apiserver` block:
   ```nginx
   proxy_set_header X-Real-IP $remote_addr;
   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   ```
   兩個 header 帶的都是 CF IP。任何靠 IP 的邏輯 ( rate limit、風控、地理判斷、
   abuse 追查、audit log ) 全部失準。有些 derived project 還有第二個 proxy block
   ( 例如 registry 的 ), 同樣的兩行也在那裡
3. **rate limit 會比沒有更糟** — config.ngx 裡註解掉的 `limit_req zone=api burst=7`
   若啟用, 會以 CF 節點為單位限流, 等於把所有訪客算成同一人。修好之前不要開

## 解法

nginx 內建 realip module ( Debian/Ubuntu 的 nginx-full / nginx-extras 都有編進去,
`nginx -V 2>&1 | grep -o with-http_realip_module` 可確認 )。

```nginx
set_real_ip_from <每個 cloudflare 網段>;
real_ip_header CF-Connecting-IP;
```

關鍵是 realip 改寫的是 `$remote_addr` 本身, 在任何 location 被評估之前就生效。
所以 access.log、`X-Real-IP`、`X-Forwarded-For`、`limit_req` 全部自動跟著正確,
**一行 `proxy_set_header` 都不用改**。

不需要 `real_ip_recursive on` — 那是給 X-Forwarded-For 這種逗號串列用的,
`CF-Connecting-IP` 永遠是單一 IP。

## 安全性 ( 這條不能省 )

`set_real_ip_from` 必須只列 CF 的網段。少了它 ( 或寫成 `0.0.0.0/0` ), 任何人都能
自己送一個 `CF-Connecting-IP: 1.2.3.4` 來偽造來源 IP, 繞過 rate limit、污染 audit log。

反過來說, 只要清單是對的, 直連源站的攻擊者偽造不了 — 他的來源 IP 不在信任網段內,
header 會被直接忽略。直連的風險是繞過 CF 的 WAF / DDoS 防護, 那是另一回事
( 防火牆只放行 CF 網段 ), 不在這個 task 範圍。

## 卡在哪

網段清單會變, 是跨 project 共用的, 而且錯一格就等於信任範圍錯一格 — 不能手抄。
需要生成 tool + include 機制, 已獨立成 20260912-nginx-rule-include.md
( 與 @plotdb/registry 的手動貼片段是同一個問題 )。本 task 等它落地後才動手。

要開關也不成問題: template-text 支援條件展開, 已有 project 用
`!{if enable_hsts? and enable_hsts => """..."""  else ""}` 包住 HSTS 的 listen 80,
照抄即可。是否與既有的 `enable_hsts` 合成一個 flag ( 會踩 CF redirect loop 的
就是掛 CF 的 ) 還是分開, 要看部署實況再決定。

## 現在不做

決定先記錄。給後人看的說明放在 `config/base/nginx/cloudflare-notice.md`,
因為先讀到那個目錄的人未必會翻 tasks/todo。

## 驗證

套用後直接看 log 就知道 — access.log 第一欄應該變成各式各樣的訪客 IP,
而不是清一色 172.64.0.0/13 那段。
