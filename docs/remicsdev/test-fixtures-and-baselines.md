# ReMICS Dev — test fixtures and baselines

**Codebase:** remicsdev  
**Last updated:** 2026-07-15  
**Related:** [automated-testing.md](automated-testing.md), [tsip-archive-queries.md](tsip-archive-queries.md), [test-account-setup.md](test-account-setup.md)

Pinned tables and archive baselines for drift-tolerant automated batch tests.

**Implemented location:** `tests/remicsdev/fixtures/` (`baselines.yaml`, `files/*.txt`, README).  
**Operator UI:** `http://localhost/admin/` (Export/Import/Validate + TSIP compare).  
**Workers:** `scripts/Invoke-MicsFileOpCompare.ps1`, `scripts/Invoke-RecentDistinctTsipCompares.ps1`, `scripts/Invoke-LastTsipCompare.ps1`, `scripts/Update-RemicsDevTestBaselines.ps1`, `scripts/Remove-RemicsDevTestTables.ps1`.

---

## Pinned fixtures (remicsdev / `rctl1`)

| Fixture | Use | Notes |
|---------|-----|-------|
| `cat` | print → import → validate (smoke) | Export ~1307 bytes; must be **> 1024** ([session fix](session-2026-06-29-login-import-fixes.md)) |
| `ecomm2602` | complex print/import; primary TSIP | Export ~3506 bytes; TSIP run `TS1` |
| `ecomm2601b` | secondary TSIP / print | Export ~5156 bytes; live compare default |

Import round-trips always use a **fresh short table name** (`cataHHmmss`, `e2602aHHmmss`, …) — MICS root names truncate around 16 characters.

### Shared cross-schema fixtures

For account-independent manual testing, every existing schema referenced by an
active MICS account contains:

- TS: `testts1`, `testts2`, `testts3`
- ES: `testes1`, `testes2`, `testes3`

These fixed names make the file type obvious in both data trees. Reinstall
missing fixtures with `scripts/Install-MicsSharedTestFixtures.ps1`. The script
adapts TS operator records to each destination schema and reserves only those
six roots.

The FCSA `/admin/` file-op runner supports all four operations for both types:
Export, Import, Validate, and Round-trip. TS fixtures use `FtPrint`, `FtImport`,
and `FtValidate`; ES fixtures use `FePrint`, `FeImport`, and `FeValidate`.
Temporary imports use allowlisted names and are removed after each run.

Verified 2026-07-16: 198 non-empty fixture sets across 33 schemas; TS and ES
print smoke both succeeded from `aliant`. The active `abccom` account rows are
excluded because their configured `PrimarySchema=abccom` does not correspond
to an existing SQL schema.

After import / validate / round-trip, the worker **drops** those auto tables with `ftImport … -x` (allowlisted prefixes only; pinned `cat` / `ecomm2602` / `ecomm2601b` are never touched). See [test-account-setup.md](test-account-setup.md) (Phase A cleanup). Orphan sweep: `scripts/Remove-RemicsDevTestTables.ps1`.

---

## Baseline file

Location: `tests/remicsdev/fixtures/baselines.yaml`

Stores per-fixture:

- TSIP baseline `run_id` from `web.tsip_run`
- Row counts (`sites` / `chans` / `antes`)
- Export byte size for print/import tests

Refresh:

```powershell
.\scripts\Update-RemicsDevTestBaselines.ps1
```

### Rolling distinct TSIP batch

The admin TSIP button snapshots and tests up to the 10 most recent distinct
files from completed `web.tsip_run` rows. Distinctness is:

`source_schema + protype + parm_file`

Repeated runs of one file therefore consume one slot, while TS and ES files
with the same root remain distinct. The query runs each time the button is
pressed, so newly archived files automatically enter the rolling set. If fewer
than 10 exist, all available distinct files run.

Each batch saves its exact baseline selection before execution:

`D:\inetpub\fcsa\admin\tsip-runs\batches\{batch_id}\manifest.json`

It also saves one result JSON per file plus `results.json`. Individual reruns
are sequential to avoid same-file TSIP concurrency.

---

## Assertion layers

| Layer | What | Pass criteria | Drift sensitivity |
|-------|------|---------------|-------------------|
| **L0 Infra** | Login, session, exe on disk | `shownetsession` has `FCSASESS`, `prog_dir` → `develbat`; exes exist | None |
| **L1 Process** | Batch actually ran | exe exit 0; `web.dblogger` `logerrorcode=0` when used; TSIP not concurrent/empty | Low |
| **L2 Structural** | Outputs exist and are plausible | Export size > 1024 and ≠ 1024; import creates `ft_{name}_*`; TSIP reports **> 0 bytes** | Low |
| **L3 Archive-relative** | Compare to baseline | Export size near baseline; import row counts; TSIP registry/calc/report_line | Medium |
| **L4 Cross-fixture** | Same failure on multiple parms | ≥2 pinned TSIP parms fail L3 → likely **code/deploy**; one fails → likely **drift** | Heuristic |

### TSIP L3 checks

After each TSIP test run, capture new `run_id` and compare to baseline:

1. **Registry:** `num_int_cases`, `archive_status=complete`, `protype`, `parm_file`, `run_name` match baseline.
2. **Layer 2 row counts:** `COUNT(*)` on `web.tsip_arc_ts_chan` / `tsip_arc_ts_site` — exact match when DB unchanged.
3. **Calc fingerprint:** Compare `calcico`, `resti` on joined keys (`caseno`, `intcall1`, `viccall1`) — report changed row count as drift metric.
4. **Report line counts:** Per `report_type` in `web.tsip_run_report_line` — counts should match baseline.

### Print / import / validate L3 checks

1. `ftPrint` → exit 0; file size **> 1024** and not exactly 1024; near baseline bytes.
2. `ftImport` under short auto name → exit 0; `ft_{name}_titl` exists; site/chan counts match fixture; then auto tables cleaned up.
3. `ftValidate` on a freshly imported copy → exit 0; no `*ERROR*` markers; then auto tables cleaned up.

---

## Baseline refresh workflow

When someone intentionally changes `cat` or `ecomm2602` data:

1. Run tests manually and verify output is correct.
2. Run `scripts/Update-RemicsDevTestBaselines.ps1`.
3. Commit updated `baselines.yaml` (+ `files\*.txt`) with date and reason in commit message.

Without refresh: tests should report **NO MATCH / WARN_DRIFT** (L3 mismatch, L1/L2 pass), not silent PASS.

---

## Web invocation map

| Program | ASMX | Method | Batch exe | FCSA admin |
|---------|------|--------|-----------|------------|
| Print | `Tfileed/TwsTabUtil.asmx` | `exportTable` | `ftPrint` | Export / Print button |
| Import | same | `importTable` | `ftImport` | Import button |
| Validate | same | `valFile` | `ftValidate` | Validate button |
| TSIP | `Ttsipmenu/TwsTsip.asmx` | `tsipRun` | `TpRunTsip` / `TsipInitiator` | TSIP re-run compare |

Admin handlers: `/admin/fileop-start.ashx`, `/admin/fileop-status.ashx`, `/admin/tsip-compare-start.ashx`.

Reference: [ts-file-import-flow.md](ts-file-import-flow.md), [tsip.md](tsip.md).

---

## What we avoid

- Byte-exact golden files on disk for TSIP reports (timestamps, paths drift)
- Asserting calc values against live tables without archive comparison
- Running tests as real production user accounts (long-term: use `autotest1`)
- Overwriting pinned fixture tables via import
- Leaving auto-import `ft_*` sets in `rctl` after file-op tests (cleanup via `ftImport -x`)
