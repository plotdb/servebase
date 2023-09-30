require! <[lderror @plotdb/suuid ./aux]>

(backend) <- (->module.exports = it)  _

# for serving a friendly error page if it's not an API and prevent looping error
route490 = (req, res, err) ->
  if !/^\/api/.exec(req.originalUrl) and !/^\/err\/490/.exec(req.originalUrl) =>
    # cookie domain: webmasters.stackexchange.com/questions/55790
    #  - no domain: request-host will be used
    #  - with domain: start with a dot. similar to *.some.site
    ## with http header - rely on browsers to redirect. cookie ignored.
    # if err.redirect => return res.redirect 302, err.redirect
    ## with reversed proxy - will need a reversed proxy to take affect
    ## NOTE User may access the original URL again after error has been resolved,
    #       but if the page is cached, user won't be able to reach the original URL.
    #       so, we explicitly disable cache via header.
    res.set {
      "Content-Type": "text/html"
      "X-Accel-Redirect": err.redirect or \/err/490
      "X-Accel-Buffering": "no"
      "Cache-Control": "no-cache, no-store, must-revalidate"
      "Pragma": "no-cache"
      "Expires": 0
    }
  else delete err.redirect
  res.cookie \lderror, JSON.stringify(err), {maxAge: 60000, httpOnly: false, secure: true, sameSite: \Strict}
  return res.status 490 .send err

handler = (err, req, res, next) ->
  # 1. custom error by various package - handle by case and wrapped in lderror
  # 2. custom error from this codebase ( wrapped in lderror ) - pass to frontend with lderror
  # 3. trivial, unskippable error - ignore
  # 4. log all unexpected error.
  try
    if !err => return next!
    # SESSION corrupted, usually caused by a duplicated session id
    # this is generated in @servebase/auth by a middleware
    # which checks for duplicated session id
    if err.code == \SESSIONCORRUPTED =>
      aux.clear-cookie req, res
      err = lderror 1029
    # delegate csrf token mismatch to lderror handling
    if err.code == \EBADCSRFTOKEN => err = lderror 1005
    if err.id == 1029 =>
      # SESSIONCORRUPTED is a rare and strange error.
      # we should log it until we have confidence that this is solved correctly.
      err.log = true
      # we used to handle this in a specific route such as `/auth/reset`.
      # However, this exception may be emitted directly from @plotdb/express-session,
      # thus bypass `/auth/reset` directly - in this case we can never handle them.
      # So, we clear cookie + logout here as the last resort to clear the mess.
      try
        aux.clear-cookie req, res
        req.logout!
      catch _e
    err.uuid = suuid!
    err <<< {_detail: user: (req.user or {}).key or 0, ip: aux.ip(req), url: req.originalUrl}
    # log every single error except those will be logged below ( has id + log = true )
    if backend.config.log.all-error and !(lderror.id(err) and err.log) =>
      backend.log-error.debug(
        {err: err}
        "error logged in error handler (lderror id #{lderror.id(err)})"
      )
    if lderror.id(err) =>
      # customized error - pass to frontend for them to handle
      # to log customized error, set `log` to true
      if err.log =>
        req.log.error {err}, """
        exception logged [URL: #{req.originalUrl}] #{if err.message => ': ' + err.message else ''} #{err.uuid}
        """.red
      delete err.stack
      return route490 req, res, err

    else if (err instanceof URIError) and "#{err.stack}".startsWith('URIError: Failed to decode param') =>
      # errors to be ignored, due to un-skippable error like body json parsing issue
      return res.status 400 .send err
    # all handled exception should be returned before this line.
  catch e
    req.log.error {err: e}, "exception occurred while handling other exceptions".red
    req.log.error "original exception follows:".red

  # --- take care of unhandled exceptions ---
  req.log.error {err}, "unhandled exception occurred [URL: #{req.originalUrl}] #{if err.message => ': ' + err.message else ''} #{err.uuid}".red
  # filter and leave only core fields to prevent from credential leaking
  err = err{id,name,uuid,payload}
  # either (error without id) or (nested exception, may be lderror) goes here.
  # let user know it's 500 if id is not explicitly provided.
  if !(err.name? and err.id?) => err <<< name: \lderror, id: 500
  # friendly error page, see above for code explanaition.
  return route490 req, res, err

return handler
