# Post-fix adjacent bug hunt — 2026-09-08

**Scope:** Categories 1–6 recommended after B1–B6 fixes.  
**Script:** `scripts/Invoke-PostFixAdjacentBugHunt.ps1`  
**Evidence:** `tmp-tsjob/postfix-adjacent-bughunt-2026-09-08.json`  
**Mode:** Identify + verify only — **no fixes applied**.

## Confirmed bugs

| ID | Cat | Sev | Bug |
|----|-----|-----|-----|
| **B7** | 6 | P2 | **ES cull temp tables missing for some company schemas** — **Fixed 2026-09-08** — provisioned `cull_temp{1,2,3}_es` on aliant, bchy, bell, bmce, bragg, dnd, tbay, tels, terago via `ddl/b7-create-es-cull-temp-tables.sql`. Same day: TS `cull_temp{1,2,3}` via `ddl/b7-create-ts-cull-temp-tables.sql`. Live: bchy1 ES 101 sites + TS 20 links. |

## Cleared (no bug found)

| Cat | Area | Result |
|-----|------|--------|
| 1 | Batch email (`MicsEmail` / queue) | `Send`→`SendSql`; PFD/LAML/SMTP/TsipInitiator configs use `adm.t_EmailQueue_local`; live `SMTP.exe` queues successfully |
| 2 | ES save filtered + 101 keys + keep/over | 101 sites saved to both PDFs with `owhere` + chunked `StoreKeys` |
| 3 | Aux Eng lat/long | Passive abbrev OK (B4 holds); Terrain/PFD/SatAZE accept `45-30N`; Orbit rejects abbrev **same as classic** |
| 4 | SDF Ante >60 + `InsertAntd` | 61 antennas → 2 chunks → `su_*_ante`=61, `su_*_antd`=937 |
| 5 | TS large multi-select | 80 links → sites/chans populated via `}` keys |

## Notes (not bugs)

- Classic SDF `;` chunk boundaries (~59 then 60) vs rewrite equal batches of 60 — both accepted by ASMX.
- Classic TS has no client `.` StoreKeys chunking; server `SaveKeys*` loops — large save OK at 80.
- `Ssutil.SendEmail` has no external callers; PFD uses `Products.SendEmail` → `SendSql`.
