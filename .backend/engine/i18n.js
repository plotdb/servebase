// Generated by LiveScript 1.6.0
(function(){
  var fs, chokidar, i18next, i18nextFsBackend, i18nextHttpMiddleware, jsYaml, ret;
  fs = require('fs');
  chokidar = require('chokidar');
  i18next = require('i18next');
  i18nextFsBackend = require('i18next-fs-backend');
  i18nextHttpMiddleware = require('i18next-http-middleware');
  jsYaml = require('js-yaml');
  ret = function(opt){
    var options, this$ = this;
    options = import$({
      lng: ['zh-TW'],
      fallbackLng: 'zh-TW',
      preload: ['zh-TW'],
      ns: 'default',
      defaultNS: 'default',
      fallbackNS: 'default',
      initImmediate: false,
      backend: {
        loadPath: 'locales/{{lng}}/{{ns}}.yaml'
      }
    }, opt || {});
    return i18next.use(i18nextFsBackend).use(i18nextHttpMiddleware.LanguageDetector).init(options).then(function(){
      var _load, watcher;
      _load = function(arg$){
        var file, type, err;
        file = arg$.file, type = arg$.type;
        if (type !== 'unlink') {
          try {
            jsYaml.load(fs.readFileSync(file, 'utf8'));
            i18next.reloadResources(options.lng);
            return this$.logI18n.info(file + " " + (type === 'add' ? '' : 're') + "loaded.");
          } catch (e$) {
            err = e$;
            return this$.logI18n.error({
              err: err
            }, ("locale file " + file + " parse error: " + (err.message || 'no message provided')).red);
          }
        }
      };
      watcher = chokidar.watch(['locales'], {
        persistent: true,
        ignored: function(f){
          return /\/\./.exec(f);
        }
      });
      watcher.on('add', function(it){
        return _load({
          file: it,
          type: 'add'
        });
      }).on('change', function(it){
        return _load({
          file: it,
          type: 'change'
        });
      }).on('unlink', function(it){
        return _load({
          file: it,
          type: 'unlink'
        });
      });
      return i18next;
    });
  };
  module.exports = ret;
  function import$(obj, src){
    var own = {}.hasOwnProperty;
    for (var key in src) if (own.call(src, key)) obj[key] = src[key];
    return obj;
  }
}).call(this);
