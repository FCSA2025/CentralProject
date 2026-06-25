# CentralProject — TODO

Tracked documentation, investigation, and implementation work. Update as items complete or priorities change.

**Last updated:** 2026-06-25

- [x] **Bill report-table SQL disabled** — `mOutputToReportsTable = false` + guards on `InsertFinalMD5allRunsandReports()` / `WriteRunReportToDbTable()`; deployed `TpRunTsip.exe` 2026-06-24 (jobs 139–140 verified)
- [x] **TSIP batch success popups removed** — `mics\Ttsipmenu\tsipBatch.aspx` (server only; status bar message instead of two alerts)

---

## TSIP run archive (implement later)

Full plan: **[remicsdev/tsip-implementation-plan.md](remicsdev/tsip-implementation-plan.md)**

Phase 0 fix (exit 666) + hybrid archive (`web.tsip_run`, normalized `tt_*`/`te_*`, report line cache). Test after each phase.

- [x] **Phase 0** — Storedef block removed; deployed `D:\develbat\TpRunTsip.exe` 2026-06-24 — verified **`rctl1` / `ecomm2602`**
- [x] **Phase 1** — DDL applied on remicsdev 2026-06-17: `web.tsip_run`, parm_ts/es, 10 arc_* tables, `tsip_run_report_line`, grants — see `docs/remicsdev/sql/tsip-archive/`
- [x] **Phase 2** — `TsipRunArchive.cs` + two-phase hook in `TpRunTsip.Main()`; verified remicsdev 2026-06-25
- [x] **Phase 3** — Report line cache in `TryArchiveAfterClose` (`web.tsip_run_report_line`); verified 2026-06-25
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
| High | [Source layout — where to edit code](remicsdev/source-layout.md) | **Complete** | Web vs batch; inetpub = web source; env copies |
| High | [Git/GitHub setup checklist](github-setup-checklist.md) | **Complete** | New-machine pre-flight; Credential Manager lessons |
| High | [TSIP implementation plan](remicsdev/tsip-implementation-plan.md) | **Active** | Phase 0 fix + archive Phases 1–5; test per phase |
| High | [TSIP tt tables & capture](remicsdev/tsip-tt-tables.md) | **Complete** | Lifecycle mapped; superseded by archive plan for capture strategy |
| High | [Batch programs](remicsdev/batch-programs.md) | **In progress** | First analysis pass done; open questions remain |
| Medium | [Environments & URLs](remicsdev/environments-and-urls.md) | **Complete** | IIS/DNS verified; prod not on this server |
| Medium | [Database access](remicsdev/database-access.md) | **Complete** | Invoke-RemicsDevSql.ps1; schema overview |
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
