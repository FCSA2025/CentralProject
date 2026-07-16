# AD-free auth — Phase 0 and 1 results

**Status:** Complete (2026-07-15)  
**Scope:** CentralProject scripts + SQL only — **no** remicsdev `Tlogin` / `Global.asax` / `JobSubmit` edits  
**Related plan:** AD-free MICS login (option 3)

---

## What was proved

| Check | Result |
|-------|--------|
| Schema from `dbo.t_UserDetails.PrimarySchema` only | Pass (`rctl1` → `rctl`) |
| Dedicated pilot `dbautht1` (active, schema `rctl`, plaintext password) | Pass |
| CLI batch without AD (`MICSUSER` env): print + import `cat` MATCH + cleanup | Pass |
| Plaintext verify / bad password / set / restore / inactive rejected | Pass (Phase 1) |

Result JSON:

- [`ad-free-auth-phase0-results.json`](ad-free-auth-phase0-results.json)
- [`ad-free-auth-phase1-results.json`](ad-free-auth-phase1-results.json)

---

## Scripts (new files only)

| Script | Role |
|--------|------|
| [`scripts/MicsDbAuth.ps1`](../../scripts/MicsDbAuth.ps1) | Dot-source helpers: get user/schema, test/set plaintext password, ensure pilot |
| [`scripts/Prove-RemicsDevDbAuth.ps1`](../../scripts/Prove-RemicsDevDbAuth.ps1) | Phase 0 gate (`-EnsurePilot` `-RunBatch`) |
| [`scripts/Test-MicsDbAuth.ps1`](../../scripts/Test-MicsDbAuth.ps1) | Phase 1 gate |

```powershell
.\scripts\Prove-RemicsDevDbAuth.ps1 -EnsurePilot -RunBatch
.\scripts\Test-MicsDbAuth.ps1
```

Pilot credentials (remicsdev testing only): micsId `dbautht1`, password `dbauth-test`, schema `rctl`.  
`rctl1` remains mapped to `rctl` but `IsActiveYN=N` — do not use it for DB-auth login smoke until activated.

---

## Findings for Phase 2+

1. **Do not call** `dbo.user_schema()` / `user_schema2022` for schema — use `PrimarySchema`.
2. **Plaintext** `Password` works for testing; leave `PasswordHash` unused until a later phase.
3. AD-free batch is already viable via env `MICSUSER` (CLI harness); web still blocked on `principalw` / `CreateProcessAsUser` until JobSubmit + Global.asax change under `UseDbAuth`.
4. App-pool ACL for `IISReMicsSer` on `userdirs` was **not** re-validated as that identity in Phase 0 (CLI ran as the interactive admin). Still a Phase 2/4 pre-check before enabling web JobSubmit as app pool.
5. Port `MicsDbAuth.ps1` contract into `utilities/MicsDbAuth.cs` when remicsdev code is first edited.

---

## Next (Phase 2 — first remicsdev edits)

**Done 2026-07-15** — see [`ad-free-auth-phase2-cut.md`](ad-free-auth-phase2-cut.md).

Feature-flag `UseDbAuth`; wire Tlogin verify + PrimarySchema; Global.asax skip AD impersonation; JobSubmit `Process.Start`; ambient `principalw` / `ImpersonateForJob`; `navigationTop` project list by `micsid` (not `USER`-scoped view).
