# @servebase/auth - Authentication Subsystem

Authentication Subsystem involes following parts:

 - db - defines data schema for authentication.
   - This is defined in `init.sql` under `config/base/db`.
 - backend - access endpoint between client and server ( via server API )
 - frontend - how website interact with users via widgets and client API

User information is stored in an object called `global`, passed by an API by requested, which contains:

 - `csrfToken`: a string for csrf token.
 - `production`: either true or false, indicating if this is run under production environment.
 - `ip`: user ip.
 - `user`: user object with at least following fields:
   - `key`: positive integer if user is logged in. otherwise 0, null or undefined.
   - `displayname`: verbose name
   - `username`: email. accounts managed by system admin use `<name>@<scope>.invalid`
     ( created directly in db; `*.invalid` can't be signed up ). users log in to
     them by typing `<name>@<scope>` in authpanel - a domain without `.` gets
     `.invalid` appended, login only.
   - `staff`: true if this is staff user.
   - `verified`: if this account if verified.
 - `captcha`: captcha configuration. an object of key(captcha provider) / config (sitekey / enabled) mapping.
 - `oauth`: additional oauth methods, as an object with oauth name to `{enabled}` mapping.
 - `version`: software version
 - `config`: other configuration for frontend, from `client` field of `secret.ls`.
 - `policy`: server policy information (partially). see `lib/index.ls` for detail.


## Frontend

Frontend related codes are defined under `module/auth`. It includes two parts:

 - `authpanel` block defined in `@plotdb/block` spec.
 - auth API, as wrapper to `authpanel` block.


### Auth API

include `auth/index.js` and construct a new `auth` object:

    new auth(opt)


with following constructor options:

 - `api`: default `/api/auth/`. auth api root path. update this if you change the api root path in backend.
 - `manager`: a block manager for loading block modules.
 - `loader`: a global ldloader. `auth` uses this to indicate loading status for better UX.
 - `zmgr`: a global zmgr for aligning z-index between widgets.
 - `initFetch`: default true. invoke `fetch` automatically when constructs if true.
 - `authpanel`: id of the authpanel block to use. optional. use `{name: '@servebase/auth'}` if omitted.


APIs of the auth object:

 - `logout()`: logout a user.
   - fire `update` event if success, otherwise fire `error` event.
 - `reset()`: reset user session (clear cookie) by redirecting to reset url (`/auth/reset` by default)
 - `get(opt)`: return a Promise that resolves with the (local stored) `global` object.
   - if no `global` available, `fetch` is called (without `renew` flag) automatically.
   - options:
     - `authedOnly`: ensure that user is logged in.
       - trigger authentication flow if user is not login
         - resolve with `global` object if authed, and rejects with `lderror(1000)` if auth fails.
       - without `authedOnly`, a `global` object for anonymous user will be returned.
     - `tab`: see `prompt(opt)` below.
     - `lock`: see `prompt(opt)` below.
     - `redirect`: see `prompt(opt)` below.
   - difference between `get` and `fetch`:
     - `get` returns local stored global object.
     - `fetch` retrieve data from cookie or server (with `renew`)
 - `ensure()`: ensure a user is logged in. Prompt an authpanel if a user is not logged in.
   - shorthand for `get({authedOnly: true})`
 - `ensureVerified()`: ensure a user's email is verified. Prompt an verification dialog if user is not verified.
 - `fetch(opt)`: fetch the `global` object from either cookie or server.
   - options:
     - `renew`: true to fetch from server. false to fetch from cookie first. default true.
   - fire `update` event if local auth information is updated (either from server or cookie).
 - `prompt(opt)`: shorthand for `ui.authpanel(true, opt)` / toggle authpanel on, with options:
   - `tab`: either `login` or `signup`, indicating tab to show. previous state (or `login`) if omitted.
   - `lock`: if true, force user to not dismiss this panel unless authenticated.
   - `redirect`: indicating that this panel is triggered by redireting, instead of a explicit action of login.
 - `oauth(opt)`: trigger oauth login. options:
   - `name`: oauth login name. e.g., `facebook`, `google` or `line`.
 - `reset()`: reset user cookie by redirecting user to `/auth/reset`.
 - `on(name, cb)`: listen to specific event `name` with callback function `cb`
 - `fire(name, ...args)`: fire event `name` with `args`.
 - `apiRoot()`: return `apiRoot`
 - `inject`: (TBD)
 - `setUi`: (TBD/deprecated) change ui widget configured in constructor option `ui`.


### Auth Route

By default the URL path `/auth/` is used as the main access point for auth related requests. This page is left for developers to implement, and should accept a single query string as the action of request, such as:

    https://mysite/auth/?passwd-reset

 Without action it should popup authpanel by default. Following actions should be supported:

 - `auth`: show authpanel. default behavior.
 - `oauth-done`: oauth authentication is done.
 - `oauth-failed`: oauth authentication is failed.
 - `mail-expire`: mail verification expired.
 - `mail-verified`: mail verified.
 - `passwd-reset`: for user to request password reset link
 - `passwd-change`: for user to change password from reset link
 - `passwd-expire`: password reset linek expired.
 - `passwd-done`: password reset is done.

`@servebase/auth` provides blocks for above actions and a corresponding router in `route.js`, which can be used after `route.js` included with:

    a = new auth!
    a.route!

Check sample site `frontend/base/src/pug/auth/index.pug` for an working example.


### Common UI blocks

Two additional account related blocks are provided:

 - `change-password`: can be used to change user's password.
 - `account-info`: can be used to update user information. (such as displayname)

These blocks are not ldcover and should be injected manually into document when used. You can also wrap them in ldcover manually if needed.


### Events

 - `error`: when error occurs during authentication, along with the error object
 - `update`: when auth information is updated, along with the `global` object.
 - `logout` fired if `auth.logout` is called successfully.


##r Authpanel

We use `@plotdb/block` to simplify and offload authpanel from main pages. It's possible to customize authpanel appearence by extending `auth` block. Following are the `ldview` interface + minimal markup for authpanel script to work:

    +scope("authpanel")
      input(ld="username",name="username",autocomplete="username")
      input(ld="displayname",name="displayname",autocomplete="displayname")
      input(ld="password",name="password",type="password",autocomplete="password")
      a(ld="forgot-password") Forget Password
      button(ld="switch",data-name="login") Login
      button(ld="switch",data-name="signup") Sign Up
      button(ld="submit") Submit
      button(ld="oauth",data-name="facebook") Facebook
      button(ld="oauth",data-name="google") Google
      div(ld="info", data-name="default")
      div(ld="info", data-name="login-exceeded")
      div(ld="info", data-name="login-failed")
      div(ld="info", data-name="signup-failed")
      div(ld="info", data-name="token")

Additionally, following are supported ld selectors:

 - `signin-failed-hint`: node with this selector will show only if signin fails.
 - `signin-failed-hint-text`: content of this node with be related text for reason of signin failure.
 - `submit-text`: `login` or `sign up`, based on mode user chooses.


Authpanel script works with bootstrap and still have some class names hardcoded, which should be abstracted in the future to make its UI fully customizable.


### Authpanel Construction

Pass `auth` object when constructing authpanel block:

    @auth = new auth!
    manager.from(
      {name: "@servebase/auth"},
      {root: document.body, data: {auth: @auth, zmgr: zmgr}
    )
      .then ->  ...


check `src/base.ls` for sample implementation of authpanel. Its interface should be a function that:

 - accept two parameters:
   - `toggle`: true / false. toggle on the authpanel if true, otherwise false.
   - `opt`: options including `lock`, `tab` and `redirect`. see `prompt` api above for detail explanation.
 - return a Promise which resolves with either null or a `global` object.
   - check `user.key` to determine if user login successfully.


## backend

By default, the URL path `/auth/` and `/api/auth/` is used for communication between frontend and backend.

`@servebase/backend` also expose its internal auth object as `backend.auth`, which provides some APIs as:

 - `user`: user related operations.
   - `delete({key, username})`: delete the user with either given `key` or `username`.
     -  one of `key` or `username` should be provided. `key` take precedence over `username`.
 - `mail`: mail related operations
   - `verify({req, user})`: - send verification mail to a given user. `user` is an object with:
     - `key`: user's key
     - `username`: user's username (email)


engine/auth.ls. API endpoints:

 - sign in related
   - GET  / `@api/auth/info` - server and user information
   - POST / `@api/auth/signup` - signup. params:
     - username
     - displayname
     - password
     - config
   - POST / `@api/auth/login` - login.
     - params:
       - username
       - password
     - return optional `{passwordDue, passwordShouldRenew}` when necessary with following meaning:
       - `passwordDue`: how many time password has been due.
       - `passwordShouldRenew`: should password be renewed.
     - return `{mfa: {methods}}` instead, without logging in, if the user has 2FA enabled.
       see Two-Factor Authentication below.
   - POST / `@api/auth/logout` - logout. no params.
   - POST / `@api/auth/reset` - logout, clear cookie
   - POST / `@api/auth/clear` - logout, clear cookie from all devices
   - GET  / `@api/auth/<oauth>/callback`
 - password reset
   - POST / `@api/auth/passwd`
   - POST / `@api/auth/passwd/:token`
   - GET  / `@app/auth/passwd/:token`
 - email verification
   - POST / `@api/auth/mail/verify`
   - GET  / `@app/auth/mail/verify/:token`
 - oauth login
   - POST / `@api/auth/<name>`
   - GET  / `@api/auth/<name>/callback`
 - user related
   - PUT  / `@api/auth/user/` - update user object. params:
     - displayname
     - description
     - title
     - tags


### Common Errors

 - 1015 - bad parameters
 - 1012 - permission denied
 - 1034 - user not found
 - 500 - internal server error


## Two-Factor Authentication ( 2FA )

TOTP ( Google Authenticator and similar apps ) plus one-time recovery codes. Off unless configured:

    auth:
      mfa:
        enabled: true
        # also require 2FA on oauth ( google / facebook / line ) login. default false:
        # the oauth provider usually has its own 2FA.
        oauth: false
        # name shown in the authenticator app. default: `sitename`, then `domain`.
        issuer: 'My Site'
        # using the same code twice ( within its 30 second window ):
        #  - 'session' ( default ): fine within one session - e.g. log in, then change a
        #    setting with the same code - but refused from any other session, which is
        #    where a stolen code would be used.
        #  - true: always fine ( npm works this way ).
        #  - false: never ( RFC 6238 5.2 ).
        reuse: 'session'
        # keys for encrypting TOTP secrets and hashing recovery codes, same shape as `auth.pepper`.
        # to rotate: add a new key, point `current` to it, and keep the old one - data made
        # under the old key still needs it. key names must not contain `:`.
        keys: {k1: 'a long random string'}
        current: 'k1'

The server refuses to start if `enabled` is set but `keys[current]` is missing. Needs `migrate/002.sql`
( tables `mfa`, `mfarecovery` ) on existing databases.

Login takes two steps once a user has 2FA enabled:

 1. password ( or oauth ) passes. Instead of logging in, the server keeps a pending login in the session
    ( 5 minutes, 5 attempts ) and answers `{mfa: {methods}}`; oauth redirects the popup to `/auth?mfa-required`.
 2. `POST /api/auth/mfa/verify {method, code}` - `method` is `totp` or `recovery`. On success the user is
    logged in and the reply is what `/login` would have answered, plus `{recovery: {remain}}` when a recovery
    code was used.

The authpanel handles both steps with the `mfa-verify` block; nothing to do on the frontend beyond that.

Endpoints ( all under `/api/auth` ):

 - `POST /mfa/verify` - second login step, see above.
 - `GET  /mfa` - `{enabled, methods: [{method, createdtime, lastused}], recovery: {remain}, password}`.
   `password`: whether enabling asks for the current password ( false for oauth-only accounts ).
 - `POST /mfa/totp/setup` - start enrolling: `{secret, uri, qr}` ( `qr`: svg ). The secret waits,
   encrypted, in the session for 10 minutes; nothing is stored until `enable`.
 - `POST /mfa/totp/enable {code, password}` - finish enrolling. Replies `{recovery: [codes]}`, the only
   time the codes are shown in plain text. Logs out the user's other sessions.
 - `POST /mfa/totp/disable {method, code}` - needs a current code ( `method: totp` ) or a recovery code.
 - `POST /mfa/recovery {method, code}` - replace all recovery codes, same proof as `disable`.
 - `POST /admin/mfa/reset {key | username}` - admin only. Removes the user's 2FA entirely.

Frontend blocks: `mfa-verify` ( the second login step ), `mfa-required` ( its page for the oauth popup ) and
`mfa-setup` ( for the settings page: enable, show / regenerate recovery codes, disable ). `global.policy.mfa`
is set when the feature is on. Whether a user has 2FA is not in `global.user`: ask `GET /mfa`, or join the `mfa` table.

Errors: `1045` wrong code, `1050` code consumed - right code, but already used in its 30 second window and
`reuse` refuses it here; wait for the next one. Not counted as a failure. `1013` pending login or setup expired, `1049` too many attempts - 5 on one pending
login, or 10 in a row on one account within 15 minutes ( a success resets it; counted in process memory ), `1011` already enabled, `1030` wrong
password.

Notes:

 - a TOTP code whose time step is not newer than the last accepted one counts as used again - see `reuse`.
 - nothing 2FA related goes into `users`: that row is copied into every session. The `mfa` table is the only
   record of who has it.
 - turning `enabled` off skips 2FA for everyone, but keeps their settings for when it comes back.
 - admin `su` ( `session.login` ) bypasses 2FA, as it bypasses the password.
 - adding email / sms later: see the comment at the top of `lib/mfa.ls`. The login flow, recovery codes
   and failure counting stay as they are; `mfa.target` is there for the phone number / address.


## Additional Notes

`/me/settings/` is used as the link to users' setting pages. This should be configurable (TODO)


## config (TBD)

 - session cookie age
 - username pattern ( email? )
 - password pattern


## Authpanel Construction

In order to reduce bundle size, you may want to construct the authpanel without extending `auth` block. This is experimenting but you can include `base-imp.js` and construct block module manually, similar to what has been done in `src/base-def.ls` and `src/base.pug`:


base.pug:

    script(type="module"): :lsc
      include base-imp.js
      include base-def.js


base-def.ls:

    module.exports = {
      pkg:
        name: "auth", version: "0.0.1", path: "base.html"
        i18n: i18n-resource
        dependencies: [
          {name: "ldview", version: "main"}
          {name: "ldnotify", version: "main"}
          {name: "ldform", version: "main"}
          {name: "ldbutton", version: "main", type: \css}
          {name: "@loadingio/loading.css", version: "main", path: "lite.min.css"}
          {name: "ldnotify", version: "main", type: \css, global: true}
          {name: "curegex", version: "main", path: "curegex.min.js"}
        ]
    } <<< base-imp


## User Object

### Config

User object contains a configuration object `config` in db schema definition, which is application-based; for now we have following fields defined in various modules:

 - consent: for tracking time of consent
   - cookie: timestamp when user accept cookie usage.
   - custom: should be an object. add your own consent here.
 - invitetoken: track if this account is created with invitetoken. it's an object with [token,timestamp] pairs, where:
   - token: invite token used on this account
   - timestamp: time when consuming this invite token
 - custom: should be an object. add your own customized fields here.

possibly custom and deprecated fields:

 - tos, legal, newsletter
 - authinfo.renewpw: moved to `system.renewpw` ( `config/base/db/migrate/003.sql` ). still read as a fallback.

`config` is sent to frontend as is ( global payload ), so don't put anything users shouldn't see there.


### System

`system` keeps system states, not sent to frontend. However the whole `users` row is copied into session, so it's not a place for secrets either ( see the `mfa` table ).

 - renewpw: true if user should renew password immediately ( e.g., account created by admin with a given password ).
 - pending: `{by, at}`, account created by admin ( `by`: creator's user key ) and not activated yet. see Account Activation.


## Account Activation

Admin can create an account for someone else and let them set the password by themselves:

    backend.auth.activate.create {req, username, displayname, detail, by: req.user.key}
      .then (user) -> # set up roles etc. here

This creates a `pending` account without password, and sends an activation mail ( template `activate` ). The link ( `/auth/activate/:token` ) only checks the token and leads to the `activate` block; the token is consumed when the password is posted ( `POST /api/auth/activate/:token` ), so link scanners in mail services won't use it up. Activating also marks email as verified.

 - tokens are one-time, stored as sha256 in table `activatetoken`. sending again ( `backend.auth.activate.send {req, user}` ) invalidates earlier ones.
 - link lifetime: `config.policy.token-expire.activate` in seconds, 7 days by default.
 - a pending account can't log in, by password or by 3rd party, nor sign up again: these return lderror `1052`. authpanel then shows block `activate-required`, which sends the mail again.
 - forgot password on a pending account sends the activation mail instead ( at most once per minute ), with the same response, so users don't need to tell them apart.
 - admin setting the password directly ( `/api/admin/user/:key/password` ) also activates the account, without marking email as verified.

Needs `config/base/db/migrate/003.sql` on existing databases.
