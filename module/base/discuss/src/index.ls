
discuss = (o = {}) ->
  @root = if typeof(o.root) == \string => document.querySelector(o.root) else o.root
  @host = o.host or {}
  @cfg = o.config or {}

  if marked? =>
    md = new marked.Marked!
    markedr = new marked.Renderer!
    markedr.link = (href, title, text) ->
      link = marked.Renderer.prototype.link.call @, href, title, text
      return link.replace \<a, '<a target="_blank" rel="noopener noreferrer" '
    md.setOptions renderer: markedr

  @ <<<
    _evthdr: {}
    _loading: false
    _purify: (t) ->
      if DOMPurify? => return DOMPurify.sanitize t
      console.warn "[@servebase/discuss] DOMPurify is not found which is required for DOM sanitizing"
      return t
    _md: (t) ->
      if marked? and md => return md.parse t
      console.warn "[@servebase/discuss] marked is not found which is required for markdown compiling"
      return t
    comments: [], discuss: {}
  @_uri = o.uri or window.location.pathname
  @_slug = o.slug or null
  @_core = o.core
  @_edit = {}
  @

discuss.prototype = Object.create(Object.prototype) <<<
  on: (n, cb) -> (if Array.isArray(n) => n else [n]).map (n) ~> @_evthdr.[][n].push cb
  fire: (n, ...v) -> for cb in (@_evthdr[n] or []) => cb.apply @, v
  is-ready: ({ctx}) -> !!(@_edit{}[ctx.key].{}content.body or '').trim!length
  init: ->
    @view = @_view {root: @root}
    @_core.init!
      .then ~> @_core.auth.get!
      .then (g) ~> @g = g
  load: ->
    @_loading = true
    @view.render!
    @fire \loading
    payload = if @_slug => {slug: @_slug} else {uri: @_uri}
    ld$.fetch \/api/discuss, {method: \GET}, {params: payload, type: \json}
      .finally ~> @loading = false
      .then (r) ~>
        @ <<<
          comments: r.comments or []
          discuss: r.discuss or {}
          roles: r.roles or {}
        @fire \loaded
        @view.render!
  content-render: ({node, ctx}) ->
    obj = ctx.content or {}
    if !(obj.config or {})["renderer"] or !(obj.body?) => node.innerText = (obj.body or '')
    else node.innerHTML = @_purify @_md obj.body
  _view: ({root}) ->
    set-cfg = (ctx, o = {}) ~> for k,v of o => @_edit{}[ctx.key].{}content.{}config[k] = v
    set-avatar = ({node, ctx}) ~>
      if @host.avatar => node.style.background = "url(#{@host.avatar {comment: ctx or {}}})"
      else node.style.background = \auto
    cfg = {}
    cfg.edit =
      action:
        input:
          input: ({node, views, ctx}) ~>
            @_edit{}[ctx.key].{}content.body = node.value
            views.0.render \submit
        click:
          cancel: ({node, ctx, views}) ~>
            @_edit{}[ctx.key].editing = !@_edit{}[ctx.key].editing
            views.1.render!
          submit: ({node, ctx, ctxs}) ~>
            if node.classList.contains \running => return
            if node.classList.contains \disabled => return
            if !@is-ready {ctx} => return
            # {uri, reply, content, slug, key, title}
            payload =
              key: ctx.key
              uri: @_uri
              content: JSON.parse(JSON.stringify(@_edit{}[ctx.key].content or {}))
              slug: @_slug
            @_core.auth.ensure!
              .then ~>
                @_edit{}[ctx.key].ldld.on!
                @_core.captcha
                  .guard cb: (captcha) ->
                    payload <<< {captcha}
                    ld$.fetch(
                      \/api/discuss/comment
                      {method: if payload.key => \PUT else \POST}
                      {type: \json, json: payload}
                    )
              .then (ret) -> debounce 1000 .then -> return ret
              .then (ret) ~>
                ctx <<< content: JSON.parse(JSON.stringify(@_edit{}[ctx.key].content or {}))
                if !ctx.key =>
                  c = {
                    owner: @_core.user.key
                    createdtime: Date.now!
                    _user:
                      key: @_core.user.key,
                      displayname: @_core.user.displayname
                  } <<< payload{uri, content, slug} <<< ret{key, slug}
                  @fire \new-comment, c
                  @comments.push c
                # TODO we may want to update role object
                # o commenters can see their roles immediately
                @_edit{}[ctx.key].{}content.body = ''
                @_edit{}[ctx.key].preview = false
                @view.get \input .value = ''
                @view.render!
              .finally ~> debounce 1000 .then ~> @_edit{}[ctx.key].ldld.off!
      init: submit: ({node, ctx}) ~> @_edit{}[ctx.key].ldld = new ldloader root: node
      handler:
        "@": ({node, ctx}) ~>
          if ctx.key => return node.classList.toggle \d-none, !@_edit{}[ctx.key].editing
          hide = if !@host.perm => !@cfg["comment-new"]
          else !@host.perm({comment: ctx, action: \new, config: @cfg})
          node.classList.toggle \d-none, hide
        input: ({node, views, ctx}) ~>
          node.value = @_edit{}[ctx.key].{}content.body or ''
        "toggle-preview":
          action:
            input: check: ({node, views, ctxs}) ~>
              @_edit{}[ctxs.0.key].preview = !!node.checked
              views.1.render!
            click: label: ({node, views, ctxs}) ~>
              input = views.0.get \check
              @_edit{}[ctxs.0.key].preview = input.checked = !input.checked
              views.1.render!
        "use-markdown":
          action:
            input: check: ({node, views, ctxs}) ~>
              use-markdown = !!node.checked
              set-cfg ctxs.0, {renderer: if use-markdown => \markdown else ''}
              views.1.render!
            click: label: ({node, views, ctxs}) ~>
              input = views.0.get \check
              use-markdown = input.checked = !input.checked
              set-cfg ctxs.0, {renderer: if use-markdown => \markdown else ''}
              views.1.render!
        avatar: set-avatar
        preview: ({node, ctx}) ~>
          revert = ("off" in node.getAttribute(\ld).split(" "))
          state = (
            !(
              @_edit{}[ctx.key].preview and
              ((@_edit{}[ctx.key].content or {}).config or {}).renderer == \markdown
            ) xor revert
          )
          node.classList.toggle \d-none, state
        panel: ({node, ctx}) ~> @content-render {node, ctx: @_edit{}[ctx.key]}
        submit: ({node, ctx}) ~> node.classList.toggle \disabled, !@is-ready {ctx}
        "if-markdown": ({node, ctx}) ~>
          hidden = ((@_edit{}[ctx.key].content or {}).config or {}).renderer != \markdown
          node.classList.toggle \d-none, hidden
    cfg.discuss = text: "@": ~> (@discuss or {}).title or 'untitled'
    cfg.comments = handler:
      "no-comment": ({node}) ~> node.classList.toggle \d-none, @comments.length
      comment:
        list: ~> @comments
        key: -> it.key
        view: 
          text:
            date: ({ctx}) ->
              if isNaN(d = new Date(ctx.createdtime)) => return \-
              new Date(d.getTime! - (d.getTimezoneOffset!*60000)).toISOString!.slice(0,19).replace(\T,' ')
            author: ({ctx}) -> ctx._user.displayname
          action: click:
            edit: ({node, ctx, views}) ~>
              @_edit{}[ctx.key].editing = !@_edit{}[ctx.key].editing
              views.0.render!
            delete: ({node, ctx}) ~>
              @_core.auth.ensure!
                .then ~>
                  if !@host.confirm-delete => return Promise.resolve true
                  return @host.confirm-delete {comment: ctx}
                .then ~>
                  if !it => return
                  @_edit{}[ctx.key].ldld.on!
                  ld$.fetch(
                    "/api/discuss/comment/#{ctx.key}", {method: \DELETE}
                  )
                    .finally ~>
                      debounce 1000 .then ~> @_edit{}[ctx.key].ldld.off!
                      return
                    .then ~>
                      @fire \delete-comment, ctx
                      @comments.splice @comments.indexOf(ctx), 1
                      @view.render!
          init: "@": ({ctx}) ~> @_edit{}[ctx.key].content = JSON.parse(JSON.stringify(ctx.content))
          handler:
            update: { ctx: ({ctxs}) -> ctxs.0 } <<< cfg.edit
            edit: ({node, ctx}) ~>
              hide = if !@host.perm => false
              else !@host.perm({comment: ctx, action: \edit, config: @cfg})
              node.classList.toggle \d-none, hide
            delete: ({node, ctx}) ~>
              hide = if !@host.perm => false
              else !@host.perm({comment: ctx, action: \delete, config: @cfg})
              node.classList.toggle \d-none, hide
            avatar: set-avatar
            role:
              list: ({ctx}) ~>
                ret = @roles[ctx.owner] or []
                (if Array.isArray(ret) => ret else [ret]).filter(->it)
              key: -> it
              view: text: name: ({ctx}) ~> if @_core.i18n => @_core.i18n.t(ctx) else ctx
            content: (o) ~> @content-render o{node, ctx}

    return new ldview do
      root: root
      init-render: false
      handler:
        loading: ({node,names}) ~> node.classList.toggle \d-none, !(@_loading xor ('off' in names))
        discuss: cfg.discuss
        edit: {ctx: -> {}} <<< cfg.edit
        comments: cfg.comments

if module? => module.exports = discuss
else if window? => window.discuss = discuss
