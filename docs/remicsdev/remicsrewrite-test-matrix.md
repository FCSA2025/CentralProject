# RemIcsReWrite — feature test matrix (visible nav scope)

**Status:** Living checklist — scope = **visible nav only** (`remics-nav-data.js`, currently **92 entries / 58 active / 24 wrap checks**)  
**Last smoke:** 75/75 PASS (nav-driven feature smoke)
**Oracle:** Shared backend outcomes (ASMX/batch reports, DB, JSON) — not DOM/pixel parity  
**Automation:** [`scripts/Invoke-RemicsReWriteFeatureSmoke.ps1`](../../scripts/Invoke-RemicsReWriteFeatureSmoke.ps1) (nav-driven) + FCSA `/admin/` panel  
**Nav manifest:** [`scripts/Get-RemicsVisibleNavManifest.ps1`](../../scripts/Get-RemicsVisibleNavManifest.ps1)  
**Related:** [automated-testing.md](automated-testing.md), [remicsrewrite-phase675.md](remicsrewrite-phase675.md)

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
```

FCSA Testing: `/admin/` → **RemIcsReWrite feature smoke** panel.

---

## Legend

| Mode | Meaning |
|------|---------|
| **Rewrite** | Shell view + ashx/ASMX in RemIcsReWrite |
| **Hybrid** | Rewrite UI + classic page for part of flow |
| **Wrap** | Nav opens classic popup (`tsip-post`, `aux-eng`, pwd recovery) |
| **Auto** | Covered by feature smoke script (nav manifest) |
| **Manual** | Human check required |
| **N/A** | Visible but disabled stub |

---

## Visible nav inventory (automation target)

| Section | Active items | Auto coverage |
|---------|--------------|---------------|
| **File** | TS/ES trees, Bulk Print TS/ES, 11× SDF file types | views + `files.ashx` + `sdf-files` all types |
| **Search/Extract** | TS Data, ES Data, 11× SDF search types | views + `ds-search` + `ds-sdf` all types |
| **TSIP** | Parm, Batch Reports, Monitor, Delete TSIP Job, Post Analysis (10) | views + `tsip-status` + `tsip-reps-meta` + post wrap URLs |
| **Auxiliary Engineering** | 14 tools incl. Area Coordination | view + all `auxengmenu` wrap URLs |
| **Tools** | User Preferences (timeout + extra help), Contact Information, Change Passwords, Set Up Password Recovery | views + `session.ashx` + `contact.ashx` + `password.ashx` + pwdqa wrap |
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
| Set Up Password Recovery | Wrap | pwdqa.aspx 200 (optional) | Yes |

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
| Post Analysis (10 items) | Wrap | classic pages via tsip-post | Yes (HTTP 200 each) |
| NAD27 (post + aux) | External | NRCAN URL | Manual (external) |

Post Analysis wrap targets: OHL, Terrain, Antenna RPE, CTX, CASEDET CSV/KML×4, Generate CTX.

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
| Passive … HiLo (13 wraps) | Wrap | auxengmenu/*.aspx 200 | Yes |
| Area Coordination | Wrap | AUXAreaCoord1.aspx 200 | Yes |
| NAD27–WGS84 | External | NRCAN | Manual |

---

## Tools (visible)

| Feature | Mode | Oracle | Auto |
|---------|------|--------|------|
| Change Passwords | Rewrite | change-password view + bad-old test | Yes |
| User Preferences (Session Timeout) | Rewrite | session.ashx timeoutget/set + PrefExtraHelp | Manual |
| Contact Information | Rewrite | contact.ashx get/set | Manual |
| Set Up Password Recovery | Wrap | pwdqa.aspx | Yes (optional) |

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
- [ ] Area Coordination: AUXAreaCoord1 → pick area → AUXAreaCoord2 loads
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
| Nav-visible wrap URLs | **100%** | Feature smoke (manifest; pwdqa optional) |
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
6. **Views** — HTTP 200 for every unique active shell view in nav (+ welcome); **wrap-only** views (`tsip-post`, `pwd-recovery-setup`) are excluded — those are covered by wrap URL checks instead  
7. **Wrap URLs** — HTTP 200 for every tsip-post + aux-eng + pwd-recovery classic page (pwdqa optional)

Regenerating nav or hiding sections automatically shrinks/grows the smoke suite.
