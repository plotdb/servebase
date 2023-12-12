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
 - 3rd party gateway redirects user back if the payment is confirmed immediately.
   - e.g., payment with credit card.
   - Returned URL is defined in config and payment gateway. e.g., `/ext/pay/done`.


## Frontend APIs

payment object provides following methods:

 - `request(opt)`: request a payment to 3rd party payment gateway.
   - opt is an object with following fields:
     - `gateway`: payment gateway name. Corresponding config in server config must exist.
     - `url`: optional. Alternative URL to payment gateway.
     - `payload`: payment information. Passed to server for signing, and then sent to payment gateway.
       - common fields as follows. Gateways may require additional fields.
         - `scope`: reference of the item this payment is for.
         - `slug`: this is generated automatically when signing for gateway signer.
         - `name`: generic name for this payment
         - `amount`: payment amount, in string.
     - `method`: HTTP request method. optional, `POST` if omitted.
   - returns an object with following value:
     `url`: url of the gateway page to open.
     `method`: HTTP method (GET, POST, etc) to use when opening the gateway payment page.
     `payload`: data to send to gateway page.
     `slug`: unique slug for this payment
     `state`: state of this payment
     `key`: key of this payment.
 - `check(opt)`: check the state of a payment record. options:
   - `scope`: TBD
   - `slug`: payment slug to check


## Routes: Generic

 - `/extpi/pay/notify`: api accepting notification about a finished payment.
 - `/ext/pay/done`: generic redirect page after a finished payment.
 - `/pay/sign`: signing a payload before posting to 3rd party gateway.
 - POST `/pay/check`: check the state of a given payment. option:
   - `payload`: an object with `slug` field indicating the payment row to query


## Routes: Gateway Specific 

 - `/ext/pay/gw/:name`: payment page, showing payment detail and options / fields for users.
   - only applicable for dummy gateway, or any gateway supporting customized payment page.
 - `/extapi/pay/gw/:name/pay`:api for taking care of the payment request.
   - only applicable for dummy gateway, or any gateway supporting customized payment page.
 - Following APIs will be needed when we support multiple gateways in the same site.
 - `/ext/pay/gw/:name/done`: gateway specific redirect page after a finished payment.
 - `/extapi/pay/gw/:name/notify: api accepting notification about a finished payment.


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
          testing: true /* true to use testing environment */
          MerchantID: "..."
          hashkey: "..."
          hashiv: "..."
          ReturnURL: 'https://serve.base/ext/pay/done'
          NotifyURL: 'https://serve.base/extapi/pay/notify'
          Email: "..."

When `payment.gateway` is `dummy`, a dummy gateway will be automatically created in this server.
