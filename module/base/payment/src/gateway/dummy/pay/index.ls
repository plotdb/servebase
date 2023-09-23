module.exports =
  pkg: {}
  interface: -> @ldcv
  init: ({root}) ->
    (res, rej) <~ new Promise _
    ldc.init ldc.register <[core viewlocals]>, ({core, viewlocals}) ~>
      info = (viewlocals.info or {})
      @ldcv = new ldcover root: root, zmgr: core.zmgr
      @view = new ldview do
        root: root
        action: click: pay: ~>
          ld$.fetch "/extapi/pay/gw/dummy/pay", {method: \POST}, {json: info}
            .then ~> @ldcv.set!
        text:
          name: ({node}) -> info.name or 'Not Available'
          amount: ({node}) -> info.amount or '0.00'
      res!

