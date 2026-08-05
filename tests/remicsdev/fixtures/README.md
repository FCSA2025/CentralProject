# ReMICS Dev — test fixtures

Pinned TS table exports and metadata for Export/Print, Import, Validate, and TSIP tests.

## Fixtures

| Id | Source table | File | Role |
|----|--------------|------|------|
| `cat` | `rctl.ft_cat_*` | `files/cat.txt` (~1.3 KB) | Smoke print / import / validate |
| `ecomm2602` | `rctl.ft_ecomm2602_*` | `files/ecomm2602.txt` (~3.5 KB) | Complex-but-small print / import; primary TSIP parm |
| `ecomm2601b` | `rctl.ft_ecomm2601b_*` | `files/ecomm2601b.txt` (~5.2 KB) | Secondary TSIP / drift fixture |

Baselines (sizes, row counts, TSIP `run_id`) live in [`baselines.yaml`](baselines.yaml) (rctl1/rctl3), [`baselines-xci1.yaml`](baselines-xci1.yaml), and [`baselines-dnd1.yaml`](baselines-dnd1.yaml).

## Updates\Primary harvest (DbUpdate staging samples)

Largest files copied from live `D:\Updates\Primary` (2026-07-31) for import/validate stress and DbUpdate-adjacent testing. Naming pattern: `{micsid}_{yyMMddHHmm}_{pdfname}.txt`.

| File | Bytes | Notes |
|------|------:|-------|
| `files/updates-primary/rctl12_2601051258_at_w6911w0061_m0.txt` | 28030 | Largest staging sample |
| `files/updates-primary/bchy2_2601031507_hsy_260103b.txt` | 14266 | |
| `files/updates-primary/bchy2_2601051105_bructl_260105b.txt` | 6996 | |
| `files/updates-primary/xci7_2512241008_vyb577.txt` | 5207 | |
| `files/updates-primary/bchy2_2601031614_pik_260103b.txt` | 4503 | |

These are **not** auto-installed; import manually into a disposable `cmxa*` / test name when needed.

## dnd1 circular DbUpdate pairs

Under `files/updates-primary/circular/dnd1/` — delete/add-back staging files for repeatable MDB testing (submitter `dnd1`, operator `DND`):

| Set | Delete | Add-back | Sites |
|-----|--------|----------|------:|
| cmxts03 smoke | `dndc03del` | `dndc03add` | 2 |
| cmxts01 complex | `dndc01d01`–`d06` | `dndc01a01`–`a06` | 274 |

Generate or refresh: `scripts/New-Dnd1CircularUpdateFixtures.ps1`. Details: [`circular/dnd1/README.md`](files/updates-primary/circular/dnd1/README.md).

## seq10 circular (10 TS + 10 ES)

Under `files/updates-primary/circular/seq10/` — numbered delete/add-back pairs (submitter `cyc1`):

| Type | Files | Sites/file | Total sites |
|------|-------|------------|------------:|
| TS | `cycts01d`…`cycts05a` (10) | 20–55 | 170 |
| ES | `cyces01d`…`cyces05a` (10) | 20–55 | 170 |

Run files 01→10 in order for net-zero DB change. Install subset masters `cycts10` / `cyces10` via `Install-MicsComplexFixtures.ps1`.

Generate: `scripts/New-CircularSeq10Fixtures.ps1`. Copy to inbox: `scripts/Install-CircularSeq10ToInbox.ps1`. Details: [`circular/seq10/README.md`](files/updates-primary/circular/seq10/README.md).

## Complex pinned fixtures (`cmx*`)

| Pinned name | Type | Master export | Role |
|-------------|------|---------------|------|
| `cmxts01` | TS | `files/complex/xci-tafli19b.txt` | ~478 chans; default complex print/import |
| `cmxts03` | TS | `files/complex/rctl-ecomm2601.txt` | TSIP-capable complex TS |
| `cmxes01` | ES | `files/complex/rctl-rert.txt` | ~5.6k chans |
| `cmxes02` | ES | `files/complex/xci-es140km.txt` | Medium ES |

Manifest: [`complex-manifest.yaml`](complex-manifest.yaml). Install into `rctl`, `xci`, `dnd`:

```powershell
.\scripts\Export-RemicsDevComplexMasters.ps1
.\scripts\Install-MicsComplexFixtures.ps1
.\scripts\Restore-MicsComplexFixtures.ps1 -Fixture cmxts01   # after destructive test
```

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
