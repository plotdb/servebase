// Generated by LiveScript 1.6.0
(function(){
  (function(it){
    return module.exports = it;
  })(function(backend){
    var lib, e;
    if (!backend.config.payment) {
      return;
    }
    try {
      lib = require('@servebase/payment/lib');
      return lib({
        backend: backend
      });
    } catch (e$) {
      e = e$;
      return backend.logServer.error("payment configured but payment module is not installed");
    }
  });
}).call(this);
