require! <[@servebase/discuss]>
(backend) <- (->module.exports = it)  _

role = ({users}) ->
  ret = {}
  (users or []).map -> ret[it] = <[sample]>
  return Promise.resolve ret

discuss {backend, route: backend.route, api: {role}}
