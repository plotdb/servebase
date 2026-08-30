# srcbuild 的相依圖與 bundle 建置：已確認的問題

狀態：以下七點都已在 srcbuild 0.1.0 修掉, 並附上 regression test ( `npm test` ) 。
除了 cycle 那題會讓舊 code 同步卡死無法計入, 其餘測項在舊 code 上全數 fail。
細節見 srcbuild 的 `CHANGELOG.md` v0.1.0。下面保留原始的分析, 因為它同時是
這些測試的說明, 也記錄了每個 bug 的失敗模式。

2026/08/30 為了 `20260830-asset-cache-strategy.md` 的 bundle hash 而通讀
`@plotdb/srcbuild` ( 本地 checkout 在 `../srcbuild` , 版本 0.0.71 ) 。
以下都是讀 code 加上小實驗確認過的, 不是猜測。行號以 `src/` 的 LiveScript 原始碼為準,
`dist/` 的編譯結果一致。


## 一、syntax error 會讓相依關係消失 ( 這是「有時 dependency 追不到」的原因 )

`adapter.ls` 的 `log-dependencies` ( 24-35 行 ) 在 `get-dependencies` 拋錯時,
記一行 log 然後丟出 `lderror 999`。兩個呼叫端都是同一個處理：

    # adapter.ls:52-55 ( change )
    if @is-supported file =>
      try @log-dependencies file catch e
        if e.name == \lderror and e.id == 999 => continue

    # adapter.ls:101-103 ( init )
    try @log-dependencies file catch e
      if e.name == \lderror and e.id == 999 => continue
    init-builds.push file

`continue` 發生在 `affected-files.add file` 之前, 所以分析失敗的檔案**完全從這一輪消失**：
不會 build, 不會往下游傳播, 在 `init` 時連 `init-builds` 都進不去。

關鍵在於 pug 的 `compileClientWithDependenciesTracked` 會**執行 filter**。實測：

    //- a.pug
    doctype html
    html
      body
        script
          include:lsc a.ls

`a.ls` 只要有 LiveScript 語法錯誤, `get-dependencies('a.pug')` 就直接拋
`Parse error on line 2: Unexpected 'DEDENT'` —— 錯的是 `.ls`, 但死掉的是 `.pug` 的相依分析。

於是完整的失敗路徑是：

 - 伺服器啟動時 `index.ls` 剛好是壞的
 - `init` 分析 `index.pug` 失敗 → `@depends.on['index.ls']` 從來沒建立過
 - 修好 `index.ls` → chokidar 發 change → pug adapter 的 `is-supported('index.ls')` 為 false,
   於是不做分析, 只查 `@depends.on['index.ls']` —— 是空的
 - 結果：`index.pug` 永遠不會重建, 除非手動 touch `index.pug`

symptom 正好是「改了東西但跑的是舊的」而且沒有任何錯誤訊息 ( 那行 `analyse ... failed`
在啟動時就滾過去了 ) 。

srcbuild 自己的 `TODO.md` 第一條就是這件事：

    track files failed to `get-dependencies` and retry each time a new change event is fired.

修法方向：adapter 維護一個 `@failed` Set, 分析失敗時放進去, 每次 change 事件都把
`@failed` 裡的檔案一併放進 queue 重試; 成功後移除。另外 `init` 時分析失敗的檔案仍應
`init-builds.push`, 讓 build 階段自己去報那個真正的錯誤 ( 現在錯誤訊息只有語意模糊的
「analyse 失敗」) 。


## 二、`adapter.change` 的 BFS 沒有 visited set —— 指數級展開, 看起來就像 circular build

`adapter.ls:49-62`：

    while queue.length
      file = queue.pop!
      ...
      affected-files.add file
      ...
      Array.from(@depends.on[file] or [])
        .map (f) ->
          if !mtimes[f] or mtimes[f] < mtimes[file] => mtimes[f] = mtimes[file]
          queue.push f

`affected-files` 只用來收集結果, **從來沒被拿來判斷要不要跳過**。`queue.push f` 是無條件的。

兩個後果：

 - 圖裡只要有環, 這個 while 就是無窮迴圈 ( 不是無窮 build, 是 event loop 直接卡死 )。
   `mtimes` 也擋不住：第二次走到同一個節點時 `mtimes[f] < mtimes[file]` 不成立,
   但 `queue.push f` 在 if 外面。
 - 就算沒有環, 這是對 DAG 做**路徑列舉**而不是節點走訪。典型的 pug 站台是
   `version.pug` → `base.pug` → 每一頁, 而每一頁又同時 include 好幾個共用 module,
   路徑數是乘法成長。改一個底層 module 就可能 pop 出幾萬到幾百萬次,
   而且每次 pop 都做 `fs.exists-sync` + `fs.stat-sync`。

「有時會 circular build」很可能就是這個 —— 不是真的重複產檔, 是這個迴圈在燒 CPU。

修法：加 visited 判斷, 但要保留 mtime 的最大值傳播語意 —— 只有在
「沒走訪過」或「這次帶來的 mtime 比上次大」時才 push：

    seen = {}
    ...
      Array.from(@depends.on[file] or [])
        .map (f) ->
          if seen[f]? and seen[f] >= mtimes[file] => return
          seen[f] = mtimes[file]
          if !mtimes[f] or mtimes[f] < mtimes[file] => mtimes[f] = mtimes[file]
          queue.push f

這樣每個節點最多被重訪「不同 mtime 值的個數」次, 實務上是 1-2 次。


## 三、bundle 的 spec 生命週期是壞的 —— link 只會增加, 不會減少

`bundle.ls` 的 `specmgr` 用三張反向表 ( `codesrc` / `specsrc` / `deps` ) 決定
「哪些檔案的變動要觸發哪些 bundle 重建」。移除這些 link 的路徑全部是死的：

 - `specmgr.unlink` ( 123-128 行 ) 呼叫 `s.remove(...)` , 但 `s` 是 `Set` ——
   `Set.prototype.remove` 不存在, 應該是 `delete`。這一行必定丟 TypeError。
   `dist/ext/bundle.js:295` 同樣是 `s.remove(...)` 。
 - `specmgr.del-specsrc` ( 130-138 行 ) 呼叫 `spec.unlink specsrc: n` , 但 `unlink`
   是 `specmgr` 的方法, `spec` 上沒有。同樣必定丟 TypeError。
 - `specmgr.delete` ( 110-115 行 ) 只呼叫 `unlink` ( 見上, 會爆 ) , 而且從頭到尾
   沒有 `delete @_[k]` —— spec 物件本身根本沒被移除。
 - `build.del-specsrc` ( 225 行 ) 寫成 `specmgr.del-specsrc n` , 指向的是 module scope
   的**建構函式** specmgr 而不是 `@specmgr`。而且整份 code 沒有任何地方呼叫它。
 - `specmgr.update` ( 87-107 行 ) 直接把 `s.codesrc` 換成新的 Set 再 `link` 新的,
   舊的 `@codesrc[oldfile]` 裡那筆 spec key 就永遠留著。

淨效果：**codesrc 的關聯只增不減**。一個檔案一旦曾經被某個 bundle 引用過,
之後即使那個 bundle 不再包含它, 改動它仍然會觸發那個 bundle 重建。加上
`.bundle-dep/**.dep` 的快取檔也從來不刪, 重啟時 `load-caches` 會把早就不存在的
spec 全部復活。跑久了會累積一堆幽靈 bundle 一直在重建。

因為死路徑從來沒被執行過, 這些 TypeError 至今沒人看到。要修的話得先讓
`del-specsrc` 真的被叫到 ( pug 檔被刪除時 ) , 那三個 bug 才會浮現。


## 四、`build-by-spec` 沒有任何 dirty 判斷, 每次都重寫

`bundle.ls:255` 開始的 `build-by-spec` 跟其他 builder 不一樣：`lsc.ls:32`、
`stylus.ls:31`、`pug.ls:191`、`asset.ls:22` 都有

    if !fs.exists-sync(src) or aux.newer(des, mtime) => continue

的守衛, 只有 bundle 沒有。任何一個 codesrc 的 change 事件都會完整重讀所有來源、
重跑 uglify、重寫 `des` 與 `des-min`。

現在不會爆炸只是因為 bundle 的輸出 ( `static/assets/bundle/*` ) 剛好不是任何 bundle 的
輸入。一旦要做「bundle 重建 → 回頭重建引用它的頁面」( 見 asset-cache-strategy 的待決一 ) ,
這個守衛就是必要的 —— 否則 page → bundle → page 會變成真正的無窮迴圈。

順帶：`build` ( 247-251 行 ) 在 change 檔案包含 `@cfgfn` 時 `return @load-cfg!` ,
會**略過同一批其他檔案的 `touch-code`**。同時存檔 `bundle.json` 和一個 lib 檔就會漏掉後者。


## 五、`.min` 檔名推導用的是字串 replace 不是 regex

`bundle.ls:277-278`：

    f = f.replace "\.min.#ext", ".#ext"
    f-min = f.replace "\.#ext", ".min.#ext"

LiveScript 的 `"\."` 就是 `"."`, 而 `String.replace` 傳字串時是**取代第一個出現的位置**,
不是 regex, 也不是從尾端算。所以任何路徑中間帶 `.js` / `.css` 的模組都會被推錯：

    static/assets/lib/three.js/main/index.js
      → f-min = static/assets/lib/three.min.js/main/index.js   ( 錯 )

結果是讀不到 `.min` 檔, 靜默 fallback 去 uglify 原始檔 ( `build-by-spec` 285-295 行的
`if o.code-min => ... else uglify-js.minify(o.code)` ) 。不會壞掉, 但慢, 而且完全沒有跡象。
應該改成錨定在結尾的 regex。


## 六、其他

 - `pug.ls:191` 的 mtime 守衛只看 `desv` ( `.view/*.js` ) , 但同一輪要產 `desv` 和
   `desh` 兩個檔。`desh` 被刪掉而 `desv` 還新的話, static html 不會重生。
 - build 失敗時舊的 `desh` 留在磁碟上, 於是壞掉的頁面會繼續送出上一版正確的 HTML ——
   又一個「沒有跡象」的失敗模式。
 - `view/pug.ls:24` 的 `lc.use-cache = true or opt.settings['view cache']`
   ( 已記在 asset-cache-strategy 待決三 ) 。


## 處理順序 ( 已完成 )

一和二是正確性問題而且修起來便宜, 先做, 都是 upstream ( srcbuild ) 的修改。
三和四是 bundle content hash 的前置條件 —— 不修的話新的 page↔bundle 回饋路徑會直接
踩到無窮迴圈。五和六順手。第七點是寫測試時才發現的, 見下。


## 七、`clear-dirty` 的 debounce 是掛在 prototype 上的

寫測試時才發現。`bundle.ls` 原本是

    clear-dirty: debounce 1000, ->

`@loadingio/debounce.js` 把 timer 存在一個 closure 變數 `l` 裡, 而這個 `debounce(...)`
在 prototype 上只求值一次 —— 所以**所有 specmgr 實例共用同一個 timer**。

servebase 是 `lsp {base: [@feroot] ++ config.srcbuild}` , 一個 base 一個 bundler。
兩個 bundler 在 1 秒內都 `set-dirty` 的話, 後者的 `ret.clear()` 會清掉前者的 timer,
而最後 `f.apply(this$)` 用的是後者的 `this` —— 前者的 `@_dirty` 就一直留著不會 flush,
它的 bundle spec 變更被靜默丟掉, 直到下一次剛好又有東西碰到它。

直接驗證過：

    proto = {flush: debounce 300, -> console.log @name}
    a = Object.create(proto) <<< {name: 'A'}
    b = Object.create(proto) <<< {name: 'B'}
    a.flush!; b.flush!    # 只印出 B

修法是在 constructor 裡綁 per-instance。`watch.ls` 的 `@change-debounced` 本來就是
在 `init!` 裡建的, 沒有這個問題; 全 repo 只有這一處是 prototype-level debounce。
