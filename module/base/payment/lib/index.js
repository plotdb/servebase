// Generated by LiveScript 1.6.0
(function(){
  (function(it){
    return module.exports = it;
  })(function(arg$){
    var route, perm, backend, db, cfg, gwinfo, path, lderror, https, aux, suuid, fs, fetch, log, mods, err, notifyHandler, doneHandler, gw;
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
      var slug;
      if (!(slug = req.body.slug)) {
        return lderror.reject(400);
      }
      return db.query("update payment set (state, paidtime) = ('complete', now()) where slug = $1\nreturning key", [req.body.slug]).then(function(r){
        r == null && (r = {});
        if ((r.rows || (r.rows = [])).length < 1) {
          return lderror.reject(400);
        }
        return res.send();
      });
    };
    doneHandler = function(req, res, next){
      return res.send('done.');
    };
    doneHandler = (route || {}).done || function(req, res){
      var fn;
      fn = path.join(path.dirname(__filename), '..', 'view/paid/index.pug');
      return res.render(fn, {});
    };
    backend.route.extapp.post('/pay/done', doneHandler);
    backend.route.extapi.post('/pay/notify', function(req, res, next){
      return notifyHandler(req, res, next);
    });
    backend.route.api.post('/pay/sign', aux.signedin, (perm || {}).sign || function(q, s, n){
      return n();
    }, function(req, res, next){
      var ref$, payload, gateway, ret;
      ref$ = req.body || {}, payload = ref$.payload, gateway = ref$.gateway;
      payload.slug = suuid();
      ret = {
        state: 'pending',
        slug: payload.slug
      };
      return Promise.resolve().then(function(){
        if (!(payload && gateway && mods[gateway] && mods[gateway].sign)) {
          return lderror.reject(1020);
        }
        return db.query("insert into payment (owner, scope, slug, gateway, state) values ($1,$2,$3,$4,$5)\nreturning key", [
          req.user.key, payload.scope, payload.slug, {
            gateway: gateway
          }, 'pending'
        ]);
      }).then(function(r){
        r == null && (r = {});
        ret.key = (r.rows || (r.rows = []))[0].key;
        return mods[gateway].sign({
          cfg: gwinfo,
          payload: payload
        });
      }).then(function(arg$){
        var payload;
        payload = arg$.payload;
        return res.send((ret.payload = payload, ret));
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
