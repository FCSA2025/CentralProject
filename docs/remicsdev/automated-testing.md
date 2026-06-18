# ReMICS Dev — automated testing strategy

**Codebase:** remicsdev  
**Last updated:** 2026-06-17  
**Related:** [Login flow & session model](login-flow.md) (manual test template)

Long-term goal: a **repeatable automated test suite** that validates login, session contract, environment wiring, and (eventually) batch execution — starting from the manual browser test that succeeded on remicsdev.

---

## Manual test template (validated 2026-06-17)

The following manual procedure **passed** on remicsdev and is the seed for automation:

1. Log in at `http://remicsdev.cloudmicsdev.ca/mics/Tlogin.aspx`
2. Confirm main navigation loads (`TnavigationFull` frame shell)
3. Open `/mics/Maintenance/shownetsession.aspx` in the same browser session
4. Assert session fields present: `FCSASESS`, `s_user`, `s_schema`, `db_name`, `prog_dir`, `user_dir`, `Active=T`, etc.
5. Optional server corroboration: `D:\MicsWebLogs\logins\<user>_conn.txt`, `userdirs\<schema>\<user>\`

This proves the full chain: **Forms/AD auth → `TloginValidate` → SQL session → session keys → navigation active**.

---

## Automation tiers — scope and limits

| Tier | Name | What it tests | How | How far | Main limitations |
|------|------|---------------|-----|---------|------------------|
| **1** | HTTP smoke | Login POST, redirect chain, session cookie, `shownetsession` HTML | PowerShell / curl with cookie jar; parse `__VIEWSTATE` | Login + session field assertions | No JS/iframes; may need extra GET to `navigationTop.aspx` for `Active=T` |
| **2** | Browser E2E | Full UI login, frames, cookies, diagnostics page | **Playwright** (recommended) or Selenium on Windows | Closest to manual test; logout/relogin | Legacy Web Forms + Telerik; timing; needs dedicated test account |
| **3** | Server-side checks | Log files, `userdirs`, optional SQL | PowerShell on server or via share | Corroborates session setup without browser | Not a substitute for “user can log in” |
| **4** | Batch smoke | One safe batch job after login | Browser or HTTP trigger + wait + assert log/exit | End-to-end through `JobSubmit` + `CreateProcessAsUser` | Requires domain user, Windows token path, dev-safe job; hard in generic Linux CI |

**Tier 5 (future, not in current backlog):** module-by-module regression (menus, imports, reports) — only after tiers 1–4 are stable.

---

## Recommended implementation order

### Tier 1 — HTTP smoke (implement first)

Fast, no browser install, good for post-deploy checks.

```
GET  Tlogin.aspx          → capture VIEWSTATE / EVENTVALIDATION
POST Tlogin.aspx          → credentials, follow redirects
GET  navigationTop.aspx   → optional, to set Active=T
GET  Maintenance/shownetsession.aspx
     → parse HTML, assert expected key/value pairs
```

**Suggested location:** `tests/remicsdev/smoke/login-session.http.ps1`

**Assertions (minimum):**

- HTTP 200 on `shownetsession` after login
- Body contains `FCSASESS:` with non-empty value
- `prog_dir` contains `develbat`
- `db_name` matches environment (`remicsdev`)
- `s_user` matches test account

### Tier 2 — Browser E2E (implement second)

Primary regression suite for auth changes.

```
Playwright: login → wait for navigation shell → open shownetsession → expect(text)
Optional: screenshot on failure; trace for debugging
```

**Suggested location:** `tests/remicsdev/e2e/login-session.spec.ts`

**Also cover:**

- Logout via `logoff.aspx` → session cleared
- Failed login (throwaway wrong password) → no `FCSASESS`

### Tier 3 — Server-side corroboration (implement third)

Run after tier 1 or 2 succeeds (same test run):

```
Assert file exists: D:\MicsWebLogs\logins\<testuser>_conn.txt (modified within N minutes)
Assert directory:   D:\inetpub\remicsdev\mics\userdirs\<schema>\<testuser>\
Optional SQL:       FCSASESS value appears in expected logging table
```

**Suggested location:** `tests/remicsdev/smoke/assert-login-server.ps1`

### Tier 4 — Batch smoke (implement fourth)

Only after batch analysis identifies a **dev-safe, read-only or minimal** job.

Prerequisites:

- Documented safe entry point (e.g. specific `TwsTabUtil.asmx` method or maintenance page)
- Confirmed exe exists in `D:\develbat`
- Test account has SQL + filesystem permissions

Flow:

```
Login (tier 1 or 2) → trigger one batch action → poll web.dblogger or extractlogs → assert return code 0
```

**Limitation:** CI runner must reach remicsdev and test account must work with `LogonUser` / `principalw` path.

---

## Proposed repo layout (when implemented)

```
CentralProject/
  tests/
    remicsdev/
      smoke/
        login-session.http.ps1
        assert-shownetsession.ps1    # HTML parser / assertions
        assert-login-server.ps1      # tier 3
      e2e/
        login-session.spec.ts        # tier 2 Playwright
        playwright.config.ts
      fixtures/
        test-users.env.example       # gitignored real secrets
  docs/remicsdev/automated-testing.md  ← this file
```

---

## Runner and CI requirements

| Requirement | Reason |
|-------------|--------|
| Target **remicsdev** only (not prod) | Live AD + SQL |
| **Dedicated test MICS account** | Never use personal admin credentials in automation |
| Secrets outside repo | Key vault, GitHub Actions secrets, or local `.env` (gitignored) |
| Network access to `remicsdev.cloudmicsdev.ca` | Tests hit real IIS |
| **Windows agent** (for tier 4) | Batch impersonation path |
| Schedule: nightly + post-deploy | Avoid blocking every commit initially |

---

## Testability improvements (optional, later)

Highest ROI code changes (not required to start tiers 1–2):

- Dev-only JSON diagnostic endpoint instead of parsing `shownetsession` HTML
- IP-restrict `/Maintenance/*` or require admin role for diagnostic pages
- Stable `data-testid` attributes on login form (reduces Playwright fragility)

---

## What not to automate early

- Full menu/page crawl (1,000+ `.aspx` files)
- All batch programs (deploy gaps, long runtime, side effects)
- Linux-only CI without Windows/domain reach for tier 4

---

## Related

- [TODO](../TODO.md) — implementation tasks for tiers 1–4
- [login-flow.md](login-flow.md) — session keys to assert
- [web-app-structure.md](web-app-structure.md) — batch invocation (tier 4 prep)
