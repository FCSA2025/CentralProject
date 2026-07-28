# ReMICS Dev — TSIP (Terrestrial Station Interference Program)

**Codebase:** remicsdev  
**Status:** Active reference (call path + logging verified 2026-07-20; formulas 2026-06-17)  
**See also:** [Working tables lifecycle](tsip-tt-tables.md), **[Implementation plan](tsip-implementation-plan.md)** (Phase 0 fix + archive), [Archive queries](tsip-archive-queries.md), [Application learnings](application-learnings.md)

TSIP identifies **radio interference** between proposed/new systems and existing terrestrial (TS) and earth (ES) stations. It is described in source as *"the core of the MICS system"*.

---

## What TSIP does (plain language)

Given a **parameter file** that describes one or more analysis runs (proposed PDF/MDB vs environment PDF/MDB, coordination distance, path-loss model, margins, etc.), TSIP:

1. Loads station/antenna/channel data from the database
2. **Culls** distant or irrelevant sites
3. Computes **path loss** between interferer and victim
4. Computes **C/I or I/N** (carrier-to-interference or interference-to-noise)
5. Flags cases where margin requirements are not met
6. Writes **text reports** and optionally emails them to the user

Analysis types: **TS–TS**, **TS–ES**, and **ES–TS** interference.

---

## Program architecture

Three executables form the batch pipeline; a fourth handles queue admin.

```mermaid
flowchart LR
    WEB["MICS UI / ASMX<br/>or independent app"]
    INIT["TsipInitiator.exe"]
    Q["web.tsip_queue"]
    RUN["TpRunTsip.exe"]
    ARC["web.tsip_run archive"]
    OUT["Report files + email"]
    LOG["dblogger / extractlogs / TsipInitiator.log"]

    WEB --> INIT
    WEB --> LOG
    INIT --> Q
    INIT --> RUN
    INIT --> LOG
    RUN --> OUT
    RUN --> ARC
```

| Program | Path | Role |
|---------|------|------|
| **TpRunTsip** | `D:\MicsBatchProgs\MicsBat\TpRunTsip\` | **Calculation engine** — all interference math and reports |
| **TsipInitiator** | `D:\MicsBatchProgs\MicsBat\TsipInitiator\` | Queue supervisor (~5 slots), spawns TpRunTsip, emails results |
| **TsipQdelete** | `D:\MicsBatchProgs\MicsBat\TsipQdelete\` | Remove waiting jobs from queue |
| **TsipSkim** | `mics\Tsipskim\` | Post-process reports into DB (not web-triggered) |

**Source tree:** TSIP C# lives under **`D:\MicsBatchProgs\MicsBat\`** (`TpRunTsip`, `TsipInitiator`). **MICSTSIP source does not exist** as a separate maintained tree — see [implementation plan](tsip-implementation-plan.md). A parallel fork exists under `MICSH\` (`MICS#.sln`); do not deploy from there.

**Runtime on remicsdev:** `TsipInitiator` is launched from `D:\develbat\` via web `prog_dir`. `TpRunTsip.exe` is resolved by `Ssutil.GetBinPath()` — on this server hardcoded to **`D:\develbat\`** (see below).

---

## How we call TSIP (authoritative contract)

There are two supported entry styles. Both must end at the same executable and environment contract.

```text
Caller (MICS UI  -or-  independent web app)
  -> start D:\develbat\TsipInitiator.exe  with CLI + env vars
      -> INSERT web.tsip_queue
      -> spawn D:\develbat\TpRunTsip.exe
          -> calc + report files
          -> archive web.tsip_run (+ children)
      -> email reports
```

**Do not** call `TpRunTsip.exe` directly from web code. `TsipInitiator` owns queue slots (~5), duplicate detection, spawning, and email.

### Path A — MICS web UI / ASMX (session required)

1. User builds/selects a **parameter file** in `Ttsipmenu` (`tsipParm.aspx`, `lookuptsip` lookups)
2. **Execute Batch TSIP** -> `tsipBatch.aspx?parameter={parmfile}`
3. AJAX **`tsipValidateAll`** — checks all runs have valid TS/ES PDFs
4. AJAX **`tsipRun`** — submits batch job
5. Browser gets immediate **`OK:0`** (queued) or **`OK:2`** (duplicate) — **does not wait for calculations**
6. User receives **email** with report attachments when complete
7. Reports browsable via **`tsipRepsTree.aspx`**, CASEDET KML/CSV pages

| Step | Endpoint | Body |
|------|----------|------|
| Validate | `POST {SiteName}Ttsipmenu/TwsTsip.asmx/tsipValidateAll` | `{"tsipparmname":"MYTSIP01"}` |
| Run | `POST {SiteName}Ttsipmenu/TwsTsip.asmx/tsipRun` | `{"parmfile":"MYTSIP01"}` |

Uses ASP.NET AJAX JSON (`Content-Type: application/json`) and requires a live MICS login session (`EnableSession=true`). Helper: `includeFiles/Tutils.js` -> `callajaxchrome`.

`tsipRun` return values: `OK:0` queued, `OK:2` duplicate, `ERROR:...` / `ERRORSYS:...` / session `timeout...`.

### Path B — Independent web app (own login / pages)

An external site should **not** call `TwsTsip.asmx/tsipRun` unless it also creates a full MICS session. Instead, after the app's own authentication, map the user to a MICS identity and launch `TsipInitiator` with the same CLI and environment variables `JobSubmit` would set.

### Command line (both paths)

MICS builds this in `TwsTsip.asmx.cs`:

```csharp
oLog.logprogram = Session["prog_dir"] + "TsipInitiator";
oLog.logargs = db_name + " " + projectCode + " -otsip " + parmfile + " -p" + Session["prog_dir"];
JobSubmit.SubmitJob(oLog, " ", 2);  // 2 sec wait — detect duplicate queue
```

Example on remicsdev:

```text
D:\develbat\TsipInitiator.exe remicsdev rctl1_0 -otsip MYTSIP01 -pD:\develbat\
```

| Argument | Meaning |
|----------|---------|
| `remicsdev` | SQL database name |
| `rctl1_0` | Project code (`adm.project_ids` / session `defProject`) |
| `-otsip MYTSIP01` | Parameter-file name (all runs in that file execute) |
| `-pD:\develbat\` | Directory containing `TsipInitiator` and `TpRunTsip` |

`-otsip` marks operator/web-style submission. One call runs **every run** in `{schema}.tp_{parmfile}_parm`.

### Environment variables (required contract)

Set on the child process before start (`JobSubmit` does this for Path A):

| Variable | Required | Purpose |
|----------|----------|---------|
| `MicsUser` / `MICSUSER` | Yes | MICS account (`TsipInitiator` requires this) |
| `Password` | Yes | Batch/tool credentials |
| `work_dir` / `WORK_DIR` | Yes | User working directory (reports / write test) |
| `DBName` | Yes | Database name |
| `odbc` | Yes | ODBC DSN |
| `SqlInstance` | Yes | SQL instance |
| `MICS_PROJECT` | Yes | Project code |
| `Domain` | Usually | Legacy domain expectation |
| `webdrive` | Usually | Shared drive root |
| `MICS_NAD_FILE` | Usually | `{webdrive}\prod\files\ntv2_0` |
| `TARGETDIRFORTSIPREPORTS` | Set by initiator | Report output folder for `TpRunTsip` |

Optional calc: `FCSAMAPS50K`, `FCSAMAPS250K`, `MICS_CTX_CALC`.

### Wait semantics

HTTP / API callers should wait only a few seconds (MICS uses **2**):

| Observation | Treat as |
|-------------|----------|
| Process still running after short wait | Queued / running in background |
| Exit code **2** | Duplicate already in queue |
| Other non-zero quick exit | Launch / DB / setup failure |
| Full calculation finished in-request | **Do not design for this** — email + files signal completion |

Under `UseDbAuth=true`, `JobSubmit` launches via `Process.Start` as the IIS app-pool identity (not per-user `CreateProcessAsUser`).

### TsipInitiator -> TpRunTsip

`TsipQ.StartTsip()` spawns `TpRunTsip.exe`. **`GetBinPath("tpRunTsip", database)`** normally resolves `{micsRoot}\bin\`, but on remicsdev:

```4787:4791:D:\MicsBatchProgs\MicsBat\_Utillib\Ssutil.cs
            /**************************************************************************************************************************
             * OVERRIDE FOR remicsdev TESTING
             * ************************************************************************************************************************/
            mMicsBinDirPath = @"D:\develbat\";
            string path = Path.Combine(mMicsBinDirPath, micsProgramName + ".exe");
```

**Verified:** Both `TsipInitiator` and `TpRunTsip` run from **`D:\develbat\`** on this server.

### Prerequisites before launch

1. Active `dbo.t_UserDetails` row with `PrimarySchema` pointing at a real SQL schema
2. Project row in `adm.project_ids` for that `micsid`
3. Writable work directory for the launch identity
4. Parameter table `{schema}.tp_{parmfile}_parm`
5. Proposed/environment TS/ES tables referenced by the parm runs exist and are valid

---

## Inputs

### A. What the user submits (web layer)

| Input | Source | Example |
|-------|--------|---------|
| Parameter file name | Tree selection / query string | `MYTSIP01` |
| Database | Session `db_name` | `remicsdev` |
| Project code | Session `defProject` | charge code |
| MICS user | Session `s_user` | login id |
| Windows identity | Session `principalw` | batch impersonation |

The web passes **only the parm file name** — not per-run fields.

### B. Parameter table (database)

Table: **`{schema}.tp_{parmfile}_parm`** — one row per **run**.

Loaded by `TpRunTsip.ParmFileInit()` → `TpDynParm.TpSelectParm()`.

Key fields (from code usage):

| Field | Meaning |
|-------|---------|
| `runname` | Run identifier (used in output filenames) |
| `protype` | `T` = terrestrial (TS), `E` = earth (ES) |
| `proname` | Proposed system PDF/MDB name |
| `envname` | Environment PDF/MDB name |
| `envtype` | Environment type (`PDF_ES`, `MDB_ES`, etc.) |
| `coordist` | Coordination distance (site culling) |
| `spherecalc` | Path-loss model selector (`'1'`–`'5'`, see formulas) |
| `margin` | Required margin (dB) — interference if `resti < margin` |
| `analopt` | Analysis options |
| `reports` | Which reports to generate |
| `country`, `selsites`, `codes`, `chancodes` | Filtering / scope |

### C. Proposed and environment data

PDF or MDB tables (`ft_*`, `fe_*`, `mt_*`, `me_*`) referenced by parm rows — station locations, antennas, channels, powers, heights, frequencies, etc.

### D. Environment variables (batch runtime)

Set by `JobSubmit` and TsipInitiator/TpRunTsip startup:

| Variable | Purpose |
|----------|---------|
| `MICSUSER` / `PASSWORD` | DB session identity |
| `WORK_DIR` | User working directory (email attachment paths) |
| `TARGETDIRFORTSIPREPORTS` | Report output directory (set when TpRunTsip starts) |
| `FCSAMAPS50K` / `FCSAMAPS250K` | DTED terrain dirs (default `d:\dted50\data`, `d:\dted250\data`) |
| `MICS_CTX_CALC` | If set, compute CTX values vs lookup |
| `SqlInstance`, `DBName`, `odbc`, `work_dir`, `MICS_PROJECT` | From JobSubmit |

### E. TpRunTsip command line

```
TpRunTsip <dbName> <projCode> <paramTableName> [-o<prefix>] [-u<micsUser>] [-t]
```

| Flag | Purpose |
|------|---------|
| `-o<prefix>` | Report filename prefix |
| `-u` | MICS user override |
| `-t` | Also store reports in DB table `{param}_tsip_reports` |

---

## Calculation flow (TpRunTsip)

High-level loop in `TpRunTsip.Main()`:

```
Parse args + env
Connect DB (Ssutil.UtConnect)
ParmFileInit → load tp_{parm}_parm rows
Init DTED directories (CTEfunctions.Init_Directories)
FOR EACH parm run:
    OpenReportStreams()
    ParmRecInit() — validate PDFs, adjust coordist
    IF protype=E OR envtype is ES:
        TeBuildSH.TeBuildSHTable()   ← ES–TS / TS–ES engine
    ELSE:
        TtBuildSH.TtBuildSHTable()   ← TS–TS engine
    UpdateParmRec(numIntCases)
    ReportStudy → ReportNew → TpExecRpt → TpExportRpt
CloseReportStreams
```

### TS–TS path (`TtBuildSH` + `TtCalcs`)

| Step | Method | Purpose |
|------|--------|---------|
| Site culling | `GenRoughCull`, `IntVicSiteCull` | Drop sites outside coordination distance |
| Geometry | `AxSub2.AxDistan`, `AxSub3.PathDist` | Distance, bearing, path length |
| Tables | `TtDynSite`, `TtDynAnte`, `TtDynChan` | Build interference case records |
| Path loss | `TtCalcs.TtPathLoss` | Model selected by `spherecalc` |
| Antenna/discrimination | `TtCalcs.CalcTotADisc` | Antenna gain, cross-polar, nulls |
| Interference | `TtCalcs.TtChanCalcs` | C/I or I/N, margin check |
| Orbit (optional) | `TtCalcs.TtTsorbCalcs` | Uses `AxOrbitSupp.AxOrbit` → `.ORBIT` report |
| Passive | `TtCalcPassive` | Passive interference cases |

### ES path (`TeBuildSH` + `TeCalcs` + `TeSubCalc`)

| Step | Method | Purpose |
|------|--------|---------|
| Tables | `TeSubCalc.TeTableNames` | Terrain/earth/azimuth tables |
| Horizon | `TeSubCalc.TeCheckRadioHoriz` | Radio horizon vs `me_azim` / `fe_azim` |
| Path loss | `TeCalcs.TeChanCalcs`, `TeSubCalc.TeCalcL20M1` | ES-specific models |
| Refraction | `TeCalcs.CalcRefElev` | Atmospheric refraction on elevation |

---

## Formulas (verified in source)

### 1. Free-space path loss

`GenUtil.FreeSpacePathLoss` — `MicsBat\_Utillib\GenUtil.cs`

```
pLoss = 32.45 + 20·log10(plengthKm) + 20·log10(freqMHz) + AtmosphericAtten(freqKHz, plengthKm)
```

Used when `spherecalc = '3'`, and as baseline for OH-loss display.

### 2. Spherical Earth path loss (TS–TS)

`TtCalcs.SphericalPathLoss` — `MicsBat\TpRunTsip\TtCalcs.cs`

```
transDist = 4.123 · (√rxHeight + √txHeight)     // km, heights in meters
FSL = 32.45 + 20·log10(plength) + 20·log10(freq)

IF plength > transDist:
    θ = (plength - transDist) / 8.5              // milliradians
    H = θ · plength / 4000
    h = 1.063 · θ² · 0.001
    N = 20·log10(5 + 0.27·H) + 1.17261·h
    ploss = 29.73 + 30·log10(freq) + 10·log10(plength) + 30·log10(θ) + N
    ploss = max(ploss, FSL)
ELSE:
    ploss = FSL
```

Selected when `spherecalc = '2'`.

### 3. Path-loss model selector (TS–TS)

`TtCalcs.TtPathLoss` — `spherecalc` from parm record:

| Code | Model |
|------|-------|
| `'1'` | CCIR-SJM — `GenUtil.CalcPatLoss` |
| `'2'` | Spherical Earth — `SphericalPathLoss` |
| `'3'` | Free space — `FreeSpacePathLoss` |
| `'4'` | PCS / COST-231 extension — `PCSPropLoss` (Hata-style α for antenna heights ≤60 m) |
| `'5'` | Over-horizon — `CTEfunctions.Calc_OhLoss` using DTED 50K/250K terrain profiles |

Path distance uses **`AxSub3.PathDist`** (path length accounting for antenna and ground heights), not always great-circle surface distance alone.

### 4. C/I and I/N interference (TS–TS)

`TtCalcs.TtChanCalcs` — after path loss and antenna discrimination:

**I/N mode** (`ecalctype == eMINUSI`):

```
bandTmp = intPowrTx + intAGain - patloss + vicAGain - intAFSLtx - totAdiscC
calcico = bandTmp - vicAFSLrx

resti = reqdcalc - calcico          // copolar
resti = reqdcalc - calcixp          // cross-polar (uses totAdiscX)

report = TRUE if resti < margin    → interference case
```

**C/I mode:**

```
calcico = vicpwrrx - bandTmp
resti = calcico - reqdcalc
report = TRUE if resti < margin
```

`reqdcalc` = required C/I or I/N threshold (from parm / band rules).  
`resti` = **margin remaining** — negative or below `margin` means reportable interference.

### 5. ES Mode 2.0 loss

`TeSubCalc.TeCalcL20M1` — for air-route radio with spherical calc Y/2:

```
x = 2.2 · dist · freq^(1/3) · (K_FACTOR·6374.82)^(-2/3)
fx = 11 + 10·log10(x) - 17.6·x
y = 9.6 · freq^(2/3) · (K_FACTOR·6374.82)^(-1/3)
gyt, gye = height-gain terms from terrht, earthht
FSL = 32.45 + 20·log10(dist) + 20·log10(freqMHz)
loss = max(FSL, FSL - fx - gyt - gye)
```

Other distance bands use piecewise constants (`const1`, `const2`) for non-air routes.

### 6. Geometry

- **`AxSub2.AxDistan`** — geodesic distance/bearing on WGS-style ellipsoid (lat/long in arc-seconds)
- **`AxSub3.PathDist`** — 3-D path distance with ground and antenna heights
- **`TeCalcs.CalcRefElev`** — refraction-adjusted elevation using earth-radius factor and refractive index

### 7. Over-horizon (terrain)

When `spherecalc = '5'`, `CTEfunctions.Calc_OhLoss` uses DTED elevation profiles between site coordinates (`OhLossXfer` struct with lat/long pairs). Free-space loss is stored for comparison; OH result codes distinguish colocated sites, profile failures, etc.

---

## Outputs, logging tables, and log files

TSIP writes to **SQL tables**, **user report files**, and **diagnostic log files**. Use this section when debugging a launch from either Path A or Path B.

### A. SQL tables (operational)

| Table / object | Who writes | When | What to look for |
|----------------|------------|------|------------------|
| `web.dblogger` / `web.dblogger_view` | MICS `dblogger` via `JobSubmit` (Path A) | Submit start + finish | `logprogram` contains `TsipInitiator`; `logerrorcode` `0` = queued OK, `2` = duplicate, `-98` = process start failed |
| `web.tsip_queue` | `TsipInitiator` / `TsipQ` | Insert at queue entry; status updates while running | Job id, parm, user, status `W` waiting / `X` running; terminal/deleted often `D` / `F` |
| `{schema}.tp_{parm}_parm` | `TpRunTsip` | After each run | `numIntCases` updated |
| Working `tt_*` / `te_*` tables | `TpRunTsip` | During calc | Transient calc tables (see [tsip-tt-tables.md](tsip-tt-tables.md)) |
| `{param}_tsip_reports` | `TpRunTsip` | Only if `-t` flag | Optional consolidated report storage (legacy) |
| `adm.t_EmailQueue` (typical) | Email helpers | When email is queued | Outbound mail for report delivery |

Queue monitor UI: `tsipMonitor.aspx` reloads about every 5 seconds and lists non-terminal `web.tsip_queue` rows.

### B. SQL tables (archive — remicsdev)

After report streams close, `TsipRunArchive.TryArchiveAfterClose` records the run for compare/history:

| Table | Role |
|-------|------|
| `web.tsip_run` | Registry: `mics_user`, `source_schema`, `parm_file`, `run_name`, `protype`, `queue_job_id`, `archive_status`, timestamps |
| `web.tsip_run_parm_ts` / `web.tsip_run_parm_es` | Snapshot of input parm row |
| `web.tsip_arc_ts_*` / `web.tsip_arc_te_*` | Archived working-table copies |
| `web.tsip_run_report_line` | Line-by-line cache of on-disk report text |

Join live queue to archive with `web.tsip_run.queue_job_id = web.tsip_queue.TQ_Job`. Query examples: [tsip-archive-queries.md](tsip-archive-queries.md). Admin re-run compare uses completed `web.tsip_run` rows (latest distinct `source_schema + protype + parm_file`).

### C. User report files (deliverables)

Written under **`TARGETDIRFORTSIPREPORTS`** (from `work_dir` / user report directory), named:

```text
{prefix}_{paramTableName}_{runname}.{EXT}
```

With `-otsip`, prefix is typically `tsip`. Shared error/console often omit run name:

```text
{prefix}_{paramTableName}.ERR
{prefix}_{paramTableName}.CONSOLE
```

| Extension | Content |
|-----------|---------|
| `.ERR` | Error / summary log (also used as email body when little else exists) |
| `.CONSOLE` | TsipInitiator console capture for the job |
| `.STUDY` | Study summary |
| `.CASEDET` | Case detail |
| `.CASESUM` | Case summary |
| `.CASEOHL` | Over-horizon case detail |
| `.STATSUM` | Station summary |
| `.EXEC` | Execution report |
| `.HILO` | Hi/Lo analysis |
| `.ORBIT` | Orbit intersection (when requested) |
| `.AGGINTREP` / `.AGGINT.csv` | Aggregate interference |
| `.TS_EXPORT` / `.ES_EXPORT` | Export for FtPrint/FePrint |

These files are the primary user-visible artifacts and the source copied into `web.tsip_run_report_line`.

### D. Diagnostic / process log files

| Path | Writer | Purpose |
|------|--------|---------|
| `D:\MicsBatchLogs\TsipInitiator.log` | `TsipInitiator` (`Log2`) | Initiator verbose/error log (session-oriented) |
| `{web_drive}\extractlogs\{user}tsip.txt` | `TwsTsip.asmx` `tsipRun` | Per-user web submit debug (Path A) |
| `{web_drive}\extractlogs\{site}_{user}submit5.txt` | `JobSubmit` | Process spawn / env / CreateProcess or Process.Start outcome |
| User-dir write-test file | `TsipInitiator` | Confirms `WORK_DIR` is writable before queueing |
| Batch logs under `D:\MicsBatchLogs\` (related) | Other batch helpers | Shared batch logging area on this server |

On remicsdev, `web_drive` is typically `D:`, so extract logs are under `D:\extractlogs\`.

### E. Email

`TsipEmail.SendSql()` in `TsipInitiator` attaches report files and emails the MICS user when configured. This is the primary "run finished" signal for interactive users. HTTP `OK:0` only means **queued**, not complete.

### F. Web browsing (post-run)

| Page | Purpose |
|------|---------|
| `tsipMonitor.aspx` | Queue status |
| `tsipRepsTree.aspx` | Report tree |
| `CASEDETTSTSkml.aspx`, `CASEDETTSESkml.aspx` | KML viewers |
| `DownLoad.aspx` | File download |

### G. Quick triage order

When a TSIP did not run from web or an external caller:

1. `web.dblogger` — did `JobSubmit` start/finish? (`-98` = never launched)
2. `D:\extractlogs\*submit5.txt` / `{user}tsip.txt` — spawn and args
3. `D:\MicsBatchLogs\TsipInitiator.log` — initiator errors (missing `MicsUser`, DB connect, queue)
4. `web.tsip_queue` — was a job inserted? stuck in `W`/`X`?
5. User report folder — `.ERR` / `.CONSOLE` / empty deliverables
6. `web.tsip_run` — archive row present? `archive_status` / message

---

## Shared libraries (calculation dependencies)

| Library | Location | Used for |
|---------|----------|----------|
| `_Auxlib` | `MicsBat\_Auxlib\` | `AxSub2`, `AxSub3`, `AxOrbitSupp`, `SatAze` — geometry, orbit |
| `_OHloss` | `MicsBat\_OHloss\` | `CTEfunctions` — terrain OH loss, DTED |
| `_Utillib` | `MicsBat\_Utillib\` | `GenUtil`, `TsipQ`, `Ssutil`, reporting |
| `_Configuration` | `MicsBat\_Configuration\` | Constants, errors, enums |
| `_DataStructures` | `MicsBat\_DataStructures\` | `TpParm`, `TtChan`, `FtSite`, etc. |
| `_NewLib` | `MicsBat\_NewLib\` | Math helpers |

---

## Related but separate tools

These share math libraries but are **not** the TSIP batch pipeline:

| Tool | Invoked from | Calculation | Output |
|------|--------------|-------------|--------|
| **Worbit.exe** | `auxengmenu\AUXOrbit.aspx` | `AxOrbitSupp.AxOrbit` | `returnvalues` table |
| **WsatAze.exe** | `auxengmenu\AUX*.aspx` | `SatAze.AxSataze` | Bearings/elevation → `returnvalues` |
| **getcoords.exe** | Engineering menus | Coordinate lookup | User dir files |

TSIP internally reuses **`AxOrbitSupp`** for optional `.ORBIT` reports inside `TtTsorbCalcs`.

---

## Key source files (start here when reading code)

| File | Why |
|------|-----|
| `MicsBat\TpRunTsip\TpRunTsip.cs` | Main loop, report orchestration |
| `MicsBat\TpRunTsip\TtCalcs.cs` | TS–TS path loss + C/I math |
| `MicsBat\TpRunTsip\TtBuildSH.cs` | TS–TS table build + culling |
| `MicsBat\TpRunTsip\TeCalcs.cs` / `TeSubCalc.cs` | ES path loss |
| `MicsBat\_Utillib\GenUtil.cs` | Free space, CCIR helpers |
| `MicsBat\_Utillib\TsipQ.cs` | Queue + spawn TpRunTsip |
| `MicsBat\_Utillib\Ssutil.cs` | DB connect, GetBinPath |
| `MicsBat\TsipInitiator\TsipInitiator.cs` | Web entry orchestration |
| `mics\Ttsipmenu\TwsTsip.asmx.cs` | Web service submit |
| `mics\Ttsipmenu\tsipBatch.aspx` | User batch UI |

External doc reference in code: `AH-0034 TsipInitiator System Context.pdf` (under mics documentation).

---

## Open questions

1. Is **`MICSH`** or **`MicsBat`** the authoritative build tree for TSIP today?
2. **`GetBinPath` hardcode** to `D:\develbat\` — intentional for all dev work or temporary?
3. Production **`TpRunTsip`** path — `{micsRoot}\bin` vs `prod\bin` when override removed?
4. Full mapping of **`spherecalc`** and **`analopt`** parm values to user-visible UI labels
5. **`TsipSkim`** — is it still used in any workflow?

---

## Related

- [Batch programs](batch-programs.md) — deploy paths, TsipInitiator in develbat
- [Automated testing](automated-testing.md) — tier 4 batch smoke candidate
- [Web app structure](web-app-structure.md) — JobSubmit pattern
- [Application learnings](application-learnings.md) — UseDbAuth / env pitfalls
- [TSIP archive queries](tsip-archive-queries.md) — inspect `web.tsip_run` and report lines
- [Test fixtures and baselines](test-fixtures-and-baselines.md) — rolling distinct TSIP compare
