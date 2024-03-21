require! <[livescript path]>
module.exports =
  from: (m = []) ->
    _m = if Array.isArray(m) => m else [m]
    ret = _m.map (m) -> require(path.join(__dirname, '../../../../config', m))
    return if Array.isArray(m) => ret else ret.0
