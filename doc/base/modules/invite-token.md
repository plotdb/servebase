# Invite Token Mechanism

The invite token mechanism restricts user registration by requiring a valid invite token during the signup process (including both OAuth and password-based scenarios).

To enable this mechanism, you need to:

- Set `policy.login.acceptSignup = 'invite'` in the secret configuration.
- Insert invite token records into the database, or implement your own invite token management system.

Once enabled, users will be prompted to enter an invite token during registration. Registration will be denied if no token is provided or if the token is invalid. Upon successful registration, the invite token will be recorded in the user's configuration field `config.invitetoken`.

This field is an object, where each key is an invite token and the corresponding value is the timestamp (in epoch milliseconds) indicating when it was used. This structure allows future support for multiple invite tokens per user.

Currently, the backend does not provide a built-in mechanism to generate invite tokens. However, a downstream user of Servebase, **Grant Dash**, has implemented one, which could potentially be reverse-integrated in the future.


## Token Field Details

Tokens are retrieved from the `invitetoken` table, which includes the following fields:

- `owner`: Key of the token creator
- `scope`: The code representing the token's intended owner (e.g., an organization), defined by the implementer
- `token`: The invite token itself
- `ttl`: Time-to-live for the token. Although defined, it is currently not implemented (TODO)
- `domain`: Domain to which the token applies
- `detail`: A JSON object containing:
  - `count`: Maximum allowed uses
  - `used`: Number of times used
- `deleted`: Whether the token has been deleted
