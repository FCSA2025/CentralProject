# RemIcsReWrite Phase 2 — Database Update (Transfer to FCSA)

**Status:** Implemented (2026-07-31)  
**Entry:** Shell → TS Data Files → right-click → **Database Update**

## Constraints

Same as Phase 1: batch output identity via `TwsTabUtil.asmx/exportForUpdate` (`ftPrint` + staging under `updates\primary\`). UI labels match `Tpcnmenu/DbUpdate.aspx`.

## Flow

1. **Gate** — `GET dbupdate.ashx?name=&filetype=TS` mirrors classic `GetUserValidFlag` rules (`N`/`T`/`L`/empty block; `P`/`S`/`K` warn but allow).
2. **Transfer** — `RemIcsApi.exportForUpdate(..., { userFcsa: 'F' })`.
3. **Notify** — `POST dbupdate.ashx` ports `EMAIL_Click` (subject/body/CC + `SesUtils.send_email_message2`).
4. Success alert: **Transfer for database update complete.**

**Email:** Outgoing mail is **suppressed** on remicsdev (`DisableOutgoingEmail=true`). Bodies are logged to `extractlogs\{user}EmailSuppressed.txt`. Contract documented in [email-contracts.md](email-contracts.md); re-enable in Phase 5.

**Not in Phase 2 for TS:** User Database Update button (classic hardcodes `userupdate=0` for TS).

## Files

| Path | Role |
|------|------|
| `RemIcsReWrite/dbupdate.ashx` | Gate + email notify |
| `remics-api.js` | `dbUpdateGate`, `dbUpdateNotify` |
| `js/remics-ts.js` | `mountDbUpdate` |
| `views/ts-file.html` | `panel-dbupdate` |
| `views/ts-tree.html` | Context menu enabled |

## Manual check

1. Validate a file first if status is `N` (blocked until validated).  
2. Database Update → **Transfer to FCSA for update**.  
3. Confirm staging file under `{web_drive}\updates\primary\` and extract log `extractlogs\{user}PCNDbUpdate.txt`.  
