module.exports =
  pkg: {}
  interface: -> @ldcv
  init: ({root}) ->
    ldc.init ldc.register <[core viewlocals]>, ({core, viewlocals}) ~>
      <~ core.init!then _
      @ldcv = new ldcover root: root, zmgr: core.zmgr
      @view = new ldview do
        root: root
        action: click: pay: ->
          ld$.fetch "/extapi/pay/dummy-gateway/pay", {method: \POST}, {json: viewlocals{slug, name, amount}}
            .then -> core.ldcvmgr.get {name: "@servebase/payment", path: "gateway/paid"}
        text:
          name: ({node}) -> viewlocals.name or 'Not Available'
          amount: ({node}) -> viewlocals.amount or '0.00'
