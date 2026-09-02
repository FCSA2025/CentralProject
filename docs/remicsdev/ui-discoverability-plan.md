# RemIcsReWrite — UI discoverability plan (post–Al Moreno)

**Status:** **Complete** (Waves U1–U3 done)  
**Date:** 2026-09-02  
**Trigger:** Al Moreno Runs report — parm selected, only **Add run** usable; Edit/Dup/Delete needed a run selection users did not discover.  
**Related:** [path-b-wave4-audit-plan.md](path-b-wave4-audit-plan.md) (backend/UI honesty Waves 4A–4D complete); Al Moreno Runs hotfix (done).

---

## Progress log

| When | ID | Result |
|------|-----|--------|
| 2026-09-02 | Runs hotfix | Parm click auto-expands + first run; Edit/Dup/Delete gated (pre-plan). |
| 2026-09-02 | **U1-1** | Retrieve Reports: auto-select ERRORS else first report leaf; Display enabled only for leaf; Delete for parm/leaf; titles + status. `remics-tsip.js` + `tsip-reps.html`. |
| 2026-09-02 | **U1-2** | File Open TsipParm navigates `tsip-parm?parm=…`; existing `focusParmFromRoute` expands + selects. `remics-phase675.js`. Cache-bust `2026090219`. |
| 2026-09-02 | **U2-1** | CASEDET: status hint after load; no auto-select (CSV `onchange` fires generate). |
| 2026-09-02 | **U2-2** | PDF lists: “click to edit” idle status; first hop/site preferred until user chooses; `(all)` still available. `remics-pdf.js`. |
| 2026-09-02 | **U2-3** | SDF expand: select first `d^` record + `onSelect`. `remics-sdf-tree.js`. |
| 2026-09-02 | **U2-4** | Aux Coord/HiLo: `!ok` keeps options + status error (no fake empty list). `remics-phase675.js`. |
| 2026-09-02 | **U2-5** | Monitor Cancel: dynamic `title`; auto-select first own waiting job. `remics-tsip.js`. Cache-bust `2026090220`. |
| 2026-09-02 | **U3-1** | Tree DOM: replace `:scope` with direct-child helpers. `remics-tree.js` + `remics-ts.js`. |
| 2026-09-02 | **U3-2** | Welcome Active file: show + link for `TSIPPARM` / `TSIPREP`. `remics-app.js`. |
| 2026-09-02 | **U3-3** | TS/ES/SDF Find: status on empty query; note when searching whole tree. `remics-tree.js` + `remics-sdf-tree.js`. |
| 2026-09-02 | **U3-4** | PDF next-step always visible (not gated by Extra Help). `remics-hints.js` + `pdf-edit.html`. Cache-bust `2026090221`. |

---

## Lesson applied

When an action needs a **child** selection:

1. **Auto-select** a sensible default when the parent is chosen, **or**
2. **Disable + explain** (button `title` / status) why it is unavailable, **and**
3. Never leave primary actions looking enabled when they will only `alert`.

Same class of bug as silent empty lists / false success — but on the **selection model**.

---

## Already fixed (reference pattern)

| Area | Fix |
|------|-----|
| **TSIP Runs** | Parm click auto-expands + selects first run; Edit/Dup/Delete gated on `selectedRun`; titles + selection copy (`remics-tsip.js`, `tsip-parm.html`) |
| **SDF / PDF select silence** | W3-8 / W4-19: do not wipe dropdowns on `!ok` |
| **U1-1 Reports** | Expand → prefer ERRORS / first file leaf; Display/Delete gated + titles |
| **U1-2 File Open TsipParm** | `navigate('tsip-parm', 'parm=…')` + `focusParmFromRoute` |
| **U2 CASEDET / PDF / SDF / Aux / Monitor** | See progress log |
| **U3 tree / Welcome / Find / PDF next-step** | See progress log |

---

## Bug / opportunity inventory

### Wave U1 — Same class as Al Moreno (do first)

| ID | Sev | Screen | Symptom | Fix approach | Status |
|----|-----|--------|---------|--------------|--------|
| **U1-1** | P1 | **Retrieve TSIP Reports** | Parm/run selected; Display/Delete still look enabled → alert | Mirror Runs: auto-select leaf; gate buttons | **Done 2026-09-02** |
| **U1-2** | P1 | **File Open → TsipParm** | Typed/selected name dropped | Navigate with `?parm=`; focus on mount | **Done 2026-09-02** |

### Wave U2 — Unclear idle / two-level edit

| ID | Sev | Screen | Symptom | Fix approach | Status |
|----|-----|--------|---------|--------------|--------|
| **U2-1** | P2 | **CASEDET** | After load, idle / no selection | Status hint (no auto-select — generate-on-change) | **Done 2026-09-02** |
| **U2-2** | P2 | **PDF Sites/Antes/Chans/Azims** | Count-only status; hop defaults to (all) | Click-to-edit status; prefer first hop/site | **Done 2026-09-02** |
| **U2-3** | P2 | **SDF tree** | File selected; edit needs record | Highlight first record on expand | **Done 2026-09-02** |
| **U2-4** | P2 | **Aux Eng pickers** | `!ok` → fake empty list | Status error; don’t wipe options | **Done 2026-09-02** |
| **U2-5** | P3 | **TSIP Monitor Cancel** | Static title when disabled | Dynamic title; auto-select first own `W` | **Done 2026-09-02** |

### Wave U3 — Fragility / polish

| ID | Sev | Area | Symptom | Fix approach | Status |
|----|-----|------|---------|--------------|--------|
| **U3-1** | P3 | `remics-tree.js` / `remics-ts.js` | `:scope` fragility | Child-walk helper | **Done 2026-09-02** |
| **U3-2** | P3 | Welcome “Active file” | TSIPPARM shows (none) | Show + link | **Done 2026-09-02** |
| **U3-3** | P3 | SDF/TS/ES Find | Opaque with no selection | Status hint | **Done 2026-09-02** |
| **U3-4** | P3 | PDF next-step hints | Only when hints on | Always show list guidance | **Done 2026-09-02** |

**Out of scope for this plan:** Backend honesty (Waves 0–4), Path A interior polish, new features.

---

## Recommended execution order

```
U1  →  U1-1, U1-2 DONE
U2  →  U2-1 … U2-5 DONE
U3  →  U3-1 … U3-4 DONE
```

**Test policy:** Roster ≥2 of `bchy1`, `rctl1`, `xci1`. Manual: select parent only → confirm primary actions either work (via auto-select) or are disabled with a clear reason; no surprise alerts as the only feedback.

---

## Review decisions

1. **Reports (U1-1):** **ERRORS first**, else first report file leaf (implemented).
2. **CASEDET (U2-1):** **status-only** — auto-select would fire CSV generate on load.
3. **PDF (U2-2):** **status + prefer first hop/site**; no auto-open of single row (browse-friendly). `(all)` remains available; once chosen, session filter remembers it.
4. **PDF next-step (U3-4):** always on; field-level Extra Help remains optional.

---

## References

- Al Moreno Runs hotfix: `remics-tsip.js` (auto-expand / `selectFirst`), `docs/remicsdev/README.md`
- Path B Wave 4: [path-b-wave4-audit-plan.md](path-b-wave4-audit-plan.md)
