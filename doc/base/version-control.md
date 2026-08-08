# Version Control

This document describes how we manage versions, releases and different customization via git.


## Repository / Branch structures

 - repo: source
   - master
   - dev/...
   - release/a.b.c
   - release/d.e.f
 - repo: customer-a ( derived from release/a.b.c, in standalone repo )
   - master
   - dev/...
   - release/g.h.i
 - repo: customr-b ( derived from release/d.e.f, in standalone repo )
   - master
   - dev/...
   - release/j.k.l
 - ...


## development process

 - (master) : develop on `master` branch
 - (dev/...) : experiment features / functionality on `dev/...` branch. merge back to master if needed.
 - (master -> release/xxx) : branch to release/xxx when releasing.
 - (commit -> release/xxx) : cherry-pick commits from mainstream to specific release branch for hotfixes.
 - (source/release/a.b.c -> customer/master) : upgrade customer-a by merging source/release/a.b.c
 - (customer/master -> customer/release/yyy) : customer repo can also has releases.
 - only branch when we need hotfix. otherwise simply use tag.


## versioning: servebase vs derived projects

servebase and each derived project keep their own versions, independently:

 - servebase version:
   - tracked by git tags + `doc/base/CHANGELOG.md` ( `## master` section for unreleased changes )
   - servebase does NOT bump the `version` field in `package.json` — that file is shared,
     and bumping it would create a merge conflict for every derived project.
     the `version` field belongs to derived projects.
 - derived project version:
   - tracked by its own git tags + root-level `CHANGELOG.md` + `package.json` version field.
   - root-level `CHANGELOG.md` is reserved for derived projects; servebase must not create one.
 - which servebase version a derived project is based on:
   - `doc/base/CHANGELOG.md` comes along when merging from servebase — its topmost
     version section tells the current base version. no extra marker file needed.
   - machine-readable alternative: `git merge-base HEAD servebase/master` + `git describe --tags`
 - upgrading across servebase versions:
   - breaking changes are documented per version in `doc/base/migration-note.md`.
     when an upgrade spans multiple versions, walk through the notes version by version.

in general, servebase keeps its own files under its own namespace
( `doc/base/`, `backend/base/`, `frontend/base/`, `config/base/`, `module/base/`,
`context/servebase/` ) so derived projects can add their own files
( e.g. `context/project/`, root-level `CHANGELOG.md` ) without merge conflicts.


## private files

Following files will (and should) be ignored, and thus won't be committed to version control system, based on the  `.gitignore` settings:

 - `local.*`
 - `*.log`
 - `secret.*`
 - `config/private` folder.

Additionally, there are other files ignored in `.gitignore` file but it's up to users' descretion to keep ignoring them or not. See `.gitignore` for more information.


## setup new customer repo

init:

    git init # create a new, empty repo
    # repo url can be like git@github.com:plotdb/servebase
    git remote add servebase <servebase-repo-url>
    git fetch servebase
    git reset --hard servebase/master # alternatively to specific tag / release.
    git remote add origin <our-repo-url> # repo we are going to use
    git push -u origin master # populate data into remote repo
    npm i # and any other necessary initializing commands

update:

    # ... make some changes ... and then commit + push ...
    git fetch servebase # pull in newly update from servebase
    git merge servebase/master # or specific branches, to update our codebase
    git push # update our remote repo
