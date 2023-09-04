// Generated by LiveScript 1.6.0
(function(){
  var discuss, ref$;
  discuss = function(o){
    var md, markedr;
    o == null && (o = {});
    this.root = typeof o.root === 'string'
      ? document.querySelector(o.root)
      : o.root;
    this.host = o.host || {};
    this.cfg = o.config || {};
    if (typeof marked != 'undefined' && marked !== null) {
      md = new marked.Marked();
      markedr = new marked.Renderer();
      markedr.link = function(href, title, text){
        var link;
        link = marked.Renderer.prototype.link.call(this, href, title, text);
        return link.replace('<a', '<a target="_blank" rel="noopener noreferrer" ');
      };
      md.setOptions({
        renderer: markedr
      });
    }
    this._evthdr = {};
    this._loading = false;
    this._purify = function(t){
      if (typeof DOMPurify != 'undefined' && DOMPurify !== null) {
        return DOMPurify.sanitize(t);
      }
      console.warn("[@servebase/discuss] DOMPurify is not found which is required for DOM sanitizing");
      return t;
    };
    this._md = function(t){
      if ((typeof marked != 'undefined' && marked !== null) && md) {
        return md.parse(t);
      }
      console.warn("[@servebase/discuss] marked is not found which is required for markdown compiling");
      return t;
    };
    this.comments = [];
    this.discuss = {};
    this._uri = o.uri || window.location.pathname;
    this._slug = o.slug || null;
    this._core = o.core;
    this._edit = {};
    return this;
  };
  discuss.prototype = (ref$ = Object.create(Object.prototype), ref$.on = function(n, cb){
    var this$ = this;
    return (Array.isArray(n)
      ? n
      : [n]).map(function(n){
      var ref$;
      return ((ref$ = this$._evthdr)[n] || (ref$[n] = [])).push(cb);
    });
  }, ref$.fire = function(n){
    var v, res$, i$, to$, ref$, len$, cb, results$ = [];
    res$ = [];
    for (i$ = 1, to$ = arguments.length; i$ < to$; ++i$) {
      res$.push(arguments[i$]);
    }
    v = res$;
    for (i$ = 0, len$ = (ref$ = this._evthdr[n] || []).length; i$ < len$; ++i$) {
      cb = ref$[i$];
      results$.push(cb.apply(this, v));
    }
    return results$;
  }, ref$.isReady = function(arg$){
    var ctx, ref$, ref1$, key$;
    ctx = arg$.ctx;
    return !!(((ref$ = (ref1$ = this._edit)[key$ = ctx.key] || (ref1$[key$] = {})).content || (ref$.content = {})).body || '').trim().length;
  }, ref$.init = function(){
    var this$ = this;
    this.view = this._view({
      root: this.root
    });
    return this._core.init().then(function(){
      return this$._core.auth.get();
    }).then(function(g){
      return this$.g = g;
    });
  }, ref$.load = function(){
    var payload, this$ = this;
    this._loading = true;
    this.view.render();
    this.fire('loading');
    payload = this._slug
      ? {
        slug: this._slug
      }
      : {
        uri: this._uri
      };
    return ld$.fetch('/api/discuss', {
      method: 'GET'
    }, {
      params: payload,
      type: 'json'
    })['finally'](function(){
      return this$.loading = false;
    }).then(function(r){
      this$.comments = r.comments || [];
      this$.discuss = r.discuss || {};
      this$.roles = r.roles || {};
      this$.fire('loaded');
      return this$.view.render();
    });
  }, ref$.contentRender = function(arg$){
    var node, ctx, obj;
    node = arg$.node, ctx = arg$.ctx;
    obj = ctx.content || {};
    if (!(obj.config || {})["renderer"] || !(obj.body != null)) {
      return node.innerText = obj.body || '';
    } else {
      return node.innerHTML = this._purify(this._md(obj.body));
    }
  }, ref$._view = function(arg$){
    var root, setCfg, setAvatar, cfg, this$ = this;
    root = arg$.root;
    setCfg = function(ctx, o){
      var k, v, ref$, ref1$, ref2$, key$, results$ = [];
      o == null && (o = {});
      for (k in o) {
        v = o[k];
        results$.push(((ref$ = (ref1$ = (ref2$ = this$._edit)[key$ = ctx.key] || (ref2$[key$] = {})).content || (ref1$.content = {})).config || (ref$.config = {}))[k] = v);
      }
      return results$;
    };
    setAvatar = function(arg$){
      var node, ctx;
      node = arg$.node, ctx = arg$.ctx;
      if (this$.host.avatar) {
        return node.style.background = "url(" + this$.host.avatar({
          comment: ctx || {}
        }) + ")";
      } else {
        return node.style.background = 'auto';
      }
    };
    cfg = {};
    cfg.edit = {
      action: {
        input: {
          input: function(arg$){
            var node, views, ctx, ref$, ref1$, key$;
            node = arg$.node, views = arg$.views, ctx = arg$.ctx;
            ((ref$ = (ref1$ = this$._edit)[key$ = ctx.key] || (ref1$[key$] = {})).content || (ref$.content = {})).body = node.value;
            return views[0].render('submit');
          }
        },
        click: {
          cancel: function(arg$){
            var node, ctx, views, ref$, key$;
            node = arg$.node, ctx = arg$.ctx, views = arg$.views;
            ((ref$ = this$._edit)[key$ = ctx.key] || (ref$[key$] = {})).editing = !((ref$ = this$._edit)[key$ = ctx.key] || (ref$[key$] = {})).editing;
            return views[1].render();
          },
          submit: function(arg$){
            var node, ctx, ctxs, payload, ref$, key$;
            node = arg$.node, ctx = arg$.ctx, ctxs = arg$.ctxs;
            if (node.classList.contains('running')) {
              return;
            }
            if (node.classList.contains('disabled')) {
              return;
            }
            if (!this$.isReady({
              ctx: ctx
            })) {
              return;
            }
            payload = {
              key: ctx.key,
              uri: this$._uri,
              content: JSON.parse(JSON.stringify(((ref$ = this$._edit)[key$ = ctx.key] || (ref$[key$] = {})).content || {})),
              slug: this$._slug
            };
            return this$._core.auth.ensure().then(function(){
              var ref$, key$;
              ((ref$ = this$._edit)[key$ = ctx.key] || (ref$[key$] = {})).ldld.on();
              return this$._core.captcha.guard({
                cb: function(captcha){
                  payload.captcha = captcha;
                  return ld$.fetch('/api/discuss/comment', {
                    method: payload.key ? 'PUT' : 'POST'
                  }, {
                    type: 'json',
                    json: payload
                  });
                }
              });
            }).then(function(ret){
              return debounce(1000).then(function(){
                return ret;
              });
            }).then(function(ret){
              var ref$, key$, c, ref1$;
              ctx.content = JSON.parse(JSON.stringify(((ref$ = this$._edit)[key$ = ctx.key] || (ref$[key$] = {})).content || {}));
              if (!ctx.key) {
                c = (ref$ = (ref1$ = {
                  owner: this$._core.user.key,
                  createdtime: Date.now(),
                  _user: {
                    key: this$._core.user.key,
                    displayname: this$._core.user.displayname
                  }
                }, ref1$.uri = payload.uri, ref1$.content = payload.content, ref1$.slug = payload.slug, ref1$), ref$.key = ret.key, ref$.slug = ret.slug, ref$);
                this$.fire('new-comment', c);
                this$.comments.push(c);
              }
              ((ref$ = (ref1$ = this$._edit)[key$ = ctx.key] || (ref1$[key$] = {})).content || (ref$.content = {})).body = '';
              ((ref$ = this$._edit)[key$ = ctx.key] || (ref$[key$] = {})).preview = false;
              this$.view.get('input').value = '';
              return this$.view.render();
            })['finally'](function(){
              return debounce(1000).then(function(){
                var ref$, key$;
                return ((ref$ = this$._edit)[key$ = ctx.key] || (ref$[key$] = {})).ldld.off();
              });
            });
          }
        }
      },
      init: {
        submit: function(arg$){
          var node, ctx, ref$, key$;
          node = arg$.node, ctx = arg$.ctx;
          return ((ref$ = this$._edit)[key$ = ctx.key] || (ref$[key$] = {})).ldld = new ldloader({
            root: node
          });
        }
      },
      handler: {
        "@": function(arg$){
          var node, ctx, ref$, key$, hide;
          node = arg$.node, ctx = arg$.ctx;
          if (ctx.key) {
            return node.classList.toggle('d-none', !((ref$ = this$._edit)[key$ = ctx.key] || (ref$[key$] = {})).editing);
          }
          hide = !this$.host.perm
            ? !this$.cfg["comment-new"]
            : !this$.host.perm({
              comment: ctx,
              action: 'new',
              config: this$.cfg
            });
          return node.classList.toggle('d-none', hide);
        },
        input: function(arg$){
          var node, views, ctx, ref$, ref1$, key$;
          node = arg$.node, views = arg$.views, ctx = arg$.ctx;
          return node.value = ((ref$ = (ref1$ = this$._edit)[key$ = ctx.key] || (ref1$[key$] = {})).content || (ref$.content = {})).body || '';
        },
        "toggle-preview": {
          action: {
            input: {
              check: function(arg$){
                var node, views, ctxs, ref$, key$;
                node = arg$.node, views = arg$.views, ctxs = arg$.ctxs;
                ((ref$ = this$._edit)[key$ = ctxs[0].key] || (ref$[key$] = {})).preview = !!node.checked;
                return views[1].render();
              }
            },
            click: {
              label: function(arg$){
                var node, views, ctxs, input, ref$, key$;
                node = arg$.node, views = arg$.views, ctxs = arg$.ctxs;
                input = views[0].get('check');
                ((ref$ = this$._edit)[key$ = ctxs[0].key] || (ref$[key$] = {})).preview = input.checked = !input.checked;
                return views[1].render();
              }
            }
          }
        },
        "use-markdown": {
          action: {
            input: {
              check: function(arg$){
                var node, views, ctxs, useMarkdown;
                node = arg$.node, views = arg$.views, ctxs = arg$.ctxs;
                useMarkdown = !!node.checked;
                setCfg(ctxs[0], {
                  renderer: useMarkdown ? 'markdown' : ''
                });
                return views[1].render();
              }
            },
            click: {
              label: function(arg$){
                var node, views, ctxs, input, useMarkdown;
                node = arg$.node, views = arg$.views, ctxs = arg$.ctxs;
                input = views[0].get('check');
                useMarkdown = input.checked = !input.checked;
                setCfg(ctxs[0], {
                  renderer: useMarkdown ? 'markdown' : ''
                });
                return views[1].render();
              }
            }
          }
        },
        avatar: setAvatar,
        preview: function(arg$){
          var node, ctx, revert, state, ref$, ref1$, key$;
          node = arg$.node, ctx = arg$.ctx;
          revert = in$("off", node.getAttribute('ld').split(" "));
          state = !(ref$ = !(((ref1$ = this$._edit)[key$ = ctx.key] || (ref1$[key$] = {})).preview && ((((ref1$ = this$._edit)[key$ = ctx.key] || (ref1$[key$] = {})).content || {}).config || {}).renderer === 'markdown')) !== !revert && (ref$ || revert);
          return node.classList.toggle('d-none', state);
        },
        panel: function(arg$){
          var node, ctx, ref$, key$;
          node = arg$.node, ctx = arg$.ctx;
          return this$.contentRender({
            node: node,
            ctx: (ref$ = this$._edit)[key$ = ctx.key] || (ref$[key$] = {})
          });
        },
        submit: function(arg$){
          var node, ctx;
          node = arg$.node, ctx = arg$.ctx;
          return node.classList.toggle('disabled', !this$.isReady({
            ctx: ctx
          }));
        },
        "if-markdown": function(arg$){
          var node, ctx, hidden, ref$, key$;
          node = arg$.node, ctx = arg$.ctx;
          hidden = ((((ref$ = this$._edit)[key$ = ctx.key] || (ref$[key$] = {})).content || {}).config || {}).renderer !== 'markdown';
          return node.classList.toggle('d-none', hidden);
        }
      }
    };
    cfg.discuss = {
      text: {
        "@": function(){
          return (this$.discuss || {}).title || 'untitled';
        }
      }
    };
    cfg.comments = {
      handler: {
        "no-comment": function(arg$){
          var node;
          node = arg$.node;
          return node.classList.toggle('d-none', this$.comments.length);
        },
        comment: {
          list: function(){
            return this$.comments;
          },
          key: function(it){
            return it.key;
          },
          view: {
            text: {
              date: function(arg$){
                var ctx, d;
                ctx = arg$.ctx;
                if (isNaN(d = new Date(ctx.createdtime))) {
                  return '-';
                }
                return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 19).replace('T', ' ');
              },
              author: function(arg$){
                var ctx;
                ctx = arg$.ctx;
                return ctx._user.displayname;
              }
            },
            action: {
              click: {
                edit: function(arg$){
                  var node, ctx, views, ref$, key$;
                  node = arg$.node, ctx = arg$.ctx, views = arg$.views;
                  ((ref$ = this$._edit)[key$ = ctx.key] || (ref$[key$] = {})).editing = !((ref$ = this$._edit)[key$ = ctx.key] || (ref$[key$] = {})).editing;
                  return views[0].render();
                },
                'delete': function(arg$){
                  var node, ctx;
                  node = arg$.node, ctx = arg$.ctx;
                  return this$._core.auth.ensure().then(function(){
                    if (!this$.host.confirmDelete) {
                      return Promise.resolve(true);
                    }
                    return this$.host.confirmDelete({
                      comment: ctx
                    });
                  }).then(function(it){
                    var ref$, key$;
                    if (!it) {
                      return;
                    }
                    ((ref$ = this$._edit)[key$ = ctx.key] || (ref$[key$] = {})).ldld.on();
                    return ld$.fetch("/api/discuss/comment/" + ctx.key, {
                      method: 'DELETE'
                    })['finally'](function(){
                      debounce(1000).then(function(){
                        var ref$, key$;
                        return ((ref$ = this$._edit)[key$ = ctx.key] || (ref$[key$] = {})).ldld.off();
                      });
                    }).then(function(){
                      this$.fire('delete-comment', ctx);
                      this$.comments.splice(this$.comments.indexOf(ctx), 1);
                      return this$.view.render();
                    });
                  });
                }
              }
            },
            init: {
              "@": function(arg$){
                var ctx, ref$, key$;
                ctx = arg$.ctx;
                return ((ref$ = this$._edit)[key$ = ctx.key] || (ref$[key$] = {})).content = JSON.parse(JSON.stringify(ctx.content));
              }
            },
            handler: {
              update: import$({
                ctx: function(arg$){
                  var ctxs;
                  ctxs = arg$.ctxs;
                  return ctxs[0];
                }
              }, cfg.edit),
              edit: function(arg$){
                var node, ctx, hide;
                node = arg$.node, ctx = arg$.ctx;
                hide = !this$.host.perm
                  ? false
                  : !this$.host.perm({
                    comment: ctx,
                    action: 'edit',
                    config: this$.cfg
                  });
                return node.classList.toggle('d-none', hide);
              },
              'delete': function(arg$){
                var node, ctx, hide;
                node = arg$.node, ctx = arg$.ctx;
                hide = !this$.host.perm
                  ? false
                  : !this$.host.perm({
                    comment: ctx,
                    action: 'delete',
                    config: this$.cfg
                  });
                return node.classList.toggle('d-none', hide);
              },
              avatar: setAvatar,
              role: {
                list: function(arg$){
                  var ctx, ret;
                  ctx = arg$.ctx;
                  ret = this$.roles[ctx.owner] || [];
                  return (Array.isArray(ret)
                    ? ret
                    : [ret]).filter(function(it){
                    return it;
                  });
                },
                key: function(it){
                  return it;
                },
                view: {
                  text: {
                    name: function(arg$){
                      var ctx;
                      ctx = arg$.ctx;
                      return ctx;
                    }
                  }
                }
              },
              content: function(o){
                return this$.contentRender({
                  node: o.node,
                  ctx: o.ctx
                });
              }
            }
          }
        }
      }
    };
    return new ldview({
      root: root,
      initRender: false,
      handler: {
        loading: function(arg$){
          var node, names, ref$;
          node = arg$.node, names = arg$.names;
          return node.classList.toggle('d-none', !(!this$._loading !== !(ref$ = in$('off', names)) && (this$._loading || ref$)));
        },
        discuss: cfg.discuss,
        edit: import$({
          ctx: function(){
            return {};
          }
        }, cfg.edit),
        comments: cfg.comments
      }
    });
  }, ref$);
  if (typeof module != 'undefined' && module !== null) {
    module.exports = discuss;
  } else if (typeof window != 'undefined' && window !== null) {
    window.discuss = discuss;
  }
  function in$(x, xs){
    var i = -1, l = xs.length >>> 0;
    while (++i < l) if (x === xs[i]) return true;
    return false;
  }
  function import$(obj, src){
    var own = {}.hasOwnProperty;
    for (var key in src) if (own.call(src, key)) obj[key] = src[key];
    return obj;
  }
}).call(this);
