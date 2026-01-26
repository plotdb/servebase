# Audit Logs

## Database

You can log / track database queries via `database.query-audit` api. It's the same with `database.query` except with the third additional parameter as an object with at least and `audit` field, which is used to distinguish from possible future configs of `database.query`:

    {db} = backend
    db.query-audit "update ....", [...], {audit: { ... }}

Without `audit` field, `database.query-audit` acts the same with `database.query`; we can consider merge these 2 APIs but for now we use a separated name to make it clear that we are using an audited version of query API.

The `audit` field of the thrid parameter in `batabase supports follow fields:

 - `atomic`: boolean, default true. when true, the actual query and the audit log query will be atomic.
   - That is, the actual query will only work if audit is successful, otherwise will be rolled back.
 - `req`: the request object from express router.
   - Informations such as path, sessionID and IP will be retrieved and stored if available.
 - `action`: purpose of the logged action. The naming structure is defined in below section.
 - `option`: object of additional information about this action. optional. Empty if omitted.
 - `user`: user key who conducts this action.
 - `new`: data to be written. optional, query params will be used if omitted.
 - `old`: data to be replaced. optional, left empty if omitted
   - `new` and `old` field will be put into the params field of the object to be stored in the `data` field.


By default, user session ID, IP, user key will be kept directly in auditlog table along with its local log time.


## Action

Action is defined as an unique string, indicating the purpose of the logged query is for. For simplicity, it's defined as a string with 3 separated parts, `domain`(optional), `target(mandatory)` and `action`(mandatory):

    domain(.decorator):target(.decorator):action(.decorator)

where decorator is also a string:

    prj:state.batch

To prevent confusion and chaos, you should always use only one decorator in each section ( either domain, target or action); for any additional decorators, put it in the `option` field as an object with key(option) / value pairs. For example:

    {
      action: "prj:state.batch",
      option: { dry-run: true, force: true }
    }
