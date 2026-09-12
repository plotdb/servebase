# config.ngx 的 compile-time include 與外部規則生成

2026/09/12。越來越多 nginx rule 不是手寫的, 而是外部來源生成的, 但目前只能手貼進
每個 project 的 `config/web/nginx/config.ngx`。

## 現況的問題

某個 derived project 的 config.ngx 裡有一整塊 `#### generated from @plotdb/registry ####`,
五十多行, 而那塊中間有一行註解寫著 `# this location is patched manually`。

生成內容與手改混在同一個檔裡, 只有兩種結局: 重新生成會蓋掉手改, 不重新生成就跟著
上游漂移。沒有第三條路。

同一個來源還可能要貢獻不同 context 的片段 — registry 除了 server block 裡的 location,
還需要一個 server block 外的 `proxy_cache_path`。

Cloudflare 的 real ip 網段清單 ( 見 20260912-cloudflare-real-ip.md ) 是同一個形狀的
問題: 外部來源、會變、跨 project 共用、不該手抄。registry 是第一個, CF 是第二個,
不會是最後一個。

## A. config.ngx 支援 compile-time include

在 template-text 這層展開, render 成一個完整的 config.ngx, 而不是用 nginx 自己的
runtime `include` 指令。

這跟 `doc/base/infrastructure.md` 的 `src/raw` 選擇 build-time union 而非
serve-time lookup order 是同一個判斷: 把合併發生在建構期, 下游就只看到一份產物,
不必有第二套實作去理解搜尋順序。

具體理由:

1. 產物是單一完整檔, 部署不依賴目標機器上剛好有那個被 include 的檔
2. 缺片段在 render 時就會發現, 而不是 nginx reload 才 fail。
   runtime include 指到不存在的檔案會讓 nginx 起不來; 若為了容錯寫成 glob
   ( `include foo.conf*;` ) 又會在該啟用卻沒檔案時靜默跑成沒設定 — 換成另一種靜默失敗
3. 可以被既有的 `!{if ...}` 條件包住 ( 已有 project 用這個寫法包 HSTS 的 listen 80 )
4. include 進來的內容還能再吃一層參數替換 — registry 的片段裡就有 `!{cache.name}`

設計上要處理的:

- **片段要能落在不同 context** — http / server / location。同一個來源可能同時需要
  server block 外的 `proxy_cache_path` 和 block 內的 location
- **生成內容與本地覆寫要分離** — 不要再出現 `patched manually` 夾在生成區塊裡。
  本地要改的東西應該有自己的位置, 重生不會動到它
- **片段來源** — node_modules ( registry 自帶 )、`config/base/nginx/` 下的、
  以及抓下來生成的

## B. 從外部清單生 ngx 片段的 tool

放 `tool/base/`, 比照 `ping` / `logview` / `cachecheck` 的慣例 ( bash + 頂部 usage
註解 + 對應的 npm run + `-j` 吐 json + 有語意的 exit code )。

第一個使用者是 Cloudflare:

- 抓 https://www.cloudflare.com/ips-v4 與 ips-v6
- 產出 `set_real_ip_from` 清單 + `real_ip_header CF-Connecting-IP`
- 產物就是 A 的一個 include 片段
- **抓不到時必須明確失敗** — 不能產出空清單。空清單是 fail-safe 的
  ( 不信任任何來源 = 不會被偽造 ), 但結果是設了等於沒設, 而且看起來像設好了

形狀應該做成通用的 ( 來源 URL → 片段 ), CF 只是第一個。

## 現在不做

不改任何 config.ngx。決定先記錄。
`config/base/nginx/cloudflare-notice.md` 有給後人看的說明。
