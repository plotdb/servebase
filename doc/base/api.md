# API

api design guideline.

 - no trailing /
 - route 綁定 file ? 並依路徑定義? ( 較好管理 ) 
   - 混合式的概念怎麼辦? 比方說, brd/admin, org/admin, 是要各別放在 brd, org 中呢, 還是放在 admin 中呢?
 - api & view 如何分開? 

use concept similar to ORM.

plugin? 
 - 使用 alternative server?
 - 獨立模組拆出? 

## External API

 - for accessing without CSRF protection.
 - /extapi/ route ( @route.extapi )


## Public Route ( session-free zone )

 - `@route.public` — root-level router, mounted **before** `auth` ( session middleware ):

       @route.public = aux.routecatch express.Router {mergeParams: true}
       app.use \/, @route.public

 - requests handled here never touch session middleware, so responses carry
   **no `Set-Cookie`** — this is required for routes fronted by nginx `proxy_cache`:
   nginx by default refuses to cache responses with `Set-Cookie`
   ( and force-caching them would leak one user's session to others ).
 - use for cacheable resources without per-user semantics,
   e.g. `@plotdb/registry` assets ( `/assets/lib/*` ).
 - no url prefix ( unlike `/extapi/` ) — mounted at `/`, so routes keep their
   original paths; unmatched requests fall through to the normal
   session-enabled chain.
 - **routes mounted here must stay session-free**: anything reading `req.user` /
   `req.session` will not work, and must go to the normal app instead
   ( e.g. `/staff/flush/*` needs admin session, so it stays on `route.app` ).

mount point semantics summary:

| router | mounted | skips | for |
|--------|---------|-------|-----|
| `@route.public` | before auth | session + csrf | cacheable, no per-user semantics |
| `@route.extapi` | before csrf | csrf | programmatic api without csrf token |
| `@route.localctl` | unix socket | http entirely | local developer / ops commands |
