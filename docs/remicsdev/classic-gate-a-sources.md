# Classic Gate A sources (versioned in CentralProject)

RemIcsReWrite still calls classic ASMX/pages for TSIP validation and some file operations. **Company-isolation fixes in those paths must be in Git**, not only on `D:\inetpub\remicsdev\mics`.

## Tracked files

| Repo path | Live path | Gate A change | Rebuild after edit |
|-----------|-----------|---------------|-------------------|
| `config/remicsdev/source/mics/Ttsipmenu/TwsTsip.asmx` | `...\Ttsipmenu\TwsTsip.asmx` | ASMX entry | `mics.csproj` or Ttsipmenu project → `bin\` |
| `config/remicsdev/source/mics/Ttsipmenu/TwsTsip.asmx.cs` | `...\Ttsipmenu\TwsTsip.asmx.cs` | `tsipValidate` / `tsipValidateAll` + `AppendPdfCatalogCheck` (`operator = s_schema`) | Same |
| `config/remicsdev/source/mics/Tfileactions/copy.aspx` | `...\Tfileactions\copy.aspx` | Copy UI (uses `RemIcsApi`) | Markup only — recycle app pool |
| `config/remicsdev/source/mics/Tfileactions/copy.aspx.cs` | `...\Tfileactions\copy.aspx.cs` | Dup check filters `web.user_tables_view` by `operator` | `Tfileactions.csproj` → `bin\Tfileactions.dll` |

**Also tracked (not gitignored):** `lookuptsip/luTsipPdfList.aspx.cs`, `luTsipEnvFileName.aspx.cs` — operator filter on PDF/env lookups.

Everything else under `Ttsipmenu/`, `Tfileactions/`, and sibling classic menu folders remains **local snapshot only** (see `.gitignore`).

## Symlinks (optional, recommended on dev server)

After editing in the repo, point live IIS at repo files:

```powershell
.\scripts\New-RemicsDevSourceLinks.ps1
```

Gate A classic files are included in the script’s `$Mappings` list (same pattern as `tsipBatch.aspx`).

## Workflow

1. Edit tracked file under `config/remicsdev/source/mics/`.
2. If symlinks are active, live path already follows the repo file; otherwise copy to `D:\inetpub\remicsdev\mics\...` or `\\IIS-REMICS-PROD\...`.
3. Rebuild DLL if `.cs` changed (see table above).
4. Run `.\scripts\Invoke-GateAIsolationTest.ps1` (and `Invoke-GateATailIsolationTest.ps1` for rewrite handlers).
5. Commit and push.

## Refresh from live (one-time / drift recovery)

```powershell
$live = '\\IIS-REMICS-PROD\D$\inetpub\remicsdev\mics'
$repo = 'E:\AIProjects\CentralProject\config\remicsdev\source\mics'
@('Ttsipmenu\TwsTsip.asmx','Ttsipmenu\TwsTsip.asmx.cs','Tfileactions\copy.aspx','Tfileactions\copy.aspx.cs') |
  ForEach-Object { Copy-Item -Force (Join-Path $live $_) (Join-Path $repo $_) }
```

## Related

- [remicsrewrite-stabilization-plan.md](remicsrewrite-stabilization-plan.md) — Gate A
- [config/remicsdev/README.md](../../config/remicsdev/README.md) — symlink layout
