# Resume here

**Last updated:** 2026-06-17

---

## Next: TSIP run archive (when ready)

Implementation plan: **[docs/remicsdev/tsip-archive-plan.md](../docs/remicsdev/tsip-archive-plan.md)**

Hybrid 3-layer storage (14 tables): `web.tsip_run` registry + normalized `arc_ts_*` / `arc_te_*` snapshots + report file line cache. Hook: `TsipRunArchive.ArchiveRun()` in `TpRunTsip.Main()` before `KillTable(cUnique)`.

Tracked in [docs/TODO.md](../docs/TODO.md) — Phases 1–5.

---

## Batch analysis phase 2

First pass documented: **[docs/remicsdev/batch-programs.md](../docs/remicsdev/batch-programs.md)**

Key findings to follow up:

| Topic | Finding |
|-------|---------|
| **remicsdev runtime** | `D:\develbat\` (~55 exes) via `ProgDir=\develbat\` |
| **remicstest runtime** | `D:\devel\bin\` via `ProgDir=\devel\bin\` |
| **Primary source** | `D:\MicsBatchProgs\MicsBat\MicsBat.sln` |
| **Build staging** | `MicsBat\_bin\Release\` (~118 exes) |
| **Deploy** | Release\|x64 → develbat and/or PostBuild COPY; legacy inetpub → devel\bin |
| **prod\bin** | ~55 exes; promotion process **unknown** |
| **Tier 4 smoke** | Pick candidate (e.g. `CheckMicsConfig`) — not selected yet |

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
