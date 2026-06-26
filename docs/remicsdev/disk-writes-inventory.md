# MICS Disk Writes — Inventory

**Codebase:** remicsdev  
**Status:** Reference — initial classification complete  
**Created:** 2026-06-17  
**Related:** [disk-write-reduction-plan.md](disk-write-reduction-plan.md), [tsip-implementation-plan.md](tsip-implementation-plan.md)

---

## Summary

MICS writes to disk from two primary codebases:

| Codebase | Path | Scope |
|----------|------|-------|
| Web (IIS) | `D:\inetpub\remicsdev\mics` | ~200+ `.cs` / `.vb` files with I/O |
| Batch | `D:\MicsBatchProgs\MicsBat` | TSIP, JobSubmit, utilities |

Tracked source symlinks: `config/remicsdev/source/`. Deploy exes: `D:\develbat\`.

**Note:** `dblogger` (`DBAccess\dblogger.cs`) writes to **SQL** (`web.dblogger`), not disk. Adjacent `StreamWriter` calls are separate file debug.

---

## Disk write roots

| Root | Typical path | Primary use |
|------|--------------|-------------|
| `extractlogs` | `{web_drive}\extractlogs\` (often `D:\extractlogs\`) | Per-user / per-operation debug traces |
| `perflogs` | `{web_drive}\perflogs\` | Login, session, job-submit traces |
| `MicsWebLogs` | `D:\MicsWebLogs\` | Login audit, release audit, email metadata |
| `userdirs` | `...\mics\userdirs\{schema}\{user}\` | User workspace — reports, KML, display `.txt` |
| `MicsBatchLogs` | `d:\MicsBatchLogs\` | TSIP batch session diagnostics |
| `prod/files` | `{GetMicsRoot(db)}files\` | TSIP shared log, DB read-access markers |
| Regulatory data dirs | `coms_data_dir`, `fcc_dataout_dir`, etc. | Import/export command and batch files |
| `App_Data` | `mics\App_Data\ErrorLog.txt` | Unhandled web exceptions |

Debug directory resolution: `utilities\DebugUtils.cs` reads `web.debugdirectory` table, else falls back to `D:\extractlogs`.

---

## Category A — Debug / diagnostic (Stage 1: disable first)

Highest volume; safest to comment out or gate off. Estimated ~80% of unnecessary writes.

| ID | What | Where written | Why | Module(s) | Stage |
|----|------|---------------|-----|-----------|-------|
| A1 | Per-operation trace | `extractlogs\{user}*.txt` | Request troubleshooting | `TwsTsip.asmx.cs`, `JobSubmit.cs` | 1 |
| A2 | FCC button trace | `extractlogs\{user}fccButton*.txt` | FCC processing debug (high volume) | `FCCInfo\BuildSiteTables.aspx.cs` | 1 |
| A3 | Job submit trace | `extractlogs\{site}_{user}submit5.txt` | Batch spawn / env debug | `JobSubmit.cs`, `JobSubmitNET.cs` | 1 |
| A4 | TSIP run/delete trace | `extractlogs\{user}tsip.txt`, `{user}tsipDelete.txt` | TSIP web action debug | `Ttsipmenu\TwsTsip.asmx.cs` | 1 |
| A5 | KML/PDF debug | `extractlogs\{user}pdfkmldebug*.txt`, `user_dir\kmldebug*.txt` | Map export troubleshooting | `KmlUtils.cs`, `FCCMAPkml.aspx.cs` | 1 |
| A6 | Email send debug | `extractlogs\SendEmailSql.txt`, `MicsWebLogs\SendEmailSql*.txt` | SMTP/SQL path tracing | `SesUtils.cs` | 1 |
| A7 | LDAP verbose login | `perflogs\goodwinlogin.txt`, `badwinlogin.txt` | AD auth trace | `Tlogin.aspx.cs` | 1 |
| A8 | Password recovery debug | `D:\extractlogs\*pwdrecov*.txt` | One-off debug | `Maintenance\pwdrecov.aspx.cs` | 1 |
| A9 | Dev scratch | `d:\users\...\temp\clickbait.txt` | Local dev only | `_NewLib\CanUsaBorder.cs` | 1 |
| A10 | Documentation tooling | `documentation\functions.txt`, etc. | Code inventory, not runtime | `documentation\` | 1 |
| A11 | TpRunTsip session log | `d:\MicsBatchLogs\TpRunTsip.log` | Batch run diagnostics | `TpRunTsip.cs` | 1 |
| A12 | TsipInitiator session log | `d:\MicsBatchLogs\TsipInitiator.log` | Orchestration diagnostics | `TsipInitiator\TsipInitiator.cs` | 1 |
| A13 | TsipEmail session log | `d:\MicsBatchLogs\TsipEmail.log` | Email-send audit | `TsipInitiator\TsipEmail.cs` | 1 |
| A14 | Generic Log2 | Default `D:\perflogs` (caller-set) | Shared debug framework | `_NewLib\Log2.cs` (`WriteMode.DISABLED`) | 1 |
| A15 | TSIP shared ops log | `{GetMicsRoot}files\tsiplog.log` | Queue/spawn/email audit | `_Utillib\TsipQ.cs` (`WriteToTsipLog`) | 1 |
| A16 | QuickLog append | Caller path | Lightweight debug | `_NewLib\QuickLog.cs` | 1 |

---

## Category B — Ops / audit (Stage 2: review before disable)

Moderate volume; ops/security value. Keep bad-login and error log until SQL replacement exists.

| ID | What | Where written | Why | Module(s) | Stage |
|----|------|---------------|-----|-----------|-------|
| B1 | Session lifecycle | `perflogs\{user}{sid}*.txt`, `sesend.txt`, `menulog.txt` | Timeout, logout, menu | `SesUtils.cs`, `Global.asax.cs` | 2 |
| B2 | Login connection log | `MicsWebLogs\logins\{user}_conn.txt` | Per-login audit (smoke tests use this) | `TloginValidate.aspx.cs` | 2 |
| B3 | Bad-login tracking | `perflogs\badlogin.txt`, `badlogins.txt`, `mailbadlogin.txt` | Security alerting | `Tlogin.aspx.cs`, `Global.asax.cs` | Keep |
| B4 | Email metadata log | `MicsWebLogs\{user}SendEmailMessage.txt` | Pre-SMTP audit | `SesUtils.cs` | 2 |
| B5 | Release audit | `MicsWebLogs\releasedev.txt`, `perflogs\release.txt` | Deploy trace | `wsRelease.asmx.cs`, `wsMtnce.asmx.cs` | 2 |
| B6 | Production errors | `App_Data\ErrorLog.txt` or `D:\extractlogs\ErrorLog.txt` | Unhandled exceptions | `ErrorUtils.cs` | Keep |
| B7 | Password timeout | `perflogs\pwdtimeout.txt` | Password-timeout events | `UserUtils.cs` | 2 |
| B8 | Email failure diagnostics | `extractlogs\EmailSendError{user}.txt`, `{user}logenv.txt` | SMTP failure debug | `SesUtils.cs` | 2 |

---

## Category C — User deliverables (Stage 3–4: keep until DB replacement)

Business-critical; external apps and web UI depend on physical files today.

| ID | What | Where written | Why | External dependency | Stage |
|----|------|---------------|-----|---------------------|-------|
| C1 | TSIP report files | `userdirs\{schema}\{user}\{prefix}_{run}.*` | Primary batch output (.STATSUM, .CASEDET, .AGGINTREP, .CSV, .ERR, etc.) | `TsipEmail.cs` attaches via UNC; users download | 3 |
| C2 | TSIP console capture | `{destPath}\{prefix}_{run}.CONSOLE` | User-visible run log | `TsipInitiator.cs` | 3 |
| C3 | Report display copy | `CopyToTxt` → `{filename}.txt` in `user_dir` | Browser opens via `../userdirs/...` | `TwsTsipTree.asmx.cs` | 3 |
| C4 | Report tree listing | Scans `user_dir` for `tsip_*` | Retrieve TSIP Batch Reports UI | Same; not using `web.tsip_run_report_line` yet | 3 |
| C5 | KML map output | `user_dir\{kmlrepname}` | Map download/view | `KmlUtils.cs`, TSIP KML pages | 4 |
| C6 | PCN lookup text | `userdirs\...\p{serial}.txt` | Lookup display | `PcnLookup.aspx.cs` | 4 |
| C7 | Job stdout capture | Caller `outFile` under `user_dir` | Generic batch output | `JobSubmit.cs` | 4 |
| C8 | Import/export reports | `ImpExp` `StreamWriter`, radio catalog | ES/SDF PDF/text export | `ImpExp.cs`, `BuildRadioCatalog\` | 4 |
| C9 | `.prn` → `.txt` display | `userdirs\...` via `File.Move` | Report viewing | `TwsTsip.asmx.cs`, `DBAccess\TsRadio.cs` | 3 |

**TSIP archive (DB, not disk):** Phases 2–3 capture registry + report lines to `web.tsip_run` / `web.tsip_run_report_line`. Phase 4 web UI will read from DB instead of disk.

---

## Category D — Regulatory / batch command files (Stage 5: do not disable without external app review)

Critical; external batch programs read command files from disk.

| ID | What | Where written | Why | Module(s) | Stage |
|----|------|---------------|-----|-----------|-------|
| D1 | COMS command + logs | `coms_data_dir\` + `extractlogs\` | COMS batch driver input | `COMSTSoutput.aspx.cs`, `COMSTSimport.aspx.cs` | 5 |
| D2 | ISED-TS import | Data dir + logs | Regulatory import | `ISEDTSInfo\ISEDTSimport.aspx.cs` | 5 |
| D3 | ISED-ES conversion | Output + `extractlogs\ISEDESIMPError.txt` | Regulatory conversion | `ISEDESInfo\ISEDESConvertData.aspx.vb` | 5 |
| D4 | FCC import/export | `fcc_dataout_dir\`, `FCCTSOPERS*.txt`, etc. | FCC operator/update files | `ImportFCCData.aspx.cs`, `FCCEmailUpdate.aspx.cs` | 5 |
| D5 | File upload | `SaveAs` to user/work dir | User file import | `Tfileactions\import.aspx.cs` | 5 |
| D6 | Tab import/export | `work_dir` temp files | Tabular data exchange | `Tfileactions\TwsTabUtil.asmx.cs` | 5 |
| D7 | Area PDF logs | `extractlogs\` (PDF pipeline itself critical) | FCC area PDF generation | `FCCInfo\WriteAreaPDF.aspx.cs` | 5 |

---

## Category E — Infrastructure / coordination (keep)

Small volume; required for correct operation.

| ID | What | Where written | Why | Module(s) | Stage |
|----|------|---------------|-----|-----------|-------|
| E1 | User workspace creation | `userdirs\{schema}\`, `{schema}\{user}\` | Required at login | `TloginValidate.aspx.cs` | Keep |
| E2 | Write-access probe | `{destPath}\JuNkTeSt.txt` (create + delete) | Pre-flight before TSIP queue | `TsipInitiator.cs` | Keep |
| E3 | DB read-access markers | `{GetMicsRoot}files\read\{pid}` | Qutils coordination | `_Utillib\Qutils.cs` | Keep |
| E4 | Release file copy/delete | Target deploy paths | Prod/test release | `wsMtnce.asmx.cs`, `wsRelease.asmx.cs` | Keep |

---

## Path variable cheat sheet

| Symbol | Typical resolved path | Set by |
|--------|----------------------|--------|
| `user_dir` / `WORK_DIR` | `D:\inetpub\{db}\mics\userdirs\{schema}\{micsid}` | WebMICS session / JobSubmit |
| `TARGETDIRFORTSIPREPORTS` | Same as `WORK_DIR` when spawned by TsipInitiator | `TsipQ.StartTsip()` |
| `web_drive` | `D:` (app setting) | `web.config` / Application |
| `extractlogs` | `{web_drive}\extractlogs\` | Hardcoded fallback or app var |
| TSIP shared log | `{GetMicsRoot(db)}files\tsiplog.log` | `Ssutil.GetTsipLogFileName()` |

---

## Safe vs business-critical (quick reference)

### Generally safe to disable (Category A)
- All `extractlogs\` per-user debug traces
- KML/PDF debug side files
- LDAP verbose login trace
- `Log2` via `WriteMode.DISABLED`
- Documentation codegen pages
- Hardcoded dev paths

### Do not disable without replacement (Categories C, D, E)
- `userdirs\` — TSIP reports, KML, CopyToTxt, display pipeline
- Import `SaveAs` / `File.WriteAllLines` — COMSTS, ISED, FCC batch drivers
- `JobSubmit` output files — batch stdout/stderr capture
- Release `File.Copy` / `File.Delete`
- `ErrorUtils` → `App_Data\ErrorLog.txt`
- `Directory.CreateDirectory` for `userdirs` at login

### Gray area (Category B)
- `perflogs\` session/menu tracking
- `MicsWebLogs\logins\{user}_conn.txt`
- Bad-login files + email flow — security audit
- `WriteToTsipLog` — useful for queue incidents

---

## Stage 1 priority files

1. `FCCInfo\BuildSiteTables.aspx.cs` — many `fccButton*.txt`
2. `utilities\JobSubmit.cs` — `submit5.txt`
3. `Ttsipmenu\TwsTsip.asmx.cs` — `{user}tsip.txt`, `tsipDelete.txt`
4. `utilities\KmlUtils.cs` + `FCCMAPkml.aspx.cs` — KML debug
5. `utilities\SesUtils.cs` — email debug (not SMTP send)
6. Batch: `Log2` in `TpRunTsip`, `TsipInitiator`, `TsipEmail`; `WriteToTsipLog` in `TsipQ.cs`

Implementation marker comment: `// DISK-WRITE-REDUCTION stage1 — debug only`
