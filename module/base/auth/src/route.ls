route = (o = {}) ->
  supported-actions = <[
    auth
    mail-expire mail-verified
    oauth-done oauth-failed mfa-required
    passwd-change passwd-expire passwd-done passwd-reset
  ]>

  if !(n = [k for k of httputil.qs!].filter(->it in supported-actions).0) => n = \auth
  # if route to authpanel is triggered by url other than expected (`/auth` by default)
  # then it's a redirect action caused by server check which requires user to login
  # we may show additional information for this scenario, identifying by `redirect` flag.
  redirect = !window.location.pathname.startsWith(\/auth)
  @_manager.from(
    ({name: "@servebase/auth"} <<< (o.bid or {}) <<< {path: n})
    {
      root: o.root or document.body
      data: { lock: redirect, redirect: redirect }
    }
  )

if auth? => auth.prototype.route = route
