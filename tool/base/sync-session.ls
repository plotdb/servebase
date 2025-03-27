require! <[@servebase/backend @servebase/config yargs re2 curegex ./init]>

argv = yargs process.argv.slice 2
  .option \user, do
    alias: \u
    description: "user key"
    type: \string
  .help \help
  .alias \help, \h
  .check (argv, options) ->
    if curegex.tw.get('email', re2).exec(argv.u) => return true
    if argv.u and !isNaN(argv.u) => return true
    throw new Error("user key required and should be a number")
  .argv

({secret, db, backend}) <- init!then _
Promise.resolve!
  .then ->
    if !isNaN(+argv.u) => return Promise.resolve(+argv.u)
    db.query "select key from users where username = $1 and deleted is not true", [argv.u]
      .then (r={}) ->
        if !(u = r.[]rows.0) => return Promise.reject new Error("no such user.")
        u.key
  .then (key) ->
    backend.session.sync {user: key}
  .then ->
    console.log \done.
    process.exit!
