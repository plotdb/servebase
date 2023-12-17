# Oen Provider

configuration:

 - `merchantId`: usually the subdomain of the admin panel.
   - e.g., the `<merchantId`> part of `<merchantId>.oen.tw`
 - `token`: authorization token passed in header along with API calls to oen.
   - available in general settings in admin panel of oen.
 - `successUrl`: redirect URL when paid successfully.
 - `failureUrl`: redirect URL whtn paid unsuccessfully.
