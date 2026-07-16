# ReMICS application architecture and lessons learned

This document records the application behavior discovered while replacing the
remicsdev Active Directory login dependency, exercising TS/ES file operations,
and building repeatable TSIP comparisons. It describes the application as
observed in July 2026 and is intended to guide future maintenance.

## Application shape

ReMICS is a legacy ASP.NET Web Forms application composed of a main `mics`
project and many feature-specific assemblies. Authentication and execution are
not isolated concerns: identity is used by page code, SQL connections,
filesystem access, and native batch-process submission.

The browser-facing application and the native MICS programs form one runtime:

1. Forms Authentication establishes the browser session.
2. `Tlogin.aspx.cs` establishes MICS session values.
3. `TloginValidate.aspx.cs` resolves the schema, project, and working directory.
4. Web Forms pages and ASMX services invoke `JobSubmit`.
5. `JobSubmit` passes the session context to native programs through environment
   variables.
6. Native programs use the schema/project context and write tables, files, and
   TSIP run records.

Changes to login behavior therefore have to be tested through native file and
TSIP operations, not only through successful page navigation.

## Identity has four separate meanings

The application historically treated several identities as if they were one:

- **MICS identity**: the value stored in `Session["s_user"]`.
- **Web principal**: the authenticated browser principal.
- **Windows execution identity**: formerly the AD user token stored in
  `Session["principalw"]`.
- **SQL/filesystem identity**: formerly inherited from Windows impersonation.

With database authentication enabled, these are deliberately separated:

- The MICS identity remains the selected application user.
- Forms Authentication remains the browser-session mechanism.
- SQL, filesystem, and child processes run as the IIS application-pool
  identity.
- The selected MICS identity is passed to batch programs through `MicsUser`.

This separation is the central design rule for AD-free operation.

## Database authentication

`UseDbAuth` is the feature flag separating the new and old paths:

- `true`: credentials are checked against `dbo.t_UserDetails`, AD `LogonUser`
  is skipped, and work runs as the application pool.
- `false`: the original membership, `LogonUser`, impersonation, and
  `CreateProcessAsUser` behavior remains.

`SesUtilities.MicsDbAuth` centralizes the flag and database-authentication
operations. SQL is parameterized and explicitly executed as the process
identity so request impersonation cannot change the connection identity.

The current development implementation compares the supplied password with the
existing plaintext `dbo.t_UserDetails.Password` value. This proves the
application flow but is security debt; a password-hash migration is required
before treating this as a modern credential store.

An account is usable only when:

- `micsId` matches the submitted MICS ID.
- `IsActiveYN` is `Y`.
- `PrimarySchema` is populated.
- The referenced SQL schema actually exists.
- `adm.project_ids` contains the projects that should be visible to that MICS
  ID.

`PrimarySchema` is the source of truth for the application schema. SQL
functions based on the current SQL login, such as `dbo.user_schema()`, do not
represent the selected MICS user when all requests connect as the app pool.

## Session contract

The important session values include:

- `s_user`: selected MICS ID.
- `s_password`: password passed to native tools by the existing contract.
- `s_schema`: value resolved from `t_UserDetails.PrimarySchema`.
- `defProject`: selected/default project from `adm.project_ids`.
- `user_dir`: per-schema, per-user working directory.
- `s_cnString`: application ODBC connection string.
- `principalw`: legacy compatibility value expected by many assemblies.

The database-authentication path stores the process principal in `principalw`.
This avoids null-reference failures in old code, but it is not a token for the
selected MICS user. New or edited code must use
`MicsDbAuth.ImpersonateForJob(...)`, which impersonates only on the old AD path
and is a no-op under database authentication.

## Project lookup

`adm.project_ids_view` depends on SQL `USER`. It worked while each request
impersonated an AD user, but it returns the app-pool user's view of the data
under database authentication.

The database-authentication path must query `adm.project_ids` by `micsid`.
Default-project updates must continue to constrain both `micsid` and schema so
one user's selection does not alter another user's defaults.

## Batch execution contract

The old `JobSubmit` implementation launches native tools with
`CreateProcessAsUser` and the AD token. The database-authentication path uses
`Process.Start`, which causes the child process to run as the IIS application
pool.

Before launching a tool, the web application populates environment variables
including:

- `SqlInstance`
- `MicsUser`
- `Password`
- `Domain`
- `webdrive`
- `work_dir`
- `odbc`
- `DBName`
- `MICS_PROJECT`
- `MICS_NAD_FILE`

These variables are part of the effective interface between the web
application and native executables. A login change that does not preserve them
can appear successful in the browser while native operations fail.

`JobSubmit` and `JobSubmit2` both require the database-authentication branch.
Asynchronous and long-running TSIP behavior must also be retained:

- Negative wait values mean submit and return.
- A zero wait means wait indefinitely.
- A positive wait is a timeout.
- `TsipInitiator` may be left running after the web request returns.

Diagnostic logging must tolerate unavailable log files. Logging errors should
not prevent the requested batch process from starting.

## Application-pool permissions

The app-pool identity replaces per-user AD identities for infrastructure
access. It therefore needs:

- Trusted SQL access to the ReMICS database.
- Required read/write/DDL permissions in every enabled MICS schema.
- Read/write/create access in user working directories.
- Access to batch executable and shared-data directories.
- Access to application and batch logs.

Adding an account to `t_UserDetails` or the admin dropdown is insufficient when
its schema has not been granted to the app pool. Account activation, schema
existence, project mapping, SQL permissions, and filesystem permissions must be
verified together.

## TS and ES file operations

TS and ES files use different executable families and table prefixes:

- TS: `FtPrint`, `FtImport`, `FtValidate`, and `ft_` tables.
- ES: `FePrint`, `FeImport`, `FeValidate`, and `fe_` tables.

They also use different command-line conventions. The harness must dispatch by
fixture `file_type`; changing only the filename is not sufficient.

TS files contain an operator code in the `SD` record. Imports into a different
schema can silently filter data or create empty fixture tables when the
embedded operator does not match the target schema. Shared TS fixtures must be
copied to a temporary file and have the operator field adapted before import.

PowerShell must fully materialize file content before overwriting the same
temporary file. A streaming `Get-Content | ... | Set-Content` pipeline can keep
the source open and cause a file-lock failure.

Fixture discovery cannot trust `PrimarySchema` alone. Some user rows can refer
to schemas that do not exist, so schema-wide operations must join or check
`sys.schemas`.

## Shared fixtures and destructive operations

The shared fixtures are:

- TS: `testts1`, `testts2`, `testts3`
- ES: `testes1`, `testes2`, `testes3`

`Install-MicsSharedTestFixtures.ps1` installs them into active, existing
schemas. Without `-Force`, existing fixture sets are preserved. With `-Force`,
the script removes tables belonging to the reserved fixture names before
reimporting them.

Because import and round-trip tests can create and drop tables, fixture names
must remain reserved and clearly separate from user data. Test scripts should
never generalize destructive cleanup from these explicit fixture roots.

## TSIP history and comparison

`web.tsip_run` is the durable source for TSIP run metadata. "Last 10 runs" is
not the same as "last 10 useful test cases": users may run the same parameter
file repeatedly.

The recent-distinct batch selects the latest completed baseline for each
distinct:

```text
source_schema + protype + parm_file
```

It orders those representatives by recency and processes up to ten. This
supports fewer than ten available cases and automatically incorporates new
distinct parameter files.

Each batch writes a manifest and per-run results. Individual comparisons are
kept isolated so one failed run does not erase the results of completed runs.
PowerShell 5.1 also requires generic lists to be converted with `.ToArray()`
before JSON serialization in this flow.

## Admin test harness

The FCSA admin panel is intentionally allowlisted. Its account dropdown is a
test control, not general user administration. The selected account is passed
to `fileop-start.ashx`, validated again by the handler, and then supplied to
`Invoke-MicsFileOpCompare.ps1`.

The source and deployed copies must stay synchronized:

- `sites/fcsa/src/admin`
- `sites/fcsa/dist/admin`

Result and diagnostic files generated by handlers are runtime artifacts and
should not be committed.

Per-user test passwords belong in `.env.local` and must not be committed. The
scripts use account-specific keys before any shared fallback.

## Build and deployment dependencies

`utilities.dll` contains `MicsDbAuth` and `JobSubmit`; it must be rebuilt before
assemblies that reference the new helper. The main authentication changes are
in `mics.dll`, while file operations are primarily in `Tfileactions.dll`.
Additional ASMX and feature assemblies contain direct impersonation wrappers
and must be rebuilt after those wrappers are converted.

The safe source-edit order is:

1. Add and build the utilities changes.
2. Apply and build the main `mics` login/session changes.
3. Apply and build `Tfileactions`.
4. Apply the mechanical impersonation-wrapper change to the remaining feature
   projects and build each affected assembly.
5. Deploy the matching configuration and admin-harness files.
6. Recycle the application pool and test through native operations.

## Minimum regression coverage

A successful login is only the first check. Regression testing should include:

1. Valid, invalid, and inactive database accounts.
2. Schema and default-project resolution for users in different schemas.
3. Password change.
4. TS print/export, import, validate, and round trip.
5. ES print/export, import, validate, and round trip.
6. Table copy/delete or other representative ASMX operations.
7. TSIP submission, completion, archive, and comparison.
8. Filesystem creation in a new user's work directory.
9. A feature-flag check of the retained AD path where that environment is
   available.

The highest-value diagnostic information is the selected MICS ID, resolved
schema/project/work directory, effective Windows process identity, executable
and arguments, environment setup, native exit code, and result artifact path.
