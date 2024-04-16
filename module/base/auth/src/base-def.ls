module.exports = {
  pkg:
    name: "auth", version: "0.0.1", path: "base.html"
    i18n: i18n-resource
    dependencies: [
      {name: "ldview", version: "main"}
      {name: "ldnotify", version: "main"}
      {name: "ldform", version: "main"}
      {name: "ldbutton", version: "main", type: \css}
      {name: "@loadingio/loading.css", version: "main", path: "lite.min.css"}
      {name: "ldnotify", version: "main", type: \css, global: true}
      {name: "curegex", version: "main", path: "curegex.min.js"}
    ]
} <<< base-imp
