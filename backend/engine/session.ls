require! <[lderror]>

session = (opt = {}) ->
  @db = opt.db
  @log = opt.log-server
  @

session.prototype = Object.create(Object.prototype) <<<
  delete: ({user}) ->
    # alternatively use session store clear?
    @db.query "delete from session where owner = $1", [user]
  sync: ({req, user, obj}) ->
    # sync update all session for the same user with the same user object
    # however expression-save with `resave = true` write user object back to session store
    # so we have to also update req.user to prevent inconsistency.
    Promise.resolve!
      .then ~>
        if obj => return Promise.resolve(obj)
        (r = {}) <~ @db.query """select * from users where key = $1 and deleted is not true""", [user] .then _
        return r.[]rows.0
      .then (obj) ~>
        if !obj => return
        req.user <<< obj
        @db.query """
        update session set detail = jsonb_set(detail, '{passport,user}', ($1)::jsonb)
        where owner = $2
        """, [JSON.stringify(obj), user]
  login: ({user, req}) ->
    # this login should be used only for updating session data.
    # normal login process should be done in backend/auth/index.ls,
    # and go through `get-user` for additional check.
    # this may regenerate session id and csrftoken
    # so may lead to inconsistency between tabs with the same session id.
    # alternatively req.session.reload() may be used
    # so we should consider this as a deprecated and consider not to use this.
    @db.query "select * from users where key = $1 and deleted is not true", [user]
      .then (r={}) ->
        if !(u = r.[]rows.0) => return lderror.reject 404
        (res, rej) <- new Promise _
        req.login u, (e) -> if e => rej(e) else res!

module.exports = session
