// Generated by LiveScript 1.6.0
(function(){
  var lderror, suuid, aux;
  lderror = require('lderror');
  suuid = require('@plotdb/suuid');
  aux = require('./aux');
  (function(it){
    return module.exports = it;
  })(function(backend){
    var config, route490, handler;
    config = backend.config;
    route490 = function(req, res, err){
      if (!/^\/api/.exec(req.originalUrl) && !/^\/err\/490/.exec(req.originalUrl)) {
        res.set({
          "Content-Type": "text/html",
          "X-Accel-Redirect": err.redirect || '/err/490'
        });
      } else {
        delete err.redirect;
      }
      res.cookie('lderror', JSON.stringify(err), {
        maxAge: 60000,
        httpOnly: false,
        secure: true,
        sameSite: 'Strict'
      });
      return res.status(490).send(err);
    };
    handler = function(err, req, res, next){
      var e;
      try {
        if (!err) {
          return next();
        }
        if (err.code === 'SESSIONCORRUPTED') {
          aux.clearCookie(req, res);
          err = lderror(1029);
          err.log = true;
        }
        if (err.code === 'EBADCSRFTOKEN') {
          err = lderror(1005);
        }
        err.uuid = suuid();
        if (backend.config.log.allError && !(lderror.id(err) && err.log)) {
          backend.logError.debug({
            err: (err._detail = {
              user: (req.user || {}).key || 0,
              ip: aux.ip(req),
              url: req.originalUrl
            }, err)
          }, "error logged in error handler (lderror id " + lderror.id(err) + ")");
        }
        if (lderror.id(err)) {
          if (err.log) {
            req.log.error({
              err: err
            }, ("exception logged [URL: " + req.originalUrl + "] " + (err.message ? ': ' + err.message : '') + " " + err.uuid).red);
          }
          delete err.stack;
          return route490(req, res, err);
        } else if (err instanceof URIError && (err.stack + "").startsWith('URIError: Failed to decode param')) {
          return res.status(400).send(err);
        }
      } catch (e$) {
        e = e$;
        req.log.error({
          err: e
        }, "exception occurred while handling other exceptions".red);
        req.log.error("original exception follows:".red);
      }
      req.log.error({
        err: err
      }, ("unhandled exception occurred [URL: " + req.originalUrl + "] " + (err.message ? ': ' + err.message : '') + " " + err.uuid).red);
      err = {
        id: err.id,
        name: err.name,
        uuid: err.uuid
      };
      if (!(err.name != null && err.id != null)) {
        err.name = 'lderror';
        err.id = 500;
      }
      return route490(req, res, err);
    };
    return handler;
  });
}).call(this);
