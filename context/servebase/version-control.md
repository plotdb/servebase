# Version Control - 專案特例

本專案大致遵循 `context/shared/version-control.md`，但有以下特例：

## CHANGELOG.md 位置

CHANGELOG.md 放在 `doc/base/CHANGELOG.md`，**不放專案根目錄**。

原因：servebase 是基板專案，derived projects fork 後會持續 rebase 取得基板更新。
根目錄的 CHANGELOG.md 會與 derived project 自己的 changelog 衝突；`doc/base/`
屬於基板命名空間，rebase 時不會相撞。

格式仍照 shared guideline：`## master` section 放尚未進版的變更，
依 features / tweaks / bug fix 分類。

## 命名空間原則

同樣邏輯適用於其他檔案：基板專屬的東西放基板命名空間
（ `doc/base/`、`backend/base/`、`frontend/base/`、`config/base/`、`module/base/`、
`context/servebase/` ），避免佔用 derived project 會使用的路徑
（ 如 `context/project/`、根目錄 `CHANGELOG.md` ），減少 merge 衝突。

## 基板 / derived 雙版本維護

servebase（基板）與 derived project 各有自己的版本，維護方式：

### 基板版本

 - 以 git tag + `doc/base/CHANGELOG.md` 為準
 - **不使用 package.json 的 version 欄位**——那是共用檔，基板 bump 一次
   就是給所有 derived 製造一次 rebase 衝突。version 欄位讓給 derived 用。

### derived 目前基於基板的哪一版

 - `doc/base/CHANGELOG.md` 會跟著 rebase 進 derived，最上面的版本 section
   就是目前基於的基板版本，rebase 完自然更新，不需額外標記檔
 - 機器可讀的查法：`git merge-base HEAD upstream/master` 後 `git describe --tags`

### derived 自己的版本

 - 根目錄 `CHANGELOG.md` + 自己的 git tag + package.json version，
   與基板互不干涉（基板 changelog 已收進 `doc/base/`）

### 跨版本升級

 - 基板的 breaking change 依版本分節寫進 `doc/base/migration-note.md`；
   derived rebase 跨了幾版，就照 migration note 逐版處理
 - 注意：`doc/base/version-control.md`（正式文件）定義的 derived 更新方式是
   **merge**（`git merge servebase/master`），不是 rebase——merge 可保留 derived
   已發佈的 tag 歷史。`context/servebase/README.md` 寫「fork 後持續 rebase」與此
   不一致，以 doc/base 為準。
