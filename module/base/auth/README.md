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
 - `oauth`: additional oauth methods, as an object with oauth name to `{enabled}` mapping.
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

