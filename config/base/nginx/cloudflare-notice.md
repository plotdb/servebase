# Running behind Cloudflare

`config.ngx` assumes nginx faces the visitor directly. Behind Cloudflare it does not:
every connection comes from a CF edge node, so `$remote_addr` is a CF address
( e.g. `172.68.106.144` ), never the visitor's.

Nothing in this config compensates for that.

## What is wrong right now

1. **access.log is useless for analytics** — every line records a CF node.
   One production site accumulated 14G of such logs before anyone looked.

2. **The backend receives the wrong client ip.** In `@apiserver`:

   ```nginx
   proxy_set_header X-Real-IP $remote_addr;
   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   ```

   Both headers carry the CF node address, so anything keyed on client ip — rate
   limiting, abuse tracing, audit logs, geo decisions — is wrong. Derived projects
   that add a second proxy block ( a registry backend, say ) repeat those two lines
   and inherit the same problem.

3. **`limit_req` would be worse than useless.** The commented-out
   `limit_req zone=api burst=7 nodelay` would throttle per CF node, i.e. treat every
   visitor as one client. Do not enable it before this is fixed.

## The fix, and why it is not here yet

nginx's realip module rewrites `$remote_addr` itself, before any location is
evaluated, so all three resolve at once and **no `proxy_set_header` line changes**:

```nginx
set_real_ip_from <each cloudflare range>;
real_ip_header CF-Connecting-IP;
```

`real_ip_recursive` is not needed — `CF-Connecting-IP` is always a single address,
not an X-Forwarded-For style list.

What blocks committing this is the range list: it changes over time, it is shared by
every derived project, and a wrong or stale entry is a wrong trust boundary. That
needs a generator and an include mechanism, tracked in
`context/servebase/tasks/todo/20260912-nginx-rule-include.md` and
`context/servebase/tasks/todo/20260912-cloudflare-real-ip.md`.

## If a site needs this before then

Fetch the current ranges from https://www.cloudflare.com/ips-v4 and
https://www.cloudflare.com/ips-v6 — do not copy a list out of a blog post — and put
the directives at the top of the server block, before any `location`. Add them to the
port 80 block too, or its redirect logs stay wrong.

**`set_real_ip_from` must list only Cloudflare ranges.** Without it, or with
`0.0.0.0/0`, anyone can send `CF-Connecting-IP: 1.2.3.4` and forge their source
address. With a correct list a direct-to-origin attacker is not in a trusted range,
so the header is ignored. ( Blocking direct origin access is a separate concern:
that is about bypassing CF's WAF and DDoS protection, not ip spoofing. )

Anything added by hand will be superseded once the include mechanism lands. Leave a
comment saying so.
