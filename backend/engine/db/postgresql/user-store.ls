require! <[crypto bcrypt lderror re2 curegex @loadingio/debounce.js]>

re-email = curegex.tw.get('email', re2)
is-email = -> return re-email.exec(it)

user-store = (opt = {}) ->
  @config = opt.config or {}
  @policy = pw = (@config.policy or {}).password or {}
  pw.renew = if !pw.renew or isNaN(pw.renew) => 0 else (+pw.renew >?= 1)
  if typeof(pw.track) == \object =>
    pw.track.day = if !pw.track.day or isNaN(pw.track.day) => 0 else (+pw.track.day >?= 1)
    pw.track.count = if !pw.track.count or isNaN(pw.track.count) => 0 else (+pw.track.count >?= 1)
  else
    pw.track = {day: if !pw.track or isNaN(pw.track) => 0 else (+pw.track >?= 1)}
  @db = opt.db
  @

user-store.prototype = Object.create(Object.prototype) <<< do
  # store whole object ( no serialization )
  serialize: (u = {}) -> Promise.resolve u
  deserialize: (v = {}) -> Promise.resolve v

  # md5 is bad, because
  #  - it's really fast - thus, also really fast for brute force cracking.
  #  - it loses entropy for information > 128bits
  # however, we actually double hash md5 by bcrypt and:
  #  - bcrypt.hash is way much slower
  #  - password is not common with more than 128bits entropy. 128bits is usually enough.
  # additionally:
  #  - md5 minimizes the risk of DDoS attacks with extremely long password.
  # while double hashing is kinda useless but it's generally equivalent secure:
  #  - https://stackoverflow.com/questions/348109
  # ref:
  #  - `chaining md5 and bcrypt`, https://security.stackexchange.com/questions/119680/
  #  - `fb also does this`, wbl, https://news.ycombinator.com/item?id=19171957
  hashing: (password, doMD5 = true, doBcrypt = true) -> new Promise (res, rej) ->
    ret = if doMD5 => crypto.createHash(\md5).update(password).digest(\hex) else password
    if doBcrypt => bcrypt.genSalt 12, (e, salt) -> bcrypt.hash ret, salt, (e, hash) -> res hash
    else res ret

  compare: (password='', hash) -> new Promise (res, rej) ->
    md5 = crypto.createHash(\md5).update(password).digest(\hex)
    bcrypt.compare md5, hash, (e, ret) -> if ret => res! else rej new lderror(1012)

  get: ({username, password, method, detail, create}) ->
    username = username.toLowerCase!
    if !(is-email username) => return Promise.reject new lderror(1015)
    @db.query "select * from users where username = $1", [username]
      .then (ret = {}) ~>
        if !(user = ret.[]rows.0) and !create => return lderror.reject 1034
        if !user => return @create {username, password, method, detail}
        if !(method == \local or user.method == \local) =>
          delete user.password
          return user
        @compare password, user.password .then ~> user
      .then (user) ~>
        if user.{}config.{}consent.cookie => return user
        user.config.consent.cookie = new Date!getTime!
        @db.query "update users set config = $2 where key = $1", [user.key, user.config] .then -> user
      .then (user) ->
        delete user.password
        return user

  create: ({username, password, method, detail, config}) ->
    username = username.toLowerCase!
    if !config => config = {}
    if !is-email(username) => return Promise.reject new lderror(1015)
    Promise.resolve!
      .then ~> if method == \local => @hashing(password) else password
      .then (password) ~>
        displayname = if detail => detail.displayname or detail.username
        if !displayname => displayname = username.replace(/@[^@]+$/, "")
        config.{}consent.cookie = new Date!getTime!
        user = { username, password, method, displayname, detail, config, createdtime: new Date! }
        @db.query "select key from users where username = $1", [username]
          .then (r={}) ~>
            if r.[]rows.length => return lderror.reject 1014
            @db.query """
            insert into users (username,password,method,displayname,createdtime,detail,config)
            values ($1,$2,$3,$4,$5,$6,$7)
            returning key
            """, [
              username, password, method, displayname,
              new Date!toUTCString!, detail, config
            ]
          .then (r={}) ~>
            if !(r = r.[]rows.0) => return Promise.reject 500
            user <<< r{key}
            @password-track {user, hash: password}
          .then -> user

  password-track: ({user, password, hash}) ->
    if !(@policy.track.day or @policy.track.count or @policy.renew)
    or !(hash or password) => return Promise.resolve!
    # debounce password track to control tracking frequency
    debounce 1000
      .then -> if hash => that else @hashing(password)
      .then (hash) ~> @db.query "insert into password (owner, hash) values ($1, $2)", [user.key, hash]
      .then ~>
        # it's possible that we are here even if track is not configured.
        # in this case, we track for a minimal amount. (count = 1, day = 1)
        count = @policy.track.count >? 1
        (r={}) <~ @db.query """
        select key from password
        where owner = $1
        order by key desc limit $2
        """, [user.key, count] .then _
        if !(p = r.[]rows[* - 1]) => return
        @db.query "delete from password where owner = $1 and key < $2", [user.key, p.key]
      .then ~>
        day = @policy.track.day >? 1
        @db.query """
        delete from password
        where owner = $1 and createdtime < now() - make_interval(0,0,$2)
        """, [user.key, day]

  password-due: ({user}) ->
    # always not due ( within 180 days ) if renew is not enabled.
    if !@policy.renew => return Promise.resolve(-180 * 86400 * 1000)
    @db.query """
    select * from password
    where owner = $1
    order by createdtime desc limit 1
    """, [user.key]
      .then (r={}) ~>
        freq = @policy.renew * (86400 * 1000)
        now = Date.now!
        checktime = if (entry = r.[]rows.0) =>
          # use max so we can use a future snooze to delay renewal reuqest
          Math.max(
            new Date(entry.snooze or 0).getTime!,
            new Date(entry.createdtime).getTime! + freq
          )
        else new Date(user.createdtime).getTime! + freq
        return now - checktime
  ensure-password-unused: ({user, password}) ->
    track = @policy.track
    if !(track.day or track.count) =>
      qs = "select * from password where owner = $1 order by key desc limit 1"
    else
      qs = "select * from password where owner = $1"
      if track.day => qs += " and createdtime >= now() - make_interval(0,0,0,$2)"
      qs += " order by key desc"
      if track.count => qs += " limit $#{if track.day => 3 else 2}"
    params = (
      [user.key] ++
      (if track.day => [track.day >? 1] else []) ++
      (if track.count => [track.count >? 1] else [])
    )
    @db.query qs, params
      .then (r={}) ~>
        ps = r.[]rows.map (p) ~> @compare(password, p.hash).then(->1).catch(->0)
        Promise.all ps
      .then (r=[]) ->
        if r.filter(->it).length => return lderror.reject 1036

module.exports = user-store
