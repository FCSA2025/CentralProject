# RemIcsReWrite — verified bug check (2026-09-09)

**Scope:** False-success / soft-fail paths, Aux Eng deliverables, PDF-edit / SDF key parity.  
**Method:** Code review vs classic + source/live hash match. Candidates rejected unless evidence confirms a real user-facing or data defect.  
**Action:** Document only — no fixes in this pass.

---

## Confirmed bugs

| ID | Sev | Area | Defect | Evidence |
|----|-----|------|--------|----------|
| **E1** | P2 | TS/ES Import UI | After a failed import (body is report name, not `IMPORTOK`), UI alerts “File import failed!” **and still shows `IMPORT COMPLETE`** (`imp-m3`) | `remics-ts.js` `mountImport` ~1171–1176: failure branch `show($('imp-m3'), true)`. `views/ts-file.html` / `es-file.html` hardcode `<b>IMPORT COMPLETE</b>`. Success path also uses `imp-m3`. |
| **E2** | P3 | SDF tree Validate | Status text **“Validate OK”** whenever `valFile` returns `ok` — including when a report was written that lists validation errors | `remics-phase675.js` `sdfFileActions` Validate: `status.textContent = r.ok ? 'Validate OK' : …`. Contrast: TS/ES validate parses report error counts and gates PCN/DbUpdate. |
| **E3** | P3 | PDF Title save | `TitleSave` ignores `ExecuteNonQuery` rowcount → **`ok: true` on 0-row UPDATE** (then may still flip catalog valid flag) | `pdf-edit.ashx` `TitleSave`. Contrast: `AzimDelete`, `pdf-extra`, `sdf-edit` fail closed on 0-row (W4-15/W4-21). Practical only if `_titl` row missing; still dishonest success. |
| **E4** | P1 | SDF **Note** keys | Tree / `delete_note` use **`nonum^oper`**; rewrite form `RecSpec` / `RecKeyJoin` use **`oper^nonum`**. Opening a Note from the tree maps key parts into the wrong columns → load miss. Form Delete after save calls `delete_note` with inverted parts → **ASMX returns OK with 0 rows deleted**, UI returns to tree, row remains | Classic: `noteCode` builds `d^sdf^nonum^oper`; `sdfNote.aspx.cs` maps `keyparts[2]=nonum`, `[3]=oper`; `delete_note` same. Rewrite: `sdf-edit.ashx` Note fields `oper` then `nonum`; `RecKeyValues` assigns tree parts in field order; `remics-sdf-edit.js` Delete uses `'d^'+name+'^'+key`. DS extract `oper:nonum` matches InsertNote — extract save OK; **subsidiary tree/edit path broken**. |

---

## Cleared this pass (not bugs)

| Area | Verdict |
|------|---------|
| Aux Eng (13 tools) | No new open defects vs classic after prior B4/B5/W2-3/W3 fixes; Pattern/PCS/Sep/Coord live, not stubs |
| remics-api `classifyAsmxValue` ERROR/timeout | Fail-closed |
| remics-ds TS/ES save | Uses `dsAsmxOk` (C2) |
| pdf-extra 0-row update/delete | Fail-closed |
| ES azimuth Delete / invalidate | Implemented; safer than classic `delete_azim` |
| ES ante Delete `n.` / `a.` prefix | ASMX ignores prefix; form uses `n.` correctly |
| Ante/Ctx/Plan parent Delete cascade | Same ASMX as classic (child tables deleted) |
| Ctx/Plan/Town/Rout/Traf tree key order vs form | Aligned with classic |
| Source vs live (checked files) | Match |

---

## Suggested fix order (when authorized)

1. **E4** — Align Note key order with classic tree (`nonum^oper`) in `RecSpec` / types / join, **or** special-case Note in `RecKeyValues` / Delete like classic `sdfNote.aspx.cs`. Verify: open from tree, save, form Delete, tree Delete.
2. **E1** — On import failure, show failure panel (or stay on `imp-m0`), never `imp-m3` / “IMPORT COMPLETE”.
3. **E2** — Label status “Validate finished — open report” or parse summary like TS validate; do not say OK if errors present.
4. **E3** — Fail `TitleSave` when `ExecuteNonQuery() == 0` (and ideally if catalog update alone would succeed wrongly).

---

## Fixed 2026-09-09 (cache `2026090904`)

| ID | Fix |
|----|-----|
| **E4** | Note `RecSpec` / `keys` order `nonum`, `oper` (UI still shows Operator then Note Number) |
| **E1** | Import result panel title **IMPORT FAILED** vs **IMPORT COMPLETE** |
| **E2** | SDF Validate fetches report, parses counts, opens report window |
| **E3** | `TitleSave` returns `ok: false` when 0 rows updated |

- E1: `js/remics-ts.js` (`mountImport`), `views/ts-file.html` / `es-file.html` (`imp-m3`)
- E2: `js/remics-phase675.js` (`sdfFileActions` Validate)
- E3: `pdf-edit.ashx` (`TitleSave`)
- E4: `sdf-edit.ashx` (`RecSpec` Note), `js/remics-sdf-types.js`, `js/remics-sdf-edit.js` Delete; classic `Tsdfmenu/TwsSDFTree.asmx.cs` `noteCode` / `delete_note`, `sdfNote.aspx.cs`
