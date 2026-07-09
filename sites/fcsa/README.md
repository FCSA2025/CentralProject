# FCSA static site

Self-hosted static copy of public [fcsa.ca](https://fcsa.ca) content for IIS on this server.

## Layout

| Path | Purpose |
|------|---------|
| `scripts/Build-FcsaSite.ps1` | Extract from WordPress REST API + build HTML to `dist/` |
| `scripts/Deploy-FcsaIis.ps1` | Deploy `dist/` to `D:\inetpub\fcsa` and configure IIS |
| `src/css/site.css` | Site stylesheet |
| `src/js/site.js` | Mobile nav toggle |
| `dist/` | Build output (deployed to IIS) |
| `docs/fcsa-url-map.csv` | WordPress URL → new path mapping |
| `docs/assets-manifest.csv` | Downloaded media inventory |

## Rebuild and deploy

```powershell
cd E:\AIProjects\CentralProject
.\sites\fcsa\scripts\Build-FcsaSite.ps1
.\sites\fcsa\scripts\Deploy-FcsaIis.ps1   # requires Administrator
```

## Testing

- Home: `http://localhost/` or `http://35.182.140.161/`
- French: `http://localhost/fr/`
- MICS (unchanged): `http://remicsdev.cloudmicsdev.ca/mics/`

See [docs/fcsa/fcsa-migration-plan.md](../../docs/fcsa/fcsa-migration-plan.md) for full scope.
