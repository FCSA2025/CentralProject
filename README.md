# CentralProject

Central hub for managing, editing, compiling, and updating related codebases on the Windows/IIS server.

Codebases are registered one at a time under `context/codebases/`. Each file documents paths, solutions, databases, and build/deploy notes for that system.

**Human-readable documentation** (how the code works) lives under [`docs/`](docs/).

**Git/GitHub on a new machine:** [docs/github-setup-checklist.md](docs/github-setup-checklist.md) — credential pitfalls, pre-flight checks, copy-paste setup.

## Remote repository

**GitHub:** https://github.com/FCSA2025/CentralProject (`main`)

## Resume work

**→ [docs/TODO.md](docs/TODO.md)** — documentation backlog and auth-prep checklist.  
**→ [context/RESUME.md](context/RESUME.md)** — session state and next tasks.

## Registered codebases

| ID | Description | Context | Documentation |
|----|-------------|---------|---------------|
| remicsdev | ReMICS Dev — MICS web app + batch programs | [context/codebases/remicsdev.yaml](context/codebases/remicsdev.yaml) | [docs/remicsdev/](docs/remicsdev/) |

## Environment
- **OS:** Windows Server
- **Web server:** IIS
- **Database:** Microsoft SQL Server (remote)
- **Languages:** ASP, ASP.NET (C#), C# batch/console programs
