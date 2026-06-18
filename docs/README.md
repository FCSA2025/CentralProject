# Documentation

CentralProject documents how related codebases work — not just where files live, but how requests, configuration, batch jobs, and databases connect.

The codebases are legacy ASP/ASP.NET and cause-and-effect is spread across many folders, and behavior is often driven by `web.config` and `Global.asax` rather than obvious entry points. These docs are written to reduce that navigation cost.

## How docs are organized

```
docs/
  README.md                 ← you are here
  remicsdev/                ← first codebase
    README.md               ← index for this codebase
    infrastructure-mapping.md
    (future topics…)
```

| Layer | What it covers | Example doc |
|-------|----------------|-------------|
| **Infrastructure** | IIS, URLs, disk paths, app pools, config files | `infrastructure-mapping.md` |
| **Startup & config** | Application boot, `web.config` keys, session/auth | `login-flow.md` |
| **Web application** | Folders, shared libs, batch invocation | `web-app-structure.md` |
| **Batch programs** | C# console tools, build output, deploy paths | `batch-programs.md` |
| **Database** | SQL Server, ODBC, schemas, who connects how | *(planned)* |
| **Automated testing** | Smoke/E2E tiers 1–4 | `automated-testing.md` |

Each codebase gets its own folder under `docs/`. Machine-readable facts (paths, bindings, verified dates) also live in [`context/codebases/`](../context/codebases/) as YAML for tooling and quick reference.

## Writing conventions

- **Verified** — confirmed on the server (IIS query, file read, runtime).
- **Inferred** — logical conclusion not yet fully traced in code.
- **Open** — explicitly unknown; listed until resolved.

When adding a doc, link back to related docs and to the YAML context file. Prefer diagrams and tables over long prose.

## Registered documentation

| Codebase | Index | Docs |
|----------|-------|------|
| remicsdev | [remicsdev/README.md](remicsdev/README.md) | [Infrastructure](remicsdev/infrastructure-mapping.md) · [Login/session](remicsdev/login-flow.md) · [Testing strategy](remicsdev/automated-testing.md) |
