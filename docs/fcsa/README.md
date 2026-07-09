# FCSA.ca documentation

Public marketing site for the Frequency Coordination System Association — migration from external WordPress to a self-hosted static IIS site.

**Live site today:** https://fcsa.ca (WordPress on nginx/Plesk — not on our IIS servers)  
**MICS application:** [remicsdev documentation](../remicsdev/README.md)

## Documentation index

| Doc | Status | Summary |
|-----|--------|---------|
| [Migration plan (Phases 1–4)](fcsa-migration-plan.md) | **Active** | WordPress → static IIS on server IP; HTTP only; DNS out of scope |
| [MICS auth integration (Phase 5)](fcsa-mics-auth-integration.md) | **Planned** | Single login via `fcsa.ca/mics`; cookie vs session; TSIP compatibility |

## Quick reference

| What | Value |
|------|-------|
| WordPress host | External (nginx/Plesk, PHP 8.3) |
| Target IIS app pool (static) | `fcsaapp` — own pool; v4.0 Classic like `remicsdevapp`; identity `ApplicationPoolIdentity` |
| Target IIS site | `fcsa` — binding `http/*:80:` (IP default) |
| Target physical path | `D:\inetpub\fcsa\` |
| Public access (this plan) | `http://35.182.140.161/` (verify IP if server changes) |
| `fcsa.ca` DNS | **Unchanged** — WordPress stays public |
| TLS | **Deferred** — HTTP only for now |
| SEO | Not required for migration |
| Member / auth pages | **Omit** — ReMICS/MICS auth at merge (Phase 5) |
| Default Web Site | Stop + remove `:80` binding at Phase 3 |
| French | Copy `/fr/` content; simplified paths under `/fr/` |
| Visual style | Clean modern CSS; logos/colors from WordPress |

## Related

- [TODO](../TODO.md) — FCSA migration task list
- [Login flow & session model](../remicsdev/login-flow.md) — MICS auth mechanics
- [Infrastructure mapping](../remicsdev/infrastructure-mapping.md) — IIS patterns on remicsdev server
