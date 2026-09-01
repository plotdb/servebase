# 首次全量建置不產生 intl 輸出

2026/09/01 做 `src/raw` 遷移驗證時發現。與 raw / srcbuild 0.1.4 無關,是既有問題。

## 現象

把 `frontend/base/{static,.view,.bundle-dep}` 全部清空後冷啟動,initial scan 建了 24 個
頁面,**其中沒有任何一個產生 intl 版本**:

    src/pug/auth/index.pug        --> static/auth/index.html
    src/pug/err/490.pug           --> static/err/490.html
    src/pug/index.pug             --> static/index.html
    ... ( 共 24 個, 全部只有非 intl 版 )

intl 檔案是**後續**因為 bundle hash 改變而觸發的重建才出現的,所以只有那批被
invalidate 到的頁面有:

    static/intl/{en,zh-TW}/{index,auth/index,dev/index}.html      <- 只有這些

`err/490` 跟 `lighthouse/index` 之後沒有再被 invalidate 過, 所以永遠沒有 intl 版。

確認方式: `touch` 任一 pug 來源, intl 版立刻正常產生。把 `src/pug` 全部 touch 一次,
48 個 intl 檔案全部出現 ( 24 頁 x 2 語系 )。

## 影響

長期存活的 `static/` 樹反而是**不完整**的, 而且沒有人會發現:

    遷移前那棵跑了一天多的樹     intl 檔案 10 個
    全部 touch 後的完整建置       intl 檔案 48 個

也就是說 38 個 intl 頁面一直不存在。nginx 的 fallback 是
`try_files /$1 /$1/index.html @apiserver`, 所以請求 `/intl/en/modules/error/404.html`
會落到 express, 由 route 決定生死 —— 沒 route 的就是 404, 而且是靜默的。

反過來說, 這也表示「哪些 intl 檔案存在」取決於這棵樹的歷史, 不取決於原始碼。

## 位置

`srcbuild/src/ext/pug.ls:350`:

    lngs = ([''] ++ (if @i18n and @_build-intl => @i18n.{}options.lng or [] else []))

initial scan 執行到這行時 `@i18n` 還沒 ready ( 或 `options.lng` 還是空的 ), 所以
`lngs` 只有 `['']`。之後的 change event 才拿得到語系清單。

servebase 這邊 `backend/engine/index.ls:128` 把 `i18n` 傳進 `srcbuild.lsp`, 而
`@i18n` 是在 `prepare` 裡才 `.then ~> @i18n = it` 設好的 —— 要確認傳進去的到底是
哪一個, 以及 initial scan 是不是跑在它 resolve 之前。

## 要做的事

- 確認根因是 i18n 未 ready 還是別的 ( 上面只是最合理的推測, 沒有實證到那一行 )
- 修法方向: initial scan 等 i18n ready 再跑, 或 `lngs` 為空時不要當成「就是沒有語系」
  而是延後
- 這跟 `watcher.ready` ( srcbuild 0.1.3 ) 是同一類問題: 建置在它的相依還沒就緒時就開始
