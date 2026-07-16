# AD-free auth — Phase 2 cut (UseDbAuth on remicsdev)

**Status:** Smoke-validated 2026-07-15

**Pilot:** `dbautht1` / `dbauth-test` / schema `rctl` / project `rctl1_0`

**Flag:** `web.config` `UseDbAuth=true`, `<identity impersonate="false" />`

**Snapshot:** `D:\Backups\remicsdev-adfree-precut\20260715_174340\`

---

## What works

| Check | Result |
|-------|--------|
| DB login (`t_UserDetails` plaintext) | Pass — navigation shows `dbautht1 -remicsdev` |
| `Session[s_schema]` from `PrimarySchema` | Pass (`rctl`) |
| SQL / ODBC as `IISReMicsSer` | Pass |
| Process-identity `Session[principalw]` + `ImpersonateForJob` no-op | Pass |
| `navigationTop` project list from `adm.project_ids` by `micsid` | Pass (`rctl1_0`) |
| Web export via `TwsTabUtil.exportTable` → `JobSubmit` `Process.Start` | Pass (`FILENAME:cat.txt`) |
| Web import via `importTable` → `ftImport` as app pool | Pass (`IMPORTOK`, submit5 log `UseDbAuth: spawn as app pool`) |
| Password change UI (`loginPassword.aspx`) | Pass — temp change + restore to `dbauth-test` |
| CLI print/import harness as `MICSUSER=dbautht1` | Pass (MATCH) |

---

## Remicsdev code touched (inetpub — not in GitHub)

| Area | Change |
|------|--------|
| `utilities/MicsDbAuth.cs` | Verify/Set password, `GetPrimarySchema`, `EnsureProcessPrincipalInSession`, `ImpersonateForJob` |
| `utilities/JobSubmit.cs` | `UseDbAuth` → `SubmitJobViaProcessStart`; null-safe submit logging |
| `Tlogin.aspx` / `.cs` | `Login1_Authenticate` DB verify; skip `LogonUser` |
| `TloginValidate.aspx.cs` | Schema from `PrimarySchema` |
| `Global.asax.cs` | Skip Windows impersonation when UseDbAuth |
| `loginPassword.aspx.cs` | DB plaintext password change |
| `navigationTop.aspx.cs` | Project list from `adm.project_ids WHERE micsid=…` (not `USER`-scoped view) |
| Many ASMX / pages | `ImpersonateForJob` instead of casting `principalw` + `Impersonate` |
| Separate DLLs | Rebuild **`utilities.dll`**, **`mics.dll`**, and **`Tfileactions.dll`** (import/export lives here) |

---

## Why the plan missed `principalw` / `project_ids_view`

The Phase 2 plan correctly targeted the **auth seam** (Tlogin / Membership / LogonUser) and the **spawn seam** (JobSubmit `CreateProcessAsUser` → `Process.Start`). What it understated:

1. **`principalw` is ambient session infrastructure**, not only a JobSubmit input. Dozens of ASMX/page methods wrap every file op in `WindowsPrincipal` + `Impersonate()` *before* calling JobSubmit. Skipping LogonUser without a substitute nulls that ambient credential and crashes the wrappers — even when JobSubmit itself is fixed.

2. **SQL authorization still used Windows/`USER` identity.** `adm.project_ids_view` filters `WHERE micsid = USER`. Under Trusted_Connection as the app pool, `USER` is `IISReMicsSer`, so the project dropdown emptied and wiped `Session[defProject]`. Login-time `user_project2022` looked fine; the next `navigationTop` load overwrote it.

3. **Smoke was ordered “login first, file-ops later.”** Plan validation stopped at Login Successful before exercising the ASMX surface that depends on those ambient contracts. CLI harnesses never hit `principalw` or `project_ids_view`.

4. **Multi-assembly build.** File-ops code is in `Tfileactions.dll`, not `mics.dll`. Editing `.asmx.cs` without rebuilding that project left old binaries in place — another reason web export looked broken after “mics rebuild.”

---

## Rollback

1. Prefer: `UseDbAuth=false` and restore `<identity impersonate="true" />` if needed; recycle `remicsdevapp`.
2. Full: restore DLLs / sources from `D:\Backups\remicsdev-adfree-precut\20260715_174340\`.

---

## Follow-ups

- Hash passwords (leave plaintext for testing until then).
- Audit other `USER`-scoped views/procs under UseDbAuth.
- Rebuild sibling ASMX projects (`Ttsipmenu`, `Tesmenu`, …) that received `ImpersonateForJob` source edits so binaries match.
- Optional: dedicated `autotest` schema later (cleanup-in-place on `rctl` remains Phase A).
