config folder structure

 - `base`: servebase sample configs
 - `private`: per site configs that should be kept as secret
 - `gen`: generated files, can be re-gen based on configs from e.g., `private` or env vars.
 - `dev`: development / testing overrides, see below. not version controlled.
 - `<name>`: configs dedicated for `<name>`
   - can follow `base` structure yet  there is no limitation of this. which is:
     - `nginx`: nginx config.
     - `mail`: mail templates
     - `db`: db schema configs
     - `docker`: docker (composer) config files
     - `bootstrap`: bootstrap custom scss
     - `modules`: (TBD) module specific config

run scripts under `tool` with `./tool/<name>`.


## overrides

On start, the engine merges two optional files over `private/<config>.ls` ( `<config>` is `secret`
unless `-c` says otherwise ), in this order:

 - `private/<config>.local.ls`: a person's own override. may hold secrets, like the config itself.
 - `dev/<config>.ls`: development / testing override, e.g. `captcha: enabled: false` while testing
   locally. no secrets: coding agents read and write this folder, while `private` is off limits to
   them. never applied in production ( `NODE_ENV=production` ) - skipped with a warning instead.

Objects merge key by key; anything else, arrays included, replaces. Each override applied is printed
on start. Both are ignored by git. Note this reserves `dev` as a config folder name.
