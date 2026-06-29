# Email to Bill — remicsdev fixes (line-by-line edit guide)

**Date:** 29 June 2026  
**Environment:** remicsdev IIS (`D:\inetpub\remicsdev\mics`, batch `D:\develbat\`)  
**Purpose:** Bill has the same files on his copy of the server. This document lists **every source change** with **find / replace** instructions, line context, and **why**. No access to our repo is required.

**After editing source:** rebuild and copy binaries as listed in §7.  
**SQL Server:** no changes in this work.

---

**Suggested email subject:** remicsdev — line-by-line edit guide (login, import, ftPrint, 29 Jun 2026)

---

Bill,

We fixed remicsdev login, batch job spawning (error 1314), TS export truncation, and import warning popups. Below is everything we changed in source, in file order, so you can apply the same edits on your copy.

There is also **server configuration** (GPO already in place; **local security policy** on each IIS box) in §1.

---

## 1. Server configuration (not source code)

### 1A. Domain GPO (you already created this)

**GPO name:** MICS IIS Server Rights  
**Linked at:** `cloudmicsdev.ca`  
**Computer Configuration → Policies → Windows Settings → Security Settings → Local Policies → User Rights Assignment**

Add **`cloudmicsdev\IISReMicsSer`** to these three policies:

1. Impersonate a client after authentication  
2. Replace a process level token  
3. Adjust memory quotas for a process  

Then on **each IIS server** that hosts remicsdev:

```text
gpupdate /force
iisreset
```

**Why:** Web batch jobs use `CreateProcessAsUser` under the app pool account. Without these privileges, `web.dblogger` shows `ERROR:CreateProcessAsUser: 1314` and `ftImport` never runs.

---

### 1B. Domain Users logon rights on each IIS server (required for login)

**Why:** MICS calls `LogonUser` after AD Membership succeeds. Domain users need permission to obtain an **interactive** or **batch** token on the IIS machine. Without this, Win32 error **1385** occurs (login page shows remediation text; previously looked like “session timed out”).

**Do not change SQL Server. Do not use NETWORK (3) logon** — SQL sees `NT AUTHORITY\ANONYMOUS LOGON` at `TloginValidate`.

#### Permanent fix (recommended) — add to **MICS IIS Server Rights** GPO

In GPMC → **MICS IIS Server Rights** → Computer Configuration → Windows Settings → Security Settings → **User Rights Assignment**:

| Setting | Add |
|---------|-----|
| Allow log on locally | `CLOUDMICSDEV\Domain Users` |
| Log on as a batch job | `CLOUDMICSDEV\Domain Users` |

Prefer **security filtering** or an **IIS-servers OU link** so this GPO does not apply domain-wide to every computer.

Then on each IIS server: `gpupdate /force` and recycle the app pool or `iisreset`.

**Why GPO, not local policy only:** On 2026-06-29, `gpupdate /force` at ~16:10 **removed** Domain Users from local logon rights that had been added via `secedit`; login broke again until `secedit` was re-applied. GPO is the durable fix.

#### Temporary workaround — local `secedit` (until GPO is updated)

On each IIS server:

1. Export current user rights:

```text
secedit /export /cfg C:\Temp\localsec_export.inf /areas USER_RIGHTS
```

2. Edit `C:\Temp\localsec_export.inf`. On these two lines, **append** the Domain Users SID for your domain (ours is `*S-1-5-21-1195307379-3143033687-510536770-513` for `CLOUDMICSDEV\Domain Users` — resolve on your box with: `(New-Object System.Security.Principal.NTAccount("CLOUDMICSDEV\Domain Users")).Translate([System.Security.Principal.SecurityIdentifier]).Value`):

**Line `SeInteractiveLogonRight`** — add `,*S-1-5-21-1195307379-3143033687-510536770-513` at end (use your SID).

**Line `SeBatchLogonRight`** — add the same SID at end.

3. Apply:

```text
secedit /configure /db C:\Temp\secedit.sdb /cfg C:\Temp\localsec_export.inf /areas USER_RIGHTS
```

4. No reboot required; recycle app pool or `iisreset`.

**Scope:** Local policy only — **overwritten on the next domain `gpupdate`**. Use until the GPO change above is deployed.

---

## 2. Web login — `D:\inetpub\remicsdev\mics\Tlogin.aspx.cs`

**Rebuild into:** `D:\inetpub\remicsdev\mics\bin\mics.dll` (see §7)

### Change 2A — LogonUser: INTERACTIVE then BATCH, with logging (in `Login1_LoginPassed`)

**Why:**

- **INTERACTIVE (2)** or **BATCH (4)** tokens work with ODBC `Trusted_Connection=yes` to SQL.
- **NETWORK (3)** must **not** be used — SQL sees `NT AUTHORITY\ANONYMOUS LOGON` and login stops at `TloginValidate` with a blank page.
- Logging Win32 errors to `D:\perflogs\goodwinlogin.txt` replaces the misleading “session timed out” when `LogonUser` fails after AD password OK.

**Find** (original pattern — single INTERACTIVE call, generic failure):

```csharp
            // log user into windows
            const int LOGON32_LOGON_INTERACTIVE = 2;
            const int LOGON32_PROVIDER_WINNT50 = 3;
            IntPtr token = IntPtr.Zero;
```

… through the block that ends with:

```csharp
            bool isSuccess = false;
            try
            {
                isSuccess = LogonUser(sUserName, sDomain, sloginPwd,
                    LOGON32_LOGON_INTERACTIVE, LOGON32_PROVIDER_WINNT50, ref token);
            }
            catch(Exception ex)
            {
                swg.WriteLine("LogonUser failed: " + ex.Message);
                swg.Close();
                return;
            }


            if (!isSuccess)
            {
                swg.WriteLine("LogonUser failed - invalid info");
                swg.Close();
                return;
                //RaiseLastError();
            }
            else
            {
                swg.WriteLine("LogonUser succeeded - winuser = " + Login1.UserName + ":" + Application["AD_Domain"].ToString());
```

**Replace with:**

```csharp
            // log user into windows — INTERACTIVE/BATCH required for ODBC Trusted_Connection; do not use NETWORK (SQL sees ANONYMOUS LOGON).
            const int LOGON32_LOGON_INTERACTIVE = 2;
            const int LOGON32_LOGON_BATCH = 4;
            const int LOGON32_PROVIDER_WINNT50 = 3;
            IntPtr token = IntPtr.Zero;
```

(Keep existing code between the const block and `string sUserName = Login1.UserName;` unchanged — LDAP / commented Andrews block / `sUserName` setup.)

Then replace the `bool isSuccess` through start of `else` success block with:

```csharp
            bool isSuccess = false;
            int logonTypeUsed = LOGON32_LOGON_INTERACTIVE;
            try
            {
                // INTERACTIVE (2) is required for ODBC Trusted_Connection to SQL as the domain user.
                // NETWORK (3) obtains a token but SQL sees NT AUTHORITY\ANONYMOUS LOGON.
                isSuccess = LogonUser(sUserName, sDomain, sloginPwd,
                    LOGON32_LOGON_INTERACTIVE, LOGON32_PROVIDER_WINNT50, ref token);
                if (!isSuccess)
                {
                    int interactiveErr = Marshal.GetLastWin32Error();
                    swg.WriteLine("LogonUser INTERACTIVE failed - Win32 error: " + interactiveErr + " (" + DescribeLogonUserError(interactiveErr) + ")");
                    swg.Flush();
                    logonTypeUsed = LOGON32_LOGON_BATCH;
                    isSuccess = LogonUser(sUserName, sDomain, sloginPwd,
                        LOGON32_LOGON_BATCH, LOGON32_PROVIDER_WINNT50, ref token);
                }
            }
            catch(Exception ex)
            {
                swg.WriteLine("LogonUser failed: " + ex.Message);
                swg.Close();
                return;
            }


            if (!isSuccess)
            {
                int win32Err = Marshal.GetLastWin32Error();
                string errDesc = DescribeLogonUserError(win32Err);
                swg.WriteLine("LogonUser failed - Win32 error: " + win32Err + " (" + errDesc + ")");
                swg.WriteLine("LogonType last tried: " + logonTypeUsed + " (2=INTERACTIVE, 4=BATCH), Provider: LOGON32_PROVIDER_WINNT50 (3)");
                swg.WriteLine("Machine: " + Environment.MachineName);
                swg.Close();

                // Forms auth already succeeded; without principalw the next page hits relogin ("session timed out").
                FormsAuthentication.SignOut();
                Session.Abandon();
                Response.Redirect("Tlogin.aspx?winlogon=" + win32Err, true);
                return;
            }
            else
            {
                swg.WriteLine("LogonUser succeeded - winuser = " + Login1.UserName + ":" + Application["AD_Domain"].ToString());
                swg.WriteLine("LogonType: " + logonTypeUsed + " (2=INTERACTIVE, 4=BATCH)");
```

(Keep remainder of `else` block — `Session.Add("principalw", …)` etc. — unchanged.)

---

### Change 2B — New helper method `DescribeLogonUserError`

**Why:** Maps Win32 codes to readable text on login page and in `goodwinlogin.txt`.

**Insert** immediately **before** `protected void Login1_LoginError`:

```csharp
        private static string DescribeLogonUserError(int win32Err)
        {
            switch (win32Err)
            {
                case 1326: return "ERROR_LOGON_FAILURE (bad password or unknown user for this logon type)";
                case 1327: return "ERROR_ACCOUNT_RESTRICTION (policy restriction, e.g. logon hours)";
                case 1328: return "ERROR_INVALID_LOGON_HOURS";
                case 1330: return "ERROR_NOT_PRIMARY";
                case 1331: return "ERROR_INVALID_WORKSTATION (user not allowed on this computer — check AD Log On To)";
                case 1907: return "ERROR_PASSWORD_EXPIRED";
                case 1909: return "ERROR_ACCOUNT_LOCKED_OUT";
                case 1385: return "ERROR_LOGON_TYPE_NOT_GRANTED (grant Domain Users Allow log on locally and Log on as a batch job on this IIS server via GPO — do not use NETWORK logon)";
                default: return "see Win32 error code documentation";
            }
        }

```

---

### Change 2C — Show Win32 error on login page when redirected

**Why:** User sees a clear message instead of recycling through “session timed out.”

**In** `protected void Page_Load`, inside `if (!IsPostBack)`, **insert as first lines** in that block (before the existing `try` that sets `lab1.Text`):

```csharp
                if (Request.QueryString["winlogon"] != null)
                {
                    int errCode;
                    if (int.TryParse(Request.QueryString["winlogon"], out errCode))
                    {
                        LoginErrorDetails.Text = "Windows logon failed on this server (error " + errCode + ": " +
                            DescribeLogonUserError(errCode) + "). AD password check passed but the IIS server could not obtain a Windows token.";
                        if (errCode == 1385)
                        {
                            LoginErrorDetails.Text += " Local secedit fixes are temporary — gpupdate removes them. Add Domain Users to those rights in MICS IIS Server Rights (or an IIS-OU GPO).";
                        }
                    }
                }

```

---

## 3. Login validate — `D:\inetpub\remicsdev\mics\TloginValidate.aspx.cs`

**Rebuild into:** `mics.dll` (same project as Tlogin)

### Change 3A — Show SQL errors instead of blank page

**Why:** When ODBC fails (e.g. during logon token issues), the catch block only wrote to `_conn.txt` and returned — user saw an empty validate page.

**Find** (commented-out error labels):

```csharp
            catch (Exception ex)
            {   // if login fails with error 28000 try resetting user's password in Active Directory
                //ErrorLabel1.Text = "Error opening database - Please contact FCSA";
                // ex.Message string repeats the message - this code retrieves the second copy from string 
                //int errindex = ex.Message.IndexOf("ERROR", 5); // start search after first 'ERROR' - this will find second
                //string errdisp = ex.Message.Substring(errindex);
                //ErrorLabel2.Text = "System error is: " + errdisp;
                sw3.WriteLine("Database connection failed: " + ex.Message); sw3.Close();
                return;
            }
```

**Replace with:**

```csharp
            catch (Exception ex)
            {   // if login fails with error 28000 try resetting user's password in Active Directory
                ErrorLabel1.Text = "Error opening database - Please contact FCSA";
                ErrorLabel1.Visible = true;
                int errindex = ex.Message.IndexOf("ERROR", 5);
                if (errindex >= 0)
                {
                    ErrorLabel2.Text = "System error is: " + ex.Message.Substring(errindex);
                }
                else
                {
                    ErrorLabel2.Text = "System error is: " + ex.Message;
                }
                ErrorLabel2.Visible = true;
                sw3.WriteLine("Database connection failed: " + ex.Message); sw3.Close();
                return;
            }
```

---

## 4. TS export truncate fix — `D:\MicsBatchProgs\MicsBat\FtPrint\FtPrint.cs`

**Rebuild into:** `D:\develbat\ftPrint.exe` (Release | x64 — see §7)

### Change 4A — Flush and close output file before exit

**Why:** `-o` output uses `File.CreateText()` (1024-byte buffer). `mTW.Close()` was commented out, so exports were **truncated at ~1024 bytes** (import then failed mid-line). `ftPrint` still returned exit 0.

**Find** (in `Main`, just before `BiUtil.BiBillingRec(Constant.BI_END, "")`):

```csharp
                // Prepare to exit normally.

               // if (mTW != Console.Out) mTW.Close();  // Just being extra cautious.

                BiUtil.BiBillingRec(Constant.BI_END, "");
```

**Replace with:**

```csharp
                // Prepare to exit normally.

                if (mTW != null && mTW != Console.Out)
                {
                    mTW.Flush();
                    mTW.Close();
                }

                BiUtil.BiBillingRec(Constant.BI_END, "");
```

**Verify after deploy:** export a TS file (e.g. `cat`); file size should be **> 1024 bytes** for a two-site link (~1300 bytes for our test case).

---

## 5. Import warnings — `D:\inetpub\remicsdev\mics\Tfileactions\TwsTabUtil.asmx.cs`

**Rebuild into:** `D:\inetpub\remicsdev\mics\bin\Tfileactions.dll` (see §7)

### Change 5A — Log warnings; do not return warning filename to browser

**Why:** Successful imports with non-fatal warnings wrote `{name}.txt` and the UI showed **alert + popup**. Warnings are now archived under `D:\MicsWebLogs\imports\` and the user returns to the tree silently. **Hard errors** (`case -1`) unchanged.

**Find** (in `importTable`, `switch (oLog.logreturncode)`):

```csharp
                        case 0:  // no errors (or TS with possible warnings)
                            if (filetype == "TS")
                            {
                                // check if .txt file has any content - if so these are warnings and must be displayed
                                if (File.Exists(Session["user_dir"].ToString() + filename + ".txt"))
                                {
                                    FileInfo fi = new FileInfo(Session["user_dir"].ToString() + filename + ".txt");
                                    if (fi.Length > 0)
                                    {
                                        return "IMPORTOK:" + filename + ".txt";
                                    }
                                }
                            }
                            return "IMPORTOK:";
                        case 1: // warnings only (unlikely - this is holdover from earlier versions of tsImport and esImport)
                            return "IMPORTOK:" + filename + ".txt";
```

**Replace with:**

```csharp
                        case 0:  // no errors (or TS/ES with possible warnings — logged, not shown to user)
                            if (filetype == "TS" || filetype == "ES")
                            {
                                string warnFile = Session["user_dir"].ToString() + filename + ".txt";
                                if (File.Exists(warnFile))
                                {
                                    FileInfo fi = new FileInfo(warnFile);
                                    if (fi.Length > 0)
                                    {
                                        LogImportWarnings(filename, filetype, warnFile, projectCode);
                                    }
                                }
                            }
                            return "IMPORTOK:";
                        case 1: // warnings only (legacy tsImport / esImport exit code)
                            {
                                string warnFile = Session["user_dir"].ToString() + filename + ".txt";
                                if (File.Exists(warnFile))
                                {
                                    LogImportWarnings(filename, filetype, warnFile, projectCode);
                                }
                            }
                            return "IMPORTOK:";
```

---

### Change 5B — New method `LogImportWarnings` (end of class, before closing `}`)

**Why:** Copies warning stdout to a durable log; appends index line for search.

**Insert** before the final `    }` closing the `TwsTabUtil` class (after the last method, e.g. after `SqlFlat`):

```csharp
        /// <summary>
        /// Archive ftImport/feImport warning stdout to MicsWebLogs; user is not prompted (see import.aspx).
        /// </summary>
        private void LogImportWarnings(string filename, string filetype, string warnFilePath, string projectCode)
        {
            try
            {
                string webDrive = Application["web_drive"].ToString();
                string user = Session["s_user"].ToString();
                string schema = Session["s_schema"].ToString();
                string sess = Session["FCSASESS"] != null ? Session["FCSASESS"].ToString() : "0";
                string stamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
                string logDir = webDrive + "\\MicsWebLogs\\imports\\" + schema + "\\" + user;
                if (!Directory.Exists(logDir))
                {
                    Directory.CreateDirectory(logDir);
                }
                string archiveName = filename + "_" + stamp + "_" + sess + ".txt";
                string archivePath = Path.Combine(logDir, archiveName);
                File.Copy(warnFilePath, archivePath, true);

                string indexLog = webDrive + "\\MicsWebLogs\\imports\\import_warnings.log";
                string summary = DateTime.Now.ToString("yyyy/MM/dd HH:mm:ss")
                    + "\tuser=" + user
                    + "\tschema=" + schema
                    + "\tfile=" + filename
                    + "\ttype=" + filetype
                    + "\tproject=" + projectCode
                    + "\tsession=" + sess
                    + "\tarchive=" + archivePath
                    + Environment.NewLine;
                File.AppendAllText(indexLog, summary);
            }
            catch (Exception ex)
            {
                ErrorUtils.NotifySystemOps(ex, "LogImportWarnings");
            }
        }
```

**Log locations after change:**

- Index: `D:\MicsWebLogs\imports\import_warnings.log`
- Archive: `D:\MicsWebLogs\imports\{schema}\{user}\{filename}_{timestamp}_{FCSASESS}.txt`

---

## 6. Import UI — `D:\inetpub\remicsdev\mics\Tfileactions\import.aspx`

**No DLL rebuild** — static `.aspx` / JavaScript; copy file or edit in place, then recycle app pool.

### Change 6A — Remove warning alert and popup on successful import

**Why:** Matches server change 5A — successful import always returns `IMPORTOK:` with no filename.

**Find** in function `importTableSuccess`:

```javascript
                else  // import was successful, but possibly with warnings
                {
                    parent.txtName = document.frmRight.txtMicsFile.value;
                    var msgparts = dispfile.split(":");
                    if (msgparts[1] != "") // not "" implies a file name was provided for display
                    {
                        alert("File imported with warnings");
                        url = "../userdirs/" + document.frmRight.sesUID.value + "/" + document.frmRight.sesMID.value + "/" + msgparts[1];
                        window.open(url, "WndImport", "toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,status=yes");
                        cleanfile = msgparts[1];
                        m3.style.display = "";
                    }
                    else {
                        alert("File imported");
                        goBack();
                    }
                }
```

**Replace with:**

```javascript
                else  // import was successful (warnings, if any, logged server-side — see MicsWebLogs\imports)
                {
                    parent.txtName = document.frmRight.txtMicsFile.value;
                    goBack();
                }
```

**Note:** Failed imports (`dispfile` does not start with `IMPORTOK`) still alert and open the error `.txt` — unchanged.

---

## 7. Build and deploy (after source edits)

### 7A. Web — `mics.dll` (Tlogin + TloginValidate)

From a machine with MSBuild and web application targets:

```text
MSBuild D:\inetpub\remicsdev\mics\mics.csproj /p:Configuration=Release /t:Build
```

Output: `D:\inetpub\remicsdev\mics\bin\mics.dll`

### 7B. Web — `Tfileactions.dll`

```text
MSBuild D:\inetpub\remicsdev\mics\Tfileactions\Tfileactions.csproj /p:Configuration=Release /t:Build
```

Output: `D:\inetpub\remicsdev\mics\bin\Tfileactions.dll`

### 7C. Batch — `ftPrint.exe`

```text
MSBuild D:\MicsBatchProgs\MicsBat\FtPrint\FtPrint.csproj /p:Configuration=Release /p:Platform=x64 /t:Build
```

Output: `D:\develbat\ftPrint.exe`

### 7D. Recycle

```text
iisreset
```

(or restart app pool `remicsdevapp` only)

---

## 8. Verification checklist

| Test | Expected |
|------|----------|
| Login as rctl1 | Main navigation loads |
| `D:\perflogs\goodwinlogin.txt` | `LogonUser succeeded` … `LogonType: 2` or `4` |
| Export TS file `cat` | `cat.txt` size **> 1024** bytes |
| Import exported file under new name | Success; return to tree; no warning popup |
| Import with warnings | No popup; line in `D:\MicsWebLogs\imports\import_warnings.log` |
| `web.dblogger` latest ftImport | `CreateProcessAsUser` success; not 1314 |
| Failed import (bad file) | Still alerts and opens error `.txt` |

---

## 9. Files **not** changed

- SQL Server / databases  
- `ftImport.exe` (only `ftPrint.exe` in batch)  
- `JobSubmit.cs`  
- `import.aspx.cs` (code-behind)  
- `web.config`  

---

## 10. Summary for Bill

| Problem | Fix location |
|---------|----------------|
| Batch 1314 | GPO on `IISReMicsSer` (§1A) |
| Login / “session timed out” | Local logon rights (§1B) + `Tlogin.aspx.cs` (§2) |
| Blank page after login | `TloginValidate.aspx.cs` (§3) |
| Export truncated at 1024 bytes | `FtPrint.cs` (§4) |
| Import warning popups | `TwsTabUtil.asmx.cs` + `import.aspx` (§5–6) |

If anything does not match your line numbers, search for the **Find** strings above — they are unique in each file.

Regards,  
[Your name]
