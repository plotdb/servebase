# @servebase/config

for retrieving configuration from `config` folder. usage:

    require! <[@servebase/config]>
    secret = config.from 'private/secret'


Following are available methods:

 - `from(n)`: load config from `config/#n` by require.
 - `yaml(o, lng)`: load config parsed from yaml file `config/#o`. `o` can be a list.
   - `config/#lng/#o` if lng if provided. lng can be a list.
 - `json(o, lng)`: load config parsed from json file `config/#o`. `o` can be a list.
   - `config/#lng/#o` if lng if provided. lng can be a list.
 - `text(o, lng)`: load text file `config/#o`. `o` can be a list.
   - `config/#lng/#o` if lng if provided. lng can be a list.

If given parameter `o` is a list (in `yaml`, `json` and `text`):
 - files listed in it will be tried in order, and the first one found will be returned.
 - If none is found, promise will be rejected with lderror 1027.
 - If parsing failed for the found file, promise will be rejected with lderror 1017.

If given parameter `lng` is a list (in `yaml`, `json` and `text`):
 - files listed in it will be tried in order, and the first one found will be returned.
   - entries listed in `lng` will be tried for each entry in `o` until the first match.
 - If none is found, promise will be rejected with lderror 1027.
