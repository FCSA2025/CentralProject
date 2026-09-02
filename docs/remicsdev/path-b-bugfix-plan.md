# RemIcsReWrite — Path B bug-fix plan (2026-09-02)

**Status:** **Waves 0–3 complete** (2026-09-02)  
**Parent:** [remicsrewrite-stabilization-plan.md](remicsrewrite-stabilization-plan.md) (Path B ops/regression)  
**Scope:** Confirmed code bugs from high-yield audit + medium/lower-yield follow-up pass  
**Out of scope:** Interior polish (Path A), Phase 7 / hidden nav (Path C), speculative “could be” issues

**Test policy:** Every fix verified on roster **≥2 of** `bchy1`, `rctl1`, `xci1` (note schemas in PR/commit notes). Prefer automated smoke where practical.

---

## Progress log

| When | ID | Result |
|------|-----|--------|
| 2026-09-02 | **W0-1** | Fixed in `pwd-reset.aspx`: email lookup before `SetPassword`; no email → refuse mutate, message includes “Your password was not changed.” Deployed to `D:\inetpub\remicsdev\mics\RemIcsReWrite\pwd-reset.aspx` (hash match). **Decision:** refuse change without email (not “change + display”). |
| 2026-09-02 | **W0-2** | Fixed in `pcn.ashx`: honor `InsertEmailQueue` result; on failure return `ok: false`, preserve userdirs export for retry; temp/export cleanup only after successful queue. UI already handles `!r.ok` (`remics-ts.js`). Deployed to IIS (hash match). |
| 2026-09-02 | **W0-3** | Fixed in `kml.ashx` `MailReports`: if zero attachments after existence checks, return `false` with clear error; do not send or delete sources. UI already handles `!r.ok` (`remics-ts.js` mountKml). Deployed to IIS (hash match). |
| 2026-09-02 | **W1-1** | Fixed in `sdf-files.ashx`: Ctx suffix `"ctx"` → `"ctx_"`; LIKE builder escapes `_`/`%` in suffix so `ctx_` does not also match `ctxd`. Verified DB + HTTP: `bchy1` Ctx list returns `rd3ctx` / `su_rd3ctx_ctx_` only. Deployed to IIS. |
| 2026-09-02 | **W1-2** | Fixed in `CaseDetCsv.cs` `get_antepos_ft` / `get_antepos_mt`: on site miss append `,,,`; on ante miss append `,` so TSTS CSV always emits 4 antepos fields. Deployed to IIS. |
| 2026-09-02 | **W1-3** | Fixed in `CaseDetCsv.cs` `get_terrinfo`: clear `terrlatit2`/`terrlongit2`/`terrgrnd2`/`terranum2`/`terracode2`/`terrht2` at start of each call so a miss does not reuse the prior row. Deployed; `bchy1` TSES CSV generate OK (`te_testes1_es1.csv`). |
| 2026-09-02 | **W1-4** | Fixed in `CaseDetKml.cs` `WriteTETTLinkInfo` / `WriteETTTLinkInfo` / `WriteTTLinkInfo` (both loops): reset remote lat/long/alt/anum each row; skip green link when remote lookup misses. Deployed to IIS. |
| 2026-09-02 | **W1-5** | Fixed in `CaseDetKml.cs` `HtmlDescET`: Interferer uses `dlatl`/`dlongl`, Victim `dlatr`/`dlongr` (mirror `HtmlDescTE`). Deployed to IIS. |
| 2026-09-02 | **W2-1** | Fixed in `CaseDetKml.cs` `Finish`: empty generate → `ok: false` + error; `remics-phase675.js` KML path alerts on `r.error`. Deployed to IIS. |
| 2026-09-02 | **W2-2** | Fixed in `CaseDetKml.cs` `Finish`: partial TE/ET/TT email → `ok: false` with sent counts; UI surfaces `r.error`. Deployed to IIS. |
| 2026-09-02 | **W2-3** | Fixed in `aux-passive.ashx` / `aux-ohl.ashx` / `aux-terrain.ashx`: missing/empty report after job success → `ok: false`. **Decision:** hard fail (Email stays disabled). Deployed to IIS. |
| 2026-09-02 | **W2-4** | Fixed in `dbupdate.ashx`: when `emailOk == false`, keep `ok: true` for transfer but message = “transfer succeeded, but notification email failed…”. UI already soft-warns via `emailSent` (`remics-ts.js`). **Decision:** soft honesty (transfer OK, notify failed). Deployed to IIS. |
| 2026-09-02 | **W2-5** | Fixed in `remics-ds.js`: removed `updateValidES` `.catch(() => ({ok:true}))` swallow; invalidate failure falls through to save `.catch`. Deployed to IIS. |
| 2026-09-02 | **W2-6** | Fixed in `sdf-edit.ashx` ChildSave/ChildDelete: honor `SetUserValidFlag` like parent saves; `ok: false` on failure. Deployed to IIS. |
| 2026-09-02 | **W2-7** | Fixed in `TwsTsip.asmx.cs` `AppendPdfCatalogCheck`: blank/whitespace PDF name → validate failure code `1`. Live IIS hash already matched (file locked during copy retry). |
| 2026-09-02 | **W3-1** | Fixed in `genctx.ashx`: after Finish + logerrorcode switch, also fail when `logreturncode != 0` (classic AUXgenctx1 gate). Deployed to IIS. |
| 2026-09-02 | **W3-2** | Fixed in `genctx.ashx` `LoadCtxFps`: removed empty catch; `HandleSpectra` returns `ok: false` on DB failure. Deployed to IIS. |
| 2026-09-02 | **W3-3** | Fixed in `pwd-reset.aspx` / `pwd-recovery.ashx`: adm fallback uses `micsid` + `ultrixid` when schema known (`GetPrimarySchema` / `s_schema`). Deployed to IIS. |
| 2026-09-02 | **W3-4** | Fixed in `aux-hilo.ashx`: `LogMenuUse("AUXHiLo")` (classic AUXHilo1 incorrectly logged `AUXGenCTX`). Deployed to IIS. |
| 2026-09-02 | **W3-5** | Fixed in `remics-phase675.js` bulk print: on `!data.ok`, alert/status includes `printed: [...]`. Deployed to IIS. |
| 2026-09-02 | **W3-6** | Fixed in `ds-search.ashx` / `ds-sdf.ashx` / `CaseDetCsv.cs` / `CaseDetKml.cs`: generic client errors; `NotifySystemOps` where available; no `ex.ToString()` / SQL in JSON. Deployed to IIS. **Decision:** scrub now. |
| 2026-09-02 | **W3-7** | Fixed in `remics-ds.js` (TS/ES search) + `remics-phase675.js` (DS-SDF search): `.catch` clears stuck “Searching...”. Deployed to IIS. |
| 2026-09-02 | **W3-8** | Fixed in `remics-phase675.js` `populateSdfSelect`: surface error on `!data.ok`; do not silently empty. Deployed to IIS. |

---

## Bug inventory

### Wave 0 — Account lockout / false success (do first)

| ID | Sev | Area | File(s) | Defect | Fix approach | Status |
|----|-----|------|---------|--------|--------------|--------|
| **W0-1** | P0 | Password reset | `pwd-reset.aspx` | Was: `SetPassword` before email lookup; missing email left user locked out without showing new password | Lookup email **first**; only then `SetPassword`. If email missing, do **not** change password. | **Done 2026-09-02** |
| **W0-2** | P1 | PCN send | `pcn.ashx` | Was: `InsertEmailQueue` ignored; always `ok: true`; export deleted on failure | Honor `sent`; `ok: false` on queue fail; preserve export until success | **Done 2026-09-02** |
| **W0-3** | P1 | TS KML email | `kml.ashx` | Was: skip missing files then still email and return success with **zero** attachments | Fail closed if `attached == 0`; no send / no delete | **Done 2026-09-02** |

### Wave 1 — Data correctness (CSV / KML / SDF list)

| ID | Sev | Area | File(s) | Defect | Fix approach | Status |
|----|-----|------|---------|--------|--------------|--------|
| **W1-1** | P1 | SDF Ctx list | `sdf-files.ashx` | Was: suffix `"ctx"` vs tables `su_*_ctx_`; also unescaped `_` in LIKE would match `ctxd` | Suffix `"ctx_"` + escape `_`/`%` in LIKE suffix | **Done 2026-09-02** |
| **W1-2** | P1 | TSTS CASEDET CSV | `CaseDetCsv.cs` `get_antepos_*` | Was: on ante/site miss, fields not appended → column shift | Always append 4 fields (empty placeholders on miss) | **Done 2026-09-02** |
| **W1-3** | P1 | TSES CASEDET CSV | `CaseDetCsv.cs` `get_terrinfo` | Was: secondary terr fields not cleared on miss → stale prior row | Clear six fields at start of each `get_terrinfo` call | **Done 2026-09-02** |
| **W1-4** | P1 | KML green TT links | `CaseDetKml.cs` TT link writers | Was: remote lat/long not reset on lookup miss; link still drawn | Reset remote vars each row; skip link when remote lookup misses | **Done 2026-09-02** |
| **W1-5** | P2 | ET KML balloon | `CaseDetKml.cs` `HtmlDescET` | Was: lat/long columns swapped vs Interferer/Victim headers | Use `dlatl`/`dlongl` for Interferer and `dlatr`/`dlongr` for Victim (mirror `HtmlDescTE`) | **Done 2026-09-02** |

### Wave 2 — Honesty / partial success messaging

| ID | Sev | Area | File(s) | Defect | Fix approach | Status |
|----|-----|------|---------|--------|--------------|--------|
| **W2-1** | P2 | CASEDET KML empty generate | `CaseDetKml.cs` `Finish` + `remics-phase675.js` | Was: `ok: true` + “No files were created”; UI treated as success | Server: `ok: false`; UI alerts on `r.error` / `!r.ok` | **Done 2026-09-02** |
| **W2-2** | P2 | CASEDET KML partial email | `CaseDetKml.cs` `Finish` + `remics-phase675.js` | Was: TE/ET partial send → `ok: true`; UI ignored `error` | All intended sends must succeed for `ok: true`; else `ok: false` with counts; UI surfaces `r.error` | **Done 2026-09-02** |
| **W2-3** | P2 | Aux Passive / OHL / Terrain | `aux-passive.ashx`, `aux-ohl.ashx`, `aux-terrain.ashx` | Was: job “success” with missing/empty report still `ok: true` | Hard `ok: false` when report missing/empty (Email stays disabled) | **Done 2026-09-02** |
| **W2-4** | P2 | DbUpdate notify | `dbupdate.ashx` + `remics-ts.js` | Was: `ok: true` + “complete” when `emailOk == false` | Soft: `ok: true` + `emailSent: false` + message “transfer OK, notify failed” (never “complete” alone) | **Done 2026-09-02** |
| **W2-5** | P1 | ES Data Search save | `remics-ds.js` | Was: `updateValidES` `.catch(() => ({ ok: true }))` swallows failure → “Save complete” | Remove swallow; invalidate failure → save failure | **Done 2026-09-02** |
| **W2-6** | P2 | SDF child edit | `sdf-edit.ashx` ChildSave/ChildDelete | Was: `SetUserValidFlag` return ignored | Check return like parent saves; `ok: false` on failure | **Done 2026-09-02** |
| **W2-7** | P2 | `tsipValidateAll` blank PDF | `TwsTsip.asmx.cs` `AppendPdfCatalogCheck` | Was: blank `proname` / blank `envname` (when PDF_*) skipped → looks Ready | Whitespace PDF → validate failure code `1` | **Done 2026-09-02** |

### Wave 3 — Medium/lower yield follow-ups

| ID | Sev | Area | File(s) | Defect | Fix approach | Status |
|----|-----|------|---------|--------|--------------|--------|
| **W3-1** | P2 | genctx | `genctx.ashx` | Was: did not check `logreturncode` after Finish | Fail when `logreturncode != 0` (classic gate) | **Done 2026-09-02** |
| **W3-2** | P2 | genctx spectra | `genctx.ashx` `LoadCtxFps` | Was: DB exceptions swallowed → always `ok: true` empty | Propagate `ok: false` on DB failure | **Done 2026-09-02** |
| **W3-3** | P2 | pwd email fallback | `pwd-reset.aspx`, `pwd-recovery.ashx` | Was: adm fallback `WHERE micsid` only | Schema-scoped `micsid` + `ultrixid` when known | **Done 2026-09-02** |
| **W3-4** | P2 | Aux HiLo telemetry | `aux-hilo.ashx` | Was: `LogMenuUse("AUXGenCTX")` | `LogMenuUse("AUXHiLo")` (classic had same bug) | **Done 2026-09-02** |
| **W3-5** | P2 | print-email UI | `remics-phase675.js` bulk print | Was: partial print list ignored on failure | Surface `printed: [...]` in error alert/status | **Done 2026-09-02** |
| **W3-6** | P2 | Exception detail leak | `ds-search.ashx`, `ds-sdf.ashx`, CaseDet CSV/KML | Was: full `ex.ToString()` / raw SQL to client | Generic message + `NotifySystemOps`; no stack/SQL in JSON | **Done 2026-09-02** |
| **W3-7** | P3 | Search UI hang | `remics-ds.js`, `remics-phase675.js` DS-SDF | Was: missing `.catch` → “Searching...” stuck | Add `.catch` → setStatus error | **Done 2026-09-02** |
| **W3-8** | P3 | SDF dropdown | `remics-phase675.js` `populateSdfSelect` | Was: ignores `!data.ok` | Show status error; do not silently empty | **Done 2026-09-02** |

---

## Explicitly not bugs / deferred

| Item | Why |
|------|-----|
| remicsdev `adm.pcn_account_details` for email | Intentional remicsdev/micstest routing (aligned with Aux Eng after Al email fix) |
| Nested ODBC in pdf-edit / pdf-extra | Not found in this pass |
| Monitor / Delete TSIP ownership | Looks correct (own + `W`) |
| contact / session timeout | Clean |
| files.ashx / reconcile.ashx | Clean for Gate B patterns |
| DS search master tables (`main.mt_*`) | By design |
| Path A interior / Path C Phase 7 | Abandoned/paused |

---

## Execution order (recommended)

```
Wave 0  →  W0-1, W0-2, W0-3          (lockout + false email success)  DONE
Wave 1  →  W1-1 … W1-5              (wrong data on disk / maps)       DONE
Wave 2  →  W2-1 … W2-7              (honesty / Ready / Save complete) DONE
Wave 3  →  W3-1 … W3-8              (hardening / telemetry / leaks)   DONE
```

Ship waves as separate reviewable commits (or one commit per wave). Do not mix Wave 0 with polish.

---

## Verification checklist (per wave)

```powershell
# Always after deploy
.\scripts\Invoke-GateFRegressionTest.ps1 -HttpOnly
.\scripts\Invoke-RemicsReWriteFeatureSmoke.ps1 -User bchy1 -BaseUrl 'http://remicsdev.cloudmicsdev.ca/mics/'
.\scripts\Invoke-RemicsReWriteFeatureSmoke.ps1 -User xci1  -BaseUrl 'http://remicsdev.cloudmicsdev.ca/mics/'
```

| Wave | Extra verification |
|------|-------------------|
| **0** | Manual pwd-reset with user that has QA but **no** email → password unchanged (or password shown). PCN send with forced queue fail (or bad staging) → `ok: false`, export still present. KML email with missing files → `ok: false`. |
| **1** | SDF Ctx tree non-empty for a schema that has `su_*_ctx_`. CASEDET CSV sample rows before/after for miss cases. KML ET balloon + green links spot-check. |
| **2** | CASEDET KML empty run + partial email UX. Aux OHL/Passive missing-report path. ES Data Search save with invalidate forced fail. Empty-proname run fails `tsipValidateAll`. |
| **3** | genctx fail path; HiLo menu log row shows `AUXHiLo`; DS search 500 body has no stack; print-email partial message. |

**Gate coverage follow-ups (after fixes land):**

- [x] Document pwd-reset contract: email required before `SetPassword`; no email → password unchanged (W0-1)
- [x] Ctx SDF list: `sdf-files.ashx?type=Ctx` returns real `su_*_ctx_` masters (W1-1; verified bchy1 → `rd3ctx`)
- [ ] Optional: CASEDET generate empty → `ok: false` assertion for a known empty run
- [ ] Optional: blank-proname `tsipValidateAll` → failure code `1` (W2-7)
- [ ] Optional: DS search forced 500 → JSON has no `detail` / stack (W3-6)

---

## Effort sketch

| Wave | Rough size | Risk |
|------|------------|------|
| 0 | Small (3 files) | High user impact if wrong — test carefully |
| 1 | Medium (CaseDetCsv/Kml + sdf-files) | Data output changes — compare sample CSV/KML |
| 2 | Medium (handlers + JS) | Contract changes for UI — update callers |
| 3 | Small–medium | Mostly fail-closed / logging |

---

## Review decisions

1. **W0-1:** **Refuse** password change when email is missing (implemented). Do not rotate-and-display in the no-email path.
2. **W2-3:** **Hard** `ok: false` when report missing/empty (implemented).
3. **W2-4:** **Soft** honesty — transfer may succeed with `ok: true` + `emailSent: false` and explicit “notify failed” message (implemented).
4. **Wave 3 W3-6:** **Scrub now** — generic client messages + `NotifySystemOps` (implemented).
5. **W3-4:** Use **`AUXHiLo`** (classic AUXHilo1 incorrectly used `AUXGenCTX`).
6. **Ship cadence:** still open — one wave per day vs one push?

---

## References

- High-yield audit (2026-09-02 chat): Aux Eng, PCN/KML/DbUpdate/SDF, CASEDET, `tsipValidateAll`
- Medium/lower pass: pwd-reset, ES DS save, genctx, print-email UI, DS exception leaks, HiLo telemetry
- Prior fixed pattern to mirror: `tsip-reps-tree` nested readers + Gate C/F honesty; `UserDirUtil` + `Assembly Src`
- W0-1: `pwd-recovery.ashx` email-before-mutate order
