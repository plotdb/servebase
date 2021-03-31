// Generated by LiveScript 1.6.0
(function(){
  var expressSession, passport, passportLocal, passportFacebook, passportGoogleOauth20, lderror, aux, getUser, strategy, ret;
  expressSession = require('express-session');
  passport = require('passport');
  passportLocal = require('passport-local');
  passportFacebook = require('passport-facebook');
  passportGoogleOauth20 = require('passport-google-oauth20');
  lderror = require('lderror');
  aux = require('../../module/aux');
  getUser = function(arg$){
    var username, password, method, detail, create, done;
    username = arg$.username, password = arg$.password, method = arg$.method, detail = arg$.detail, create = arg$.create, done = arg$.done;
    return db.auth.user.get({
      username: username,
      password: password,
      method: method,
      detail: detail,
      create: create
    }).then(function(user){
      done(null, user);
    })['catch'](function(){
      done(new lderror(1012), null, {
        message: ''
      });
    });
  };
  strategy = {
    local: function(opt){
      return passport.use(new passportLocal.Strategy({
        usernameField: 'username',
        passwordField: 'password'
      }, function(username, password, done){
        return getUser({
          username: username,
          password: password,
          method: 'local',
          detail: null,
          create: false,
          done: done
        });
      }));
    },
    google: function(opt){
      return passport.use(new passportGoogleOauth20.Strategy({
        clientID: opt.clientID,
        clientSecret: opt.clientSecret,
        callbackURL: "/api/u/auth/google/callback",
        passReqToCallback: true,
        userProfileURL: 'https://www.googleapis.com/oauth2/v3/userinfo',
        profileFields: ['id', 'displayName', 'link', 'emails']
      }, function(request, accessToken, refreshToken, profile, done){
        if (!profile.emails) {
          done(null, false, {});
        } else {
          getUser(profile.emails[0].value, null, false, profile, true, done);
        }
      }));
    },
    facebook: function(opt){
      return passport.use(new passportFacebook.Strategy({
        clientID: opt.clientID,
        clientSecret: opt.clientSecret,
        callbackURL: "/api/u/auth/facebook/callback",
        profileFields: ['id', 'displayName', 'link', 'emails']
      }, function(accessToken, refreshToken, profile, done){
        if (!profile.emails) {
          done(null, false, {});
        } else {
          getUser(profile.emails[0].value, null, false, profile, true, done);
        }
      }));
    }
  };
  ret = function(backend){
    var db, app, config, route, sessionStore, session, x$;
    db = backend.db, app = backend.app, config = backend.config, route = backend.route;
    route.auth.get('/info', function(req, res){
      var ref$, payload, ref1$;
      res.setHeader('content-type', 'application/json');
      payload = JSON.stringify({
        csrfToken: req.csrfToken(),
        production: backend.production,
        ip: aux.ip(req),
        user: req.user
          ? {
            key: (ref1$ = req.user).key,
            config: ref1$.config,
            displayname: ref1$.displayname,
            verified: ref1$.verified,
            username: ref1$.username
          }
          : {},
        recaptcha: {
          sitekey: (ref$ = config.grecaptcha || (config.grecaptcha = {})).sitekey,
          enabled: ref$.enabled
        }
      });
      res.cookie('global', payload, {
        path: '/',
        secure: true
      });
      return res.send(payload);
    });
    ['local', 'google', 'facebook'].map(function(it){
      if (config[it]) {
        return strategy[it](config[it]);
      }
    });
    passport.serializeUser(function(u, done){
      db.auth.user.serialize(u).then(function(v){
        done(null, v);
      });
    });
    passport.deserializeUser(function(v, done){
      db.auth.user.deserialize(v).then(function(u){
        u == null && (u = {});
        done(null, u);
      });
    });
    sessionStore = function(){
      return import$(this, db.auth.session);
    };
    sessionStore.prototype = expressSession.Store.prototype;
    app.use(session = expressSession({
      secret: config.session.secret,
      resave: true,
      saveUninitialized: true,
      store: new sessionStore(),
      proxy: true,
      cookie: {
        path: '/',
        httpOnly: true,
        maxAge: 86400000 * 30 * 12
      }
    }));
    app.use(passport.initialize());
    app.use(passport.session());
    x$ = route.auth;
    x$.post('/signup', function(req, res, next){
      var ref$, username, displayname, password, config;
      ref$ = {
        username: (ref$ = req.body).username,
        displayname: ref$.displayname,
        password: ref$.password,
        config: ref$.config
      }, username = ref$.username, displayname = ref$.displayname, password = ref$.password, config = ref$.config;
      if (!username || !displayname || password.length < 8) {
        return next(new lderror(400));
      }
      return db.auth.user.create({
        username: username,
        password: password,
        method: 'local',
        detail: {
          displayname: displayname
        },
        config: config || {}
      }).then(function(user){
        req.logIn(user, function(){
          res.send();
        });
      })['catch'](function(){
        next(new lderror(403));
      });
    });
    x$.post('/login', function(req, res, next){
      return passport.authenticate('local', function(err, user, info){
        if (err || !user) {
          return next(err || new lderror(1000));
        }
        return req.logIn(user, function(err){
          if (err) {
            next(err);
          } else {
            res.send();
          }
        });
      })(req, res, next);
    });
    x$.post('/logout', function(req, res){
      req.logout();
      return res.send();
    });
    return x$;
  };
  module.exports = ret;
  function import$(obj, src){
    var own = {}.hasOwnProperty;
    for (var key in src) if (own.call(src, key)) obj[key] = src[key];
    return obj;
  }
}).call(this);
