# RemIcsReWrite Phase 4 — ES parity + nav polish

**Status:** Implemented (2026-07-31)  
**Entry:** Shell → **File → ES Data Files**

## Scope

| Item | Notes |
|------|--------|
| ES tree | `files.ashx?filetype=ES` → `fe_%_titl` |
| File ops | Same `TwsTabUtil.asmx` as TS with `filetype: 'ES'` → `feValidate` / `fePrint` / `feImport` / `KillTable` / `copy` |
| Validate UI | No HiLo / Verbose (classic ES) |
| Database Update | `dbupdate.ashx` already ES-aware (`tabletype` 5) |
| Nav polish | ES enabled; Reports group placeholders (disabled) |

## Files

| Path | Role |
|------|------|
| `views/es-tree.html` / `es-file.html` | ES chrome |
| `js/remics-ts.js` | Shared TS/ES module (`filetype` from view) |
| `js/remics-nav.js` | ES Data Files + deferred Reports |
| `js/remics-app.js` | Mount `es-tree` / `es-file` |

## Out of scope (later)

- ES child edit tree (`esTitle`, sites, azim, cloc, ccal)
- PCN Coordination (`PcnES.aspx`)
- Create new ES master (empty file)
- Full Reports / FCC / ISED menus

## Smoke

Prefer a schema with `fe_*_titl` (e.g. `testes1` / fixtures). As that user:

1. **ES Data Files** → list loads  
2. Right-click → Validate → submit log shows **`feValidate`** (not `ftValidate`)  
3. Display Results opens `userdirs/.../{name}.txt`  
4. Export / Copy / Delete with `filetype: ES`
