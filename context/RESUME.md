# Resume here

**Last updated:** 2026-06-23

---

## Database access (documented)

Query/modify **remicsdev** via **[scripts/Invoke-RemicsDevSql.ps1](../scripts/Invoke-RemicsDevSql.ps1)** — see **[docs/remicsdev/database-access.md](../docs/remicsdev/database-access.md)**.

---

## Source layout (documented)

Where to edit web vs batch code: **[docs/remicsdev/source-layout.md](../docs/remicsdev/source-layout.md)**

Key points: **`D:\inetpub\remicsdev\mics\` = web source + IIS**; batch source at **`D:\MicsBatchProgs`**; CentralProject is docs only; remicstest is a separate inetpub copy.

---

## GitHub (done)

Repo: **https://github.com/FCSA2025/CentralProject** — `main` synced.

For the **next machine or project**, copy **[docs/github-setup-checklist.md](../docs/github-setup-checklist.md)** and run the pre-flight checks **before** first push (Credential Manager / Keychain beats debugging PATs).

---

## Next: TSIP (Phase 0 fix, then archive)

Implementation plan: **[docs/remicsdev/tsip-implementation-plan.md](../docs/remicsdev/tsip-implementation-plan.md)**

**Phase 0:** Remove broken `venn.tsip*Storedef` ODBC block from `MicsBat\TpRunTsip`; build to `D:\develbat\`. Verified jobs 138–140 (`rctl1` / `ecomm2602`).
**Phases 1–5:** Greenfield shared-schema `web.*` archive — test after each phase.

Tracked in [docs/TODO.md](../docs/TODO.md).

---

## Batch analysis phase 2

First pass documented: **[docs/remicsdev/batch-programs.md](../docs/remicsdev/batch-programs.md)**

**Environments on this server (verified 2026-06-23):** **[docs/remicsdev/environments-and-urls.md](../docs/remicsdev/environments-and-urls.md)**

| Topic | Finding |
|-------|---------|
| **Working login** | `http://remicsdev.cloudmicsdev.ca/mics/Tlogin.aspx` only dev confirmed in daily use |
| **Test** | `remicstest.cloudmicsdev.ca` — IIS site + inetpub copy; app pool was Stopped |
| **Prod URLs** | `remicsproddev`, `micsprod`, `micsimport` — **DNS fails on this server**; no local IIS |
| **remicsdev runtime** | `D:\develbat\` (~55 exes) via `ProgDir=\develbat\` |
| **remicstest runtime** | `D:\devel\bin\` via `ProgDir=\devel\bin\` |
| **Primary source** | `D:\MicsBatchProgs\MicsBat\MicsBat.sln` |
| **prod\bin** | ~55 exes on this server; **no prod web inetpub**; promotion **unknown** |

Open: `wTerrex` vs `Worbit.exe`, `SQLtoFlat` not deployed, `MICSH` vs `MicsBat`.

Full backlog: [docs/TODO.md](../docs/TODO.md)

---

## Quick reference

| Item | Value |
|------|-------|
| Batch source | `D:\MicsBatchProgs\MicsBat\` |
| Dev runtime (remicsdev) | `D:\develbat\` |
| Test runtime (remicstest) | `D:\devel\bin\` |
| Prod runtime (inferred) | `D:\prod\bin\` |
| Verify web→disk | `.\scripts\verify-batch-mapping.ps1` |
| Compare bin dirs | `.\scripts\compare-batch-bins.ps1` |

Context: [codebases/remicsdev.yaml](codebases/remicsdev.yaml)
