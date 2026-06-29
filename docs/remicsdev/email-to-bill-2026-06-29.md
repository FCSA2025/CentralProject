# Email to Bill — remicsdev login, batch, and TS import/export (29 June 2026)

**Subject:** remicsdev — login, batch spawn (1314), export truncation, import warnings (29 Jun 2026)

**Attachment / supplement:** `email-to-bill-2026-06-29-line-edits.md` (find/replace for every source file)

---

Bill,

Summary of work on **remicsdev** today (`http://remicsdev.cloudmicsdev.ca/mics/Tlogin.aspx`, server **IIS-ReMics-Prod**). We went from broken login and batch jobs to working login, TS export, and TS import. **No changes were made to SQL Server** — the database and table data (e.g. `cat`) were fine throughout.

This email is the full handoff. The line-by-line edit guide in CentralProject has every source change if you need to apply the same edits on another copy of the server.

---

## Current status (end of 29 June)

| Area | Status |
|------|--------|
| Login (rctl1) | **Working** — after re-applying Domain Users logon rights locally |
| Batch spawn (1314) | **Resolved** — `CreateProcessAsUser succeeded` in logs |
| TS export (`ftPrint`) | **Fixed** — full files (~1307 bytes for `cat`, not 1024) |
| TS import (`ftImport`) | **Working** — export/re-import confirmed via UI |
| Import warnings | **Logged to disk** — no alert/popup unless user looks |

**Important:** Login is working on a **temporary** local-policy fix. The next domain **`gpupdate /force`** can break login again until you add Domain Users to the GPO (see § Action required below).

---

## Problems we hit (in order)

### 1. TS import failed with error 1314

**Symptom:** Import (and other batch jobs) failed from the web app. `web.dblogger` showed `ERROR:CreateProcessAsUser: 1314`. `ftImport.exe` never started.

**Cause:** The IIS app pool account **`cloudmicsdev\IISReMicsSer`** did not hold the Windows privileges required for `CreateProcessAsUser` when impersonating the logged-in user.

**Fix applied:** Domain GPO **MICS IIS Server Rights** — added `IISReMicsSer` to:

1. Impersonate a client after authentication  
2. Replace a process level token  
3. Adjust memory quotas for a process  

Then `gpupdate /force` and `iisreset` on the IIS server.

---

### 2. Login failed — “session timed out” on a fresh login

**Symptom:** AD password accepted, then redirect to “session timed out” / relogin. Misleading — not a session timeout.

**Cause:** MICS login is **three steps**, not one:

1. **AD Membership** validates the password (Forms Auth cookie) — this succeeded.  
2. **`LogonUser`** obtains a Windows token → `Session["principalw"]` — this **failed** with Win32 error **1385** (`ERROR_LOGON_TYPE_NOT_GRANTED`).  
3. **`TloginValidate`** opens SQL with ODBC `Trusted_Connection=yes` as the impersonated user — never reached when step 2 fails.

Without `principalw`, `Global.asax` sends the user to `relogin.aspx`, which looks like a session timeout.

**Fix:** Domain users need **INTERACTIVE (2)** or **BATCH (4)** logon permission on the IIS server:

| User Rights Assignment | Principal |
|------------------------|-----------|
| Allow log on locally | `CLOUDMICSDEV\Domain Users` |
| Log on as a batch job | `CLOUDMICSDEV\Domain Users` |

**Do not use NETWORK (3) logon** as a workaround — it can succeed at `LogonUser` but SQL then sees **`NT AUTHORITY\ANONYMOUS LOGON`** and login stops at `TloginValidate` (blank page).

**Code changes:** `Tlogin.aspx.cs` — try INTERACTIVE then BATCH; log Win32 errors to `D:\perflogs\goodwinlogin.txt`; show clear error on login page instead of recycling through relogin. `TloginValidate.aspx.cs` — re-enabled SQL error labels (were commented out → blank page).

---

### 3. Import failed after login worked — parse errors around line 22

**Symptom:** Valid table `cat` in the database; export succeeded; re-import as a new name failed with parse errors mid-file.

**Cause:** **`ftPrint` export files were truncated at ~1024 bytes.** In `FtPrint.cs`, output to `-o` uses a `StreamWriter` with a 1024-byte buffer; **`mTW.Close()` was commented out** before process exit. Export returned exit 0 but the file was incomplete — often cutting mid-record at line 22. `ftImport` correctly rejected the truncated file.

**Fix:** Before exit, flush and close the output stream when writing to `-o`. Rebuilt **`D:\develbat\ftPrint.exe`**.

**Quick check:** If an export file is exactly **1024 bytes**, the old `ftPrint` is still in use.

---

### 4. Import warnings — alert and popup on success

**Symptom:** Successful imports with warnings showed an alert and opened a warning file popup.

**Fix:** `TwsTabUtil.asmx.cs` — archive warnings to `D:\MicsWebLogs\imports\` and return `IMPORTOK:` only. `import.aspx` — on success, go back without alert. Warnings are in the log index `import_warnings.log` if needed.

---

## GPO vs local policy — read this before the next gpupdate

We applied two different kinds of server configuration:

| Change | Where | Purpose | Durable? |
|--------|-------|---------|----------|
| `IISReMicsSer` → impersonate / replace token / memory quota | **MICS IIS Server Rights** GPO | Fix **1314** | **Yes** — survives gpupdate |
| `Domain Users` → Allow log on locally + Log on as a batch job | **Local `secedit` only** (so far) | Fix **1385** | **No** — reverted once already |

**Timeline on 29 June:**

| Time | Event |
|------|-------|
| ~14:28 | GPO for 1314 applied; batch spawn working |
| ~15:11–15:50 | Login worked after local `secedit` added Domain Users |
| ~16:10 | **`gpupdate /force`** — Domain Users **removed** from local logon rights; login **1385** again |
| After re-`secedit` | Login restored; confirmed working |

**The 1314 GPO did not remove app-pool privileges.** Login broke because domain GPO refresh overwrote the manual local logon-rights addition. **MICS IIS Server Rights** `GptTmpl.inf` still does not include Domain Users on `SeInteractiveLogonRight` / `SeBatchLogonRight`.

---

## Action required (priority order)

### 1. Add Domain Users to GPO (before next gpupdate on IIS)

In GPMC → **MICS IIS Server Rights** → Computer Configuration → Windows Settings → Security Settings → **User Rights Assignment**:

| Setting | Add |
|---------|-----|
| Allow log on locally | `CLOUDMICSDEV\Domain Users` |
| Log on as a batch job | `CLOUDMICSDEV\Domain Users` |

**Scope the GPO** so this does not apply to every domain computer — use an **IIS-servers OU link** or **security filtering** to the IIS EC2 computer accounts only.

Then on each IIS server: `gpupdate /force` and recycle the app pool or `iisreset`.

### 2. Second IIS EC2 (if load-balanced)

Apply the same GPO refresh, logon rights, and deployed binaries:

- `D:\inetpub\remicsdev\mics\bin\mics.dll`  
- `D:\inetpub\remicsdev\mics\bin\Tfileactions.dll`  
- `D:\develbat\ftPrint.exe`  

### 3. Temporary workaround (if GPO not done yet)

Local `secedit` on each IIS box — full steps in the line-by-line guide §1B. **Expect this to be overwritten on the next domain `gpupdate`.**

---

## Application changes deployed on remicsdev

| Component | Source | Deploy target | What changed |
|-----------|--------|---------------|--------------|
| Web login | `mics\Tlogin.aspx.cs` | `bin\mics.dll` | INTERACTIVE → BATCH `LogonUser`; Win32 logging; login page shows 1385 remediation (GPO; warns local secedit is temporary) |
| Login validate | `mics\TloginValidate.aspx.cs` | same `mics.dll` | SQL connection errors visible on screen |
| Import service | `Tfileactions\TwsTabUtil.asmx.cs` | `bin\Tfileactions.dll` | Warnings archived to `D:\MicsWebLogs\imports\`; return `IMPORTOK:` only |
| Import UI | `Tfileactions\import.aspx` | (markup only) | No warning alert/popup on successful import |
| TS export | `MicsBat\FtPrint\FtPrint.cs` | `D:\develbat\ftPrint.exe` | Flush/close output file before exit |

**Not changed:** SQL Server, `ftImport.exe`, `JobSubmit.cs`, database content.

### Build commands (reference)

```text
MSBuild D:\inetpub\remicsdev\mics\mics.csproj /p:Configuration=Release /t:Build
MSBuild D:\inetpub\remicsdev\mics\Tfileactions\Tfileactions.csproj /p:Configuration=Release /t:Build
MSBuild D:\MicsBatchProgs\MicsBat\FtPrint\FtPrint.csproj /p:Configuration=Release /p:Platform=x64 /t:Build
Restart-WebAppPool remicsdevapp
```

---

## How to diagnose next time

| Issue | Check first |
|-------|-------------|
| Login / 1385 | `D:\perflogs\goodwinlogin.txt` |
| SQL after login | `D:\MicsWebLogs\logins\{user}_conn.txt` |
| Batch spawn / 1314 | `D:\extractlogs\remicsdev_{user}submit5.txt` |
| Batch job result | `web.dblogger` (program, return code, error text) |
| Import parse errors | `{user_dir}{name}.txt` (stdout capture) |
| Truncated export | File size exactly 1024 bytes → old `ftPrint` |
| Import warnings | `D:\MicsWebLogs\imports\import_warnings.log` |

**1314** = batch never started (app pool privileges).  
**1385** = `LogonUser` failed (Domain Users logon rights on IIS).  
**Import “Errors found” with exit -1** after spawn works = **`ftImport` ran** but rejected input (often truncated export).

---

## Verification evidence (29 June)

| Test | Result |
|------|--------|
| `CreateProcessAsUser` (rctl1) | Succeeded — no 1314 |
| Login rctl1 → `TloginValidate` | Database connection opened; `FCSASESS` assigned (session 13045) |
| Export `cat` before ftPrint fix | 1024 bytes — truncated |
| Export `cat` after ftPrint fix | ~1307 bytes — complete |
| Import after fix | UI import confirmed working |
| Login after afternoon gpupdate | Broke (1385) until local secedit re-applied |

---

## Documentation in CentralProject

| Doc | Purpose |
|-----|---------|
| `docs/remicsdev/session-2026-06-29-login-import-fixes.md` | Full technical session notes |
| `docs/remicsdev/email-to-bill-2026-06-29-line-edits.md` | **Line-by-line find/replace** for every source file |
| `docs/remicsdev/login-flow.md` | Auth chain and session model |
| `docs/remicsdev/ts-file-import-flow.md` | Import chain and 1314 diagnostics |

Happy to walk through GPMC settings or the login chain on a call if useful.

Regards,  
[Your name]
