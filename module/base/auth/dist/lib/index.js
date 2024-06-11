// Generated by LiveScript 1.6.0
(function(){
  var lderror, jsonwebtoken, expressSession, passport, passportLocal, passportFacebook, passportGoogleOauth20, passportLineAuth, aux, passwd, mail;
  lderror = require('lderror');
  jsonwebtoken = require('jsonwebtoken');
  expressSession = require('@plotdb/express-session');
  passport = require('passport');
  passportLocal = require('passport-local');
  passportFacebook = require('passport-facebook');
  passportGoogleOauth20 = require('passport-google-oauth20');
  passportLineAuth = require('passport-line-auth');
  aux = require('@servebase/backend/aux');
  passwd = require('./passwd');
  mail = require('./mail');
  (function(f){
    return module.exports = function(it){
      return f.call({}, it);
    };
  })(function(backend){
    var db, app, config, route, session, captcha, k, v, oauth, policy, ref$, ref1$, limitSessionAmount, getUser, strategy, injectInviteToken, x$, this$ = this;
    db = backend.db, app = backend.app, config = backend.config, route = backend.route, session = backend.session;
    captcha = Object.fromEntries((function(){
      var ref$, results$ = [];
      for (k in ref$ = config.captcha) {
        v = ref$[k];
        results$.push([k, v]);
      }
      return results$;
    }()).map(function(it){
      var ref$;
      if (it[0] === 'enabled') {
        return [it[0], it[1]];
      } else {
        return [
          it[0], {
            sitekey: (ref$ = it[1]).sitekey,
            enabled: ref$.enabled
          }
        ];
      }
    }));
    oauth = Object.fromEntries((function(){
      var ref$, results$ = [];
      for (k in ref$ = config.auth) {
        v = ref$[k];
        results$.push([k, v]);
      }
      return results$;
    }()).map(function(it){
      return it[0] === 'local'
        ? null
        : [
          it[0], {
            enabled: !(it[1].enabled != null) || it[1].enabled
          }
        ];
    }).filter(function(it){
      return it;
    }));
    policy = {};
    if (((ref$ = (ref1$ = backend.config).policy || (ref1$.policy = {})).login || (ref$.login = {})).acceptSignup != null) {
      (policy.login || (policy.login = {})).acceptSignup = backend.config.policy.login.acceptSignup;
    }
    limitSessionAmount = false;
    this.user = {
      'delete': function(arg$){
        var key, username;
        key = arg$.key, username = arg$.username;
        if (!(key || username)) {
          return lderror.rejrect(400);
        }
        if (username) {
          username = (username + "").trim().toLowerCase();
        }
        return db.query("select username,key from users\nwhere deleted is not true and\n" + (key ? 'key = $1' : 'username = $1'), [key ? key : username]).then(function(r){
          var u;
          r == null && (r = {});
          if (!(u = (r.rows || (r.rows = []))[0])) {
            return lderror.reject(404);
          }
          return session['delete']({
            user: u.key
          }).then(function(){
            return db.query("update users\nset (username,displayname,method,password,deleted)\n= ($2, $3, 'local', '', true)\nwhere key = $1", [u.key, "deleted(" + u.username + ")/" + u.key, "(deleted user " + u.key + ")"]);
          });
        });
      }
    };
    getUser = function(arg$){
      var username, password, method, detail, create, inviteToken, cb, req;
      username = arg$.username, password = arg$.password, method = arg$.method, detail = arg$.detail, create = arg$.create, inviteToken = arg$.inviteToken, cb = arg$.cb, req = arg$.req;
      return db.userStore.get({
        username: username,
        password: password,
        method: method,
        detail: detail,
        create: create,
        inviteToken: inviteToken
      }).then(function(user){
        db.query("select count(ip) from session where owner = $1 group by ip", [user.key]).then(function(r){
          r == null && (r = {});
          if (limitSessionAmount && (((r.rows || (r.rows = []))[0] || {}).count || 1) > 1) {
            return cb(lderror(1004), null, {
              message: ''
            });
          } else {
            return cb(null, (user.ip = aux.ip(req), user));
          }
        });
      })['catch'](function(e){
        var ref$;
        if (e && ((ref$ = config.policy || (config.policy = {})).login || (ref$.login = {})).logging) {
          backend.logSecurity.info("login fail " + method + " method " + username + " eid " + e.id + "/" + e.message);
        }
        if ((ref$ = lderror.id(e)) === 1000 || ref$ === 1004 || ref$ === 1012 || ref$ === 1015 || ref$ === 1034 || ref$ === 1040 || ref$ === 1043) {
          return cb(e, false);
        }
        console.log(e);
        return cb(lderror(500));
      });
    };
    strategy = {
      local: function(opt){
        return passport.use(new passportLocal.Strategy({
          usernameField: 'username',
          passwordField: 'password',
          passReqToCallback: true
        }, function(req, username, password, cb){
          return getUser({
            username: username,
            password: password,
            method: 'local',
            detail: null,
            create: false,
            cb: cb,
            req: req,
            inviteToken: req.session.inviteToken
          });
        }));
      },
      google: function(opt){
        return passport.use(new passportGoogleOauth20.Strategy({
          clientID: opt.clientID,
          clientSecret: opt.clientSecret,
          callbackURL: "/api/auth/google/callback",
          passReqToCallback: true,
          userProfileURL: 'https://www.googleapis.com/oauth2/v3/userinfo',
          profileFields: ['id', 'displayName', 'link', 'emails']
        }, function(req, accessToken, refreshToken, profile, cb){
          if (!profile.emails) {
            cb(null, false, {});
          } else {
            getUser({
              username: profile.emails[0].value,
              password: null,
              method: 'google',
              detail: profile,
              create: true,
              cb: cb,
              req: req,
              inviteToken: req.session.inviteToken
            });
          }
        }));
      },
      facebook: function(opt){
        return passport.use(new passportFacebook.Strategy({
          clientID: opt.clientID,
          clientSecret: opt.clientSecret,
          passReqToCallback: true,
          callbackURL: "/api/auth/facebook/callback",
          profileFields: ['id', 'displayName', 'link', 'emails']
        }, function(req, accessToken, refreshToken, profile, cb){
          if (!profile.emails) {
            cb(null, false, {});
          } else {
            getUser({
              username: profile.emails[0].value,
              password: null,
              method: 'facebook',
              detail: profile,
              create: true,
              cb: cb,
              req: req,
              inviteToken: req.session.inviteToken
            });
          }
        }));
      },
      line: function(opt){
        return passport.use(new passportLineAuth.Strategy({
          channelID: opt.channelID,
          channelSecret: opt.channelSecret,
          callbackURL: "/api/auth/line/callback",
          scope: ['profile', 'openid', 'email'],
          botPrompt: 'normal',
          passReqToCallback: true,
          prompt: 'consent',
          uiLocales: 'zh-TW'
        }, function(req, accessToken, refreshToken, params, profile, cb){
          var ret, e;
          try {
            ret = jsonwebtoken.verify(params.id_token, opt.channelSecret);
            if (!(ret && ret.email)) {
              throw new Error('');
            }
            getUser({
              username: ret.email,
              password: null,
              method: 'line',
              detail: profile,
              create: true,
              cb: cb,
              req: req,
              inviteToken: req.session.inviteToken
            });
          } catch (e$) {
            e = e$;
            console.log(e);
            cb(null, false, {});
          }
        }));
      }
    };
    route.auth.get('/info', function(req, res){
      var payload, ref$;
      res.setHeader('content-type', 'application/json');
      payload = JSON.stringify({
        csrfToken: req.csrfToken(),
        production: backend.production,
        ip: aux.ip(req),
        user: req.user
          ? {
            key: (ref$ = req.user).key,
            config: ref$.config,
            plan: ref$.plan,
            displayname: ref$.displayname,
            verified: ref$.verified,
            username: ref$.username,
            staff: ref$.staff
          }
          : {},
        captcha: captcha,
        oauth: oauth,
        policy: policy,
        version: backend.version,
        cachestamp: backend.cachestamp,
        config: backend.config.client || {}
      });
      res.cookie('global', payload, {
        path: '/',
        secure: true
      });
      return res.send(payload);
    });
    injectInviteToken = function(req, res, next){
      var t;
      if (req.body && (t = req.body.inviteToken)) {
        req.session.inviteToken = t;
      }
      return next();
    };
    ['local', 'google', 'facebook', 'line'].forEach(function(name){
      var x$;
      if (!(config.auth || (config.auth = {}))[name]) {
        return;
      }
      strategy[name](config.auth[name]);
      x$ = route.auth;
      x$.post("/" + name, injectInviteToken, passport.authenticate(name, {
        scope: config.auth[name].scope || ['profile', 'openid', 'email']
      }));
      x$.get("/" + name + "/callback", function(name){
        return function(req, res, next){
          return passport.authenticate(name, function(e, u, i){
            if (e) {
              return res.redirect("/auth?oauth-failed&code=" + lderror.id(e));
            }
            if (!u) {
              return res.redirect('/auth?oauth-failed');
            }
            return req.logIn(u, function(e){
              if (e) {
                return next(e);
              }
              return res.redirect('/auth?oauth-done');
            });
          })(req, res, next);
        };
      }(name));
      return x$;
    });
    passport.serializeUser(function(u, done){
      db.userStore.serialize(u).then(function(v){
        done(null, v);
      });
    });
    passport.deserializeUser(function(v, done){
      db.userStore.deserialize(v).then(function(u){
        u == null && (u = {});
        done(null, u);
      });
    });
    app.use(function(req, res, next){
      var c, cs;
      c = (req.headers || {}).cookie || '';
      cs = c.split(/;/).filter(function(it){
        return /^connect.sid=/.exec(it.trim());
      });
      return cs.length > 1
        ? next({
          code: 'SESSIONCORRUPTED'
        })
        : next();
    });
    app.use(backend.session.middleware(expressSession({
      secret: config.session.secret,
      resave: true,
      saveUninitialized: true,
      store: db.sessionStore,
      proxy: true,
      cookie: import$({
        path: '/',
        httpOnly: true,
        maxAge: config.session.maxAge
      }, config.session.includeSubDomain
        ? {
          domain: "." + config.domain
        }
        : {})
    })));
    app.use(passport.initialize());
    app.use(passport.session());
    x$ = route.auth;
    x$.post('/signup', backend.middleware.captcha, function(req, res, next){
      var ref$, username, displayname, password, inviteToken;
      ref$ = {
        username: (ref$ = req.body).username,
        displayname: ref$.displayname,
        password: ref$.password,
        inviteToken: ref$.inviteToken
      }, username = ref$.username, displayname = ref$.displayname, password = ref$.password, inviteToken = ref$.inviteToken;
      if (!username || !displayname || password.length < 8) {
        return next(lderror(400));
      }
      return db.userStore.create({
        username: username,
        password: password,
        inviteToken: inviteToken,
        method: 'local',
        detail: {
          displayname: displayname
        },
        config: req.body.config || {}
      }).then(function(user){
        var ref$;
        if (((ref$ = config.policy || (config.policy = {})).login || (ref$.login = {})).skipVerify) {
          return user;
        }
        return this$.mail.verify({
          req: req,
          user: user
        })['catch'](function(err){
          if (lderror.id(err) === 998) {
            return user;
          }
          return backend.logMail.error({
            err: err
          }, ("send mail verification mail failed (" + username + ")").red);
        }).then(function(){
          return user;
        });
      }).then(function(user){
        req.login(user, function(err){
          if (err) {
            next(err);
          } else {
            res.send({});
          }
        });
      })['catch'](function(e){
        var ref$;
        if ((ref$ = lderror.id(e)) === 1004 || ref$ === 1014 || ref$ === 1040 || ref$ === 1043) {
          return next(e);
        }
        console.error(e);
        next(lderror(403));
      });
    });
    x$.post('/login', backend.middleware.captcha, function(req, res, next){
      return passport.authenticate('local', function(err, user, info){
        if (err || !user) {
          return next(err || lderror(1000));
        }
        return req.login(user, function(err){
          if (err) {
            return next(err);
          }
          db.userStore.passwordDue({
            user: user
          }).then(function(span){
            return res.send(span > 0
              ? {
                passwordDue: span,
                passwordShouldRenew: span > 0
              }
              : {});
          });
        });
      })(req, res, next);
    });
    x$.post('/logout', function(req, res){
      return req.logout(function(){
        res.send();
      });
    });
    route.auth.put('/user', aux.signedin, backend.middleware.captcha, function(req, res, next){
      var ref$, k, v, ref1$, displayname, description, title, tags;
      ref1$ = (function(){
        var ref$, results$ = [];
        for (k in ref$ = {
          displayname: (ref$ = req.body).displayname,
          description: ref$.description,
          title: ref$.title,
          tags: ref$.tags
        }) {
          v = ref$[k];
          results$.push({
            k: k,
            v: v
          });
        }
        return results$;
      }()).filter(function(it){
        return it.v != null;
      }).map(function(it){
        return ((it.v || '') + "").trim();
      }), displayname = ref1$[0], description = ref1$[1], title = ref1$[2], tags = ref1$[3];
      if (!displayname) {
        return lderror.reject(400);
      }
      return db.query("update users set (displayname,description,title,tags) = ($1,$2,$3,$4) where key = $5", [displayname, description, title, tags, req.user.key]).then(function(){
        var ref$;
        return ref$ = req.user, ref$.displayname = displayname, ref$.description = description, ref$.title = title, ref$.tags = tags, ref$;
      }).then(function(){
        return session.sync({
          req: req,
          user: req.user.key,
          obj: req.user
        });
      }).then(function(){
        return res.send();
      });
    });
    route.auth.post('/user/delete', aux.signedin, backend.middleware.captcha, function(req, res){
      if (!(req.user && req.user.key)) {
        return lderror.rejrect(400);
      }
      return this$.user['delete']({
        key: req.user.key
      }).then(function(){
        return req.logout(function(){
          return res.send();
        });
      });
    });
    app.get('/auth/reset', function(req, res){
      aux.clearCookie(req, res);
      return req.logout(function(){
        res.render("auth/index.pug");
      });
    });
    app.post('/api/auth/clear', aux.signedin, backend.middleware.captcha, function(req, res){
      return session['delete']({
        user: req.user.key
      }).then(function(){
        aux.clearCookie(req, res);
        return req.logout(function(){
          res.send();
        });
      });
    });
    app.post('/api/auth/clear/:uid', aux.isAdmin, function(req, res){
      return session['delete']({
        user: req.params.uid
      }).then(function(){
        return res.send();
      });
    });
    app.post('/api/auth/reset', function(req, res){
      aux.clearCookie(req, res);
      return req.logout(function(){
        res.send();
      });
    });
    this.passwd = passwd(backend);
    this.mail = mail(backend);
    this.passwd.route();
    this.mail.route();
    return this;
  });
  function import$(obj, src){
    var own = {}.hasOwnProperty;
    for (var key in src) if (own.call(src, key)) obj[key] = src[key];
    return obj;
  }
}).call(this);
