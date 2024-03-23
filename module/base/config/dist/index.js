var livescript, path, lderror, jsYaml, fs;
livescript = require('livescript');
path = require('path');
lderror = require('lderror');
jsYaml = require('js-yaml');
fs = require("fs-extra");
module.exports = {
  _p: function(p){
    return path.join(__dirname, '../../../../config', p);
  },
  _wrap: function(m, cb){
    var _m, _, this$ = this;
    m == null && (m = []);
    _m = Array.isArray(m)
      ? m
      : [m];
    return (_ = function(i){
      i == null && (i = 0);
      if (!_m[i]) {
        return lderror.reject(1027);
      }
      return cb(this$._p(_m[i]))['catch'](function(e){
        return e.code === 'ENOENT'
          ? _(i + 1)
          : lderror.reject(1017);
      });
    })();
  },
  from: function(p){
    return require(this._p(p));
  },
  json: function(m){
    m == null && (m = []);
    return this._wrap(m, function(p){
      return fs.readJson(p);
    });
  },
  yaml: function(m){
    m == null && (m = []);
    return this._wrap(m, function(p){
      return fs.readFile(p).then(function(it){
        return jsYaml.safeLoad(it);
      });
    });
  }
};