# ReMICS Dev (remicsdev) documentation

Frequency Coordination System — development environment on IIS.

**Login URL:** http://remicsdev.cloudmicsdev.ca/mics/Tlogin.aspx

Machine-readable context: [`context/codebases/remicsdev.yaml`](../../context/codebases/remicsdev.yaml)

## Documentation index

| Doc | Status | Summary |
|-----|--------|---------|
| [Infrastructure mapping](infrastructure-mapping.md) | **Complete** | IIS sites/apps, disk paths, config files, batch and DB wiring |
| [Web application structure](web-app-structure.md) | **Complete** | Folders, shared libs, batch invoke path, verification script |
| [Login flow & session model](login-flow.md) | **Complete** | Auth path, session keys — source + browser validated |
| [Automated testing strategy](automated-testing.md) | **Complete** | Tiers 1–4 plan; manual test template passed |
| [Batch programs](batch-programs.md) | **In progress** | Source, build/deploy paths, web↔disk gaps |
| [TSIP deep dive](tsip.md) | **In progress** | Calculations, formulas, inputs, outputs |
| [TSIP tt tables & capture](tsip-tt-tables.md) | **Complete** | Working table lifecycle |
| [TSIP run archive plan](tsip-archive-plan.md) | **Planned** | Hybrid storage design; implementation queued |
| Startup & configuration | Planned | `Global.asax`, full `Application[]` keys |
| Database | Planned | SQL Server instance, ODBC, connection patterns |

## Quick reference

| What | Where |
|------|-------|
| IIS site | `remicsdev` → `D:\inetpub\remicsdev` |
| MICS web app (IIS application `/mics`) | `D:\inetpub\remicsdev\mics` |
| Authoritative `web.config` | `D:\inetpub\remicsdev\mics\web.config` |
| Web solution | `D:\inetpub\remicsdev\mics\mics.sln` |
| Batch source | `D:\MicsBatchProgs` |
| Batch runtime (this site) | `D:\develbat` (from `ProgDir` in web.config) |
| SQL Server | `EC2AMAZ-9DKDM82\REMICS_DEV` / database `remicsdev` |
