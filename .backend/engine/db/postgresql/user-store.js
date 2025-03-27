// Generated by LiveScript 1.6.0
(function(){
  var crypto, bcrypt, lderror, re2, curegex, debounce, reEmail, isEmail, userStore;
  crypto = require('crypto');
  bcrypt = require('bcrypt');
  lderror = require('lderror');
  re2 = require('re2');
  curegex = require('curegex');
  debounce = require('@loadingio/debounce.js');
  reEmail = curegex.tw.get('email', re2);
  isEmail = function(it){
    return reEmail.exec(it);
  };
  userStore = function(opt){
    var pw, ref$, ref1$;
    opt == null && (opt = {});
    this.config = opt.config || {};
    this.policy = {
      login: (this.config.policy || {}).login || {},
      password: pw = (this.config.policy || {}).password || {}
    };
    pw.renew = !pw.renew || isNaN(pw.renew)
      ? 0
      : +((ref$ = pw.renew) >= 1
        ? ref$
        : pw.renew = 1);
    if (typeof pw.track === 'object') {
      pw.track.day = !pw.track.day || isNaN(pw.track.day)
        ? 0
        : +((ref1$ = (ref$ = pw.track).day) >= 1
          ? ref1$
          : ref$.day = 1);
      pw.track.count = !pw.track.count || isNaN(pw.track.count)
        ? 0
        : +((ref1$ = (ref$ = pw.track).count) >= 1
          ? ref1$
          : ref$.count = 1);
    } else {
      pw.track = {
        day: !pw.track || isNaN(pw.track)
          ? 0
          : +((ref$ = pw.track) >= 1
            ? ref$
            : pw.track = 1)
      };
    }
    this.db = opt.db;
    return this;
  };
  userStore.prototype = import$(Object.create(Object.prototype), {
    serialize: function(u){
      u == null && (u = {});
      return Promise.resolve(u);
    },
    deserialize: function(v){
      v == null && (v = {});
      return Promise.resolve(v);
    },
    hashing: function(password, doMD5, doBcrypt){
      doMD5 == null && (doMD5 = true);
      doBcrypt == null && (doBcrypt = true);
      return new Promise(function(res, rej){
        var pw, ret;
        pw = (password + "").substring(0, 256);
        ret = doMD5 ? crypto.createHash('md5').update(pw).digest('hex') : pw;
        if (doBcrypt) {
          return bcrypt.genSalt(12, function(e, salt){
            return bcrypt.hash(ret, salt, function(e, hash){
              return res(hash);
            });
          });
        } else {
          return res(ret);
        }
      });
    },
    compare: function(password, hash){
      password == null && (password = '');
      return new Promise(function(res, rej){
        var md5;
        md5 = crypto.createHash('md5').update(password).digest('hex');
        return bcrypt.compare(md5, hash, function(e, ret){
          if (ret) {
            return res();
          } else {
            return rej(new lderror(1012));
          }
        });
      });
    },
    get: function(arg$){
      var username, password, method, detail, create, inviteToken, this$ = this;
      username = arg$.username, password = arg$.password, method = arg$.method, detail = arg$.detail, create = arg$.create, inviteToken = arg$.inviteToken;
      username = username.toLowerCase();
      if (!isEmail(username)) {
        return Promise.reject(new lderror(1015));
      }
      return this.db.query("select * from users where username = $1", [username]).then(function(ret){
        var user;
        ret == null && (ret = {});
        if (!(user = (ret.rows || (ret.rows = []))[0]) && !create) {
          return lderror.reject(1034);
        }
        if (!user) {
          return this$.create({
            username: username,
            password: password,
            method: method,
            detail: detail,
            inviteToken: inviteToken
          });
        }
        if (!(method === 'local' || user.method === 'local')) {
          delete user.password;
          return user;
        }
        return this$.compare(password, user.password).then(function(){
          return user;
        });
      }).then(function(user){
        var ref$;
        if (((ref$ = user.config || (user.config = {})).consent || (ref$.consent = {})).cookie) {
          return user;
        }
        user.config.consent.cookie = new Date().getTime();
        return this$.db.query("update users set config = $2 where key = $1", [user.key, user.config]).then(function(){
          return user;
        });
      }).then(function(user){
        delete user.password;
        return user;
      });
    },
    create: function(arg$){
      var username, password, method, detail, config, inviteToken, force, policy, this$ = this;
      username = arg$.username, password = arg$.password, method = arg$.method, detail = arg$.detail, config = arg$.config, inviteToken = arg$.inviteToken, force = arg$.force;
      policy = this.policy.login;
      if (!force && policy.acceptSignup != null && (!policy.acceptSignup || policy.acceptSignup === 'no')) {
        return lderror.reject(1040);
      }
      username = username.toLowerCase();
      if (!config) {
        config = {};
      }
      if (!isEmail(username)) {
        return lderror.reject(1015);
      }
      return Promise.resolve().then(function(){
        if (method === 'local') {
          return this$.hashing(password);
        } else {
          return password;
        }
      }).then(function(password){
        var displayname, verified, user;
        displayname = detail ? detail.displayname || detail.username : void 8;
        if (!displayname) {
          displayname = username.replace(/@[^@]+$/, "");
        }
        verified = method === 'local' || !(policy && policy.oauthDefaultVerified)
          ? null
          : {
            date: Date.now()
          };
        (config.consent || (config.consent = {})).cookie = new Date().getTime();
        user = {
          username: username,
          password: password,
          method: method,
          displayname: displayname,
          detail: detail,
          config: config,
          createdtime: new Date()
        };
        if (verified) {
          user.verified = verified;
        }
        return this$.db.query("select key from users where username = $1", [username]).then(function(r){
          var p;
          r == null && (r = {});
          if ((r.rows || (r.rows = [])).length) {
            return lderror.reject(1014);
          }
          return p = force || policy.acceptSignup !== 'invite'
            ? Promise.resolve(null)
            : this$.db.query("select * from invitetoken where token = $1 and deleted is not true", [inviteToken]);
        }).then(function(r){
          var token, ttl, detail;
          if (r && !(token = (r.rows || (r.rows = []))[0])) {
            return lderror.reject(1043);
          }
          if (token.ttl && (isNaN(ttl = new Date(token.ttl).getTime()) || ttl <= Date.now())) {
            return lderror.reject(1043);
          }
          if (!token) {
            return;
          }
          detail = token.detail || {};
          if (!detail.count) {
            return;
          }
          if ((detail.used || 0) >= detail.count) {
            return lderror.reject(1004);
          }
          token.detail.used = token.detail.used + 1;
          (config.inviteToken || (config.inviteToken = {}))[inviteToken] = {
            createdtime: Date.now()
          };
          return this$.db.query("update invitetoken set detail = $2 where key = $1", [token.key, token.detail]);
        }).then(function(){
          return this$.db.query("insert into users (username,password,method,displayname,createdtime,detail,config,verified)\nvalues ($1,$2,$3,$4,$5,$6,$7,$8)\nreturning key", [username, password, method, displayname, new Date().toUTCString(), detail, config, verified]);
        }).then(function(r){
          r == null && (r = {});
          if (!(r = (r.rows || (r.rows = []))[0])) {
            return Promise.reject(500);
          }
          user.key = r.key;
          return this$.passwordTrack({
            user: user,
            hash: password
          });
        }).then(function(){
          return user;
        });
      });
    },
    passwordTrack: function(arg$){
      var user, password, hash, policy, this$ = this;
      user = arg$.user, password = arg$.password, hash = arg$.hash;
      policy = this.policy.password;
      if (!(policy.track.day || policy.track.count || policy.renew) || !(hash || password)) {
        return Promise.resolve();
      }
      return debounce(1000).then(function(){
        var that;
        if (that = hash) {
          return that;
        } else {
          return this.hashing(password);
        }
      }).then(function(hash){
        return this$.db.query("insert into password (owner, hash) values ($1, $2)", [user.key, hash]);
      }).then(function(){
        var count, ref$;
        count = (ref$ = policy.track.count) > 1 ? ref$ : 1;
        return this$.db.query("select key from password\nwhere owner = $1\norder by key desc limit $2", [user.key, count]).then(function(r){
          var p, ref$;
          r == null && (r = {});
          if (!(p = (ref$ = r.rows || (r.rows = []))[ref$.length - 1])) {
            return;
          }
          return this$.db.query("delete from password where owner = $1 and key < $2", [user.key, p.key]);
        });
      }).then(function(){
        var day, ref$;
        day = (ref$ = policy.track.day) > 1 ? ref$ : 1;
        return this$.db.query("delete from password\nwhere owner = $1 and createdtime < now() - make_interval(0,0,$2)", [user.key, day]);
      });
    },
    passwordDue: function(arg$){
      var user, policy;
      user = arg$.user;
      policy = this.policy.password;
      if (!policy.renew) {
        return Promise.resolve(-180 * 86400 * 1000);
      }
      return this.db.query("select * from password\nwhere owner = $1\norder by createdtime desc limit 1", [user.key]).then(function(r){
        var freq, now, checktime, entry;
        r == null && (r = {});
        freq = policy.renew * (86400 * 1000);
        now = Date.now();
        checktime = (entry = (r.rows || (r.rows = []))[0])
          ? Math.max(new Date(entry.snooze || 0).getTime(), new Date(entry.createdtime).getTime() + freq)
          : new Date(user.createdtime).getTime() + freq;
        return now - checktime;
      });
    },
    ensurePasswordUnused: function(arg$){
      var user, password, track, qs, params, ref$, this$ = this;
      user = arg$.user, password = arg$.password;
      track = this.policy.password.track;
      if (!(track.day || track.count)) {
        qs = "select * from password where owner = $1 order by key desc limit 1";
      } else {
        qs = "select * from password where owner = $1";
        if (track.day) {
          qs += " and createdtime >= now() - make_interval(0,0,0,$2)";
        }
        qs += " order by key desc";
        if (track.count) {
          qs += " limit $" + (track.day ? 3 : 2);
        }
      }
      params = [user.key].concat(track.day
        ? [(ref$ = track.day) > 1 ? ref$ : 1]
        : [], track.count
        ? [(ref$ = track.count) > 1 ? ref$ : 1]
        : []);
      return this.db.query(qs, params).then(function(r){
        var ps;
        r == null && (r = {});
        ps = (r.rows || (r.rows = [])).map(function(p){
          return this$.compare(password, p.hash).then(function(){
            return 1;
          })['catch'](function(){
            return 0;
          });
        });
        return Promise.all(ps);
      }).then(function(r){
        r == null && (r = []);
        if (r.filter(function(it){
          return it;
        }).length) {
          return lderror.reject(1036);
        }
      });
    }
  });
  module.exports = userStore;
  function import$(obj, src){
    var own = {}.hasOwnProperty;
    for (var key in src) if (own.call(src, key)) obj[key] = src[key];
    return obj;
  }
}).call(this);
