# RemIcsReWrite — delete options audit (document only)

**Date:** 2026-09-09  
**Scope:** User reports that multiple file types have **no Delete** in the rewrite, including work done under Auxiliary Engineering.  
**Action taken:** Inventory only — **no code or UI changes**.

Compare classic WebMICS trees/forms vs RemIcsReWrite. Classic delete is almost always a **right-click context menu** (Telerik). Rewrite mirrors that pattern in most trees.

---

## Verdict (short)

| Area | Delete available in rewrite? | vs classic |
|------|------------------------------|------------|
| TS / ES **whole file** | Yes — tree context **Delete** → delete panel / `killTable` | Parity |
| TS **site / link / antenna / channel / chng** | Yes — context Delete (correct nodes) | Parity |
| ES **site / antenna folder / channel / cloc / ccal** | Yes — Delete Site / Delete Antenna / Delete on correct nodes | Parity |
| ES **azimuth** | **No** — neither tree nor Azimuths panel | **Gap** — classic `esAzimuth.aspx` has per-row **Delete** → `delete_azim` |
| SDF subsidiary (Ante, Band, Ctx, Eqpt, …) **file** | Yes — right-click file → **Delete file** | Parity (classic **Delete File**) |
| SDF subsidiary **record** | Yes — right-click record → **Delete record** | Parity (classic **Delete**) |
| SDF edit form (parent record) | No Delete button on form | Same as classic (delete from tree) |
| SDF child rows (discr / CTX detail / Plan detail) | Yes — **Delete** on child grid | Parity |
| Antenna RPE / DS extract (`ds-sdf`) | No file/record delete on extract UI | Same as classic extract pages |
| Aux Eng tools (Gen CTX, Pattern, OHL, Terrain, PFD, …) | No catalogue delete UI | Same as classic Aux Eng — outputs/files live elsewhere |
| TSIP parm / run / reports / queue | Explicit Delete buttons (often gated on selection) | Parity (with prior U1 discoverability fixes) |

Most “no delete” reports are likely **discoverability / wrong node / wrong menu**, not missing `killTable` wiring — except **ES azimuth Delete**, which is a real rewrite omission.

---

## How delete works in the rewrite

1. **Trees** (TS, ES, SDF): status text says “Right-click for actions”. There is usually **no toolbar Delete**.
2. **File delete** uses `TwsTabUtil.asmx/killTable` (same as classic).
3. **Record delete** uses classic ASMX (`delete_ts_*`, `delete_es_*`, `delete_*` SDF methods).
4. **Aux Eng** and **ds-sdf** create or extract into **Subsidiary Data Files** (or email/download reports). Deleting those catalogues is under **File → Subsidiary Data Files → …**, not under Aux Eng.

---

## Detailed inventory

### 1. Terrestrial (TS) data files

| Node | Classic menu | Rewrite (`remics-tree.js`) | Notes |
|------|--------------|----------------------------|--------|
| File `e` | Validate / Export / PCN / DbUpdate / **Delete** / Copy / KML | Same (+ Edit Contents) | OK |
| Site header `s` | New Link + **Delete** | Edit / Dup / New Link / **Delete** | Delete present |
| Link `k` | **Delete** | **Delete** | OK |
| Antenna `a` | Edit + **Delete** | Edit / Dup / **Delete** | OK |
| Channel `c` | Edit + **Delete** | Edit / Dup / **Delete** | OK |
| Change of call `g` | Edit + **Delete** | Edit + **Delete** | OK |
| Site data `d` / title `t` | Edit only | Edit (+ Dup on `d`) | No delete — same as classic |

**User pitfall:** Delete is on the **site/link/antenna/channel** node via right-click, not a button on the edit form.

### 2. Earth station (ES) data files

| Node | Classic menu | Rewrite | Notes |
|------|--------------|---------|--------|
| File `e` | … / **Delete** / Copy | Same | OK |
| Site header `s` | **Delete Site** (+ New Antenna) | Edit / Dup / **Delete Site** / New Antenna | OK |
| Antenna **folder** `n` | **Delete Antenna** (+ New Channel / New Azimuth) | Edit / Dup / **Delete Antenna** / New Channel / New Azimuth | OK |
| Antenna **data** `a` | Edit only | Edit / Dup | **No Delete** — same as classic; delete is on folder `n` |
| Channel `h` | Edit + **Delete** | Edit / Dup / **Delete** | OK |
| Azimuth `m` | Edit only (tree) | Edit / Dup | Tree never had Delete |
| CLOC / CCAL | Edit + **Delete** | Edit + **Delete** | OK |

#### Confirmed gap — ES azimuth Delete (**D1**)

- Classic: open azimuth list (`esAzimuth.aspx`); each row has **Edit** and **Delete**; Delete calls `TwsESTree.asmx/delete_azim`.
- Rewrite: `pdf-edit` Azimuths panel has New / Save / Dup / Cancel — **no Delete**. No `azimDelete` / `delete_azim` path in RemIcsReWrite JS/handlers found.
- Tree context on `m` correctly matches classic (Edit only); classic relied on the **form**, which rewrite did not port.

### 3. Subsidiary Data Files (SDF) — Ante, Band, Ctx, Eqpt, Oper, Plan, Rout, Note, Towr, Town, Traf

| Action | Classic (`Tsdfmenu` + `sdfTreeLib.js`) | Rewrite |
|--------|----------------------------------------|---------|
| Delete whole file | Right-click file `e` → **Delete File** → `killTable` | Right-click file → **Delete file** → `killTable` |
| Delete record | Right-click record `d` → **Delete** → `delete_*` | Right-click record → **Delete record** → `sdfTreeCall(deleteFn)` |
| All 11 types | Per-type trees with same menus | `remics-sdf-tree.js` maps each type’s `deleteFn` |

**UX / discoverability (**D2**):**

- Rewrite `views/sdf-tree.html` hint: “right-click a **record** to Edit” — does **not** mention Delete file or Delete record.
- Toolbar has Create / Refresh / Help only (no Delete).
- Users who create Ante files via **Antenna RPE** or Ctx via **Generate CTX Curves** must leave Aux Eng and open **Subsidiary Data Files** to delete; nothing in Aux Eng exposes Delete.

This matches classic placement, but rewrite copy makes Delete easier to miss.

### 4. Antenna RPE / DS extract (`#/ds-sdf?type=Ante`)

- Saves into Ante subsidiary tables (including discrimination via `InsertAntd`).
- **No** Delete control on the extract/save UI (classic `dsAnte` / list extract path likewise does not delete catalogues).
- After save, rewrite navigates toward Subsidiary Antennas — delete there via right-click.

Same pattern for other DS SDF extract types (Ctx, etc.).

### 5. Auxiliary Engineering

Tools under `#/aux-eng?tool=…` are calculators / report generators (distance, passive, pattern, PCS, sat, sep, coord, orbit, OHL, NAD27, terrain, PFD, genctx, hilo).

| Expectation | Reality |
|-------------|---------|
| Delete “files” from Aux Eng | **Neither classic nor rewrite** provide a file-catalogue Delete here |
| Gen CTX Save | Creates/updates **CTX** subsidiary data — delete under **Subsidiary → CTX** |
| Antenna RPE (nav may land on `ds-sdf`) | Catalogue under **Subsidiary → Antennas** |
| OHL / Terrain / PFD / etc. | Email / CSV / download outputs — not SDF file trees |

**D3:** Reports of “no delete in Aux Eng” are **expected product shape**, not a missing classic feature — but users may not know where files landed.

### 6. TSIP

Parm file Delete, run Delete, report Delete, Delete TSIP Job — present as buttons (often disabled until selection). Prior U1 work addressed false-enabled alerts. Not the focus of this audit; no new TSIP delete omission found vs classic.

---

## Likely user-facing confusion (not missing backend)

1. **Right-click only** — same as classic, but less obvious without Telerik chrome.
2. **Wrong node** — e.g. ES antenna leaf (`a`) has no Delete; need antenna **folder** (`n`) or site header for cascade deletes.
3. **Wrong section** — Aux Eng / RPE / Gen CTX vs **Subsidiary Data Files**.
4. **SDF hint** underplays Delete.
5. **Touch / trackpad** — context menu harder than classic desktop habit.

---

## Open items (no fix yet)

| ID | Sev | Issue | Classic | Rewrite |
|----|-----|-------|---------|---------|
| **D1** | P2 | ES azimuth Delete missing | Form Delete → `delete_azim` | No UI / no rewrite handler found |
| **D2** | P3 | SDF / tree Delete hard to discover | Context menus; file menu says Delete File | Delete exists; hint/toolbar omit Delete |
| **D3** | info | Aux Eng has no catalogue Delete | Same | Same — document for support |

---

## Source pointers

- Rewrite menus: `js/remics-tree.js` (`menuItems`), `js/remics-phase675.js` (`mountSdfTree` / `sdfFileActions`)
- Rewrite deletes: `js/remics-ts.js` (`deleteTreeNode`, `mountDelete`), `js/remics-sdf-tree.js` (`deleteFn`)
- Classic: `Ttsmenu/tsTree.aspx`, `Tesmenu/esTree.aspx`, `Tesmenu/esAzimuth.aspx` (+ `delete_azim`), `Tsdfmenu/sdf*Tree.aspx` + `sdfTreeLib.js`
- Azimuths UI: `views/pdf-edit.html` (`pdf-panel-azims`) — no Delete control

---

## Follow-up (when authorized)

1. Port classic azimuth row Delete (call `delete_azim` or equivalent) into rewrite Azimuths panel.
2. Optionally improve SDF tree hint / status to mention **right-click file → Delete file** and **right-click record → Delete record**.
3. Optionally add short Aux Eng note after Gen CTX / RPE save: “Delete catalogues under Subsidiary Data Files.”

---

## Implemented 2026-09-09 (beyond classic)

Shipped in rewrite (cache `2026090903`) — **not** classic parity only:

| Area | Change |
|------|--------|
| **D1 ES azimuth** | `azimDelete` in `pdf-edit.ashx`; **Del** on list + **Delete** on form |
| PDF site / ante / chan / link | Form **Delete** + list **Del** (ASMX cascade) |
| ES antenna leaf `a` | Context **Delete** (classic Edit-only) |
| TS/ES trees | **Delete selected** button |
| SDF tree | **Delete file** / **Delete record** buttons + clearer hint |
| SDF edit | Parent **Delete** button |
| Aux Eng Gen CTX | **Delete CTX subsidiary files** panel |
| Aux Eng HiLo | **Delete file** for selected TS proposed file |
| ds-sdf / Antenna RPE | **Delete SDF file** panel for current type |
