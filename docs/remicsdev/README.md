# ReMICS Dev (remicsdev) documentation

Frequency Coordination System — development environment on IIS.

**Login URL:** http://remicsdev.cloudmicsdev.ca/mics/Tlogin.aspx

Machine-readable context: [`context/codebases/remicsdev.yaml`](../../context/codebases/remicsdev.yaml)

## Documentation index

| Doc | Status | Summary |
|-----|--------|---------|
| [Database access](database-access.md) | **Complete** | sqlcmd wrapper, schemas, read/write conventions |
| [Source layout — where to edit code](source-layout.md) | **Complete** | Web vs batch paths; inetpub = web source; env copies |
| [Environments & URLs](environments-and-urls.md) | **Complete** | IIS/DNS verified; prod URLs not on this server |
| [Web application structure](web-app-structure.md) | **Complete** | Folders, shared libs, batch invoke path, verification script |
| [Login flow & session model](login-flow.md) | **Complete** | Auth path, session keys — source + browser validated |
| [Automated testing strategy](automated-testing.md) | **Complete** | Tiers 1–4 plan; manual test template passed |
| [Batch programs](batch-programs.md) | **In progress** | Source, build/deploy paths, web↔disk gaps |
| [TSIP deep dive](tsip.md) | **In progress** | Calculations, formulas, inputs, outputs |
| [TSIP implementation plan](tsip-implementation-plan.md) | **Active** | Phase 0 fix + archive Phases 1–5; codebase notes |
| [TSIP tt tables lifecycle](tsip-tt-tables.md) | **Complete** | Working table reference (not the implementation plan) |
| Startup & configuration | Planned | `Global.asax`, full `Application[]` keys |

## Quick reference

| What | Where |
|------|-------|
| IIS site | `remicsdev` → `D:\inetpub\remicsdev` |
| MICS web app (IIS application `/mics`) | `D:\inetpub\remicsdev\mics` — **also the VS source tree** |
| Web solution | `D:\inetpub\remicsdev\mics\mics.sln` |
| Authoritative `web.config` | `D:\inetpub\remicsdev\mics\web.config` |
| CentralProject hub (docs only) | `E:\AIProjects\CentralProject` |
| Batch source | `D:\MicsBatchProgs` (`.cs` — no separate prod source tree) |
| Batch runtime (this site) | `D:\develbat` (`.exe` only) |
| Batch runtime (production) | `D:\prod\bin` (`.exe` only; promotion manual/inferred) |
| SQL Server | `EC2AMAZ-9DKDM82\REMICS_DEV` / database `remicsdev` |
| SQL helper script | `scripts/Invoke-RemicsDevSql.ps1` |
