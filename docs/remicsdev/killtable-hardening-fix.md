# KillTable delete hardening (remicsdev, 2026-07-28)

**Status:** Applied and verified on remicsdev

Follow-up to [KillTable delete bug (UseDbAuth)](killtable-delete-bug.md). Addresses the “worked briefly then failed again” behavior.

---

## Problems addressed

| Issue | Symptom | Root cause |
|-------|---------|------------|
| Exit **7** on re-delete | Same system-error popup after a successful delete | `DROP TABLE` without `IF EXISTS`; missing tables treated as fatal |
| Exit **-532462766** (CLR crash) | Web delete fails while CLI works | `CheckDebugSetting()` called `cn.Open()` without catch when `odbc` env missing |
| Env vars not reaching batch | Intermittent web failures | `Process.Start` under IIS did not reliably inherit `Environment.SetEnvironmentVariable` |
| Broken catalog view | `web.user_tables_view` always empty | View corrupted to `WHERE operator = d` (invalid predicate) |

The original **`user_schema2022` / `t_UserDetails` fix remains in place** (exit code 2).

---

## Changes made

### 1. SQL: repair `web.user_tables_view`

**Script:** [`scripts/remicsdev/fix-user_tables_view.sql`](../../scripts/remicsdev/fix-user_tables_view.sql)

Recreated the view as a pass-through of `web.user_tables` (no `USER` filter). Required for **UseDbAuth** because the app pool login is `IISReMicsSer`, not the MICS user.

**Before:** 0 rows from view; 1,454 rows in base table for `rctl`  
**After:** view count matches base table for `rctl`

AD/production sites that rely on row-level filtering should use the commented AD variant in the script (`WHERE operator = RTRIM(dbo.user_schema2022(USER))`).

### 2. `KillTable.exe` hardening

**Source (edited):**

- `D:\MicsBatchProgs\MicsBat\KillTable\Program.cs`
- `D:\inetpub\remicsdev\KillTable\Program.cs` (mirror)

**Deployed:** `D:\develbat\KillTable.exe` (Release build, 2026-07-28)

| Change | Detail |
|--------|--------|
| Idempotent drops | `IF OBJECT_ID(...) IS NOT NULL DROP TABLE ...` plus `IsMissingTableError()` fallback |
| Schema lookup | Handle `DBNull`/empty from `user_schema2022`; return **3** instead of throwing |
| `CheckDebugSetting` | Wrap `cn.Open()` in try/catch; return 0 if ODBC unavailable |

**Verify (CLI):**

```powershell
# Re-delete of already-removed file should exit 0
$env:MicsUser='rctl1'; $env:odbc='remicsdev'; $env:webdrive='D:'
D:\develbat\KillTable.exe remicsdev TS fox rctl1_0
```

### 3. `JobSubmit` — explicit batch environment (UseDbAuth)

**Source:** `D:\inetpub\remicsdev\mics\utilities\JobSubmit.cs`

**Deployed:** `D:\inetpub\remicsdev\mics\bin\utilities.dll` (Release build)

Added `ApplyBatchEnvironment(ProcessStartInfo)` to copy `MicsUser`, `odbc`, `Password`, `work_dir`, etc. onto `ProcessStartInfo.EnvironmentVariables` before `Process.Start`.

IIS app pool **`remicsdevapp` was recycled** after deploy.

**Verify (web):**

- POST `Tfileactions/TwsTabUtil.asmx/killTable` for `fox` → `{"d":"fox"}`
- Repeat POST (re-delete) → still `{"d":"fox"}` (exit 0 in `remicsdev_rctl1submit5.txt`)

---

## Rebuild commands (reference)

```powershell
# KillTable → D:\develbat\KillTable.exe
& "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe" `
  "D:\MicsBatchProgs\MicsBat\KillTable\KillTable.csproj" /p:Configuration=Release /p:Platform=AnyCPU

# utilities.dll → D:\inetpub\remicsdev\mics\bin\
& "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe" `
  "D:\inetpub\remicsdev\mics\utilities\utilities.csproj" /p:Configuration=Release /p:Platform=AnyCPU

& "$env:windir\system32\inetsrv\appcmd.exe" recycle apppool "remicsdevapp"
```

---

## Diagnostics

| Symptom | Check |
|---------|--------|
| Exit **7** | `D:\extractlogs\remicsdev_{user}submit5.txt` — pre-hardening: missing table on `DROP` |
| Exit **-532462766** | Missing `odbc`/`MicsUser` env on child process; confirm `utilities.dll` deploy + app pool recycle |
| View empty | `SELECT COUNT(*) FROM web.user_tables_view WHERE operator='rctl'` — should be > 0 |
| Exit **2** | `user_schema2022` — see [killtable-delete-bug.md](killtable-delete-bug.md) |

---

## Rollback

1. Restore prior `KillTable.exe` / `utilities.dll` from backup (or rebuild from pre-change source).
2. Recycle `remicsdevapp`.
3. To restore old view (not recommended on UseDbAuth): reapply broken definition only if required for a specific test.

---

## Related

- [KillTable delete bug (UseDbAuth)](killtable-delete-bug.md) — schema lookup fix (`user_schema2022`)
- [AD-free auth Phase 2 cut](ad-free-auth-phase2-cut.md) — `Process.Start` / app-pool model
