## master

 - fixes:
   - `start` no longer retries a server that cannot start. a run dying within
     `SB_CRASH_FAST` seconds ( 10 ) counts as a failed start; `SB_CRASH_MAX` of
     them in a row ( 5 ) and the loop backs off, gives up and exits nonzero,
     instead of respawning a doomed process every few seconds until someone
     notices the fan. it leaves `.server.crash` behind - when, how often, why,
     tail of the log - which `npm run ping` reports whenever a project has no
     server, plus an optional `SB_CRASH_HOOK` for reaching the outside world.
     the hook runs under `SB_CRASH_HOOK_TIMEOUT` ( 30s ) and is killed if it
     overruns: what stops a server from starting often stops a mail call too,
     and reporting the hang must not become one. see `doc/base/infrastructure.md`
     -> Giving Up.
   - `tool/base/ping` tells a busy server from an absent one. the control socket
     is served from the event loop that also serves the site, and `localctl.init`
     runs only after `listen()` has taken the port, so between "port taken" and
     "able to answer" the socket accepts and nothing replies - curl reports 28,
     not 7. reading only curl's output made that window look like "no server",
     which is exactly when a second `./start` is most likely; the loser then
     spun on EADDRINUSE. such a server now reports `running: true, busy: true`.
   - `start` refuses to start over a server that is still coming up, and removes
     `.server.pid` only if it is still its own. the ping guard cannot see a
     server that has not opened its socket yet, so a live pid in `.server.pid` is
     now checked too; and a process that lost the race used to delete the
     winner's pidfile as it exited, leaving `npm run stop` with nothing to kill
     and the surviving server findable only by hand in `ps`.
 - features:
   - content-addressed frontend assets, off by default. `config.build.hash.enabled`
     turns it on; `mode` picks `filename` ( `<name>.<hash>[.min].<ext>`, servable as
     immutable ) or `query` ( `<name>.min.js?v=<hash>`, nothing accumulates ). covers
     bundles, compiled `.ls` and compiled `.styl`. see
     `doc/base/infrastructure.md` -> Asset Cache Policy.
   - `npm run cachecheck -- <origin>`: assert the edge applies the cache policy the
     build assumes. urls are read from the build's own manifest, so it checks what the
     project actually ships. `-j` json, `-q` exit code only, `-s` warnings fail too,
     `-k` self-signed cert. a wrong cache policy is silent otherwise.
   - `module/base/refresh` ( WIP, not wired ): the piece that tells an already-open page
     that the deploy underneath it moved on. content addressing keeps such a page
     working but silently old, and backend api drift is the part no asset strategy can
     fix. the module is self-contained - nothing outside it is touched, so nothing in a
     running site changes until it is wired in. see its README.
 - tweaks:
   - document where the files nobody generates belong: `<feroot>/src/raw`, copied
     verbatim into the document root ( `doc/base/infrastructure.md` -> Generated and
     Hand-Written Files ). they sit directly in `static/` today, which makes that
     directory the only copy of some of its contents and derived for the rest, with
     nothing able to tell the two apart. the section carries the migration recipe -
     build into an empty `static/` and diff - and is explicit that a project must
     finish it before acting on what follows from it, since a derived project merges
     this document long before it does the move, and `rm -rf static` on an
     unmigrated tree deletes files that exist nowhere else.
   - nginx sample gains the asset cache rules: content-addressed urls immutable with a
     `try_files` fallback to the plain name, plain build output and fedep `main`/`local`
     symlinks no-cache, exact-version lib directories immutable. each block repeats the
     server-level security headers, since `add_header` does not inherit. a
     `map $arg_v` makes `mode: 'query'` cacheable too - `location` matching ignores the
     query string, so without it a `?v=` url is served no-cache and the mode buys
     nothing.
   - the express view engine is handed the content-hash store instead of re-reading the
     manifest off disk.
   - document which build artifacts belong in version control and why - it follows from
     whether the running server needs them, not from taste ( `doc/base/infrastructure.md`
     -> Build Artifacts / Deploying Build Artifacts ). includes the `.gitattributes`
     trick for projects that commit `static/`, and why those projects want
     `mode: 'query'` rather than `filename`.
   - `@plotdb/srcbuild` -> `^0.1.4`, in the root package, in the module workspaces and
     in `<feroot>` - all of them have to move together, because `lib.pug` is injected by
     path and resolved from the frontend root, so whichever copy lands there wins.
     0.1.1 fixes content addressing across a warm restart: the url -> pages index was
     memory-only and is only filled while a page renders, so a restart that rebuilt
     nothing left it empty - the first edit after it moved the hash without
     re-rendering the pages that embed it. 0.1.2 warns when the injected `lib.pug` is
     not the one shipped with the running srcbuild - the failure above was found that
     way, and it is otherwise silent. 0.1.3 moves minification onto a worker thread, so
     a build no longer stalls the event loop of the server it shares a process with,
     and stops a minifier error from silently producing an empty file. 0.1.4 adds
     `src/raw` ( see Generated and Hand-Written Files above ); nothing in this project
     uses it yet, and the older whitelist copier it sits beside is unchanged.
 - bug fix:
   - ( in srcbuild 0.1.0, see its CHANGELOG ) dependency-graph traversal hung on cycles
     and grew multiplicatively on shared includes; a file whose dependency analysis
     failed was silently never rebuilt; the bundle reverse index only ever grew; bundles
     were rewritten on every event; the express view engine ran a second full build of
     the whole pug tree in parallel with the real one.


## 0.0.1 - 2026-08-25

 - features:
   - start script: process identification, three-fold ( see `doc/base/infrastructure.md` -> Daemon ):
     - re-exec with argv[0] as `start:<dirname>`
     - launch server with `--home <pwd>`, so `pgrep -f <pwd>` can find it
     - engine sets `process.title` to `servebase:<dirname>[:<config.sitename>]`
   - `npm stop`: stop server as a unit. start script writes `.server.pid` ( gitignored,
     removed on exit ); stop kills both the start script and its pipeline children,
     since bash defers traps while waiting on a foreground pipeline.
   - `npm run log`: pretty log window over `server.log`, decoupled from the server
     process. now backed by `tool/base/logview`, so it takes arguments
     ( `npm run log -- <opt>` ): `-n`/`-a` line window in a pager instead of follow,
     `-f` follow, `-m` module, `-l` min level, `-g` regex, `-s`/`-e` date range and
     `-d` dayspan ( yyyymmdd, UTC ), plus an alternate log path. bare `npm run log`
     still follows, as before. see `doc/base/index.md` -> Log.
   - `./start --noloop` ( or `-n` ): run once without auto-restart loop, for service
     managers that restart on their own ( e.g. systemd `Restart=always` ).
     example systemd unit added in `infrastructure.md`.
   - `npm run ping` ( `tool/base/ping` ): report whether a server is running for
     this project, and which one - title, pid, home, config name, port, mode,
     version, uptime. `-j` for raw json, `-q` for exit code only ( 0 up / 1 down ),
     so agents and scripts can branch on it. liveness is decided by connecting to
     `.localctl.sock`, not by `.server.pid`, which survives SIGKILL and whose pid
     may be reused. backed by a new engine-level localctl handler `GET /info`.
     see `doc/base/index.md` -> Ping.
   - `./start` refuses to launch a second server for the same project ( prints the
     running one's info and exits 1 ); `--force` / `-F` overrides. checked before
     the exit traps are installed, so bailing out never removes the running
     server's `.server.pid`.
 - tweaks:
   - start: build server command with bash arrays so paths with spaces are safe;
     omit `-c` when no config name is given.
   - localctl callers pass `curl -q` so a user's `~/.curlrc` ( e.g. a `-w` timing
     format ) cannot corrupt the response. affects `npm run cachestamp` too.
 - security:
   - deps: `npm audit fix` ( 46 -> 24 advisories; axios, ws, shell-quote,
     i18next-http-middleware, babel, body-parser among others )
   - pin `re2` to `~1.23.0`: 1.26.x pulls node-gyp 13 / undici 7, which needs
     `worker_threads.markAsUncloneable` ( Node >= 22.10 ) and fails to build on
     Node 20. revert to `^1.26.1` after Node 22 upgrade.
     see `context/servebase/todo/node22-and-remaining-vulns.md` for the rest.
   - volta: pin node 20.17.0 -> 20.20.2
   - replace native `re2` with `re2js` ( pure-JS RE2 port ) via curegex 0.1.0
     engine support - no more native compilation issues, works on any Node
     version; also clears re2's own moderate advisory ( 24 -> 23 )
 - docs:
   - add `doc/base/CHANGELOG.md` ( this file ) - servebase changelog lives here,
     not in root, which is reserved for derived projects.
   - `doc/base/version-control.md`: add versioning section ( servebase vs derived ).
   - commit servebase AI context as `context/servebase/`
     ( renamed from `context/project`, which is reserved for derived projects );
     `context/shared` remains gitignored.

note: production runs prebuilt js in `.backend`; run `npm run prebuild` on deploy
for the `--home` / `process.title` changes to take effect.
