# log rotate 狀況的檢查機制 ( tool/base/logcheck )

2026/09/12。起因: 某台 production server 建好三個月, `/var/log/nginx/` 積到 14G,
logrotate 一次都沒跑成功, 而且沒有任何人發現。

## 為什麼沒被發現 — logrotate 會靜默失敗

那台的 `/etc/logrotate.d/nginx` 寫的是 `create 640 nginx adm`, 但它是 Debian 系,
worker 跑在 `www-data`, 系統裡根本沒有 `nginx` 這個 user。

logrotate 遇到 unknown user 的行為是: **跳過整個 config 檔, 但 exit 0**。

```
error: /etc/logrotate.d/nginx:8 unknown user 'nginx'
error: found error in /var/log/nginx/*.log, skipping
... Handling 0 logs
```

所以 `systemctl status logrotate.timer` 永遠是 `active (waiting)`, 每天照跑,
exit code 永遠是 0。任何監控 timer 狀態或 exit code 的做法都抓不到。

**要檢查的是結果 ( log 到底有沒有被輪替 ), 不是執行狀態。**

這與 `tool/base/cachecheck` 的存在理由是同一個 — 那支工具的開頭寫著
「a wrong cache policy is silent. nothing breaks, nothing logs」。沒轉成的 log
也一樣: 什麼都沒壞, 什麼都沒記, 直到磁碟滿了才知道。值得斷言, 而不是只寫在文件裡。

## 要做的事

一支 `tool/base/logcheck`, 比照 `cachecheck` / `ping` 的形式 ( bash + 頂部 usage
註解 + `npm run logcheck` + `-j` 吐 json 給 scripts / agents / CI + 有語意的 exit code )。

檢查項目, 由強到弱:

1. **最後輪替時間** — 讀 `/var/lib/logrotate/status`, 每個 pattern 一行日期。
   超過該 config 宣告的週期 ( daily / weekly ) 太久就告警。最直接的結果檢查
2. **單檔大小** — 掃 log 目錄, 任何單一 log 檔超過閾值 ( e.g. 500M ) 就告警。
   即使 status 看起來正常, 檔案異常大就是有問題
3. **設定本身是否有效** — `logrotate -d` 的 stderr 抓 `error:` / `skipping`。
   這條直接對應上面那個失敗模式
4. **有沒有漏網的 log** — 掃常見 log 目錄, 比對哪些檔案不被任何
   `/etc/logrotate.d/*` 的 pattern 涵蓋。前三項都是「設定存在但無效」,
   這條抓的是「根本沒設定」

涵蓋範圍至少要有: nginx ( access / error )、專案自己的 `server.log`
( 已有 `config/base/logrotate/config.cfg` 在管 )、以及系統其它 log。

## 順帶: nginx 的 logrotate 也該納管

`config/base/logrotate/` 目前只有 server.log 的 template。nginx 的是各機器手動設,
所以才會有這次這種抄錯 user 的事 — 而且那次的修復也是直接改機器上的
`/etc/logrotate.d/nginx`, 沒進任何 repo, 重建機器會再漏一次。

比照 `config.cfg` 的 `!{...}` + template-text 慣例補一份 nginx 用的, 其中 user / group
必須是參數 ( 這正是踩雷的那一格 ), 預設值要跟發行版對得上: Debian/Ubuntu 是
`www-data adm`, RHEL 系才是 `nginx`。

網路上大量 nginx logrotate 範例出自 RHEL 系文件, 直接抄到 Debian 上就是這個下場。

## 之後

`logcheck` 能跑之後, 接到定期執行的流程裡, 至少要能被 cron 呼叫並在異常時回非 0。
