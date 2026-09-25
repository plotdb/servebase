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
  sanitizeHtml: function(html){
    var p;
    p = this.getPurify
      ? this.getPurify()
      : typeof DOMPurify != 'undefined' && DOMPurify !== null ? DOMPurify : null;
    if (!p) {
      throw new Error("[@servebase/mail] DOMPurify is required for sanitizing html");
    }
    return p.sanitize((html || '') + "", {
      ALLOWED_TAGS: ['p', 'br', 'strong', 'b', 'em', 'i', 'u', 's', 'a', 'ul', 'ol', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'span'],
      ALLOWED_ATTR: ['href', 'target', 'rel', 'class', 'contenteditable']
    });
  },
  quillFormats: function(){
    return ['header', 'bold', 'italic', 'underline', 'strike', 'link', 'list', 'blockquote', 'mmvar'];
  },
  renderHtml: function(tpl, vars){
    var self, re, html;
    vars == null && (vars = {});
    self = this;
    re = /<span[^>]*\sdata-var="([^"]*)"[^>]*>(?:<span[^>]*>[\s\S]*?<\/span>|[^<])*<\/span>/g;
    html = ((tpl || '') + "").replace(re, function(m, name){
      name = (name + "").trim();
      return self.escapeHtml(vars[name] != null ? vars[name] : '');
    });
    return self.tighten(self.sanitizeHtml(html));
  },
  tighten: function(html){
    return ((html || '') + "").replace(/<p(\s[^>]*)?>/g, function(m, attr){
      attr = attr || '';
      if (/\sstyle\s*=/.exec(attr)) {
        return m;
      }
      return "<p" + attr + " style=\"margin:0\">";
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
}