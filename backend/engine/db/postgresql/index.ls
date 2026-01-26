require! <[pg lderror ./session-store ./user-store @servebase/backend/aux]>

pg.defaults.poolSize = 30

database = (backend, opt = {}) ->
  @config = config = backend.config
  @log = log = backend.log.child {module: 'db'}
  {user, password, host, database, port, poolSize} = if !config.db.postgresql.profile => config.db.postgresql
  else {} <<< config.db.postgresql <<< (config.db.postgresql?profiles[config.db.postgresql.profile] or {})
  @uri = "postgres://#{user}:#{password}@#{host}#{if port => ':' + port else ''}/#{database}"

  @pool = new pg.Pool do
    connectionString: @uri
    max: poolSize or 20
    idleTimeoutMillis: 30000
    connectionTimeoutMillis: 2000

  @pool.on \error, (err, client) -> log.error "db pool error".red
  @session-store = new session-store {
    db: @, session: backend.config.session.max-age, logger: log, query-only: opt.query-only
  }
  @user-store = new user-store {db: @, config, logger: log}

  @

database.prototype = Object.create(Object.prototype) <<< do
  query-audit: (q, p, c) ->
    audit = c?audit
    [do-audit, is-atomic] = [!!audit, (audit?atomic or !(audit?atomic?))]
    @pool.connect!
      .then (client) ->
        if !do-audit => return (
          <- client.query q, p .finally _
          client.release!
        )
        req = audit.req
        Promise.resolve!
          .then -> if is-atomic => client.query 'BEGIN'
          .then ->
            (query-result) <- client.query q, p .then _
            detail = audit{action, user} <<< {
              data: ({ new: (audit.new or p)
              } <<< ( if audit.old? => {old: audit.old} else {}  # old
              ) <<< ( if req?query => {query: req.query} else {} # query
              ))
            } <<< (if req => path: req.path, ip: aux.ip req else {})
            client.query """
            insert into auditlog (action,option,session,ip,owner,detail) values ($1,$2,$3,$4,$5,$6)
            """, [audit.action, audit.option, req?sessionID, detail.ip, audit.user, detail]
            return if !is-atomic => query-result
            else client.query 'COMMIT' .then -> query-result
          .catch (e) ->
            return if !is-atomic => Promise.reject e
            else client.query 'ROLLBACK' .finally -> Promise.reject e
          .finally -> client.release!

      .catch (e) ->
        Promise.reject new lderror {err: e, id: 0, query: q, message: "database query error"}

  query: (q, p) ->
    @pool.connect!
      .then (client) -> 
        (ret) <- client.query q, p .then _
        client.release!
        return ret
      .catch ->
        Promise.reject new lderror {err: it, id: 0, query: q, message: "database query error"}

module.exports = database

