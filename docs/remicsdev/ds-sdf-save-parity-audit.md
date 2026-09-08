# DS-SDF Save parity audit (2026-09-08)

Compares classic `Tdssdf` list-page save contracts (`detkey` / `fcninsert1/2` / `AppendDup*` / `Delete*`) to RemIcsReWrite `ds-sdf.ashx` `KeyParts` and `remics-phase675.js` `SDF_SAVE`, and checks `TwsdsSDF.asmx.cs` colon-split (`kp[]`) arity.

**Per-type:** 11/11 PASS, 0 FAIL.
**Findings (incl. cross-cutting):** 0.
**Live deploy has `dsSdfRowKey`:** True.
**`saveDsSdf` rejects ASMX ERROR bodies:** True.

| Type | Status | Classic page | Classic key | Rewrite keyParts | Insert1 | Insert2 | Issues |
|------|--------|--------------|-------------|------------------|---------|---------|--------|
| Ante | **PASS** | `dsAnteList.aspx` | `acode` | `acode` | `InsertAnte` | InsertAntd |  |
| Band | **PASS** | `dsBand.aspx` | `bndcde` | `bndcde` | `InsertBand` | — |  |
| Ctx | **PASS** | `dsCtxList.aspx` | `tfci:tfcr:rxeqp` | `tfci:tfcr:rxeqp` | `InsertCtx` | InsertCtxd |  |
| Eqpt | **PASS** | `dsEqptList.aspx` | `ecode` | `ecode` | `InsertEqpt` | — |  |
| Oper | **PASS** | `dsOperList.aspx` | `oper` | `oper` | `InsertOper` | — |  |
| Plan | **PASS** | `dsPlanList.aspx` | `sband:splan` | `sband:splan` | `InsertPlan` | InsertPlnd |  |
| Rout | **PASS** | `dsRoutList.aspx` | `rcomp:routnumb` | `rcomp:routnumb` | `InsertRout` | — |  |
| Note | **PASS** | `dsNoteList.aspx` | `oper:nonum` | `oper:nonum` | `InsertNote` | — |  |
| Towr | **PASS** | `dsTowr.aspx` | `twcode` | `twcode` | `InsertTowr` | — | classic Towr sets fcninsert2=InsertTowr (duplicate parent call); rewrite correctly omits insert2 |
| Town | **PASS** | `dsTownList.aspx` | `call1:atwrno` | `call1:atwrno` | `InsertTown` | — |  |
| Traf | **PASS** | `dsTrafList.aspx` | `trafcode:ecode` | `trafcode:ecode` | `InsertTraf` | — |  |

## Cross-cutting findings

- None.

## Notes

- **Towr:** classic Towr sets fcninsert2=InsertTowr (duplicate parent call); rewrite correctly omits insert2

## Method

1. Parse classic `ds*List.aspx` / `dsBand.aspx` / `dsTowr.aspx` for insert/dup/delete + `.cs` detkey.
2. Parse rewrite `KeyParts` + `SDF_SAVE` (source and live IIS).
3. For each Insert*, detect colon `kp[]` arity in `TwsdsSDF.asmx.cs`.
4. Flag `saveDsSdf` if it does not reject `ERROR*` ASMX bodies.

## Runtime

Ran `scripts/Invoke-DsSdfSaveParitySmoke.ps1` against remicsdev (rctl / rctl1): **11/11 PASS** (createTable → Insert → optional Insert2 → AppendDup verify → killTable). Composite keys exercised for Ctx, Plan, Note, Rout, Town, Traf; detail inserts for Ante/Ctx/Plan returned empty success bodies.

### Remaining high-yield areas (2026-09-08 follow-up)

| Area | Result |
|------|--------|
| SDF composite keys + insert2 map | Covered above (B1/B2) |
| SDF detail row counts (Ante/Ctx/Plan) | **PASS** — e.g. Ante parent=1 detail=35; Ctx detail=18; Plan detail=2 |
| Key separator drift (`^` vs `:` vs `}`) | **B3 found+fixed** — TS link/OE used `,` instead of classic `}`; sdf-edit `^` stays on `sdf-edit.ashx` only (not TwsdsSDF) |
| ES Data Search save | **PASS** (small) — location keys via `StoreKeys` match classic; full E2E cleared 2026-09-08 |
| ES StoreKeys 100-key `.` chunks | **PASS (B6 fixed 2026-09-08)** — classic `.` every 100 keys + per-block `StoreKeys`; smoke `Invoke-B6EsChunkSmoke.ps1` 12/12 |

Identify/verify: `scripts/Invoke-DsBugHuntIdentifyVerify.ps1` (TS/ES save E2E + owhere cleared). B6 fixed — `Invoke-B6EsChunkSmoke.ps1`.

Repeat: `scripts/Invoke-DsRemainingAreasSmoke.ps1`.

Machine-readable: `tmp-tsjob/ds-sdf-save-audit.json`, `tmp-tsjob/ds-sdf-save-smoke.json`, `tmp-tsjob/ds-remaining-areas-smoke.json`

