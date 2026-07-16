# ReMICS Dev — test fixtures

Pinned TS table exports and metadata for Export/Print, Import, Validate, and TSIP tests.

## Fixtures

| Id | Source table | File | Role |
|----|--------------|------|------|
| `cat` | `rctl.ft_cat_*` | `files/cat.txt` (~1.3 KB) | Smoke print / import / validate |
| `ecomm2602` | `rctl.ft_ecomm2602_*` | `files/ecomm2602.txt` (~3.5 KB) | Complex-but-small print / import; primary TSIP parm |
| `ecomm2601b` | `rctl.ft_ecomm2601b_*` | `files/ecomm2601b.txt` (~5.2 KB) | Secondary TSIP / drift fixture |

Baselines (sizes, row counts, TSIP `run_id`) live in [`baselines.yaml`](baselines.yaml).

## Shared TS / ES fixtures

Every existing SQL schema referenced by an active MICS account has six reserved
table sets:

| MICS name | Type | Source |
|-----------|------|--------|
| `testts1` | TS | `files/testts1.txt` (small smoke fixture) |
| `testts2` | TS | `files/testts2.txt` (complex fixture) |
| `testts3` | TS | `files/testts3.txt` (secondary complex fixture) |
| `testes1` | ES | `files/testes1.txt` (small smoke fixture) |
| `testes2` | ES | `files/testes2.txt` (140 km fixture) |
| `testes3` | ES | `files/testes3.txt` (300 km fixture) |

Install missing fixtures (or preview first):

```powershell
.\scripts\Install-MicsSharedTestFixtures.ps1 -WhatIf
.\scripts\Install-MicsSharedTestFixtures.ps1
```

The installer derives one account/project per schema and adapts the operator
field in each TS file to the target schema. Existing reserved fixtures are
skipped unless `-Force` is specified. It never touches other table roots.

The FCSA `/admin/` panel supports Export, Import, Validate, and Round-trip for
all six shared fixtures. It dispatches `testts*` through the `Ft*` executables
and `testes*` through the corresponding `Fe*` executables.

Its TSIP button captures the latest completed run for up to 10 distinct
`schema + TS/ES type + parm file` combinations and reruns them sequentially.
The live query automatically expands toward 10 as new distinct files are
archived; a batch manifest preserves the exact baseline run IDs tested.

As of 2026-07-16, all 33 existing schemas referenced by active users contain all
six non-empty fixtures (198 table sets). `abccom` is not included because
`dbo.t_UserDetails.PrimarySchema` references `abccom`, but that SQL schema does
not currently exist.

## Safety rules

- **Import** always uses a fresh short name (max ~16 chars), e.g. `cataHHmmss` / `e2602aHHmmss` — never overwrite pinned tables.
- **Validate** runs against a freshly imported copy (FtValidate mutates `ft_*` tables).
- After import / validate / round-trip, the worker **drops** allowlisted auto tables (`ftImport -x`). Pinned roots (`cat`, `ecomm2602`, `ecomm2601b`) are never deleted.
- Orphan cleanup: `.\scripts\Remove-RemicsDevTestTables.ps1` (use `-WhatIf` first).
- Auth/schema: CLI uses `MICSUSER` → SQL lookup (e.g. `rctl1` → `rctl`). See [test-account-setup.md](../../../docs/remicsdev/test-account-setup.md).
- Do not commit large TSIP report dumps; those stay under `D:\inetpub\fcsa\admin\tsip-runs\`.

## Refresh workflow

1. Confirm exports look correct in the UI (or via CLI).
2. Run:

```powershell
.\scripts\Update-RemicsDevTestBaselines.ps1
```

3. Review and commit `baselines.yaml` (+ updated `files\*.txt` if intentional).

## Related scripts / UI

- Worker: `scripts/Invoke-MicsFileOpCompare.ps1`
- Orphan cleanup: `scripts/Remove-RemicsDevTestTables.ps1`
- TSIP worker: `scripts/Invoke-LastTsipCompare.ps1`
- Operator UI: `http://localhost/admin/`
