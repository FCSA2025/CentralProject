# CentralProject

Central hub for managing, editing, compiling, and updating related codebases on the Windows/IIS server.

Codebases are registered one at a time under `context/codebases/`. Each file documents paths, solutions, databases, and build/deploy notes for that system.

**Human-readable documentation** (how the code works) lives under [`docs/`](docs/).

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
