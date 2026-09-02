# Gate F — automated regression (remicsdev)

**Purpose:** Nightly checks that RemIcsReWrite stabilization invariants still hold. Emails the FCSA team when SQL checks fail; HTTP isolation failures are reported in job step 2.

## Checks

| Check | Source | Pass condition |
|-------|--------|----------------|
| Cross-company TSIP parms | `web.RunGateFRegression` | Zero parm files whose runs reference another operator's PDF (`proname` or `PDF_*` `envname`) |
| Catalog drift | Same proc | `catalog_orphans = 0` and `catalog_missing = 0` for types 0/5/417 |
| Reconcile freshness | Same proc | Latest `LIVE` row in `web.user_tables_reconcile_run` within 36 hours |
| TSIP isolation (HTTP) | `Invoke-GateFRegressionTest.ps1 -HttpOnly` | `tsipValidate` returns `not found` for foreign PDF — per roster user |
| TSIP reports root (HTTP) | Same script | `tsip-reps-tree.ashx` returns `ok=true` — per roster user (catches compile/Assembly Src breaks) |

## Nightly SQL Agent job

| Property | Value |
|----------|--------|
| Job name | **RemIcs Gate F Regression** |
| Schedule | Daily **03:15** local (after User Tables Reconcile at 02:30) |
| Step 1 | TSQL: `EXEC web.RunGateFRegression @SendEmail=1` — emails team + fails job on issues |
| Step 2 | CmdExec: PowerShell HTTP roster check — emails on HTTP failure |

Deploy / update:

```powershell
.\scripts\Deploy-GateFRegressionJob.ps1
```

## Manual / CI

```powershell
# Full Gate F (SQL + HTTP, no email)
.\scripts\Invoke-GateFRegressionTest.ps1

# SQL only
.\scripts\Invoke-GateFRegressionTest.ps1 -SqlOnly

# HTTP roster only (same as job step 2)
.\scripts\Invoke-GateFRegressionTest.ps1 -HttpOnly -SendEmailOnFailure
```

## Audit tables

```sql
SELECT TOP 10 * FROM web.gate_f_regression_run ORDER BY run_id DESC;
SELECT * FROM web.gate_f_regression_finding WHERE run_id = <id>;
```

## Email

Uses `msdb.dbo.sp_send_dbmail` profile **AlertMailProfile**, from **mics@fcsa.ca**, to the FCSA team list (same recipients as Email Queue Local error notifications).

## Artifacts

| Path | Role |
|------|------|
| `docs/remicsdev/ddl/web.gate_f_regression_log.sql` | Run + finding tables |
| `docs/remicsdev/ddl/web.RunGateFRegression.sql` | `web.RunGateFRegression`, `web.SendGateFAlert` |
| `docs/remicsdev/gate-f-regression-agent-job.sql` | Job step 1 T-SQL |
| `scripts/Deploy-GateFRegressionJob.ps1` | Deploy DDL + Agent job |
| `scripts/Invoke-GateFRegressionTest.ps1` | Manual smoke + job step 2 |

Cross-company detection logic matches `docs/remicsdev/sql/delete-cross-company-parms.sql` (audit + delete; no deletes in nightly job).
