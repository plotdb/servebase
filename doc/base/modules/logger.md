# Logger

Logs from express server will be kept in `server.log` in root directory. By default it won't be rotated, which can be done via `logrotate` tool provided by system.

A helper logrotate config generator can be found in `config/base/logrotate`. To use it, prepare a configuration file ( in yaml format ) and use `template-text` to transform it:

    npx tt -c your.yaml config/base/logrotate/config.cfg > output-file

check `config/base/logrotate/README.md` for more information about configuration.
