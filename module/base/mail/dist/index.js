(function(){
var mail;
mail = {};var common, k, v;
common = {
  isValidColumn: function(n){
    n = ((n || '') + "").trim();
    return !!(n && n.length <= 64 && !/[{}"'<>]/.exec(n));
  },
  escapeHtml: function(v){
    return ((v != null ? v : '') + "").replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  },
  renderText: function(tpl, vars){
    vars == null && (vars = {});
    return ((tpl || '') + "").replace(/\{\{([^{}]*)\}\}/g, function(m, name){
      name = (name + "").trim();
      return vars[name] != null ? vars[name] + "" : '';
    });
  },
  renderHtml: function(tpl, vars){
    var self, re;
    vars == null && (vars = {});
    self = this;
    re = /<span[^>]*\sdata-var="([^"]*)"[^>]*>(?:<span[^>]*>[\s\S]*?<\/span>|[^<])*<\/span>/g;
    return ((tpl || '') + "").replace(re, function(m, name){
      name = (name + "").trim();
      return self.escapeHtml(vars[name] != null ? vars[name] : '');
    });
  },
  usedVars: function(arg$){
    var subject, content, names, k;
    subject = arg$.subject, content = arg$.content;
    names = {};
    (((subject || '') + "").match(/\{\{([^{}]*)\}\}/g) || []).map(function(m){
      return names[m.replace(/^\{\{|\}\}$/g, '').trim()] = true;
    });
    (((content || '') + "").match(/<span[^>]*\sdata-var="([^"]*)"[^>]*>/g) || []).map(function(m){
      var r;
      r = /data-var="([^"]*)"/.exec(m);
      if (r) {
        return names[r[1].trim()] = true;
      }
    });
    return (function(){
      var results$ = [];
      for (k in names) {
        if (k) {
          results$.push(k);
        }
      }
      return results$;
    }());
  },
  toText: function(html){
    return ((html || '') + "").replace(/\uFEFF/g, '').replace(/<br\s*\/?>/gi, '\n').replace(/<\/(p|div|h[1-6]|li|blockquote|tr)>/gi, '\n').replace(/<li[^>]*>/gi, '- ').replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&').replace(/\n{3,}/g, '\n\n').trim();
  },
  formatSender: function(arg$){
    var ref$, sender, sendername, s, n;
    ref$ = arg$ != null
      ? arg$
      : {}, sender = ref$.sender, sendername = ref$.sendername;
    s = ((sender || '') + "").trim();
    n = ((sendername || '') + "").trim();
    if (!s) {
      return '';
    }
    if (~s.indexOf('<')) {
      return s;
    }
    if (!n) {
      return s;
    }
    return "\"" + n.replace(/[\"\\\\]/g, '') + "\" <" + s + ">";
  },
  render: function(arg$, vars){
    var subject, content, html;
    subject = arg$.subject, content = arg$.content;
    vars == null && (vars = {});
    html = this.renderHtml(content, vars);
    return {
      subject: this.renderText(subject, vars),
      html: html,
      text: this.toText(html)
    };
  }
};
if (typeof mail != 'undefined' && mail !== null) {
  for (k in common) {
    v = common[k];
    if (typeof v === 'object') {
      import$(mail[k] || (mail[k] = {}), v);
    } else {
      mail[k] = v;
    }
  }
}
function import$(obj, src){
  var own = {}.hasOwnProperty;
  for (var key in src) if (own.call(src, key)) obj[key] = src[key];
  return obj;
}if (typeof module != 'undefined' && module !== null) {
  module.exports = mail;
} else if (typeof window != 'undefined' && window !== null) {
  window.sbmail = mail;
}})();
