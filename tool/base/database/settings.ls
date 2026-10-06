# resolve the effective postgresql settings the same way the backend does
# ( backend/engine/db/postgresql/index.ls ): when `profile` is set, the entry in
# `profiles` is merged over the base settings. reading `database` / `user` off the
# base object alone gives `undefined` for a profile-based config, and psql then
# happily creates a role and a database literally named "undefined".
settings = (pg = {}) ->
  if !pg.profile => pg else {} <<< pg <<< (pg.profiles?[pg.profile] or {})

# fail loudly instead of passing `undefined` on to psql.
required = (cfg = {}) ->
  missing = <[database user]>.filter -> !cfg[it]
  if missing.length =>
    throw new Error "postgresql config has no #{missing.join ' / '} ( profile: #{cfg.profile or 'none'} )"
  cfg

module.exports = {settings, required}
