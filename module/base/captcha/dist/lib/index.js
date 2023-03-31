// Generated by LiveScript 1.6.0
(function(){
  var request, lderror, aux, captcha, ref$;
  request = require('request');
  lderror = require('lderror');
  aux = require('@servebase/backend/aux');
  captcha = function(opt){
    opt == null && (opt = {});
    this.cfg = opt || {};
    this.middleware = this._middleware();
    return this;
  };
  captcha.prototype = (ref$ = Object.create(Object.prototype), ref$.verify = function(req, res, next){
    var obj, e, ref$, cfg;
    obj = req.body && req.body.captcha
      ? req.body.captcha
      : req.fields ? req.fields.captcha : null;
    if (typeof obj === 'string') {
      try {
        obj = JSON.parse(obj);
      } catch (e$) {
        e = e$;
      }
    }
    if (!(obj && obj.token)) {
      return Promise.resolve({
        score: 0,
        verified: false
      });
    }
    if (!((ref$ = obj.name) === 'hcaptcha' || ref$ === 'recaptcha_v3' || ref$ === 'recaptcha_v2_checkbox')) {
      return lderror.reject(1020);
    }
    if (!(cfg = this.cfg[obj.name])) {
      return lderror.reject(1020);
    }
    if (!(!(cfg.enabled != null) || cfg.enabled)) {
      return lderror.reject(1020);
    }
    return captcha.verifier[obj.name](req, res, cfg, obj);
  }, ref$._middleware = function(){
    var this$ = this;
    if (!(this.cfg && (!(this.cfg.enabled != null) || this.cfg.enabled))) {
      return function(req, res, next){
        return next();
      };
    }
    return function(req, res, next){
      return this$.verify(req, res, next).then(function(cap){
        if (!cap.score || cap.score < 0.5) {
          return next(lderror(1009));
        }
        return next();
      })['catch'](function(e){
        return next(e);
      });
    };
  }, ref$);
  captcha.verifier = {
    hcaptcha: function(req, res, config, capobj){
      return new Promise(function(resolve, reject){
        return request({
          url: 'https://hcaptcha.com/siteverify',
          method: 'POST',
          form: {
            secret: config.secret,
            response: capobj.token,
            remoteip: aux.ip(req)
          }
        }, function(e, r, b){
          var data, that;
          if (e) {
            reject(lderror(1010));
          }
          try {
            data = JSON.parse(b);
          } catch (e$) {
            e = e$;
            return reject(lderror.reject(1010));
          }
          return resolve({
            score: data.success
              ? 1
              : (that = data.score) ? that : 0,
            verified: true
          });
        });
      });
    },
    recaptcha_v2_checkbox: function(req, res, config, capobj){
      return new Promise(function(resolve, reject){
        return request({
          url: 'https://www.google.com/recaptcha/api/siteverify',
          method: 'POST',
          form: {
            secret: config.secret,
            response: capobj.token,
            remoteip: aux.ip(req)
          }
        }, function(e, r, b){
          var data, that;
          if (e) {
            return reject(lderror(1010));
          }
          try {
            data = JSON.parse(b);
          } catch (e$) {
            e = e$;
            return reject(lderror(1010));
          }
          if (data.success === false) {
            return reject(lderror(1009));
          }
          return resolve({
            score: data.success
              ? 1
              : (that = data.score) ? that : 0,
            verified: true
          });
        });
      });
    },
    recaptcha_v3: function(req, res, config, capobj){
      return new Promise(function(resolve, reject){
        return request({
          url: 'https://www.google.com/recaptcha/api/siteverify',
          method: 'POST',
          form: {
            secret: config.secret,
            response: capobj.token,
            remoteip: aux.ip(req)
          }
        }, function(e, r, b){
          var data;
          if (e) {
            return reject(lderror(1010));
          }
          try {
            data = JSON.parse(b);
          } catch (e$) {
            e = e$;
            return reject(lderror(1010));
          }
          if (data.success === false) {
            return reject(lderror(1009));
          }
          return resolve({
            score: data.score,
            verified: true
          });
        });
      });
    }
  };
  module.exports = captcha;
}).call(this);
