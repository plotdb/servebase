# @servebase/erratum

Global error / rejection handler. Also wrap `lderror` event handler to provide better lderror event handling.


## Usage

    new erratum({ handler: (err) -> ... })


## Lockdown

By default each error is answered on its own terms: the dialog for that error
code opens and the page carries on. That is the right response while the error
*is* the problem, and the wrong one once the page itself can no longer be
trusted - a document that failed to rebuild, a sync layer that stopped acking.
From there on every further action is taken against a state nobody can vouch
for.

`lockdown` routes **every** error to a single dialog instead:

    erratum.lockdown -> ldcvmgr.lock {ns: \local, name: \hint-reload}

It is a toggle rather than a constructor option because *when* it is safe to
engage is a runtime question - start-up has its own permission and fetch
failures that are perfectly ordinary, and locking the page on those would break
it for everyone. Engage it once past that point:

    erratum.lockdown true     # engage, reusing the dialog set earlier
    erratum.lockdown false    # stand down, back to per-error handling
    erratum.locked!           # current state

The dialog fires at most once per engagement. A second one would add nothing -
the page is already declared unsafe - and whatever is failing is likely to keep
failing, which would otherwise stack a cover per error, or loop outright if the
dialog's own code is what throws.


## Builtin Dialogs

`@servebase/erratum` provides some generic builtin dialogs for quickly building a error handling mechanism. These dialogs are shipped in `@plotdb/block` format and are expected to be the fallback of `/modules/error` related block files.

Example is available in demo nginx config for adopting these as a fallback. The following example is from the demo config:


    location ~ ^/modules/error/(.*)$ {
      root !{root};
      try_files /modules/error/$1 /assets/lib/@servebase/erratum/main/block/$1 @apiserver;
    }



## Note

`window.onerror` is not triggered when the console directly generates an error.

It can be triggered via wrapping test code with setTimeout - however `evt.error` will be null.

Alternative to listener:

    window.onerror = (msg,fn,lineno,colno,error) -> ...


## Handler Suggestion

Expired session removal may cause an active session expire, which leads to csrftoken mismatch (1005). We should prompt and ask user to re-auth if necessary:

    if lderror.id(e) == 1005 => auth.fetch {renew: true} # or any other reload / reauth actions
