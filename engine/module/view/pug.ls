require! <[fs path pug]>
pug-extapi = require("../../watch/build/pug").extapi
reload = require("require-reload")(require)

engine = (backend) ->
  pug-cached = {}
  log = (f, opt, t, type, cache) ->
    f = f.replace(opt.basedir, '')
    backend.log.debug "[VIEW] #{f} served in #{t}ms (#type#{if cache =>' cached' else ''})"
  return (f, opt, cb) ->
    lc = {}
    if opt.settings.env == \development => lc.dev = true
    # force cache to true since we do invalidate cache. still keep opt.settings for reference.
    lc.cache = true or opt.settings['view cache']
    {viewdir, basedir} = opt
    pc = path.join(viewdir, f.replace(basedir, '').replace(/\.pug$/, '.js'))
    try
      t1 = Date.now!
      mtime = fs.stat-sync(pc).mtime
      cache = false
      ret = pug-cached[pc] = if !lc.cache => {js: reload(pc), mtime}
      else if !pug-cached[pc] or (mtime - pug-cached[pc].mtime) > 0 => {js: require(pc), mtime}
      else 
        cache = true
        pug-cached[pc]
      # cache with js - it's from pug cache. just escape to catch block
      if !ret.js => throw new Error!
      ret = ret.js(opt)
      t2 = Date.now!
      if lc.dev => log f, opt, t2 - t1, \precompiled, cache
      cb null, ret
    catch e
      t1 = Date.now!
      mtime = fs.stat-sync(f).mtime
      p = if !lc.cache or !pug-cached[f] or (pug-cached[f] and mtime - pug-cached[f].mtime > 0) =>
        new Promise (res, rej) -> fs.read-file f, (e, b) -> if e => rej e else res b
          .then (buf) -> pug-cached[f] = {buf}
      else Promise.resolve(pug-cached[f])
      p
        .then (obj) ->
          # only if mtime is set ( not fresh ) and we explicitly ask for want cache, will cache be true.
          if !(cache = obj.mtime? and lc.cache) => obj.mtime = mtime
          ret = (pug.render(obj.buf, ({} <<< opt <<< {filename: f, cache, basedir}) <<< pug-extapi))
          t2 = Date.now!
          if lc.dev => log f, opt, t2 - t1, 'from pug', cache
          cb null, ret
        .catch ->
          backend.log.error "[VIEW] #{f.replace(opt.basedir, '')} serve failed."
          cb e, null

module.exports = engine
