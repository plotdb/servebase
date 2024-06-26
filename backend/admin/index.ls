(backend) <- (->module.exports = it)  _
{db,config,route:{api},session} = backend
if config.base != \base => return

require! <[express lderror re2 curegex @plotdb/suuid]>
require! <[@servebase/backend/aux @servebase/backend/throttle]>

route = aux.routecatch express.Router {mergeParams: true}
api.use \/admin, route
route.use aux.is-admin

route.get \/cachestamp, (req, res, next) ->
  res.send "#{backend.cachestamp}"

route.post \/cachestamp, (req, res, next) ->
  backend.cachestamp = new Date!getTime!
  res.send "#{backend.cachestamp}"

route.get \/throttle/reset, (req, res, next) ->
  throttle.reset!
  res.send!

route.post \/users/, (req, res, next) ->
  if !(keyword = req.body.keyword) => return lderror.reject 400
  db.query """
  select u.*
  from users as u
  where (u.username = $1 or u.key = $2) and u.deleted is not true
  order by u.createdtime desc
  """, [keyword, if isNaN(+keyword) => null else +keyword]
    .then (r={}) ->
      rows = r.[]rows
      rows.map -> delete it.password
      res.send rows

re-email = curegex.tw.get('email', re2)
is-email = -> return re-email.exec(it)

route.post \/user/delete, (req, res) ->
  if !(username = req.body.username) => return lderror.reject 400
  if !is-email(username) => return lderror.reject 400
  backend.auth.user.delete {username} .then -> res.send {}

route.post \/user/, (req, res) ->
  if <[username displayname password]>.filter(->!req.body[it]).length => return lderror.reject 400
  {username,displayname,password} = req.body
  if !is-email(username) => return lderror.reject 400
  if password.length < 8 => return lderror.reject 400
  # TODO verify password based on customized rules, if needed.
  detail = {username, displayname}
  config = {}
  method = \local
  db.user-store.create {username, password, method, detail, config}
    .then ->
      delete it.password
      res.send it

route.post \/user/:key/password, aux.validate-key, (req, res) ->
  key = +req.params.key
  if !(password = req.body.password) or password.length < 8 => return lderror.reject 400
  # TODO verify password based on customized rules, if needed.
  db.query "select password from users where key = $1", [key]
    .then ({rows}) -> if !rows or !rows.0 => return lderror.reject 404
    .then -> db.user-store.hashing password, true, true
    .then (pw-hashed) ->
      db.query "update users set (method,password) = ('local',$1) where key = $2", [pw-hashed, key]
    .then -> session.delete {user: key}
    .then -> res.send!

route.post \/user/:key/email, aux.validate-key, (req, res) ->
  key = +req.params.key
  if !((email = req.body.email) and is-email(email))  => return lderror.reject 400
  db.query "select key from users where username = $1", [email]
    .then (r={}) ->
      if r.[]rows.length => return lderror.reject 1011
      db.query "update users set username = $1 where key = $2", [email, key]
    .then -> session.delete {user: key}
    .then -> res.send!

route.post \/user/:key/logout, aux.validate-key, (req, res) ->
  session.delete {user: +req.params.key}
    .then -> res.send!

route.delete \/user/:key, aux.validate-key, (req, res, next) ->
  key = +req.params.key
  session.delete {user: key}
    .then -> db.query "delete from users where key = $1", [key]
    .catch ->
      # delete user failed. there might be some additional rows in other table owned by this user.
      # just remove the username, displayname and mark the account as deleted.
      db.query """
      update users
      set (username,displayname,deleted)
      = (('deleted-' || key),('user ' || key),true)
      where key = $1
      """, [key]
    .then -> res.send!

route.put \/su/:key, aux.validate-key, (req, res) ->
  key = +req.params.key
  session.login {user: key, req} .then -> res.send!

route.post \/invite-token, (req, res) ->
  detail = {count: (req.body or {}).count or 1, used: 0}
  token = (req.body or {}).token or suuid!
  db.query """select key from invitetoken where token = $1 and deleted is not true""", [token]
    .then (r={}) ->
      if r.[]rows.length => return lderror.reject 1011
      db.query """
      insert into invitetoken (owner,token,detail)
      values ($1, $2, $3) returning token""", [req.user.key, token, detail]
    .then -> res.send {token}
