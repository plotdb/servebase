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
