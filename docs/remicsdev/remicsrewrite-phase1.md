# RemIcsReWrite Phase 1 — TS file ops (classic UI, identical reports)

**Status:** Implemented (2026-07-31)  
**Entry:** `http://remicsdev.cloudmicsdev.ca/mics/RemIcsReWrite/login.aspx` → `shell.aspx#/ts-tree`

## Constraints (product)

1. **Report output identity** — Validate / Export / Import still call `Tfileactions/TwsTabUtil.asmx` → the same `ftValidate` / `ftPrint` / `ftImport` / `KillTable` / `CopyTable` binaries with the same argument shapes. Report files land at:

   `userdirs/{schema}/{user}/{name}.txt`

   External automation must see the **same bytes** as the classic UI. The rewrite must never reformat, filter, or regenerate report text in JavaScript.

2. **Classic look** — Cream (`#ffffcc`), sky-blue top bar (`#87cefa`), maroon labels, gray `.bt` buttons, centered `FCSA MICS …` headings, marquees, and **Display Results** via `window.open` on the userdirs `.txt` — matching legacy `Tfileactions/*.aspx` and `tsTree` interaction, without frames/Telerik.

## What shipped

| Piece | Role |
|-------|------|
| `files.ashx` | JSON TS list (same `ft_%_titl` INFORMATION_SCHEMA query as classic tree) |
| `views/ts-tree.html` + `js/remics-ts.js` | File list + right-click menu (Validate / Export / Import / Delete / Copy) |
| `views/ts-file.html` | Classic wizards; Display Results opens raw report URL |
| `shell.aspx` | Project Code + Active File fields (navigationTop parity) |
| Diagnostic harness | Still at `index.aspx?harness=1` / `file.aspx` (blue debug UI — not the product path) |

## Deferred

- PCN Coordination, Database Update (Phase 2)
- TSIP (Phase 3), ES tree (Phase 4)
- Site/antenna/channel edit trees inside a PDF

## Manual check

1. Login as `dnd1` (or `rctl1`) via RemIcsReWrite login  
2. **TS Data Files** → list shows `cmxts01` / `cmxts03`  
3. Right-click → Validate → **Display Results** → popup shows ftValidate text unchanged  
4. Compare path/size with a classic validate on the same file if needed  
