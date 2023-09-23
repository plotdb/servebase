({core, viewlocals}) <- ldc.register <[core viewlocals]>, _
<- core.init!then _
core.ldcvmgr.get {name: "@servebase/payment", path: "gateway/dummy/pay/index.html"}
  .then ->
    url = "/extapi/pay/gw/dummy/done"
    form = document.createElement \form
    attrs = method: \post, action: url
    for k,v of attrs => form.setAttribute k, v
    document.body.appendChild form
    form.submit!
