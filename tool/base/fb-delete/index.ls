require! <[lderror crypto @servebase/auth]>
(backend) <- (->module.exports = it)  _
{db,config,route:{api,app}} = backend

api.get \/fb/delete-confirmation/:token, (req, res) ->
  db.query "select key,deleted from users where key = $1 limited 1", [req.params.token]
    .then (r={}) ->
      u = r.[]rows.0
      return res.send(
        if !u or u.deleted => "deleted" else "not yet deleted"
      )

api.post \/fb/delete, (req, res) ->
  secret = ((config.auth or {}).facebook or {}).clientSecret
  signed_request = req.body.signed_request
  if !(secret and signed_request) => return lderror.reject 404
  de64 = (str) -> Buffer.from(str.replace(/-/g, '+').replace(/_/g,'/'), \base64).toString!
  parse = (token, secret) ->
    [sig, payload] = token.split('.', 2)
    sig = Buffer.from(de64(sig), \binary)
    data = JSON.parse(de64(payload))
    expected-sig = crypto.createHmac(\sha256, secret).update(payload).digest!
    if !crypto.timingSafeEqual sig, expected-sig => return false
    return data
  data = parse signed_request, secret
  if !data => return lderror.reject 400
  userid = data["user_id"]
  db.query """
  select * from users
  where
    method = 'facebook' and
    deleted is not true and
    (detail->'id')::text = $1
  limit 1
  """, [userid]
    .then (r={}) ->
      if !(u = r.[]rows.0) => return lderror.reject 404
      auth.user.delete {key: u.key}
    .then ->
      res.send {
        url: "https://#{config.domain}/api/auth/fb/delete-confirmation/#{u.key}"
        confirmation_code: "#{u.key}"
      }
