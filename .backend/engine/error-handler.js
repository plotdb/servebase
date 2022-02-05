// Generated by LiveScript 1.6.0
(function(){
  var lderror, handler;
  lderror = require('lderror');
  handler = function(err, req, res, next){
    var e;
    try {
      if (!err) {
        return next();
      }
      if (err.code === 'EBADCSRFTOKEN') {
        err = lderror(1005);
      }
      if (lderror.id(err)) {
        delete err.stack;
        if (!/^\/api/.exec(req.originalUrl) && !/^\/err\/490/.exec(req.originalUrl)) {
          res.set({
            "Content-Type": "text/html",
            "X-Accel-Redirect": err.redirect || '/err/490'
          });
        } else {
          delete err.redirect;
        }
        res.cookie('lderror', JSON.stringify(err), {
          maxAge: 60000,
          httpOnly: false,
          secure: true,
          sameSite: 'Strict'
        });
        return res.status(490).send(err);
      } else if (err instanceof URIError && (err.stack + "").startsWith('URIError: Failed to decode param')) {
        return res.status(400).send();
      }
    } catch (e$) {
      e = e$;
      req.log.error({
        err: e
      }, "exception occurred while handling other exceptions".red);
      req.log.error("original exception follows:".red);
    }
    req.log.error({
      err: err
    }, ("unhandled exception occurred [URL: " + req.originalUrl + "] " + (err.message ? ': ' + err.message : '')).red);
    return res.status(500).send();
  };
  module.exports = handler;
}).call(this);
