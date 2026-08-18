# Servebase

Servebase is a nodeJS / Express based server, designed as a basis of web server development in both Backend and Frontend.

Codestack of servebase:

 - nodejs
 - livescript
 - postgresql
 - express
 - stylus
 - pug
 - docker


## Usage

Use servebase as if you fork it, and constantly pull and merge changes from servebase repo. For more information, check `version-control`.

Once setup, run following commands:

    # for development
    npm run dev

    # or, for production
    npm start


### Customized Config

Instead of `npm`, you can run `start` script directly, with optional `-c <cfg-name>`:

    ./start
    # or, alternatively
    ./start -c myconfig

with `myconfig` option added, you should prepare a corresponding config file `config/private/myconfig.ls`. Check `config/private/demo.ls` for a sample config file.

### Database

To run most of the Servebase backend code you will need a corresponding database. For now Servebase supports Postgresql only. For a quick startup of a Postgresql Instance with docker, run following:

    npm run docker-db

You may need a corresponding database configuration in your private config file.


### Log

`./start` output logs into a log file `server.log`, with the `pino` log format.
It is append-only and never rotated, so on a long-running instance it grows into
hundreds of MB - read it through `npm run log`, which wraps `tool/base/logview`:

    npm run log                    # follow, like `tail -f` ( no option = old behavior )
    npm run log -- -n 500          # last 500 lines, pretty-printed, in less
    npm run log -- -a              # whole file
    npm run log -- -f -n 500       # follow, starting from the last 500 lines
    npm run log -- -m db           # only module `db`
    npm run log -- -l 40           # only level >= 40 ( 30 info / 40 warn / 50 error )
    npm run log -- -g 'timeout'    # only lines matching regex ( raw json, pre-format )
    npm run log -- -s 20260810     # from 2026-08-10 00:00 ( UTC, inclusive )
    npm run log -- -e 20260817     # until 2026-08-17 23:59:59 ( UTC, inclusive )
    npm run log -- -d 3            # last 3 days ( dayspan; shorthand for -s )
    npm run log -- -h              # full usage
    npm run log -- other.log       # read another file

Options combine, e.g. `npm run log -- -s 20260813 -e 20260813 -l 40` for one day
of warnings and errors. Note the `--`: without it npm appends the arguments to
the script string instead of passing them along.

Notes on behavior:

 - non-follow mode pipes into `less -R` ( `-R` because pino colors the messages ).
   in less: `/` search, `n`/`N` next-prev, `g`/`G` top-bottom, `-S` toggle wrap.
 - any date option scans the whole file unless `-n` / `-a` is also given - a date
   range against the default `tail -n 2000` window would silently return nothing.
   under `-f` the window is kept, since the point there is what comes next.
 - dates are UTC, matching the timestamps pino-pretty prints ( `+0000` ).
 - `server.log` holds a few non-json lines ( subprocess output such as
   `[dev] deploy code ...` ). they pass through untouched, except under a date
   filter, where they cannot be placed in time and are dropped.
 - `-m` / `-l` / `-s` / `-e` / `-d` need `jq`; the other modes do not.

TODO:

 - log backup / rotation
 - visualization


## Repo Structure

Server files are separated in several aspects:

 - frontend / backend
 - base / derived 

For more information about repo structure, check `repo-structore'

