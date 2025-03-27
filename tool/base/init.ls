require! <[fs @servebase/config @servebase/backend]>

init = ->
  secret = config.from 'private/secret'
  b = new backend {config: secret}
  (backend) <- b.prepare!then _
  logger = backend.log.child {module: \patch}
  {db,mail-queue} = backend
  return {logger, db, mail-queue, secret, backend}

module.exports = init
