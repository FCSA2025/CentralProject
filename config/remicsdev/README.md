# remicsdev live config links

Links between CentralProject and the IIS web app on **`D:\inetpub\remicsdev\mics`**.

## Layout

| Repo path | Live path | Direction | Git |
|-----------|-----------|-----------|-----|
| `mics/Tlogin.aspx` (+ `.cs`, `.designer.cs`) | `D:\inetpub\remicsdev\mics\...` | Repo **symlink →** live | Symlink (120000) |
| `mics/web.config` | `D:\inetpub\remicsdev\mics\web.config` | Live **symlink →** repo | **Full file tracked** |

**Edit `config/remicsdev/mics/web.config` in the repo** — IIS uses the same file via the reverse symlink on `D:`. Commit and push for history (domain migration, URLs, `LoginTitle`, etc.).

**Security:** `web.config` contains AD keys and connection strings. This repo is intended for your org/server migration workflow; treat access accordingly.

## Recreate links on this server

```powershell
.\scripts\New-RemicsDevConfigLinks.ps1
```

Requires permission to create symbolic links (Developer Mode or elevated PowerShell).

## After editing code-behind

Rebuild `mics.dll` after `Tlogin.aspx.cs` changes:

```powershell
& "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe" `
  "D:\inetpub\remicsdev\mics\mics.csproj" /t:Build /p:Configuration=Debug
```

Markup-only `.aspx` and `web.config` appSettings apply without rebuild (IIS may recycle the app pool on `web.config` save).

## Domain / URL migration

Search and update in **`config/remicsdev/mics/web.config`**: `SiteName`, `SiteDomain`, `DevUrl`, `TestUrl`, `HelpUrl`, bindings-related keys, etc. Then commit. No separate copy on `D:` to sync manually.

## New server (not cloning this EC2)

Copy the repo, place `web.config` at the chosen hub path, run `New-RemicsDevConfigLinks.ps1` with `-LiveMicsRoot` set to that server's inetpub `mics` folder.
