module.exports =
  pkg:
    dependencies: [
      * name: \marked, version: \main, path: \marked.min.js
      * name: \dompurify, version: \main, path: \dist/purify.min.js
      * name: \@servebase/discuss, version: \main, path: \index.min.js
    ]
    i18n:
      en:
        "預覽": "Preview"
        "取消": "Cancel"
        "更新": "Update"
        "啟用 Markdown 語法": "Use Markdown"
        "送出留言": "Post comment"
      "zh-TW":
        "預覽": "預覽"
        "取消": "取消"
        "更新": "更新"
        "啟用 Markdown 語法": "啟用 Markdown 語法"
        "送出留言": "送出留言"

  init: ({root, ctx, data}) ->
    {marked,discuss} = ctx
    data = data or {}
    ({core}) <- servebase.corectx _
    disc = new discuss {root, core} <<< data{slug, host, uri, config}
    disc.init!
      .then -> disc.load!
      .then -> console.log "discuss loaded."
