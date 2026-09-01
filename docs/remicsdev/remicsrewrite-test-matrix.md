# RemIcsReWrite — feature test matrix (visible nav scope)

**Status:** Living checklist — scope = **visible nav only** (`remics-nav-data.js`, currently **92 entries / 58 active / 24 wrap checks**)  
**Last smoke:** 75/75 PASS (nav-driven feature smoke)
**Oracle:** Shared backend outcomes (ASMX/batch reports, DB, JSON) — not DOM/pixel parity  
**Automation:** [`scripts/Invoke-RemicsReWriteFeatureSmoke.ps1`](../../scripts/Invoke-RemicsReWriteFeatureSmoke.ps1) (nav-driven) + FCSA `/admin/` panel  
**Nav manifest:** [`scripts/Get-RemicsVisibleNavManifest.ps1`](../../scripts/Get-RemicsVisibleNavManifest.ps1)  
**Related:** [automated-testing.md](automated-testing.md), [remicsrewrite-phase675.md](remicsrewrite-phase675.md)

## Next to test (2026-08-21)

Live-verified this session (do not retest unless a regression shows up):

- Terrain Profile: generate (results in-page) + **Email me** queued
- CASEDET TSTS + TSES: CSV generate; KML Global emailed
- Password recovery / forgot password (already live)

**Next live shell runs** — Auxiliary Engineering, same two-site lat/lng that worked for Terrain  
(A `45-19-59.00N` / `075-54-00.00W` → B `45-25-01.20N` / `075-42-00.00W`):

1. **Over Horizon Losses** — K `1.333333`, freq `6000`; then **Email me**
2. **Passive Calculations** — run + **Email me**
3. **Power Flux Density** — real antenna code; blank call maps to `0`
4. **Satellite Bearings**
5. **Orbit Intersection**
6. **Generate CTX Curves**
7. **Distance and Bearing** (in-page calc vs classic)
8. Pattern / PCS / Sep / Coord / HiLo (run each once)

Email handlers now accept hyphenated job serials (`9999999-12`). OHL and Passive share that fix.

Out of scope still: hidden nav (Reports, FCC/ISED/COMSEARCH/TAFL, Build Radio Catalogue, Maintenance, Accounting, Release Updates).

## Scope rule

Test only what appears in the **visible** left nav. Hidden top-level sections (and all children) are **out of scope** — not manual, not automated:

Reports · FCC Conversion · ISED TS/Member/ES Conversion · TAFL LAML · COMSEARCH Conversion · Build Radio Catalogue · Maintenance · Accounting Reports · Release Updates

Regenerate nav after classic tree changes:

```powershell
.\scripts\Generate-RemicsNavJs.ps1
```

---

## How to run automation

```powershell
# Nav-visible feature smoke (login + all active views + wrap URLs + type loops)
.\scripts\Invoke-RemicsReWriteFeatureSmoke.ps1

# Inspect what the smoke script will cover
.\scripts\Get-RemicsVisibleNavManifest.ps1

# Tier-1 session only (localhost — use -BaseUrl if testing cloud hostname)
.\scripts\Invoke-RemicsReWriteSession.ps1 -BaseUrl 'http://localhost/mics/'

# Batch gold — pinned fixtures from tests/remicsdev/fixtures/baselines.yaml
# (bbimport2 is a live dev table used by feature smoke valFile, not a pinned fixture)
.\scripts\Invoke-MicsFileOpCompare.ps1 -Op validate -Fixture cat -MicsUser rctl1 -Json
.\scripts\Invoke-MicsFileOpCompare.ps1 -Op validate -Fixture ecomm2602 -MicsUser rctl1 -Json

# TSIP archive compare — latest completed run, or pin -BaselineRunId from baselines.yaml
.\scripts\Invoke-LastTsipCompare.ps1 -Json
.\scripts\Invoke-LastTsipCompare.ps1 -BaselineRunId 6 -Json   # ecomm2602 tsip.baseline_run_id

# Gate F — nightly regression (SQL Agent + email on failure)
.\scripts\Deploy-GateFRegressionJob.ps1          # deploy job (once)
.\scripts\Invoke-GateFRegressionTest.ps1         # manual smoke (SQL + HTTP)

# Gate E — TS/ES create/delete honesty (create, duplicate reject, delete)
.\scripts\Invoke-GateEFileOpTest.ps1
.\scripts\Invoke-GateEFileOpTest.ps1 -FileType ES -Users bchy1,rctl1,xci1

# Gate C — TSIP run safety E2E (create parm, add run, validate, delete) per roster user
.\scripts\Invoke-GateCTsipE2ETest.ps1
# Optional: extend roster
.\scripts\Invoke-GateCTsipE2ETest.ps1 -Users bchy1,rctl1,xci1,dnd1

# Gate D — lookup JS + rewrite ? button inventory (login required)
.\scripts\Invoke-GateDLookupSmokeTest.ps1

# Gate A / B isolation + catalog (see remicsrewrite-stabilization-plan.md)
.\scripts\Invoke-GateAIsolationTest.ps1 -User bchy1
.\scripts\Invoke-GateBCatalogTest.ps1 -User bchy1
```

**Lookup cache-bust policy:** bump `REMICS_SHELL.assetVer` in `shell.aspx` whenever ReWrite JS changes. `lookup1.aspx` loads `lookup-js.ashx` with that same version (from the opener shell, fallback constant in `lookupJsVer()`). After deploy, hard-refresh the shell once so stale lookup popups pick up the new `assetVer`.

FCSA Testing: `/admin/` → **RemIcsReWrite feature smoke** panel.

---

## Legend

| Mode | Meaning |
|------|---------|
| **Rewrite** | Shell view + ashx/ASMX in RemIcsReWrite |
| **Hybrid** | Rewrite UI + classic page for part of flow |
| **Wrap** | Nav opens a classic popup (none left in visible nav) |
| **Auto** | Covered by feature smoke script (nav manifest) |
| **Manual** | Human check required |
| **N/A** | Visible but disabled stub |

---

## Visible nav inventory (automation target)

| Section | Active items | Auto coverage |
|---------|--------------|---------------|
| **File** | TS/ES trees, Bulk Print TS/ES, 11× SDF file types | views + `files.ashx` + `sdf-files` all types |
| **Search/Extract** | TS Data, ES Data, 11× SDF search types | views + `ds-search` + `ds-sdf` all types |
| **TSIP** | Parm, Batch Reports, Monitor, Delete TSIP Job, Post Analysis (10) | views + `tsip-status` + `tsip-reps-meta` + `casedet.ashx` |
| **Auxiliary Engineering** | Distance, CTX, Sep, Pattern, Coord, PCS, HiLo live; Area Coordination hidden (classic never shipped it) | view + ashx jobs |
| **Tools** | User Preferences (timeout + extra help), Contact Information, Change Passwords, Set Up Password Recovery | views + `session.ashx` + `contact.ashx` + `password.ashx` + `pwd-recovery.ashx` |
| **Help / Email / dev stubs** | Disabled only | Skipped (no active nav) |

**Not in visible nav (removed from smoke):** Radio Catalogue, Info Files, Fee Calculation, DS Reports, file-open wizard.

---

## Auth / shell

| Feature | Mode | Oracle | Auto |
|---------|------|--------|------|
| Login | Rewrite | session.ashx `ok=true` | Yes |
| Shell load | Rewrite | shell.aspx 200 + phase675.js | Yes |
| Project list | Rewrite | projects.ashx JSON | Yes |
| Log off | Rewrite | session cleared | Manual |
| Change password (reject) | Rewrite | password.ashx `code=badold` | Yes |
| Change password (success) | Rewrite | login with new pwd | Manual |
| Forgot password | Rewrite | pwd-reset Q&A | Manual |
| Set Up Password Recovery | Rewrite | pwd-recovery.ashx + pwd-recovery-setup view | Yes |

---

## File (visible)

| Feature | Mode | Oracle | Auto |
|---------|------|--------|------|
| TS / ES file list | Rewrite | files.ashx | Yes |
| TS / ES tree views | Rewrite | views/ts-tree, es-tree 200 | Yes |
| Validate | Rewrite | valFile ASMX + report file | Yes |
| Export / Import | Rewrite | file-op compare gold | Partial (file-op script) |
| PDF edit get | Rewrite | pdf-edit.ashx titleget | Yes |
| PDF Links / CoC / CoL | Rewrite | pdf-extra.ashx | Yes |
| Bulk Print TS / ES | Hybrid | bulk-print view + Tbulkprint | view Yes; tree Manual |
| SDF trees (11 types) | Rewrite | sdf-files.ashx per type | Yes |
| Open / Import txt / Delete / Copy / DbUpdate / PCN | Rewrite | tree + `ts-file` / `es-file` + pcn.ashx / dbupdate.ashx | Manual (not a nav item) |

---

## Interference Analysis (TSIP)

| Feature | Mode | Oracle | Auto |
|---------|------|--------|------|
| TSIP Parameters | Rewrite | tsip-parm view + TwsTsip | view Yes; list Manual |
| Retrieve Batch Reports | Rewrite | tsip-reps view + tsip-reps-meta | Yes |
| Monitor TSIP | Rewrite | tsip-batch + tsip-status | Yes |
| Delete TSIP Job | Rewrite | `tsip-batch?monitor=1&delete=1` + `tsipDelete` on waiting own jobs | Manual (delete) |
| Post Analysis OHL / Terrain / genctx / NAD27 | Rewrite | same aux-eng tools | Yes (views) |
| Post Analysis Antenna RPE / CTX File | Rewrite | `ds-sdf` Ante / Ctx | Yes |
| Post Analysis CASEDET CSV/KML×4 | Rewrite | `tsip-casedet` + `casedet.ashx` | Yes (view + TSTS/TSES CSV); KML Global emailed 2026-08-21 |
| NAD27 (post + aux) | External | NRCAN URL | Manual (external) |

---

## Search / Extract (visible)

| Feature | Mode | Oracle | Auto |
|---------|------|--------|------|
| TS Data | Rewrite | ds-search searchTs + ds-ts view | Yes |
| ES Data | Rewrite | ds-search searchEs + ds-es view | Yes |
| SDF search (11 types) | Rewrite | ds-sdf.ashx per type | Yes |

---

## Auxiliary Engineering (visible)

| Feature | Mode | Oracle | Auto |
|---------|------|--------|------|
| Distance and Bearing | Rewrite | aux-eng view (in-shell calc) | view Yes; calc Manual |
| Generate CTX Curves | Rewrite | aux-eng?tool=genctx + genctx.ashx | view Yes; generate Manual |
| Pattern / PCS / Sep / Coord / HiLo | Rewrite | aux-eng + handlers / client math | view Yes; run Manual |
| Satellite Bearings | Rewrite | aux-eng?tool=sat + aux-sataze.ashx | view Yes; run Manual |
| Orbit Intersection | Rewrite | aux-eng?tool=orbit + aux-orbit.ashx | view Yes; run Manual |
| Passive Calculations | Rewrite | aux-eng?tool=passive + aux-passive.ashx | view Yes; run Manual |
| Over Horizon Losses | Rewrite | aux-eng?tool=ohl + aux-ohl.ashx | view Yes; **next live run + Email me** |
| Terrain Profile | Rewrite | aux-eng?tool=terrain + aux-terrain.ashx | view Yes; run + Email me live 2026-08-21 |
| Power Flux Density Contours | Rewrite | aux-eng?tool=pfd + aux-pfd.ashx | view Yes; run Manual |
| NAD27–WGS84 (Aux Eng) | Rewrite | NRCan NTv2 window (same URL as Post Analysis) | Manual (external) |
| Area Coordination | Hidden | not in left-nav (classic alerted "not available") | No |
| TS file KML Export | Rewrite | ts-file?action=kml + kml.ashx | Manual |

---

## Tools (visible)

| Feature | Mode | Oracle | Auto |
|---------|------|--------|------|
| Change Passwords | Rewrite | change-password view + bad-old test | Yes |
| User Preferences (Session Timeout) | Rewrite | session.ashx timeoutget/set + PrefExtraHelp | Manual |
| Contact Information | Rewrite | contact.ashx get/set | Manual |
| Set Up Password Recovery | Rewrite | pwd-recovery-setup view + pwd-recovery.ashx | Manual |

---

## Out of scope (hidden nav — do not test)

Reports (Radio Catalogue, Fee Calc, etc.) · FCC/ISED/COMSEARCH/TAFL · Build Radio Catalogue · Maintenance · Accounting · Release Updates. PCN send and DbUpdate notify are in the rewrite (not hidden-nav Reports).

---

## Manual testing checklist (visible nav only)

Run after automated smoke is green. Same hostname in both browsers.

### UX spot checks (~15% of visible scope)

See [interior parity plan](remicsrewrite-interior-parity-plan.md) for the full side-by-side checklist. Minimum after automated smoke is green:

- [ ] Collapsible nav: expand File → Open → TS Data Files; selection highlight follows route
- [ ] TS tree: select file → Validate → report window opens
- [ ] PDF edit: save/reload on bbimport2
- [ ] TSIP parm: list loads; run editor validates bad save
- [ ] Post Analysis: CSV report produces download on completed run
- [ ] Aux Eng Distance: same coords as classic distance.aspx
- [ ] Area Coordination: not listed in left-nav
- [ ] Change password success → log off → log in
- [ ] Forgot password (user with QA setup)

### Destructive / email (manual only)

- [ ] Delete on disposable import name only
- [ ] PCN send / DbUpdate notify — remicsdev only; confirm extractlogs + recipient mail

### Classic ↔ rewrite oracles (existing gold scripts)

- [ ] Validate `cat` — `Invoke-MicsFileOpCompare.ps1 -Op validate -Fixture cat`
- [ ] Validate `ecomm2602` — `Invoke-MicsFileOpCompare.ps1 -Op validate -Fixture ecomm2602`
- [ ] TSIP archive — `Invoke-LastTsipCompare.ps1 -Json` (optional `-BaselineRunId` from `baselines.yaml`)

---

## Automation coverage summary

| Bucket | Coverage | Tool |
|--------|----------|------|
| Nav-visible views (unique shell HTML) | **100%** | Feature smoke (manifest; excludes wrap-only views) |
| Nav-visible wrap URLs | **N/A** | None left in visible nav |
| SDF / ds-sdf all 11 types | **100%** | Feature smoke loops |
| Core ashx + dual-drive validate | High | Feature smoke |
| File-op / TSIP batch gold | High | `Invoke-MicsFileOpCompare.ps1` (pinned fixtures); `Invoke-LastTsipCompare.ps1` (`-BaselineRunId` or latest run) |
| NAD27 external URLs (post + aux) | None | Manual — skipped in wrap manifest |
| Disabled visible stubs | Skipped | N/A |
| Hidden nav sections | Skipped | Out of scope |

**Estimated for visible nav:** ~**85–90% automated**; ~**10–15% manual** (UX, destructive, password success, external NAD27, TSIP/validate deep flows).

---

## Smoke script checks (nav-driven)

The feature smoke script derives checks from `remics-nav-data.js`:

1. **Session / shell** — login, session.ashx, shell.aspx, projects.ashx  
2. **File backends** — files.ashx TS/ES, pdf-extra, pdf-edit titleget, valFile dual-drive  
3. **Per-type loops** — sdf-files ×11, ds-sdf ×11 (from nav)  
4. **Search** — ds-search TS/ES when those views are active  
5. **TSIP** — tsip-status, tsip-reps-meta, casedet list  
6. **Views** — HTTP 200 for every unique active shell view in nav (+ welcome)
7. **Wrap URLs** — none remaining in visible nav.

Regenerating nav or hiding sections automatically shrinks/grows the smoke suite.
