# backend

`backend` is the base object when constructing a backend server. Backend object is passed to route functions when initializing routes, and provides following members:

 - `mode`: value in `NODE_ENV`, e.g., `production`
 - `production`: true if in production mode, otherwise false.
 - `version`: software version (e.g., commit hash) of current repo
 - `cachestamp`: hint of oldest cache timestamp.
 - `middleware`: middleware objects, including
   - csrf
 - `config`: backend configuration
 - `base`: base name. default `base`. updated based on `config` related field.
 - `feroot`: default frontend base directory. e.g., `frontend/base`. auto generated based on `base` field
 - `root`: repo root directory
 - `server`: http.Server object
 - `app`: express application
 - `auth`: auth module
 - `log`: logger object, in pino interface
 - `log-server`: child log of `log` for server information
 - `log-build`: child log of `log` for build information
 - `log-mail`: child log of `log` for mail sender
 - `mail-queue`: mail sender
 - `route`: all default routes. including:
   - `app`: routes for view
   - `api`: routes for api
   - `extapi`: routes for api from cross domain access
   - `auth`: routes for authorization
 - `store`: redis like data store, with following function:
   - `get(key)`: return a Promise which resolves with the value corresponding to `key`.
   - `set(key, value)`: return a Promise which resolves when redis successfully update `key` with `value`.
 - `db`: db interface, postgresql object.
 - `i18n`: i18n object, in `i18next` spec.
 - `mod`: this is reserved for developers to extend backend object.
   servebase should not use this for any other purpose in the future.


## API

Following are apis available in `backend` object. Most of them are only for server use.

 - `prepare(opt)`: prepare basic components for backend without starting it.
   - return a Promise which resolves with the backend object.
   - `opt`: options for preparing backend, which is an object with following fields:
     - `db`:
       - `query-only`: true to suppress trim (session cleaning up). default true.
         - see `backend/db/postgresql` for more information.
 - `start`: init a backend server. 
   - return a Promise which resolves with the backend object.
 - `listen({logger, i18n})`: start the inited backend server. ( TODO: merge back into `start`? )
 - `watch`: start a source code building daemon.
 - `lngs(req)`: return preferred language in order based on given `req` object. req is optional.
   - this was `lng(req)` but since it returns an array, we rename it to `lngs`.
     `lng(req)` is still kept but is deprecated and should be avoided to use.

And a constructor API:

 - `create(opt)`: create a backend server and start this server.


### Access backend features via server program

construct a backend object for accessing libraries that require backend to work. Following is an example with database interface:

    require! <[backend backend/db/postgresql]>
    opt = require "../config/private/secret"
    db = new postgresql(new backend {config: opt})
    db.query "select count(key) from session" .then ->


## mail-queue API

mail-queue API:

 - `add`: add mail into mail queue
 - `send(payload, opt)`: send mail.
   - payload field:
     - from: sender. e.g., '"Servebase Dev" <contact@yourserver.address>'
       - this may be overwritten by `mail.info.from` field in secret config file.
     - to: recipient. e.g., "some@mail.address"
     - bcc: bcc recipient. e.g., "some@mail.address"
     - subject: mail title
     - text: mail text content
     - html: mail html content
     - content: used in `send-from-md` as mardkwon content. translated to text and html
   - opt field:
     - now: true if send immediately. the same as `send-directly`.
 - `send-directly(payload)`: send mail, bypassing queue
 - `send-from-md(payload, map, opt)`: send with markdown content
 - `by-template(name, email, map, config)`: send using template content.
   - templates are stored under `config/<name>/mail/${name}.yaml`.
     - when there are multiple possible names, they will be looked up with following order:
     - `private` (e.g., `config/private/mail/...`)
     - name configured in `base` field in secret file.
     - `base` (e.g., `config/base/mail/...`)
 - `batch({sender, recipients, name, payload, params, batch-size})`:
   - an abstract API for sending batch mails.
   - options:
     - `recipients`: array of recipients.
     - `sender`: sender. use `defaultSender` or generate from `sitename`, `domain` if omitted.
     - `name`: template name. use `payload` if omitted.
     - `payload`: payload for mail. use template if omitted.
     - `params`: parameters for template
     - `batch-size`: size of batch. default 1.


## View Rendering

View rendering is powered by `@plotdb/srcbuild`. For more information, check `@plotdb/srcbuild` repo README file.

Except the APIs/filters provided by `@plotdb/srcbuild`, `servebase` also provides following information via local variables (in both view and static file rendering):

 - `settings.domain`: domain name set in `secret.ls`. schema not included.
   - note that since static generated files use the value when they are generated, `domain` may cause inconsistent when used in static generated files.
 - `settings.sysinfo`: a function returning system information including `version` and `cachestamp`.


Usage of `sysinfo`:

    div= JSON.stringify(settings.sysinfo())

which return an object containing following fields:

 - `version`: software version of this running instances, based on git commit hash.
 - `cachestamp`: hint of oldest cache timestamp.
   - usually the timestamp when the service starts but can be refreshed manually.

Version information should be prepared in `<root>/.version`, which can be generated by git hook after every commit. For more information about versioning, see `misc.md`: pre-commit for establishing a git hook that automatically update `.version`.
