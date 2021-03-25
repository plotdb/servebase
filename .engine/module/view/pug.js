// Generated by LiveScript 1.6.0
(function(){
  var fs, fsExtra, path, pug, srcbuild, pugext, reload, fsp, pugViewEngine;
  fs = require('fs');
  fsExtra = require('fs-extra');
  path = require('path');
  pug = require('pug');
  srcbuild = require('@plotdb/srcbuild');
  pugext = require("@plotdb/srcbuild/dist/ext/pug");
  reload = require("require-reload")(require);
  fsp = fs.promises;
  pugViewEngine = function(options){
    var extapi, logger, pugcache, log;
    extapi = new pugext({
      logger: options.logger,
      i18n: options.i18n
    }).getExtapi();
    logger = options.logger;
    pugcache = {};
    log = function(f, opt, t, type, cache){
      return logger.debug(f.replace(opt.basedir, '') + " served in " + t + "ms (" + type + (cache ? ' cached' : '') + ")");
    };
    return function(f, opt, cb){
      var lc, intl, viewdir, basedir, pc, startTime, mtime, ret, e;
      lc = {
        isCached: false
      };
      if (opt.settings.env === 'development') {
        lc.dev = true;
      }
      lc.useCache = true || opt.settings['view cache'];
      intl = opt.i18n ? path.join("intl", opt._locals.language) : '';
      viewdir = opt.viewdir, basedir = opt.basedir;
      pc = path.join(viewdir, intl, f.replace(basedir, '').replace(/\.pug$/, '.js'));
      startTime = Date.now();
      try {
        mtime = +fs.statSync(pc).mtime;
        if (!lc.useCache || !pugcache[pc] || mtime - pugcache[pc].mtime > 0) {
          ret = pugcache[pc] = {
            js: reload(pc),
            mtime: mtime
          };
        } else {
          lc.isCached = true;
          ret = pugcache[pc];
        }
        if (!ret.js) {
          throw new Error('');
        }
        ret = ret.js(opt);
        if (lc.dev) {
          log(f, opt, Date.now() - startTime, 'precompiled', lc.isCached);
        }
        return cb(null, ret);
      } catch (e$) {
        e = e$;
        return Promise.resolve().then(function(){
          lc.mtime = +fs.statSync(f).mtime;
          if (!lc.useCache || !pugcache[f] || lc.mtime - pugcache[f].mtime > 0) {
            return fsp.readFile(f).then(function(buf){
              return pugcache[f] = {
                buf: buf
              };
            });
          } else {
            return Promise.resolve(pugcache[f]);
          }
        }).then(function(obj){
          var ret, ref$;
          if (!(lc.isCached = obj.mtime != null && lc.useCache)) {
            obj.mtime = lc.mtime;
          }
          ret = pug.compileClient(obj.buf, import$((ref$ = import$({}, opt), ref$.filename = f, ref$.basedir = basedir, ref$), extapi));
          ret = " (function() { " + ret + "; module.exports = template; })() ";
          return fsExtra.ensureDir(path.dirname(pc)).then(function(){
            return fsp.writeFile(pc, ret);
          });
        }).then(function(){
          var ref$;
          return ref$ = pugcache[pc] || (pugcache[pc] = {}), ref$.js = reload(pc), ref$.mtime = lc.mtime, ref$;
        }).then(function(){
          var ret;
          ret = pugcache[pc].js(opt);
          if (lc.dev) {
            log(f, opt, Date.now() - startTime, 'from pug', lc.isCached);
          }
          return cb(null, ret);
        })['catch'](function(err){
          logger.error({
            err: err
          }, f.replace(opt.basedir, '') + " view rendering failed.");
          return cb(err, null);
        });
      }
    };
  };
  module.exports = pugViewEngine;
  function import$(obj, src){
    var own = {}.hasOwnProperty;
    for (var key in src) if (own.call(src, key)) obj[key] = src[key];
    return obj;
  }
}).call(this);
