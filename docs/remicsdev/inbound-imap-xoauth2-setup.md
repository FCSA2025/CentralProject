# Inbound IMAP XOAUTH2 — detailed setup (first time)

This guide assumes you have **never** created an Entra app or used Exchange Online PowerShell for service principals. Follow the steps in order. Do not skip the “which Object ID” section — that is the #1 failure point.

**Goal:** Let our remicsdev script read mail from **`jscott@fcsa.ca`** over IMAP using OAuth (no password login).

**Official Microsoft doc (reference):** [Authenticate an IMAP connection using OAuth](https://learn.microsoft.com/en-us/exchange/client-developer/legacy-protocols/how-to-authenticate-an-imap-pop-smtp-application-by-using-oauth)

---

## Before you start

### Accounts / roles you need

You (or a colleague) must be able to sign in as:

| Role | Why |
|------|-----|
| **Application Administrator** or **Global Administrator** (or **Cloud Application Administrator** + ability to grant consent) | Create the Entra app, add API permission, click **Grant admin consent** |
| **Exchange Administrator** (or Global Admin) | Run `New-ServicePrincipal` and `Add-MailboxPermission` |

If your account is only a normal user, you will get stuck on admin consent or Exchange PowerShell. Ask an FCSA/M365 admin to do Part A–C with you on a call.

### What you will create (plain English)

1. An **app registration** in Microsoft Entra = “a robot identity” that can request tokens.
2. A **client secret** = “the robot’s password” (shown only once).
3. Permission **IMAP.AccessAsApp** = “this robot is allowed to use IMAP as an app.”
4. An **Exchange service principal** + **FullAccess** on `jscott@fcsa.ca` = “Exchange is allowed to let that robot open this one mailbox.”

### Scratch pad (fill as you go)

Open Notepad. You will collect **four** values:

```text
INBOUND_TENANT_ID=
INBOUND_CLIENT_ID=
INBOUND_CLIENT_SECRET=
ENTERPRISE_APP_OBJECT_ID=
```

Keep the secret private. Do **not** paste it into chat, email, or git unless you are handing it to the agent on the secure remicsdev box for the probe only.

---

## Part A — Create the Entra app registration

### A1. Open Entra admin center

1. On a PC where you can use a browser, go to:  
   **https://entra.microsoft.com**
2. Sign in with your **work** account (the one in the FCSA / M365 tenant — typically `something@fcsa.ca`).
3. If you land on a home dashboard, that is fine.

(Alternate URL that also works: **https://portal.azure.com** → search **Microsoft Entra ID** → open it.)

### A2. Open App registrations

1. In the left menu, expand **Identity** (if shown), then click **Applications**.
2. Click **App registrations**.
3. At the top, click **+ New registration**.

### A3. Fill the registration form

| Field | What to enter |
|-------|----------------|
| **Name** | `Remicsdev Inbound IMAP` |
| **Supported account types** | Select **Accounts in this organizational directory only** (single tenant). Do **not** choose “any organizational directory” or “personal Microsoft accounts”. |
| **Redirect URI** | Leave **blank**. We are not building a website login. |

Click **Register**.

### A4. Copy Tenant ID and Client ID (immediately)

You are now on the app’s **Overview** page.

1. Find **Application (client) ID** — it looks like `a1b2c3d4-....`  
   → Paste into Notepad as `INBOUND_CLIENT_ID=`
2. Find **Directory (tenant) ID** — another GUID  
   → Paste into Notepad as `INBOUND_TENANT_ID=`

**Important:** On this same Overview page there is also an **Object ID**.  
**Do not use that Object ID for Exchange.** That is the wrong one. Leave it alone for now.

Leave this browser tab open (or note the app name so you can find it again).

---

## Part B — Create a client secret

### B1. Open Certificates & secrets

1. Still inside your app (`Remicsdev Inbound IMAP`).
2. Left menu under **Manage**, click **Certificates & secrets**.
3. Select the **Client secrets** tab (not Certificates).
4. Click **+ New client secret**.

### B2. Create the secret

| Field | What to enter |
|-------|----------------|
| **Description** | `remicsdev-imap-demo` |
| **Expires** | Pick **180 days** or **24 months** (whatever your org allows). Note the expiry date in Notepad. |

Click **Add**.

### B3. Copy the secret Value NOW

A new row appears with columns **Description**, **Expires**, **Value**, **Secret ID**.

1. Click the **copy** icon next to **Value** (the long random string).  
   → Paste into Notepad as `INBOUND_CLIENT_SECRET=`
2. **Do not** copy **Secret ID** — that is not the password.
3. If you leave this page without copying **Value**, Microsoft will **never show it again**. You would have to create a new secret.

---

## Part C — Add IMAP application permission and grant admin consent

### C1. Open API permissions

1. Left menu under **Manage**, click **API permissions**.
2. You may already see `Microsoft Graph` → `User.Read` (Delegated). That is normal. Leave it.

### C2. Add Office 365 Exchange Online permission

1. Click **+ Add a permission**.
2. A panel opens: **Request API permissions**.
3. Click the tab **APIs my organization uses** (not “Microsoft APIs” first — Exchange IMAP app permission is easier to find this way).
4. In the search box, type: `Office 365 Exchange Online`
5. Click the result named exactly **Office 365 Exchange Online**.
6. Choose **Application permissions** (not Delegated permissions).  
   - Application = robot acts as itself (what we need for a scheduled job).  
   - Delegated = acts as a signed-in user (wrong for this demo job).
7. Expand or scroll the list and check **`IMAP.AccessAsApp`**.
8. Click **Add permissions** at the bottom.

You should now see a permission row like:

`Office 365 Exchange Online` · `IMAP.AccessAsApp` · Type **Application** · Status often **Not granted** (yellow).

### C3. Grant admin consent

1. Still on **API permissions**, click **Grant admin consent for \<Your Organization\>**.
2. Confirm **Yes**.
3. Status for `IMAP.AccessAsApp` should become a green check: **Granted for \<org\>**.

If the button is greyed out or fails: your account lacks admin consent rights. Stop and ask a Global Admin / Privileged Role Admin to click it.

---

## Part D — Copy the Enterprise application Object ID (the correct one)

This is the ID Exchange needs. It is **not** the Object ID on the App registration Overview.

### D1. Open Enterprise applications

1. In Entra left menu: **Identity** → **Applications** → **Enterprise applications**  
   Direct link habit: **https://entra.microsoft.com** → search top bar for **Enterprise applications**.
2. In the list filter / search box, type: `Remicsdev Inbound IMAP`
3. Click the application name to open it.

If it does not appear yet: wait 1–2 minutes, refresh, or clear the Application type filter to **All applications**. Creating an app registration usually creates the enterprise app automatically after consent.

### D2. Copy Object ID

1. On the Enterprise application **Overview** page, find **Object ID** (a GUID).
2. Paste into Notepad as `ENTERPRISE_APP_OBJECT_ID=`

### Quick check — which ID is which

| Name in Notepad | Where you got it | Used for |
|-----------------|------------------|----------|
| `INBOUND_TENANT_ID` | App registration → Overview → Directory (tenant) ID | Token URL |
| `INBOUND_CLIENT_ID` | App registration → Overview → Application (client) ID | Token + `New-ServicePrincipal -AppId` |
| `INBOUND_CLIENT_SECRET` | Certificates & secrets → **Value** | Token request |
| `ENTERPRISE_APP_OBJECT_ID` | **Enterprise applications** → Overview → Object ID | `New-ServicePrincipal -ObjectId` |

If you mix up App registration Object ID vs Enterprise Object ID, IMAP will get a token but return **`NO AUTHENTICATE`**.

---

## Part E — Enable IMAP on the mailbox (Exchange admin center)

1. Go to **https://admin.exchange.microsoft.com**
2. Sign in with an Exchange / Global admin account.
3. Left: **Recipients** → **Mailboxes**.
4. Search for `jscott` and open **jscott@fcsa.ca**.
5. Find **Manage email apps settings** / **Email apps** / **Mailbox features** (wording varies).
6. Ensure **IMAP** is **enabled** (On). Save if you changed it.

Optional: under **Mobile Device** / email apps, IMAP should not be blocked by a policy for this user.

---

## Part F — Register the app in Exchange Online (PowerShell)

This must run on a PC where you can install modules and sign in interactively (your laptop is fine). It does **not** have to run on IIS-REMICS-PROD.

### F1. Open PowerShell

1. Start **Windows PowerShell** or **PowerShell 7** as your normal user (admin elevation usually not required for `-Scope CurrentUser`).
2. Run:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser -Force
Import-Module ExchangeOnlineManagement
```

If `Install-Module` asks to install **NuGet** or trust the gallery, answer **Yes**.

### F2. Connect to Exchange Online

```powershell
Connect-ExchangeOnline
```

A browser window opens. Sign in with the **Exchange admin** account. Complete MFA if prompted. When connected, the prompt returns with no error.

(If browser auth fails, try: `Connect-ExchangeOnline -UserPrincipalName you@fcsa.ca`)

### F3. Create the Exchange service principal

Paste your real values from Notepad (replace the placeholders):

```powershell
$AppId        = 'PASTE_INBOUND_CLIENT_ID_HERE'
$SpObjectId   = 'PASTE_ENTERPRISE_APP_OBJECT_ID_HERE'

New-ServicePrincipal -AppId $AppId -ObjectId $SpObjectId -DisplayName 'Remicsdev Inbound IMAP'
```

Success: a service principal object is returned (or a short confirmation).

If you get **already exists**, that is OK — continue.

Verify:

```powershell
Get-ServicePrincipal | Where-Object { $_.AppId -eq $AppId } | Format-List
```

### F4. Grant the app FullAccess to jscott@fcsa.ca only

```powershell
$AppId = 'PASTE_INBOUND_CLIENT_ID_HERE'
$exoSp = Get-ServicePrincipal | Where-Object { $_.AppId -eq $AppId }

Add-MailboxPermission -Identity 'jscott@fcsa.ca' `
  -User $exoSp.Identity `
  -AccessRights FullAccess
```

Verify:

```powershell
Get-MailboxPermission -Identity 'jscott@fcsa.ca' |
  Where-Object { $_.User -like '*Remicsdev*' -or $_.User -eq $exoSp.Identity } |
  Format-Table Identity, User, AccessRights
```

You want a row showing **FullAccess** for this service principal.

### F5. Disconnect

```powershell
Disconnect-ExchangeOnline -Confirm:$false
```

**Wait 5–15 minutes** after F4 before testing IMAP. Permissions can take a short while to propagate.

---

## Part G — Put secrets on IIS-REMICS-PROD (for the probe)

On **IIS-REMICS-PROD**, in an elevated PowerShell if needed:

```powershell
cd E:\AIProjects\CentralProject

New-Item -ItemType Directory -Force -Path config\remicsdev | Out-Null
Copy-Item docs\remicsdev\inbound-imap.env.example config\remicsdev\.env.inbound-imap.local
notepad config\remicsdev\.env.inbound-imap.local
```

Fill the file so it looks like (example shape only):

```text
INBOUND_IMAP_HOST=outlook.office365.com
INBOUND_IMAP_PORT=993
INBOUND_IMAP_USER=jscott@fcsa.ca
INBOUND_IMAP_AUTH=xoauth2

INBOUND_TENANT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
INBOUND_CLIENT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
INBOUND_CLIENT_SECRET=your-secret-value-here

INBOUND_TOKEN_SCOPE=https://outlook.office365.com/.default
```

Save and close. This path is **gitignored** (`.env.*`).

Tell the agent the file is ready (do not paste the secret into chat if you can avoid it). Then run:

```powershell
cd E:\AIProjects\CentralProject
.\scripts\Probe-RemicsInboundImapXoauth2.ps1
```

### What success looks like

```text
Token: OK (expires_in=3599, ...)
AUTHENTICATE XOAUTH2: OK ...
SELECT INBOX: OK ...
RESULT: XOAUTH2 IMAP succeeded
```

### What common failures mean

| Symptom | Likely cause |
|---------|----------------|
| `TOKEN FAIL` / `invalid_client` | Wrong client ID or secret, or secret expired |
| `TOKEN FAIL` / `unauthorized_client` / consent | Admin consent not granted for `IMAP.AccessAsApp` |
| Token OK, then `NO AUTHENTICATE` | Wrong **Enterprise** Object ID used in `New-ServicePrincipal`, or mailbox permission missing, or still propagating |
| Token OK, `NO AUTHENTICATE` | IMAP disabled on mailbox |
| Permission not listed under “APIs my organization uses” | Wrong tab (use Application permissions on **Office 365 Exchange Online**, not Graph `Mail.Read`) |

---

## Checklist (print / tick)

- [ ] Part A — App registered; `INBOUND_TENANT_ID` + `INBOUND_CLIENT_ID` saved
- [ ] Part B — Client secret **Value** saved (not Secret ID)
- [ ] Part C — `IMAP.AccessAsApp` (Application) + **admin consent Granted**
- [ ] Part D — `ENTERPRISE_APP_OBJECT_ID` from **Enterprise applications** (not App registration Object ID)
- [ ] Part E — IMAP enabled on `jscott@fcsa.ca`
- [ ] Part F — `New-ServicePrincipal` + `Add-MailboxPermission` FullAccess
- [ ] Waited a few minutes
- [ ] Part G — `.env.inbound-imap.local` filled on IIS-REMICS-PROD
- [ ] Probe prints `RESULT: XOAUTH2 IMAP succeeded`

---

## After the probe succeeds

We continue the inbound plan: SQL tables, poller script, SQL Agent schedule. Classification stays later.
