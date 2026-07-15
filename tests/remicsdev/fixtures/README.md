# ReMICS Dev — test fixtures

Pinned TS table exports and metadata for Export/Print, Import, Validate, and TSIP tests.

## Fixtures

| Id | Source table | File | Role |
|----|--------------|------|------|
| `cat` | `rctl.ft_cat_*` | `files/cat.txt` (~1.3 KB) | Smoke print / import / validate |
| `ecomm2602` | `rctl.ft_ecomm2602_*` | `files/ecomm2602.txt` (~3.5 KB) | Complex-but-small print / import; primary TSIP parm |
| `ecomm2601b` | `rctl.ft_ecomm2601b_*` | `files/ecomm2601b.txt` (~5.2 KB) | Secondary TSIP / drift fixture |

Baselines (sizes, row counts, TSIP `run_id`) live in [`baselines.yaml`](baselines.yaml).

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
