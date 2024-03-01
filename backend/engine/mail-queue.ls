require! <[fs path @plotdb/colors js-yaml lderror]>
require! <[nodemailer nodemailer-mailgun-transport]>
require! <[./utils/md]>

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
    @log.info "#{if @suppress => '(suppressed)'.gray else ''} sending [from:#{payload.from}] [to:#{payload.to}] [subject:#{payload.subject}]".cyan
    if @suppress => return res!
    (e,i) <~ @api.sendMail payload, _
    if !e => return res!
    @log.error "send mail failed: api.sendMail failed.", e
    return rej lderror 500

  # content -> text / html
  send-from-md: (payload, map = {}, opt={}) -> new Promise (res, rej) ~>
    content = (payload.content or '')
    payload.from = (@info or {}).from or payload.from
    for k,v of map =>
      re = new RegExp("\#{#k}", "g")
      content = content.replace(re, v)
      payload.from = payload.from.replace(re, v)
      payload.subject = payload.subject.replace(re, v)
    payload.text = md.to-text(content)
    payload.html = md.to-html(content)
    delete payload.content
    @send(payload,opt).then -> res!

  by-template: (name, email, map = {}, config = {}) ->
    fn = (b) -> "config/#b/mail/#name.yaml"
    fs.promises.access fn \private
      .then ~> fn \private
      .catch ~> fs.promises.access fn @base .then ~> fn @base
      .catch ~> fs.promises.access fn \base .then ~> fn \base
      .catch (e) ~>
        @log.error "send mail failed: read template file failed.", e
        return lderror.reject 1027
      .then (file) ~>
        fs.promises.read-file file
          .catch (e) ~>
            @log.error "send mail failed: read template file failed. ", e
            return lderror.reject 1017
      .then (content) ~>
        try
          return js-yaml.safe-load(content)
        catch e
          @log.error "send mail failed: parse template yaml failed.", e
          return lderror.reject 1017
      .then (payload) ~>
        option = from: payload.from, to: email, subject: payload.subject, content: payload.content
        if config.bcc => option.bcc = config.bcc
        @send-from-md(option, map,{now: config.now})

module.exports = mail-queue
