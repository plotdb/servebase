require! <[fs path @servebase/config @plotdb/colors js-yaml lderror re2 curegex jsdom dompurify]>
require! <[nodemailer nodemailer-mailgun-transport]>
require! <[./utils/md]>

# use jsdom to create window/document for dompurify
jsdom-doc = "<DOCTYPE html><html><body></body></html>"
jsdom-option =
  # suppress SecurityError for localStorage availability in opaque origin
  url: \http://localhost
dom = new jsdom.JSDOM(jsdom-doc, jsdom-option)
purify = dompurify (new jsdom.JSDOM '').window

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
  @i18n = opt.i18n
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
    if opt.from => payload.from = opt.from
    if opt.cc => payload.cc = opt.cc
    if opt.bcc => payload.bcc = opt.bcc
    if opt.now => return @send-directly payload
    new Promise (res, rej) ~> @add {payload, res, rej}

  # directly send
  send-directly: (payload) -> new Promise (res, rej) ~>
    cc = if !payload.cc => ' '
    else " [cc:#{if Array.isArray(payload.cc) => payload.cc.join(' ') else payload.cc}] "
    bcc = if !payload.bcc => ''
    else "[bcc:#{if Array.isArray(payload.bcc) => payload.bcc.join(' ') else payload.bcc}] "
    if payload.html => payload.html = purify.sanitize payload.html
    @log.info "#{if @suppress => '(suppressed)'.gray else ''} sending [from:#{payload.from}] [to:#{payload.to}]#cc#bcc[subject:#{payload.subject}]".cyan
    if @suppress => return res!
    (err,i) <~ @api.sendMail payload, _
    if !err => return res!
    @log.error {err}, "send mail failed: api.sendMail failed."
    return res!

  # markdown stored in `payload.content` and converted into `payload.text` and `payload.html`
  send-from-md: (payload, map = {}, opt={}) ->
    @get-content {payload, map, lng: opt.lng}
      .then (payload) ~> @send payload, opt{now, from, cc, bcc}

  # similar to `send-from-md` instead that payload is from template
  by-template: (name, email, map = {}, opt = {}) ->
    @get-content {name, map, lng: opt.lng}
      .then (payload) ~> @send (payload <<< {to: email}), opt{now, from, cc, bcc}
      .catch (err) ~>
        @log.error {err}, "send mail by template failed for name `#name`"
        return Promise.reject(err)

  # (optionally load payload if name is defined and) convert payload with name map.
  get-content: ({name, payload, map, lng}) ->
    Promise.resolve!
      .then ~>
        if !name => return JSON.parse JSON.stringify(payload or {})
        config.yaml [\private, @base, \base].map(->path.join(it, "mail/#name.yaml")), lng
      .then (payload = {}) ~>
        if !(content = payload.content or '') => return payload
        for k,v of map =>
          re = new RegExp("\#{#k}", "g")
          content = content.replace(re, v)
          payload.from = (payload.from or '').replace(re, v)
          payload.subject = (payload.subject or '').replace(re, v)
        payload.text = md.to-text(content)
        payload.html = md.to-html(content)
        return payload
      .then (payload) ->
        payload.html = purify.sanitize(payload.html or '')
        return payload

  batch: ({sender, recipients, name, payload, params, batch-size, lng}) ->
    sender = @cfg.default-sender or sender
    if !sender and !(@cfg.sitename and @cfg.domain) => return lderror.reject 1015
    # we may want to make sure sender is a valid recipient
    # since no-reply@xxx probably won't be a correct sender.
    if !sender => sender = "\"#{@i18n.t(@cfg.sitename, {lng})}\" <no-reply@#{@cfg.domain}>"
    batch = []
    params = (params or {}) <<< {domain: @cfg.domain, sitename: @i18n.t(@cfg.sitename, {lng})}
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
