# Source vs deployed binary drift check

**Status:** Planned (procedure documented, not yet executed)  
**Related:** [MDB site fetch bug analysis](mdb-site-fetch-bug-analysis.md)

Safe procedure to verify that `D:\develbat\TpRunTsip.exe` and `D:\develbat\_Utillib.dll` match a **fresh compile** of our on-server source under `D:\MicsBatchProgs\MicsBat\`.

## Question answered

> Does what TSIP runs today match what our `.cs` source would produce if compiled now?

External code (e.g. Si Ke's proposal) is **out of scope** for this check.

## Safe approach

1. Build `_Utillib` and `TpRunTsip` to a **temp folder only** (e.g. `D:\temp\mics-build-verify\`)
2. **Do not copy** output to `D:\develbat\`
3. SHA256-compare fresh `_Utillib.dll` and `TpRunTsip.exe` against deployed copies
4. If hashes differ, decompile both with `ilspycmd` and diff `MtGetSiteWN`, `MtCloseSite`, `TtFullSiteGet`

## Build commands

```powershell
$verifyRoot = 'D:\temp\mics-build-verify'
New-Item -ItemType Directory -Force -Path $verifyRoot | Out-Null

$msbuild = 'C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe'

& $msbuild 'D:\MicsBatchProgs\MicsBat\_Utillib\_Utillib.csproj' `
  /t:Rebuild /p:Configuration=Release /p:Platform=x64 /p:OutputPath=$verifyRoot\

& $msbuild 'D:\MicsBatchProgs\MicsBat\TpRunTsip\TpRunTsip.csproj' `
  /t:Rebuild /p:Configuration=Release /p:Platform=x64 /p:OutputPath=$verifyRoot\
```

## Compare

```powershell
@('_Utillib.dll','TpRunTsip.exe') | ForEach-Object {
  $f = $_
  $match = (Get-FileHash "$verifyRoot\$f").Hash -eq (Get-FileHash "D:\develbat\$f").Hash
  "$f match=$match"
}
```

## Pre-checks already done (2026-07-24)

| Check | Result |
|-------|--------|
| `_Utillib` `.cs` — `MicsBatchProgs` vs `inetpub\mics` | Identical |
| `D:\develbat` vs `_bin\Release` | Identical for both DLL and EXE |
| Deployed DLL contains `MtGetSiteWN` | Yes |

A full isolated rebuild is still recommended for definitive proof.

## Outcomes

| Hash result | Action |
|-------------|--------|
| Match | Trust source-level bug analysis for deployed code |
| Mismatch | Investigate build/deploy drift before changing logic |
