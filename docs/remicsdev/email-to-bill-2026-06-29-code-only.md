# Email to Bill — remicsdev source edits (exact line numbers)

**Subject:** remicsdev — source line edits (login, ftPrint, import warnings) — 29 Jun 2026

**Scope:** Code only. No SQL changes.

Line numbers below are from our **IIS-ReMics-Prod** tree after edits. **“Your file (before)”** is the line range on your unmodified copy; **“After edit”** is where the same logic sits on our server.

**Rebuild after edits:**

```text
MSBuild D:\inetpub\remicsdev\mics\mics.csproj /p:Configuration=Release /t:Build
MSBuild D:\inetpub\remicsdev\mics\Tfileactions\Tfileactions.csproj /p:Configuration=Release /t:Build
MSBuild D:\MicsBatchProgs\MicsBat\FtPrint\FtPrint.csproj /p:Configuration=Release /p:Platform=x64 /t:Build
Restart-WebAppPool remicsdevapp
```

---

Bill,

Below are every source change with **exact line numbers** and **old → new** code. Apply on your copy of the same paths, then rebuild as above.

---

## 1. `D:\inetpub\remicsdev\mics\Tlogin.aspx.cs` → `bin\mics.dll`

### 1A — LogonUser constants and comments

| | Lines |
|---|------|
| Your file (before) | **135–137** |
| After edit | **135–141** |

**OLD (135–137):**

```csharp
            // log user into windows
            const int LOGON32_LOGON_INTERACTIVE = 2;
            const int LOGON32_PROVIDER_WINNT50 = 3;
```

**NEW (135–141):**

```csharp
            // log user into windows — INTERACTIVE (2) then BATCH (4) for ODBC Trusted_Connection.
            // Do not use NETWORK (3): SQL sees NT AUTHORITY\ANONYMOUS LOGON at TloginValidate.
            // 1385 means Domain Users lack Allow log on locally / Log on as a batch job on this IIS server.
            const int LOGON32_LOGON_INTERACTIVE = 2;
            const int LOGON32_LOGON_BATCH = 4;
            const int LOGON32_PROVIDER_WINNT50 = 3;
```

*(Lines 142–177 unchanged — `IntPtr token`, LDAP comments, `sUserName` / `sDomain` / `sloginPwd` setup.)*

---

### 1B — LogonUser call, failure handling, success logging

| | Lines |
|---|------|
| Your file (before) | **178–210** |
| After edit | **178–246** |

**OLD (178–210):**

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
                swg.Flush();

                Session.Add("principald", (GenericPrincipal)Thread.CurrentPrincipal);
                Session.Add("principalw", new WindowsPrincipal(new WindowsIdentity(token)));
```

**NEW (178–246):**

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
                swg.Flush();

                Session.Add("principald", (GenericPrincipal)Thread.CurrentPrincipal);
                Session.Add("principalw", new WindowsPrincipal(new WindowsIdentity(token)));
```

*(Remainder of `else` — WindowsIdentity logging, `swg.Close()`, closing braces — unchanged from your file.)*

---

### 1C — New method `DescribeLogonUserError` (insert)

| | Lines |
|---|------|
| Your file (before) | **Insert before line 248** (`protected void Login1_LoginError`) |
| After edit | **249–263** |

**NEW (249–263):**

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

### 1D — Show Win32 error on login page (`Page_Load`)

| | Lines |
|---|------|
| Your file (before) | **Insert inside `if (!IsPostBack)` before the `try` that sets `lab1.Text`** (~line 411) |
| After edit | **425–437** |

**NEW (425–437):**

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

## 2. `D:\inetpub\remicsdev\mics\TloginValidate.aspx.cs` → same `mics.dll`

### 2A — ODBC open failure: show errors on screen

| | Lines |
|---|------|
| Your file (before) | **116–122** |
| After edit | **116–132** |

**OLD (116–122):**

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

**NEW (116–132):**

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

## 3. `D:\MicsBatchProgs\MicsBat\FtPrint\FtPrint.cs` → `D:\develbat\ftPrint.exe`

### 3A — Flush and close `-o` output file before exit

| | Lines |
|---|------|
| Your file (before) | **225–228** |
| After edit | **225–231** |

**OLD (225–228):**

```csharp
                // Prepare to exit normally.

               // if (mTW != Console.Out) mTW.Close();  // Just being extra cautious.

                BiUtil.BiBillingRec(Constant.BI_END, "");
```

**NEW (225–231):**

```csharp
                // Prepare to exit normally.

                if (mTW != null && mTW != Console.Out)
                {
                    mTW.Flush();
                    mTW.Close();
                }

                BiUtil.BiBillingRec(Constant.BI_END, "");
```

**Verify:** export `cat` — file must be **> 1024 bytes** (~1307 for our test case).

---

## 4. `D:\inetpub\remicsdev\mics\Tfileactions\TwsTabUtil.asmx.cs` → `bin\Tfileactions.dll`

### 4A — `importTable`: log warnings, return `IMPORTOK:` only

| | Lines |
|---|------|
| Your file (before) | **793–806** (in `switch (oLog.logreturncode)`) |
| After edit | **793–815** |

**OLD (793–806):**

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

**NEW (793–815):**

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

*(Hard errors `case -1` still `return filename + ".txt"` — unchanged.)*

---

### 4B — New method `LogImportWarnings` (insert)

| | Lines |
|---|------|
| Your file (before) | **Insert before closing `}` of class `TwsTabUtil`** (after `SqlFlat`, ~line 1812) |
| After edit | **1814–1851** |

**NEW (1814–1851):**

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

**Logs:** `D:\MicsWebLogs\imports\import_warnings.log` and `D:\MicsWebLogs\imports\{schema}\{user}\{file}_{timestamp}_{FCSASESS}.txt`

---

## 5. `D:\inetpub\remicsdev\mics\Tfileactions\import.aspx` (no DLL — recycle app pool)

### 5A — Remove warning alert/popup on successful import

| | Lines |
|---|------|
| Your file (before) | **404–418** (function `importTableSuccess`, final `else`) |
| After edit | **404–408** |

**OLD (404–418):**

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

**NEW (404–408):**

```javascript
                else  // import was successful (warnings, if any, logged server-side — see MicsWebLogs\imports)
                {
                    parent.txtName = document.frmRight.txtMicsFile.value;
                    goBack();
                }
```

---

## Files not changed

- SQL Server / databases  
- `ftImport.exe`, `JobSubmit.cs`, `import.aspx.cs`, `web.config`

---

Regards,  
[Your name]
