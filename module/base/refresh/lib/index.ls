# tag every response with the version the server is currently running.
#
# the point is not to serve the version - it is that a page already open in a browser
# has no way to learn that the deploy underneath it moved. it holds html, js and css
# from one build and talks to an api from another, and nothing tells it so. with content
# addressing the assets it holds stay valid ( the hashed urls keep resolving ), which
# removes the crash but not the mismatch: the page is simply old.
#
# so the server states its version on the way out, and the page compares. no polling, no
# extra request - it rides on traffic the page was making anyway.

refresh = (opt = {}) ->
  @backend = opt.backend
  # response header carrying the running version. the client only ever compares it with
  # what it saw first, so the value just has to change when the deploy changes.
  @header = opt.header or 'X-App-Version'
  @middleware = @_middleware!
  @

refresh.prototype = Object.create(Object.prototype) <<< do
  version: -> (@backend or {}).version or 'na'

  _middleware: -> (req, res, next) ~>
    # `.version` is watched at runtime, so this follows a deploy without a restart.
    res.set @header, @version!
    next!

module.exports = refresh
