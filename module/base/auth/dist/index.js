// Generated by LiveScript 1.6.0
(function(){
  (function(it){
    return it.apply({});
  })(function(){
    var lc, getGlobal, auth;
    lc = {};
    getGlobal = proxise(function(a){
      if (lc.global) {
        return Promise.resolve(lc.global);
      } else if (lc.fetching) {
        return;
      }
      if (a) {
        return a.fetch();
      }
    });
    auth = function(opt){
      var ref$, this$ = this;
      opt == null && (opt = {});
      this._manager = opt.manager;
      this.timeout = {
        loader: 1000,
        failed: 10000
      };
      this.evtHandler = {};
      this.ui = {
        loader: opt.loader || {
          on: function(){},
          off: function(){},
          cancel: function(){}
        },
        authpanel: function(tgl, o){
          var bid;
          o == null && (o = {});
          if (this$._authpanel) {
            return this$._authpanel(tgl, o);
          }
          this$.ui.loader.on(350);
          bid = opt.authpanel || {
            name: "@servebase/auth"
          };
          return this$._manager.from(bid, {
            root: document.body,
            data: {
              auth: this$,
              zmgr: opt.zmgr
            }
          }).then(function(p){
            return this$._authpanel = p['interface'];
          }).then(function(i){
            this$.ui.loader.off();
            return i(tgl, o);
          });
        },
        timeout: function(){
          return new Promise(function(res, rej){});
        }
      };
      if (!this._apiRoot) {
        this._apiRoot = opt.api || "/api/auth";
      }
      if ((ref$ = this._apiRoot)[ref$.length - 1] !== '/') {
        this._apiRoot += '/';
      }
      if (opt.initFetch == null || opt.initFetch) {
        this.fetch();
      }
      return this;
    };
    auth.prototype = import$(Object.create(Object.prototype), {
      on: function(n, cb){
        var this$ = this;
        return (Array.isArray(n)
          ? n
          : [n]).map(function(n){
          var ref$;
          return ((ref$ = this$.evtHandler)[n] || (ref$[n] = [])).push(cb);
        });
      },
      fire: function(n){
        var v, res$, i$, to$, ref$, len$, cb, results$ = [];
        res$ = [];
        for (i$ = 1, to$ = arguments.length; i$ < to$; ++i$) {
          res$.push(arguments[i$]);
        }
        v = res$;
        for (i$ = 0, len$ = (ref$ = this.evtHandler[n] || []).length; i$ < len$; ++i$) {
          cb = ref$[i$];
          results$.push(cb.apply(this, v));
        }
        return results$;
      },
      inject: function(){
        return {};
      },
      apiRoot: function(){
        return this._apiRoot;
      },
      setUi: function(it){
        return import$(this.ui, it || {});
      },
      logout: function(){
        var this$ = this;
        this.ui.loader.on();
        return ld$.fetch(this.apiRoot() + "logout", {
          method: 'post'
        }, {}).then(function(){
          return this$.fetch({
            renew: true
          });
        })['finally'](function(){
          return this$.ui.loader.off();
        }).then(function(){
          return this$.fire('logout');
        })['catch'](function(e){
          return this$.fire('error', e);
        });
      },
      reset: function(){
        this.ui.loader.on();
        return window.location.href = "/auth/reset";
      },
      ensure: function(opt){
        opt == null && (opt = {});
        return this.get((opt.authedOnly = true, opt));
      },
      get: function(opt){
        var this$ = this;
        opt == null && (opt = {
          authedOnly: false
        });
        return getGlobal(this).then(function(g){
          g == null && (g = {});
          if (!opt.authedOnly) {
            return g;
          }
          if (!(g.user || (g.user = {})).key) {
            return this$.ui.authpanel(true, opt).then(function(){
              return getGlobal(this);
            });
          }
        }).then(function(g){
          g == null && (g = {});
          if (opt.authedOnly && !(g.user || (g.user = {})).key) {
            return Promise.reject(new lderror(1000));
          }
          return g;
        });
      },
      fetch: function(opt){
        var ret, promise, this$ = this;
        opt == null && (opt = {
          renew: true
        });
        lc.fetching = true;
        this.ui.loader.on(this.timeout.loader);
        this.watchdog = debounce(this.timeout.failed, function(){
          this$.ui.loader.off();
          return this$.ui.timeout().then(function(){
            return this$.ui.loader.on();
          }).then(function(){
            return debounce(10000);
          }).then(function(){
            return this$.fetch();
          });
        })();
        ret = !opt.renew && /global=/.exec(document.cookie) ? document.cookie.split(';').map(function(it){
          return /^global=(.+)/.exec(it.trim());
        }).filter(function(it){
          return it;
        })[0] : null;
        promise = ret
          ? Promise.resolve(JSON.parse(decodeURIComponent(ret[1])))
          : ld$.fetch(this.apiRoot() + "info", {}, {
            type: 'json'
          });
        return promise['finally'](function(g){
          this$.watchdog.cancel();
          this$.ui.loader.cancel();
          return this$.ui.loader.off();
        }).then(function(g){
          var ref$, e;
          lc.fetching = false;
          ((ref$ = ld$.fetch).headers || (ref$.headers = {}))['X-CSRF-Token'] = g.csrfToken;
          g.ext = this$.inject(g) || {};
          getGlobal.resolve(JSON.parse(JSON.stringify(lc.global = g)));
          try {
            this$.fire('update', lc.global);
          } catch (e$) {
            e = e$;
            this$.fire('error', e);
            console.log(e);
          }
          return lc.global;
        })['catch'](function(e){
          if (lderror.id(e) === 1029) {
            return Promise.reject(e);
          }
          e.name = 'lderror';
          e.id = 1007;
          this$.fire('error', e);
          console.log("server down: ", e);
          return new Promise(function(res, rej){});
        });
      },
      prompt: function(o){
        return this.ui.authpanel(true, o);
      },
      oauth: function(arg$){
        var name, this$ = this;
        name = arg$.name;
        return this.get().then(function(g){
          var form, login;
          g == null && (g = {});
          if ((g.user || (g.user = {})).key) {
            return g;
          }
          this$.oauth.window = window.open('', 'oauth-login', 'height=640,width=560');
          this$.oauth.form = form = ld$.create({
            name: 'div'
          });
          form.innerHTML = "<form target=\"oauth-login\" action=\"" + this$.apiRoot() + name + "/\" method=\"post\">\n  <input type=\"hidden\" name=\"_csrf\" value=\"" + g.csrfToken + "\"/>\n</form>";
          document.body.appendChild(form);
          window.oauthLogin = login = proxise(function(){
            return ld$.find(form, 'form', 0).submit();
          });
          return login().then(function(){
            return this$.fetch({
              renew: true
            });
          });
        })['finally'](function(){
          if (!(this$.oauth.form && this$.oauth.form.parentNode)) {
            return;
          }
          return this$.oauth.form.parentNode.removeChild(this$.oauth.form);
        }).then(function(g){
          g == null && (g = {});
          if (!(g.user || (g.user = {})).key) {
            return Promise.reject(new lderror(1000));
          } else {
            return g;
          }
        })['catch'](function(e){
          this$.fire('error', e);
          return Promise.reject(e);
        });
      }
    });
    if (typeof module != 'undefined' && module !== null) {
      return module.exports = auth;
    } else if (typeof window != 'undefined' && window !== null) {
      return window.auth = auth;
    }
  });
  function import$(obj, src){
    var own = {}.hasOwnProperty;
    for (var key in src) if (own.call(src, key)) obj[key] = src[key];
    return obj;
  }
}).call(this);
