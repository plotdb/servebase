# Cloudflare Challenge

Behind Cloudflare, WAF or bot protection may challenge API ( `fetch` ) or websocket requests.
Such a request only gets `403` with `cf-mitigated: challenge` - the browser can't solve a
challenge page in the background, so the request just fails ( e.g. `/api/auth/info` on boot,
or `/ws` never connecting ).

Servebase handles this with a Turnstile widget that has pre-clearance enabled: when a request
is challenged, the frontend runs the widget, Cloudflare sets `cf_clearance` on the domain, and
the request is resent. See `module/base/captcha/README.md` -> Cloudflare challenge for details.


## Enabling

Optional, and off unless a sitekey is set.

 - Cloudflare: create a Turnstile widget with pre-clearance enabled, for a hostname in the
   same zone as the site. Pick a clearance level at least as strong as the challenges your
   rules issue ( e.g. `Managed` for `Managed Challenge` ).
 - frontend: set the sitekey in `corecfg` ( e.g. `frontend/<base>/src/ls/site.ls` ):

       challenge: sitekey: '<pre-clearance widget sitekey>'

   it's in the frontend rather than config, since it's needed before the first API call and
   `/api/auth/info` may be the request being challenged.
 - websocket: pass `challenge: core.challenge` to `@servebase/connector`.

No secret key and no backend change are needed: Cloudflare, not our backend, checks the result.

The `site.ls` shipped with servebase uses Cloudflare's test sitekey and the local mock's
`clear` endpoint. Replace the sitekey and remove `clear` in your own site.


## Loading the Sitekey

A pre-clearance widget works for the Cloudflare zone its hostname belongs to, so a site
served on domains in different zones needs a sitekey per zone. `corecfg` is evaluated in the
browser at boot, so it can take the sitekey from wherever the page has it by then:

 - single domain: hardcode it in `corecfg`, as above.
 - per deployment: load a small static script before `core` that each deployment can replace
   ( e.g. served from a per-deployment folder by nginx ), and have `corecfg` read from it:

       challenge: (window.sitecfg or {}).challenge or {}

 - several zones in one deployment: pick by `location.hostname` in `corecfg`.

Avoid getting it from an API: the API may be challenged too. A static script is rarely
covered by challenge rules - keep it that way.


## Testing

 - locally: `dev.cf-challenge-mock` in config mocks the challenge on given paths.
   See `context/servebase/config.md` -> 開發用設定 (dev).
 - against Cloudflare: add a WAF custom rule with `Managed Challenge`, scoped to yourself
   ( e.g. `http.cookie contains "cf_test=1"` ), and delete `cf_clearance` to retest. Remove
   the rule afterwards.


## Limitations

 - it only makes the frontend cope with a challenge. Why requests get challenged is still
   decided by Cloudflare's rules - check Security Events.
 - whether pre-clearance clears challenges from Bot Fight Mode is not verified.
