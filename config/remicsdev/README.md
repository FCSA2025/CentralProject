# remicsdev live config symlinks

Symlinks from CentralProject to the IIS web app on **`D:\inetpub\remicsdev\mics`**. Edit files here (or under `mics/`) — changes apply to the live site without moving files.

## Layout

| Repo path | Live path |
|-----------|-----------|
| `mics/Tlogin.aspx` | `D:\inetpub\remicsdev\mics\Tlogin.aspx` |
| `mics/Tlogin.aspx.cs` | `D:\inetpub\remicsdev\mics\Tlogin.aspx.cs` |
| `mics/Tlogin.aspx.designer.cs` | `D:\inetpub\remicsdev\mics\Tlogin.aspx.designer.cs` |
| `mics/web.config` | `D:\inetpub\remicsdev\mics\web.config` (symlink local only; **gitignored** — contains secrets) |

Tracked without secrets: **`web.config.login-title.snippet.xml`** — merge `LoginTitle` into live `web.config`.

## Recreate on this server

```powershell
.\scripts\New-RemicsDevConfigLinks.ps1
```

Requires permission to create symbolic links (Developer Mode or elevated PowerShell).

## After editing code-behind

Rebuild and deploy:

```powershell
& "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe" `
  "D:\inetpub\remicsdev\mics\mics.csproj" /t:Build /p:Configuration=Debug
```

Markup-only `.aspx` and `web.config` appSettings take effect without rebuild.

## New machine

Clones get **file contents** for tracked paths (Windows `core.symlinks=false`), not live symlinks. Run `New-RemicsDevConfigLinks.ps1` after adjusting `$LiveMicsRoot` if paths differ.
