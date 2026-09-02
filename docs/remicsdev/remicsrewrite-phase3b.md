# RemIcsReWrite Phase 3b — Retrieve TSIP Batch Reports

**Status:** Implemented (2026-07-31) — re-verified 2026-09-02 after `UserDirUtil` / `Assembly Src` fix; see [stabilization plan](remicsrewrite-stabilization-plan.md) Gate C/F  
**Entry:** Shell → **Interference Analysis (TSIP) → Retrieve TSIP Batch Reports**

> **Multi-company:** Closing criteria = `Invoke-GateCTsipRepsEditTest.ps1` on the roster. Gate F also asserts `tsip-reps-tree` root `ok=true`.

## Classic parity

Mirrors `Ttsipmenu/tsipRepsTree.aspx`:

| Step | Classic ASMX | RemIcsReWrite |
|------|--------------|---------------|
| List parms with reports | `populateRepTree` | Same |
| Expand parm (ERRORS / Run-N / types) | `populateRepParm` | Same |
| Open report | `CopyToTxt` → `window.open` `userdirs/{schema}/{user}/{file}.txt` | Same |
| Delete one / all for parm | `DeleteFile` / `DeleteAll` | Same (buttons) |

Tree shape: `parm` → `ERRORS` + `Run-{n}` → report types (`CASEOHL`, `STUDY`, …). Double-click a leaf (or **Display Results**) opens the copied `.txt` — same deliverable files as email/external automation.

## Files

| Path | Role |
|------|------|
| `views/tsip-reps.html` | Classic cream pane |
| `js/remics-tsip.js` (`mountReps`) | Tree + open/delete |
| `js/remics-tsip-api.js` | `populateRepTree` / `populateRepParm` / `copyToTxt` / deletes |
| `js/remics-nav.js` | Nav label matches legacy |

## Case-count glance (deviation from classic)

`Case Number : 7` in CASEDET is the **header for case #7**, not a total line. Totals:

| Source | Meaning |
|--------|---------|
| `web.tsip_run.num_int_cases` | Preferred (engine case count; matches CASEDET case headers) |
| Count of `Case Number :` lines in `.CASEDET` | Fallback |
| `Number of reporting cases: N` in `.CASESUM` | Last resort — can be higher (sub-rows / freq lines) |

UI shows next to each run and in a banner:

- **N > 0** → `N interference case(s)`
- **0** → `No cases detected`
- **missing** → `Unknown result — see report files for details`

Endpoint: `tsip-reps-meta.ashx` (also used by queue monitor when `queue_job_id` matches).

## Smoke

**Automated (preferred):** `.\scripts\Invoke-GateCTsipRepsEditTest.ps1`

**Manual:** as any roster user after a finished job in **their** schema (rctl example: `ecomm2601`):

1. **Retrieve TSIP Batch Reports** → see parm  
2. Expand → run node shows glance e.g. `(N interference cases)`  
3. Double-click a report type (or Display Results) → popup under `userdirs/{schema}/{user}/`
