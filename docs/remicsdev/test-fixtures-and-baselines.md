# ReMICS Dev — test fixtures and baselines

**Codebase:** remicsdev  
**Last updated:** 2026-06-30  
**Related:** [automated-testing.md](automated-testing.md), [tsip-archive-queries.md](tsip-archive-queries.md)

Pinned tables and archive baselines for drift-tolerant automated batch tests.

---

## Pinned fixtures (remicsdev / `rctl1`)

| Fixture | Use | Notes |
|---------|-----|-------|
| `cat` | print → import round-trip | Export must be **> 1024 bytes** ([session fix](session-2026-06-29-login-import-fixes.md)) |
| `ecomm2602` / run `TS1` | TSIP | Verified parm; archive run_id **6** (2026-06-30 CLI) and earlier **4–5** (2026-06-25) |

Import round-trips always use a **fresh table name** (`cat_auto_{yyyyMMdd_HHmm}`) to avoid overwriting production data.

---

## Baseline file

Location (when implemented): `tests/remicsdev/fixtures/baselines.yaml`

Stores per-fixture:

- TSIP baseline `run_id` from `web.tsip_run`
- Row counts on `web.tsip_arc_ts_chan` / `tsip_arc_ts_site`
- Report line counts per `report_type` in `web.tsip_run_report_line`
- Export byte size and import row count for print/import tests

Phase B (dedicated account): `baselines-autotest1.yaml` — see [test-account-setup.md](test-account-setup.md).

---

## Assertion layers

| Layer | What | Pass criteria | Drift sensitivity |
|-------|------|---------------|-------------------|
| **L0 Infra** | Login, session, exe on disk | `shownetsession` has `FCSASESS`, `prog_dir` → `develbat`; exes exist | None |
| **L1 Process** | Batch actually ran | `web.dblogger`: `logerrorcode=0`, not 1314/-98; TSIP `TQ_Finish=0`, not 666 | Low |
| **L2 Structural** | Outputs exist and are plausible | Export size > 1024; import creates `ft_{name}_*`; TSIP reports **> 0 bytes**; `num_int_cases > 0` | Low |
| **L3 Archive-relative** | Compare to baseline run | Registry, row counts, calc fingerprint, report line counts vs baseline `run_id` | Medium |
| **L4 Cross-fixture** | Same failure on multiple parms | ≥2 pinned TSIP parms fail L3 same night → likely **code/deploy**; one fails → likely **drift** | Heuristic |

### TSIP L3 checks

After each TSIP test run, capture new `run_id` and compare to baseline:

1. **Registry:** `num_int_cases`, `archive_status=complete`, `protype`, `parm_file`, `run_name` match baseline.
2. **Layer 2 row counts:** `COUNT(*)` on `web.tsip_arc_ts_chan` / `tsip_arc_ts_site` — exact match when DB unchanged.
3. **Calc fingerprint:** Compare `calcico`, `resti` on joined keys (`caseno`, `intcall1`, `viccall1`) — report changed row count as drift metric.
4. **Report line counts:** Per `report_type` in `web.tsip_run_report_line` — counts should match baseline.

### Print / import / validate L3 checks

1. `exportTable` → `dblogger` exit 0; file size **> 1024** and not exactly 1024.
2. `importTable` under `cat_auto_{timestamp}` → exit 0; `tableexists` true.
3. `valFile` on `cat` → exit 0.

---

## Baseline refresh workflow

When someone intentionally changes `cat` or `ecomm2602` data:

1. Run tests manually and verify output is correct.
2. Run `scripts/Update-RemicsDevTestBaselines.ps1` (to implement).
3. Commit updated `baselines.yaml` with date and reason in commit message.

Without refresh: tests should report **WARN_DRIFT** (L3 mismatch, L1/L2 pass, single fixture), not silent PASS.

---

## Web invocation map

| Program | ASMX | Method | Batch exe |
|---------|------|--------|-----------|
| Print | `Tfileactions/TwsTabUtil.asmx` | `exportTable(filename, "TS", projectCode)` | `ftPrint` |
| Import | same | `importTable(filename, "TS", projectCode)` | `ftImport` |
| Validate | same | `valFile(filename, "TS", projectCode, hilorep, verbose)` | `ftValidate` |
| TSIP | `Ttsipmenu/TwsTsip.asmx` | `tsipRun(parmfile)` | `TsipInitiator` |

Reference: [ts-file-import-flow.md](ts-file-import-flow.md), [tsip.md](tsip.md).

---

## What we avoid

- Byte-exact golden files on disk for TSIP reports (timestamps, paths drift)
- Asserting calc values against live tables without archive comparison
- Running tests as real production user accounts
