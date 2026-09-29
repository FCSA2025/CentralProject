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

## PFD / Coverage Contours (Aux Eng)

Batch `PFDcont` → `Products.WriteFilesSendEmail` → `MicsEmail.Send` / `SendSql` (in `_Utillib`). Web UI (`aux-pfd.ashx` / classic `AUXpfdc1`) only submits the job; delivery is from the batch after `.rep`/`.csv`/MapInfo/KML files are written.

| Field | Value |
|-------|--------|
| Subject | `PFDCont Report: {base}.rep` (also CSV / MapInfo / KML variants) |
| Body | `See Attachement ...` |
| Attachments | Staged under `D:\MicsEmailStaging` → UNC for SQL Agent |
| Queue | remicsdev: `adm.t_EmailQueue_local` via `PFDcont.exe.config` `EmailQueueTable` |

**Fixed 2026-09-08 (B5):** `MicsEmail.Send` previously never executed the INSERT; reports landed on disk but never queued.

---

## LAML reports / SMTP test tool

| Program | Path | Notes |
|---------|------|-------|
| **SendLAMLreports** | `D:\develbat\SendLAMLreports.exe` | Queues via `Email.Send` → `t_EmailQueue_local` + staging (`App.config`). Subject: `FCSA LAML report…` |
| **SMTP.exe** | `D:\develbat\SMTP.exe` | Queue smoke test via `MicsEmail.Send` (legacy 6-arg CLI still accepted; only `<to>` used) |
| **SetEmailPassword** | `D:\develbat\SetEmailPassword.exe` | **Still SMTP by design** — validates `mics@fcsa.ca` password before writing the registry key the mail stack may need |

---

## Config keys (remicsdev testing — 2026-08-25)

```xml
<add key="DisableOutgoingEmail" value="false" />
<add key="EmailRedirectAllTo" value="alejandro.moreno@sympatico.ca,plin@fcsa.ca" />
```

All queued outbound mail (PCN, DbUpdate, password reset, TSIP, print/KML) is redirected to those tester inboxes. Original To/CC is appended to the body. `sbekhsat@fcsa.ca` is omitted from this list for now.

Operator emails may still be normalized in SQL ([`ddl/remicsdev-test-email-normalize.sql`](ddl/remicsdev-test-email-normalize.sql)):

- `dbo.t_UserDetails.email`
- `adm.account_details.email` (DbUpdate notify + auto-processor submitter)
- `adm.pcn_account_details.email` (PCN on remicsdev)

Those stored addresses are the “original recipients” shown in the redirect footer; delivery uses `EmailRedirectAllTo`.

**Agent schedules:** Update Queue Local every 10 min; Email Queue Local every 2 min.

### Removal checklist (production cutover)

1. Restore real operator emails from backup (reverse normalize script export)
2. Remove or clear `EmailRedirectAllTo` on all sites and TsipInitiator `App.config`
3. Set `DisableOutgoingEmail` to `true` if legacy log-only paths should be suppressed again
4. Verify SQL Agent jobs process queues on schedule
5. Capture live samples into `tests/remicsdev/fixtures/email-samples/` if needed

### Previous testing config (superseded)

```xml
<add key="DisableOutgoingEmail" value="true" />
<add key="EmailRedirectAllTo" value="jscott@fcsa.ca" />
```

---

## Inbound (demo) — IMAP poll of jscott@fcsa.ca

**Status (2026-09-21 Phase 0):** Demo ingest only (store for later classification). Not production; test mailbox.

| Item | Value |
|------|--------|
| Mailbox | `jscott@fcsa.ca` (test) |
| Host | `outlook.office365.com:993` (SSL), folder `INBOX` |
| Probe host | IIS-REMICS-PROD |
| CAPABILITY | `AUTH=XOAUTH2`, **`LOGINDISABLED`** (no PLAIN/LOGIN) |
| Basic Auth LOGIN | **Failed** — server: `Basic authentication is disabled.` |
| Working auth for demo | **XOAUTH2** client credentials + `IMAP.AccessAsApp` (Exchange service principal + mailbox FullAccess) |
| Setup | [inbound-imap-xoauth2-setup.md](inbound-imap-xoauth2-setup.md) |
| Probe | `scripts/Probe-RemicsInboundImapXoauth2.ps1` + `config/remicsdev/.env.inbound-imap.local` |
| Secrets | Local/gitignored config only; do not commit passwords or tokens |

Classification / NLP remains out of scope until ingest works. Full plan: `.cursor/plans/inbound_imap_mail_store_c0b91763.plan.md`.

---

## Verification query

```sql
SELECT TOP 5 mail_sequence, mailTo, mailSubject, sentYN, SentDate
FROM adm.t_EmailQueue_local ORDER BY mail_sequence DESC;
```
