# FCSA.ca — WordPress to static IIS migration plan

**Status:** Ready for testing (Phases 1–4 deployed 2026-07-09)  
**Last updated:** 2026-07-09  
**Phase 5 (MICS auth):** [fcsa-mics-auth-integration.md](fcsa-mics-auth-integration.md)

Migrate public FCSA marketing content from external WordPress to a self-hosted **static HTTP** site on this IIS server. **WordPress at `fcsa.ca` stays live indefinitely** — external DNS cutover is **out of scope** for this plan.

**Access model:** Browsers hitting this server’s **public IP on port 80** (no `Host` header) serve the new static FCSA site by default.

**Repo:** [CentralProject](https://github.com/FCSA2025/CentralProject) — content under `sites/fcsa/`.

---

## Out of scope (deferred to broader project)

| Item | Notes |
|------|-------|
| **External DNS** — point `fcsa.ca` / `www` to this server | WordPress remains canonical public URL for now |
| **HTTPS / TLS** | HTTP only until SSL added to project TODO |
| **Phase 5 MICS auth** | `fcsa.ca/mics` — separate future work |
| **WordPress decommission** | Not planned with this effort |

---

## Current state (verified)

### WordPress (content source)

| Item | Value |
|------|-------|
| Live URL | https://fcsa.ca (external nginx/Plesk) |
| REST API | Public — pages + media downloadable |
| Pages | ~48 (EN + partial FR); ~62 media items |

### This IIS server — IP default behavior (verified 2026-07-09)

| Item | Value |
|------|-------|
| Public IP (this host) | `35.182.140.161` |
| Port 80 default binding | **`Default Web Site`** — `http/*:80:` (no hostname) |
| Default app pool | `DefaultAppPool` — **Stopped** |
| **Result today** | `http://35.182.140.161/` → **503 Service Unavailable** |
| Default site content (if pool were started) | `C:\inetpub\wwwroot\` — IIS welcome (`iisstart.htm`) only |
| MICS sites | Host-header only (`remicsdev.cloudmicsdev.ca`, `remicstest…`) — **do not** respond to bare IP |

**Implication:** Port 80 IP traffic is unused today (503). FCSA will **take the `*:80:` binding** so IP navigation serves the new static site. `remicsdev` / `remicstest` continue to work via hostname.

---

## Scope decisions

| Decision | Choice |
|----------|--------|
| Public URL | WordPress **`fcsa.ca`** unchanged |
| This server access | **`http://<server-ip>/`** (and paths under it) |
| TLS | **Off** for now |
| Member content (Phases 1–3) | All public static — no login gates |
| WordPress admin | Do not link or recreate |
| French | Copy `/fr/` as-is; EN-only pages stay EN-only |
| Images | Use every scraped image |
| SEO | Not required |
| Git | **CentralProject** — `sites/fcsa/` |
| DNS cutover | **Out of scope** |
| **Contact / apply / become-a-member** | **Static text only** — copy address, phone, instructions from WordPress; **no** `mailto:` links, **no** forms |
| **Visual style** | **Clean modern layout** — new simple responsive CSS; FCSA logos/colors from WordPress assets |

---

## URL path strategy (simplified)

No need to preserve WordPress slugs on disk (DNS not pointing here). Build a **short, readable tree**; record old URLs in `fcsa-url-map.csv` for reference only.

**English (examples):**

| WordPress (source) | New path |
|--------------------|----------|
| `/` (home) | `/index.html` |
| `/about/`, `/about/corporate-profile/`, etc. | `/about/index.html`, `/about/mandate.html`, … (one file per page, shallow names) |
| `/governance/` + sub-pages | `/governance/index.html`, `/governance/officers.html`, … |
| `/resources/` | `/resources/index.html` |
| `/contact-us/` | `/contact/index.html` |
| `/become-a-member/` | `/members/join.html` |
| `/apply/` | `/members/apply.html` |
| `/events/` | `/events/index.html` |
| `/privacy-policy/` | `/privacy.html` |

**French:** keep `/fr/` prefix — e.g. `/fr/index.html`, `/fr/about/index.html`, `/fr/contact/index.html` (simplified slugs, not WordPress French slugs like `a-propos-de-lapcf` unless you prefer matching FR URLs).

**Rules:**

- Lowercase, hyphenated filenames; section folders with `index.html` where it helps navigation.
- Internal links use **relative paths** only (portable on IP).
- PDFs under `/assets/documents/`; images under `/assets/images/`.
- No `.php`, no trailing-slash dependency required (IIS default documents: `index.html`).

---

## Contact, apply, and become-a-member (static text)

Extract body copy from WordPress (`contact-us`, `apply`, `become-a-member`). Publish as normal HTML pages with:

- Organization name, mailing address, phone, fax (if present on WP)
- Plain-text instructions (e.g. how to apply for membership)
- **No** `<form>`, **no** `mailto:` links, **no** WordPress POST endpoints

If WordPress had a map image (`FCSA-Map.png`), keep it on `/contact/index.html` from `/assets/images/`.

---

## Pages to exclude (WordPress auth / member portal)

Do **not** extract, build, or link to these WordPress routes — authentication moves to **ReMICS/MICS** when the sites are merged later ([Phase 5](fcsa-mics-auth-integration.md)):

| WordPress path (examples) | Reason |
|---------------------------|--------|
| `/log-in/`, `/register/`, `/edit-profile/`, `/dashboard/`, `/no-access/` | Login / member portal UI |
| `/fr/connexion-du-membre/` | FR login |
| Nav links to “Log in” / “Member area” | Point nowhere on static site (omit from header) |

**Include** public marketing pages only: about, governance, resources, contact, join/apply (static text), events, privacy, equipment lists, etc. If `members-list` on WordPress is a **public** org listing (not a gated directory), include it; if it requires login on WP, skip it.

---

## IIS hosting

### New site: `fcsa` + pool `fcsaapp`

| Setting | Value |
|---------|-------|
| Site name | `fcsa` |
| Physical path | `D:\inetpub\fcsa\` |
| App pool | `fcsaapp` — **clone `remicsdevapp` settings** (see below), **Started** |
| Binding | `http/*:80:` — **no hostname** (IP default) |
| Protocol | **HTTP only** |

### App pool `fcsaapp` — align with `remicsdevapp`

Create **`fcsaapp` as its own pool** (not shared with `remicsdevapp`). Clone operational settings from `remicsdevapp` for consistency:

| Setting | `remicsdevapp` | `fcsaapp` (planned) |
|---------|----------------|---------------------|
| `managedRuntimeVersion` | v4.0 | **v4.0** (same) |
| `managedPipelineMode` | Classic | **Classic** (same) |
| `autoStart` | true | **true** |
| Recycling / failure / CPU | defaults | **Copy from remicsdevapp** |
| **Identity** | `cloudmicsdev\IISReMicsSer` | **`ApplicationPoolIdentity`** — **do not copy** |

Static HTML does not need `IISReMicsSer` batch privileges. Match runtime and pipeline only.

**Create pattern (Phase 3):**

```powershell
# Clone pool config, then set identity
appcmd add apppool /name:fcsaapp /managedRuntimeVersion:v4.0 /managedPipelineMode:Classic
appcmd set apppool fcsaapp /processModel.identityType:ApplicationPoolIdentity
appcmd set apppool fcsaapp -attribute.autoStart:true
```

Grant **`IIS AppPool\fcsaapp`** → **Read** on `D:\inetpub\fcsa\`.

**When a dedicated domain account is needed later:** Phase 5 MICS on `fcsamicsapp` only — not for static `fcsaapp`.

### Default Web Site handling

When deploying FCSA (Phase 3):

1. **Stop `Default Web Site`** entirely.
2. **Remove** its `http/*:80:` binding so only `fcsa` owns IP:80 default.
3. Leave `DefaultAppPool` stopped (unchanged).

Avoids two sites competing for bare-IP traffic and removes IIS welcome-page confusion.

Do **not** share `remicsdevapp` with FCSA.

### Hostname sites unchanged

| Site | Binding | Unaffected |
|------|---------|------------|
| `remicsdev` | `*:80:remicsdev.cloudmicsdev.ca` | Yes |
| `remicstest` | `*:80:remicstest.cloudmicsdev.ca` | Yes |
| `REMICS` | `*:8080:` | Yes |

---

## Implementation phases

### Phase 1 — Inventory and extraction

- Export pages from `wp-json/wp/v2/pages` (EN + FR) **excluding auth/member-portal slugs** (see table above).
- Mirror remaining public URLs; download media + PDFs.
- Produce `sites/fcsa/docs/fcsa-url-map.csv` and `assets-manifest.csv`.

### Phase 2 — Static site build

- **Clean modern layout** — new responsive CSS (not Divi); reuse FCSA logos and brand colors from scraped assets.
- Shared header/nav/footer; FR under `/fr/` with simplified paths.
- All manifest images; strip WP admin/login/ads; **no login/register links in nav**.
- **Contact, apply, become-a-member:** static text at `/contact/`, `/members/apply.html`, `/members/join.html`.

### Phase 3 — IIS deploy (HTTP, IP default)

- Create `fcsaapp` pool and `fcsa` site at `D:\inetpub\fcsa\`.
- **Stop `Default Web Site`**; remove its `*:80:` binding.
- Bind `fcsa` to `http/*:80:`; deploy built files.
- Verify: `http://35.182.140.161/` serves FCSA home; `http://remicsdev.cloudmicsdev.ca/mics/` still works.

### Phase 4 — QA (local review)

- **Reviewer:** project owner (self-review).
- **Test from:** EC2 server itself (`http://localhost/`, `http://127.0.0.1/`, or `http://35.182.140.161/`).
- Link check EN + FR; image/PDF manifest; spot-check contact/join/apply static text.
- Confirm no runtime `fcsa.ca/wp-*` dependencies.
- **External testers / wider audience** — out of scope; see [TODO](../TODO.md).

### Phase 5 — MICS integration (deferred)

See [fcsa-mics-auth-integration.md](fcsa-mics-auth-integration.md). Requires hostname `fcsa.ca` + DNS eventually — not part of Phases 1–4.

---

## Proposed repo layout

```
CentralProject/
  sites/fcsa/
    src/                    # HTML/CSS (deployed to D:\inetpub\fcsa\)
    assets/                 # images, PDFs
    scripts/
      Export-FcsaWordPress.ps1
      Normalize-FcsaHtml.ps1
    docs/
      fcsa-url-map.csv
      assets-manifest.csv
  docs/fcsa/                 # this documentation
```

---

## Starting requirements (go checklist)

Before Phase 1 implementation:

| # | Requirement | Status |
|---|-------------|--------|
| 1 | **Content source** — public WordPress scrape (no WP admin) | Known OK |
| 2 | **Git repo** — CentralProject, branch workflow as usual | Confirmed |
| 3 | **HTTP only** — no cert work in this plan | Confirmed |
| 4 | **DNS** — no `fcsa.ca` changes; WordPress stays public | Confirmed |
| 5 | **IP default** — FCSA owns `*:80:`; Default Web Site displaced | Planned (Phase 3) |
| 6 | **Server IP** — `35.182.140.161` verified for smoke tests | Verified 2026-07-09 |
| 7 | **Contact / apply / join** — static text only (no `mailto:`) | **Confirmed** |
| 8 | **URL paths** — simplified shallow paths + `fcsa-url-map.csv` | **Confirmed** |
| 9 | **Reviewer** — self; test locally on EC2 | **Confirmed** |
| 10 | **Visual style** — clean modern CSS | **Confirmed** |
| 11 | **Default Web Site** — stop site + remove `:80` binding | **Confirmed** |
| 12 | **Auth pages** — omit; ReMICS/MICS later | **Confirmed** |

**All starting requirements confirmed.** Ready for Phase 1 implementation.

---

## Success criteria

- `http://<server-ip>/` serves static FCSA content (EN + FR where extracted).
- All manifest images present; no WordPress runtime dependencies.
- `remicsdev` / `remicstest` host-header sites still work.
- WordPress at `https://fcsa.ca` unchanged.
- Dedicated `fcsaapp`; MICS pools unaffected.

---

## Related

- [FCSA doc index](README.md)
- [TODO](../TODO.md) — SSL and DNS deferred items
- [Infrastructure mapping](../remicsdev/infrastructure-mapping.md)
