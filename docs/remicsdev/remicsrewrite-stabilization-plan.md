# RemIcsReWrite — stabilization & reassessment plan

**Status:** Active (2026-09-02) — Gates A–G done; **Path B (ops/regression)** only — Paths A (interior) and C (feature expansion) abandoned for now  
**Supersedes for prioritization:** feature-expansion phases in [remicsrewrite-phase675.md](remicsrewrite-phase675.md) and [remicsrewrite-interior-parity-plan.md](remicsrewrite-interior-parity-plan.md)  
**Related:** [user-tables-reconcile.md](user-tables-reconcile.md), [remicsrewrite-test-matrix.md](remicsrewrite-test-matrix.md), [email-contracts.md](email-contracts.md), [gate-f-regression.md](gate-f-regression.md)

---

## Why this document exists

The original RemIcsReWrite program was framed as a **rewrite** but shipped as a **thin shell over legacy batch + ASMX**, with new JavaScript that reimplemented UX without the same invariants as classic MICS. That gap produced real production bugs (cross-company PDF selection, false Ready states, alert/focus traps, catalog drift, lookup JS corruption).

**This plan stopped feature parity work until stabilization gates passed.** Gates A–G are green. Active mode is **Path B** (ops/regression only). Interior polish (Path A) and feature expansion (Path C) are abandoned/paused.

---

## What went wrong (root causes)

| Pattern | Symptom | Example from 2026-08-31 |
|---------|---------|-------------------------|
| **Global catalog reads** | User sees or selects another company's files | TSIP `?` lookups / validate without `operator = s_schema` |
| **Catalog ≠ physical tables** | UI shows files that don't exist or hides real ones | `web.user_tables` orphans after CopyTable/KillTable partial failure |
| **Optimistic UI gates** | Buttons enabled when batch will fail immediately | TSIP "Ready" + Run with empty parm → exit **-2227** |
| **Alert + focus loops** | Unclosable dialogs | TSIP run form `onfocus` → alert → refocus |
| **JS bridge fragility** | Silent lookup death | `lookup-js.ashx` regex ate `<=` in classic JS |
| **False failure messaging** | User retries create → duplicate errors | CopyTable succeeded, dblogger update failed |
| **"Parity" without oracle** | Looks like classic, behaves differently | INFORMATION_SCHEMA lists vs `user_tables` for validation |
| **Telerik / frames dependency (classic)** | Rewrite still depends on classic ASMX, lookups, batch | Not a true rewrite — every shortcut must preserve classic contracts |
| **Single-account testing bias** | Fixes verified only for `rctl1` / one schema; other companies break in production | Harness, smoke scripts, and phase docs defaulted to `rctl1`; `bchy1` caught cross-company bugs only by accident |
| **Hardcoded test-account behavior** | One schema “passes” while code is wrong for everyone else | Any `rctl`/`bchy`/`dnd` literals, fixture names, or special-case output in rewrite paths (audit required) |
| **E2E that stops before the user menu** | Batch/email succeeds; Retrieve Reports / edit still 500 | Gate C covered parm→run→validate only; never called `tsip-reps-*.ashx` |
| **Incomplete `Assembly Src` helpers** | New shared `.cs` compiles in one ashx, 500s in another | `UserDirUtil` added without `<%@ Assembly Src=... %>` / was `internal` across ashx assemblies |
| **Regression smoke too thin** | Nightly green while a primary nav surface is dead | Gate F HTTP only checked `tsipValidate` foreign PDF |

The old phase docs treated **backend parity** and **layout parity** as separate checkboxes but did not require **security/isolation invariants**, **catalog consistency**, or **multi-company verification** as release gates.

---

## Lessons learned (2026-09-02)

**Incident:** After `UserDirUtil` (case-insensitive `mics_user` for archive dirs), Al (bchy) got TSIP emails but **Retrieve TSIP Reports** failed and parm edit appeared broken. Root causes: missing `Assembly Src`, `internal` class, then nested ODBC readers once archive rows matched.

| Gate | Should have caught it? | Why it missed |
|------|------------------------|---------------|
| **C** (primary) | Yes | E2E stopped before reports tree / edit load-save |
| **F** (safety net) | Yes | HTTP smoke was validate-isolation only |
| **G** | Partially | Multi-company feature coverage not closed yet |
| A / B / D / E | No | Different failure classes |

**Rules going forward:**

1. **TSIP E2E includes post-run UX** — reports root/expand/open and edit-run load/save on the roster, not only create→validate→delete.
2. **Gate F HTTP covers primary TSIP surfaces** — at least `tsip-reps-tree` root `ok=true` per roster user (compile/runtime death must fail the job).
3. **Shared ashx helpers** — follow `casedet.ashx`: `public` types + `<%@ Assembly Src="Helper.cs" %>` on every consumer; smoke those ashx after deploy.
4. **Do not treat “email arrived” as “reports menu works.”**
5. **Case-folding / archive matching** — exercise expand-parm when archive rows exist (latent nested-reader class of bug).

---

## Stabilization gates (must pass before new features)

### Gate A — Company isolation (P0)

Every path that lists or validates TS/ES/TSIP PDFs must filter by `Session['s_schema']` / `operator`.

**Audit targets:**

- [x] All `lookuptsip/luTsip*.aspx.cs` (PDF list, env file name) — `operator` filter in source + IIS
See [classic-gate-a-sources.md](classic-gate-a-sources.md) for versioned classic ASMX/pages (`TwsTsip.asmx.cs`, `copy.aspx.cs`).

- [x] `Ttsipmenu/TwsTsip.asmx.cs` — `tsipValidate`, `tsipValidateAll` + `AppendPdfCatalogCheck` (**tracked in repo**)
- [x] `Tfileactions/copy.aspx.cs` — `operator` filter on dup check (**tracked in repo**)
- [x] Rewrite bridges: `files.ashx` (schema-scoped INFORMATION_SCHEMA), `tsip-run.ashx` save validation (catalog-only `user_tables_view`)
- [x] Post Analysis / CASEDET / Aux Eng file pickers — `casedet.ashx` schema-scoped run list; Aux Eng uses `files.ashx` lists + `aux-coord.ashx` / `aux-hilo.ashx` schema checks (`Invoke-GateATailIsolationTest.ps1`)
- [x] Data Search save pickers — `populatePdfSelect` → `files.ashx` (schema-scoped); search queries `main.mt_*` / `main.me_*` master tables by design

**Verified 2026-09-01:** `Invoke-GateAIsolationTest.ps1` PASS for `bchy1`, `rctl1`, `xci1` (foreign PDF rejected on validate + save; own PDF validates).

**Verified 2026-09-01:** `Invoke-GateATailIsolationTest.ps1` PASS for `bchy1`, `rctl1`, `xci1` (file lists, CASEDET list, aux-coord, aux-hilo reject foreign PDF).

### Gate B — Catalog integrity (P0)

`web.user_tables` must match physical marker tables for types **0 / 5 / 417**.

**Done (infra):**

- [x] `web.ReconcileUserTables` proc
- [x] Nightly SQL Agent job **User Tables Reconcile** (02:30)
- [x] On-demand: `Invoke-RemicsUserTablesReconcile.ps1`

**Remaining:**

- [x] Extend reconcile scope documented — types **300+** explicitly excluded ([user-tables-reconcile.md](user-tables-reconcile.md))
- [x] After KillTable/CopyTable/createTable errors — `reconcile.ashx` + auto-reconcile in `remics-api.js` / `remics-ts.js`
- [x] Rewrite create/delete paths distinguish physical vs catalog (`files.ashx` `catalogExists` / `catalogDrift`; create pre-check + repair)

**Verified 2026-09-01:** `Invoke-GateBCatalogTest.ps1` — drift query zero after live reconcile; HTTP `reconcile.ashx` + `files.ashx` catalog flags.

### Gate C — TSIP run safety (P0)

- [x] Empty parm files show **No runs**, not Ready; Run disabled
- [x] New parm → New run flow
- [x] Env file cross-company check (PDF envname must be own-operator when `envtype` is `PDF_*`) — `tsipValidateAll` + `tsip-run.ashx` save
- [x] Save-run server validation mirrors `tsipValidateAll` (catalog-only `user_tables_view` in `tsip-run.ashx`)
- [x] End-to-end TSIP path passes on **each schema in the test roster** — `Invoke-GateCTsipE2ETest.ps1` (default: bchy1, rctl1, xci1)
- [x] **TSIP onboarding UX (2026-09-01):** 3-step workflow strip, empty-state CTAs, button renames, run-form banner + field hints, badge legend, welcome quick start — `Invoke-TsipUxSmokeTest.ps1`
- [x] **Post-run usability (2026-09-02 lesson):** Retrieve Reports + edit-run — `Invoke-GateCTsipRepsEditTest.ps1` on roster (`tsip-reps-tree` root/expand, `tsip-reps-open`, `tsip-reps-meta`, parm edit load/save). Closing Gate C requires **both** E2E and reps/edit scripts.

### Gate D — Lookup & form UX (P1)

- [x] `lookup-js.ashx` tag strip safe for `<=`
- [x] Inventory every rewrite `?` lookup type — smoke test after hard refresh (`Invoke-GateDLookupSmokeTest.ps1`)
- [x] Remove remaining alert+focus traps in `remics-ts.js`, ES flows, import wizards
- [x] Cache-bust policy for `lookup1.aspx` / lookup JS (document in test matrix)

### Gate E — Create/delete honesty (P1)

- [x] TsipParm create: pre-check + post-tree verify + friendly "already exists"
- [x] TS/ES create/delete same pattern in `remics-ts.js`
- [x] KillTable failure → suggest reconcile + refresh, not raw CopyTable text

### Gate F — Automated regression (P1)

Nightly **SQL Agent job** `RemIcs Gate F Regression` (03:15 local) emails FCSA team on failure. See [gate-f-regression.md](gate-f-regression.md).

- [x] SQL check: zero cross-company parm runs (`web.RunGateFRegression`)
- [x] HTTP smoke: TSIP validate returns `not found` for foreign PDF — per schema in roster (job step 2 / `Invoke-GateFRegressionTest.ps1`)
- [x] Nightly reconcile run row in `web.user_tables_reconcile_run` (staleness check in `web.RunGateFRegression`)
- [x] **HTTP smoke (2026-09-02 lesson):** `tsip-reps-tree.ashx` root returns `ok=true` per roster user (catches missing `Assembly Src` / compile 500s). Job step 2 already points at `Invoke-GateFRegressionTest.ps1` (no redeploy needed for script body).

### Gate G — Multi-company coverage (P0)

**No gate closes on a single MICS user or schema.** Passing as `rctl1` alone is necessary for dev convenience; it is **not** sufficient for stabilization sign-off.

- [x] Feature smoke / manual gates run with **≥3 schemas** from the roster (rotate default user each run) — verified 2026-09-02: `bchy1`, `rctl1`, `xci1` via schema-owned TS PDF pick (no hardcoded `bbimport2`)
- [x] Gate C E2E **and** Gate C reps/edit green on the same roster (`Invoke-GateCTsipE2ETest.ps1` + `Invoke-GateCTsipRepsEditTest.ps1`)
- [x] No hardcoded schema, operator, or MICS user in RemIcsReWrite **product** paths (grep audit; test-only scripts excluded)
- [x] No special-case output, fallback lists, or “works for rctl” branches in rewrite handlers
- [x] Pinned fixtures (`cmxts01`, `ecomm2602`, etc.) used only as **data** inside each login’s own schema — not as substitutes for other companies’ files
- [x] New fixes include a note: *which schemas were exercised* (not only “works on rctl1”)
- [x] Shared ashx helpers audited: every consumer has `Assembly Src`; helper types are `public` (`UserDirUtil`, `CaseDetCsv`, `CaseDetKml`)

**Justified product hardcode (classic parity):** `js/remics-nav.js` `FCSA_INTERNAL_USERS` list mirrors classic `TnavigationLeft.aspx` for `fcsaOnly` nav items — not a schema filter for file/catalog paths.

---

## Multi-company test policy

RemIcsReWrite must work for **every** logged-in company (`Session['s_schema']`). Testing culture that centered on **rctl** (and occasionally **dnd** / **xci**) allowed cross-schema catalog leaks, wrong lookups, and hardcoded behavior to ship.

### Test roster (minimum)

Use **at least three** of these per stabilization gate; rotate so no one account dominates:

| Schema | Example login | Role in matrix |
|--------|---------------|----------------|
| `rctl` | `rctl1` | Historical dev default — **not** the only gate |
| `bchy` | `bchy1` | Recently onboarded; caught cross-company TSIP bugs |
| `dnd` | `dnd1` | Seq10 / fixture workflows |
| `xci` | `xci1` | Second major operator |
| `venn` | `venn1` | Different data shape / TSIP history |

Add others from `adm.account_details` when touching a feature known to vary by operator (e.g. `hulme`, `frse`, `fmda2`).

### Anti-patterns (explicitly forbidden)

1. **“Green on rctl1” = done** — close gates only when the roster passes.
2. **Hardcoded schema/user in rewrite code** — all paths use `Session['s_schema']` / `Session['s_user']` (or ASMX session), never literal `rctl`/`bchy` except in comments or test harness config.
3. **Fixture names presented as real files for other companies** — e.g. showing `ecomm2602` in a picker for `bchy1` because it exists under `rctl`.
4. **Single-user smoke as release criteria** — [`Invoke-RemicsReWriteFeatureSmoke.ps1`](../../scripts/Invoke-RemicsReWriteFeatureSmoke.ps1) accepts `-User`; CI/manual runs must rotate accounts (document in test matrix).
5. **Docs that say “As rctl1…” without “repeat as bchy1 / xci1”** — scrubbed in phase1–675 / harness / interior (2026-09-02); keep roster language on further edits.

### Audit command (hardcoding)

```powershell
# Product code — expect zero matches in handlers/JS (review any hit)
rg -n "rctl1|bchy1|dnd1|'rctl'|\"rctl\"|schema\s*=\s*'rctl" `
  config/remicsdev/source/mics/RemIcsReWrite `
  --glob "!*test*" --glob "!*.md"
```

---

## Work phases (execution order)

### Phase S0 — Ops & notifications (done 2026-09-01)

- [x] Error queue team mail: replace `mlimpin@fcsa.ca` → `alejandro.moreno@sympatico.ca` in [email-queue-local-agent-job.sql](email-queue-local-agent-job.sql); redeploy **Email Queue Local**
- [x] Document [user-tables-reconcile.md](user-tables-reconcile.md)

### Phase S1 — Isolation audit & fixes (done 2026-09-01)

1. [x] Grep all `user_tables` / `user_tables_view` queries in `config/remicsdev/source/mics` and `D:\inetpub\remicsdev\mics`
2. [x] Fix any missing `operator` filter; mirror to IIS
3. [x] Add envname cross-company rule to TSIP save/validate
4. [x] Re-run cross-company parm scan (should stay at 0)

### Phase S2 — Catalog & file lifecycle (done 2026-09-01)

1. [x] TS/ES create/delete UX parity with TsipParm fixes
2. [x] Optional: post-error reconcile hook from rewrite on CopyTable/KillTable ambiguous failure (`reconcile.ashx` + auto in remics-api/ts)
3. [x] Review `files.ashx` vs catalog for list/validate consistency

### Phase S3 — TSIP & lookups hardening (done 2026-09-02)

1. [x] Full lookup smoke matrix (all `Tsip*` types in `lookuptsip.js`) — **each schema in roster**
2. [x] Server-side run save validation
3. [x] End-to-end per roster schema: own TS only → parm → run
4. [x] **Add:** reports retrieve + edit-run multi-user (`Invoke-GateCTsipRepsEditTest.ps1`); fold reports root into Gate F HTTP

### Phase S3.5 — Coverage hardening from 2026-09-02 incident (done 2026-09-02)

1. [x] Promote reps/edit script into Gate C closing criteria (`Invoke-GateCTsipRepsEditTest.ps1`)
2. [x] Extend Gate F HTTP with `tsip-reps-tree` root; job already invokes the script file
3. [x] Close **Gate G** (hardcoding audit + roster feature smoke + Assembly Src audit)
4. Start **S4** product fork (Path B selected 2026-09-02)

### Phase S4 — Rewrite program reassessment (product) — **Path B selected**

**Honest scope statement going forward:**

| Claim | Reality |
|-------|---------|
| "Rewrite" | **Shell + routing** over existing batch/ASMX — not new domain layer |
| "No Telerik" | Correct for rewrite UI; classic Telerik trees still authoritative for some flows |
| "Parity" | Must mean **same bytes + same authorization boundaries for every operator**, not similar HTML on one test account |
| "Tested" | Means **multi-company roster green**, not “rctl1 smoke passed” |

**Product fork (2026-09-02):**

| Path | Meaning | Decision |
|------|---------|----------|
| **A — Interior parity (IP-\*)** | Layout/UX polish vs classic | **Abandoned** — good enough; [interior plan](remicsrewrite-interior-parity-plan.md) archived |
| **B — Ops / regression** | Keep gates green; fix user-reported breaks | **Active** — see below |
| **C — Feature expansion** | Phase 7 email, hidden nav, new rewrite SQL | **Paused** — reopen only explicitly |

**Decisions (adopted 2026-09-02 — Gates A–G green on roster `bchy1` / `rctl1` / `xci1`):**

1. **Stop** calling incomplete areas "Ready" in docs/README until Gates A–C **and G** pass for that area on the roster.
2. **Prefer** classic `lu*.aspx` backends for lookups (already exist) — rewrite only hosts iframe/JS bridge; do not re-query catalog in JS without schema.
3. **Do not** add new rewrite-owned SQL for file lists; use `user_tables_view` + operator or existing ASMX.
4. **Interior parity (IP-\*) abandoned** — do not schedule IP work unless product explicitly reopens Path A.
5. **Telerik retirement** remains a separate program — rewrite is step 1 (frames out), not Telerik removal.
6. **Retire rctl-centric planning** — legacy phase docs scrubbed 2026-09-02; keep roster language on further edits.
7. **Hardcoding audit** — before closing any gate, run the [audit command](#multi-company-test-policy) and fix or justify every hit in product code.
8. **TSIP “done” includes reports + edit** — Gate C closes only with E2E **and** `Invoke-GateCTsipRepsEditTest.ps1`; Gate F HTTP includes `tsip-reps-tree` root.
9. **Phase 7 / hidden nav / new features stay off** until Path C is explicitly reopened.

Deliverable (done 2026-09-02): [README.md](README.md) + phase1–675 / harness / interior docs updated for roster wording and Path B.

---

## Path B — what remains (active)

Stabilization is **maintenance mode**. No polish backlog, no Phase 7, no new surfaces. Work is only:

| Work | How |
|------|-----|
| **Nightly Gate F** | SQL Agent job at 03:15; triage FCSA alert email on failure (`Invoke-GateFRegressionTest.ps1` / [gate-f-regression.md](gate-f-regression.md)) |
| **Catalog reconcile** | Nightly **User Tables Reconcile** at 02:30; on-demand after messy create/delete |
| **User-reported regressions** | Diagnose → fix → verify on **roster** (not rctl-only); note schemas exercised |
| **Post-fix smoke** | Rotate `Invoke-RemicsReWriteFeatureSmoke.ps1 -User …`; for TSIP use Gate C E2E + reps/edit |
| **Deploy discipline** | Shared ashx helpers: `public` + `Assembly Src` on every consumer; smoke those ashx after deploy |
| **Doc/process hygiene** | Keep this plan + gate scripts truthful; no new feature docs until Path C |

**Not in Path B:** IP-* layout work · Phase 7 email re-enable · hidden-nav Reports/FCC/ISED · new rewrite-owned SQL · Telerik removal.

**Active bug-fix backlog:** [path-b-bugfix-plan.md](path-b-bugfix-plan.md) (Waves 0–3 complete).

**Exit Path B only when product explicitly chooses Path A or Path C again.**

---

## Daily checklist (remicsdev)

```powershell
# Gate F nightly regression (manual; job runs at 03:15) — includes tsip-reps-tree root
.\scripts\Invoke-GateFRegressionTest.ps1

# Gate C — both required
.\scripts\Invoke-GateCTsipE2ETest.ps1
.\scripts\Invoke-GateCTsipRepsEditTest.ps1

# Cross-company parms (expect 0) — global, not per-user
.\scripts\Invoke-RemicsDevSql.ps1 -ReadOnly -Query "EXEC web.RunGateFRegression @SendEmail=0, @FailJobOnIssues=0"

# Last reconcile
.\scripts\Invoke-RemicsDevSql.ps1 -ReadOnly -Query "SELECT TOP 5 * FROM web.user_tables_reconcile_run ORDER BY run_id DESC"

# Feature smoke — rotate user each run (do not use rctl1 exclusively); auto-picks company TS PDF
.\scripts\Invoke-RemicsReWriteFeatureSmoke.ps1 -User bchy1 -BaseUrl 'http://remicsdev.cloudmicsdev.ca/mics/'
# next run: -User xci1, then dnd1, etc.
```

---

## References (bugs fixed 2026-08-31 / 2026-09-02)

- Cross-company TSIP parm cleanup (`docs/remicsdev/sql/delete-cross-company-parms.sql`; 9 files removed 2026-09-01)
- TSIP UX: `remics-tsip.js`, `remics-tsip-run-form.js`, `tsip-parm.html`, `tsip-batch.html`
- Lookup: `lookup-js.ashx`, `lookup1.aspx`, `luTsipPdfList.aspx.cs`, `luTsipEnvFileName.aspx.cs`
- Catalog: `web.ReconcileUserTables`, Agent job **User Tables Reconcile**
- Reports/edit (2026-09-02): `UserDirUtil.cs` + `Assembly Src` on `tsip-reps-*.ashx`; nested ODBC fix in `tsip-reps-tree.ashx`; Gate C reps/edit + Gate F reports root; feature smoke schema-owned TS PDF
