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
   - `username`: email
   - `staff`: true if this is staff user. 
   - `verified`: if this account if verified.
 - `captcha`: captcha configuration. an object of key(captcha provider) / config (sitekey / enabled) mapping.
 - `version`: software version
 - `config`: other configuration for frontend, from `client` field of `secret.ls`.


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
   - difference between `get` and `fetch`:
     - `get` returns local stored global object.
     - `fetch` retrieve data from cookie or server (with `renew`)
 - `ensure()`: ensure a user is logged in. Prompt an authpanel if a user is not logged in.
   - shorthand for `get({authedOnly: true})`
 - `fetch(opt)`: fetch the `global` object from either cookie or server.
   - options:
     - `renew`: true to fetch from server. false to fetch from cookie first. default true.
   - fire `update` event if local auth information is updated (either from server or cookie).
 - `prompt(opt)`: shorthand for `ui.authpanel(true, opt)` / toggle authpanel on, with options:
   - `tab`: either `login` or `signup`, indicating tab to show. previous state (or `login`) if omitted.
   - `lock`: if true, force user to not dismiss this panel unless authenticated.
 - `social(opt)`: trigger social login. options:
   - `name`: social login name. e.g., `facebook`, `google` or `line`.
 - `reset()`: reset user cookie by redirecting user to `/auth/reset`.
 - `on(name, cb)`: listen to specific event `name` with callback function `cb`
 - `fire(name, ...args)`: fire event `name` with `args`.
 - `apiRoot()`: return `apiRoot`
 - `inject`: (TBD)
 - `setUi`: (TBD/deprecated) change ui widget configured in constructor option `ui`.


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
      button(ld="social",data-name="facebook") Facebook
      button(ld="social",data-name="google") Google
      div(ld="info", data-name="default")
      div(ld="info", data-name="login-exceeded")
      div(ld="info", data-name="login-failed")
      div(ld="info", data-name="signup-failed")
      div(ld="info", data-name="token")

Authpanel script works with bootstrap and still have some class names hardcoded, which should be abstracted in the future to make its UI fully customizable.


### Authpanel Construction

Pass `auth` object when constructing authpanel block:

    @auth = new auth!
    manager.from(
      {name: "auth"},
      {root: document.body, data: {auth: @auth}
    )
      .then ->  ...


check `src/base.ls` for sample implementation of authpanel. Its interface should be a function that:

 - accept two parameters:
   - `toggle`: true / false. toggle on the authpanel if true, otherwise false.
   - `opt`: options including `lock` and `tab`. see `prompt` api above for detail explanation.
 - return a Promise which resolves with either null or a `global` object.
   - check `user.key` to determine if user login successfully.


## backend


engine/auth.ls. API endpoints:

 - sign in related
   - GET  / `@api/auth/info` - server and user information
   - POST / `@api/auth/signup` - signup. params:
     - username
     - displayname
     - password
     - config
   - POST / `@api/auth/login` - login. params:
     - username
     - password
   - POST / `@api/auth/logout` - logout. no params.
   - POST  / `@api/auth/reset` - logout, clear cookie
   - GET  / `@api/auth/<social>/callback`
 - password reset
   - POST / `@api/auth/passwd`
   - POST / `@api/auth/passwd/:token`
   - GET  / `@app/auth/passwd/:token`
 - email verification
   - POST / `@api/auth/mail/verify`
   - GET  / `@app/auth/mail/verify/:token`


## config

 - session cookie age
 - username pattern ( email? )
 - password pattern
