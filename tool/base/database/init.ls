require! <[path child_process os]>
{exec-sync} = child_process
fs = require \fs-extra
{grant-sql} = require \./grant

root    = path.join __dirname, \../../..
sql-dir = path.join root, \config/base/db

# same `-c <name>` convention as `./start`, so a repo holding several site
# configs can init the matching database instead of only `secret`.
cfg-name = do ->
  argv = process.argv.slice 2
  idx = argv.findIndex -> it in <[-c --config-name]>
  if idx >= 0 and argv[idx + 1] => argv[idx + 1] else \secret

secret = require path.join(root, "config/private/#cfg-name")
cfg      = secret.db.postgresql
dbname   = cfg.database
username = cfg.user
password = cfg.password

run = (cmd) ->
  try exec-sync cmd, {stdio: \inherit}; true
  catch e => false

psql-sql = (sql, db = \postgres) ->
  f = path.join os.tmpdir!, "init-#{Date.now!}.sql"
  fs.write-file-sync f, sql
  ok = run "psql -U postgres -d #{db} -f #{f}"
  fs.unlink-sync f
  ok

psql-file = (file, db = dbname) ->
  run "psql -U postgres -d #{db} -f #{file}"

custom-sql-files = []
try
  if secret.base
    custom-dir = path.join root, "config/#{secret.base}/db"
    if fs.path-exists-sync custom-dir
      custom-sql-files =
        fs.readdir-sync custom-dir
          .filter -> /\.sql$/.test it
          .sort!
          .map -> path.join custom-dir, it
catch e => # skip

console.log "\n[init] creating role #{username}..."
psql-sql """
  DO $$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '#{username}') THEN
      CREATE ROLE #{username} LOGIN PASSWORD '#{password}';
    END IF;
  END
  $$;
"""

console.log "\n[init] creating database #{dbname}..."
db-exists = try
  r = exec-sync "psql -U postgres -tAc \"SELECT 1 FROM pg_database WHERE datname='#{dbname}'\"", {encoding: \utf8}
  r.trim! == \1
catch => false

unless db-exists
  psql-sql "CREATE DATABASE #{dbname} OWNER #{username};"

console.log "\n[init] running config/base/db/init.sql..."
psql-file path.join(sql-dir, \init.sql)

for f in custom-sql-files
  rel = path.relative root, f
  console.log "\n[init] running #{rel}..."
  psql-file f

console.log "\n[init] granting privileges..."
psql-sql (grant-sql dbname, username), dbname

console.log "\n[init] done."
