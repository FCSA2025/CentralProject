# TSIP archive — query reference

Practical SQL for inspecting archived TSIP runs on remicsdev. All archive objects live in schema **`web`**, keyed by **`run_id`**.

**Related:** [tsip-implementation-plan.md](tsip-implementation-plan.md) · [sql/tsip-archive/README.md](sql/tsip-archive/README.md) · [database-access.md](database-access.md)

**Run queries:**

```powershell
.\scripts\Invoke-RemicsDevSql.ps1 -ReadOnly -Query "SELECT TOP 10 * FROM web.tsip_run ORDER BY run_id DESC"
```

---

## Table map

| Layer | Tables | Use |
|-------|--------|-----|
| **Registry** | `web.tsip_run` | Run metadata, `mics_user`, `source_schema`, `queue_job_id`, status |
| **Parm snapshot** | `web.tsip_run_parm_ts`, `web.tsip_run_parm_es` | Input parm row at run time |
| **Working copy (TS)** | `web.tsip_arc_ts_{site,ante,chan,parm}`, `web.tsip_arc_ts_statsum` | TS-TS / TS-ES calc results |
| **Working copy (ES)** | `web.tsip_arc_te_{site,ante,chan,parm}`, `web.tsip_arc_te_statsum` | ES calc results (`statsum_part` = `P` or `E`) |
| **Report cache** | `web.tsip_run_report_line` | Line-by-line copy of on-disk reports |
| **Queue (live)** | `web.tsip_queue` | Batch job history; join on `queue_job_id` = `TQ_Job` |

---

## 1. Run discovery

### Recent runs (all users)

```sql
SELECT run_id, queue_job_id, mics_user, source_schema,
       parm_file, run_name, view_name, protype,
       num_int_cases, archive_status,
       run_started_utc, run_finished_utc
FROM web.tsip_run
ORDER BY run_started_utc DESC;
```

### Runs for one MICS user

```sql
DECLARE @user VARCHAR(32) = 'rctl1';

SELECT run_id, queue_job_id, parm_file, run_name, protype,
       num_int_cases, archive_status, run_started_utc
FROM web.tsip_run
WHERE mics_user = @user
ORDER BY run_started_utc DESC;
```

### Runs for a parm file + run name (history)

```sql
DECLARE @parm  VARCHAR(64) = 'ecomm2602';
DECLARE @run   VARCHAR(64) = 'TS1';

SELECT run_id, queue_job_id, mics_user, num_int_cases,
       archive_status, run_started_utc, run_finished_utc
FROM web.tsip_run
WHERE parm_file = @parm AND run_name = @run
ORDER BY run_started_utc;
```

### Latest run for a parm/run (single `run_id`)

```sql
DECLARE @parm VARCHAR(64) = 'ecomm2602';
DECLARE @run  VARCHAR(64) = 'TS1';

SELECT TOP 1 run_id, run_started_utc, archive_status
FROM web.tsip_run
WHERE parm_file = @parm AND run_name = @run
ORDER BY run_started_utc DESC;
```

---

## 2. Queue linkage

### Archive rows joined to queue job

```sql
SELECT r.run_id, r.queue_job_id, r.parm_file, r.run_name,
       r.archive_status, r.run_started_utc,
       q.TQ_Job, q.TQ_ArgFile, q.TQ_Status, q.TQ_Finish,
       q.TQ_TimeIn, q.TQ_TimeStart, q.TQ_TimeEnd
FROM web.tsip_run r
LEFT JOIN web.tsip_queue q ON q.TQ_Job = r.queue_job_id
ORDER BY r.run_id DESC;
```

### Successful queue jobs with no archive row

```sql
SELECT q.TQ_Job, q.TQ_ArgFile, q.TQ_MicsID, q.TQ_Finish, q.TQ_TimeEnd
FROM web.tsip_queue q
WHERE q.TQ_Finish = 0
  AND NOT EXISTS (
      SELECT 1 FROM web.tsip_run r WHERE r.queue_job_id = q.TQ_Job
  )
ORDER BY q.TQ_Job DESC;
```

Runs before Phase 2, or runs that failed before the archive hook, will appear here. `queue_job_id` is NULL on runs archived before 2026-06-25.

### Link integrity check

```sql
SELECT r.run_id, r.queue_job_id, r.parm_file,
       CASE
           WHEN r.queue_job_id IS NULL THEN 'no_job_id'
           WHEN q.TQ_Job IS NULL THEN 'orphan_job_id'
           WHEN LTRIM(RTRIM(q.TQ_ArgFile)) <> LTRIM(RTRIM(r.parm_file)) THEN 'parm_mismatch'
           ELSE 'ok'
       END AS link_check
FROM web.tsip_run r
LEFT JOIN web.tsip_queue q ON q.TQ_Job = r.queue_job_id
ORDER BY r.run_id;
```

---

## 3. Archive health

### Status summary

```sql
SELECT archive_status, COUNT(*) AS n,
       SUM(CASE WHEN queue_job_id IS NULL THEN 1 ELSE 0 END) AS null_job_id
FROM web.tsip_run
GROUP BY archive_status;
```

### Row counts per run (TS)

```sql
SELECT r.run_id, r.parm_file, r.run_name, r.protype,
       (SELECT COUNT(*) FROM web.tsip_arc_ts_site    s WHERE s.run_id = r.run_id) AS ts_site,
       (SELECT COUNT(*) FROM web.tsip_arc_ts_ante    a WHERE a.run_id = r.run_id) AS ts_ante,
       (SELECT COUNT(*) FROM web.tsip_arc_ts_chan    c WHERE c.run_id = r.run_id) AS ts_chan,
       (SELECT COUNT(*) FROM web.tsip_arc_ts_statsum t WHERE t.run_id = r.run_id) AS ts_statsum,
       (SELECT COUNT(*) FROM web.tsip_run_report_line l WHERE l.run_id = r.run_id) AS report_lines
FROM web.tsip_run r
WHERE r.protype = 'T'
ORDER BY r.run_id;
```

### Row counts per run (ES)

```sql
SELECT r.run_id, r.parm_file, r.run_name,
       (SELECT COUNT(*) FROM web.tsip_arc_te_site    s WHERE s.run_id = r.run_id) AS te_site,
       (SELECT COUNT(*) FROM web.tsip_arc_te_ante    a WHERE a.run_id = r.run_id) AS te_ante,
       (SELECT COUNT(*) FROM web.tsip_arc_te_chan    c WHERE c.run_id = r.run_id) AS te_chan,
       (SELECT COUNT(*) FROM web.tsip_arc_te_statsum t WHERE t.run_id = r.run_id) AS te_statsum,
       (SELECT COUNT(*) FROM web.tsip_run_report_line l WHERE l.run_id = r.run_id) AS report_lines
FROM web.tsip_run r
WHERE r.protype = 'E'
ORDER BY r.run_id;
```

### Report types cached for a run

```sql
DECLARE @run_id BIGINT = 4;

SELECT report_type, COUNT(*) AS line_count,
       MIN(line_no) AS first_line, MAX(line_no) AS last_line
FROM web.tsip_run_report_line
WHERE run_id = @run_id
GROUP BY report_type
ORDER BY report_type;
```

Expected report types (when requested in parm): `CASEDET`, `CASESUM`, `CASEOHL`, `STATSUM`, `STUDY`, `EXEC`, `EXPORT`, `AGGINT`, `AGGINTCSV`, `HILO`, `ORBIT`.

### Failed or partial archives

```sql
SELECT run_id, parm_file, run_name, archive_status, archive_message,
       run_started_utc, run_finished_utc
FROM web.tsip_run
WHERE archive_status <> 'complete'
ORDER BY run_started_utc DESC;
```

---

## 4. Parm snapshot

```sql
DECLARE @run_id BIGINT = 4;

-- TS runs
SELECT * FROM web.tsip_run_parm_ts WHERE run_id = @run_id;

-- ES runs
SELECT * FROM web.tsip_run_parm_es WHERE run_id = @run_id;
```

Compare parm across two runs:

```sql
SELECT run_id, proname, runname, numcases, numtecases, mdate, mtime
FROM web.tsip_run_parm_ts
WHERE run_id IN (4, 5)
ORDER BY run_id;
```

---

## 5. Layer 2 — normalized results

Replace `@run_id` and filter as needed. Column sets mirror live `{schema}.tt_*` / `te_*` working tables.

### TS interference cases (chan level)

```sql
DECLARE @run_id BIGINT = 4;

SELECT caseno, intcall1, viccall1, intfreqtx, vicfreqrx,
       calcico, calcixp, resti, ohresult
FROM web.tsip_arc_ts_chan
WHERE run_id = @run_id
ORDER BY caseno, intcall1, viccall1;
```

### TS site pairs

```sql
DECLARE @run_id BIGINT = 4;

SELECT caseno, intcall1, viccall1, intname1, vicname1,
       int1vic1dist, report
FROM web.tsip_arc_ts_site
WHERE run_id = @run_id
ORDER BY caseno;
```

### ES chan results

```sql
DECLARE @run_id BIGINT = 99;  -- ES example

SELECT etcaseno, tecaseno, terrcall1, earthlocation,
       calci20mode1, marg20mode1, calci01mode1
FROM web.tsip_arc_te_chan
WHERE run_id = @run_id
ORDER BY etcaseno;
```

### STATSUM staging

```sql
-- TS
SELECT tmpinter, tmpcall1, tmpname, tmpoper, tmplatit, tmplongit, tmpgrnd
FROM web.tsip_arc_ts_statsum
WHERE run_id = 4
ORDER BY tmpinter, tmpcall1;

-- ES (proposed P + environment E)
SELECT statsum_part, tmpinter, tmplocat, tmpcall1, tmpname
FROM web.tsip_arc_te_statsum
WHERE run_id = 99
ORDER BY statsum_part, tmpinter, tmpcall1;
```

### Compare calc data between two archived runs

```sql
SELECT a4.caseno, a4.intcall1, a4.viccall1,
       a4.calcico AS run4_ico, a5.calcico AS run5_ico
FROM web.tsip_arc_ts_chan a4
JOIN web.tsip_arc_ts_chan a5
  ON a4.caseno = a5.caseno
 AND a4.intcall1 = a5.intcall1
 AND a4.viccall1 = a5.viccall1
WHERE a4.run_id = 4 AND a5.run_id = 5
  AND a4.calcico <> a5.calcico;
```

---

## 6. Layer 3 — reassemble reports from line cache

### Full report as text (single result row)

Use for download, print preview, or email body attachment generation in Phase 4.

```sql
DECLARE @run_id      BIGINT       = 4;
DECLARE @report_type VARCHAR(32)  = 'CASEDET';

SELECT STRING_AGG(CAST(line_text AS NVARCHAR(MAX)), CHAR(13) + CHAR(10))
       WITHIN GROUP (ORDER BY line_no) AS report_text
FROM web.tsip_run_report_line
WHERE run_id = @run_id AND report_type = @report_type;
```

### Paginated lines (web UI)

```sql
DECLARE @run_id      BIGINT = 4;
DECLARE @report_type VARCHAR(32) = 'CASEDET';
DECLARE @offset      INT = 0;
DECLARE @page_size   INT = 100;

SELECT line_no, line_text
FROM web.tsip_run_report_line
WHERE run_id = @run_id AND report_type = @report_type
ORDER BY line_no
OFFSET @offset ROWS FETCH NEXT @page_size ROWS ONLY;
```

### Line-level diff between two runs (same report type)

```sql
SELECT r2.line_no,
       CASE WHEN r2.line_text = r3.line_text THEN 'match' ELSE 'diff' END AS cmp,
       r2.line_text AS run2, r3.line_text AS run3
FROM web.tsip_run_report_line r2
JOIN web.tsip_run_report_line r3
  ON r2.report_type = r3.report_type AND r2.line_no = r3.line_no
WHERE r2.run_id = 2 AND r3.run_id = 3
  AND r2.report_type = 'CASEDET'
  AND r2.line_text <> r3.line_text
ORDER BY r2.line_no;
```

Timestamps and EXEC/STUDY timing lines commonly differ between runs; CASEDET body lines should match when inputs are unchanged.

---

## 7. Useful filters

| Goal | Filter |
|------|--------|
| My runs only | `WHERE mics_user = '<MicsUser>'` |
| One schema | `WHERE source_schema = 'rctl'` |
| One parm file | `WHERE parm_file = 'ecomm2602'` |
| One run name | `AND run_name = 'TS1'` |
| Date range | `AND run_started_utc >= '2026-06-25' AND run_started_utc < '2026-06-26'` |
| TS vs ES | `WHERE protype = 'T'` or `'E'` |
| Linked to queue | `WHERE queue_job_id IS NOT NULL` |

**`view_name`** is `{parm_file}_{run_name}` (e.g. `ecomm2602_TS1`). Live working tables at archive time were `{source_schema}.tt_{view_name}_*` or `te_{view_name}_*`.

---

## 8. Invoke-RemicsDevSql examples

```powershell
# List recent runs
.\scripts\Invoke-RemicsDevSql.ps1 -ReadOnly -Query @"
SELECT TOP 20 run_id, mics_user, parm_file, run_name, archive_status, run_started_utc
FROM web.tsip_run ORDER BY run_started_utc DESC
"@

# Report line counts for a run
.\scripts\Invoke-RemicsDevSql.ps1 -ReadOnly -Query @"
SELECT report_type, COUNT(*) AS lines
FROM web.tsip_run_report_line WHERE run_id = 4
GROUP BY report_type ORDER BY report_type
"@
```

---

## Phase 4 (not yet implemented)

These queries support **investigation and verification** today. End-user **read, print, and email** from archived results requires web UI work — see [TODO.md](../TODO.md) Phase 4.
