// Generated by LiveScript 1.6.0
(function(){
  var connector, ref$;
  connector = function(opt){
    opt == null && (opt = {});
    this.ws = null;
    this._running = false;
    this._tag = "[@servebase/connector]";
    this._init = opt.init;
    this._ldcv = opt.ldcv || function(){};
    this._error = opt.error || null;
    this._reconnect = opt.reconnect;
    this._path = opt.path || '/ws';
    this.hub = {};
    return this;
  };
  connector.prototype = (ref$ = Object.create(Object.prototype), ref$.open = function(){
    var this$ = this;
    console.log(this._tag + " ws reconnect ...");
    return this.ws.connect().then(function(){
      return console.log(this$._tag + " object reconnect ...");
    }).then(function(){
      if (this$._reconnect) {
        return this$._reconnect();
      }
    }).then(function(){
      return console.log(this$._tag + " connected.");
    })['catch'](function(e){
      if (this$._error && typeof this$._error === 'function') {
        return this$._error(e);
      }
      return Promise.reject(e);
    })['catch'](function(e){
      return Promise.reject(e);
    });
  }, ref$.reopen = function(){
    var this$ = this;
    if (this._running) {
      return;
    }
    this._running = true;
    if (this._ldcv.toggle) {
      this._ldcv.toggle(true);
    } else {
      this._ldcv(true);
    }
    return debounce(1000).then(function(){
      return this$.open();
    }).then(function(){
      return debounce(350);
    }).then(function(){
      if (this$._ldcv.toggle) {
        return this$._ldcv.toggle(false);
      } else {
        return this$._ldcv(false);
      }
    }).then(function(){
      return this$._running = false;
    });
  }, ref$.init = function(){
    var this$ = this;
    this.ws = new ews({
      path: this._path
    });
    this.ws.on('offline', function(){
      return this$.reopen();
    });
    this.ws.on('close', function(){
      return this$.reopen();
    });
    if (this._init) {
      this._init();
    }
    return this.open();
  }, ref$);
  if (typeof module != 'undefined' && module !== null) {
    module.connector = connector;
  } else if (typeof window != 'undefined' && window !== null) {
    window.connector = connector;
  }
}).call(this);
