# RemIcsReWrite Phase 6.75 — Remaining core (pre-email)

**Status:** Implemented (MVP, 2026-07-31)  
**Slot:** After Phase 6.5, before Phase 7 (email re-enable)  
**Detail plan:** `~/.cursor/plans/phase_6.75_remaining_core_f9a2c1b0.plan.md`

## Workstreams

| ID | Delivered |
|----|-----------|
| **T** | `#/tsip-casedet` → `casedet.ashx` list + classic CSV/KML URLs; `remics-tsip-validation.js` on run save; PCN receive N/A (classic has no receive page; ES RX-only already in Phase 6 send) |
| **F** | `#/file-open`; pdf-edit Links / Chg Call / Chg Loc / ES Chg Call via `pdf-extra.ashx`; `#/sdf-tree` + `sdf-files.ashx` + `createTable` SDF types |
| **S** | `#/ds-sdf` → `ds-sdf.ashx` (`main.sd_*`); DS Reports nav opens classic `dsTSReport` / `dsESReport` |
| **R** | Fee calc wizard; Bulk Print → classic print trees; Radio Catalogue / Info Files (popup shortcuts; no shell HTML) |
| **A** | `#/aux-eng` Distance (client `distsubs.js`) + links to classic `auxengmenu/*` |

## Handlers / JS

- `casedet.ashx`, `pdf-extra.ashx`, `sdf-files.ashx`, `ds-sdf.ashx`
- `js/remics-phase675.js`, `js/remics-tsip-validation.js`, `js/distsubs.js`

## Out of scope (unchanged)

FCC/ISED/TAFL loads · Maintenance/Accounting/Tools/Help · Phase 7 email · release cutover · rewriting Aux Eng math
