# @servebase/config

for retrieving configuration from `config` folder. usage:

    require! <[@servebase/config]>
    secret = config.from 'private/secret'


Following are available methods:

 - `from(n)`: load config from `config/#n` by require.
 - `yaml(o)`: load config parsed from yaml file `config/#o`. `o` can be a list.
 - `json(o)`: load config parsed from json file `config/#o`. `o` can be a list.
 - `text(o)`: load text file `config/#o`. `o` can be a list.

If given parameter `o` is a list (in `yaml`, `json` and `text`):
 - files listed in it will be tried in order, and the first one found will be returned.
 - If none is found, promise will be rejected with lderror 1027.
 - If parsing failed for the found file, promise will be rejected with lderror 1017.
