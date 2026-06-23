# ReMICS Dev — database access

**Codebase:** remicsdev  
**Verified:** 2026-06-23 (`sqlcmd` connectivity, permissions, schema inventory)  
**Prerequisite:** [Infrastructure mapping](infrastructure-mapping.md)  
**Context file:** [`context/codebases/remicsdev.yaml`](../../context/codebases/remicsdev.yaml)

How to query and modify the **remicsdev** SQL Server database from CentralProject (agents, scripts, ad-hoc work).

---

## Connection summary

| Setting | Value |
|---------|--------|
| Instance | `EC2AMAZ-9DKDM82\REMICS_DEV` |
| Database | `remicsdev` |
| Auth | **Windows integrated** (`Trusted_Connection=true`) |
| ODBC DSN (system) | `remicsdev` → same instance, database `RemicsDev` |
| Web app connection | Built in `Global.asax.cs` from `SQL_INSTANCE` + `DBName` in `web.config` |

```text
Server=EC2AMAZ-9DKDM82\REMICS_DEV;Database=remicsdev;Trusted_Connection=true;
```

**Verified (2026-06-23):** Shell running as `CLOUDMICSDEV\jscott` connects with **db_owner** on `remicsdev` (SELECT, INSERT, UPDATE, ALTER).

Other environments (`remicstest`, production, import) use different IIS sites and may point at different databases — only **remicsdev** is covered here until explicitly tested.

---

## Helper script

**Path:** [`scripts/Invoke-RemicsDevSql.ps1`](../../scripts/Invoke-RemicsDevSql.ps1)

Wraps `sqlcmd` with remicsdev defaults. Override server/database via environment variables or optional `.env.local` keys (see below).

### Examples

```powershell
cd E:\AIProjects\CentralProject

# Inline query
.\scripts\Invoke-RemicsDevSql.ps1 -Query "SELECT DB_NAME() AS db, SYSTEM_USER AS [user]"

# List all schemas (with table counts)
.\scripts\Invoke-RemicsDevSql.ps1 -ListSchemas

# List tables in web schema
.\scripts\Invoke-RemicsDevSql.ps1 -ListTables -Schema web

# Run a .sql file (e.g. future TSIP archive DDL)
.\scripts\Invoke-RemicsDevSql.ps1 -InputFile .\path\to\script.sql

# Read-only guard (blocks INSERT/UPDATE/DELETE/DDL/EXEC)
.\scripts\Invoke-RemicsDevSql.ps1 -ReadOnly -Query "SELECT TOP 10 * FROM web.some_table"
```

### Overrides

| Source | Keys |
|--------|------|
| Parameters | `-Server`, `-Database` |
| Environment | `REMICS_SQL_SERVER`, `REMICS_SQL_DATABASE` |
| `.env.local` (gitignored) | Same keys — see [`env.local.example`](../../env.local.example) |

### Requirements

- **sqlcmd** on PATH (or default install path under SQL Server Client SDK)
- Windows account with rights on `remicsdev` (same as interactive login on the server)

---

## Raw sqlcmd (no script)

```powershell
& "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE" `
  -S "EC2AMAZ-9DKDM82\REMICS_DEV" `
  -d remicsdev `
  -E `
  -Q "SELECT TOP 5 TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES ORDER BY 1, 2" `
  -W -s "|"
```

---

## Schema overview

MICS uses **many SQL schemas** — often one per project, customer, or functional area. Table names are frequently prefixed by domain (`ts`, `es`, `tt_*` working tables, etc.).

**Verified** top schemas by table count (2026-06-23):

| Schema | Tables (approx.) | Typical role |
|--------|------------------|--------------|
| `venn`, `frse`, `hulme`, `fmda2`, … | 100–1300+ | **Project / tenant** data partitions |
| `dbo` | ~209 | Shared / legacy objects |
| `web` | ~9 | Web-layer registry (future TSIP archive targets `web.tsip_run`, etc.) |
| `tsip`, `tsip_archive` | ~6 / ~18 | TSIP-related persistent objects |
| `acct` | ~21 | Accounting / storage usage |
| `tabledef`, `techdef` | ~39 / ~26 | Metadata / definitions |
| `fcc`, `ised`, `import` | varies | Domain modules |

Refresh counts anytime:

```powershell
.\scripts\Invoke-RemicsDevSql.ps1 -ListSchemas
```

**Inferred:** Most day-to-day MICS data lives under **project-named schemas**, not only `dbo`. Always confirm schema before `SELECT *`.

### Discovering structure

```powershell
# Columns for a table
.\scripts\Invoke-RemicsDevSql.ps1 -Query @"
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'web' AND TABLE_NAME = 'your_table'
ORDER BY ORDINAL_POSITION
"@

# Foreign keys referencing a table
.\scripts\Invoke-RemicsDevSql.ps1 -Query @"
SELECT fk.name, OBJECT_SCHEMA_NAME(fk.parent_object_id) AS fk_schema,
       OBJECT_NAME(fk.parent_object_id) AS fk_table
FROM sys.foreign_keys fk
WHERE OBJECT_SCHEMA_NAME(fk.referenced_object_id) = 'web'
  AND OBJECT_NAME(fk.referenced_object_id) = 'your_table'
"@
```

---

## Conventions for agents and scripts

### Read vs write

| Intent | Approach |
|--------|----------|
| Exploration, reporting, schema discovery | Prefer `-ReadOnly` or plain `SELECT` |
| Data fix, archive load, DDL | Omit `-ReadOnly`; confirm database name first |
| Production / import DBs | **Do not assume** — test connection and permissions explicitly |

### Safety checks before writes

1. Confirm **database** = `remicsdev` (not prod/import).
2. Confirm **schema + table** with `INFORMATION_SCHEMA` or `-ListTables`.
3. Use transactions when testing destructive work: `BEGIN TRAN` … `ROLLBACK` until satisfied.
4. Prefer idempotent DDL (`IF NOT EXISTS`) for new objects (see [TSIP archive plan](tsip-archive-plan.md)).

### Working tables (`tt_*` / `te_*`)

TSIP and similar batch jobs create **ephemeral per-run tables** in project schemas. They are dropped on the next rerun of the same parm/run name — not a safe place for long-term edits without understanding the batch lifecycle. See [TSIP tt tables](tsip-tt-tables.md).

### Credentials

- **No SQL password in repo.** Windows auth only for this environment.
- `.env.local` may hold optional `REMICS_SQL_*` overrides; never commit secrets.
- LDAP / AD strings in `web.config` are for the **web app**, not for ad-hoc SQL access.

---

## How the web app connects (reference)

From `web.config` → `Global.asax.cs`:

| `web.config` key | Application key | remicsdev value |
|------------------|-----------------|-----------------|
| `SQL_INSTANCE` | `Sql_Instance` | `EC2AMAZ-9DKDM82\REMICS_DEV` |
| `DBName` | `db_name` | `remicsdev` |
| *(computed)* | `sqlclient_cnString` | `Server=…;Database=remicsdev;Trusted_Connection=true;` |

Runtime pages also set `Session["s_schema"]` per logged-in user/project — ad-hoc SQL bypasses that and can query any schema your login allows.

---

## Related docs

| Topic | Doc |
|-------|-----|
| IIS + SQL wiring | [Infrastructure mapping](infrastructure-mapping.md) |
| Login → session → DB routing | [Login flow](login-flow.md) |
| TSIP working tables | [TSIP tt tables](tsip-tt-tables.md) |
| Planned archive DDL (`web.*`) | [TSIP archive plan](tsip-archive-plan.md) |
| Where source lives | [Source layout](source-layout.md) |
