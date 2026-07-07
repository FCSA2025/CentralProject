# ReMICS Dev — dedicated test account setup

**Codebase:** remicsdev (Phase A) → production (Phase B)  
**Last updated:** 2026-06-30  
**Related:** [automated-testing.md](automated-testing.md), [test-fixtures-and-baselines.md](test-fixtures-and-baselines.md)

Provisioning guide for a **dedicated MICS test account** — required before running automated tests against production.

---

## Why a dedicated account

- Never run automation as a real user (`rctl1`, etc.).
- Isolated schema, fixtures, and baselines avoid side effects on production data.
- Credentials live in gitignored `tests/remicsdev/fixtures/secrets.env` only.

---

## Phase A — remicsdev now (`rctl1`)

Use `rctl1` / schema `rctl` only until the harness is stable.

Credentials via `tests/remicsdev/fixtures/secrets.env` (copy from `secrets.env.example`; never commit passwords).

---

## Phase B — `autotest1` (before prod)

### AD + MICS

1. Create AD user `autotest1` in `CLOUDMICSDEV` (or prod equivalent).
2. Add to MICS with own schema (e.g. `autotest`).
3. Set `tsip_email=n` to avoid spam during nightly runs.

### SQL + fixtures

- Copy or grant read access to pinned fixtures (`cat`, `ecomm2602` parm/tables) into `autotest` schema.
- Document copy commands here when provisioned.

### Filesystem

- `user_dir`: `D:\inetpub\remicsdev\mics\userdirs\autotest\autotest1\`
- Confirm directory created on first login.

### Windows / GPO

Same logon rights as other domain users on IIS:

- Allow log on locally
- Log on as a batch job

See [session-2026-06-29-login-import-fixes.md](session-2026-06-29-login-import-fixes.md) for error 1385 context.

### Baselines

- Seed `tests/remicsdev/fixtures/baselines-autotest1.yaml` after first successful full suite run.
- Switch default test user via env var `MICS_TEST_USER=autotest1` in `config.yaml`.

---

## Production promotion checklist

1. Provision `autotest1` (or env-specific name) on prod IIS + SQL.
2. Deploy exes (`mics.dll`, `develbat` batch programs).
3. Run smoke suite as `autotest1` only — never as real users.
4. Verify L0 + L1 + one TSIP run before declaring deploy good.
