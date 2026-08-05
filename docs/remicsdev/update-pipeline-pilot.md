# DbUpdate staging pipeline — remicsdev pilot

**Status:** Pilot implemented 2026-08-05  
**Execution identity:** `fwmda` / schema `fmda2` / project `fwmda_0`  
**Trigger:** FCSA admin button (`/admin/` → DbUpdate staging pipeline panel)

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
9. Archive staging file to `completed/{jobId}/` or `failed/{jobId}/`

Spoof success gate (main is **not** updated if any check fails):

- Exit code 0
- `validated = P` on `fmda2.ft_{pdf}_titl`
- Stdout does not contain `No records were Updated, Deleted, or Added`

Admin **Update mode** dropdown: spoof-first (default), spoof-only, main-only.

**Validate all** runs import + validate on every inbox file without moving them. Results appear in the **Validate** column (green OK U/M, red FAIL) and persist in `admin/update-pipeline/validate-cache.json` across page refreshes.

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
  failed\{jobId}\
```

---

## Recovery

| Situation | Action |
|-----------|--------|
| Validate fails | Update not run; post-clean still drops PDF tables; file in `failed/` |
| Spoof fails | Main not updated; file in `failed/` |
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
