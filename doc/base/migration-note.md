 - srcbuild 0.1.0: content-addressed frontend assets
   - generated js / css / bundles can be content-addressed, either as
     `<name>.<hash>[.min].<ext>` or as `?v=<hash>`. OFF by default; turn it on with
     `config.build.hash.enabled`. requires nginx rules to be worth anything - see
     `doc/base/infrastructure.md` -> Asset Cache Policy, and verify with
     `npm run cachecheck -- <origin>`. nothing changes until you enable it.
   - the deployed nginx config is the project's own ( `config/web/nginx/` ), and
     `config/gen/` is gitignored, so merging this does not change what is running:
     update the config, re-run `npm run config`, reload nginx.
   - `@plotdb/srcbuild` moved from `^0.0.71` to `^0.1.0` in the root package and in
     `module/base/{auth,captcha,consent,discuss}`. note that `lib.pug` is resolved from
     the frontend root, so whatever version lands in `<feroot>/node_modules` wins
     regardless of the root dependency - both have to be up to date.
 - API endpoints changed
   - global and auth api changed. corresponding frontend may need update, if not upgraded.
 - users.system ( account activation )
   - run `config/base/db/migrate/003.sql` before deploying: it adds `users.system` and
     table `activatetoken`, and moves `config.authinfo.renewpw` to `system.renewpw`.
     signup, password changes and admin user creation fail until the column exists.
   - lderror 2.4.9 for `1052` ( account not activated ).
   - projects with their own authpanel / admin pages: handle `1052` on login and signup
     ( see block `activate-required` ), and code that reads `config.authinfo.renewpw`
     should read `system.renewpw` too.
