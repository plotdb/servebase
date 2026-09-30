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

## Cloudflare challenge ( turnstile pre-clearance )

When Cloudflare ( WAF / bot protection ) challenges a `fetch` or websocket request, the
request only gets `403` with `cf-mitigated: challenge` - a browser can't solve a challenge
page in the background. `captcha.cfchallenge` handles this with a Turnstile widget that has
pre-clearance enabled: once solved, Cloudflare sets `cf_clearance` on the domain and later
requests ( websocket handshake included ) pass. No backend verification is involved.

`core` sets it up as `core.challenge` and wraps `ld$.fetch` before any API call, so every
`ld$.fetch` that gets challenged runs Turnstile and is resent once. Config comes from
`corecfg` rather than `/api/auth/info`, since that API may be the one challenged:

    ldc.register \corecfg, <[]>, -> ->
      challenge: sitekey: '<pre-clearance widget sitekey>'

options:

 - `sitekey`: a Turnstile widget with pre-clearance enabled, in the same Cloudflare zone as
   the site. without it, nothing is wrapped.
 - `timeout`: give up ( and return the original error ) if no result before interaction, in ms.
   default 30s. once the widget asks for interaction, the user's pace applies.
 - `clear`: POST the token here after solving. for the local mock only - never set in production.

API:

 - `wrap(ld$)`: wrap `ld$.fetch`. done by `core`.
 - `solve()`: run Turnstile. concurrent callers share one run.
 - `probe(url)`: GET `url` and solve if it is challenged; resolves whether it solved. for
   websocket, whose handshake status the browser doesn't expose. `@servebase/connector`
   does this with its `challenge` option: `new connector {challenge: core.challenge, ...}`.

A challenge is recognized by the `cf-mitigated` header ( needs `@loadingio/ldquery` >= 3.0.7,
which exposes `e.headers` ) and otherwise by the challenge page's markers in the body.

Local test: set `dev.cf-challenge-mock` in config ( see `backend/engine/cf-challenge-mock.ls` )
and use Cloudflare's test sitekeys, e.g. `1x00000000000000000000AA` ( passes ),
`2x00000000000000000000AB` ( fails ), `3x00000000000000000000FF` ( forces interaction ).
To test against real Cloudflare, add a WAF custom rule with `Managed Challenge` scoped to
yourself ( e.g. by a cookie ), and delete `cf_clearance` to retest.


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


