# captcha

Mechanism for human verification

 - abstract interface for accessing captcha resources.
   - able to interate multiple captcha `providers` (e.g., grecaptcha v3 -> hcaptcha -> customer support )
 - 3rd party service supported via provider.
 - provide local captcha fallback ( TODO )
   - a simple captcha
   - verify via interacting with customer supports
     - CR sends a pass key to user for temporarily bypass captcha checking

## API

captcha is a global object providing following APIs:

 - `init(cfg)`: init captcha with configuration object `cfg` which contains corresponding configuration object for every providers as a member in cfg with provider name as its field name.
 - `register(name, provider)`: register a provider with `name`
 - `get(name)`: return a provider with given `name`. return `provider` instance, with interface defined below.
 - `guard(opt)`: guard a request with captcha. this may trigger a set of default captcha object ui. opt:
   - `cb(verify-object)`: function called with a verified object ( `{token, name}` )
     - this function should use the given verification object to send server API call.
       - see `middleware` below for how `verify-object` should be sent.
     - this function should reject if the given verification object doesn't accepted by remote server.

register captcha provider with `captcha.register(name, provider)`, where provider is an object implementing following methods:

 - `verify(obj)` - verify with custom defined `obj` object. (TBD)
   - return a verified object. For a verified object, see below.
 - `init(obj)` - init with custom defined `obj` object.
 - `priority` - lower = higher
 - `cfg(obj)` - for configuring this captcha. obj with following fields:
   - `enabled` - true if this provider is enabled
   - `sitekey` - sitekey for this provider
 - `create(opt)` - create a provider instance with given opt. captcha provides a default function for this method so developer won't have to implement this.
 - `interface`: a provider instance interface object implementing following fields:
   - `init`:  init object. constructor options will be kept as member variable `opt`. ( the `opt` passed via `create(opt)` )
   - `render()`: render object.
   - `reset()`: reset object status.
   - `get()`: return a verified object ( see below ); trigger interface for user to verify if needed.


## Verified Object

Verified object is passed to server and use for result verification in server side.

 - `token` - token after verified.
 - `name` - name of this provider


## Middleware

`@servebase/captcha` in the server side can be used as a middleware to automatically check captcha result. It expects captcha data to be passed in following ways:

 - a stringified JSON in `captcha` field of a multipart request.
 - a `captcha` field of a JSON body.

`request.body.captcha` is expected (in either JSON object or stringified JSON in string format) which is parsed by the servebase backend engine (via JSON parser from `body-parser`) or directly by user customized middleware, such as multiparty:

    api.post 'my-url', connect-multiparty!, backend.middleware.captcha, (req, res) -> ...


following are some possible ways to pass captcha to backend:

    captcha.guard cb: (captcha) ->
      ld$.fetch "my-url", {method: "POST"}, {json: {captcha}}

    captcha.guard cb: (captcha) ->
      fd = new FormData!
      fd.append "captcha", JSON.stringify(captcha)
      ld$.fetch "my-url", {method: "POST", body: fd}


### Verify once per session

`backend.middleware.captcha` verifies every request. For an API a user calls repeatedly
( e.g. a helper button ), `backend.middleware.captcha.once` verifies once and then lets
the same session through for a while without a captcha:

    api.post 'my-url', aux.signedin, throttle, backend.middleware.captcha.once({scope: 'my-feature', ttl: 10 * 60 * 1000}), (req, res) -> ...

 - valid pass in session: pass through, no captcha needed.
 - no pass and no captcha in request: `1048` ( captcha required ).
 - captcha in request: verify it. Pass through and record the pass, or `1009` if it fails.
 - `scope`: passes are per scope. use the same scope to share one verification between APIs. default `default`.
 - `ttl`: pass lifetime in ms. default 10 minutes.
 - without `req.session`, it falls back to verifying every request.

The pass only proves the user was human when it was issued and cannot be revoked
before `ttl`, so keep `ttl` short and keep a throttle on the API. The pass is stored in
the session, so it is per browser: a new device or cleared cookies means verifying again.

In frontend, use `core.captcha.once` instead of `guard`. It sends the request without a
captcha first ( `cb` gets `null` ), and only runs `guard` and resends once on `1048`:

    core.captcha.once cb: (captcha) ->
      ld$.fetch "my-url", {method: "POST"}, {json: {captcha, ...}, type: \json}

Test: `./node_modules/.bin/lsc module/base/captcha/test/once.ls` ( no external service ).

## Captcha flow

- accessing any API
  - recaptcha is required?
    - yes: verify ( 1 )
      - verification failed. frontend receive backend error code
      - frontend try again with alternative method
      - try again until
        - all alternatives tried
        - any alternative pass.
    - no: access api.
      - api accessing failed ( due to throttling or any other reason )
      - can this failure resolved by captcha?
        - yes: verify ( go to 1 )


