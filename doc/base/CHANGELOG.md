## master

 - features:
   - start script: process identification, three-fold ( see `doc/base/infrastructure.md` -> Daemon ):
     - re-exec with argv[0] as `start:<dirname>`
     - launch server with `--home <pwd>`, so `pgrep -f <pwd>` can find it
     - engine sets `process.title` to `servebase:<dirname>[:<config.sitename>]`
   - `npm stop`: stop server as a unit. start script writes `.server.pid` ( gitignored,
     removed on exit ); stop kills both the start script and its pipeline children,
     since bash defers traps while waiting on a foreground pipeline.
   - `npm run log`: live pretty log window ( `tail -f server.log | pino-pretty` ),
     decoupled from the server process.
   - `./start --noloop` ( or `-n` ): run once without auto-restart loop, for service
     managers that restart on their own ( e.g. systemd `Restart=always` ).
     example systemd unit added in `infrastructure.md`.
 - tweaks:
   - start: build server command with bash arrays so paths with spaces are safe;
     omit `-c` when no config name is given.
 - security:
   - deps: `npm audit fix` ( 46 -> 24 advisories; axios, ws, shell-quote,
     i18next-http-middleware, babel, body-parser among others )
   - pin `re2` to `~1.23.0`: 1.26.x pulls node-gyp 13 / undici 7, which needs
     `worker_threads.markAsUncloneable` ( Node >= 22.10 ) and fails to build on
     Node 20. revert to `^1.26.1` after Node 22 upgrade.
     see `context/servebase/todo/node22-and-remaining-vulns.md` for the rest.
   - volta: pin node 20.17.0 -> 20.20.2
 - docs:
   - add `doc/base/CHANGELOG.md` ( this file ) - servebase changelog lives here,
     not in root, which is reserved for derived projects.
   - `doc/base/version-control.md`: add versioning section ( servebase vs derived ).
   - commit servebase AI context as `context/servebase/`
     ( renamed from `context/project`, which is reserved for derived projects );
     `context/shared` remains gitignored.

note: production runs prebuilt js in `.backend`; run `npm run prebuild` on deploy
for the `--home` / `process.title` changes to take effect.
