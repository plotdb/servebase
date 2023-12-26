(backend) <- (->module.exports = it)  _
if !backend.config.payment => return
try
  require! <[@servebase/payment/lib]>
  lib {backend}
catch e
  backend.log-server.error "payment configured but payment module is not installed"
