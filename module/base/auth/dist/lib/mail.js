// Generated by LiveScript 1.6.0
(function(){
  var crypto, lderror, aux, throttle;
  crypto = require('crypto');
  lderror = require('lderror');
  aux = require('@servebase/backend/aux');
  throttle = require('@servebase/backend/throttle');
  (function(f){
    return module.exports = function(it){
      return f(it);
    };
  })(function(backend){
    var db, config, route, session, mdw, getmap;
    db = backend.db, config = backend.config, route = backend.route, session = backend.session;
    mdw = {
      throttle: throttle.kit.login,
      captcha: backend.middleware.captcha
    };
    getmap = function(req){
      var lngs, domain, sitename;
      lngs = backend.lngs(req);
      domain = config.domain || aux.hostname(req);
      sitename = config.sitename
        ? backend.i18n.t(config.sitename, {
          lngs: lngs,
          lng: lngs[0]
        })
        : config.domain || aux.hostname(req);
      return {
        sitename: sitename,
        domain: domain
      };
    };
    return {
      verify: function(arg$){
        var req, user, obj;
        req = arg$.req, user = arg$.user;
        obj = {};
        return backend.mailQueue.inBlacklist(user.username).then(function(ret){
          if (ret) {
            return lderror.reject(998);
          }
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
            var email, ret;
            email = user.username;
            if (/@g(oogle)?mail\.com$/.exec(email)) {
              ret = email.split('@');
              email = ret[0].replace(/(\+.*)$/, '').replace(/\./g, '') + ("@" + ret[1]);
            }
            return backend.mailQueue.byTemplate('mail-verify', email, import$({
              token: obj.hex
            }, getmap(req)), {
              now: true,
              lng: backend.lngs(req)[0]
            });
          });
        });
      },
      route: function(){
        var this$ = this;
        route.auth.post('/mail/verify', aux.signedin, mdw.throttle, mdw.captcha, function(req, res){
          return db.query("select key,verified from users where key = $1 and deleted is not true", [req.user.key]).then(function(r){
            var u;
            r == null && (r = {});
            if (!(u = (r.rows || (r.rows = []))[0])) {
              return lderror.reject(404);
            }
            if ((u.verified || (u.verified = {})).date) {
              return res.send({
                result: "verified"
              });
            }
            return this$.verify({
              req: req,
              user: req.user
            }).then(function(){
              return res.send({
                result: "sent"
              });
            })['catch'](function(e){
              if (lderror.id(e) === 998) {
                return res.send({
                  result: "skipped"
                });
              }
              return Promise.reject(e);
            });
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
              return lderror.reject(1013);
            }
            lc.obj = r.rows[0];
            return db.query("delete from mailverifytoken where owner = $1", [lc.obj.owner]);
          }).then(function(){
            var tick, verified;
            tick = parseInt(((config.policy || {}).tokenExpire || {}).mailVerify);
            if (isNaN(tick) || tick < 0) {
              tick = 600;
            }
            if (new Date().getTime() - new Date(lc.obj.time).getTime() > 1000 * tick) {
              return lderror.reject(1013);
            }
            lc.verified = verified = {
              date: Date.now()
            };
            return db.query("update users set verified = $2 where key = $1", [lc.obj.owner, JSON.stringify(verified)]);
          }).then(function(){
            return db.query("select * from users where key = $1", [lc.obj.owner]).then(function(r){
              var u;
              r == null && (r = {});
              if (!(u = (r.rows || (r.rows = []))[0])) {
                return;
              }
              u.verified = lc.verified;
              return session.sync({
                req: req,
                user: lc.obj.owner,
                obj: u
              });
            });
          }).then(function(){
            return res.redirect('/auth/?mail-verified');
          })['catch'](function(e){
            if (lderror.id(e) !== 1013) {
              return Promise.reject(e);
            } else {
              return res.redirect('/auth/?mail-expire');
            }
          });
        });
      }
    };
  });
  function import$(obj, src){
    var own = {}.hasOwnProperty;
    for (var key in src) if (own.call(src, key)) obj[key] = src[key];
    return obj;
  }
}).call(this);
