ldc.register \pagecfg, <[]>, ->
  locales:
    en: settings: \Settings
    "zh-TW": settings: \設定

ldc.register <[core]>, ({core}) ->
  <- core.init!then _
  view = new ldview { root: document.body }
  blocks = []
  core.manager.from {name: \@servebase/auth, path: \change-password}, {root: view.get('change-password')}
    .then (ret) -> blocks.push ret
    .then -> core.manager.from {name: \@servebase/auth, path: \account-info}, {root: view.get('account-info')}
    .then (ret) -> blocks.push ret
    .then -> core.manager.from {name: \@servebase/auth, path: \mfa-setup}, {root: view.get('mfa-setup')}
    .then (ret) -> blocks.push ret
  core.i18n.on \languageChanged, ->
    blocks.map -> it.instance.transform \i18n
  

