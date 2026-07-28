# MDB site fetch fix — Option A (minimal cursor cleanup)

**Status:** Planned (not implemented)  
**Prerequisite:** [mdb-site-fetch-bug-analysis.md](mdb-site-fetch-bug-analysis.md)  
**Approach:** Fix the existing `DynMdbSite` / `DynMdbAntenna` / `DynMdbChannel` cursor lifecycle without adding parallel `*2` functions or replacing `MtGetSiteWN`.

---

## Goal

Make the MDB ODBC path reliable by ensuring statement cursors are **closed when `MtClose*` is called**, matching what callers (and comments) already expect — without changing `TtFullSiteGet`, `MtGetSiteWN` call sites, or the `ReadColBindings` fetch model.

---

## Scope

| In scope | Out of scope |
|----------|--------------|
| `DynMdbSite.MtCloseSite`, `MtSelectSite` | Si's `MtGetSiteWN2` / `MtFetch*2` duplication |
| `DynMdbAntenna.MtCloseAntenna`, `MtSelectAntenna` | Refactor to full `FtGetSiteWN` pattern (Option B) |
| `DynMdbChannel.MtCloseChannel`, `MtSelectChannel` | Changes to `TtFullSiteGet` or TSIP callers |
| Verify with existing TSIP regression (`Invoke-LastTsipCompare.ps1`) | Production promotion |

**Source trees to edit (when approved):**

- `D:\inetpub\remicsdev\mics\_Utillib\DynMdbSite.cs`
- `D:\inetpub\remicsdev\mics\_Utillib\DynMdbAntenna.cs`
- `D:\inetpub\remicsdev\mics\_Utillib\DynMdbChannel.cs`
- Mirror copies under `D:\MicsBatchProgs\MicsBat\_Utillib\` if batch rebuild is required

---

## Changes

### 1. `MtCloseSite` — actually close the static statement cursor

**File:** `DynMdbSite.cs`

**Current behavior:** Sets `cursorOpen = false`; calls `DisConn(Zero)`; leaves `mhStmt` result set open.

**Planned behavior:**

```csharp
// In MtCloseSite, before clearing cursorOpen:
if (mhStmt != SQLHANDLE.Zero)
{
    ODBC.SQLFreeStmt(mhStmt, ODBC.SQL_CLOSE);
}
cursors[curHandle].cursorOpen = false;
// Do not DisConn(Zero) — connection is process-wide singleton via NewConn()
```

**Notes:**

- `SQLFreeStmt(SQL_CLOSE)` is already used at the start of `MtSelectSite`; this makes close explicit at end-of-use.
- Do **not** `SQLFreeHandle` on `mhStmt` in `MtCloseSite` — it is reused across selects; only close the cursor.

### 2. `MtSelectSite` — store connection handle on cursor (optional but recommended)

**Current:** `hConn = NewConn()` then `cursors[curHandle].hConn = Zero`.

**Planned:**

```csharp
cursors[curHandle].hConn = hConn;  // singleton handle, for diagnostics/future DisConn if needed
cursors[curHandle].hStmt = mhStmt;  // document real stmt used by MtFetchSite (was Zero)
```

This does not change fetch logic (`MtFetchSite` still uses `mhStmt`) but makes cursor state truthful and aids debugging.

### 3. Mirror fixes in `DynMdbAntenna` and `DynMdbChannel`

Apply the same `SQLFreeStmt(SQL_CLOSE)` in:

- `MtCloseAntenna` / `MtSelectAntenna`
- `MtCloseChannel` / `MtSelectChannel`

Each class has its own static `mhStmt`; close on `MtClose*` for that class.

### 4. Cosmetic fix in `MtUtils.MtGetSiteWN` (optional, same PR)

Line ~177: change `MtAnte.NUM_COLUMNS` → `MtSite.NUM_COLUMNS` for the pre-allocated `nullInd` array (dead code today, but misleading).

---

## Test plan

### Before merge

1. Build `mics` / `MicsBat` assemblies that contain the Dyn changes (per [source-layout.md](source-layout.md)).
2. Copy rebuilt `_Utillib` DLL to `D:\develbat\` if TSIP exe loads it from there.

### Regression

Run at least three MDB_TS TSIP reruns via existing harness:

```powershell
.\scripts\Invoke-LastTsipCompare.ps1 -BaselineRunId 40 -Json   # ecomm2602
.\scripts\Invoke-LastTsipCompare.ps1 -BaselineRunId 39 -Json   # ecomm2601
.\scripts\Invoke-LastTsipCompare.ps1 -BaselineRunId 38 -Json   # ecomm2601b
```

**Pass criteria:**

- `new_num_int_cases` equals baseline
- `calc_mismatches = 0`
- No new log lines: `Marker G-2`, `failed contiguity test`, `Invalid cursor state`
- Archive row counts for `site` / `ante` / `chan` unchanged

### Targeted ODBC stress (optional)

If intermittent bug is suspected, add a small test harness that:

1. Calls `MtSelectSite` + `DbCountRows` + `MtFetchSite` in a loop (1000×) for a known `call1`
2. Interleaves `MtEnumSite` between iterations (simulates TSIP victim enumeration)

Failure rate before vs after fix documents improvement.

---

## Rollback

Revert the three `DynMdb*.cs` files and rebuild. No database or config changes.

---

## Why Option A first

- Smallest diff; preserves Bill's existing `ReadColBindings` model
- Addresses the most likely failure mode (open cursor on static `mhStmt`)
- Avoids Si's `magicNumber` / `NewConn(true)` defects
- If failures persist after Option A, escalate to Option B (full `FtGetSiteWN` alignment for `MtGetSiteWN`)
