require! <[fs path @servebase/config @plotdb/colors js-yaml lderror re2 curegex]>
require! <[nodemailer nodemailer-mailgun-transport]>
require! <[./utils/md]>

re-email = curegex.tw.get('email', re2)
is-email = -> return re-email.exec(it)

# # sample code for sending mail
# backend.mail-queue.add {
#   from: '"Servebase Dev" <contact@yourserver.address>'
#   to: "some@mail.address"
#   subject: "Your Title"
#   text: """  .... ( your text ) .... """
#   html: """  .... ( your html ) .... """
# }
#   .then -> ...

libdir = path.dirname fs.realpathSync(__filename.replace(/\(js\)$/,''))
rootdir = path.join(libdir, '../..')

mail-queue = (opt={}) ->
  @api = if opt.smtp =>
    nodemailer.createTransport(opt.smtp)
  else if opt.mailgun =>
    nodemailer.createTransport(nodemailer-mailgun-transport(opt.mailgun))
  else
    sendMail: ~>
      @log.error "sendMail called while mail gateway is not available"
      return lderror.reject 500, "mail service not available"
  @suppress = opt.suppress
  @base = opt.base or 'base'
  @log = opt.logger
  @info = opt.info or {}
  @cfg = opt or {}
  if opt.blacklist? =>
    if Array.isArray(opt.blacklist) =>
      @_blacklist = opt.blacklist
        .map (n) ->
          "#{(if !n => '' else if /@/.exec(n) => n else "@#n")}".trim!
        .filter -> it
    else if typeof(opt.blacklist) == \object =>
      if typeof(opt.blacklist.module) == \string  =>
        try
          p = if !/^\./.exec(opt.blacklist.module) => opt.blacklist.module
          else path.join(rootdir, opt.blacklist.module)
          @_blacklist = require p
        catch err
          @log.error {err}, "blacklist is provided as a module, however failed to load, and thus disabled."
  @list = []
  @

mail-queue.prototype = Object.create(Object.prototype) <<< do
  in-blacklist: (m = "") ->
    return if !@_blacklist => Promise.resolve false
    else if Array.isArray(@_blacklist) =>
      <~ Promise.resolve!then _
      for i from @_blacklist.length - 1 to 0 by -1 => if (~m.indexOf(@_blacklist[i])) => return true
      return false
    else if typeof(@_blacklist.is) == \function => @_blacklist.is m
    else Promise.resolve false
  add: (obj) ->
    @list.push obj
    @handler!
  handle: null
  handler: ->
    if @handle => return
    @log.info "new job incoming, handling...".cyan
    @handle = setInterval (~>
      @log.info "#{@list.length} jobs remain...".cyan
      obj = @list.splice(0, 1).0
      if !obj =>
        @log.info "all job done, take a rest.".green
        clearInterval @handle
        @handle = null
        return
      @send-directly obj.payload
        .then obj.res
        .catch obj.rej
    ), 5000

  # queued send
  send: (payload, opt = {}) ->
    if opt.now => return @send-directly payload
    new Promise (res, rej) ~> @add {payload, res, rej}

  # directly send
  send-directly: (payload) -> new Promise (res, rej) ~>
    cc = if !payload.cc => ' '
    else " [cc:#{if Array.isArray(payload.cc) => payload.cc.join(' ') else payload.cc}] "
    bcc = if !payload.bcc => ''
    else "[bcc:#{if Array.isArray(payload.bcc) => payload.bcc.join(' ') else payload.bcc}] "
    @log.info "#{if @suppress => '(suppressed)'.gray else ''} sending [from:#{payload.from}] [to:#{payload.to}]#cc#bcc[subject:#{payload.subject}]".cyan
    if @suppress => return res!
    (err,i) <~ @api.sendMail payload, _
    if !err => return res!
    @log.error {err}, "send mail failed: api.sendMail failed."
    return res!

  # content -> text / html
  send-from-md: (payload, map = {}, opt={}) ->
    payload = JSON.parse JSON.stringify payload
    (res, rej) <~ new Promise _
    content = (payload.content or '')
    payload.from = (@info or {}).from or payload.from
    for k,v of map =>
      re = new RegExp("\#{#k}", "g")
      content = content.replace(re, v)
      payload.from = payload.from.replace(re, v)
      payload.subject = payload.subject.replace(re, v)
    # We may want to trap unresolved tokens
    # if /\#{[^}]+}/.exec(content) => throw new Error("unresolved token exists when sending from md.")
    payload.text = md.to-text(content)
    payload.html = md.to-html(content)
    delete payload.content
    @send(payload,opt).then -> res!

  by-template: (name, email, map = {}, opt = {}) ->
    # TODO add i18n support.
    # we may want to use subfolder (e.g., en/mail/some.yaml) to store mails for different language
    # and a fallback lng should be considered.
    config.yaml [\private, @base, \base].map(->path.join(it, "mail/#name.yaml")), opt.lng
      .then (payload) ~>
        obj = from: opt.from or payload.from, to: email, subject: payload.subject, content: payload.content
        if opt.cc => obj.cc = opt.cc
        if opt.bcc => obj.bcc = opt.bcc
        @send-from-md(obj, map,{now: opt.now})
      .catch (err) ~>
        @log.error {err}, "send mail by template failed for name `#name`"
        return Promise.reject(err)

  batch: ({sender, recipients, name, payload, params, batch-size, lng}) ->
    sender = @cfg.default-sender or sender
    if !sender and !(@cfg.sitename and @cfg.domain) => return lderror.reject 1015
    # we may want to make sure sender is a valid recipient
    # since no-reply@xxx probably won't be a correct sender.
    if !sender => sender = "\"#{@cfg.sitename}\" <no-reply@#{@cfg.domain}>"
    batch = []
    params = (params or {}) <<< @cfg{sitename, domain}
    payload = {} <<< (payload or {}) <<< from: sender
    batch-size = batch-size or 1
    recipients = (recipients or []).map(-> it).filter(->is-email it)
    if !recipients.length => return Promise.resolve!
    if !(name or payload.subject) => return Promise.resolve!
    while recipients.length => batch.push(recipients.splice 0, batch-size)
    ps = batch.map (rs = []) ~>
      try _payload = JSON.parse(JSON.stringify(payload)) catch e => return Promise.reject e
      if !rs.length => return Promise.resolve!
      Promise.resolve!
        .then ~>
          _payload <<< (if rs.length > 1 => {to: sender, bcc: rs} else {to: rs})
          # use site template if payload contains no content fields
          if name and !(_payload.subject and (_payload.text or payload.html)) =>
            return @by-template(name, _payload.to, params, ({lng, now: true} <<< _payload{from, bcc}))
          @send _payload
    Promise.all ps

module.exports = mail-queue
