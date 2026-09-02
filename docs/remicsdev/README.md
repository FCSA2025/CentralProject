# ReMICS Dev (remicsdev) documentation

Frequency Coordination System — development environment on IIS.

**Login URL:** http://remicsdev.cloudmicsdev.ca/mics/Tlogin.aspx

Machine-readable context: [`context/codebases/remicsdev.yaml`](../../context/codebases/remicsdev.yaml)

## Documentation index

| Doc | Status | Summary |
|-----|--------|---------|
| [Database access](database-access.md) | **Complete** | sqlcmd wrapper, schemas, read/write conventions |
| [Source layout — where to edit code](source-layout.md) | **Complete** | Web vs batch paths; inetpub = web source; env copies |
| [Environments & URLs](environments-and-urls.md) | **Complete** | IIS/DNS verified; prod URLs not on this server |
| [Web application structure](web-app-structure.md) | **Complete** | Folders, shared libs, batch invoke path, verification script |
| [Login flow & session model](login-flow.md) | **Complete** | Auth path, session keys — source + browser validated |
| [Test account & schema isolation](test-account-setup.md) | **Complete** | Auth→schema mapping; Phase A cleanup; Phase B `autotest1` |
| [AD-free auth Phase 0–1](ad-free-auth-phase01.md) | **Complete** | `t_UserDetails` prove + plaintext helper (no remicsdev login edits yet) |
| [KillTable delete bug (UseDbAuth)](killtable-delete-bug.md) | **Complete** | TS delete system error; `user_schema2022` + app-pool schema lookup |
| [KillTable hardening (idempotent drop + env)](killtable-hardening-fix.md) | **Complete** | `IF EXISTS` drops, `user_tables_view` repair, `JobSubmit` env pass-through |
| [RemIcsReWrite harness plan](remicsrewrite-harness-plan.md) | **Complete** | Frame-free login/TS/delete harness at `/mics/RemIcsReWrite/` |
| [RemIcsReWrite Phase 1](remicsrewrite-phase1.md) | **Complete** | Classic-looking TS tree/file ops; identical batch reports |
| [RemIcsReWrite Phase 2](remicsrewrite-phase2.md) | **Complete** | Database Update / Transfer to FCSA (exportForUpdate + email) |
| [Email contracts + kill switch](email-contracts.md) | **Active** | `DisableOutgoingEmail`; re-enable in **Phase 7** |
| [RemIcsReWrite Phase 3](remicsrewrite-phase3.md) | **Complete*** | TSIP parm list / validate / run / queue poll (*re-verify via Gate C roster, not rctl-only*) |
| [RemIcsReWrite Phase 3b](remicsrewrite-phase3b.md) | **Complete*** | Retrieve TSIP Batch Reports (*broken 2026-09-02 by incomplete `UserDirUtil` deploy; fixed + Gate C/F coverage*) |
| [RemIcsReWrite Phase 4](remicsrewrite-phase4.md) | **Complete** | ES Data Files parity + nav placeholders |
| [RemIcsReWrite Phase 5](remicsrewrite-phase5.md) | **Active** | Raw-IP host-aware Pref cookies + session diag |
| [RemIcsReWrite Phase 6](remicsrewrite-phase6.md) | **Active** | PCN Coordination (`Tpcnmenu` parity) |
| [RemIcsReWrite Phase 6.5](remicsrewrite-phase65.md) | Implemented | Data Search TS/ES + create masters + deeper edit / TSIP CRUD |
| [RemIcsReWrite Phase 6.75](remicsrewrite-phase675.md) | **Stabilized** | Visible-nav scope shipped; new features deferred — see [stabilization plan](remicsrewrite-stabilization-plan.md) Gates A–G |
| [RemIcsReWrite test matrix](remicsrewrite-test-matrix.md) | **Active** | Feature checklist + automation vs manual; feature smoke script |
| [RemIcsReWrite interior parity plan](remicsrewrite-interior-parity-plan.md) | **Abandoned** | Layout polish good enough — not active; see Path B in [stabilization plan](remicsrewrite-stabilization-plan.md) |
| [**RemIcsReWrite stabilization plan**](remicsrewrite-stabilization-plan.md) | **Active (Path B)** | Gates A–G passed; ops/regression mode — no interior polish, no feature expansion |
| [Path B bug-fix plan](path-b-bugfix-plan.md) | **Complete** | Waves 0–3 done (2026-09-02) |
| [user_tables reconcile](user-tables-reconcile.md) | **Active** | Nightly + on-demand catalog sync for TS/ES/TSIP parm |
| [Automated testing strategy](automated-testing.md) | **Complete** | Tiers 1–4 plan; manual test template passed |
| [Batch programs](batch-programs.md) | **In progress** | Source, build/deploy paths, web↔disk gaps |
| [Session 2026-06-29 — login & import fixes](session-2026-06-29-login-import-fixes.md) | **Complete** | 1314 GPO, LogonUser 1385 + gpupdate/secedit, ftPrint 1024-byte bug, import warning logging, all code changes |
| [Email draft — Bill (2026-06-29, code line numbers)](email-to-bill-2026-06-29-code-only.md) | **Complete** | Exact line numbers + old/new code (no server config) |
| [Email draft — Bill (2026-06-29, line-by-line)](email-to-bill-2026-06-29-line-edits.md) | **Complete** | Full find/replace edit guide including server config |
| [Email draft — Bill (2026-06-29, summary)](email-to-bill-2026-06-29.md) | **Complete** | Stakeholder handoff with GPO timeline and follow-ups |
| [Email draft — Bill (2026-07-29, AJAX P0–P2)](email-to-bill-2026-07-29-ajax-auth-fixes.md) | **Complete** | ES delete, export/import/copy RemIcsApi, TSIP, bulk print; P3 excluded |
| [Validate UseDbAuth + valType fix](validate-useDbAuth-fix.md) | **Complete** | `isedess23b` incident; `TFileOptions.js` + `JobSubmit` exit codes |
| [TSIP deep dive](tsip.md) | **Active** | Call contract (MICS + independent apps), logging tables/files, formulas |
| [MDB site fetch bug analysis](mdb-site-fetch-bug-analysis.md) | **Complete** | Si Ke `MtGetSiteWN2` review; ODBC cursor lifecycle findings |
| [MDB site fetch fix — Option A](mdb-site-fetch-fix-plan-option-a.md) | **Planned** | Minimal `MtClose*` / cursor cleanup (not implemented) |
| [Source vs binary drift check](source-vs-binary-drift-check.md) | **Planned** | Safe isolated rebuild to verify develbat matches source |
| [TSIP implementation plan](tsip-implementation-plan.md) | **Active** | Phase 0 fix + archive Phases 1–5; codebase notes |
| [TSIP tt tables lifecycle](tsip-tt-tables.md) | **Complete** | Working table reference (not the implementation plan) |
| Startup & configuration | Planned | `Global.asax`, full `Application[]` keys |

## Quick reference

| What | Where |
|------|-------|
| IIS site | `remicsdev` → `D:\inetpub\remicsdev` |
| MICS web app (IIS application `/mics`) | `D:\inetpub\remicsdev\mics` — **also the VS source tree** |
| Web solution | `D:\inetpub\remicsdev\mics\mics.sln` |
| Authoritative `web.config` | `D:\inetpub\remicsdev\mics\web.config` |
| CentralProject hub (docs only) | `E:\AIProjects\CentralProject` |
| Batch source | `D:\MicsBatchProgs` (`.cs` — no separate prod source tree) |
| Batch runtime (this site) | `D:\develbat` (`.exe` only) |
| Batch runtime (production) | `D:\prod\bin` (`.exe` only; promotion manual/inferred) |
| SQL Server | `EC2AMAZ-9DKDM82\REMICS_DEV` / database `remicsdev` |
| SQL helper script | `scripts/Invoke-RemicsDevSql.ps1` |
