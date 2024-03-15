# @servebase/core

service core module that initializes, constructs and provides following members:

 - `global`: server basic information
 - `user`: user object
 - `auth`: authentication
 - `ldcvmgr`: popup module handler
 - `manager`: block manager
 - `loader`: full screen loading indicator
 - `captcha`: captcha provider
 - `zmgr`: z-index manager
 - `error`: error handler
 - `i18n`: i18n object. use this instead accessing `i18next` directly for module abstraction.
 - `hint`: additional information for above modules.

with additional APIs stored in `servebase` global variable:

 - `corectx(cb)`: run `cb` a ldc app with core inited as dependency.
   - example: `servebase.corectx(({core}) -> @auth == core.auth);`
   - return a Promise, resolved the return value of `cb` ( `cb` can also return Promise )
 - `config(opt)`: config core module. should be called before core is initialized.
   - see `Customization` section below for more detail.


## Usage

To use a `@servebase/core` module, use `ldc` to load it:

    ldc.register <[core]>, ({core}) -> ...


Alternatively, use `servebase.corectx`:

    <- servebase.corectx _
    # now `this` is the core object:
    @manager.from ...


## Dependencies

 - zmgr
 - ldloader
 - ldcvmgr
 - lderror
 - @servebase/captcha
 - @servebase/auth
 - @loadingio/ldc
 - @plotdb/semver
 - @plotdb/block
 - @plotdb/rescope
 - @plotdb/csscope
 - @plotdb/httputil
 - i18next ( optional )
 - i18nextBrowserLanguageDetector ( optional )


## Customization

`@servebase/core` is provided as a convenient basic toolkit for controlling a website, so you can still build your own core module.

However, building a similar module from scratch may be kinda a redundant work. Thus, following methods are provided for core module customization:

 - with `corecfg` ldc module, which is the dependency of `core` ldc module.
 - config with `servebase.config`.

Both the option in `servebase.config` or the `corecfg` ldc module are something with the same definition as below:

 - an object. In this case, it should be an object with following fields:
   - `manager`: a `@plotdb/block` block manager. Optional, it will replace the default manager if provided.
   - `auth`: an object to customize auth behavior, with following fields:
     - `authpanel`: block id of the authpanel to use.
   - `i18n`: optional i18n related configs. if provided, should be an object with following fields:
     - `locales`: i18n resource objects for core modules translation. namespaced. (such as navtop )
       - this should be an object containing objects for each namespace with bundles of languages. e.g.,

             {
                navtop: {en: {...}, "zh-TW": {...},
                footer: {en: {...}, "zh-TW": {...}
             }

         the actual fields and supported languages are up to the frontend code design.


     - `cfg`: optional i18n module configuration.
       - if provided, following fields should be defined:
         - `supportedLng`: list of supported languages. e.g.,  ["en", "zh-TW"]
         - `fallbackLng`: fallback language. e.g.,  `en`
         - `fallbackNS`: fallback namespace.
         - `defaultNS`: default namespace.
       - if omitted, following config will be used:

             {supportedLng: ["en, "zh-TW"], fallbackLng: "zh-TW", fallbackNS: "", defaultNS: ""}

     - `driver`: optional i18n module object. if omitted, i18next will be used if available.
 - a function. In this case, it will be called with `core` context and should return an object defined above.

`servebase.config` should always be called only once and before any possible core initialization to prevent inconsistent behavior.


## i18n

`@servebase/core` detects `lng` or `setlng` querystring to enfoce a locale setting. `lng` is temporarily and `setlng` will also update cookie for following access. For example:

    https://serve.base/?lng=en


## hint

`hint` provides additional informations for core modules. It's an object with following fields:

 - `i18n`: an object with following fields:
   - `placeholder`: default false. Indicate if a given i18n module is a placeholder.
     - a placeholder i18n module is a module that only contains keys and no actual translations.
       It's used to provide a default value for a given key.
