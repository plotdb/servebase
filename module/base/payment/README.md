# @servebase/payment

## Concept

Common flow of a payment:

 - User triggers the payment flow (by pressing payment button, etc)
 - Frontend collects required information, pass to `/pay/sign` via `payment.request(opt)` api (see below).
   - An internal payment record is created for tracking this payment.
 - Payload returned from `/pay/sign` sent to 3rd party payment gateway page. (e.g., `/ext/pay/gw/dummy`)
 - 3rd party gateway tracks and confirm the payment, post result to `/extapi/pay/gw/:name/notify`
   - State of the corresponding internal payment record is marked as complete.
     (or, marked according to the reported result)
 - 3rd party gateway redirects user to `/ext/pay/gw/:name/done` if the payment is confirmed immediately.
   - e.g., payment with credit card.


## Frontend APIs

payment object provides following methods:

 - `request(opt)`: request a payment to 3rd party payment gateway. opt is an object with following fields:
   - `gateway`: payment gateway name. Corresponding config in server config must exist.
   - `url`: optional. Alternative URL to payment gateway.
   - `payload`: payment information. Passed to server for signing, and then sent to payment gateway.
     - common fields as follows. Gateways may require additional fields.
       - `scope`: reference of the item this payment is for.
       - `slug`: this is generated automatically when signing for gateway signer.
       - `name`: generic name for this payment
       - `amount`: payment amount, in string.
   - `method`: HTTP request method. optional, `POST` if omitted.
 - `check(opt)`: check the state of a payment record. options:
   - `scope`: TBD
   - `slug`: payment slug to check


## Routes: Generic

 - `/extpi/pay/notify`: api accepting notification about a finished payment. (TBD)
 - `/ext/pay/done`: redirect page after a finished payment. (TBD)
 - `/pay/sign`: signing a payload before posting to 3rd party gateway.
 - POST `/pay/check`: check the state of a given payment. option:
   - `payload`: an object with `slug` field indicating the payment row to query

## Routes: Gateway Specific 

 - `/ext/pay/gw/:name`: payment page, showind payment detail and options / fields for users.
   - only applicable for dummy gateway, or any gateway supporting customized payment page.
 - `/extapi/pay/gw/:name/pay`:api for taking care of the payment request.
   - only applicable for dummy gateway, or any gateway supporting customized payment page.
 - `/ext/pay/gw/:name/done`: redirect page after a finished payment. (TBD)
 - `/extapi/pay/gw/:name/notify: api accepting notification about a finished payment. (TBD)



## Backend

init payment backend module with:

    require! <[@servebase/payment/lib]>
    lib opt

where `opt` is an object with following fields:

 - `backend`: backend object.
 - `route`: an object containing routes for different purposes:
   - `done(req, res, next)`: for redirection from a completed payment.
 - `perm`: permission check middlewares before different actions:
   - `sign(req, res, next)`: verify if a given signing attempt should be allowed.


## Configuration

You will have to configure server config file to enable payment, in `payment` field.

    payment:
      gateway: " ... " /* used gateway name, one of the fields below (dummy, newebpay, etc) */
      gateways:
        dummy: {}
        newebpay: /* following fields are defined by the gateway used */
          MerchantID: "..."
          hashkey: "..."
          hashiv: "..."
          ReturnURL: 'https://serve.base/ext/pay/gw/<gateway-name>/done'
          NotifyURL: 'https://serve.base/extapi/pay/gw/<gateway-name>/notoify'
          Email: "..."

When `payment.gateway` is `dummy`, a dummy gateway will be automatically created in this server.
