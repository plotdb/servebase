var livescript, path;
livescript = require('livescript');
path = require('path');
module.exports = {
  as: function(m){
    var _m, ret;
    m == null && (m = []);
    _m = Array.isArray(m)
      ? m
      : [m];
    ret = _m.map(function(m){
      return require(path.join(__dirname, '../../../../config', m));
    });
    return Array.isArray(m)
      ? _m
      : _m[0];
  }
};