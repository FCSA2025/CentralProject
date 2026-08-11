# seq10 circular DbUpdate fixtures (10 TS + 10 ES)

Repeatable **delete → add-back** sequences for DbUpdate pipeline testing.
Submitter defaults to **`dnd1`** (audit only); pipeline runs as **`fwmda`**.

## Layout

| Path | Contents |
|------|----------|
| `ts/` | 10 TS staging files + `cycts10-master.txt` + bootstrap `dnd1_*_cycts10.txt` |
| `es/` | 10 ES staging files + `cyces10-master.txt` + bootstrap `dnd1_*_cyces10.txt` |
| `seq10-manifest.json` | File list, site counts, run order, bootstrap paths |

Delete passes use **`SK,D` / `AK,D` / `CK,D`**; add-back passes use **`SK,A` / `AK,A` / `CK,A`**
(matching the proven dnd1 circular pattern). TS **`SD`** operator is **`DND`**.

## Repeatable test cycle

```text
ONE-TIME SETUP
  1. Install operator fixtures (dnd schema)
  2. Bootstrap main.* with full seq10 site subset

PER FILE (repeat indefinitely)
  A. Operator (dnd1): import staging → validate → DbUpdate export → inbox
     OR: .\scripts\Install-CircularSeq10ToInbox.ps1 -Pair N (copies + enqueues)
  B. Auto job: Update Queue Local → Invoke-RemicsUpdateAutoProcessor.ps1 (spoof-first)
     OR admin panel: Validate all → Update all validated
  C. Next file in sequence (01d → 01a → 02d → 02a → … → 05a)
```

### One-time setup

```powershell
cd E:\AIProjects\CentralProject

# Regenerate fixtures (default submitter dnd1)
.\scripts\New-CircularSeq10Fixtures.ps1

# Pin masters into dnd schema (operator import/validate/export)
.\scripts\Install-MicsComplexFixtures.ps1 -Schema dnd -Fixture cycts10
.\scripts\Install-MicsComplexFixtures.ps1 -Schema dnd -Fixture cyces10

# Seed main.* so delete passes validate (fwmda inbox pipeline)
.\scripts\Initialize-CircularSeq10Main.ps1
```

### Run one pair (smoke)

```powershell
# Copy pair 1 only to inbox and enqueue update queue rows
.\scripts\Install-CircularSeq10ToInbox.ps1 -FileType Both -Pair 1

# Auto-processing (preferred) — wait ~2 min or run manually:
.\scripts\Invoke-RemicsUpdateAutoProcessor.ps1 -MaxFiles 1

# Admin panel alternative:
.\scripts\Invoke-RemicsUpdateValidateAll.ps1
.\scripts\Invoke-RemicsUpdateValidatedAll.ps1
```

Run **delete (`*d`) before add-back (`*a`)** for each pair. After all 10 files per type,
the database returns to its pre-test state.

### Full E2E auto cycle (operator submit → completion email)

```powershell
# One-time bootstrap + repeatable pair-1 cycle (ES recommended first)
.\scripts\Run-Seq10AutoUpdateE2E.ps1 -FileType ES -Pair 1

# Bootstrap only
.\scripts\Run-Seq10AutoUpdateE2E.ps1 -SetupOnly

# Both TS and ES (requires main seeded for both)
.\scripts\Run-Seq10AutoUpdateE2E.ps1 -FileType Both -Pair 1 -SkipBootstrap
```

Single steps:

```powershell
# Simulate operator Transfer to FCSA (import → validate → export → enqueue)
.\scripts\Submit-RemicsDevDbUpdate.ps1 -StagingSource "...\seq10\es\dnd1_*_cyces01d.txt" -FileType ES

# Process queue + send email
.\scripts\Invoke-RemicsUpdateAutoProcessor.ps1 -MaxFiles 1
```

### Operator-side (before inbox)

On **dnd1** (or any account — regenerate with `-Submitter xci1` etc.):

1. Import the staging `.txt` into the operator schema (TS tree / ES tree).
2. Validate the PDF.
3. **Database Update → Transfer to FCSA** (export to `D:\updates\primary\` or ES inbox).

The exported filename uses the logged-in account as submitter; keep generator `-Submitter`
in sync.

## Generate / validate

```powershell
.\scripts\New-CircularSeq10Fixtures.ps1 -Submitter dnd1

# Smoke-test pair 1 against fwmda (requires Initialize-CircularSeq10Main.ps1 first)
.\scripts\New-CircularSeq10Fixtures.ps1 -ValidateSample
```

## Site counts per file

Each pair reuses the same proven smoke sites (net-zero when cycled in order):

| Type | Sites/pair | Master source | Pairs |
|------|----------:|---------------|------:|
| TS | 2 | `rctl-ecomm2601` (same as cmxts03) | 5 |
| ES | 1 | `xci-es140km` (same family as cmxes02) | 5 |

TS and ES sequences are **independent**.

## Troubleshooting

If validate fails after a partial import, drop orphan PDF tables in `fmda2`:

```powershell
powershell -File scripts/Invoke-RemicsDevSql.ps1 -Query `
  "SELECT name FROM sys.tables WHERE name LIKE 'ft_cycts%' OR name LIKE 'fe_cyces%'"
```

Re-run **`Initialize-CircularSeq10Main.ps1`** if `main.*` lost the seq10 site subset.
