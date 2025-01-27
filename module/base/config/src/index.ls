require! <[livescript path lderror js-yaml]>
fs = require "fs-extra"

module.exports =
  _p: (p, lng) ->
    p = path.join(__dirname, '../../../../config', p)
    return if !lng => p else path.join(path.dirname(p), lng, path.basename(p))
  _wrap: (m = [], cb, lngs) ->
    _m = if Array.isArray(m) => m else [m]
    lngs = if Array.isArray(lngs) => lngs else [lngs]
    _l = (i = 0, j = 0) ~>
      if j > lngs.length => return Promise.reject(new Error! <<< {code: \ENOENT})
      (e) <~ cb(@_p(_m[i], lngs[j])).catch _
      if e.code == \ENOENT => _l(i, j + 1) else lderror.reject(1017)
    return (_ = (i = 0) ~>
      if !_m[i] => return lderror.reject(1027)
      (e) <- _l(i, 0).catch _
      return if e.code == \ENOENT => _(i + 1) else lderror.reject(1017)
    )!
  from: (p) -> require @_p(p)
  json: (m = [], lng) -> @_wrap m, ((p) -> fs.read-json p), lng
  yaml: (m = [], lng) -> @_wrap m, ((p) -> fs.read-file p .then -> js-yaml.safe-load it), lng
  text: (m = [], lng) -> @_wrap m, ((p) -> fs.read-file p .then -> it.toString!), lng
