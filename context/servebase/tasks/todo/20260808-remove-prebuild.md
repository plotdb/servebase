# 拆掉 production 預編譯 ( prebuild / .backend )

2026/08/08 討論 start script 時順帶檢視的結論：預編譯對啟動速度沒有實質幫助，可以拆掉。

實測: backend 全部 55 個 .ls 檔 ( ~64KB ) 用 lsc 整包編譯只要 0.25s ( 含 node 啟動 )。
啟動時間的大頭是 require npm 套件與連 DB/Redis, 與是否預編譯無關。

預編譯的代價:

1. 兩條 code path: start 裡 production 跑 .backend、dev 跑 backend, 行為差異藏在這
2. stale build 風險: 改了 source 忘了 prebuild, production 跑舊 code, 難查
3. 部署多一步, 每個 derived project 都要記得

「production 不需要 livescript」不成立 — livescript 本來就在 dependencies ( pug ext 要用 )。

## 要做的事

- start 拿掉 NODE_ENV 分支, production 也直接跑 lsc
- 清掉 package.json 的 prebuild script 與 .backend 相關設定
- 檢查 deploy 流程 / derived projects 有沒有引用 .backend 的地方

若未來在意冷啟動 ( e.g. serverless ), 再加回來即可。

## 進度

2026/09/13: `start` 預設跑 `lsc ./backend/engine/index`, production 也一樣。
`.backend` 留著當 legacy / 緊急手段, 判斷就是「production 下存在就用」—— 沒有
flag、沒有設定 ( dev 一律走 source, 跟以前一樣: 留下的 .backend 若被 dev 吃到,
之後改 .ls 會完全沒反應 ),
但每次啟動都 warning, 並在 `backend/` 下有 `.ls` 比 build 新時多印一行 OUT OF DATE。
`npm run ping` 多一欄 `backend: source | prebuilt` ( engine 自己從 `__filename`
判斷 —— livescript 的 require hook 會在編譯的檔名尾巴加 `(js)`, 跟
`engine/index` 找自己目錄用的是同一個記號 —— 所以不靠 start 傳、手動啟動也準 )。

剩下的:

- `.backend` 目前是版控的, 且已經 stale ( 最後更新 2026/08/28, 之後 backend 原始碼
  還有改動 )。不刪的話所有 clone 都會走到 prebuilt 路徑並一直 warning, 等於沒改。
  應該 `git rm -r .backend` 並加進 .gitignore。
- 確認 source 模式在 production 跑一段時間沒問題後, 拿掉 package.json 的
  `prebuild` script 與 start 裡的 prebuilt 分支 ( ping 的 backend 欄位屆時也可拿掉 )
- 檢查 derived projects 的 deploy 流程有沒有引用 .backend
