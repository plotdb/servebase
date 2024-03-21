require! <[livescript path]>
module.exports =
  as: (m = []) ->
    _m = if Array.isArray(m) => m else [m]
    ret = _m.map (m) -> require(path.join(__dirname, '../../../../config', m))
    return if Array.isArray(m) => _m else _m.0
