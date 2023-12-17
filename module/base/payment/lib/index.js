// Generated by LiveScript 1.6.0
(function(){
  (function(it){
    return module.exports = it;
  })(function(arg$){
    var route, perm, backend, db, cfg, gwinfo, path, lderror, https, aux, suuid, fs, fetch, log, mods, err, notifyHandler, gw;
    route = arg$.route, perm = arg$.perm, backend = arg$.backend;
    db = backend.db;
    if (!(cfg = backend.config.payment)) {
      return;
    }
    if (!(gwinfo = (cfg.gateways || {})[cfg.gateway])) {
      return;
    }
    path = require('path');
    lderror = require('lderror');
    https = require('https');
    aux = require('@servebase/backend/aux');
    suuid = require('@plotdb/suuid');
    fs = require("fs-extra");
    fetch = require("node-fetch");
    log = backend.log.child({
      module: 'payment'
    });
    mods = {};
    try {
      mods[cfg.gateway] = require("./" + cfg.gateway);
    } catch (e$) {
      err = e$;
      log.error({
        err: err
      }, ("payment gateway `" + cfg.gateway + "` configured but failed to load.").red);
      return;
    }
    notifyHandler = function(req, res, next){
      return Promise.resolve().then(function(){
        if (!mods[cfg.gateway].notified) {
          return req.body;
        } else {
          return mods[cfg.gateway].notified({
            cfg: gwinfo,
            body: req.body || {}
          });
        }
      }).then(function(ret){
        var slug, key, obj;
        ret == null && (ret = {});
        if (!((slug = ret.slug) || (key = ret.key))) {
          return lderror.reject(400);
        }
        obj = {
          name: cfg.gateway,
          payload: ret.payload || {}
        };
        return db.query("update payment set (state, gateway, paidtime) = ($3, $2, now())\nwhere " + (slug != null ? 'slug = $1' : 'key = $1') + "\nreturning key", [slug != null ? slug : key, obj, ret.state || 'pending']).then(function(r){
          r == null && (r = {});
          if ((r.rows || (r.rows = [])).length < 1) {
            return lderror.reject(400);
          }
          return obj;
        });
      });
    };
    backend.route.extapi.post('/pay/notify', function(req, res, next){
      return notifyHandler(req, res, next).then(function(){
        return res.send();
      });
    });
    backend.route.extapp.post('/pay/done', function(req, res, next){
      return notifyHandler(req, res, next).then(function(obj){
        var fn;
        obj == null && (obj = {});
        fn = path.join(path.dirname(__filename), '..', 'view/done/index.pug');
        return res.render(fn, {
          exports: obj
        });
      });
    });
    backend.route.api.post('/pay/sign', aux.signedin, (perm || {}).sign || function(q, s, n){
      return n();
    }, function(req, res, next){
      var payload, gateway, mod, endpoint, ret;
      payload = (req.body || {}).payload;
      gateway = (req.body || {}).gateway || cfg.gateway;
      if (!(payload && gateway && (mod = mods[gateway]) && mod.sign)) {
        return lderror.reject(1020);
      }
      payload.slug = suuid();
      payload.email = req.user.username;
      endpoint = mod.endpoint || function(){
        return {};
      };
      ret = {
        state: 'pending',
        slug: payload.slug
      };
      return Promise.resolve().then(function(){
        return db.query("insert into payment (owner, scope, slug, payload, gateway, state) values ($1,$2,$3,$4,$5,$6)\nreturning key", [
          req.user.key, payload.scope, payload.slug, payload, {
            gateway: gateway
          }, 'pending'
        ]);
      }).then(function(r){
        r == null && (r = {});
        ret.key = (r.rows || (r.rows = []))[0].key;
        payload.key = ret.key;
        return mod.sign({
          cfg: gwinfo,
          payload: payload
        });
      }).then(function(arg$){
        var payload, ep, ref$;
        payload = arg$.payload;
        ep = endpoint({
          cfg: gwinfo,
          payload: payload
        }) || {};
        return res.send((ref$ = (ret.url = ep.url, ret.method = ep.method, ret), ref$.payload = payload, ref$));
      });
    });
    backend.route.api.post('/pay/check', aux.signedin, function(req, res, next){
      var payload;
      if (!(payload = req.body.payload)) {
        return lderror.reject(400);
      }
      return db.query("select state,createdtime,paidtime from payment where slug = $1", [payload.slug]).then(function(r){
        r == null && (r = {});
        return res.send((r.rows || (r.rows = []))[0] || {});
      });
    });
    if (cfg.gateway === 'dummy') {
      gw = mods.dummy.gateway;
      backend.route.extapi.post('/pay/gw/dummy/pay', gw.pay);
      backend.route.extapi.post('/pay/gw/dummy/notify', gw.notify || function(q, s, n){
        return n();
      }, notifyHandler);
      backend.route.extapi.post('/pay/gw/dummy/done', gw.done || function(q, s, n){
        return n();
      }, doneHandler);
      return backend.route.extapp.post('/pay/gw/dummy/', gw.page);
    }
  });
}).call(this);
