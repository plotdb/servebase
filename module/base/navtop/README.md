# @servebase/navtop

site-wise navigation menu dynamics


## Usage

    ldc.register <[navtop]>, ({navtop}) -> ...


`@servebase/navtop` uses ldview to manipulte its DOM. following ld selectors are available:

 - `signup`: authpanel is triggered in signup tab when clicked
 - `login`: authpanel is triggered in login tab when clicked
 - `logout`: sign user out when clicked
 - `displayname`: show user's displayname
 - `admin`: show if `user.staff` is not false
 - `unauthed`: show if it's an anonymous user
 - `authed` show if current user is signed in.
 - `avatar`: show user avatar. default to `/assets/avatar/#{uid}`
 - `t`: indicating that this tag should be translated. `textContent` of this tag will be used as key.
 - `lng-picker`: indicating a language picker widget, and will be hidden if i18n module is either a placeholder or not available.

Set th `ld-scope` attribute to `@servebase/navtop` in the root element of your navbar for the module to recognize your DOM tree.


## Class Transition

`@servebase/navtop` changes bar class if data-classes and data-pivot is defined.

 - `data-classes`: "class1 class2 ...;class1 class2 ..." for before and after transition classs.
 - `data-pivot`: node to monitor for visibility and thus reflect the whether state should be change.

node from `data-pivot` is watched for visibility changes so there are several possible scenarios of the visibility:

 - not intersected -> intersected
   - class changes: `before` -> `after`
 - intersected -> not intersected
   - class changes: `after` -> `before`
 - not intersected -> intersected -> not intersected
   - class changes: `before` -> `after` -> `before`

we may need additional flexibility of controlling navtop behavior based on multiple pivot nodes, which is left as future work.


## API

the `navtop` module provides following API:

 - `toggle(v)`: show / hide navbar based on value `v`.


## i18n Namespace

namespace `@servebase/navtop` is used when translating. Config your i18n object accordingly for i18n support.
