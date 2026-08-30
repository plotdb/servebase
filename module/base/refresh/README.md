# @servebase/refresh

Tell a page that is already open that the deploy underneath it moved on, and let the
person decide when to reload.

Status: WIP / proof of concept. Nothing outside this directory is touched, so nothing
in a running site changes until it is wired in - see Wiring.

Both halves have been exercised against a live server: the header follows the `.version`
file at runtime without a restart, and the client fires once when the value moves and
not again. What has not been decided is where the notice belongs in a real page, and
whether a page that never calls the api needs a heartbeat.


## Why

A browser tab can outlive several deploys. It is holding html, js and css from one
build and talking to an api from another, and nothing tells it so.

Content addressing does not solve this, it only removes the crash: the hashed urls the
page holds keep resolving ( and `try_files` covers a url whose generation has been
expired ), so the page keeps working - it is just old, silently. Backend api drift is
the part that actually bites, and no asset strategy can fix it.

This is the other half of that story. It is also what makes the cheap retention setting
( `hash.keep = 3`, `keepDays = 0` ) the right default: we do not try to keep every
artefact alive forever, we tell the page to catch up instead.


## How

The server states its running version on every response; the page compares it with the
first value it ever saw.

    server   res.set 'X-App-Version', backend.version
    client   wrap fetch, read the header, fire `updated` when it changes

No polling and no extra request - it rides on traffic the page was making anyway.
`backend.version` comes from the `.version` file, which is watched at runtime, so this
follows a deploy without a restart.

Deliberate limits:

 - it fires once. the point is to offer a reload, not to nag.
 - it never reloads by itself. a forced reload throws away whatever the person was in
   the middle of, and the whole premise here is that the page is usable but stale.
 - a page that never talks to the server never notices. that is the honest cost of not
   polling; a heartbeat can be added later behind the same `updated` event.


## Wiring ( not done )

Four steps, none of them taken here.

1. register the workspace, in the root `package.json` and in `<feroot>/package.json`,
   and add `{"name": "@servebase/refresh", "dir": "dist"}` to `frontendDependencies`.
2. backend, in `backend/engine`:

        require! <[@servebase/refresh]>
        app.use new refresh({backend: @}).middleware

   note this tags every response, not just api routes.
3. frontend, add `{name: "@servebase/refresh", version: "main"}` to the `+script` list
   in `base.pug` ( or `dev/base.pug` to try it on dev pages only ).
4. decide the notice:

        servebaseRefresh.init!
        servebaseRefresh.on \updated, ->
          # ldnotify is already a dependency. non-blocking, with a reload action.

Everything above is base-namespace, so derived projects get it on merge.


## Demo

`demo/index.pug` is a page that shows the version this page first saw, the version the
last response reported, and the banner when they diverge. It is kept here rather than in
the site because it only works once the wiring above is done. To try it, do the wiring
with step 3 pointing at `dev/base.pug`, drop the file into
`<feroot>/src/pug/dev/refresh/index.pug`, and open `/dev/refresh/`.

Simulating a deploy needs no restart - the version comes from the `.version` file, which
is watched at runtime:

    echo "deploy-$(date +%s)" > .version


## Options

    header    response header to use. default `X-App-Version`.
