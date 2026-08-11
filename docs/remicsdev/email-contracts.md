# Outgoing email contracts (remicsdev)

**Status (2026-08-07):** remicsdev uses **`adm.t_EmailQueue_local`** + **Email Queue Local** job on EC2AMAZ-9DKDM82. Attachments staged on IIS-REMICS-PROD (`D:\MicsEmailStaging` → UNC `\\IIS-REMICS-PROD\MicsEmailStaging\...`). Legacy **`adm.t_EmailQueue`** unchanged for prod.

**Handoff:** [`email-queue-rollout-handoff.md`](email-queue-rollout-handoff.md) | Local job: [`email-queue-local-agent-job.sql`](email-queue-local-agent-job.sql) | Legacy job: [`email-queue-agent-job.sql`](email-queue-agent-job.sql)

---

## Queue row format

| Column | Value |
|--------|--------|
| `mailFrom` | `mics.fcsa.ca` or `mics@fcsa.ca` |
| `mailTo` | Intended recipients (redirected when `EmailRedirectAllTo` set) |
| `mailCC` | NULL or CC list |
| `mailSubject` | From templates below |
| `mailBody` | From templates + redirect footer when applicable |
| `mailBodyFormat` | `TEXT` |
| `mailAttachments` | Semicolon-separated full paths; remicsdev uses UNC `\\IIS-REMICS-PROD\MicsEmailStaging\...` after staging |
| `sentYN` | `N` |

Implementation: `SesUtilities.SesUtils.InsertEmailQueue` in `utilities/SesUtils.cs` (compiled to `utilities.dll`).

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
| Delivery | `SesUtils.InsertEmailQueue` (FCSA flag 2 in production; dev override keeps sender + plin + jscott) |

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

## Password reset

Used by classic `Maintenance/pwdrecov.aspx.cs` `sendemails()` and RemIcsReWrite `pwd-reset.aspx`.

| Mail | Subject | Body |
|------|---------|------|
| User | `New MICS password` | `The new password generated for user {id} is: {password}` |
| FCSA | `New MICS password` | `A new password was generated for user {id}` |

Two queue INSERTs via `InsertEmailQueue` / `send_email_sql(..., FCSA: 1)`.

---

## TSIP completion mail

Batch `TsipInitiator/TsipEmail.cs` — INSERT into queue with classic subject/body. **Phase 2:** `mailAttachments = NULL` (text only). Redirect via `EmailRedirectAllTo` in `App.config`.

**Success subject:** `TSIP output for {root}, first filename: {file} at {timestamp}`  
**Success body:** `No Errors` (+ redirect footer when redirected)

---

## Config keys (remicsdev testing — 2026-08-07)

```xml
<add key="DisableOutgoingEmail" value="false" />
<add key="EmailRedirectAllTo" value="" />
```

Operator emails normalized in SQL ([`ddl/remicsdev-test-email-normalize.sql`](ddl/remicsdev-test-email-normalize.sql)):

- `dbo.t_UserDetails.email`
- `adm.account_details.email` (DbUpdate notify + auto-processor submitter)
- `adm.pcn_account_details.email` (PCN on remicsdev)

All set to `jscott@fcsa.ca` for end-to-end testing without redirect footers.

**Agent schedules:** Update Queue Local every 10 min; Email Queue Local every 2 min.

### Removal checklist (production cutover)

1. Restore real operator emails from backup (reverse normalize script export)
2. Remove or clear `EmailRedirectAllTo` on all sites and TsipInitiator `App.config` (already empty on remicsdev)
3. Set `DisableOutgoingEmail` to `true` if legacy log-only paths should be suppressed again
4. Verify SQL Agent jobs process queues on schedule
5. Capture live samples into `tests/remicsdev/fixtures/email-samples/` if needed

### Previous testing config (superseded)

```xml
<add key="DisableOutgoingEmail" value="true" />
<add key="EmailRedirectAllTo" value="jscott@fcsa.ca" />
```

---

## Verification query

```sql
SELECT TOP 5 mail_sequence, mailTo, mailSubject, sentYN, SentDate
FROM adm.t_EmailQueue_local ORDER BY mail_sequence DESC;
```
