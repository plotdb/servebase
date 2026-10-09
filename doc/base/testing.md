# Testing

Tests are plain scripts, no framework. Each one asserts for itself and reports through its exit
code, so it runs on its own with `lsc` as well as under the runner. `npm test` finds them across
the root and every workspace listed in `package.json`, runs each in its own process and sums up.


## Where tests go

Every workspace ( and the root ) keeps its tests under `test/`, split by what they need:

 - `test/unit/`: no outside service. Fakes stand in for databases, mail transports, captcha
   providers and the like. Fast, and always run.
 - `test/integration/`: needs something real - a local postgres, usually. Run only when asked
   ( `--integration` ). Create its own scratch resources ( e.g. a throwaway database ) and remove
   them when done; never touch a database someone works with.

Each `.ls` ( or `.js` ) file directly in those folders is one test. Put helpers in a subfolder or
under another name so the runner does not pick them up as tests.


## Running

    npm test                          # unit tests everywhere
    npm test -- --integration         # unit and integration tests
    npm test -- auth mail             # only tests whose path contains `auth` or `mail`
    npm test -- --integration mail    # filters work with --integration too

    ./node_modules/.bin/lsc module/base/captcha/test/unit/once.ls    # a single test, directly

The runner exits non-zero when any test fails, or when nothing matches the given filters.


## Writing a test

 - Exit `0` when everything passes, `1` when something fails. Exit `77` to skip - e.g. an
   integration test that cannot reach postgres. A skip is reported but is not a failure.
 - A test that blows up ( an uncaught exception, a non-zero exit of any other value ) counts as
   failed, so there is no need to catch everything.
 - Print one line per check, so a failure can be read without opening the test. A small `ok`
   helper is enough:

        failed = 0
        ok = (cond, msg) ->
          console.log "  #{if cond => 'ok  ' else 'FAIL'} #msg"
          if !cond => failed := failed + 1
        # ... checks ...
        process.exit(if failed => 1 else 0)

 - Require what is under test by path from `__dirname` ( e.g. `../../dist/lib/index.js` ), so the
   test runs from any working directory.
 - Begin the file with a short comment: what it covers, what it fakes, and how to run it alone.

See `module/base/captcha/test/unit/once.ls` for a unit test with a faked provider, and
`module/base/mail/test/integration/transport.ls` for an integration test with a scratch database.
