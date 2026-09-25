## master

 - features:
   - `@servebase/erratum`: `lockdown` - a toggle that routes every error to one
     dialog instead of answering each on its own terms. The per-error handling
     is right while the error is the problem, and wrong once the page itself
     cannot be trusted: from there each further action runs against a state
     nobody can vouch for. A toggle rather than a constructor option because
     when it is safe to engage is a runtime question - start-up has its own
     ordinary permission and fetch failures, and locking on those would break
     the page for everyone. Fires once per engagement, so a failing page cannot
     stack covers, and a dialog that throws is reported rather than looped.
     See `module/base/erratum/README.md` -> Lockdown.
   - the backend runs from the livescript sources everywhere now, production
     included. compiling all of `backend/` costs about 0.25s against a startup
     otherwise spent requiring the npm tree and reaching db / redis, and in
     exchange production stops running a code path nobody develops against and
     can no longer quietly serve last month's code after a forgotten
     `npm run prebuild`. `.backend` remains as the legacy path and as somewhere
     to stand if the sources cannot be run: its presence is the whole switch -
     in production, if `.backend/engine/index.js` exists, `start` runs it, and
     warns on every start that it did, plus a second line when a source under
     `backend/` is newer than the build. development never takes it, as it never
     has, so a stray prebuild cannot leave a developer editing files nothing
     runs. no flag, nothing to configure; `rm -rf .backend` is how a project
     leaves it behind. `npm run ping` reports which of the two a
     running server took ( `backend: source | prebuilt` ). see
     `doc/base/infrastructure.md` -> Prebuilt or Source.
   - `npm run servers` ( `tool/base/servers` ): every servebase process on this
     machine, not just this project's - name, port, mode, uptime, project root.
     with several terminals and coding agents starting servers, which of them is
     running what stops being answerable from any one project directory. found in
     `ps` ( `start:<dirname>` and the engine's `servebase:<dirname>[:<sitename>]`
     title ) rather than a registry, so it stays true across `kill -9`, reboots
     and `--force`; the root is each process's cwd and the details come from that
     project's own `ping`. what counts as running is that ping, not the title: an
     engine it cannot reach is listed separately rather than guessed about. a
     `start` with no engine under it is flagged - a server still coming up, or
     one stuck failing to start. `-j` for json.
 - tweaks:
   - the server reaches `listen` in about 0.95s rather than 1.36s. nothing about
     express was slow - building the app, mounting every router and taking the
     port is 16ms of that - but three requires that only the builder and the mail
     queue ever need were paid on the way there by every server, whether it built
     anything or sent any mail or not. jsdom alone is ~450ms of require.
     `@plotdb/srcbuild`, `@plotdb/block` and jsdom now load inside `watch`, which
     runs after `listen` and only when build is enabled, and jsdom only in the
     branch that has no block manager of its own to use. `dompurify` and the jsdom
     window it needs are built on the first html mail sanitized instead of at
     module load: `mail-queue.ls` is required unconditionally by the engine, while
     the queue itself is only built when mail is configured, so a server that
     sends no mail used to pay for a window it never opened. `livescript` is now
     required explicitly by the engine - it used to arrive as a side effect of
     srcbuild's `ext/pug`, and `config.from` reading a `.ls` config depends on it
     being there, which is too much to leave resting on an import order.
   - `config/base/nginx/cloudflare-notice.md`: behind cloudflare `$remote_addr` is a
     CF edge node, so access.log, the `X-Real-IP` / `X-Forwarded-For` handed to
     `@apiserver`, and a would-be `limit_req` are all wrong, and silently so. the fix
     ( nginx realip ) is one include away but needs a generated, shared range list, so
     nothing in `config.ngx` changes yet - see the three tasks dated 20260912 under
     `context/servebase/tasks/todo/`.
 - fixes:
   - `@servebase/mail`: `render` sanitizes the html body with an allowlist
     matching the editor toolbar, and throws if no DOMPurify is available. set it
     through `get-purify`; the backend injects a jsdom one.
   - `.gitignore` excludes `**/.view/.@root/`, and now says what committing
     `.view/` means rather than leaving it to whatever the patterns happen to do.
     An app that re-includes its own frontend ( `!frontend/web` ) commits that
     frontend's `.view/`: `frontend/*` covers the directory, and the per-app
     `static` / `.view` exclusions under it name only `base` and `auth`. That
     turns out to be what such an app wants - a precompiled view inlines the text
     of everything it includes, and the view engine's staleness check compares one
     `.pug` against its own `.js` and nothing else, so an `npm i` that swaps an
     `@/...` include leaves the compiled view holding the old version with nothing
     to notice; committing `.view/` next to the lockfile is what keeps the two in
     step. What it should not have committed is `.@root/`, where srcbuild puts pug
     compiled from outside `src/pug` - runtime-deployed `user/template/...`
     included. That subtree carries user data and is the one part of `.view/` that
     genuinely has to be built per request. Also drops `web/.view` and
     `module/**/web/.view`, which named a directory layout this project stopped
     using, and read as protection that was not there. See
     `doc/base/infrastructure.md` -> Build Artifacts.
   - `backend/base/manager.ls` is no longer loaded as a route. it sits in the demo
     route folder only so that `config.build.block.manager` has somewhere to point,
     but that folder is scanned and everything in it is called as a route: it was
     called with the backend as its `{base}`, built a block manager nobody kept,
     and - the reason it is now excluded rather than merely harmless - pulled jsdom
     into the startup path, ~380ms before `listen`. the builder requires it itself,
     after `listen`, when the config names it.
   - `frontend/base/src/pug/static.pug` builds again. it read `settings.domain` and
     `settings.sysinfo()`, which the view engine hands to a per-request render but
     the static build deliberately withholds - baking them into a built file mixes
     dev and production domains and pins a version that goes stale on the next
     deploy. so every start logged `Cannot read properties of undefined ( reading
     'domain' )` and produced no `static.html`, from a demo page whose job is to
     show what a static page is. it now shows one, and says why it has no
     `settings`, with `view.pug` beside it as the per-request counterpart.
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
   - `@plotdb/srcbuild` -> `^0.1.7`, and `<feroot>` no longer carries a copy of its
     own. 0.1.7 fixes a module symlinked into the document root after the watcher
     started never reporting another change: chokidar's fsevents backend only installs
     a watcher for what was there when it began, and a symlink - unlike a directory -
     is not covered by anything else, so a frontend dependency added while the dev
     server was up left its bundle stale until a restart, silently. it also stops a
     source being rebuilt underneath a build ( every module's build script opens with
     `rm -rf dist` ) from reporting as a failure; see its CHANGELOG.
     `<feroot>/package.json` used to depend on srcbuild too, and the note under
     `^0.1.4` above says why that was dangerous: `lib.pug` is injected by path and
     resolved from the frontend root, so whichever copy lands there wins over the one
     actually running, and a stale one is silent - pages build, and `asseturl`,
     `bundleurl` and `hashfile` are just absent. it had drifted to `^0.1.4` against a
     root running `^0.1.6`. with no copy in `<feroot>` at all, node resolution walks up
     to the root package and the two cannot diverge. nothing in `<feroot>` imports
     srcbuild; the dependency existed only to place that file.
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

note: production ran prebuilt js in `.backend` at the time of this release, so
`npm run prebuild` on deploy was needed for the `--home` / `process.title` changes
to take effect. since then the sources are what runs; see Prebuilt or Source.
