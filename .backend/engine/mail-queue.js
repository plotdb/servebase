// Generated by LiveScript 1.6.0
(function(){
  var fs, path, config, colors, jsYaml, lderror, nodemailer, nodemailerMailgunTransport, md, libdir, rootdir, mailQueue;
  fs = require('fs');
  path = require('path');
  config = require('@servebase/config');
  colors = require('@plotdb/colors');
  jsYaml = require('js-yaml');
  lderror = require('lderror');
  nodemailer = require('nodemailer');
  nodemailerMailgunTransport = require('nodemailer-mailgun-transport');
  md = require('./utils/md');
  libdir = path.dirname(fs.realpathSync(__filename.replace(/\(js\)$/, '')));
  rootdir = path.join(libdir, '../..');
  mailQueue = function(opt){
    var p, err, this$ = this;
    opt == null && (opt = {});
    this.api = opt.smtp
      ? nodemailer.createTransport(opt.smtp)
      : opt.mailgun
        ? nodemailer.createTransport(nodemailerMailgunTransport(opt.mailgun))
        : {
          sendMail: function(){
            this$.log.error("sendMail called while mail gateway is not available");
            return lderror.reject(500, "mail service not available");
          }
        };
    this.suppress = opt.suppress;
    this.base = opt.base || 'base';
    this.log = opt.logger;
    this.info = opt.info || {};
    if (opt.blacklist != null) {
      if (Array.isArray(opt.blacklist)) {
        this._blacklist = opt.blacklist.map(function(n){
          return ((!n
            ? ''
            : /@/.exec(n)
              ? n
              : "@" + n) + "").trim();
        }).filter(function(it){
          return it;
        });
      } else if (typeof opt.blacklist === 'object') {
        if (typeof opt.blacklist.module === 'string') {
          try {
            p = !/^\./.exec(opt.blacklist.module)
              ? opt.blacklist.module
              : path.join(rootdir, opt.blacklist.module);
            this._blacklist = require(p);
          } catch (e$) {
            err = e$;
            this.log.error({
              err: err
            }, "blacklist is provided as a module, however failed to load, and thus disabled.");
          }
        }
      }
    }
    this.list = [];
    return this;
  };
  mailQueue.prototype = import$(Object.create(Object.prototype), {
    inBlacklist: function(m){
      var this$ = this;
      m == null && (m = "");
      return !this._blacklist
        ? Promise.resolve(false)
        : Array.isArray(this._blacklist)
          ? Promise.resolve().then(function(){
            var i$, i;
            for (i$ = this$._blacklist.length - 1; i$ >= 0; --i$) {
              i = i$;
              if (~m.indexOf(this$._blacklist[i])) {
                return true;
              }
            }
            return false;
          })
          : typeof this._blacklist.is === 'function'
            ? this._blacklist.is(m)
            : Promise.resolve(false);
    },
    add: function(obj){
      this.list.push(obj);
      return this.handler();
    },
    handle: null,
    handler: function(){
      var this$ = this;
      if (this.handle) {
        return;
      }
      this.log.info("new job incoming, handling...".cyan);
      return this.handle = setInterval(function(){
        var obj;
        this$.log.info((this$.list.length + " jobs remain...").cyan);
        obj = this$.list.splice(0, 1)[0];
        if (!obj) {
          this$.log.info("all job done, take a rest.".green);
          clearInterval(this$.handle);
          this$.handle = null;
          return;
        }
        return this$.sendDirectly(obj.payload).then(obj.res)['catch'](obj.rej);
      }, 5000);
    },
    send: function(payload, opt){
      var this$ = this;
      opt == null && (opt = {});
      if (opt.now) {
        return this.sendDirectly(payload);
      }
      return new Promise(function(res, rej){
        return this$.add({
          payload: payload,
          res: res,
          rej: rej
        });
      });
    },
    sendDirectly: function(payload){
      var this$ = this;
      return new Promise(function(res, rej){
        var cc, bcc;
        cc = !payload.cc
          ? ' '
          : " [cc:" + (Array.isArray(payload.cc)
            ? payload.cc.join(' ')
            : payload.cc) + "] ";
        bcc = !payload.bcc
          ? ''
          : "[bcc:" + (Array.isArray(payload.bcc)
            ? payload.bcc.join(' ')
            : payload.bcc) + "] ";
        this$.log.info(((this$.suppress ? '(suppressed)'.gray : '') + " sending [from:" + payload.from + "] [to:" + payload.to + "]" + cc + bcc + "[subject:" + payload.subject + "]").cyan);
        if (this$.suppress) {
          return res();
        }
        return this$.api.sendMail(payload, function(err, i){
          if (!err) {
            return res();
          }
          this$.log.error({
            err: err
          }, "send mail failed: api.sendMail failed.");
          return res();
        });
      });
    },
    sendFromMd: function(payload, map, opt){
      var this$ = this;
      map == null && (map = {});
      opt == null && (opt = {});
      return new Promise(function(res, rej){
        var content, k, ref$, v, re;
        content = payload.content || '';
        payload.from = (this$.info || {}).from || payload.from;
        for (k in ref$ = map) {
          v = ref$[k];
          re = new RegExp("#{" + k + "}", "g");
          content = content.replace(re, v);
          payload.from = payload.from.replace(re, v);
          payload.subject = payload.subject.replace(re, v);
        }
        payload.text = md.toText(content);
        payload.html = md.toHtml(content);
        delete payload.content;
        return this$.send(payload, opt).then(function(){
          return res();
        });
      });
    },
    byTemplate: function(name, email, map, opt){
      var this$ = this;
      map == null && (map = {});
      opt == null && (opt = {});
      return config.yaml(['private', this.base, 'base'].map(function(it){
        return path.join(it, "mail/" + name + ".yaml");
      })).then(function(payload){
        var obj;
        obj = {
          from: opt.from || payload.from,
          to: email,
          subject: payload.subject,
          content: payload.content
        };
        if (opt.cc) {
          obj.cc = opt.cc;
        }
        if (opt.bcc) {
          obj.bcc = opt.bcc;
        }
        return this$.sendFromMd(obj, map, {
          now: opt.now
        });
      })['catch'](function(err){
        this$.log.error({
          err: err
        }, "send mail by template failed for name `" + name + "`");
        return Promise.reject(err);
      });
    }
  });
  module.exports = mailQueue;
  function import$(obj, src){
    var own = {}.hasOwnProperty;
    for (var key in src) if (own.call(src, key)) obj[key] = src[key];
    return obj;
  }
}).call(this);
