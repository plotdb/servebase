# Infrastructure

## Daemon

Node server should run as a Daemon with auto-restart mechanism. This can be done via:

 - managed by Container - default option
 - as a service - outside container
   - use `sysvinit` or `systemd`:
     - systemd: https://nodesource.com/blog/running-your-node-js-app-with-systemd-part-1
   - with systemd, run `./start --noloop` so restart is handled by systemd
     ( `Restart=always` ) instead of the inner bash loop. example unit:

         [Unit]
         Description=<project-name> server
         After=network.target

         [Service]
         Type=simple
         WorkingDirectory=/path/to/project
         Environment=NODE_ENV=production
         ExecStart=/path/to/project/start --noloop
         Restart=always
         RestartSec=1

         [Install]
         WantedBy=multi-user.target

     stdout goes to journald; follow it live with `journalctl -u <unit> -f`,
     or use `npm run log` ( pretty view over server.log, with tail / filter /
     date-range options - see `doc/base/index.md` -> Log ).
 - as a process, through `screen` - not reboot-proof but it's acceptable.
   - auto restart when process crashed with bash while loop.
   - identify process by `ps` ( argv carries `start:<dirname>` / `--home <pwd>` );
     stop with `npm stop` ( kills pid in `.server.pid`, trap takes down the group ).


## Note

 - Load Balancing
   - https://blog.gcp.expert/gcp-http-load-balancer-console/
   - https://blog.gcp.expert/gcp-instance-autoscaling/
   - for ShareDB - use Redis Pub/Sub across instances
     - https://github.com/share/sharedb/issues/110
     - https://github.com/share/sharedb/issues/295
     - https://stackoverfow.com/questions/20375338/
     - https://github.com/share/sharedb-redis-pubsub
   - nginx can help: https://www.digitalocean.com/community/tutorials/understanding-nginx-http-proxying-load-balancing-buffering-and-caching
 - Stateless Web Server
   - OpenAPI
     - https://github.com/OAI/OpenAPI-Specification/blob/master/versions/3.1.0.md
     - https://github.com/wesleytodd/express-openapi/
   - Run script continuously: Forever ( https://github.com/foreversd/forever )
 - Nginx Configuration
   - can use tools like nginx-confgen to help.
 - SQL Server / Shading
 - Docker / Kubernete
   - write file to host - https://stackoverflow.com/questions/31448821
 - static files should be served in a standalone way?

 - Kubernetes, Cloud Run
   - 初看下就是 Cloud Run 幫你省掉一些設定功
   - 不太確定如何使用 cloud run + dockerhub, 但至少使用 google registry 是可以的. 如下例:
     - gcloud builds submit --tag gcr.io/playground-290605/test


## Asset Cache Policy

Off by default. Turn it on per project with `config.build.hash`:

    build:
      enabled: true
      hash:
        enabled: true       # off unless set
        mode: 'filename'    # or 'query'
        keep: 3             # filename mode: generations kept
        keepDays: 0         # filename mode: also keep anything younger than this

It is opt-in because it changes the url of every generated asset in every page, and it
buys nothing until the edge serves the addressed form with a long `max-age`. Turn it on
once the rules below are in the config that actually runs.

Whatever the mode, the plain name is always written and always holds the latest build.
That is what already-deployed html points at, what a page rendered before the first
build falls back to, and what the nginx fallback lands on.

`mode: 'filename'` writes a second copy under a content-addressed name:

    /js/site.min.js                     mutable  - same name, different bytes each build
    /js/site.4b6ac41e1bea.min.js        immutable - this name only ever means these bytes
    /assets/bundle/vendor.min.js        mutable
    /assets/bundle/vendor.70d9624.min.js  immutable

Pages embed the hashed name. A url then names exactly one byte sequence, so it can be
served `immutable` - but old copies have to be expired eventually, and html older than
the retention window would 404 without the `try_files` fallback below.

`mode: 'query'` leaves one file and points at `/js/site.min.js?v=4b6ac41e1bea` instead.
Nothing accumulates and nothing 404s. The cost is that html older than the last build
silently gets whatever the file holds now, and some CDNs ignore the query string when
caching. Pick this if you would rather handle version drift with a "site updated, please
reload" prompt than keep artefacts around - a client holding old js across a deploy is
already exposed to backend api drift, so that prompt is worth having either way.

The edge has to distinguish them, because the whole point of the hash is to allow a long
`max-age` that would be wrong for the plain name:

    /assets/lib/<name>/<exact version>/...   public, max-age=31536000, immutable
    /assets/lib/<name>/main|local/...        no-cache   ( fedep symlinks, contents change )
    <anything>.<12 hex>[.min].<ext>          public, max-age=31536000, immutable
                                             ( with try_files back to the plain name )
    /js /css /assets/bundle /modules with ?v=<hash>   public, max-age=31536000, immutable
    /js /css /assets/bundle /modules bare    no-cache
    images / fonts                           expires 1d

`no-cache` does not mean "do not store" - the response is stored and revalidated, and
nginx answers 304 from the ETag. On this project's index that is 40 conditional requests
returning 146 bytes in total. Content addressing removes even those; it is a performance
optimisation on top of a policy that is already correct.

The `?v=` row needs a `map`, because `location` matching ignores the query string and a
`?v=` url is otherwise indistinguishable from its bare form:

    map $arg_v $<name>_asset_cc {
      ""      "no-cache";
      default "public, max-age=31536000, immutable";
    }

    location ~ ^/(?:js|css|assets/bundle|modules)/ {
      add_header Cache-Control $<name>_asset_cc always;
      # ... and the server-level security headers, repeated
    }

It deliberately does not cover `/assets/lib/*/main|local/`: the `?v=` there is
`libLoader._v`, a build-wide token, and fedep can swap the symlink without it changing.
`if` is not used for this - `add_header` inside `if` in a location behaves surprisingly.

Both modes work under the same ruleset; nothing has to change when you switch.

Three traps, all silent:

 - nginx `add_header` does not inherit. A `location` that sets any `add_header` loses the
   whole server-level set, so every new location has to repeat the security headers.
 - regex `location` blocks match in source order, first match wins. An extension rule
   like `location ~ \.(?:css|js|...)$` placed early will swallow `/assets/lib` and
   `/assets/bundle` before their own rules are reached.
 - `location` never sees the query string. `mode: 'query'` without the `map` above gets
   `no-cache` on every asset and buys nothing at all - and looks like it is working,
   because the urls do carry the hash.

`config/base/nginx/config.ngx` is a sample. The configuration that actually runs is the
project's own ( `config/web/nginx/` in a derived project ), so copying the sample is not
enough - the rules above have to be present in whatever config is deployed.

Nothing fails loudly when this is wrong. The page keeps working and keeps running stale
code, which is why the checker exists:

    npm run cachecheck -- https://your-origin      # point at nginx, not the express port
    npm run cachecheck -- -j <origin>              # json, for CI
    npm run cachecheck -- -s <origin>              # warnings ( missing security headers ) fail too

It reads the pairs to test out of the build's own manifest
( `<feroot>/.bundle-dep/manifest.json` ), so it checks the files the project actually
ships. Exit code 0 means no failures.


## Build Artifacts

The frontend build produces three things. Whether each one belongs in version control is
not a matter of taste - it follows from whether the running server needs it, so decide
per artifact rather than per project.

    <feroot>/static/                    the document root. runtime needs it.
    <feroot>/.bundle-dep/manifest.json  url -> content-addressed url. runtime needs it.
    <feroot>/.bundle-dep/<type>/*.dep   bundle specs. only the builder needs it.
    <feroot>/.view/                     precompiled pug. self-healing cache.

**`static/`** is what nginx has as its `root`, and what express serves as a fallback
when there is no nginx in front. Two kinds of thing live in it, and both are needed:
the assets ( js, css, bundles, fedep'd libs ), which exist only as files, and the
prerendered html. The html matters more than it looks: nginx's fallback location is
`try_files /$1 /$1/index.html @apiserver`, so a page whose html is missing only survives
if the app has a route that renders it. Removing `static/dev/refresh/index.html` makes
that page fail, while `/` keeps working because a route renders it.

**`manifest.json` has to travel with `static/`.** When the server does not build
( `config.build.enabled` off - assets are built elsewhere and deployed ), nothing
populates the in-memory hash store, and the view engine resolves `asseturl` /
`bundleurl` by reading this file. Without it, prerendered pages carry content-addressed
urls while server-rendered pages fall back to the plain ones: the same site behaving two
ways, silently. Whatever policy `static/` gets, this file gets the same one.

**`*.dep`** is builder state - which sources a bundle concatenates, which pug file
declares it. A server that does not build never reads it. Committing it only saves a
first-build pass.

**`.view/`** is a cache and repairs itself: the view engine compiles from `src/pug` on
demand when a precompiled template is missing. Verified by deleting the whole directory
while the server was running - pages kept rendering and the directory came back.
Committing it saves the first compile per page and nothing else.


## Deploying Build Artifacts

Two shapes, and the base project and its derived projects land on different ones.

**Build on the server.** Nothing is committed; `git pull` leaves the generated
directories alone because they are ignored, so a restart is warm and there is nothing to
arrange. This is what servebase itself does - its `frontend/base/static` is a demo, not
something a derived project consumes.

**Build locally, deploy artifacts.** `static/` and `manifest.json` are committed and
reach the server by `git pull`. This is what derived projects do with `frontend/web`.
The cost is merge noise on files nobody edits by hand.

That noise is avoidable, because these files are regenerable: taking either side and
rebuilding is always correct. A `.gitattributes` saying so turns every such conflict
into a no-op:

    frontend/web/static/**            merge=ours
    frontend/web/.bundle-dep/*.json   merge=ours

with `git config merge.ours.driver true` ( a driver that keeps the local version ). Run
the build after the merge, and the tree is correct again.

**Committing `static/` changes which hash mode you want.** In `filename` mode every
content change introduces a new *filename*, which git keeps in history forever even
after the file is expired from disk - one edit to one `.ls` already leaves four hashed
files behind. In `query` mode the file set never changes; only the bytes inside
`site.min.js` and the `?v=` in the html do, which is what git stores efficiently. If the
project commits its `static/`, prefer `mode: 'query'`.


## Database

 - database scaling
   - https://cloud.google.com/community/tutorials/horizontally-scale-mysql-database-backend-with-google-cloud-sql-and-proxysql
 - sharding: break large table content into small chunks call shards.
   - https://percona.com/blog/2019/05/24/an-overview-of-sharding-in-postgresql-and-how-it-relates-to-mongodbs/
   - https://blog.yugabyte.com/how-data-sharding-works-in-a-distributed-sql-database/
 - sql proxy
   - https://www.envoyproxy.io/docs/envoy/latest/configuration/listeners/network_filters/postgres_proxy_filter
   - https://medium.com/google-cloud/google-cloud-sql-proxy-with-autoscaling-1f63f1dd4017
 - cluster
   - it seems that "cluster" in postgresql is just a database. yet it can still be "clustered":
     - https://www.opsdash.com/blog/postgresql-cluster.html
     - https://www.opsdash.com/blog/postgresql-streaming-replication-howto.html
     - https://wiki.postgresql.org/wiki/Replication,_Clustering,_and_Connection_Pooling
 - replication
 - in-table auditing and logging
    - https://dzone.com/articles/audit-log-database-changes-in-postgresql
