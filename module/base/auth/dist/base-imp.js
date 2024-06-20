var baseImp;
baseImp = {
  init: function(arg$){
    var ctx, root, data, t, ldview, ldnotify, curegex, ldform, this$ = this;
    ctx = arg$.ctx, root = arg$.root, data = arg$.data, t = arg$.t;
    ldview = ctx.ldview, ldnotify = ctx.ldnotify, curegex = ctx.curegex, ldform = ctx.ldform;
    return servebase.corectx(function(arg$){
      var core;
      core = arg$.core;
      return function(it){
        return it.apply(this$.mod = this$.mod(import$({
          core: core,
          t: t
        }, ctx)));
      }(function(){
        var this$ = this;
        this._auth = data.auth;
        return this._auth.get().then(function(g){
          var ldcv, view, form;
          this$.global = g;
          this$.ldcv = ldcv = {};
          ldcv.authpanel = new ldcover({
            root: root,
            zmgr: core.zmgr
          });
          ldcv.authpanel.on('toggle.on', function(){
            return setTimeout(function(){
              return view.get('username').focus();
            }, 100);
          });
          this$._tab = 'login';
          this$._info = 'default';
          this$.view = view = new ldview({
            root: root,
            action: {
              keyup: {
                input: function(arg$){
                  var node, evt;
                  node = arg$.node, evt = arg$.evt;
                  if (evt.keyCode === 13) {
                    return this$.submit();
                  }
                }
              },
              click: {
                oauth: function(arg$){
                  var node, p, ref$;
                  node = arg$.node;
                  p = ((ref$ = g.policy || (g.policy = {})).login || (ref$.login = {})).acceptSignup !== 'invite'
                    ? Promise.resolve()
                    : core.ldcvmgr.get({
                      name: "@servebase/auth",
                      path: "invite-token"
                    });
                  return p.then(function(r){
                    r == null && (r = {});
                    return this$._auth.oauth({
                      name: node.getAttribute('data-name', {
                        inviteToken: r.inviteToken
                      })
                    });
                  }).then(function(g){
                    debounce(350, function(){
                      return this$.info('default');
                    });
                    this$.form.reset();
                    this$.ldcv.authpanel.set(g);
                    return ldnotify.send("success", t("login successfully"));
                  });
                },
                submit: function(arg$){
                  var node;
                  node = arg$.node;
                  return this$.submit();
                },
                'switch': function(arg$){
                  var node;
                  node = arg$.node;
                  return this$.tab(node.getAttribute('data-name'));
                }
              }
            },
            init: {
              submit: function(arg$){
                var node;
                node = arg$.node;
                return this$.ldld = new ldloader({
                  root: node
                });
              }
            },
            handler: {
              oauths: function(arg$){
                var node, k, v;
                node = arg$.node;
                return node.classList.toggle('d-none', !(function(){
                  var ref$, results$ = [];
                  for (k in ref$ = this.global.oauth) {
                    v = ref$[k];
                    results$.push(v);
                  }
                  return results$;
                }.call(this$)).filter(function(it){
                  return it.enabled;
                }).length);
              },
              "signin-failed-hint": function(arg$){
                var node;
                node = arg$.node;
                return node.classList.toggle('d-none', !this$._failedHint);
              },
              "signin-failed-hint-text": function(arg$){
                var node;
                node = arg$.node;
                return node.innerText = this$._failedHintText || '';
              },
              oauth: function(arg$){
                var node;
                node = arg$.node;
                return node.classList.toggle('d-none', !(this$.global.oauth[node.getAttribute('data-name')] || {}).enabled);
              },
              submit: function(arg$){
                var node;
                node = arg$.node;
                return node.classList.toggle('disabled', !this$.ready);
              },
              "submit-text": function(arg$){
                var node;
                node = arg$.node;
                return node.innerText = t(this$._tab === 'login' ? 'login' : 'signup');
              },
              displayname: function(arg$){
                var node;
                node = arg$.node;
                return node.classList.toggle('d-none', this$._tab === 'login');
              },
              info: function(arg$){
                var node, hide;
                node = arg$.node;
                hide = node.getAttribute('data-name') !== this$._info;
                if (node.classList.contains('d-none') || hide) {
                  return node.classList.toggle('d-none', hide);
                }
                node.classList.toggle('d-none', true);
                return setTimeout(function(){
                  return node.classList.toggle('d-none', hide);
                }, 0);
              },
              'switch': function(arg$){
                var node, name;
                node = arg$.node;
                name = node.getAttribute('data-name');
                node.classList.toggle('btn-light', this$._tab !== name);
                node.classList.toggle('border', this$._tab !== name);
                return node.classList.toggle('btn-primary', this$._tab === name);
              }
            }
          });
          this$.form = form = new ldform({
            names: function(){
              return ['username', 'password', 'displayname'];
            },
            afterCheck: function(s, f){
              if (s.username !== 1 && !this$.isValid.username(f.username.value)) {
                s.username = 2;
              }
              if (s.password !== 1) {
                s.password = !f.password.value
                  ? 1
                  : !this$.isValid.password(f.password.value) ? 2 : 0;
              }
              if (this$._tab === 'login') {
                return s.displayname = 0;
              } else {
                return s.displayname = !f.displayname.value
                  ? 1
                  : !!f.displayname.value ? 0 : 2;
              }
            },
            root: root
          });
          return this$.form.on('readystatechange', function(it){
            this$.ready = it;
            return this$.view.render('submit');
          });
        });
      });
    });
  },
  'interface': function(){
    var this$ = this;
    return function(toggle, opt){
      toggle == null && (toggle = true);
      opt == null && (opt = {});
      if (opt.tab) {
        this$.mod.tab(opt.tab);
      }
      if (opt.lock) {
        this$.mod.ldcv.authpanel.lock();
      }
      if (toggle) {
        return this$.mod.ldcv.authpanel.get();
      } else {
        return this$.mod.auth.fetch().then(function(g){
          return this.mod.ldcv.authpanel.set(g);
        });
      }
    };
  },
  mod: function(ctx){
    var core, ldview, ldnotify, curegex, t;
    core = ctx.core, ldview = ctx.ldview, ldnotify = ctx.ldnotify, curegex = ctx.curegex, t = ctx.t;
    return {
      tab: function(tab){
        if (/failed/.exec(this._info)) {
          this._info = 'default';
        }
        this._tab = tab;
        return this.view.render();
      },
      isValid: {
        username: function(u){
          return curegex.get('email').exec(u);
        },
        password: function(p){
          return p && p.length >= 8;
        }
      },
      info: function(it){
        this._info = it;
        return this.view.render('info');
      },
      submit: function(){
        var val, body, ref$, this$ = this;
        if (!this.form.ready()) {
          return;
        }
        this._failedHint = false;
        this.view.render('signin-failed-hint');
        val = this.form.values();
        body = (ref$ = {}, ref$.username = val.username, ref$.password = val.password, ref$.displayname = val.displayname, ref$);
        return this.ldld.on().then(function(){
          return debounce(1000);
        }).then(function(){
          var g, p, ref$;
          g = this$.global;
          return p = ((ref$ = g.policy || (g.policy = {})).login || (ref$.login = {})).acceptSignup !== 'invite' || this$._tab !== 'signup'
            ? Promise.resolve()
            : core.ldcvmgr.get({
              name: "@servebase/auth",
              path: "invite-token"
            });
        }).then(function(r){
          var _;
          r == null && (r = {});
          _ = function(o){
            o == null && (o = {});
            return core.captcha.guard({
              cb: function(captcha){
                import$((body.captcha = captcha, body), o.inviteToken
                  ? {
                    inviteToken: o.inviteToken
                  }
                  : {});
                return debounce(250).then(function(){
                  return ld$.fetch(this$._auth.apiRoot() + "" + this$._tab, {
                    method: 'POST'
                  }, {
                    json: body,
                    type: 'json'
                  });
                });
              }
            })['catch'](function(e){
              if (lderror.id(e) !== 1043) {
                return Promise.reject(e);
              }
              return debounce(250).then(function(){
                return core.ldcvmgr.get({
                  name: "@servebase/auth",
                  path: "invite-token"
                }).then(function(r){
                  if (!(r && r.inviteToken)) {
                    return Promise.reject(e);
                  }
                  return _({
                    inviteToken: r.inviteToken
                  });
                });
              });
            });
          };
          return _(r.inviteToken
            ? r
            : {});
        })['catch'](function(e){
          if (lderror.id(e) !== 1005) {
            return Promise.reject(e);
          }
          return ld$.fetch(this$._auth.apiRoot() + "reset", {
            method: 'POST'
          }).then(function(){
            return this$._auth.fetch({
              renew: true
            });
          }).then(function(){
            return ld$.fetch(this$._auth.apiRoot() + "" + this$._tab, {
              method: 'POST'
            }, {
              json: body,
              type: 'json'
            });
          });
        }).then(function(ret){
          ret == null && (ret = {});
          return this$._auth.fetch().then(function(g){
            if (!ret.passwordShouldRenew) {
              return g;
            }
            return core.ldcvmgr.get({
              name: "@servebase/auth",
              path: "passwd-renew"
            }).then(function(){
              return g;
            });
          });
        })['finally'](function(){
          return this$.ldld.off();
        }).then(function(g){
          debounce(350, function(){
            return this$.info('default');
          });
          this$._failedHint = false;
          this$.view.render();
          this$.form.reset();
          this$.ldcv.authpanel.set(g);
          ldnotify.send("success", t("login successfully"));
          return g;
        })['catch'](function(e){
          var id;
          console.log(e);
          id = lderror.id(e);
          if (id >= 500 && id < 599) {
            return lderror.reject(1007);
          }
          if (id === 1029) {
            return Promise.reject(e);
          }
          if (id === 1004) {
            return this$.info("login-exceeded");
          }
          this$._failedHintText = id === 1014
            ? t("Account exists. try login")
            : id === 1012 || id === 1030
              ? t("Password mismatched")
              : id === 1009 || id === 1010
                ? t("Captcha failed")
                : id === 1041
                  ? t("Resource issue")
                  : t(this$._tab + " failed");
          this$.info(this$._tab + "-failed");
          this$._failedHint = true;
          this$.view.render();
          this$.form.fields.password.value = null;
          this$.form.check({
            n: 'password',
            now: true
          });
          if (!id || (id === 1009 || id === 1010 || id === 1041)) {
            throw e;
          }
        });
      }
    };
  }
};
function import$(obj, src){
  var own = {}.hasOwnProperty;
  for (var key in src) if (own.call(src, key)) obj[key] = src[key];
  return obj;
}
