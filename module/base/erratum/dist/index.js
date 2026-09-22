(function(){
  var erratum, ref$;
  erratum = function(o){
    var this$ = this;
    o == null && (o = {});
    if (typeof window == 'undefined' || window === null) {
      console.warn("[@servebase/erratum] no window to listen to error/rejection");
    }
    window.addEventListener('error', function(evt){
      return this$.errorHandler(evt);
    });
    window.addEventListener('unhandledrejection', function(evt){
      var e;
      try {
        return this$.rejectionHandler(evt);
      } catch (e$) {
        return e = e$;
      }
    });
    if (o.handler) {
      this.handler = o.handler;
    }
    this._lockdown = o.lockdown || null;
    this._locked = false;
    this._fired = false;
    return this;
  };
  erratum.prototype = (ref$ = Object.create(Object.prototype), ref$.handler = function(e){}, ref$.lockdown = function(v){
    var ref$;
    if (typeof v === 'function') {
      ref$ = [v, true], this._lockdown = ref$[0], v = ref$[1];
    }
    this._locked = !!(v && this._lockdown);
    if (!this._locked) {
      this._fired = false;
    }
    return this._locked;
  }, ref$.locked = function(){
    return this._locked;
  }, ref$._lock = function(e){
    var err;
    if (!this._locked) {
      return false;
    }
    if (this._fired) {
      return true;
    }
    this._fired = true;
    try {
      this._lockdown(e);
    } catch (e$) {
      err = e$;
      console.error("[@servebase/erratum] lockdown handler failed:", err);
    }
    return true;
  }, ref$.errorHandler = function(evt){
    if (this._lock(evt.error)) {
      return;
    }
    if (!lderror.eventHandler.error(evt)) {
      return this.handler(evt.error);
    }
  }, ref$.rejectionHandler = function(evt){
    if (this._lock(evt.reason)) {
      return;
    }
    if (!lderror.eventHandler.rejection(evt)) {
      return this.handler(evt.reason);
    }
  }, ref$.test = function(o){
    o == null && (o = {});
    if (o.bare) {
      return this._test(o);
    } else {
      return function(o){
        var this$ = this;
        return setTimeout(function(){
          return this$._test(o);
        }, 0);
      }(o);
    }
  }, ref$._test = function(o){
    if (o.promise) {
      return lderror.reject(1023);
    } else {
      throw lderror(1023);
    }
  }, ref$);
  if (typeof module != 'undefined' && module !== null) {
    module.exports = erratum;
  } else {
    window.erratum = erratum;
  }
}).call(this);
