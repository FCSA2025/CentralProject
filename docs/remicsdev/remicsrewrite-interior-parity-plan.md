# RemIcsReWrite — interior page layout parity plan

**Status:** IP-1 complete; IP-2 complete; IP-3 + IP-4 shipped; **IP-5 items 1–4 shipped (2026-08-05)**  
**Scope:** Visible left nav only — same rule as [remicsrewrite-test-matrix.md](remicsrewrite-test-matrix.md)  
**Goal:** Organize and display interior pages (file editing, engineering, PCN, search, TSIP, tools) as closely as practical to classic MICS — without frames or Telerik.

**Related:** [Phase 1 classic look](remicsrewrite-phase1.md), [Phase 6 PCN](remicsrewrite-phase6.md), [test matrix](remicsrewrite-test-matrix.md), [Generate-RemicsNavJs.ps1](../../scripts/Generate-RemicsNavJs.ps1)

---

## What “parity” means here

Two layers — do not confuse them:

| Layer | Question | How we verify |
|-------|----------|---------------|
| **Backend / report parity** | Do batch jobs, ASMX calls, and report bytes match classic? | Feature smoke, file-op compare, LastTsipCompare |
| **Layout / UX parity** | Does the page look and flow like the classic screen users know? | Side-by-side review (this plan) + manual checklist |

This plan is **layout / UX parity** only. Backend behavior stays on existing gold scripts.

**Not in scope:** pixel-perfect RadTreeView clones, rewriting aux-eng math, hidden nav sections (Reports, FCC, Maintenance, etc.).

---

## Process (same pattern as left nav)

Repeat the nav review workflow for each interior view:

1. **Inventory** — list active nav items → rewrite `view` id → classic `.aspx` reference(s).
2. **Side-by-side** — classic (frames or popup) vs `shell.aspx#/{view}` on the same hostname.
3. **Gap matrix** — title, section order, field labels, table classes (`.o` / `.k` / `.by`), buttons (Submit / Reset / Help / Cancel), hints, marquees, status rows.
4. **Implement** — HTML in `views/*.html`, CSS in `assets/remics-shell.css`, behavior in `js/remics-*.js`. Reuse `main.css` classes; avoid new design tokens.
5. **Verify** — manual spot check + extend feature smoke only where HTTP/layout checks add value (most layout work stays manual).

Regenerate nav after menu changes:

```powershell
.\scripts\Generate-RemicsNavJs.ps1
```

---

## View inventory (visible nav → classic reference)

| Rewrite view | Nav section | Classic reference(s) | Current mode | Layout priority |
|--------------|-------------|------------------------|--------------|-----------------|
| `ts-tree` | File → TS Data Files | `Ttsmenu/tsTree.aspx` | Rewrite | **P1** — flat list vs hierarchy |
| `es-tree` | File → ES Data Files | `Tesmenu/esTree.aspx` | Rewrite | **P1** |
| `ts-file` / `es-file` | Sub-routes from trees | `Tfileactions/*.aspx` | Rewrite | **P2** — polish (mostly done) |
| `pdf-edit` | Tree → Edit contents | `Ttsmenu/ts*.aspx`, `Tesmenu/es*.aspx` | Rewrite | **P1** — multi-page classic chain |
| `bulk-print` | File → Bulk Print TS/ES | `Tbulkprint/TSPrintTree.aspx`, `ESPrintTree.aspx` | Hybrid | **P2** — staging vs dual-tree |
| `sdf-tree` | File → SDF types (×11) | `Tsdfmenu/sdf{Type}Tree.aspx` | Rewrite | **P2** — per-type titles + list |
| `ds-ts` | Search → TS Data | `Tdsts/dsTS.aspx` → `dsTSList.aspx` | Rewrite | **P1** — checkbox criteria model |
| `ds-es` | Search → ES Data | `Tdses/dsES.aspx` → `dsESList.aspx` | Rewrite | **P1** |
| `ds-sdf` | Search → SDF (×11) | `Tdssdf/ds{Type}.aspx` | Rewrite | **P1** — per-type search grids |
| `tsip-parm` | TSIP → Parameters | `Ttsipmenu/tsipParmTree.aspx` | Rewrite | **P2** — tree vs split list |
| `tsip-reps` | TSIP → Retrieve Batch Reports | `Ttsipmenu/tsipRepsTree.aspx` | Rewrite | **P3** — close; tune tree chrome |
| `tsip-batch` | TSIP → Monitor / Run batch | `tsipMonitor.aspx`, `tsipBatch.aspx` | Rewrite | **P2** — monitor table + batch note |
| `tsip-run` | Sub-route from parm | `tsipParm.aspx`, `tsipParmNew.aspx` | Rewrite | **P2** — form field parity |
| `aux-eng` | Aux Eng (×15) | `auxengmenu/distance.aspx`, `AUX*.aspx` | Hybrid | **P2** — distance DMS; rest = wrap OK |
| `change-password` | Tools | `loginPassword.aspx` | Rewrite | **P3** — minor Help/Cancel |
| `tsip-post` | Post Analysis (×10) | `Ttsipmenu/*`, `Tdssdf/*`, `auxengmenu/*` | Wrap | **N/A** — classic popup |
| `pwd-recovery-setup` | Tools | `Maintenance/pwdqa.aspx` | Wrap | **N/A** |

Sub-flows not in nav but in scope when reached from visible trees: **`pdf-edit`**, **`ts-file`/`es-file`** (Validate, Export, Import, Delete, Copy, **DbUpdate**, **PCN**).

---

## Phased workstreams

### Phase IP-1 — File trees + PDF edit (highest user traffic)

**Shipped (2026-08-05):**

- `js/remics-tree.js` — collapsible HTML tree via classic `TwsTStree.asmx` / `TwsESTree.asmx` `expandNode`
- `views/ts-tree.html`, `views/es-tree.html` — full-height tree panel, classic headings
- Context menus match classic PDF order (Validate, Export, PCN, DbUpdate, Delete, Copy, KML Export)
- Double-click file → validate; double-click Title/Site/Antenna/Channel → `pdf-edit`
- `views/pdf-edit.html` title panel — classic labels (Filename, Modify Date, Source + ??, Description textarea, Save/Cancel)

**Shipped (2026-08-05, pass 2):**

- `js/remics-pdf-fields.js` — classic Site/Antenna/Channel layouts (DMS lat/long, lookup buttons, `.m`/`.o`/`.by` labels)
- Wired into `remics-pdf.js` + `shell.aspx`; PDF edit headings (FCSA MICS Terrestrial/Earth Station …)
- PCN / DbUpdate: Help buttons + classic accesskey titles on `ts-file.html` / `es-file.html`

**Shipped (later):** New Site / Link / Antenna / Channel / Azimuth / Change of Call Sign / Change of Location open the rewrite `pdf-edit` panels (not classic popups).

**Classic patterns to match:**

- Full-height tree area; cream background; maroon centered title (`FCSA MICS …` where classic uses it).
- Context menu items and order match classic tree menus.
- PDF edit: separate “pages” per entity (Title, Site, Antenna, Channel, Link, …) with `.o`/`.by` label columns, lookup buttons where classic has `?`, DMS lat/long where classic uses deg/min/sec.
- PCN / DbUpdate entry points unchanged functionally; align panel spacing and button rows with `Tpcnmenu/*` and db-update classic pages.

**Acceptance:**

- [x] TS tree: expand file → see site/link/antenna/channel nodes (HTML tree via classic ASMX)
- [x] ES tree: same for ES node types (Change of Location, etc.)
- [x] PDF edit Title: classic labels and layout for `bbimport2`
- [x] Right-click menu labels and order match classic (PDF level)
- [x] Site/Antenna/Channel edit forms match classic field layout (core fields + DMS + lookups)
- [x] PCN / DbUpdate Help + button row parity vs classic

**Defer if needed:** RadTreeView pixel match; every lookup dialog (stub with “opens classic lookup” acceptable for pass 1).

---

### Phase IP-2 — Data search (TS / ES / SDF)

**Shipped (2026-08-05, pass 1):**

- `views/ds-ts.html`, `views/ds-es.html` — classic FIELD SELECTION checkboxes + FIELD CRITERIA panels
- `js/remics-ds.js` — `bindDsCriteria`, lat/long vs radius exclusivity, Field Descriptions / Help / Show SQL
- Submit / Reset / Help button row; same `ds-search.ashx` params as before

**Shipped (2026-08-05, pass 2):**

- `views/ds-sdf.html` — per-type criteria grids (Band, Ante, …); Submit / Reset / Help
- `ds-sdf.ashx` — multi-column search filters
- `js/remics-phase675.js` — `SDF_SEARCH` metadata + dynamic criteria mount

**Problem:** Classic uses two-phase “field selection” checkboxes + large criteria tables. Rewrite had a small flat form (now updated for TS/ES/SDF).

**Targets:**

- `views/ds-ts.html`, `views/ds-es.html`, `views/ds-sdf.html`
- `js/remics-ds.js`, `js/remics-phase675.js` (SDF mount), `ds-search.ashx`, `ds-sdf.ashx`

**Classic patterns:**

- Section headers: SITE / ANTENNA / CHANNEL (TS/ES); per-type grids for SDF (`dsAnte.aspx`, `dsBand.aspx`, …).
- Top actions: Field Descriptions, Rules Help, Show SQL (can open classic help URLs initially).
- Bottom row: Submit / Reset / Help.
- Results list layout aligned with `dsTSList.aspx` / `dsESList.aspx` (checkbox column, site columns).

**Acceptance:**

- [x] TS search: checkbox groups visible; core SITE + ANTENNA + CHANNEL criteria match classic labels
- [x] ES search: same pattern with ES-specific fields
- [x] SDF: nav deep-link `type=Band` opens Band criteria grid (per-type fields)
- [ ] Results table columns match classic list for a simple query (e.g. `call1=A*`).

---

### Phase IP-3 — TSIP interiors

**Shipped (2026-08-05):**

- `tsip-batch.html` — Important Note block, Batch TSIP / Help buttons, monitor table layout + timestamp
- `js/remics-tsip.js` — queue rendered as classic table; monitor vs batch headings
- `tsip-parm.html` — classic button layout (Run Batch TSIP)

**Targets:** `tsip-parm.html`, `tsip-batch.html`, `tsip-run.html`, `tsip-reps.html`, `js/remics-tsip.js`

**Items:**

- **Monitor TSIP:** table layout like `tsipMonitor.aspx` (timestamp row, auto-refresh option, Close).
- **Run batch:** red “Important Note” block from classic batch confirm.
- **Parm list:** optional unified tree later; pass 1 = align headings, button placement, run list columns.
- **Retrieve reports:** already close (Phase 3b); tune twisties / glance text only.

**Acceptance:**

- [x] Monitor queue table + timestamp row vs `tsipMonitor.aspx`
- [x] Run batch: red Important Note block from classic batch confirm
- [x] Parm list: headings and button placement aligned with classic

---

### Phase IP-4 — SDF trees, bulk print, aux distance, tools polish

**Shipped (2026-08-05):**

- `sdf-tree.html` — per-type long titles (“FCSA MICS Antenna Subsidiary Files”)
- `bulk-print.html` — TS/ES labels, Check all/none, Open print tree
- `aux-eng.html` — DMS distance form via classic `calcdist()` / `fDist` fields
- `change-password.html` — Help button → classic help page

**Targets:** `sdf-tree.html`, `bulk-print.html`, `aux-eng.html`, `change-password.html`

**Items:**

- SDF tree: page title includes type name (“Antenna Subsidiary Files”); match classic `sdf*Tree.aspx` headings.
- Bulk print: clarify hybrid — either improve staging list + button labels or embed simplified print checklist matching classic order.
- Aux distance: DMS inputs + height fields to match `distance.aspx`.
- Change password: add Help button href; Cancel behavior documented.

**Acceptance:**

- [x] SDF tree title includes type name
- [x] Bulk print staging + button labels
- [x] Aux distance DMS inputs + height fields
- [x] Change password Help button

---

## Shared CSS / markup rules

Apply on every touched view:

1. Wrapper: `<div class="classic-pane b">` (except login-style `change-password` → `classic-panel`).
2. Title: `<h3 align="center">` — text copied from classic page title where possible.
3. Tables: `align="center"`, labels `td.o` or `td.k`, inputs in `td.by`.
4. Buttons: `class="bt"`; group Validate/Cancel/Help in classic order.
5. Status: `classic-status` centered; marquees for in-progress states (already on file wizards).
6. No flex/grid redesign — classic used nested tables; match that habit.
7. Extend `remics-shell.css` only for patterns repeated across views (e.g. criteria section box, tree node row).

Load order unchanged: `main.css` (classic) → `remics-shell.css` (shell + interior helpers).

---

## Verification checklist (manual)

**Code-review pass 2026-08-18:** rewrite views have the classic cream pane, maroon/centered titles, `.o`/`.m`/`.bt` rows, WGS84 notes, marquees, and Help/Cancel accesskeys. Checkboxes below are **layout shipped**, not a pixel side-by-side on the DNS hostname. Do that live pass with `rctl1` in both browsers when you want visual sign-off.

### File + edit

- [x] TS tree hierarchy and context menu vs classic `tsTree.aspx` (HTML tree + classic menu order)
- [x] ES tree vs `esTree.aspx`
- [x] Validate / Export / Import wizards vs `Tfileactions/*` (marquees, WGS84 notes, Display Results)
- [x] DbUpdate panel vs classic transfer flow
- [x] PCN panel vs `Tpcnmenu` (distance, recipients, KML, attach; extra upload + temp cleanup after queue)
- [x] PDF edit Title + one Site record vs classic edit pages (also Antenna / Channel / Azimuth / Links / CoC / CoL)

### Search

- [x] DS TS criteria layout vs `dsTS.aspx`
- [x] DS ES vs `dsES.aspx`
- [x] DS SDF Ante + one other type vs `dsAnte.aspx` / `dsBand.aspx`

### TSIP

- [x] Parm list + run editor vs `tsipParmTree.aspx` / `tsipParm.aspx`
- [x] Monitor queue vs `tsipMonitor.aspx` (Delete TSIP Job is the same view with `delete=1`)
- [x] Reports tree vs `tsipRepsTree.aspx`

### Other visible

- [x] Bulk print staging vs `TSPrintTree.aspx` (hybrid: rewrite staging, classic print popup)
- [x] SDF Ante tree title/list vs `sdfAnteTree.aspx` (all 11 types; record edit in-shell)
- [x] Aux distance form vs `distance.aspx` (other Aux Eng tools stay classic popups)
- [x] Change password vs `loginPassword.aspx`

**Still live-only (optional):** hostname vs localhost chrome; RadTreeView pixel match (deferred); every lookup dialog (classic popup is acceptable).

---

## Automation impact

Layout parity stays **mostly manual**. Existing automation unchanged:

- [remicsrewrite-test-matrix.md](remicsrewrite-test-matrix.md) — backend smoke + manual UX section
- Feature smoke — views return HTTP 200; does not assert DOM layout

Optional later: screenshot diff or Playwright layout probes for top 3 views — not required for Phase IP-1.

---

## Suggested implementation order

```
IP-1  File trees + PDF edit + PCN/DbUpdate polish
  ↓
IP-2  Data search TS / ES / SDF
  ↓
IP-3  TSIP parm / monitor / run
  ↓
IP-4  SDF tree titles, bulk print, aux distance, password Help
```

Start **IP-1** unless you prefer search-first (some teams use Search/Extract daily). File + PCN is called out in the request — **IP-1 first**.

---

## Phase IP-5 — Daily edit + search polish (shipped 2026-08-05)

| # | Target | Delivered |
|---|--------|-----------|
| 1 | TSIP run editor + pdf-edit Links/Chg panels | `tsip-run.html` grouped layout; `mountRun()` radios, lookups, Help; pdf secondary panels classic headings + Help/Cancel |
| 2 | SDF trees + ds-sdf Save/Report | `remics-sdf-tree.js` wired; hierarchical `sdf-tree`; ds-sdf checkboxes, Check All/None, Save wizard via `TwsdsSDF.asmx` |
| 3 | Expanded TS/ES field selection + dsTSList results | Region, Grnd, antenna fields; Grnd column in results; backend filters in `ds-search.ashx` |
| 4 | tsip-parm unified tree + bulk-print dual-tree | Parm→runs twistie tree; bulk-print available/staging lists with add/remove/reorder |

**Verify:** TSIP run Help/lookups; SDF tree expand + right-click; ds-sdf Save to new SDF; ds-ts Grnd column; tsip-parm single tree; bulk-print staging.

---

## Files likely touched (by phase)

| Phase | Views | JS | CSS |
|-------|-------|-----|-----|
| IP-1 | `ts-tree`, `es-tree`, `pdf-edit`, `ts-file`, `es-file` | `remics-ts.js`, `remics-pdf.js` | `remics-shell.css` |
| IP-2 | `ds-ts`, `ds-es`, `ds-sdf` | `remics-ds.js`, `remics-phase675.js` | `remics-shell.css` |
| IP-3 | `tsip-parm`, `tsip-batch`, `tsip-run`, `tsip-reps` | `remics-tsip.js` | `remics-shell.css` |
| IP-4 | `sdf-tree`, `bulk-print`, `aux-eng`, `change-password` | `remics-phase675.js`, `distsubs.js` | `remics-shell.css` |

Deploy path after edits: sync `config/remicsdev/source/mics/RemIcsReWrite/` → `D:\inetpub\remicsdev\mics\RemIcsReWrite\`.
