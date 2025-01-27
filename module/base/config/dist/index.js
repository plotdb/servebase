var livescript, path, lderror, jsYaml, fs;
livescript = require('livescript');
path = require('path');
lderror = require('lderror');
jsYaml = require('js-yaml');
fs = require("fs-extra");
module.exports = {
  _p: function(p, lng){
    p = path.join(__dirname, '../../../../config', p);
    return !lng
      ? p
      : path.join(path.dirname(p), lng, path.basename(p));
  },
  _wrap: function(m, cb, lngs){
    var _m, _l, _, this$ = this;
    m == null && (m = []);
    _m = Array.isArray(m)
      ? m
      : [m];
    lngs = Array.isArray(lngs)
      ? lngs
      : [lngs];
    _l = function(i, j){
      var ref$;
      i == null && (i = 0);
      j == null && (j = 0);
      if (j > lngs.length) {
        return Promise.reject((ref$ = new Error(), ref$.code = 'ENOENT', ref$));
      }
      return cb(this$._p(_m[i], lngs[j]))['catch'](function(e){
        if (e.code === 'ENOENT') {
          return _l(i, j + 1);
        } else {
          return lderror.reject(1017);
        }
      });
    };
    return (_ = function(i){
      i == null && (i = 0);
      if (!_m[i]) {
        return lderror.reject(1027);
      }
      return _l(i, 0)['catch'](function(e){
        return e.code === 'ENOENT'
          ? _(i + 1)
          : lderror.reject(1017);
      });
    })();
  },
  from: function(p){
    return require(this._p(p));
  },
  json: function(m, lng){
    m == null && (m = []);
    return this._wrap(m, function(p){
      return fs.readJson(p);
    }, lng);
  },
  yaml: function(m, lng){
    m == null && (m = []);
    return this._wrap(m, function(p){
      return fs.readFile(p).then(function(it){
        return jsYaml.safeLoad(it);
      });
    }, lng);
  },
  text: function(m, lng){
    m == null && (m = []);
    return this._wrap(m, function(p){
      return fs.readFile(p).then(function(it){
        return it.toString();
      });
    }, lng);
  }
};