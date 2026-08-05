# Email to Bill — remicsdev AJAX/auth fixes (P0–P2, 29 July 2026)

**Subject:** remicsdev — ES delete, export/import/copy, TSIP, bulk print AJAX fixes (UseDbAuth / same-origin)

**Supplement:** This file is the handoff for syncing Bill’s codebase to the remicsdev server after the second wave of legacy UI fixes (July 2026).

---

Bill,

Following the earlier login, TS delete, and validate fixes, we applied the remaining **P0–P2** changes on **remicsdev** (`http://remicsdev.cloudmicsdev.ca/mics/`). **P3 specialized imports** (FCC/ISED/COMSTS wizards, `dsTSList` / `dsESList`) were **not** changed — those are being handled separately.

---

## Why these changes were needed

Three recurring problems caused “nothing happens”, instant **HTTP 401**, or UI stuck on “in progress” even when the server finished:

1. **Forms auth cookie** — Under `UseDbAuth=true`, the legacy `asp:Login` path did not always persist `.ADAuthCookie`. Fixed earlier in `Tlogin.aspx.cs` with explicit `FormsAuthentication.SetAuthCookie`.

2. **Wrong AJAX host** — Many pages built ASMX URLs from `Session["SiteName"]` / hidden `sesSiteName` (web.config canonical hostname). Users opening the site by **IP** or **internal DNS** sent AJAX to a different host → **401** or CORS-like failures. Fix: `micsWsUrl()` in `includeFiles/Tutils.js` builds URLs from `window.location` (same origin).

3. **Fragile jQuery ASMX callbacks** — `callajaxchrome` + manual `jQuery.parseJSON(req.responseText)` failed silently in iframe/frame layouts (validate was the worst case). Fix for file actions: shared `RemIcsReWrite/remics-api.js` (`fetch` + `credentials: 'include'`) and server-rendered `*_CFG` objects (pattern from `validate.aspx`).

**Not changed (P3 — handled elsewhere):**

- `FCCInfo/*`, `ISEDTSInfo/*`, `ISEDESInfo/*`, `COMSTSInfo/*` import/convert wizards
- `Tdsts/dsTSList.aspx`, `Tdsts/dsESList.aspx`
- `Tpcnmenu/DbUpdate.aspx` and other one-off maintenance pages still using `sesSiteName` for ASMX

---

## Summary of changes by priority

| Priority | Area | Fix |
|----------|------|-----|
| **P0** | ES tree delete | `Tesmenu/esTree.aspx` — all `killTable` + `TwsESTree.asmx/delete_*` calls use `micsWsUrl()` |
| **P1** | Export | `Tfileactions/export.aspx` + `.cs` — `EXPORT_CFG`, `RemIcsApi.exportTable()` |
| **P1** | Import | `Tfileactions/import.aspx` + `.cs` — `IMPORT_CFG`, `RemIcsApi.tableExists/killTable/importTable` |
| **P1** | Copy | `Tfileactions/copy.aspx` + `.cs` — `COPY_CFG`, `RemIcsApi.copyTable/killTable` |
| **P2** | TSIP | `tsipDelete`, `tsipParmTree`, `tsipRepsTree`, `tsipParm*`, `tsipValidation.js`, restored `tsipBatch.aspx` — `micsWsUrl()` |
| **P2** | Bulk print trees | `Tbulkprint/TSPrintTree.aspx`, `ESPrintTree.aspx` — `micsWsUrl()` |
| **Shared** | API helper | `RemIcsReWrite/remics-api.js` — `tableExists`, `copyTable`, filetype options on kill/export/import |
| **Validate** | File menu + JobSubmit + UI | `TFileOptions.js` passes `valType`; `JobSubmit` exit codes; `validate.aspx` report poll + ReadOnly session |

---

## Validate fixes (29 July 2026 — after P0–P2)

Discovered while validating ES file **`isedess23b`**: batch finished in ~2s but UI appeared hung.

| Bug | Fix |
|-----|-----|
| `fileToValidate()` omitted `valType` → ES files validated as TS (`ftValidate` looks for PDF) | `TFileOptions.js` — append `&valType=` + `parent.txtsType` |
| UseDbAuth `Process.Start` path treated any non-zero validate exit as `logerrorcode = -1` → `valFile` returned `ERROR:…` instead of report filename | `utilities/JobSubmit.cs` — `SubmitJobViaProcessStart` applies same `ftValidate`/`feValidate` special case as AD path |

Full write-up: [validate-useDbAuth-fix.md](validate-useDbAuth-fix.md)

---

## File-by-file change list

Paths are under **`D:\inetpub\remicsdev\mics\`** (IIS web source).

### Shared helpers

| File | Change |
|------|--------|
| `includeFiles/Tutils.js` | *(earlier)* `micsWsUrl()`, `asmxResult()`, `withCredentials` on AJAX helpers |
| `RemIcsReWrite/remics-api.js` | Added `tableExists`, `copyTable`; `killTable` / `exportTable` / `importTable` accept `{ filetype }` option |
| `includeFiles/TFileOptions.js` | `fileToValidate()` passes `valType` from `parent.txtsType` on validate URL |
| `utilities/JobSubmit.cs` | `SubmitJobViaProcessStart` — `ftValidate`/`feValidate` non-zero exits → `logerrorcode = 0` (match AD path) |
| `Tfileactions/validate.aspx` | ReadOnly session; report poll fallback; `syncFileTypeFromParent`; marquee replaces RadTicker |
| `includeFiles/Tutils.js` | `resetValidateUi()` uses `getElementById` for validate panels |

### P0 — ES tree

| File | Change |
|------|--------|
| `Tesmenu/esTree.aspx` | Replace `document.getElementById("sesSiteName").value + "…"` with `micsWsUrl("…")` for `killTable` and all `TwsESTree.asmx/delete_es_*` endpoints |

### P1 — Export / import / copy

| File | Change |
|------|--------|
| `Tfileactions/export.aspx` | Include `remics-api.js`; `EXPORT_CFG`; `exportFile1()` uses `RemIcsApi.exportTable()` |
| `Tfileactions/export.aspx.cs` | `JsFileName`, `JsProjectCode`, `JsFileType` for `EXPORT_CFG` |
| `Tfileactions/import.aspx` | Include `remics-api.js`; `IMPORT_CFG`; duplicate check, overwrite kill, and import via `RemIcsApi`; `startUpload()` helper |
| `Tfileactions/import.aspx.cs` | `JsProjectCode` for `IMPORT_CFG` |
| `Tfileactions/copy.aspx` | Include `remics-api.js`; `COPY_CFG`; copy and pre-delete via `RemIcsApi` |
| `Tfileactions/copy.aspx.cs` | `JsOldName`, `JsNewName`, `JsFileType`, `JsProjectCode` for `COPY_CFG` |

### P2 — TSIP

| File | Change |
|------|--------|
| `Ttsipmenu/tsipDelete.aspx` | `micsWsUrl("Ttsipmenu/TwsTsip.asmx/tsipDelete")` |
| `Ttsipmenu/tsipParmTree.aspx` | All `TwsTsipTree.asmx/*` and `killTable` URLs → `micsWsUrl()` |
| `Ttsipmenu/tsipRepsTree.aspx` | All tree/copy/delete/killTable URLs → `micsWsUrl()` |
| `Ttsipmenu/tsipParm.aspx` | `tsipValidate` URL → `micsWsUrl()` |
| `Ttsipmenu/tsipParmNew.aspx` | `tsipValidate` URL → `micsWsUrl()` |
| `Ttsipmenu/tsipParmDup.aspx` | `tsipValidate` URL → `micsWsUrl()` |
| `Ttsipmenu/tsipValidation.js` | `tsipValidate` URL → `micsWsUrl()` |
| `Ttsipmenu/tsipBatch.aspx` | **Restored** from backup (file was missing on server); `tsipValidateAll` / `tsipRun` → `micsWsUrl()` |

### P2 — Bulk print

| File | Change |
|------|--------|
| `Tbulkprint/TSPrintTree.aspx` | All `TwsBulkTree.asmx/*` URLs → `micsWsUrl()` |
| `Tbulkprint/ESPrintTree.aspx` | All `TwsBulkTree.asmx/*` URLs → `micsWsUrl()` |

### Earlier fixes (same effort — include when syncing)

| File | Change |
|------|--------|
| `Tlogin.aspx.cs` | `FormsAuthentication.SetAuthCookie` on UseDbAuth login path |
| `Ttsmenu/tsTree.aspx` | TS `killTable` + tree ASMX → `micsWsUrl()` |
| `Tfileactions/validate.aspx` + `.cs` | `VALIDATE_CFG`, `RemIcsApi.valFile()` |
| `RemIcsReWrite/*` | Harness for login / delete / export / validate testing |

---

## Build and deploy steps

On the IIS server (as admin):

```powershell
# Rebuild file-action code-behind (export/import/copy .cs changes)
& "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe |
  ForEach-Object { & $_ 'D:\inetpub\remicsdev\mics\Tfileactions\Tfileactions.csproj' /p:Configuration=Release }

# Rebuild JobSubmit (validate exit-code fix under UseDbAuth)
& "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe |
  ForEach-Object { & $_ 'D:\inetpub\remicsdev\mics\utilities\utilities.csproj' /p:Configuration=Release }

# Recycle app pool
Import-Module WebAdministration
Restart-WebAppPool remicsdevapp
```

Most changes are `.aspx` / `.js` only — DLL rebuilds needed for `Tfileactions.dll` (export/import/copy code-behind) and **`utilities.dll`** (JobSubmit validate exit codes).

---

## Suggested smoke tests after merge

1. Login as `rctl1` (or your test user) — confirm `.ADAuthCookie` in browser devtools.
2. **ES tree** — delete an ES file and a child site/antenna/channel record.
3. **Export** — export a TS file; confirm download opens and file is complete.
4. **Import** — import a `.txt` as a new name; confirm success path.
5. **Copy** — copy TS file to new name (with and without overwrite).
6. **TSIP** — open parameter tree, delete a run, submit batch TSIP (if used).
7. **Bulk print** — open TS and ES print trees; expand nodes (confirms tree ASMX calls).
8. **Validate ES file** — from ES tree, validate an ES file; URL must include `valType=ES`; submit log should show `feValidate`; UI reaches “Display Results” even when report lists errors.

Optional harness (no frames): `http://remicsdev.cloudmicsdev.ca/mics/RemIcsReWrite/login.aspx`

---

## Pattern for future pages

When adding or fixing AJAX to ASMX services:

```javascript
// Prefer same-origin URL (works for IP, DNS, or canonical hostname):
var wsUrl = micsWsUrl("Tfileactions/TwsTabUtil.asmx/killTable");

// For TwsTabUtil file ops in iframes, prefer:
RemIcsApi.killTable(filename, projectCode, { filetype: "TS" })
  .then(function (r) { if (!r.ok) { alert(r.error || r.body); return; } /* use r.body */ });
```

Server-render stable values in code-behind when parent frame variables are unreliable:

```aspx
window.VALIDATE_CFG = { fileName: "<%= JsFileName %>", projectCode: "<%= JsProjectCode %>" };
```

---

## Questions / follow-up

- If Bill’s tree still uses `sesSiteName` for navigation (not ASMX), that is OK — only **AJAX POST targets** needed changing.
- P3 FCC/ISED/COMSTS flows: coordinate separately before changing production import wizards.
- After Bill merges, run the smoke tests above on **the hostname users actually use** (not only `remicsdev.cloudmicsdev.ca`).

---

*CentralProject docs hub: `E:\AIProjects\CentralProject\docs\remicsdev\`*
