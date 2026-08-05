# Outgoing email contracts (remicsdev)

**Status (2026-07-31):** Outgoing email is **disabled** on remicsdev via `web.config` → `DisableOutgoingEmail=true`.  
All `SesUtils.send_email_*` entry points log to `D:\extractlogs\{user}EmailSuppressed.txt` and return success without queue/SMTP.

**Re-enable:** RemIcsReWrite **Phase 7** — set `DisableOutgoingEmail` to `false` (or remove the key) after SMTP/`adm.t_EmailQueue` processor is verified. Do not leave suppressed in production. (Phase 5 is raw-IP cookies only.)

---

## Database Update / Transfer to FCSA

Used by classic `Tpcnmenu/DbUpdate.aspx` `EMAIL_Click` and RemIcsReWrite `dbupdate.ashx` notify.

| Field | Value |
|-------|--------|
| From | User’s `adm.account_details.email` (also CC’d) |
| To | FCSA ops (via `SesUtils.send_email_message2(..., FCSA: 1, ...)`) |
| Subject | `Database Update Request for {sType} file {sName}` |
| Body (FCSA / `UserFcsa=F`) | See template below |
| Body (user update / `UserFcsa=U`) | Same skeleton; “submitted for user update” instead of “released for FCSA update” |

### Body template (FCSA transfer) — external automation depends on this shape

```text
The {sType} file {sName} has been released for FCSA update of MICS by

ACCOUNT ID: {schema}

USER ID: {micsid}

```

Example:

```text
The TS file cmxts01 has been released for FCSA update of MICS by

ACCOUNT ID: dnd

USER ID: dnd1

```

### Body template (user update — rarely enabled for TS)

```text
The {sType} file {sName} has been submitted for user update of MICS by

ACCOUNT ID: {schema}

USER ID: {micsid}

```

---

## PCN Notification (Phase 6)

Used by classic `Tpcnmenu/PcnDisplay.aspx` `SEND_Click` and RemIcsReWrite `pcn.ashx` send.

| Field | Value |
|-------|--------|
| Subject | `PCN Notification for {sType} file {pdfName}` |
| Body | See template below |
| Attachments | Export `{pdfName}.txt`, optional `ts_{pdfName}.kml` (TS), optional local uploads |
| FCSA flag | Production `2`; remicsdev/micstest override `0` with To = sender + plin@fcsa.ca + jscott@fcsa.ca |

### Body template

```text
This PCN has been sent by: {senderEmail}

Please be advised, the following file has been submitted for coordination:

{sType} {pdfName}

A copy is attached for import to Webmics. Recipients must respond with any objections
within 30 days from the date and time of this notice.

Note: {optional notes}
```

Related subjects (missing recipient addresses):

- `Missing email address for {sType} file {pdfName}`
- `All email addresses missing for {sType} file {pdfName}`

---

## Other email types (also suppressed while flag is true)

| Source | Notes |
|--------|--------|
| `send_email_sql3` | Active path that inserts `adm.t_EmailQueue` (login, FCC, ISED, pwd recovery, emailus, …) |
| `send_email_message` / `message2` / `sql` / `sql2` | Mostly stubbed/no-op before kill switch; still gated |
| TSIP completion mail | Batch/`TpRunTsip` path — confirm separately when re-enabling |

When re-enabling, capture one live sample of each automation-critical subject/body into this doc or `tests/remicsdev/fixtures/email-samples/`.

---

## Kill switch

```xml
<add key="DisableOutgoingEmail" value="true" />
```

Implementation: `SesUtilities.SesUtils.IsOutgoingEmailDisabled()` in `utilities/SesUtils.cs` (requires `mics.dll` rebuild after code change).
