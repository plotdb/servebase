// Generated by LiveScript 1.6.0
(function(){
  var fs, fsExtra, crypto, lderror, aux, session, throttle, captcha;
  fs = require('fs');
  fsExtra = require('fs-extra');
  crypto = require('crypto');
  lderror = require('lderror');
  aux = require('@servebase/backend/aux');
  session = require('@servebase/backend/session');
  throttle = require('@servebase/backend/throttle');
  captcha = require('@servebase/captcha');
  (function(f){
    return module.exports = function(it){
      return f(it);
    };
  })(function(backend){
    var db, config, route, mdw, getmap, verifyEmail;
    db = backend.db, config = backend.config, route = backend.route;
    mdw = {
      throttle: throttle.kit.login,
      captcha: backend.middleware.captcha
    };
    getmap = function(req){
      return {
        sitename: config.sitename || config.domain || aux.hostname(req),
        domain: config.domain || aux.hostname(req)
      };
    };
    verifyEmail = function(arg$){
      var req, io, user, obj;
      req = arg$.req, io = arg$.io, user = arg$.user;
      obj = {};
      return Promise.resolve().then(function(){
        var time;
        time = new Date();
        obj.key = user.key;
        obj.hex = (user.key + "-") + crypto.randomBytes(30).toString('hex');
        obj.time = time;
        return db.query("delete from mailverifytoken where owner=$1", [obj.key]);
      }).then(function(){
        return db.query("insert into mailverifytoken (owner,token,time) values ($1,$2,$3)", [obj.key, obj.hex, obj.time]);
      }).then(function(){
        return backend.mailQueue.byTemplate('mail-verify', user.username, import$({
          token: obj.hex
        }, getmap(req)), {
          now: true
        });
      });
    };
    route.auth.post('/mail/verify', aux.signedin, mdw.throttle, mdw.captcha, function(req, res){
      return db.query("select key from users where key = $1 and deleted is not true", [req.user.key]).then(function(r){
        r == null && (r = {});
        if (!(r.rows || (r.rows = [])).length) {
          return lderror.reject(404);
        }
        return verifyEmail({
          req: req,
          user: req.user,
          db: db
        });
      }).then(function(){
        return res.send();
      });
    });
    return route.app.get('/auth/mail/verify/:token', function(req, res){
      var lc, token;
      lc = {};
      if (!(token = req.params.token)) {
        return lderror.reject(400);
      }
      return db.query("select owner,time from mailverifytoken where token = $1", [token]).then(function(r){
        r == null && (r = {});
        if (!(r.rows || (r.rows = [])).length) {
          return lderror.reject(403);
        }
        lc.obj = r.rows[0];
        return db.query("delete from mailverifytoken where owner = $1", [lc.obj.owner]);
      }).then(function(){
        var verified;
        if (new Date().getTime() - new Date(lc.obj.time).getTime() > 1000 * 600) {
          return lderror.reject(1013);
        }
        lc.verified = verified = {
          date: Date.now()
        };
        db.query("update users set verified = $2 where key = $1", [lc.obj.owner, JSON.stringify(verified)]);
        if (req.user && req.user.key === lc.obj.owner) {
          return session.login({
            db: db,
            key: req.user.key,
            req: req
          });
        }
      }).then(function(){
        return db.query("select * from users where key = $1", [lc.obj.owner]).then(function(r){
          var u;
          r == null && (r = {});
          if (!(u = (r.rows || (r.rows = []))[0])) {
            return;
          }
          u.verified = lc.verified;
          return db.query("update sessions set detail = jsonb_set(detail, '{passport,user}', ($1)::jsonb)\nwhere (detail->'passport'->'user'->>'key')::int = $2", [JSON.stringify(u), lc.obj.owner]);
        });
      }).then(function(){
        return res.redirect('/auth/mail/verified/');
      })['catch'](function(e){
        if (lderror.id(e) !== 1013) {
          return Promise.reject(e);
        } else {
          return res.redirect('/auth/mail/expire/');
        }
      });
    });
  });
  function import$(obj, src){
    var own = {}.hasOwnProperty;
    for (var key in src) if (own.call(src, key)) obj[key] = src[key];
    return obj;
  }
}).call(this);
