require! <[livescript path lderror js-yaml]>
fs = require "fs-extra"

module.exports =
  _p: (p) -> path.join(__dirname, '../../../../config', p)
  _wrap: (m = [], cb) ->
    _m = if Array.isArray(m) => m else [m]
    return (_ = (i = 0) ~>
      if !_m[i] => return lderror.reject(1027)
      (e) <- cb(@_p(_m[i])).catch _
      return if e.code == \ENOENT => _(i + 1) else lderror.reject(1017)
    )!
  require: (p) -> require @_p(p)
  json: (m = []) -> @_wrap m, ((p) -> fs.read-json p)
  yaml: (m = []) -> @_wrap m, ((p) -> fs.read-file p .then -> js-yaml.safe-load it)
