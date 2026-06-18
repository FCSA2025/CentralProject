# CentralProject — TODO

Tracked documentation, investigation, and implementation work. Update as items complete or priorities change.

**Last updated:** 2026-06-17

---

## TSIP run archive (implement later)

Full plan: **[remicsdev/tsip-archive-plan.md](remicsdev/tsip-archive-plan.md)**

Hybrid storage: central `web.tsip_run` registry + normalized `tt_*`/`te_*` archive (14 tables) + report file line cache. Single `TsipRunArchive.ArchiveRun()` hook in `TpRunTsip.Main()` before `KillTable(cUnique)`.

- [ ] **Phase 1** — DDL: `web.tsip_run`, parm_ts/es, 10 arc_* tables, `tsip_run_report_line`
- [ ] **Phase 2** — `TsipRunArchive.cs` + hook in `TpRunTsip.Main()`
- [ ] **Phase 3** — Report file cache from `TsipReportHelper` paths
- [ ] **Phase 4** — Web: run list, file download, custom reports by `run_id`
- [ ] **Phase 5** — (Optional) Archive-aware `Tstsrp*` formatters for regen from Layer 2

---

First pass: **[remicsdev/batch-programs.md](remicsdev/batch-programs.md)**

- [ ] Pick tier 4 smoke candidate — `CheckMicsConfig` vs read-only TSIP skim?
- [ ] TSIP: confirm `MICSH` vs `MicsBat` authority; document `GetBinPath` override lifecycle
- [ ] Confirm how `D:\prod\bin` is populated
- [ ] Clarify `MICSH` vs `MicsBat` authority
- [ ] Build/deploy `SQLtoFlat` to develbat if still needed

---

## Automated testing — implement tiers 1–4

Strategy doc: [remicsdev/automated-testing.md](remicsdev/automated-testing.md)  
Manual template **passed** on remicsdev (2026-06-17).

| Tier | Task | Status | Deliverable |
|------|------|--------|-------------|
| **1** | HTTP smoke — login POST, cookie jar, `shownetsession` assertions | **Not started** | `tests/remicsdev/smoke/login-session.http.ps1` |
| **1** | HTML parser / session field assertions | **Not started** | `tests/remicsdev/smoke/assert-shownetsession.ps1` |
| **2** | Playwright E2E — login, navigation shell, `shownetsession` | **Not started** | `tests/remicsdev/e2e/login-session.spec.ts` |
| **2** | Logout / failed-login cases | **Not started** | Additional e2e specs |
| **3** | Server-side corroboration — login log, `userdirs` | **Not started** | `tests/remicsdev/smoke/assert-login-server.ps1` |
| **4** | Batch smoke — one safe job after login | **Blocked** | Needs tier 4 candidate from batch-programs.md |
| — | Test credentials / secrets template (gitignored) | **Not started** | `tests/remicsdev/fixtures/test-users.env.example` |
| — | CI runner notes (Windows agent, remicsdev only) | **Not started** | Section in automated-testing.md or `tests/README.md` |

---

## Documentation backlog

### remicsdev (MICS)

| Priority | Item | Status | Notes |
|----------|------|--------|-------|
| High | [TSIP run archive plan](remicsdev/tsip-archive-plan.md) | **Planned** | 14-table hybrid storage; implement Phases 1–5 when ready |
| High | [TSIP tt tables & capture](remicsdev/tsip-tt-tables.md) | **Complete** | Lifecycle mapped; superseded by archive plan for capture strategy |
| High | [Batch programs](remicsdev/batch-programs.md) | **In progress** | First analysis pass done; open questions remain |
| Medium | [TSIP deep dive](remicsdev/tsip.md) | **In progress** | Formulas, I/O; see tt-tables doc for persistence |
| Medium | Startup & configuration | Not started | Full `Application[]` reference, `Global.asax` |
| Medium | Database layer | Not started | ODBC vs SqlClient, schemas, `dbconnect` |
| Low | Site-root sibling URL map | Not started | COMS, SQLtoFlat, etc. |

### Cross-cutting

| Item | Status |
|------|--------|
| Register next codebase in `context/codebases/` | Waiting on user |
| Auth migration planning doc | **Unblocked** — login/session doc complete |

---

## Auth change preparation (future work)

When authentication is redesigned, these are **known dependencies** on today's session model:

- [ ] Map every consumer of `Session["principalw"]` and `Session["principald"]`
- [ ] Map every consumer of `Session["s_password"]`
- [ ] Replace or preserve `FCSASESS`
- [ ] Decide fate of Forms Auth cookie `.ADAuthCookie` vs `PrefUID` / `PrefTime` / `PrefHelp`
- [ ] InProc session state — scaling / sticky session implications
- [ ] AD Membership provider vs `LogonUser` Win32 path

See [login-flow.md](remicsdev/login-flow.md).

---

## Verification scripts (existing)

| Script | Purpose |
|--------|---------|
| [scripts/verify-batch-mapping.ps1](../scripts/verify-batch-mapping.ps1) | Code batch name → `D:\develbat` file |
| [scripts/compare-batch-bins.ps1](../scripts/compare-batch-bins.ps1) | Exe presence: develbat / devel/bin / prod/bin / _bin |

---

## Completed

- [x] Infrastructure mapping — `docs/remicsdev/infrastructure-mapping.md`
- [x] Web application structure — `docs/remicsdev/web-app-structure.md`
- [x] Login flow & session model — `docs/remicsdev/login-flow.md` (source + browser validated)
- [x] Automated testing strategy — `docs/remicsdev/automated-testing.md`
- [x] IIS permissions test (GPO fix)
- [x] Authoritative `web.config` location (`mics\web.config`)
- [x] Batch programs — first pass `docs/remicsdev/batch-programs.md`
