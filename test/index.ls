# test runner. no framework: every test is a plain script that asserts for itself
# ( see doc/base/testing.md ). this only finds them, runs each in its own process and sums up.
#
#   npm test                      # unit tests of the root and every workspace
#   npm test -- --integration     # integration tests too ( may need postgres etc. )
#   npm test -- auth mail         # only tests whose path contains `auth` or `mail`
#
# exit code of a test: 0 pass, 77 skipped ( e.g. postgres unreachable ), anything else fail.

require! <[fs path child_process]>

root = path.join __dirname, \..
SKIP = 77

# `lsc test/index.ls` and `node test/index.js` place argv differently - take what follows this script.
args = process.argv.slice(process.argv.findIndex((-> /test[\\/]index\.(ls|js)$/.test it)) + 1)
integration = \--integration in args
filters = args.filter -> !/^--/.test(it)

workspaces = [\.] ++ (JSON.parse(fs.read-file-sync path.join(root, \package.json)).workspaces or [])
kinds = [\unit] ++ (if integration => [\integration] else [])

list = []
for ws in workspaces => for kind in kinds
  dir = path.join root, ws, \test, kind
  if !fs.exists-sync(dir) => continue
  for f in fs.readdir-sync(dir).filter(-> /\.(ls|js)$/.test it).sort!
    list.push path.relative(root, path.join dir, f)
if filters.length => list = list.filter (f) -> filters.some -> f.includes it
if !list.length =>
  console.log "no test found#{if filters.length => ' for ' + filters.join(', ') else ''}."
  process.exit 1

lsc = path.join root, \node_modules/.bin/lsc
result = {pass: [], fail: [], skip: []}
for f in list
  console.log "\n━━ #f"
  bin = if /\.ls$/.test(f) => lsc else process.execPath
  r = child_process.spawn-sync bin, [f], {cwd: root, stdio: \inherit}
  code = if r.status? => r.status else 1
  result[if code == 0 => \pass else if code == SKIP => \skip else \fail].push f

console.log "\n━━ #{list.length} tests: #{result.pass.length} passed, #{result.fail.length} failed, #{result.skip.length} skipped"
for f in result.skip => console.log "  skip #f"
for f in result.fail => console.log "  FAIL #f"
if !integration => console.log "  ( integration tests not run, add --integration )"
process.exit(if result.fail.length => 1 else 0)
