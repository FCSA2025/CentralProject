# web.user_tables reconcile (remicsdev)

**Status:** Deployed on remicsdev  
**Purpose:** Keep `web.user_tables` in sync with physical TS / ES / TSIP parm tables so lookups and TSIP validation do not drift after failed CopyTable / KillTable / partial deletes.

## What it covers

| tabletype | Physical marker table |
|-----------|------------------------|
| 0 (TS) | `{schema}.ft_{name}_titl` |
| 5 (ES) | `{schema}.fe_{name}_titl` |
| 417 (TSIP parm) | `{schema}.tp_{name}_parm` |

Actions each run:

1. **DELETE_ORPHAN** — catalog row with no physical marker table  
2. **INSERT_MISSING** — physical marker table with no catalog row (`validstat=N`, then sync)  
3. **UPDATE_VALIDSTAT** — for TS/ES, set catalog `validstat` from `{titl}.validated`

Other `tabletype` families (300+/400+) are not touched.

## Artifacts

| Path | Role |
|------|------|
| `docs/remicsdev/ddl/web.user_tables_reconcile_log.sql` | `web.user_tables_reconcile_run` + `_log` |
| `docs/remicsdev/ddl/web.ReconcileUserTables.sql` | `web.ReconcileUserTables` |
| `docs/remicsdev/user-tables-reconcile-agent-job.sql` | Agent job step body |
| `scripts/Deploy-UserTablesReconcileJob.ps1` | Deploy DDL + nightly job |
| `scripts/Invoke-RemicsUserTablesReconcile.ps1` | Manual / post-error run |
| `RemIcsReWrite/reconcile.ashx` | Session-scoped HTTP reconcile (rewrite UI auto-reconcile) |

## Schedules / when to run

**Both** are intentional:

1. **Nightly SQL Agent** — job **User Tables Reconcile**, daily **02:30** local on `EC2AMAZ-9DKDM82`  
2. **After error / on demand** — when CopyTable, KillTable, or a manual DROP may have left catalog and tables out of sync:

```powershell
# Live reconcile (all companies)
.\scripts\Invoke-RemicsUserTablesReconcile.ps1

# One company only
.\scripts\Invoke-RemicsUserTablesReconcile.ps1 -Operator bchy

# Preview only
.\scripts\Invoke-RemicsUserTablesReconcile.ps1 -DryRun

# Or start the Agent job
.\scripts\Invoke-RemicsUserTablesReconcile.ps1 -StartAgentJob
```

```sql
EXEC web.ReconcileUserTables @Operator = NULL, @DryRun = 0, @SyncValidstat = 1;
-- or
EXEC msdb.dbo.sp_start_job @job_name = N'User Tables Reconcile';
```

## Audit

```sql
SELECT TOP 20 * FROM web.user_tables_reconcile_run ORDER BY run_id DESC;
SELECT TOP 100 * FROM web.user_tables_reconcile_log WHERE run_id = <id> ORDER BY log_id;
```

## Deploy

```powershell
.\scripts\Deploy-UserTablesReconcileJob.ps1
```

## Notes

- Classic UI **ResetUserTables** (`documentation/ResetUserTables.aspx`) remains the manual per-company tool (fwmda). This job is the automated equivalent for 0/5/417 only.  
- Inserted catalog rows use `adm.account_details` for a default `micsid` / `project_code` when available.  
- Preventing drift at the source still matters: KillTable/CopyTable should call `UtUpdateCentralTable`; this reconcile is the safety net.
