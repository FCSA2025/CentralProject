# TSIP archive DDL (Phase 1)

Greenfield **`web.*`** tables for the [TSIP implementation plan](../tsip-implementation-plan.md). **CREATE only** — does not alter `web.tsip_queue`, user `tt_*` / `tp_*`, or legacy schemas.

## Apply (remicsdev)

From CentralProject root:

```powershell
$dir = "docs\remicsdev\sql\tsip-archive"
@('001_registry.sql','002_arc_tables.sql','003_report_line.sql','004_grants.sql') | ForEach-Object {
    .\scripts\Invoke-RemicsDevSql.ps1 -InputFile (Join-Path $dir $_)
}
```

## Objects created (14 tables)

| Script | Tables |
|--------|--------|
| `001_registry.sql` | `web.tsip_run`, `web.tsip_run_parm_ts`, `web.tsip_run_parm_es` |
| `002_arc_tables.sql` | 8× `web.tsip_arc_{ts,te}_{site,ante,chan,parm}`, `web.tsip_arc_ts_statsum`, `web.tsip_arc_te_statsum` |
| `003_report_line.sql` | `web.tsip_run_report_line` |
| `004_grants.sql` | INSERT/SELECT for `ROLfcsaconsultants`, `ROLfcsastaff`, `ROLwebconsultants`, `ROLwebusers` |

## Verify

```powershell
.\scripts\Invoke-RemicsDevSql.ps1 -ReadOnly -Query @"
SELECT name FROM sys.tables
WHERE schema_id = SCHEMA_ID('web') AND name LIKE 'tsip_%'
ORDER BY name
"@
```

Expect **15** rows including pre-existing `tsip_queue` (**14 new** archive tables).

## Inspect archived data

See **[tsip-archive-queries.md](../../tsip-archive-queries.md)** for run discovery, queue linkage, Layer 2 samples, and report reassembly from `web.tsip_run_report_line`.

## Rollback (manual)

Drop in FK order if needed:

```sql
DROP TABLE IF EXISTS web.tsip_run_report_line;
DROP TABLE IF EXISTS web.tsip_arc_ts_statsum;
DROP TABLE IF EXISTS web.tsip_arc_te_statsum;
DROP TABLE IF EXISTS web.tsip_arc_ts_site;
DROP TABLE IF EXISTS web.tsip_arc_ts_ante;
DROP TABLE IF EXISTS web.tsip_arc_ts_chan;
DROP TABLE IF EXISTS web.tsip_arc_ts_parm;
DROP TABLE IF EXISTS web.tsip_arc_te_site;
DROP TABLE IF EXISTS web.tsip_arc_te_ante;
DROP TABLE IF EXISTS web.tsip_arc_te_chan;
DROP TABLE IF EXISTS web.tsip_arc_te_parm;
DROP TABLE IF EXISTS web.tsip_run_parm_ts;
DROP TABLE IF EXISTS web.tsip_run_parm_es;
DROP TABLE IF EXISTS web.tsip_run;
```
