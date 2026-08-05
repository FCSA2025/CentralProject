# seq10 circular DbUpdate fixtures (10 TS + 10 ES)

Repeatable **delete → add-back** sequences for DbUpdate pipeline testing.
Submitter `cyc1` (audit only); pipeline runs as `fwmda`.

## Layout

| Path | Contents |
|------|----------|
| `ts/` | 10 TS staging files + `cycts10-master.txt` (schema seed) |
| `es/` | 10 ES staging files + `cyces10-master.txt` (schema seed) |
| `seq10-manifest.json` | File list, site counts, run order |

## Site counts per file

Five delete/add pairs; each file has **15–100 sites**:

| Pair | Delete file | Sites | Add-back file | Sites |
|-----:|-------------|------:|---------------|------:|
| 1 | `cycts01d` / `cyces01d` | 20 | `cycts01a` / `cyces01a` | 20 |
| 2 | `cycts02d` / `cyces02d` | 25 | `cycts02a` / `cyces02a` | 25 |
| 3 | `cycts03d` / `cyces03d` | 30 | `cycts03a` / `cyces03a` | 30 |
| 4 | `cycts04d` / `cyces04d` | 40 | `cycts04a` / `cyces04a` | 40 |
| 5 | `cycts05d` / `cyces05d` | 55 | `cycts05a` / `cyces05a` | 55 |

**Total:** 170 sites per type (from `cmxts01` / `cmxes01` complex masters).

## Run order (net-zero)

Process files in **numeric timestamp order** (or sequence 01→10):

1. Delete pass (odd pairs: 01d, 02d, … 05d) — removes sites from `main.*`
2. Add-back pass (even pairs: 01a, 02a, … 05a) — restores original site data

After all 10 files, the database matches its pre-test state (assuming sites existed before the first delete).

TS and ES sequences are **independent** — run TS 01–10 and/or ES 01–10 separately.

## Schema install (optional)

Install pinned subset masters into test schemas (`rctl`, `xci`, `dnd`):

```powershell
.\scripts\Install-MicsComplexFixtures.ps1 -Schema dnd -Fixture cycts10
.\scripts\Install-MicsComplexFixtures.ps1 -Schema dnd -Fixture cyces10
```

Then promote to `main.*` via normal DbUpdate workflow, or use full `cmxts01` / `cmxes01` if you already have those sites in main.

## Copy to inbox

```powershell
# Generate (or refresh) fixtures
.\scripts\New-CircularSeq10Fixtures.ps1

# Copy all TS files to primary inbox
.\scripts\Install-CircularSeq10ToInbox.ps1 -FileType TS

# Copy all ES files to ES inbox
.\scripts\Install-CircularSeq10ToInbox.ps1 -FileType ES

# Or generate and install in one step
.\scripts\New-CircularSeq10Fixtures.ps1 -InstallToInbox
```

Admin panel: **Validate all** → **Update all validated** (spoof-first recommended).

## Validation notes

- **TS** files match the proven dnd1 circular pattern (from `cmxts01` / `xci-tafli19b`). Import + FtValidate pass after a clean `-x` drop (orphan `ft_*` tables from a failed import can block re-import — drop via `ftImport … junk -x` or SQL).
- **ES** files import cleanly via `feImport -d`. Delete passes (`*d`) may report many FeValidate messages because sites use `SK,D`/`AK,D`/`CK,D`; add-back passes restore `SK,A` records from the `cmxes01` master.
- Regenerate with `-ValidateSample` to smoke-test pair 1 delete/add against `fwmda_0`.

## Troubleshooting partial imports

If `ftImport`/`feImport` reports "Error creating table" but tables partially exist:

```powershell
powershell -File scripts/Invoke-RemicsDevSql.ps1 -Query `
  "SELECT name FROM sys.tables WHERE name LIKE 'ft_cycts%' OR name LIKE 'fe_cyces%'"
# Drop orphans in fmda2 before re-testing
```

```powershell
.\scripts\New-CircularSeq10Fixtures.ps1 -ValidateSample
```

`-ValidateSample` runs import+validate on the first delete and add-back file of each type against `fwmda_0`.

## Source masters

| Type | Complex fixture | Master export |
|------|-----------------|---------------|
| TS | `cmxts01` | `files/complex/xci-tafli19b.txt` (274 sites) |
| ES | `cmxes01` | `files/complex/rctl-rert.txt` (516 sites) |

Delete files set `SK/A K/CK` action to `D` with TS operator `DND`. Add-back files preserve original master content.
