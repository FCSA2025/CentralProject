# DbUpdate staging pipeline — remicsdev pilot

**Status:** Pilot implemented 2026-08-05; **auto-processing** added 2026-08-07  
**Execution identity:** `fwmda` / schema `fmda2` / project `fwmda_0`  
**Trigger:** FCSA admin button (`/admin/`) **or** SQL Agent job **Update Queue Local** (every **10 min**)

---

## Auto-processing (2026-08-07)

Operators (or seq10 fixture install) enqueue rows in **`adm.t_UpdateQueue_local`**. SQL Agent job **Update Queue Local** on EC2AMAZ-9DKDM82 invokes `Invoke-RemicsUpdateAutoProcessor.ps1` on **IIS-REMICS-PROD** via WinRM.

| Outcome | Email recipient |
|---------|-----------------|
| Success | Submitter (`adm.account_details.email`) |
| Failure | `UpdateQueueFailureNotify` (testing: `jscott@fcsa.ca` only) |

Notifications INSERT into **`adm.t_EmailQueue_local`** → **Email Queue Local** job (every **2 min**).

**Agent schedules** (EC2AMAZ-9DKDM82):

| Job | Interval |
|-----|----------|
| Update Queue Local | 10 minutes |
| Email Queue Local | 2 minutes |

Redeploy: `.\scripts\Deploy-UpdateQueueLocalJob.ps1` and `.\scripts\Deploy-EmailQueueLocalJob.ps1`

**Config** (`web.config`):

```xml
<add key="DisableOutgoingEmail" value="false" />
<add key="EmailRedirectAllTo" value="" />
<add key="UpdateQueueTable" value="adm.t_UpdateQueue_local" />
<add key="UpdateQueueEnabled" value="true" />
<add key="UpdateQueueAllowedSubmitters" value="" />
<add key="UpdateQueueFailureNotify" value="jscott@fcsa.ca" />
<add key="UpdateQueueMode" value="spoof-first" />
```

**Deploy:**

```powershell
.\scripts\Deploy-UpdateQueueLocalJob.ps1
```

**Manual run (same as agent step locally):**

```powershell
.\scripts\Invoke-RemicsUpdateAutoProcessor.ps1 -MaxFiles 1
```

**Verify queue:**

```sql
SELECT TOP 10 queue_id, [status], staging_file, pdf_name, ErrorMsg, Processed
FROM adm.t_UpdateQueue_local ORDER BY queue_id DESC;
```

**Repeatable E2E (cmxts03 — recommended):**

```powershell
# Full cycle: operator submit -> auto queue -> pipeline -> completion email (delete then add-back)
.\scripts\Run-Dnd1CircularAutoUpdateE2E.ps1 -WaitSeconds 420

# Manual steps
.\scripts\Submit-RemicsDevDbUpdate.ps1 -StagingSource "...\cmxts03\dnd1_*_dndc03del.txt" -FileType TS
.\scripts\Invoke-RemicsUpdateAutoProcessor.ps1 -MaxFiles 1
.\scripts\Invoke-RemicsEmailQueueLocal.ps1
```

Fixtures: `tests/remicsdev/fixtures/files/updates-primary/circular/dnd1/cmxts03/` + `cmxts03-manifest.json`.

---

## Inbox processing registry (2026-08-11)

Unified audit table **`adm.t_InboxProcessing_local`** tracks each DbUpdate staging file from inbox through queue, pipeline, validate-all, and stale archive. Registry writes are **non-blocking** (failures log warnings only).

| Lifecycle | Meaning |
|-----------|---------|
| `inbox` | Still in TS/ES inbox (validate-all snapshot) |
| `queued` | Claimed by Update Queue Local |
| `processing` | DbUpdate pipeline running |
| `completed` / `failed` | Pipeline finished |
| `stale_archived` | Moved by stale cleanup (>14 days + error signal) |

**Safeguards:** Stale cleanup skips files with queue status `N`/`P` or registry `queued`/`processing`.

**Config** (`web.config`):

```xml
<add key="InboxProcessingTable" value="adm.t_InboxProcessing_local" />
```

**Deploy table + SQL Agent job** (daily **02:00** local, off-peak):

```powershell
.\scripts\Deploy-UpdateInboxStaleCleanupJob.ps1
```

**Dry-run stale cleanup** (no file moves):

```powershell
.\scripts\Invoke-RemicsUpdateInboxStaleCleanup.ps1 -DryRun
```

**Verify registry:**

```sql
SELECT TOP 20 processing_id, staging_file, lifecycle_status, error_yn, [source], created, completed
FROM adm.t_InboxProcessing_local ORDER BY processing_id DESC;
```

Admin list (`update-pipeline-list.ashx`) merges **`registry-cache.json`** (written by registry helpers) into inbox/inflight rows.

**Test email addresses** (all flows deliver to jscott@fcsa.ca via DB rows, not config redirect):

```powershell
.\scripts\Invoke-RemicsDevSql.ps1 -InputFile .\docs\remicsdev\ddl\remicsdev-test-email-normalize.sql
```

Updates `dbo.t_UserDetails`, `adm.account_details`, and `adm.pcn_account_details`.

**seq10 repeatable test:**

```powershell
.\scripts\Install-CircularSeq10ToInbox.ps1 -FileType Both -Pair 1
# Wait ~2 min for agent jobs, or run processor manually
```

Requires one-time `Initialize-CircularSeq10Main.ps1` so delete passes validate.

---

## Overview

Operators export validated PDFs via RemIcsReWrite **Database Update** → files land in `D:\updates\primary\{submitter}_{timestamp}_{pdfname}.txt`.

FCSA admin **Process** runs (default **spoof-first** mode):

1. Pre-clean `killTable` (if PDF tables already in `fmda2`)
2. `FtImport` / `FeImport` into **fwmda** schema
3. `FtValidate` / `FeValidate`
4. Gate: `validated` must be `U` or `M`
5. **Sync spoof MDB** — copy `main.*` → `fmda2.*` (`Sync-FwmdaSpoofFromMain.ps1`)
6. **Spoof update** — `MtUpdate` / `MeUpdate` **`-s`** against synced spoof tables
7. On spoof success (exit 0, `validated=P`, records changed): **main cutover** — same exe without `-s`, with **`-p`**
8. Post-clean `killTable` (always — frees PDF name for next submission)
9. Archive staging file to `completed/{jobId}/` or `errors/{jobId}/` on failure

Spoof success gate (main is **not** updated if any check fails):

- Exit code 0
- `validated = P` on `fmda2.ft_{pdf}_titl`
- Stdout does not contain `No records were Updated, Deleted, or Added`

Admin **Update mode** dropdown: spoof-first (default), spoof-only, main-only.

**Validate all** runs import + validate on every inbox file. Files that fail import or validate are moved to `errors/{jobId}/`. Passing files stay in the inbox; results appear in the **Validate** column and persist in `admin/update-pipeline/validate-cache.json`.

**Update all validated** processes every inbox file marked OK in the validate cache (respects the Update mode dropdown). Files leave the inbox as each completes.

Submitter parsed from filename is **audit only**; batch env is always fwmda (billing attribution).

---

## One-time setup

### Spoof MDB tables in fmda2

One-time structure bootstrap (if tables missing):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Initialize-FwmdaSpoofTables.ps1 -Json
```

Before each spoof-first run, the pipeline refreshes spoof data from main:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Sync-FwmdaSpoofFromMain.ps1 -FileType TS -Json
```

Copies `main.mt_site`, `mt_chan`, `mt_ante`, `sd_town`, `sd_rout`, `audit_trail` → `fmda2.*` (TS) or `me_*` (ES).

### Work directory

Created automatically: `D:\Inetpub\remicsdev\mics\userdirs\fmda2\fwmda\`

### Password

Set `MICS_TEST_PASSWORD_FWMDA` in `.env.local` or machine env (falls back to `MICS_TEST_PASSWORD`, then `x`).

---

## CLI usage

```powershell
# Default: spoof-first (sync → spoof -s → main -p on success)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-RemicsUpdatePipeline.ps1 `
  -StagingFile "rctl1_2608051204_bbimport2.txt" -SpoofFirst -ResultPath "$env:TEMP\job.json"

# Spoof only — never write main.*
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-RemicsUpdatePipeline.ps1 `
  -StagingFile "rctl1_2608051204_bbimport2.txt" -SpoofOnly -ResultPath "$env:TEMP\job.json"

# Production cutover — write main.* directly
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-RemicsUpdatePipeline.ps1 `
  -StagingFile "rctl1_2608051204_bbimport2.txt" -MainOnly -ResultPath "$env:TEMP\job.json"

# Validate all inbox files (no update, files stay in inbox)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-RemicsUpdateValidateAll.ps1 `
  -ResultPath "$env:TEMP\validate-all.json"

# Update all files marked OK in validate-cache.json
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-RemicsUpdateValidatedAll.ps1 `
  -ResultPath "$env:TEMP\update-validated.json" -Mode spoof-first

# Retry a failed/processing job
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-RemicsUpdatePipeline.ps1 `
  -JobId "8df5bf1e77404b9a9b30114eb07a3bc4" -ResultPath "$env:TEMP\job.json"
```

---

## Admin UI

| Handler | Purpose |
|---------|---------|
| `update-pipeline-list.ashx` | Inbox + in-flight jobs |
| `update-pipeline-start.ashx` | Start job (`file=`, `mode=spoof-first|spoof-only|main-only`, or `retryJobId=`) |
| `update-pipeline-validate-start.ashx` | Validate all inbox files (import + validate only) |
| `update-pipeline-update-validated-start.ashx` | Update all validated inbox files (uses validate cache) |
| `update-pipeline-status.ashx` | Poll job JSON under `admin/update-pipeline/` |

Deployed to `D:\inetpub\fcsa\admin\`.

---

## Pilot test results (2026-08-05)

| Staging file | PDF | Import | Validate | MtUpdate -s | Post-clean | Result |
|--------------|-----|--------|----------|-------------|------------|--------|
| `rctl1_2608051315_bbimport2.txt` | bbimport2 | 0 | U | 0 | dropped | **PASS** |
| `rctl1_2608051320_ecomm2602a.txt` | ecomm2602a | 0 | U | 0 → P | dropped | **PASS** |

After each run: `fmda2.ft_{pdf}_*` count = 0 (name freed for collision retry).

Spoof tables (`fmda2.mt_site`) persist across runs.

---

## Directory layout

```text
D:\updates\primary\
  *.txt                    # inbox (TS)
  UnprocessedESFiles\      # inbox (ES)
  processing\{jobId}\
  completed\{jobId}\
  errors\{jobId}\           # import / validate / update failures (+ logs)
  failed\{jobId}\           # legacy failures (pre-errors folder)
```

---

## Recovery

| Situation | Action |
|-----------|--------|
| Validate fails | Update not run; post-clean still drops PDF tables; file in `errors/` |
| Spoof fails | Main not updated; file in `errors/` |
| Crash mid-step | File in `processing/`; Retry runs pre-clean then re-imports |
| Same PDF name from two submitters | Sequential runs OK — post-clean frees fwmda table set |

---

## Production cutover (future)

- Admin **Main only** mode or `-MainOnly` for direct `main.*` updates (skip spoof)
- Replace admin button with file watcher or scheduled poller (same script)
- Keep fwmda execution identity for billing

---

## Related

- [batch-programs.md](batch-programs.md) — MtUpdate/MeUpdate spoof flags (`-s`, `-C`)
- [tests/remicsdev/fixtures/README.md](../../tests/remicsdev/fixtures/README.md) — staging filename pattern
