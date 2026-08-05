# dnd1 circular DbUpdate test files

Generated pairs for repeatable **delete sites → add sites back** testing on remicsdev.
Submitter field is `dnd1` (audit only); pipeline still runs as `fwmda`.

## Fixtures

| Set | Sites | Files | Location |
|-----|------:|-------|----------|
| **cmxts03** smoke | 2 | `dndc03del` + `dndc03add` | `cmxts03/` |
| **cmxts01** complex | 274 (6 chunks × ~46) | `dndc01d01`–`dndc01d06` + matching `dndc01a01`–`dndc01a06` | `cmxts01/` |

Delete files transform master sites to `SK,D` / `AK,D` / `CK,D` with `SD` operator `DND`.
Add-back files restore original site content with `SD` operator `DND`.

## Workflow

1. `Install-MicsComplexFixtures.ps1 -Schema dnd -Fixture cmxts03` (or `cmxts01`)
2. Ensure sites exist in `main.*` (run add-back files through pipeline once if needed)
3. Copy **delete** pass files to `D:\updates\primary\`
4. Admin: **Validate all** → **Update all validated** (uses selected update mode)
5. Copy matching **add-back** files → Validate all → Update all validated
6. `Restore-MicsComplexFixtures.ps1 -Schema dnd -Fixture …` if pinned tables need reset

## Regenerate

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/New-Dnd1CircularUpdateFixtures.ps1 -Fixture cmxts03
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/New-Dnd1CircularUpdateFixtures.ps1 -Fixture cmxts01
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/New-Dnd1CircularUpdateFixtures.ps1 -Fixture cmxts03 -InstallToInbox
```

See `cmxts03-manifest.json` / `cmxts01-manifest.json` for file list and byte counts.
