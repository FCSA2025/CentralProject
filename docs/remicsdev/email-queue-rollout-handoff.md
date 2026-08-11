# Email queue rollout — handoff

**Last updated:** 2026-08-07

## Architecture

| Queue | Agent job | Server | Attachments |
|-------|-----------|--------|-------------|
| `adm.t_EmailQueue` | Email Queue | EC2AMAZ-2013EDB / prod | Legacy UNC rewrites |
| `adm.t_EmailQueue_local` | Email Queue Local | EC2AMAZ-9DKDM82 | `\\IIS-REMICS-PROD\MicsEmailStaging\...` |
| `adm.t_UpdateQueue_local` | Update Queue Local | EC2AMAZ-9DKDM82 → IIS-REMICS-PROD | DbUpdate auto-processing (see [`update-pipeline-pilot.md`](update-pipeline-pilot.md)) |

**IIS** (remicsdev site) runs on **IIS-REMICS-PROD**. **SQL Server + Agent** run on **EC2AMAZ-9DKDM82\REMICS_DEV**. Producers copy attachments to `D:\MicsEmailStaging` and queue UNC paths for the agent.

### Config (`web.config` / TsipInitiator `App.config`)

```xml
<add key="EmailQueueTable" value="adm.t_EmailQueue_local" />
<add key="EmailAttachStagingRoot" value="D:\MicsEmailStaging" />
<add key="EmailAttachStagingUncRoot" value="\\IIS-REMICS-PROD\MicsEmailStaging" />
<add key="EmailRedirectAllTo" value="jscott@fcsa.ca" />
```

### One-time IIS setup

```powershell
.\scripts\Initialize-MicsEmailStaging.ps1
```

Share **MicsEmailStaging** on `D:\MicsEmailStaging` must be readable by `CLOUDMICSDEV\SQLAgentService` on EC2AMAZ-9DKDM82 (verified via `xp_fileexist`).

**Testing:** Agent error notifications go to **jscott@fcsa.ca** only (see `@TeamRecipients` in local job SQL). Restore the full team list before production cutover.

---

## Verified (2026-08-07)

| Seq | Table | sentYN | Notes |
|-----|-------|--------|-------|
| 4 | local | Y | Text-only smoke |
| 7 | local | Y | UNC attachment `\\IIS-REMICS-PROD\MicsEmailStaging\...` delivered to jscott@fcsa.ca |

Legacy `adm.t_EmailQueue` unchanged during local tests.

---

## Code locations

| Component | Path |
|-----------|------|
| Queue helper + staging | `config/remicsdev/source/mics/utilities/SesUtils.cs` |
| PCN | `config/remicsdev/source/mics/RemIcsReWrite/pcn.ashx` |
| TSIP | `config/remicsdev/source/batch/TsipInitiator/TsipEmail.cs` |
| Local agent job | `docs/remicsdev/email-queue-local-agent-job.sql` |
| Deploy local job | `scripts/Deploy-EmailQueueLocalJob.ps1` |
| Staging share setup | `scripts/Initialize-MicsEmailStaging.ps1` |

---

## Quick verify

```sql
SELECT TOP 10 mail_sequence, sentYN, mailSubject, mailAttachments, ErrorMsg
FROM adm.t_EmailQueue_local ORDER BY mail_sequence DESC;
```

---

## Remaining

- End-to-end PCN / TSIP with real attachments via UI or batch
- Remove `EmailRedirectAllTo` when ready for production recipients
- `Send-RemicsDevPcn.ps1` export-path issue under impersonation (separate from queue)
