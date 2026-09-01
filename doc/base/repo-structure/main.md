## Repo Structure ( TBD Tentative ) 

 - frontend: frontend related code.
   - In order to support multi-site tree, you should put all codes in separated subfolder. 
     - e.g., `frontend/demo` is the demo site for servebase.
     - you should add the folder name in the `base` field of your secret config ( `config/private/secret` )
     - you can manage frontend as a submodule or workspace with npm, to separate backend and frontend dependency.
   - subfolder under `frontend/xxx`: follow `@plotdb/srcbuild` structure.
     - `.view`: prebuilt pug js files.
     - `src`
       - ls, styl, pug: compiled into `static`.
       - raw: copied into `static` verbatim - favicon, robots.txt, images, fonts,
         anything served as-is. see `doc/base/infrastructure.md` ->
         Generated and Hand-Written Files.
       - include module pug with following code: (adopted from https://github.com/pugjs/pug/issues/3125):

           p = resolve: (fn,src,opt) -> if /^@\//.exec(fn) => path.resolve(fn.replace(/^@\//, 'module')) else fn
           pug.render code, {plugins: [p]}

     - `static`
       - `s`: hold static content that are supposed to be auto generated / uploaded by users.
         - consider this as a path (e.g., `/s/...`) for web, instead of actually storing files here.
           this can be pointed or routed to other places by symlink or nginx directive.
           it's not necessary to actually have this folder physically.
       - assets and other

 - .backend: prebuilt backend js
 - backend
   - engine
     - utilities modules including
       - db, auth, etc
       - other util # 額外的工具模組
     - server code:
       - index.ls, error-handler.ls, ...
   - route
     - router / api handler. use utilitis vis `require("backend/...")`

 - locales - for i18n
   - intl
     - zh-TW, en , ... etc 

 - doc
 - test
 - tool
 - script
 - user
 - config # 需要考慮到支援不同網域. ( 參考 repo-structure/config.md )
   - build, nginx, key, mail, site
 - other files
   - start
   - package.json, package-lock.json, .gitignore, .git, node_modules, server.log
   - secret ( 公開與非公開? )

