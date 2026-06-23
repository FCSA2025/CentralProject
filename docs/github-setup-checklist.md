# Git + GitHub setup checklist (lessons learned)

**Status:** Complete (2026-06-23)  
**Applies to:** Any CentralProject hub repo on a **new machine** (Windows or macOS)  
**Case study:** [FCSA2025/CentralProject](https://github.com/FCSA2025/CentralProject) on Windows Server 2022

This doc captures what went wrong pushing CentralProject to GitHub, what we should have checked **first**, and a copy-paste checklist for the next project or machine.

---

## Executive summary

| What we assumed | What was true |
|-----------------|---------------|
| PAT in `.env.local` = git auth | Git **defaults to OS credential store**, not project files |
| Public repo = anyone can push | Public = **read** for everyone; **write** still needs auth |
| Fine-grained token with “max permissions” = push works | Token may lack **org approval**, **SSO authorize**, or **Contents write** on that repo |
| Chrome logged in = git uses that session | Git **does not** read Chrome; it uses **Credential Manager / Keychain** or a fresh OAuth flow |
| Wrong account would be in our files | Wrong account was in **Windows Credential Manager** (`JasonFCSAScott`), not in the repo |

**What fixed it:** Remove stale GitHub entry from Credential Manager → one successful `git push` → correct account stored.

---

## Could we have seen this coming?

**Yes — with a 5-minute pre-flight.** These are the red flags we skipped:

### Before first push (run on the new machine)

```powershell
# 1. Who will git authenticate as? (Windows)
cmdkey /list | findstr /i github

# 2. Git identity (commit author — NOT push auth)
git config --global user.name
git config --global user.email

# 3. Credential helper
git config --show-origin credential.helper

# 4. GCM browser mode (Windows — avoid embedded IE)
git config --global credential.msauthFlow
# Should be: system

# 5. Can we reach the remote?
git ls-remote https://github.com/ORG/REPO.git HEAD

# 6. Dry-run push auth (after remote added)
# Expect: either success, or "denied to WRONG_USER" → fix creds before debugging PATs
```

| If you see… | Likely problem |
|-------------|----------------|
| `cmdkey` shows **wrong GitHub username** | Push will fail until entry is removed |
| Push denied to **user A**, `.env.local` has **user B** | Git ignored `.env.local`; used Credential Manager |
| API `push=True` but write returns **403** | Fine-grained PAT not approved for org / missing Contents write / SSO |
| `Resource not accessible by personal access token` | Wrong token type, wrong resource owner, or org policy |
| `JasonFCSAScott` (or any old account) in Credential Manager | Legacy Explorer/IE login on that server |

**Rule:** Check **Credential Manager / Keychain before creating or debugging PATs.**

---

## Where credentials actually live (not in the repo)

| Store | Path / access | Used when |
|-------|---------------|-----------|
| **Windows Credential Manager** | `Win+R` → `control /name Microsoft.CredentialManager` | Default `git push` on Windows (`credential.helper=manager`) |
| **Git Credential Manager (GCM)** | `%ProgramFiles%\Git\mingw64\bin\git-credential-manager.exe` | OAuth browser flow, stores into Credential Manager |
| **`.env.local`** (gitignored) | Project root | **Only if we manually inject PAT** — not default git behavior |
| **Chrome saved passwords** | Chrome profile | **Never** used by git directly |
| **macOS Keychain** | Keychain Access → search `github.com` | Default on Mac (same role as Credential Manager) |

Project files correctly had **`JasonConradScott`** in `.env.local`. Git used **`JasonFCSAScott`** from Credential Manager until we removed it.

---

## Windows Server setup (this machine)

### 1. Default browser

On Server, **Settings → Default apps** may be missing. Use:

```
Win+R → control /name Microsoft.DefaultPrograms
→ Set your default programs → Google Chrome → Set this program as default
```

Or:

```
Win+R → control /name Microsoft.CredentialManager
```

### 2. Cursor / VS Code — external browser

In `%APPDATA%\Cursor\User\settings.json`:

```json
"workbench.externalBrowser": "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"
```

Cursor also: **Settings → Tools & MCP → Browser Automation → Google Chrome**.

Reload window after change.

### 3. Git — force system browser (not embedded IE)

```powershell
git config --global credential.msauthFlow system
```

Embedded WebView on Windows Server often used **IE** and logged into the **wrong GitHub account**.

### 4. Credential Manager — remove stale GitHub entries

```
Control Panel → User Accounts → Credential Manager → Windows Credentials
```

Delete any **`GitHub - https://api.github.com/...`** for the **wrong** account.

CLI list:

```powershell
cmdkey /list
```

GCM account management:

```powershell
& "C:\Program Files\Git\mingw64\bin\git-credential-manager.exe" github list
& "C:\Program Files\Git\mingw64\bin\git-credential-manager.exe" github logout OLD_ACCOUNT
```

### 5. First push

```powershell
cd E:\path\to\project
git init
git remote add origin https://github.com/FCSA2025/REPO.git
git add -A
git commit -m "Initial commit"
git push -u origin main
```

**Interactive:** User may need to complete browser OAuth once. **Agent/non-interactive** push only works **after** correct creds are stored.

### 6. Verify on GitHub

```powershell
git status -sb          # should show: main...origin/main
git log --oneline -3
```

Browser: `https://github.com/ORG/REPO` — files and commits visible.

---

## macOS setup (next machine — adapt checklist)

| Windows | macOS equivalent |
|---------|------------------|
| Credential Manager | **Keychain Access** → search `github.com` |
| `cmdkey /list` | Keychain or `git credential-manager github list` |
| `control /name Microsoft.CredentialManager` | Keychain Access.app |
| Chrome default | System Settings → Desktop & Dock → Default web browser |
| `credential.msauthFlow system` | Same git config (GCM is cross-platform) |

Pre-push on Mac:

```bash
git credential-manager github list
git config --global credential.msauthFlow
git ls-remote https://github.com/ORG/REPO.git HEAD
```

Remove wrong Keychain entries before first push.

---

## GitHub org repo (FCSA2025) — token pitfalls

Fine-grained PAT (`github_pat_...`) is **valid** — not “wrong format.” Failures were **permission/approval**, not prefix.

| Check | Where |
|-------|--------|
| Resource owner = **FCSA2025** | Token creation (cannot change by editing token) |
| **CentralProject** in selected repos | Token settings |
| **Contents: Read and write** | Token permissions |
| **Configure SSO → Authorize** | [github.com/settings/tokens](https://github.com/settings/tokens) |
| Org owner **approved** token | Org → Settings → Personal access tokens → Pending requests |

Classic PAT (`ghp_` + **`repo`** scope) often works when fine-grained fails on org repos — but **Credential Manager + one interactive push** was the fix here; PAT optional.

**Do not rely on PAT alone for first-time setup** on a shared/server machine until Credential Manager is verified clean.

---

## `.env.local` pattern (optional PAT storage)

| File | In git? | Purpose |
|------|---------|---------|
| `env.local.example` | Yes | Template with placeholders |
| `.env.local` | **No** (gitignored) | Local PAT / org / repo names for scripts |

`.env.local` does **not** change default `git push` unless scripts explicitly read it. It is **not** a substitute for fixing Credential Manager.

---

## New project / new machine — copy this checklist

### Phase A — Before `git init`

- [ ] Install Git + Git Credential Manager
- [ ] Set default browser to Chrome (or preferred)
- [ ] `git config --global credential.msauthFlow system`
- [ ] Cursor: `workbench.externalBrowser` → Chrome path
- [ ] **List and clear stale GitHub credentials** (Credential Manager / Keychain)
- [ ] Confirm GitHub web login in Chrome is **correct account**

### Phase B — GitHub repo

- [ ] Create empty repo on GitHub (no README if pushing existing local repo)
- [ ] Confirm org membership / repo admin for push account
- [ ] If fine-grained PAT planned: org approval + SSO authorize

### Phase C — Local repo

- [ ] `git init` → `.gitignore` includes `.env.local`, `.env.*`
- [ ] Initial commit
- [ ] `git remote add origin https://github.com/ORG/REPO.git`

### Phase D — First push (interactive)

- [ ] **User** runs first `git push -u origin main` (or Cursor Source Control → Push)
- [ ] Confirm GitHub shows commits
- [ ] `cmdkey /list` or `git credential-manager github list` shows **correct** account

### Phase E — Agent / CI can push later

- [ ] Only after Phase D succeeded on that machine
- [ ] Or: dedicated PAT/SSH with documented scopes in `.env.local` / secrets store

---

## CentralProject outcome (reference)

| Item | Value |
|------|--------|
| Remote | `https://github.com/FCSA2025/CentralProject.git` |
| Default branch | `main` |
| First successful push | 2026-06-23, after removing `JasonFCSAScott` from Credential Manager |
| Commits pushed | 2 (initial docs + `env.local.example`) |

---

## Commands reference (Windows)

```powershell
# Open Credential Manager
control /name Microsoft.CredentialManager

# List stored creds
cmdkey /list

# Git / GCM
git config --global credential.msauthFlow system
git config --global --get-regexp credential
& "C:\Program Files\Git\mingw64\bin\git-credential-manager.exe" github list

# Verify remote
git ls-remote origin HEAD
git status -sb
```

---

## Related docs

- [CentralProject README](../README.md)
- [TODO](TODO.md)
- [remicsdev infrastructure](remicsdev/infrastructure-mapping.md) — this server’s IIS/batch context

When copying to a new project, copy **this entire file** and update the **CentralProject outcome** section with the new repo URL.
