# CentralProject — TODO

Tracked documentation, investigation, and implementation work. Update as items complete or priorities change.

**Last updated:** 2026-07-09

- [x] **Bill report-table SQL disabled** — `mOutputToReportsTable = false` + guards on `InsertFinalMD5allRunsandReports()` / `WriteRunReportToDbTable()`; deployed `TpRunTsip.exe` 2026-06-24 (jobs 139–140 verified)
- [x] **TSIP batch success popups removed** — `mics\Ttsipmenu\tsipBatch.aspx` (server only; status bar message instead of two alerts)
- [x] **TS import spawn (1314) + login + export truncate** — Resolved 2026-06-29: GPO **MICS IIS Server Rights** for `IISReMicsSer`; local Domain Users logon rights on IIS (temporary — reverted by `gpupdate` once); `Tlogin.aspx.cs` / `TloginValidate.aspx.cs`; `ftPrint.exe` flush/close fix. See [session-2026-06-29-login-import-fixes.md](remicsdev/session-2026-06-29-login-import-fixes.md).
- [x] **Import warning popups → log-only** — `TwsTabUtil.asmx.cs` + `import.aspx`; warnings archived under `D:\MicsWebLogs\imports\` (deployed server-side 2026-06-29).
- [ ] **GPO: Domain Users logon rights on IIS** — Add `CLOUDMICSDEV\Domain Users` to Allow log on locally + Log on as a batch job in **MICS IIS Server Rights** (IIS-scoped); local `secedit` alone is overwritten by `gpupdate`.
- [ ] **Batch web test suite** — Full web path: login → ASMX (`exportTable`, `importTable`, `valFile`, `tsipRun`) → archive baselines on pinned `cat` / `ecomm2602`. See [automated-testing.md](remicsdev/automated-testing.md), [test-fixtures-and-baselines.md](remicsdev/test-fixtures-and-baselines.md), [test-account-setup.md](remicsdev/test-account-setup.md).

---

## FCSA.ca static site migration (Phases 1–4 deployed)

Full plan: **[fcsa/fcsa-migration-plan.md](fcsa/fcsa-migration-plan.md)**  
MICS auth (later): **[fcsa/fcsa-mics-auth-integration.md](fcsa/fcsa-mics-auth-integration.md)**

WordPress at `fcsa.ca` **stays live** — no external DNS to this server in this plan. New static site served at **`http://<server-ip>/`** (IP default on port 80). Repo: **CentralProject** `sites/fcsa/`. **HTTP only** — SSL deferred below.

| Phase | Task | Status |
|-------|------|--------|
| **1** | WP REST inventory + mirror EN/FR; `assets-manifest.csv` | **Complete** |
| **2** | Modernize static HTML/CSS; all images; FR as-is | **Complete** |
| **3** | IIS `fcsa` site + `fcsaapp` pool; `*:80:` binding; `D:\inetpub\fcsa\` | **Complete** |
| **4** | QA — self-review on EC2 (`localhost` / server IP) | **Ready for testing** |
| **5** | MICS at hostname + auth (needs DNS later) | **Deferred** |

- [ ] **FCSA HTTPS / TLS** — certificate + bindings when ready (out of scope for static HTTP MVP)
- [ ] **FCSA DNS cutover** — point `fcsa.ca` to this server when stakeholders ready (out of scope; WordPress remains until then)
- [ ] **FCSA external testers** — open static site on server IP to users outside EC2 / beyond local review (out of scope for migration Phases 1–4)

## TSIP run archive (implement later)

Full plan: **[remicsdev/tsip-implementation-plan.md](remicsdev/tsip-implementation-plan.md)**

Phase 0 fix (exit 666) + hybrid archive (`web.tsip_run`, normalized `tt_*`/`te_*`, report line cache). Test after each phase.

- [x] **Phase 0** — Storedef block removed; deployed `D:\develbat\TpRunTsip.exe` 2026-06-24 — verified **`rctl1` / `ecomm2602`**
- [x] **Phase 1** — DDL applied on remicsdev 2026-06-17: `web.tsip_run`, parm_ts/es, 10 arc_* tables, `tsip_run_report_line`, grants — see `docs/remicsdev/sql/tsip-archive/`
- [x] **Phase 2** — `TsipRunArchive.cs` + two-phase hook in `TpRunTsip.Main()`; verified remicsdev 2026-06-25
- [x] **Phase 3** — Report line cache in `TryArchiveAfterClose` (`web.tsip_run_report_line`); verified 2026-06-25
- [ ] **Phase 4** — Web UI: users **read, print, and email** TSIP results from archived DB storage (`run_id` list/search; reassemble `tsip_run_report_line` for download/print; email attachments from cache; optional Layer 2 views). Query reference: [tsip-archive-queries.md](remicsdev/tsip-archive-queries.md)
- [ ] **Phase 5** — (Optional) Archive-aware `Tstsrp*` formatters for regen from Layer 2

---

## Disk write reduction (staged)

Full inventory: **[remicsdev/disk-writes-inventory.md](remicsdev/disk-writes-inventory.md)**  
Staged plan: **[remicsdev/disk-write-reduction-plan.md](remicsdev/disk-write-reduction-plan.md)**

Classify and eliminate unnecessary disk writes in stages. Some external apps rely on physical files — do not disable regulatory/import paths without dependency review.

- [ ] **Stage 1 — Disable debug/extractlogs bulk writes** — Comment out or gate off extractlogs/perflogs debug `StreamWriter`/`AppendAllText` in web + batch (priority: BuildSiteTables, JobSubmit submit5, TwsTsip trace, KmlUtils debug, SesUtils email debug, batch Log2/WriteToTsipLog). Smoke: login + one TSIP run on remicsdev.
- [ ] **Stage 2 — Ops audit review** — Decide which perflogs/MicsWebLogs files to keep vs move to SQL; disable remainder (keep bad-login + ErrorLog.txt).
- [ ] **Stage 3 — TSIP deliverables** — Blocked on TSIP archive Phase 4: read/print/email from `web.tsip_run_report_line`; then stop CopyToTxt and optional report file writes.
- [ ] **Stage 4 — Other user deliverables** — KML, PCN, JobSubmit stdout — per-feature design before disable.
- [ ] **Stage 5 — Regulatory / import-export** — Inventory external batch dependencies (COMS, ISED, FCC) before any comment-out.

---

First pass: **[remicsdev/batch-programs.md](remicsdev/batch-programs.md)**

- [ ] Pick tier 4 smoke candidate — `CheckMicsConfig` vs read-only TSIP skim?
- [ ] TSIP: confirm `MICSH` vs `MicsBat` authority; document `GetBinPath` override lifecycle
- [ ] Confirm how `D:\prod\bin` is populated
- [ ] Clarify `MICSH` vs `MicsBat` authority
- [ ] Build/deploy `SQLtoFlat` to develbat if still needed

---

## Automated testing — batch web test suite

Strategy: [remicsdev/automated-testing.md](remicsdev/automated-testing.md)  
Fixtures/baselines: [test-fixtures-and-baselines.md](remicsdev/test-fixtures-and-baselines.md)  
Test account: [test-account-setup.md](remicsdev/test-account-setup.md)  
Manual template **passed** on remicsdev (2026-06-17). TSIP CLI smoke **passed** 2026-06-30 (`ecomm2602`, run_id 6).

**Goal:** Full web path — login → four batch programs via ASMX → L0–L4 assertions with archive baselines on pinned tables.

| Phase | Task | Status | Deliverable |
|-------|------|--------|-------------|
| **1** | Playwright login + L0; `secrets.env.example`; `valFile` smoke | **Not started** | `tests/remicsdev/e2e/batch-smoke.spec.ts`, `lib/Login-MicsSession.ps1` |
| **2** | Print/import/validate round-trip on `cat` | **Not started** | `lib/Invoke-MicsAsmx.ps1`, `lib/Wait-DbLoggerJob.ps1` |
| **3** | TSIP web + archive L3 vs `baselines.yaml` | **Not started** | `lib/Compare-TsipRunArchive.ps1`, `fixtures/baselines.yaml` |
| **4** | Drift triage (WARN_DRIFT vs FAIL); second TSIP fixture | **Not started** | `lib/Test-ResultReporter.ps1`, `scripts/Update-RemicsDevTestBaselines.ps1` |
| **5** | `autotest1` account + prod baselines | **Not started** | `baselines-autotest1.yaml`, [test-account-setup.md](remicsdev/test-account-setup.md) |
| — | Orchestrator | **Not started** | `tests/remicsdev/smoke/run-all-smoke.ps1` |

---

## Documentation backlog

### fcsa.ca (public website)

| Priority | Item | Status | Notes |
|----------|------|--------|-------|
| High | [Migration plan Phases 1–4](fcsa/fcsa-migration-plan.md) | **Deployed** | Static HTTP on server IP; DNS/SSL out of scope |
| High | [MICS auth integration Phase 5](fcsa/fcsa-mics-auth-integration.md) | **Planned** | `fcsa.ca/mics`; cookie vs session; single login |
| Medium | [FCSA doc index](fcsa/README.md) | **Complete** | Quick reference |

### remicsdev (MICS)

| Priority | Item | Status | Notes |
|----------|------|--------|-------|
| High | [Source layout — where to edit code](remicsdev/source-layout.md) | **Complete** | Web vs batch; inetpub = web source; env copies |
| High | [Git/GitHub setup checklist](github-setup-checklist.md) | **Complete** | New-machine pre-flight; Credential Manager lessons |
| High | [TSIP archive queries](remicsdev/tsip-archive-queries.md) | **Complete** | SQL reference for inspecting `web.tsip_run` and related tables |
| High | [TSIP implementation plan](remicsdev/tsip-implementation-plan.md) | **Active** | Phase 0 fix + archive Phases 1–5; test per phase |
| High | [TSIP tt tables & capture](remicsdev/tsip-tt-tables.md) | **Complete** | Lifecycle mapped; superseded by archive plan for capture strategy |
| High | [Batch programs](remicsdev/batch-programs.md) | **In progress** | First analysis pass done; open questions remain |
| Medium | [Environments & URLs](remicsdev/environments-and-urls.md) | **Complete** | IIS/DNS verified; prod not on this server |
| Medium | [Database access](remicsdev/database-access.md) | **Complete** | Invoke-RemicsDevSql.ps1; schema overview |
| Medium | [Disk writes inventory](remicsdev/disk-writes-inventory.md) | **Complete** | Classified by purpose; stage column for reduction |
| Medium | [Disk write reduction plan](remicsdev/disk-write-reduction-plan.md) | **Active** | Stages 1–5; Stage 1 = next implementation step |
| High | [TS file import flow](remicsdev/ts-file-import-flow.md) | **Active** | End-to-end chain; remicsdev 1314 spawn failure documented 2026-06-26 |
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
- [ ] FCSA Phase 5 — `fcsa.ca/mics` child app, `machineKey`, Forms `path="/"` — see [fcsa-mics-auth-integration.md](fcsa/fcsa-mics-auth-integration.md)

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
