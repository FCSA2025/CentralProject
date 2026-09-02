# RemIcsReWrite Phase 6.5 — Data Search + create/edit

**Status:** Implemented (2026-07-31) — historical; see [stabilization plan](remicsrewrite-stabilization-plan.md)  
**Slot:** After Phase 6 (PCN), before Phase 7 (email re-enable — **paused**)  
**Detail plan:** `~/.cursor/plans/phase_6.5_search_edit_f6184619.plan.md`

> **Multi-company:** Create/edit/search must be verified with company-owned files on the roster, not rctl-only fixtures.

Frame-free shell views + ashx/ASMX; classic cream UI. No Telerik RadTreeView. SDF Data Search and full XSLT report UIs deferred (feature expansion paused).

## Workstreams

| ID | Scope | Status |
|----|-------|--------|
| **A** | Create masters — `RemIcsApi.createTable` → `TwsTabUtil.createTable` (TS / ES / TsipParm); “Create new file” on trees + TSIP parm list | Done |
| **B** | Deeper TS/ES edit — Title / Site / Ante / Chan (+ ES Azimuth) via `pdf-edit.ashx` + `views/pdf-edit.html` / `js/remics-pdf.js` | Done |
| **C** | TSIP run CRUD — `tsip-run.ashx` + `views/tsip-run.html`; new/edit/dup/delete from parm list | Done |
| **D** | Data Search — **D1** TS + **D2** ES via `ds-search.ashx` + `views/ds-*.html` / `js/remics-ds.js`; cull/PDF insert via classic `TwsdsTS` / `TwsdsES` ASMX | Done |

## Entry points

| UI | Route |
|----|-------|
| Create TS/ES | `#/ts-tree` / `#/es-tree` → Create new file |
| Edit contents | Context menu → `#/pdf-edit?name=&filetype=` |
| TSIP create/CRUD | `#/tsip-parm` → Create parameter / New·Edit·Dup·Delete run → `#/tsip-run` |
| TS Search | Nav **Search/Extract → TS Search** → `#/ds-ts` |
| ES Search | Nav **Search/Extract → ES Search** → `#/ds-es` |

## Handlers

- `pdf-edit.ashx` — title/sites/antes/chans/azims (DBIO for record get/save)
- `tsip-run.ashx` — get/new/save/dup/delete
- `ds-search.ashx` — searchTs/searchEs/detailTs/detailEs (JSON); save path calls classic ASMX from the browser

## Out of scope (unchanged)

- SDF search (`Tdssdf`)
- TS Link / Change of Call Sign; ES Change of Location / Call Sign
- Full RadTree expand / classic context menus
- Data Search XSLT report UIs
- Re-enabling outgoing email (Phase 7)
