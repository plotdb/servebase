// Generated by LiveScript 1.6.0
(function(){
  (function(it){
    return module.exports = it;
  })(function(backend){
    var db, config, ref$, api, app, fs, path, express, lderror, re2, curegex, aux, session, throttle, route, reEmail, isEmail;
    db = backend.db, config = backend.config, ref$ = backend.route, api = ref$.api, app = ref$.app;
    if (config.base !== 'base') {
      return;
    }
    fs = require('fs');
    path = require('path');
    express = require('express');
    lderror = require('lderror');
    re2 = require('re2');
    curegex = require('curegex');
    aux = require('@servebase/backend/aux');
    session = require('@servebase/backend/session');
    throttle = require('@servebase/backend/throttle');
    route = aux.routecatch(express.Router({
      mergeParams: true
    }));
    api.use('/admin', route);
    route.use(aux.isAdmin);
    route.get('/cachestamp', function(req, res, next){
      return res.send(backend.cachestamp + "");
    });
    route.post('/cachestamp', function(req, res, next){
      backend.cachestamp = new Date().getTime();
      return res.send(backend.cachestamp + "");
    });
    route.get('/throttle/reset', function(req, res, next){
      throttle.reset();
      return res.send();
    });
    route.post('/users/', function(req, res, next){
      var keyword;
      if (!(keyword = req.body.keyword)) {
        return lderror.reject(400);
      }
      return db.query("select u.*\nfrom users as u\nwhere (u.username = $1 or u.key = $2) and u.deleted is not true\norder by u.createdtime desc", [
        keyword, isNaN(+keyword)
          ? null
          : +keyword
      ]).then(function(r){
        var rows;
        r == null && (r = {});
        rows = r.rows || (r.rows = []);
        rows.map(function(it){
          var ref$;
          return ref$ = it.password, delete it.password, ref$;
        });
        return res.send(rows);
      });
    });
    reEmail = curegex.tw.get('email', re2);
    isEmail = function(it){
      return reEmail.exec(it);
    };
    route.post('/user/', function(req, res){
      var ref$, username, displayname, password, detail, config, method;
      if (['username', 'displayname', 'password'].filter(function(it){
        return !req.body[it];
      }).length) {
        return lderror.reject(400);
      }
      ref$ = req.body, username = ref$.username, displayname = ref$.displayname, password = ref$.password;
      if (!isEmail(username)) {
        return lderror.reject(400);
      }
      if (password.length < 8) {
        return lderror.reject(400);
      }
      detail = {
        username: username,
        displayname: displayname
      };
      config = {};
      method = 'local';
      return db.userStore.create({
        username: username,
        password: password,
        method: method,
        detail: detail,
        config: config
      }).then(function(it){
        delete it.password;
        return res.send(it);
      });
    });
    route.post('/user/:key/password', aux.validateKey, function(req, res){
      var key, password;
      key = +req.params.key;
      if (!(password = req.body.password) || password.length < 8) {
        return lderror.reject(400);
      }
      return db.query("select password from users where key = $1", [key]).then(function(arg$){
        var rows;
        rows = arg$.rows;
        if (!rows || !rows[0]) {
          return lderror.reject(404);
        }
      }).then(function(){
        return db.userStore.hashing(password, true, true);
      }).then(function(pwHashed){
        return db.query("update users set (method,password) = ('local',$1) where key = $2", [pwHashed, key]);
      }).then(function(){
        return session['delete']({
          db: db,
          user: key
        });
      }).then(function(){
        return res.send();
      });
    });
    route.post('/user/:key/email', aux.validateKey, function(req, res){
      var key, email;
      key = +req.params.key;
      if (!((email = req.body.email) && isEmail(email))) {
        return lderror.reject(400);
      }
      return db.query("select key from users where username = $1", [email]).then(function(r){
        r == null && (r = {});
        if ((r.rows || (r.rows = [])).length) {
          return lderror.reject(1011);
        }
        return db.query("update users set username = $1 where key = $2", [email, key]);
      }).then(function(){
        return session['delete']({
          db: db,
          user: key
        });
      }).then(function(){
        return res.send();
      });
    });
    route.post('/user/:key/logout', aux.validateKey, function(req, res){
      return session['delete']({
        db: db,
        user: +req.params.key
      }).then(function(){
        return res.send();
      });
    });
    route['delete']('/user/:key', aux.validateKey, function(req, res, next){
      var key;
      key = +req.params.key;
      return db.query("delete from users where key = $1", [key])['catch'](function(){
        return db.query("update users\nset (username,displayname,deleted)\n= (('deleted-' || key),('user ' || key),true)\nwhere key = $1", [key]);
      }).then(function(){
        return res.send();
      });
    });
    return route.put('/su/:key', aux.validateKey, function(req, res){
      var key;
      key = +req.params.key;
      return session.login({
        db: db,
        key: key,
        req: req
      }).then(function(){
        return res.send();
      });
    });
  });
}).call(this);
