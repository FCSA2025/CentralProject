# Known bugs / open risks — remicsdev (2026-09-03)

**Status after:** Path B Waves 0–4 complete; UI discoverability U1–U3 complete; P2 batch-mapping fake bugs retired from UI.

This is the **remaining** list. Deprecated / unwired batch names (`Dummy`, `esImport`/`esPrint`, `updatedb`, `pl5Import`, `BatchApp`, `testdefaultschema`, `wTerrex`, `SQLtoFlat`) are **not** product bugs — see [batch-programs.md](batch-programs.md).

---

## Product / code bugs

| ID | Sev | Item | Status |
|----|-----|------|--------|
| **B1** | P1 | **Antenna RPE / DS Ante save dropped discrimination** | **Fixed 2026-09-08** — `SDF_SAVE.Ante` now calls `InsertAntd` / `DeleteAntd` like classic `dsAnteList.aspx` |
| **B2** | P1 | **CTX File (and Plan/Note/Rout/Town/Traf) SDF save used single key only** | **Fixed 2026-09-08** — classic Insert* expects colon composites (Ctx=`tfci:tfcr:rxeqp`); rewrite now sends `keyParts` / `dsSdfRowKey` (cache `2026090802`) |
| **B3** | P1 | **TS Data Search save used comma link/OE keys instead of `}`** | **Fixed 2026-09-08** — classic `dsTSList` uses `call1}call2}bndcde`; rewrite sent commas + trailing `}}`, breaking `SaveKeysLocal`→`StoreKeys` (cache `2026090803`) |
| **B4** | P2 | **Aux Eng Passive Calculations rejected common lat/long forms** | **Fixed 2026-09-08** — rewrite required full `DD-MM-SSN`; classic `parseLL` allows optional seconds/sense (e.g. `45-30N`). Also `pasVal` skipped disabled fields. Cache `2026090804`. |
| **B5** | P1 | **Aux Eng PFD Contours reports never emailed** | **Fixed 2026-09-08** — `MicsEmail.Send()` built a broken SQL string and never INSERTed/SMTP’d; remicsdev needs `adm.t_EmailQueue_local`. Restored `SendSql` + staging (TsipEmail contract); deployed `_Utillib.dll` + `PFDcont.exe.config`. |
| **B6** | P2 | **ES Data Search save missing classic 100-key StoreKeys chunking** | **Fixed 2026-09-08** — `saveEs` now builds classic `.`-delimited blocks (dot before every 100th key), `ClearCulls` once, then `StoreKeys` per block; checked sites only. Cache `2026090805`. Smoke: `scripts/Invoke-B6EsChunkSmoke.ps1` → 12/12 (101→2 blocks, 249→3 blocks, rctl1 + xci1). |
| **B7** | P2 | **ES cull temp tables missing on some company schemas** | **Fixed 2026-09-08** — created `cull_temp{1,2,3}_es` for aliant, bchy, bell, bmce, bragg, dnd, tbay, tels, terago (`ddl/b7-create-es-cull-temp-tables.sql`). Same day also provisioned TS `cull_temp{1,2,3}` (`ddl/b7-create-ts-cull-temp-tables.sql`). Verify: `Invoke-B7EsCullVerify.ps1` (bchy1 101 ES) + `Invoke-B7TsCullVerify.ps1` (bchy1 20-link TS). |
| **C1** | P2 | **SDF childNew/ChildSave allowed orphan detail rows** | **Fixed 2026-09-09** — Ante/Ctx/Plan child save requires valid parent key + existing parent row (`sdf-edit.ashx`). |
| **C2** | P2 | **TS/ES DS save could report success after failed/expired ASMX** | **Fixed 2026-09-09** — `callAsmxPath` throws on any `!ok` (incl. expired); `remics-ds.js` `dsAsmxOk` on save chains. Cache `2026090902`. |
| **D1** | P2 | **ES azimuth Delete missing in rewrite** | **Fixed 2026-09-09** — `pdf-edit.ashx` `azimDelete` + Azimuths list/form **Delete**; cache `2026090903`. Also Delete buttons on site/ante/chan/SDF/Aux Eng (beyond classic). See [rewrite-delete-options-audit.md](rewrite-delete-options-audit.md). |
| **E1** | P2 | **Import UI shows IMPORT COMPLETE after failure** | **Fixed 2026-09-09** — failure sets title to **IMPORT FAILED**; success keeps COMPLETE. Cache `2026090904`. |
| **E2** | P3 | **SDF Validate status says “Validate OK” with errors possible** | **Fixed 2026-09-09** — fetches report, parses error/warning counts, opens report. Cache `2026090904`. |
| **E3** | P3 | **PDF TitleSave ok on 0-row UPDATE** | **Fixed 2026-09-09** — `TitleSave` fails when `ExecuteNonQuery() == 0`. |
| **E4** | P1 | **SDF Note key order inverted vs classic tree** | **Fixed 2026-09-09** — Note keys `nonum^oper` in `sdf-edit.ashx` + `remics-sdf-types.js`. Cache `2026090904`. |

**Audit (2026-09-08):** SDF save contracts 11/11 + remaining areas (TS `}` keys, ES locations, Ante/Ctx/Plan detail rows) — see [ds-sdf-save-parity-audit.md](ds-sdf-save-parity-audit.md) and `scripts/Invoke-DsRemainingAreasSmoke.ps1`.

**Delete-options audit (2026-09-09, document only):** [rewrite-delete-options-audit.md](rewrite-delete-options-audit.md) — TS/ES/SDF file+record delete mostly parity via right-click; Aux Eng has no catalogue delete (same as classic); SDF hint underplays Delete (**D2**); only confirmed functional gap is **D1** (ES azimuth).

**Delete UX ship (2026-09-09):** Buttons + missing deletes — **D1** fixed; SDF/TS/ES **Delete selected** / Delete file·record buttons; pdf-edit Delete on site/ante/chan/azim (+ list Del); Aux Eng Gen CTX Ctx-file Delete; ds-sdf Delete file; HiLo Delete file. Cache `2026090903`.

**Identify/verify follow-up (2026-09-08):** script `scripts/Invoke-DsBugHuntIdentifyVerify.ps1` → `tmp-tsjob/ds-bug-hunt-2026-09-08.json`.

| Area | Verdict |
|------|---------|
| TS full save E2E (site+link+OE → InsertPDF* + dup keep) | **Cleared** (`rctl1`) |
| ES small save E2E | **Cleared** (`rctl1`) |
| ES StoreKeys 100-key `.` chunks | **B6 fixed** — chunked StoreKeys; smoke 12/12 |
| `owhere` `<`→`^`→`<` (TS/ES filtered) | **Cleared** |

---

## Ops / environment risks (can look like bugs)

| ID | Sev | Item | Notes |
|----|-----|------|-------|
| **O2** | P1 | **User Tables Reconcile freshness** | SQL Agent job **enabled**; Gate F failed earlier today with `reconcile_stale=1` until a manual run. Watch nightly 02:30 → Gate F 03:15. Doc: [user-tables-reconcile.md](user-tables-reconcile.md). |
| **O3** | P2 | **Source vs develbat binary drift** | Procedure documented. `_Utillib` redeployed 2026-09-08 for B5 (PFD email). Still watch `TpRunTsip` / other binaries. Doc: [source-vs-binary-drift-check.md](source-vs-binary-drift-check.md). |

~~**O1 (retired 2026-09-08):** GPO “Domain Users Allow log on locally / batch” — not a remicsdev product goal. Prefer batch under service accounts (`IISReMicsSer` / UseDbAuth). Live rights currently fine; interactive user logon on IIS is undesirable.~~

---

## Test / coverage gaps (not confirmed defects)

| ID | Item | Notes |
|----|------|-------|
| **T1** | Optional Wave-3 gate assertions | Empty CASEDET / blank `proname` / DS scrub — listed open in Wave 4 audit, outside W4 IDs |
| **T2** | Full batch web test suite | Playwright / ASMX smoke still not started ([TODO.md](../TODO.md)) |
| **T3** | Multi-company Gate G ongoing | Roster discipline remains a process requirement, not an open code bug |

---

## Deferred product work (not bugs)

- TSIP archive **Phase 4** (read/print/email from DB)
- Disk write reduction Stages 1–5
- FCSA HTTPS / DNS cutover
- Path A interior polish / Path C feature expansion (abandoned for now)

---

## UI retired this session (2026-09-03)

| Item | Action |
|------|--------|
| Tools → SQL to Flat File | Hidden from classic nav; `BuildTask.aspx` + `SqlFlat` say not available |
| Aux Eng → Area Coordination | Hidden from classic nav (was alert-only) |
| DocMenu → Test Def Schema | Button removed |
| Pathloss import (`PL`) | Already off menu; ASMX returns not available |
| RemIcsReWrite | Already omitted the above |

---

## How to re-verify

```powershell
.\scripts\Invoke-GateFRegressionTest.ps1
.\scripts\Invoke-GateCTsipE2ETest.ps1
.\scripts\Invoke-GateCTsipRepsEditTest.ps1
.\scripts\verify-batch-mapping.ps1   # still lists dead strings until source hygiene
```
