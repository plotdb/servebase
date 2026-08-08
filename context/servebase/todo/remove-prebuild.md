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
