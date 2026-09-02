# RemIcsReWrite Phase 3 — TSIP

**Status:** Implemented (2026-07-31) — historical; Gate C owns current TSIP sign-off ([stabilization plan](remicsrewrite-stabilization-plan.md))  
**Entry:** Shell → **Interference Analysis (TSIP) → TSIP Parameters**

> **Multi-company:** Prefer `Invoke-GateCTsipE2ETest.ps1` + `Invoke-GateCTsipRepsEditTest.ps1` on the roster. Fixture `ecomm2602` is an **rctl** example only.

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

**Automated (preferred):**

```powershell
.\scripts\Invoke-GateCTsipE2ETest.ps1
.\scripts\Invoke-GateCTsipRepsEditTest.ps1
```

**Manual:** pick a roster user that has a completed parm/run in **their** schema. Example for rctl only: parm `ecomm2602`. Other companies need their own `tp_*_parm` before TSIP smoke.

```powershell
# After login as that roster user in the shell:
# TSIP Parameters → <own parm> → Run Batch TSip
```

CLI gold standard (rctl fixture example): `.\scripts\Invoke-LastTsipCompare.ps1 -Fixture ecomm2602`  
For other schemas, use `-BaselineRunId` / latest run for that login.

## Phase 7 reminder (email)

- Set `DisableOutgoingEmail` false after SMTP/queue processor verified.
- Confirm TSIP completion mail body still matches external automation expectations.
