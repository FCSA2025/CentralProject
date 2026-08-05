# RemIcsReWrite Phase 5 — Raw-IP access (cookies + diagnostics)

**Status:** Implemented (2026-07-31)  
**Email:** Still **disabled** (`DisableOutgoingEmail=true`). Re-enable is **Phase 7**.

## What changed

| Area | Change |
|------|--------|
| `SesUtils.ApplyPrefCookieDomain` / `IsRequestHostIp` | Pref cookies omit `.Domain` when Host is an IP |
| `TloginValidate.aspx.cs` | PrefUID / PrefTime / PrefHelp use helper |
| `sesTimeoutSet.aspx.cs` | PrefTime uses helper |
| `RemIcsReWrite/login.aspx.cs` | `SetAuthCookie` host-only (unchanged API); relative redirect; IP diag |
| `session.ashx` | Returns `isIp`, `siteDomainConfig`, `cookieDiag.advice` |

**Not changed:** `web.config` `SiteName` / `SiteDomain` (keep for email links + legacy hostname).

## Ops you may still need

1. IIS site binding on the public/VIP IP, port 80, **Host name blank**.  
2. Firewall / security group: inbound TCP 80 (and 443 if used) from allowed CIDRs.  
3. Bookmark: `http://<PUBLIC_OR_LAN_IP>/mics/RemIcsReWrite/login.aspx`

## User policy

- **One URL per session** — IP *or* hostname, not both in the same browser profile.  
- Clear site cookies when switching between IP and `remicsdev.cloudmicsdev.ca`.

## How to test

### A. Hostname (regression)

1. Open `http://remicsdev.cloudmicsdev.ca/mics/RemIcsReWrite/login.aspx`  
2. Log in (e.g. `rctl1`).  
3. Diag drawer → `session.ashx`: `ok: true`, `isIp: false`.  
4. Smoke: TS Data Files → Validate or list loads (no 401).

### B. Raw IP (Phase 5 gate)

1. Use an IP that hits this IIS site (LAN or public VIP).  
2. Prefer a **private/incognito** window (or clear cookies for that origin).  
3. Open `http://<IP>/mics/RemIcsReWrite/login.aspx` — not the hostname URL.  
4. Log in.  
5. DevTools → Application → Cookies for `http://<IP>`:  
   - `.ADAuthCookie`, `ASP.NET_SessionId`, and any `Pref*` → **Domain empty** (host-only).  
6. Diag → `session.ashx`: `isIp: true`, `ok: true`, `formsCookieOnRequest: true`.  
7. Smoke: open **TS Data Files** (or ES); confirm list JSON / ASMX not 401.  
8. Optional: Validate one small file.

### C. Negative check (mixed cookies)

If you open hostname, then IP in the **same** profile without clearing cookies, you may see odd logout/401 — that is expected; use one host per session.

## Next

- **Phase 6** — PCN Coordination  
- **Phase 7** — Re-enable `DisableOutgoingEmail` + verify email contracts (DbUpdate, TSIP, PCN)
