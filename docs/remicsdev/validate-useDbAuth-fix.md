# Validate hang / wrong validator — UseDbAuth fixes (29 July 2026)

**Status:** Fixed on remicsdev  
**Symptom:** ES file `isedess23b` — server finished `ftValidate` in ~2s but UI stayed on “Validating…” (or showed a generic batch error instead of the report).

---

## What happened (`isedess23b` incident)

| Observation | Detail |
|-------------|--------|
| Batch time | 3:40:39 PM → 3:40:41 PM (~2 seconds) |
| Program run | `ftValidate` (TS/PDF validator) |
| Exit code | `-2237` |
| Report written | `userdirs\rctl\rctl1\isedess23b.txt` — `ERROR - pdf 'isedess23b' does not exist` |
| SQL tables | `fe_isedess23b_*` — file is **ES**, not TS/PDF |

Two separate bugs combined:

1. **Wrong file type in URL** — `fileToValidate()` opened `validate.aspx?valName=…` only. `validate.aspx.cs` defaults `valType` to `TS`, so ES files were validated with `ftValidate` instead of `feValidate`.

2. **UseDbAuth exit-code handling** — Under AD, `JobSubmit` treats non-zero `ftValidate`/`feValidate` exits (except 98–100) as “validation completed with errors” (`logerrorcode = 0`) and `valFile` returns `{name}.txt` for display. Under **UseDbAuth** (`SubmitJobViaProcessStart`), any non-zero exit set `logerrorcode = -1`, so `valFile` returned `ERROR: Unspecified error running ftValidate` and `RemIcsApi` flagged `r.ok = false` instead of showing the report.

---

## Fixes applied

### 1. Pass file type from file menu — `includeFiles/TFileOptions.js`

In `SubmitJobViaProcessStart`, after `Process.Start` + `WaitForExit`, apply the same `ftValidate`/`feValidate` special case as the `CreateProcessAsUser` path:

- Non-zero exit codes (except 98, 99, 100) → `logerrorcode = 0`, `logreturncode = 0`
- `valFile` returns `{filename}.txt` so the legacy validate UI can show “Display Results”

**Rebuild:** `utilities\utilities.csproj` → `bin\utilities.dll`  
**Recycle:** `remicsdevapp`

### 3. Validate UI hang (server done, browser stuck) — `Tfileactions/validate.aspx`

Observed after JobSubmit fix: batch finished in ~1s (`logreturncode: 0`) but iframe still showed Telerik “Validating…”. Likely causes: `valFile` `fetch` not completing in the frame layout (ASP.NET session contention), and/or RadTicker not hiding when `m1` is toggled via legacy global element refs.

Changes:

- `EnableSessionState="ReadOnly"` on validate page GET (reduces session lock vs other frames)
- Replace **RadTicker** with plain `<marquee>` (same as export/import)
- Use `document.getElementById` for `m0`–`m3` (not legacy `m1` globals)
- **`syncFileTypeFromParent()`** — if URL lacks `valType`, use `parent.txtsType` before calling `valFile`
- **Report poll fallback** — every 2s `fetch` `VALIDATE_CFG.reportUrl`; when report content changes and contains `RUN DATE`, show **VALIDATION COMPLETE** even if `valFile` `fetch` is still pending
- **Error/warning summary** — parses `There were a total of N errors and M warnings.` when present; otherwise shows *Errors were detected* (no counts) for malformed or non-standard reports
- Harden `resetValidateUi()` in `Tutils.js` to use `getElementById`

No DLL rebuild — recycle app pool optional (markup/JS only).

---

## How to verify

1. Open an **ES** file in the ES tree (e.g. `isedess23b`).
2. File → Validate.
3. Confirm URL includes `valType=ES`.
4. Confirm `D:\extractlogs\remicsdev_{user}submit5.txt` shows `feValidate` (not `ftValidate`).
5. UI should reach **VALIDATION COMPLETE** and **Display Results** opens `isedess23b.txt` (even when the report lists validation errors).

Harness: `/mics/RemIcsReWrite/file.aspx` with `valFile` and `filetype: 'ES'`.

---

## Related docs

- [Email to Bill — AJAX fixes](email-to-bill-2026-07-29-ajax-auth-fixes.md) — includes these two items in the handoff list
- [Application learnings — Batch execution](application-learnings.md#batch-execution-contract)
- [AD-free auth Phase 2](ad-free-auth-phase2-cut.md) — introduced `SubmitJobViaProcessStart`

---

## Follow-up (not done here)

- `fileToExport()` still omits `sType` on the query string (export code-behind defaults to `TS`; same class of bug for ES export).
- `ISEDESInfo/ISEDESoutput.aspx` still uses `sesSiteName` + `callajaxchrome` for validate (P3 / specialized import track).
- `Tpcnmenu/DbUpdate.aspx` — fixed same class of bugs as validate/export (see below).

---

## DbUpdate fix (30 July 2026)

`Tpcnmenu/DbUpdate.aspx` (PCN / Transfer to FCSA for update) had the same legacy AJAX issues plus JavaScript defects:

| Issue | Fix |
|-------|-----|
| `sesSiteName` ASMX URLs | `RemIcsApi.exportForUpdate` / `userUpdate` with `fetch` + credentials |
| CDN jQuery from code.jquery.com | Local `micsjquery.js` |
| `exportUser()` used undefined `projectCode` | `UPDATE_CFG` + `updateCfg()` |
| `ExportDone` typo (function is `ExportUDone`) | Corrected callback chain |
| `../../userdirs/` path for error display | `../userdirs/` |
| Fragile `callajaxchrome` + `parseJSON` | `RemIcsApi` promise handlers |

Files: `Tpcnmenu/DbUpdate.aspx`, `DbUpdate.aspx.cs`, `RemIcsReWrite/remics-api.js` (`exportForUpdate`, `userUpdate`).

### DbUpdate “unable to connect to the database” (30 July 2026, follow-up)

**Symptom:** Opening Update showed alert *“Your session was unable to connect to the database”* and logged the user out.

**Root cause (two parts):**

1. `DbUpdate.aspx.cs` queried `SELECT validated FROM ft_{name}_titl` **without the user schema prefix**. Under `UseDbAuth` the ODBC default schema is not the operator schema, so the query failed.
2. `DbUpdate.aspx` `load()` redirected to `relogin.aspx` on any `txtErrorMsg`. `relogin.aspx.cs` defaults `reason=3` when no query string is passed → the misleading database-connection message (not a real session/DB auth failure).

**Fix:** Use `UserTable.GetUserValidFlag(schema, tableType, sName)` for TS/ES (same as `PcnTS` / `PcnES`). Schema-qualify subsidiary `su_*` queries. Show `txtErrorMsg` in an alert + `goBack()` instead of redirecting to relogin.

**Follow-up (30 July 2026):** Validation-error path called `goBack()` which used `parent.sesSiteName` (wrong host) → tree reload returned session timeout → `relogin.aspx` signed user out. Fixed `TgoBack.js` to use same-origin `micsNavUrl()` / `micsWsUrl()`. Session/forms auth timeout raised to **60 minutes** (`web.config`, `TloginValidate.aspx.cs` PrefTime default).

**TSIP / SDF trees (30 July 2026):** `callajaxchrome` now unwraps ASMX `d` payloads; `sdfTreeLib.js` uses `micsWsUrl`; TSIP parm/reps trees use local `micsjquery.js` and fixed AJAX callbacks. `TFileOptions.js` batch/report links use `micsWsUrl`.

**Site-wide AJAX/jQuery audit (30 July 2026):**

| Issue | Scope | Fix |
|-------|--------|-----|
| CDN jQuery (`code.jquery.com/jquery`) | 91 `.aspx` pages | Replaced with local `micsjquery.js` |
| `parseJSON(req.responseText)` in `.then()` / `callajaxasync` | Trees, import, FCC/ISED, bulk print, DS save dialogs | `asmxResultValue()` in `Tutils.js`; callbacks use unwrapped `result` |
| `sesSiteName` + path for ASMX URLs | 50+ files (`incDSSDFSave.js`, `dsTSList`, `dsESList`, edit forms, etc.) | `micsWsUrl("…")` |
| `callajaxasync` success handler | `Tutils.js` | Normalizes via `asmxResultValue` before callback |

**Still on CDN (no local copy on server):** jQuery UI JS/CSS (`code.jquery.com/ui/1.12.1`) for dialogs/lookups — core jQuery is local; UI widgets still need CDN or a future local `jquery-ui` deploy.

**Intentionally not migrated:** `RemIcsApi`/fetch pages (validate, export, import, copy, DbUpdate); backup folders under `*_Backup_*`.
