# NOTE: mocha and nyc are on their way out.
#
# New tests are written as plain scripts you can run directly - they assert
# for themselves and exit non-zero on failure, e.g.
# module/base/mail/test/transport.ls ( npm run test:script ). That is two
# fewer devDependencies, and no need to bend a test into the shape a
# framework wants.
#
# This file is still here only because `npm test` points at it; once whatever
# is left has moved over, it goes along with mocha and nyc.

require! <[fs path assert]>

that = it

describe 'name', ->
  that "some action should be what", ->
    asset.deep-strict-equal 1, 1
