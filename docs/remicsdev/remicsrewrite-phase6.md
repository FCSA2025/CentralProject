# RemIcsReWrite Phase 6 — PCN Coordination

**Status:** Implemented (2026-07-31)  
**Entry:** TS/ES Data Files → right-click → **PCN Coordination**

## Flow

1. **Gate** — `UserTable.GetUserValidFlag` (`MUSK`); ES also checks TX channels + scatter distance  
2. **Scan** — `JobSubmit` → `pcnscan` (same args as classic `PcnLookup`)  
3. **Operators** — `{schema}.returnvalues` + emails from `adm.pcn_account_details` (remicsdev)  
4. **Send** — client `exportTable` → optional TS KML → stage `D:\Temp\{tmpdir}` → `SesUtils.send_email_message2` → cleanup  

Email remains **suppressed** until Phase 7 (`DisableOutgoingEmail=true`). Check `extractlogs\{user}PCNSend.txt` and `*EmailSuppressed.txt`.

## Files

| Path | Role |
|------|------|
| `pcn.ashx` | `gate` / `scan` / `operators` / `send` / `attach` |
| `remics-api.js` | `pcnGate`, `pcnScan`, `pcnOperators`, `pcnAttach`, `pcnSend` |
| `js/remics-ts.js` | `mountPcn` |
| `views/ts-file.html` / `es-file.html` | Classic panels |

## Smoke

1. **rctl1**, validated TS → PCN → distance 200 → Find Operators  
2. Confirm operators list (or empty-distance message)  
3. Send PCN → `exportTable` OK; `extractlogs\rctl1PCNSend.txt` shows subject `PCN Notification for TS file …`  
4. Invalidated file → blocked  
5. ES RX-only → skip alert; TX ES → scan without KML checkbox  
