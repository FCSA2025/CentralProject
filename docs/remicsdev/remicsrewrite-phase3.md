# RemIcsReWrite Phase 3 — TSIP

**Status:** Implemented (2026-07-31)  
**Entry:** Shell → **Interference Analysis (TSIP) → TSIP Parameters**

## Constraints

- Same ASMX as classic: `Ttsipmenu/TwsTsip.asmx` (`tsipValidateAll`, `tsipRun`, `tsipDelete`) and `TwsTsipTree.asmx` (`tsipTree`, `runList`).
- No direct `TpRunTsip` from the browser; queue via `TsipInitiator`.
- Completion **email suppressed** on remicsdev (`DisableOutgoingEmail`) — use queue poll UI / extractlogs. Re-enable email in Phase 5 ([email-contracts.md](email-contracts.md)).

## UI

| View | Role |
|------|------|
| `views/tsip-parm.html` | List `tp_*_parm`, show runs, open batch |
| `views/tsip-batch.html` | Validate → Run → poll `tsip-status.ashx` |
| `views/tsip-reps.html` | **Phase 3b** — Retrieve TSIP Batch Reports ([phase3b](remicsrewrite-phase3b.md)) |
| `js/remics-tsip-api.js` / `remics-tsip.js` | Client |
| `tsip-status.ashx` | JSON `web.tsip_queue` for current user |

## Smoke (recommended)

Use **rctl1** + parm **`ecomm2602`** (proven). DnD needs a `tp_*_parm` before TSIP smoke.

```powershell
# After login as rctl1 in shell:
# TSIP Parameters → ecomm2602 → Run Batch TSip
```

CLI gold standard (unchanged): `.\scripts\Invoke-LastTsipCompare.ps1 -Fixture ecomm2602`

## Phase 7 reminder (email)

- Set `DisableOutgoingEmail` false after SMTP/queue processor verified.
- Confirm TSIP completion mail body still matches external automation expectations.
