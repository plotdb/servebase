// Generated by LiveScript 1.6.0
(function(){
  var fs, chokidar, lderror, jsonwebtoken, expressSession, passport, passportLocal, passportFacebook, passportGoogleOauth20, passportLineAuth, aux, passwd, mail;
  fs = require('fs');
  chokidar = require('chokidar');
  lderror = require('lderror');
  jsonwebtoken = require('jsonwebtoken');
  expressSession = require('express-session');
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
    var db, app, config, route, captcha, k, v, limitSessionAmount, getUser, strategy, x$, this$ = this;
    db = backend.db, app = backend.app, config = backend.config, route = backend.route;
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
    limitSessionAmount = false;
    getUser = function(arg$){
      var username, password, method, detail, create, cb, req;
      username = arg$.username, password = arg$.password, method = arg$.method, detail = arg$.detail, create = arg$.create, cb = arg$.cb, req = arg$.req;
      return db.userStore.get({
        username: username,
        password: password,
        method: method,
        detail: detail,
        create: create
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
        e = lderror.id(e)
          ? e
          : lderror(500);
        return cb(e, null, {
          message: ''
        });
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
            req: req
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
              req: req
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
              req: req
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
              req: req
            });
          } catch (e$) {
            e = e$;
            console.log(e);
            cb(null, false, {});
          }
        }));
      }
    };
    this.version = 'na';
    chokidar.watch(['.version']).on('add', function(it){
      return this$.version = fs.readFileSync(it).toString();
    }).on('change', function(it){
      return this$.version = fs.readFileSync(it).toString();
    });
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
        version: this$.version,
        config: backend.config.client || {}
      });
      res.cookie('global', payload, {
        path: '/',
        secure: true
      });
      return res.send(payload);
    });
    ['local', 'google', 'facebook', 'line'].forEach(function(name){
      var x$;
      if (!(config.auth || (config.auth = {}))[name]) {
        return;
      }
      strategy[name](config.auth[name]);
      x$ = route.auth;
      x$.post("/" + name, passport.authenticate(name, {
        scope: config.auth[name].scope || ['profile', 'openid', 'email']
      }));
      x$.get("/" + name + "/callback", passport.authenticate(name, {
        successRedirect: '/auth?oauth-done',
        failureRedirect: '/auth?oauth-failed'
      }));
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
    app.use(backend.session = expressSession({
      secret: config.session.secret,
      resave: true,
      saveUninitialized: true,
      store: db.sessionStore,
      proxy: true,
      cookie: {
        path: '/',
        httpOnly: true,
        maxAge: config.session.maxAge
      }
    }));
    app.use(passport.initialize());
    app.use(passport.session());
    x$ = route.auth;
    x$.post('/signup', backend.middleware.captcha, function(req, res, next){
      var ref$, username, displayname, password, config;
      ref$ = {
        username: (ref$ = req.body).username,
        displayname: ref$.displayname,
        password: ref$.password,
        config: ref$.config
      }, username = ref$.username, displayname = ref$.displayname, password = ref$.password, config = ref$.config;
      if (!username || !displayname || password.length < 8) {
        return next(lderror(400));
      }
      return db.userStore.create({
        username: username,
        password: password,
        method: 'local',
        detail: {
          displayname: displayname
        },
        config: config || {}
      }).then(function(user){
        return this$.mail.verify({
          req: req,
          user: user
        })['catch'](function(err){
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
            res.send();
          }
        });
      })['catch'](function(){
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
            next(err);
          } else {
            res.send();
          }
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
        return new Promise(function(res, rej){
          return req.login(req.user, function(){
            return res();
          });
        });
      }).then(function(){
        return res.send();
      });
    });
    app.get('/auth/reset', function(req, res){
      aux.clearCookie(req, res);
      return req.logout(function(){
        res.render("auth/index.pug");
      });
    });
    app.post('/api/auth/clear', aux.signedin, backend.middleware.captcha, function(req, res){
      return db.query("delete from session where owner = $1", [req.user.key]).then(function(){
        aux.clearCookie(req, res);
        return req.logout(function(){
          res.send();
        });
      });
    });
    app.post('/api/auth/clear/:uid', aux.isAdmin, function(req, res){
      return db.query("delete from session where owner = $1", [req.params.uid]).then(function(){
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
}).call(this);
