# RemIcsReWrite — Path B Wave 4 audit (2026-09-02)

**Status:** **Complete** — Waves 4A–4D done (W4-1…W4-22)  
**Parent:** [path-b-bugfix-plan.md](path-b-bugfix-plan.md) (Waves 0–3 complete)  
**Scope:** New areas + lower-priority items from post–Wave-3 review  
**Out of scope:** Re-opening fixed W0–W3 items; Path A interior; Path C Phase 7

**Test policy:** Roster ≥2 of `bchy1`, `rctl1`, `xci1` where practical. Smoke + targeted probes on remicsdev.

---

## Progress log

| When | ID | Result |
|------|-----|--------|
| 2026-09-02 | **W4-1** | Fixed in `pdf-edit.ashx` `TitleSave`: after titl UPDATE, `UserTable.SetUserValidFlag(schema, TS→0 / ES→5, name, "N")`; fail closed if catalog update fails. Verified `bchy1` `testts1` / `testes1`: catalog `U`→`N` with titl. Deployed to IIS. |
| 2026-09-02 | **W4-2** | Fixed in `pdf-extra.ashx` `Invalidate`: same titl + `SetUserValidFlag`; all chng/cloc/ccal save/delete callers honor `false`. Verified `bchy1` `testts1` chngSave: catalog `U`→`N`. Deployed to IIS. |
| 2026-09-02 | **W4-3** | Fixed in `TwsTsip.asmx.cs` `AppendPdfCatalogCheck`: blank/whitespace `validstat` fails closed (code `2`). Rebuilt `Ttsipmenu.dll`. Verified blank → code `2`; `U` → Ready. |
| 2026-09-02 | **W4-4** | Fixed in `tsip-run.ashx` `CheckOwnPdfReady`: save requires `STUKML`; UI Ready hints. Verified `N`/blank reject; `U` save ok. |
| 2026-09-02 | **W4-5** | Fixed in `aux-hilo.ashx`: missing/empty report → `ok: false`. |
| 2026-09-02 | **W4-6** | Fixed in `aux-hilo.ashx`: fail when `logreturncode != 0`. Smoke HiLo ok with report. |
| 2026-09-02 | **W4-7** | Fixed in `tsipRun`: `logreturncode==2` → `OK:2`, other non-zero → ERROR; `Finish()!=0` fails. Rebuilt DLL. |
| 2026-09-02 | **W4-8** | getcoords AND→`logreturncode != 0` in `aux-ohl` / `terrain` / `pfd` / `orbit`. |
| 2026-09-02 | **W4-9** | `upload.ashx` MISSING cancel deletes raw `name.txt` + `.tmp`. |
| 2026-09-02 | **W4-10…W4-14** | Exception/SQL scrub: `tsip-run` (no `detail`/stack), `dbupdate`, `sdf-edit`, `files`/`upload`/`reconcile`/`contact`/`sdf-files`, classic `ERRORSYS` generic + notify. Deployed; `Ttsipmenu.dll` rebuilt. |
| 2026-09-02 | **W4-15…W4-22** | SDF 0-row UPDATE fail; pdf-extra delete rowcount; JS `.catch`/status batch (phase675, sdf-tree, pdf, tsip, run-form); select `!ok` keep options; blur soft alert. `shell.aspx` assetVer `2026090218`. |

---

## Verdict

| Area | Outcome |
|------|---------|
| PDF edit / tree / validate | **Wave 4A done** |
| TSIP validate / run | **W4-3/W4-7/W4-10 done** |
| TS/ES import upload | **W4-9 done** |
| Aux / job exit | **Wave 4B done** |
| Exception scrub | **Wave 4C done** |
| SDF honesty + UI hang | **Wave 4D done** |
| Optional Wave-3 gate assertions | Still open (empty CASEDET, blank proname, DS scrub) — outside Wave 4 IDs |
| Al Moreno Runs UX | **Done** (outside Wave 4 IDs) |

---

## Bug inventory

### Wave 4A — Catalog / Ready honesty

| ID | Sev | Status |
|----|-----|--------|
| **W4-1** … **W4-4** | P1–P2 | **Done 2026-09-02** |

### Wave 4B — Job exit / empty-success

| ID | Sev | Status |
|----|-----|--------|
| **W4-5** … **W4-9** | P2–P3 | **Done 2026-09-02** |

### Wave 4C — Exception / SQL leak

| ID | Sev | Area | Status |
|----|-----|------|--------|
| **W4-10** | P2 | `tsip-run.ashx` | **Done** — generic + NotifySystemOps; no `detail` |
| **W4-11** | P2 | `dbupdate.ashx` | **Done** — no `ERRORSQL:` / Message |
| **W4-12** | P2 | `sdf-edit.ashx` | **Done** — generic + notify |
| **W4-13** | P3 | files/upload/reconcile/contact/sdf-files | **Done** |
| **W4-14** | P3 | `TwsTsip.asmx.cs` | **Done** — `ERRORSYS: System error…` |

### Wave 4D — SDF honesty + UI hang

| ID | Sev | Area | Status |
|----|-----|------|--------|
| **W4-15** | P2 | SDF parent save 0-row | **Done** — Ante/Band/RecSave |
| **W4-16** | P2 | `remics-phase675.js` `.catch` | **Done** |
| **W4-17** | P3 | `remics-sdf-tree.js` `.catch` | **Done** |
| **W4-18** | P3 | `remics-pdf.js` `.catch` | **Done** |
| **W4-19** | P3 | PDF selects silent empty | **Done** |
| **W4-20** | P3 | `remics-tsip.js` `.catch` | **Done** |
| **W4-21** | P3 | pdf-extra Del rowcount + JS | **Done** |
| **W4-22** | P3 | run-form blur catch | **Done** |

---

## Recommended execution order

```
Wave 4A  →  W4-1 … W4-4 DONE
Wave 4B  →  W4-5 … W4-9 DONE
Wave 4C  →  W4-10 … W4-14 DONE
Wave 4D  →  W4-15 … W4-22 DONE
```

---

## Review decisions

1. **W4-1 / W4-2:** **Yes** — catalog invalidate on title/extra edits.
2. **W4-4:** **Yes** — reject non-Ready on save (`STUKML`) + UI hints.
3. **W4-8:** **Yes** — getcoords fail on `logreturncode != 0`.
4. **W4-14:** **Yes** — scrub classic `ERRORSYS` Message now (generic client text).

---

## References

- Path B Waves 0–3: [path-b-bugfix-plan.md](path-b-bugfix-plan.md)
- Patterns: W2-6 `SetUserValidFlag`; W3-6 exception scrub; W2-3/W3-1 job exit
- Wave 4 completed 2026-09-02
