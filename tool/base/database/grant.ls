grant-sql = (dbname, username) -> """
  GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO #{username};
  GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO #{username};
  GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO #{username};
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES    TO #{username};
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO #{username};
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON FUNCTIONS TO #{username};
"""

module.exports = {grant-sql}

if require.main is module
  require! <[@servebase/tool/init]>
  init!
    .then ({backend}) ->
      cfg = backend.config.db.postgresql
      console.log "\\c #{cfg.database}"
      console.log grant-sql cfg.database, cfg.user
    .then -> process.exit!
