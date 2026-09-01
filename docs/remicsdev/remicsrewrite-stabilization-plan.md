# RemIcsReWrite — stabilization & reassessment plan

**Status:** Active (2026-09-01)  
**Supersedes for prioritization:** feature-expansion phases in [remicsrewrite-phase675.md](remicsrewrite-phase675.md) and [remicsrewrite-interior-parity-plan.md](remicsrewrite-interior-parity-plan.md)  
**Related:** [user-tables-reconcile.md](user-tables-reconcile.md), [remicsrewrite-test-matrix.md](remicsrewrite-test-matrix.md), [email-contracts.md](email-contracts.md)

---

## Why this document exists

The original RemIcsReWrite program was framed as a **rewrite** but shipped as a **thin shell over legacy batch + ASMX**, with new JavaScript that reimplemented UX without the same invariants as classic MICS. That gap produced real production bugs (cross-company PDF selection, false Ready states, alert/focus traps, catalog drift, lookup JS corruption).

**This plan stops feature parity work until stabilization gates pass.** Interior layout polish (IP-*) and new nav surfaces are deferred.

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

The old phase docs treated **backend parity** and **layout parity** as separate checkboxes but did not require **security/isolation invariants** or **catalog consistency** as release gates.

---

## Stabilization gates (must pass before new features)

### Gate A — Company isolation (P0)

Every path that lists or validates TS/ES/TSIP PDFs must filter by `Session['s_schema']` / `operator`.

**Audit targets:**

- [ ] All `lookuptsip/luTsip*.aspx.cs` (PDF list, env file name, env type side effects)
- [ ] `Ttsipmenu/TwsTsip.asmx.cs` — `tsipValidate`, `tsipValidateAll` (partially fixed in IIS; confirm source mirror)
- [ ] `Tfileactions/copy.aspx.cs` and other file pickers using `user_tables_view`
- [ ] Rewrite bridges: `files.ashx`, `remics-tsip-run-form.js` client validate calls
- [ ] Post Analysis / CASEDET / Aux Eng file pickers (`tabletype` 300+)
- [ ] Data Search result actions that open foreign-schema PDFs

**Verification:** Log in as `bchy1`; confirm `1c0139c2444` (rctl-only) never appears in TSIP PDF or env lookups.

### Gate B — Catalog integrity (P0)

`web.user_tables` must match physical marker tables for types **0 / 5 / 417**.

**Done (infra):**

- [x] `web.ReconcileUserTables` proc
- [x] Nightly SQL Agent job **User Tables Reconcile** (02:30)
- [x] On-demand: `Invoke-RemicsUserTablesReconcile.ps1`

**Remaining:**

- [ ] Extend reconcile to high-traffic SDF/tool `tabletype`s (300+) or document explicit exclusion
- [ ] After KillTable/CopyTable errors in rewrite UI, call reconcile for affected schema (optional Agent job start)
- [ ] Rewrite create/delete paths treat "table exists" vs "catalog missing" distinctly (TS/ES, not only TsipParm)

### Gate C — TSIP run safety (P0)

- [x] Empty parm files show **No runs**, not Ready; Run disabled
- [x] New parm → New run flow
- [ ] Env file cross-company check (PDF envname must be own-operator when `envtype` is `PDF_*`)
- [ ] Save-run server validation mirrors `tsipValidateAll` (don't rely on client only)
- [ ] End-to-end test: bchy1 create parm → run → own TS only → queue completes

### Gate D — Lookup & form UX (P1)

- [x] `lookup-js.ashx` tag strip safe for `<=`
- [ ] Inventory every rewrite `?` lookup type — smoke test after hard refresh
- [ ] Remove remaining alert+focus traps in `remics-ts.js`, ES flows, import wizards
- [ ] Cache-bust policy for `lookup1.aspx` / lookup JS (document in test matrix)

### Gate E — Create/delete honesty (P1)

- [x] TsipParm create: pre-check + post-tree verify + friendly "already exists"
- [ ] TS/ES create/delete same pattern in `remics-ts.js`
- [ ] KillTable failure → suggest reconcile + refresh, not raw CopyTable text

### Gate F — Automated regression (P1)

Extend [remicsrewrite-test-matrix.md](remicsrewrite-test-matrix.md):

- [ ] SQL check: zero cross-company parm runs (query from cross-company cleanup)
- [ ] HTTP smoke: TSIP validate returns `not found` for foreign PDF name
- [ ] Nightly reconcile run row in `web.user_tables_reconcile_run` (monitor job success)

---

## Work phases (execution order)

### Phase S0 — Ops & notifications (done 2026-09-01)

- [x] Error queue team mail: replace `mlimpin@fcsa.ca` → `alejandro.moreno@sympatico.ca` in [email-queue-local-agent-job.sql](email-queue-local-agent-job.sql); redeploy **Email Queue Local**
- [x] Document [user-tables-reconcile.md](user-tables-reconcile.md)

### Phase S1 — Isolation audit & fixes (current)

1. Grep all `user_tables` / `user_tables_view` queries in `config/remicsdev/source/mics` and `D:\inetpub\remicsdev\mics`
2. Fix any missing `operator` filter; mirror to IIS
3. Add envname cross-company rule to TSIP save/validate
4. Re-run cross-company parm scan (should stay at 0)

### Phase S2 — Catalog & file lifecycle

1. TS/ES create/delete UX parity with TsipParm fixes
2. Optional: post-error `sp_start_job 'User Tables Reconcile'` hook from rewrite on CopyTable/KillTable ambiguous failure
3. Review `files.ashx` vs catalog for list/validate consistency

### Phase S3 — TSIP & lookups hardening

1. Full lookup smoke matrix (all `Tsip*` types in `lookuptsip.js`)
2. Server-side run save validation
3. bchy1 golden path: import TS → validate → parm → run → post analysis

### Phase S4 — Rewrite program reassessment (product)

**Honest scope statement going forward:**

| Claim | Reality |
|-------|---------|
| "Rewrite" | **Shell + routing** over existing batch/ASMX — not new domain layer |
| "No Telerik" | Correct for rewrite UI; classic Telerik trees still authoritative for some flows |
| "Parity" | Must mean **same bytes + same authorization boundaries**, not similar HTML |

**Decisions to record:**

1. **Stop** calling incomplete areas "Ready" in docs/README until Gate A–C pass for that area.
2. **Prefer** classic `lu*.aspx` backends for lookups (already exist) — rewrite only hosts iframe/JS bridge; do not re-query catalog in JS without schema.
3. **Do not** add new rewrite-owned SQL for file lists; use `user_tables_view` + operator or existing ASMX.
4. **Interior parity (IP-*)** resumes only after S1–S3 green on test matrix.
5. **Telerik retirement** remains a separate program — rewrite is step 1 (frames out), not Telerik removal.

Deliverable: update [README.md](README.md) phase statuses; archive misleading "Complete" labels where gates failed.

---

## Daily checklist (remicsdev)

```powershell
# Cross-company parms (expect 0)
.\scripts\Invoke-RemicsDevSql.ps1 -ReadOnly -Query "EXEC web.ReconcileUserTables @DryRun=1"

# Last reconcile
.\scripts\Invoke-RemicsDevSql.ps1 -ReadOnly -Query "SELECT TOP 5 * FROM web.user_tables_reconcile_run ORDER BY run_id DESC"

# Feature smoke (when script exists)
# .\scripts\Test-RemicsFeatureSmoke.ps1 -User bchy1
```

---

## References (bugs fixed 2026-08-31)

- Cross-company TSIP parm cleanup (`tmp-tsjob/delete-cross-company-parms.sql`)
- TSIP UX: `remics-tsip.js`, `remics-tsip-run-form.js`, `tsip-parm.html`, `tsip-batch.html`
- Lookup: `lookup-js.ashx`, `lookup1.aspx`, `luTsipPdfList.aspx.cs`, `luTsipEnvFileName.aspx.cs`
- Catalog: `web.ReconcileUserTables`, Agent job **User Tables Reconcile**
