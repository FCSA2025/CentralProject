# Email draft — Si Ke MDB site fetch review

**To:** Si Ke  
**Cc:** Simin Bekhsat  
**Subject:** Review of MtGetSiteWN2 / MDB site fetch changes

---

Hi Si,

Thank you for sending the detailed write-up on `MtGetSiteWN2` and the companion `*2` fetch helpers. We reviewed your proposal against the code on our remicsdev server (paths below) and against how TSIP actually invokes the MDB site path. This email summarizes our findings, issues we found in the proposed implementation, and a smaller alternative we are considering.

**Note:** Your code is on your machine; ours is on remicsdev. We are not comparing line-for-line against your repo — we are reviewing the design and the snippets you sent against our deployed source tree:

- `D:\MicsBatchProgs\MicsBat\_Utillib\` — `MtUtils.cs`, `DynMdbSite.cs`, `DynMdbAntenna.cs`, `DynMdbChannel.cs`
- `D:\MicsBatchProgs\MicsBat\TpRunTsip\TpMdbPdfGet.cs`
- Runtime: `D:\develbat\TpRunTsip.exe` + `D:\develbat\_Utillib.dll`

---

## 1. What we agree with

Your core observation is sound: the **non-MDB** path (`FtGetSiteWN`) and the **MDB** path (`MtGetSiteWN`) use different ODBC patterns.

The working FT path (`FtUtils.FtGetSiteWN`) does this:

- Opens one connection for the full site + antenna + channel read
- Allocates a **per-phase** statement handle
- Stores the real handle in `cursors[n].hStmt`
- Fetches columns with manual `Ssutil.DbGet*` calls
- Explicitly frees the statement handle after each phase

Our current MDB path (`MtUtils.MtGetSiteWN`) uses `DynMdbSite.MtSelectSite` / `MtFetchSite`, which rely on a **static reusable** `mhStmt`, column bindings (`ReadColBindings`), and cursor bookkeeping that does not mirror the FT path.

Aligning MDB behavior with the proven FT pattern is a reasonable direction.

---

## 2. Where TSIP enters (current code)

`TtFullSiteGet` in `TpMdbPdfGet.cs` branches on `isMDB`:

```csharp
// TpMdbPdfGet.cs, lines 863-875
if (isMDB)
{
    nRet = MtUtils.MtGetSiteWN(cCallSign, out pMtSite, 3, out pMtNulls);
    if (nRet == 0)
    {
        MtUtils.MtToFtWN(out pSite, out siteNulls, pMtSite, pMtNulls);
    }
}
else
{
    nRet = FtUtils.FtGetSiteWN(cCallSign, out pSite, 3, tabName, out siteNulls);
}
```

Your change replaces `MtGetSiteWN` with `MtGetSiteWN2` here. That is the right integration point, but the new function needs to be correct and buildable against our tree.

---

## 3. Issues in the proposed MtGetSiteWN2 (fixes to your fixes)

### 3.1 `Ssutil.NewConn(true)` does not exist

Your code calls:

```csharp
hConnection = Ssutil.NewConn(true);
```

Our `Ssutil` only exposes a parameterless method:

```csharp
// Ssutil.cs, line 440
public static SQLHDBC NewConn()
```

**Fix:** Use `Ssutil.NewConn()` with no argument, matching `FtGetSiteWN` (line 867 in `FtUtils.cs`).

---

### 3.2 Contiguity / `magicNumber` not set before `MtFetchSite2`

Your new `MtFetchSite2` (and `MtFetchAntenna2` / `MtFetchChannel2`) still enforce the contiguity check from the original fetch methods:

```csharp
if (cursors[nCursor].magicNumber != mMagicNumber)
{
    Log2.e("... failed contiguity test.");
    return -666;
}
```

In the **existing** design, `MtSelectSite` increments and assigns this:

```csharp
// DynMdbSite.cs, lines 255-262
mMagicNumber++;
cursors[curHandle].magicNumber = mMagicNumber;
```

Your `MtGetSiteWN2` bypasses `MtSelectSite` and calls `GetNextFreeCursor()` directly, but **never** increments `mMagicNumber` or sets `cursors[nSiteCursor].magicNumber` before calling `MtFetchSite2`.

**Fix (if keeping `MtFetchSite2`):** After `SQLExecDirect` succeeds on the site query, add:

```csharp
DynMdbSite.mMagicNumber++;   // if not accessible, add a small helper
DynMdbSite.cursors[nSiteCursor].magicNumber = DynMdbSite.mMagicNumber;
DynMdbSite.cursors[nSiteCursor].cursorOpen = true;
```

Apply the same pattern for antenna and channel cursors (each Dyn class has its own `mMagicNumber`).

**Better fix:** Drop the contiguity check from the `*2` fetch methods entirely when they are only used with a caller-managed `hStmt` (same as `DynSite.FtFetchSite`, which checks `cursorOpen` but not `magicNumber`).

---

### 3.3 Site cursor: `cursorOpen` not set explicitly

For antenna and channel you set:

```csharp
DynMdbAntenna.cursors[nAnteCursor].cursorOpen = true;
```

For the **site** phase you only assign `hStmt`. `MtFetchSite2` requires `cursorOpen`:

```csharp
if (!cursors[nCursor].cursorOpen)
    return (Error.DYN_CUR_NOT_OPEN);
```

`GetNextFreeCursor()` does set `cursorOpen = true`, so this may work on a fresh cursor — but it is inconsistent with your antenna/channel setup and fragile if a cursor slot is reused.

**Fix:** Explicitly set `cursorOpen = true` on the site cursor after assigning `hStmt`.

---

### 3.4 Duplicating entire fetch bodies

Adding parallel `GetSelectString`, `DbCountRows2`, `MtFetchSite2`, `MtFetchAntenna2`, and `MtFetchChannel2` duplicates hundreds of lines already present in `MtFetchSite` / `MtFetchAntenna` / `MtFetchChannel` (via `ReadColBindings`).

**Fix:** Prefer one of:

- **Option A (minimal):** Fix `MtCloseSite` / `MtCloseAntenna` / `MtCloseChannel` to close the ODBC cursor on `mhStmt` (see section 4 below) and keep existing fetch methods.
- **Option B (your direction, done once):** Refactor `MtGetSiteWN` internally to follow the `FtGetSiteWN` structure, reusing `DynSite`-style per-handle fetch logic without a parallel `*2` API surface.

---

### 3.5 Copy-paste logging and error strings

Several log lines still say `FtUtils.FtGetSiteWN` inside `MtGetSiteWN2`. The channel error path uses `nNumAnts` in the format string where `nNumChan` is intended — this same typo exists in our current code:

```csharp
// MtUtils.cs, lines 314-315 (existing bug)
Log2.e("... DbCountRows() returned nNumChan = " + nNumChan);
string str = String.Format("mtGetSiteWN03: Ingres error {0} getting channels.", nNumAnts);
```

**Fix:** Use `nNumChan` in the format string and correct log prefixes to `MtUtils.MtGetSiteWN2`.

---

### 3.6 Error paths that omit `Ssutil.DisConn(hConnection)`

Some failure branches in your antenna/channel sections return without disconnecting when `nDepth` is 3 and an earlier phase succeeded. Mirror `FtGetSiteWN`'s pattern: every exit after `NewConn()` should either reach a final `DisConn` or disconnect on the error branch.

---

## 4. Underlying issue in our current code (what you were likely hitting)

Even without your rewrite, our existing MDB layer has a real lifecycle gap.

### `MtCloseSite` does not close the statement cursor

```csharp
// DynMdbSite.cs, lines 368-387
public static int MtCloseSite(int curHandle)
{
    ...
    Ssutil.DisConn(cursors[curHandle].hConn);  // hConn is always Zero — see MtSelectSite
    cursors[curHandle].hConn = IntPtr.Zero;
    cursors[curHandle].cursorOpen = false;
    return 0;
}
```

The comment on line 192 of `MtUtils.cs` says this "closes hStmt and hConn", but it does not. Cursor cleanup on `mhStmt` is deferred to the **next** `MtSelectSite` call:

```csharp
// DynMdbSite.cs, line 221
sqlRet = ODBC.SQLFreeStmt(mhStmt, ODBC.SQL_CLOSE);
```

Meanwhile `MtSelectSite` discards the connection handle:

```csharp
// DynMdbSite.cs, lines 260-261
cursors[curHandle].hStmt = SQLHANDLE.Zero;
cursors[curHandle].hConn = SQLHANDLE.Zero;
```

…but `MtFetchSite` fetches from static `mhStmt`, not `cursors[n].hStmt`:

```csharp
// DynMdbSite.cs, line 303
SQLRETURN sqlRet = ODBC.SQLFetch(mhStmt);
```

Compare to the FT path, which stores the real handle:

```csharp
// FtUtils.cs, lines 956-957
int nDynSiteCursor = DynSite.GetNextFreeCursor();
DynSite.cursors[nDynSiteCursor].hStmt = hStmt;
```

This architectural mismatch is a plausible root cause for intermittent `Marker G-2` / invalid cursor state under TSIP load. Your instinct to mirror `FtGetSiteWN` is aligned with this analysis.

### Minor existing typo (not your introduction)

```csharp
// MtUtils.cs, line 177
SQLLEN[] nullInd = NullHelper.CreateArrayOfNullInd(MtAnte.NUM_COLUMNS, ...);
```

Should be `MtSite.NUM_COLUMNS` (33, not 36). Harmless today because `nullInd` is an `out` parameter overwritten by `MtFetchSite`, but misleading.

---

## 5. What we tested on remicsdev

We ran three MDB_TS TSIP reruns (`ecomm2602`, `ecomm2601`, `ecomm2601b`) with `envtype = MDB_TS`. All completed with 7 interference cases and no `Marker G-2` or `TtFullSiteGet` failures in the ERR files. So the bug appears **intermittent or environment-specific** on our server — but the structural ODBC issues above remain worth fixing.

We also confirmed our deployed `_Utillib.dll` contains `MtGetSiteWN` and does **not** contain `MtGetSiteWN2` / `MtFetchSite2` (your symbols are not in our runtime build).

---

## 6. Our recommended path forward

**Short term (Option A):** Minimal fix in existing `DynMdbSite` / `DynMdbAntenna` / `DynMdbChannel`:

```csharp
// Add to MtCloseSite before cursorOpen = false:
if (mhStmt != SQLHANDLE.Zero)
{
    ODBC.SQLFreeStmt(mhStmt, ODBC.SQL_CLOSE);
}
```

Same pattern for `MtCloseAntenna` and `MtCloseChannel`. No new `*2` methods; no change to `TtFullSiteGet` call sites.

**Medium term (Option B):** If Option A does not stabilize behavior, refactor `MtGetSiteWN` to follow the `FtGetSiteWN` structure in one place — with the fixes in section 3 applied — rather than maintaining duplicate fetch implementations.

---

## 7. Request

If you would like to revise the proposal:

1. Fix items 3.1–3.3 and 3.5–3.6 above.
2. Send an updated diff focused on `MtGetSiteWN` (or `MtGetSiteWN2`) only — we can review integration with `TtFullSiteGet` separately.
3. Let us know what symptom you observed (error text, log marker, callsign, `envtype`) so we can try to reproduce on remicsdev.

Happy to schedule a short call if it is easier to walk through the ODBC cursor flow.

Thanks again for the thorough analysis.

Best regards,  
Jason

---

## Reference — file paths on remicsdev

| Item | Path |
|------|------|
| TSIP entry | `D:\MicsBatchProgs\MicsBat\TpRunTsip\TpMdbPdfGet.cs` |
| MDB site fetch | `D:\MicsBatchProgs\MicsBat\_Utillib\MtUtils.cs` (`MtGetSiteWN`, ~line 105) |
| MDB Dyn site | `D:\MicsBatchProgs\MicsBat\_Utillib\DynMdbSite.cs` |
| FT reference | `D:\MicsBatchProgs\MicsBat\_Utillib\FtUtils.cs` (`FtGetSiteWN`, ~line 837) |
| Runtime | `D:\develbat\TpRunTsip.exe`, `D:\develbat\_Utillib.dll` |

Internal docs: `docs/remicsdev/mdb-site-fetch-bug-analysis.md`, `docs/remicsdev/mdb-site-fetch-fix-plan-option-a.md`
