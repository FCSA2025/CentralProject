using System;
using System.Collections;
using System.Configuration;
using System.Data.Odbc;
using System.IO;
using System.Net;
using System.Net.Mail;
using System.Security.Principal;
using System.Web;
using SqlMail;

namespace SesUtilities
{
    /// <summary>
    /// Summary description for SesUtils.
    /// </summary>
    public class SesUtils
    {
        /// <summary>
        /// When web.config DisableOutgoingEmail=true, no queue/SMTP send — log only.
        /// Re-enable for production cutover (RemIcsReWrite Phase 7).
        /// </summary>
        public static bool IsOutgoingEmailDisabled()
        {
            string v = ConfigurationManager.AppSettings["DisableOutgoingEmail"];
            return string.Equals(v, "true", StringComparison.OrdinalIgnoreCase)
                || string.Equals(v, "1", StringComparison.OrdinalIgnoreCase)
                || string.Equals(v, "yes", StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>
        /// True when the request Host is a literal IPv4/IPv6 address (not a DNS name).
        /// Used so Pref* cookies stay host-only on raw-IP URLs (Phase 5).
        /// </summary>
        public static bool IsRequestHostIp(HttpRequest request)
        {
            if (request == null || request.Url == null) return false;
            IPAddress addr;
            return IPAddress.TryParse(request.Url.Host, out addr);
        }

        /// <summary>
        /// Set cookie Domain to SiteDomain for hostname access; omit Domain for IP access (host-only).
        /// </summary>
        public static void ApplyPrefCookieDomain(HttpCookie cookie, HttpRequest request, string siteDomain)
        {
            if (cookie == null) return;
            if (IsRequestHostIp(request))
                return;
            if (!string.IsNullOrEmpty(siteDomain))
                cookie.Domain = siteDomain;
        }

        private static void LogSuppressedEmail(string source, string subject, string body, string to, string cc)
        {
            try
            {
                string user = "mics";
                try
                {
                    if (HttpContext.Current != null && HttpContext.Current.Session != null
                        && HttpContext.Current.Session["s_user"] != null)
                        user = HttpContext.Current.Session["s_user"].ToString();
                }
                catch { /* login path */ }

                string dbgfile = "D:\\extractlogs\\" + user + "EmailSuppressed.txt";
                using (var sw = new StreamWriter(dbgfile, true))
                {
                    sw.WriteLine("LOGTIME:" + DateTime.Now.ToString("yyyyMMddHHmmss.ffff"));
                    sw.WriteLine("SUPPRESSED:" + source);
                    sw.WriteLine("TO:" + (to ?? ""));
                    sw.WriteLine("CC:" + (cc ?? ""));
                    sw.WriteLine("Subject:" + (subject ?? ""));
                    sw.WriteLine("Body:" + (body ?? ""));
                    sw.WriteLine("---");
                }
            }
            catch { /* never fail callers */ }
        }

        /// <summary>When set, all queue inserts deliver to this address; original To/CC appended to body.</summary>
        public static string GetEmailRedirectAllTo()
        {
            string v = ConfigurationManager.AppSettings["EmailRedirectAllTo"];
            return string.IsNullOrWhiteSpace(v) ? null : v.Trim();
        }

        private static string EscapeSql(string value)
        {
            if (value == null) return "";
            return value.Replace("'", "''");
        }

        /// <summary>Copy attachments to local staging; queue UNC paths for SQL Agent on EC2AMAZ-9DKDM82.</summary>
        public static string StageAttachmentsForSqlAgent(string semicolonPaths)
        {
            if (string.IsNullOrWhiteSpace(semicolonPaths)) return null;

            string stageRoot = ConfigurationManager.AppSettings["EmailAttachStagingRoot"];
            if (string.IsNullOrWhiteSpace(stageRoot))
                stageRoot = @"D:\MicsEmailStaging";
            stageRoot = stageRoot.TrimEnd('\\');

            string uncRoot = ConfigurationManager.AppSettings["EmailAttachStagingUncRoot"];
            if (string.IsNullOrWhiteSpace(uncRoot))
                uncRoot = @"\\IIS-REMICS-PROD\MicsEmailStaging";
            uncRoot = uncRoot.TrimEnd('\\');

            string stageDir = Path.Combine(stageRoot, DateTime.Now.ToString("yyyyMMddHHmmss") + "_" + Guid.NewGuid().ToString("N").Substring(0, 8));
            Directory.CreateDirectory(stageDir);

            var staged = new System.Collections.Generic.List<string>();
            foreach (string part in semicolonPaths.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries))
            {
                string src = part.Trim();
                if (src.Length == 0 || !File.Exists(src)) continue;
                string dest = Path.Combine(stageDir, Path.GetFileName(src));
                if (File.Exists(dest)) File.Delete(dest);
                File.Copy(src, dest);
                string queuePath = uncRoot + dest.Substring(stageRoot.Length);
                staged.Add(queuePath);
            }

            return staged.Count == 0 ? null : string.Join(";", staged);
        }

        private static string MailAddressesToCsv(MailAddressCollection addresses)
        {
            if (addresses == null || addresses.Count == 0) return "";
            var parts = new System.Collections.Generic.List<string>();
            foreach (MailAddress addr in addresses)
            {
                if (addr != null && !string.IsNullOrWhiteSpace(addr.Address))
                    parts.Add(addr.Address.Trim());
            }
            return string.Join(",", parts);
        }

        private static string MailAttachmentsToPaths(MailMessage message)
        {
            if (message == null || message.Attachments == null || message.Attachments.Count == 0)
                return "";
            var parts = new System.Collections.Generic.List<string>();
            foreach (Attachment att in message.Attachments)
            {
                if (att == null) continue;
                string path = att.Name;
                try
                {
                    if (att.ContentStream is FileStream fs && !string.IsNullOrEmpty(fs.Name))
                        path = fs.Name;
                }
                catch { /* use Name */ }
                if (!string.IsNullOrWhiteSpace(path))
                    parts.Add(path);
            }
            return string.Join(";", parts);
        }

        private static void ApplyFcsaRecipients(ref string mailTo, ref string mailCC, ref string mailBCC, Int32 FCSA, Boolean VENN)
        {
            switch (FCSA)
            {
                case 1:
                    mailTo = "jscott@fcsa.ca,sbekhsat@fcsa.ca";
                    break;
                case 2:
                    if (string.IsNullOrWhiteSpace(mailTo))
                        mailTo = "jscott@fcsa.ca,sbekhsat@fcsa.ca";
                    else
                        mailTo = mailTo.TrimEnd(',') + ",jscott@fcsa.ca,sbekhsat@fcsa.ca";
                    break;
                case 3:
                    mailTo = "ablesonb@icloud.com";
                    break;
            }
            if (VENN)
                mailBCC = "ablesonb@icloud.com";
        }

        private static void ApplyEmailRedirect(ref string mailTo, ref string mailCC, ref string mailBody, string originalTo, string originalCc)
        {
            string redirect = GetEmailRedirectAllTo();
            if (string.IsNullOrWhiteSpace(redirect)) return;

            mailBody = (mailBody ?? "") + "\n\nOriginal recipients: To=" + (originalTo ?? "")
                + " CC=" + (string.IsNullOrWhiteSpace(originalCc) ? "" : originalCc);
            mailTo = redirect.Replace(',', ';');
            mailCC = null;
        }

        private static void LogEmailQueueInsert(string mailTo, string mailCC, string subject, bool ok, string error)
        {
            try
            {
                string user = "mics";
                try
                {
                    if (HttpContext.Current != null && HttpContext.Current.Session != null
                        && HttpContext.Current.Session["s_user"] != null)
                        user = HttpContext.Current.Session["s_user"].ToString();
                }
                catch { /* login path */ }

                string dbgfile = "D:\\extractlogs\\" + user + "EmailQueue.txt";
                using (var sw = new StreamWriter(dbgfile, true))
                {
                    sw.WriteLine("LOGTIME:" + DateTime.Now.ToString("yyyyMMddHHmmss.ffff"));
                    sw.WriteLine("OK:" + ok);
                    sw.WriteLine("TO:" + (mailTo ?? ""));
                    sw.WriteLine("CC:" + (mailCC ?? ""));
                    sw.WriteLine("Subject:" + (subject ?? ""));
                    if (!ok) sw.WriteLine("Error:" + error);
                    sw.WriteLine("---");
                }
            }
            catch { /* never fail callers */ }
        }

        /// <summary>Queue table for INSERT (remicsdev: adm.t_EmailQueue_local).</summary>
        public static string GetEmailQueueTable()
        {
            string v = ConfigurationManager.AppSettings["EmailQueueTable"];
            if (string.IsNullOrWhiteSpace(v))
                return "adm.t_EmailQueue";
            v = v.Trim();
            if (v == "adm.t_EmailQueue" || v == "adm.t_EmailQueue_local")
                return v;
            return "adm.t_EmailQueue";
        }

        /// <summary>Update auto-processing queue table (remicsdev: adm.t_UpdateQueue_local).</summary>
        public static string GetUpdateQueueTable()
        {
            string v = ConfigurationManager.AppSettings["UpdateQueueTable"];
            if (string.IsNullOrWhiteSpace(v))
                return "adm.t_UpdateQueue_local";
            v = v.Trim();
            if (v == "adm.t_UpdateQueue_local")
                return v;
            return "adm.t_UpdateQueue_local";
        }

        public static bool IsUpdateQueueEnabled()
        {
            string v = ConfigurationManager.AppSettings["UpdateQueueEnabled"];
            if (string.IsNullOrWhiteSpace(v)) return true;
            v = v.Trim();
            return v == "1" || v.Equals("true", StringComparison.OrdinalIgnoreCase);
        }

        public static bool IsUpdateQueueSubmitterAllowed(string submitter)
        {
            string list = ConfigurationManager.AppSettings["UpdateQueueAllowedSubmitters"];
            if (string.IsNullOrWhiteSpace(list) || list.Trim() == "*")
                return !string.IsNullOrWhiteSpace(submitter);
            if (string.IsNullOrWhiteSpace(submitter)) return false;
            foreach (string part in list.Split(new[] { ',', ';' }, StringSplitOptions.RemoveEmptyEntries))
            {
                if (string.Equals(part.Trim(), submitter.Trim(), StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            return false;
        }

        public static string GetUpdateQueueMode()
        {
            string v = ConfigurationManager.AppSettings["UpdateQueueMode"];
            if (string.IsNullOrWhiteSpace(v)) return "spoof-first";
            v = v.Trim().ToLowerInvariant();
            if (v == "spoof-only" || v == "main-only") return v;
            return "spoof-first";
        }

        /// <summary>INSERT pending update queue row. Not gated by DisableOutgoingEmail.</summary>
        public static bool InsertUpdateQueue(string stagingFile, string stagingPath, string submitter, string pdfName, string fileType, string submitterEmail)
        {
            if (!IsUpdateQueueEnabled())
                return false;
            if (string.IsNullOrWhiteSpace(stagingFile) || string.IsNullOrWhiteSpace(stagingPath))
                return false;
            if (!IsUpdateQueueSubmitterAllowed(submitter))
                return false;
            if (string.IsNullOrWhiteSpace(pdfName) || string.IsNullOrWhiteSpace(fileType))
                return false;

            fileType = fileType.Trim().ToUpperInvariant();
            if (fileType != "TS" && fileType != "ES")
                return false;

            string mode = GetUpdateQueueMode();
            string queueTable = GetUpdateQueueTable();
            string emailSql = string.IsNullOrWhiteSpace(submitterEmail) ? "NULL" : "'" + EscapeSql(submitterEmail) + "'";
            string strSql = "INSERT INTO " + queueTable +
                " (staging_file, staging_path, submitter, pdf_name, file_type, submitter_email, [status], [mode]) " +
                " VALUES ('" + EscapeSql(stagingFile) +
                "','" + EscapeSql(stagingPath) +
                "','" + EscapeSql(submitter) +
                "','" + EscapeSql(pdfName) +
                "','" + EscapeSql(fileType) +
                "'," + emailSql + ",'N','" + EscapeSql(mode) + "')";

            try
            {
                HttpContext ctx = HttpContext.Current;
                if (ctx == null || ctx.Session == null)
                    return false;
                using (OdbcConnection cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
                {
                    cn.Open();
                    using (OdbcCommand cmd = new OdbcCommand(strSql, cn))
                        cmd.ExecuteNonQuery();
                }
                return true;
            }
            catch
            {
                return false;
            }
        }

        /// <summary>INSERT email queue (sentYN=N). Not gated by DisableOutgoingEmail.</summary>
        public static bool InsertEmailQueue(string mailFrom, string mailTo, string mailCC, string mailSubject, string mailBody, string mailAttachments)
        {
            return InsertEmailQueue(mailFrom, mailTo, mailCC, mailSubject, mailBody, mailAttachments, null, null);
        }

        public static bool InsertEmailQueue(string mailFrom, string mailTo, string mailCC, string mailSubject, string mailBody, string mailAttachments, string connectionString, object principalw)
        {
            if (string.IsNullOrWhiteSpace(mailTo))
            {
                LogEmailQueueInsert(mailTo, mailCC, mailSubject, false, "mailTo empty");
                return false;
            }
            if (string.IsNullOrWhiteSpace(mailSubject))
            {
                LogEmailQueueInsert(mailTo, mailCC, mailSubject, false, "subject empty");
                return false;
            }
            if (mailBody == null) mailBody = "";

            string originalTo = mailTo ?? "";
            string originalCc = mailCC ?? "";
            ApplyEmailRedirect(ref mailTo, ref mailCC, ref mailBody, originalTo, originalCc);

            if (string.IsNullOrWhiteSpace(mailFrom))
                mailFrom = "mics@fcsa.ca";

            mailAttachments = StageAttachmentsForSqlAgent(mailAttachments);

            string ccSql = string.IsNullOrWhiteSpace(mailCC) ? "NULL" : "'" + EscapeSql(mailCC) + "'";
            string attachSql = string.IsNullOrWhiteSpace(mailAttachments) ? "NULL" : "'" + EscapeSql(mailAttachments) + "'";

            string queueTable = GetEmailQueueTable();
            string strSql = "INSERT INTO " + queueTable +
                " (mailFrom, mailTo, mailCC, mailSubject, mailBody, mailBodyFormat, mailAttachments, sentYN) " +
                " VALUES ('" + EscapeSql(mailFrom) +
                "','" + EscapeSql(mailTo) +
                "'," + ccSql +
                ",'" + EscapeSql(mailSubject) +
                "','" + EscapeSql(mailBody) +
                "','TEXT'," + attachSql + ",'N')";

            try
            {
                if (!string.IsNullOrEmpty(connectionString))
                {
                    using (OdbcConnection cn = new OdbcConnection(connectionString))
                    {
                        cn.Open();
                        using (OdbcCommand cmd = new OdbcCommand(strSql, cn))
                            cmd.ExecuteNonQuery();
                    }
                }
                else
                {
                    HttpContext ctx = HttpContext.Current;
                    if (ctx == null || ctx.Session == null)
                    {
                        LogEmailQueueInsert(mailTo, mailCC, mailSubject, false, "no HttpContext/session");
                        return false;
                    }
                    using (IDisposable WIC = MicsDbAuth.ImpersonateForJob(principalw ?? ctx.Session["principalw"]))
                    using (OdbcConnection cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
                    {
                        cn.Open();
                        using (OdbcCommand cmd = new OdbcCommand(strSql, cn))
                            cmd.ExecuteNonQuery();
                    }
                }
                LogEmailQueueInsert(mailTo, mailCC, mailSubject, true, null);
                return true;
            }
            catch (Exception ex)
            {
                LogEmailQueueInsert(mailTo, mailCC, mailSubject, false, ex.Message);
                return false;
            }
        }

        public static bool InsertEmailQueueFromMailMessage(MailMessage message, Int32 FCSA, Boolean VENN)
        {
            if (message == null) return false;
            string mailTo = MailAddressesToCsv(message.To);
            string mailCC = MailAddressesToCsv(message.CC);
            string mailBCC = MailAddressesToCsv(message.Bcc);
            ApplyFcsaRecipients(ref mailTo, ref mailCC, ref mailBCC, FCSA, VENN);

            string mailFrom = message.From != null ? message.From.Address : "mics@fcsa.ca";
            return InsertEmailQueue(mailFrom, mailTo, mailCC, message.Subject, message.Body, MailAttachmentsToPaths(message));
        }

        public static void LogSessionEnd(string appWEBDRIVE, SessionInfo sesInfo)
        {
            // note that for some reason this function requires explicit impersonation
            // whereas LogSessionStart does not
            // open file to log session vars (debug)

            string logfile = "";
            string info = "";
            switch (sesInfo.sesCLOSETYPE)
            {
                case "C": // password change
                    logfile = appWEBDRIVE + "\\perflogs\\" + sesInfo.sesUID + sesInfo.sesSID + "newpwd.txt";
                    info = "New Password:" + sesInfo.sesSID;
                    break;
                case "L": // logout
                    logfile = appWEBDRIVE + "\\perflogs\\" + sesInfo.sesUID + sesInfo.sesSID + "logout.txt";
                    info = "Web Logout:" + sesInfo.sesSID;
                    break;
                case "R": // restart with new project
                    logfile = appWEBDRIVE + "\\perflogs\\" + sesInfo.sesUID + sesInfo.sesSID + "restart.txt";
                    info = "Web Restart:" + sesInfo.sesSID;
                    break;
                case "T": // timeout
                    logfile = appWEBDRIVE + "\\perflogs\\" + sesInfo.sesUID + sesInfo.sesSID + "timeout.txt";
                    info = "Web Timeout:" + sesInfo.sesSID;
                    break;
                default: // unknown
                    logfile = appWEBDRIVE + "\\perflogs\\" + sesInfo.sesUID + sesInfo.sesSID + "unknown.txt";
                    info = "Unknown:" + sesInfo.sesSID;
                    break;
            }

            DateTime logTime = DateTime.Now;

            StreamWriter sw = new StreamWriter(logfile);
            sw.WriteLine("FROM ROUTINE sesUtils.LogSessionEnd");
            sw.WriteLine();
            sw.Flush();

            sw.WriteLine("MICS USER:" + sesInfo.sesUID);

            sw.WriteLine();
            sw.WriteLine("LOGTIME:" + logTime.ToString("yyyyMMddHHmmss.ffff"));
            sw.WriteLine("NETSESS:" + sesInfo.sesNSID);
            sw.WriteLine("Session:" + sesInfo.sesSID);
            sw.WriteLine("User ID:" + sesInfo.sesUID);
            sw.WriteLine(" Schema:" + sesInfo.sesSchema);
            sw.WriteLine("Project:" + sesInfo.sesDEFPROJ);
            sw.WriteLine("  CNSTR:" + sesInfo.sesCNSTR);
            sw.Flush();

            try
            {
                using (IDisposable WIC = SesUtilities.MicsDbAuth.ImpersonateForJob(sesInfo.sesWINPRIN))
                {
                    using (OdbcConnection cn = new OdbcConnection(sesInfo.sesCNSTR))
                    {
                        cn.Open();
                        sw.WriteLine("Open connection successful");
                        sw.Flush();

                        // clear any info from cull_temp tables

                        string strSql;

                        strSql = "DELETE from " + sesInfo.sesSchema + ".cull_temp1 where sessionid = '" + sesInfo.sesSID + "'";
                        sw.WriteLine(strSql);
                        sw.Flush();

                        using (OdbcCommand delete1 = new OdbcCommand(strSql, cn))
                        {
                            delete1.ExecuteNonQuery();
                        }

                        strSql = "DELETE from " + sesInfo.sesSchema + ".cull_temp2 where sessionid = '" + sesInfo.sesSID + "'";
                        sw.WriteLine(strSql);

                        using (OdbcCommand delete2 = new OdbcCommand(strSql, cn))
                        {
                            delete2.ExecuteNonQuery();
                        }

                        strSql = "DELETE from " + sesInfo.sesSchema + ".cull_temp3 where sessionid = '" + sesInfo.sesSID + "'";
                        sw.WriteLine(strSql);

                        using (OdbcCommand delete3 = new OdbcCommand(strSql, cn))
                        {
                            delete3.ExecuteNonQuery();
                        }

                        strSql = "DELETE from " + sesInfo.sesSchema + ".cull_temp1_es where sessionid = '" + sesInfo.sesSID + "'";
                        sw.WriteLine(strSql);

                        using (OdbcCommand delete4 = new OdbcCommand(strSql, cn))
                        {
                            delete4.ExecuteNonQuery();
                        }

                        strSql = "DELETE from " + sesInfo.sesSchema + ".cull_temp2_es where sessionid = '" + sesInfo.sesSID + "'";
                        sw.WriteLine(strSql);

                        using (OdbcCommand delete5 = new OdbcCommand(strSql, cn))
                        {
                            delete5.ExecuteNonQuery();
                        }

                        strSql = "DELETE from " + sesInfo.sesSchema + ".cull_temp3_es where sessionid = '" + sesInfo.sesSID + "'";
                        sw.WriteLine(strSql);

                        using (OdbcCommand delete6 = new OdbcCommand(strSql, cn))
                        {
                            delete6.ExecuteNonQuery();
                        }

                        sw.WriteLine(sesInfo.sesPROJSTART);
                        sw.Flush();

                        int year = System.Convert.ToInt32(sesInfo.sesPROJSTART.Substring(0, 4));
                        int month = System.Convert.ToInt32(sesInfo.sesPROJSTART.Substring(4, 2));
                        int day = System.Convert.ToInt32(sesInfo.sesPROJSTART.Substring(6, 2));
                        int hour = System.Convert.ToInt32(sesInfo.sesPROJSTART.Substring(8, 2));
                        int minute = System.Convert.ToInt32(sesInfo.sesPROJSTART.Substring(10, 2));
                        int second = System.Convert.ToInt32(sesInfo.sesPROJSTART.Substring(12, 2));

                        DateTime stTime = new DateTime(year, month, day, hour, minute, second);
                        DateTime curTime = DateTime.Now;

                        TimeSpan sesTime = curTime - stTime; // time in ticks
                        int sesTimeSec = sesTime.Hours * 3600 + sesTime.Minutes * 60 + sesTime.Seconds;

                        sw.WriteLine(" ");
                        sw.WriteLine("Timeout:" + sesInfo.sesTIMEOUT + "(mins)");
                        sw.WriteLine("  Start:" + stTime.ToString("yyyyMMddHHmmss"));
                        sw.WriteLine("    End:" + curTime.ToString("yyyyMMddHHmmss"));
                        sw.WriteLine(" Length:" + sesTimeSec.ToString() + "(secs)");

                        sw.WriteLine(" Billed:" + sesTimeSec.ToString() + "(secs)");
                        sw.WriteLine(" ");

                        string module = "WEB_CONN";

                        // create sql to insert billing info  
                        //SQL:VIEW:web.daily_usage_view 
                        string strSqlb = "insert into web.daily_usage_view values ('" +
                            sesInfo.sesSchema + "','" + sesInfo.sesUID + "',GetDate(),'" + sesInfo.sesDEFPROJ + "','" + module + "'," +
                            sesTimeSec + ",0,0,'" + info + "')";

                        sw.WriteLine(strSqlb);

                        string sessend = curTime.ToString("yyyyMMddHHmmss");

                        // build sql to delete sessionlogs record to record session end

                        //SQL:TABLE:web.mthly_connect
                        string strSqlw = "DELETE web.mthly_connect WHERE sessionid = '" + sesInfo.sesSID + "'";
                        sw.WriteLine(strSqlw);
                        sw.Flush();

                        // insert mics_billing
                        using (OdbcCommand insert1 = new OdbcCommand(strSqlb, cn))
                        {
                            insert1.ExecuteNonQuery();
                        }

                        // delete web.mthly_connect                                   
                        using (OdbcCommand deletew = new OdbcCommand(strSqlw, cn))
                        {
                            deletew.ExecuteNonQuery();
                        }
                    }

                    // delete session from application list of active sessions
                    // the T case (timeout) is handled in the calling routine (global.asx/SessionEnd)
                    // as the http context is not available there

                    //  COMMENTED OUT JUNE 14, 2022   - re-instated MAY 20, 2023 with try block
                    // this try block is required for case of user closing mics after failed 'forgot password' reset
                    // as in this case no user session has been created so the httpcontext variables are not yet loaded
                    try
                    {
                        if (sesInfo.sesCLOSETYPE != "T")
                        {
                            HttpApplication locApp = new HttpApplication();
                            locApp = (HttpApplication)HttpContext.Current.ApplicationInstance;

                            char[] delimiter = ",".ToCharArray();

                            locApp.Application.Lock();
                            sw.WriteLine("Before:" + locApp.Application["sessions"].ToString());
                            sw.Flush();
                            string[] loc_session_array = locApp.Application["sessions"].ToString().Split(delimiter);
                            string[] loc_uuser_array = locApp.Application["uusers"].ToString().Split(delimiter);
                            string[] loc_muser_array = locApp.Application["musers"].ToString().Split(delimiter);

                            locApp.Application["sessions"] = "";
                            locApp.Application["uusers"] = "";
                            locApp.Application["musers"] = "";
                            string comma = "";

                            for (int i = 0; i < loc_session_array.Length; i++)
                            {
                                sw.WriteLine(loc_session_array[i] + ":" + sesInfo.sesSID);
                                sw.Flush();
                                if (loc_session_array[i] != sesInfo.sesSID)
                                {
                                    locApp.Application["sessions"] = locApp.Application["sessions"] + comma + loc_session_array[i];
                                    locApp.Application["uusers"] = locApp.Application["uusers"] + comma + loc_uuser_array[i];
                                    locApp.Application["musers"] = locApp.Application["musers"] + comma + loc_muser_array[i];
                                    comma = ",";
                                }
                            }
                            locApp.Application.UnLock();
                            sw.WriteLine("After:" + locApp.Application["sessions"].ToString());
                            sw.Flush();


                            sw.WriteLine("Before:StoreMenuUse"); sw.Flush();
                            StoreMenuUse();  //insert menu use info into database
                            sw.WriteLine("After:StoreMenuUse"); sw.Flush();

                            sw.Close();
                        }
                    }
                    catch { }
                }
            }
            catch (Exception)
            {
                //ErrorUtils.NotifySystemOps(ee, "LogSessionEnd");
            }
        }
        public static void LogSessionStart(string appWEBDRIVE)
        {
            HttpContext ctx = HttpContext.Current;

            string sesUID = ctx.Session["s_user"].ToString();   // user id
            string sesSchema = ctx.Session["s_schema"].ToString();    // schema
            string sesSID = ctx.Session["FCSASESS"].ToString(); // FCSA session id
            string sesNSID = ctx.Session.SessionID.ToString();  // .NET session ID
            string sesDEFPROJ = ctx.Session["defProject"].ToString();  // default project 
            string sesCLOSETYPE = ctx.Session["CloseReason"].ToString();  // reason for session close
            string sesTIMEOUT = ctx.Session.Timeout.ToString(); // timeout value
            string sesPROJSTART = ctx.Session["ProjStart"].ToString();   // project start time
            string sesCNSTR = ctx.Session["s_cnString"].ToString(); // DB connection string

            string logfile = appWEBDRIVE + "\\perflogs\\" + sesUID + sesSID + ".txt";

            DateTime logTime = DateTime.Now;

            StreamWriter sw = new StreamWriter(logfile);
            sw.WriteLine("LOGTIME:" + logTime.ToString("yyyyMMddHHmmss.ffff"));
            sw.WriteLine("NETSESS:" + sesNSID);
            sw.WriteLine("Session:" + sesSID);
            sw.WriteLine("User ID:" + sesUID);
            sw.WriteLine("Schema :" + sesSchema);
            sw.WriteLine("Project:" + sesDEFPROJ);
            sw.WriteLine("  Start:" + sesPROJSTART);
            sw.WriteLine("Timeout:" + sesTIMEOUT);

            OdbcConnection cn;
            try
            {
                cn = new OdbcConnection(sesCNSTR);
                cn.Open();
                sw.WriteLine("Open connection successful");
            }
            catch (Exception ex)
            {
                sw.WriteLine("Database Connection failed");
                sw.WriteLine("Connection:" + sesCNSTR + ":" + ex.Message);
                sw.Close();
                return;
            }

            // create sql to insert mthly_connect record to record session start
            //SQL:TABLE:web.mthly_connect
            string strSqlw = "insert into web.mthly_connect values ('" + sesSID + "','" +
                sesSchema + "','" +
                sesUID + "','" +
                sesPROJSTART + "')";

            sw.WriteLine(strSqlw);

            // insert mthly_connect
            OdbcCommand insert1 = new OdbcCommand(strSqlw, cn);

            try
            {
                insert1.ExecuteNonQuery();
                sw.WriteLine("Insert mthly_connect successful");
            }
            catch (Exception i1)
            {
                cn.Close();
                sw.WriteLine("Insert mthly_connect failed:" + i1.Message);
            }

            // add user info application list of active sessions
            //f1.writeline("BEFORE:" + Application("sessions"));

            HttpApplication locApp = new HttpApplication();

            locApp = (HttpApplication)HttpContext.Current.ApplicationInstance;
            locApp.Application.Lock();

            if (locApp.Application["sessions"].ToString() == "")
            {
                locApp.Application["sessions"] = sesSID;
                locApp.Application["uusers"] = sesSchema;
                locApp.Application["musers"] = sesUID;
            }
            else
            {
                locApp.Application["sessions"] = locApp.Application["sessions"] + "," + sesSID;
                locApp.Application["uusers"] = locApp.Application["uusers"] + "," + sesSchema;
                locApp.Application["musers"] = locApp.Application["musers"] + "," + sesUID;
            }

            locApp.Application.UnLock();
            //f1.writeline("AFTER:" + Application("sessions"));

            cn.Close();
            sw.Close();

        }
        public static void LogMenuUse(string strMenuItem)
        {
            // this routine appends a new 'MenuLLog' Session entry to mics
            HttpContext ctx = HttpContext.Current;

            string key = "MenuLog" + DateTime.Now.ToString("O");
            string value = ctx.Session["s_user"].ToString() + "^" + ctx.Session["FCSASESS"].ToString() + "^" + strMenuItem;
            ctx.Session.Add(key, value);
        }
        private static void StoreMenuUse()
        {
            /*
            // this routine adds a Session Menulog entry to record the reason for closing the session
            // then writes the Menulog Sesson entries to the web.menulogs table
            HttpContext ctx = HttpContext.Current;

            string menulog = ctx.Application["web_drive"].ToString() + "\\perflogs\\" + ctx.Session["s_user"].ToString() + "menulog.txt";  // continuous log file for session ends
            StreamWriter swse = new StreamWriter(menulog, true);
            swse.WriteLine("");swse.Flush();

            // add menulog to Session for closure event
            switch (ctx.Session["CloseReason"].ToString())
            {
                case "C": // password change
                    LogMenuUse("Change Password");
                    break;
                case "L": // logout
                    LogMenuUse("Logout");
                    break;
                case "R": // restart with new project
                    LogMenuUse("Change Project");
                    break;
                case "T": // timeout
                    LogMenuUse("Timeout");
                    break;
                default: // unknown
                    LogMenuUse("Unknown");
                    break;
            }
            swse.WriteLine("Close Reason: " + ctx.Session["CloseReason"].ToString()); swse.Flush();

            DateTime curTime = DateTime.Now;
            string log_time = curTime.ToString("yyyy/MM/dd HH:mm:ss"); 

            // build menulog info into datatable (this is not used yet - the program currently inserts individual records)

            using (OdbcConnection cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (DataTable oDTmenulogs = new DataTable())
                {
                    //OdbcDataAdapter Da1 = new OdbcDataAdapter();
                    // create DataTable modelled on web.menulogs
                    //Da1.SelectCommand = new OdbcCommand("SELECT * FROM web.menulogs WHERE 1 = 0)", cn);
                    //OdbcCommandBuilder sqlCb1 = new OdbcCommandBuilder(Da1);
                    //Da1.Fill(oDTgeo);

                    string strSql;

                    // loop through session variables to find all entries starting with 'MenuLog' 
                    foreach (string s1 in ctx.Session.Keys)
                    {

                        //swse.WriteLine("Before filter:" + s1); swse.Flush();
                        if (s1.IndexOf("MenuLog") == 0)
                        {
                            //swse.WriteLine("After filter:" + s1);swse.Flush();
                            //DataRow drnew = oDTmenulogs.NewRow();

                            //swse.WriteLine("s1:" + s1); swse.Flush();

                            string loc_menulog_text = ctx.Session[s1].ToString();
                            swse.WriteLine("loc_menulog_text:" + loc_menulog_text); swse.Flush();

                            // parse session keys and copy entries to DataTable
                            char[] delimiter2 = "^".ToCharArray();
                            string[] loc_menulog_array = loc_menulog_text.Split(delimiter2);

                            swse.WriteLine("parts:" + loc_menulog_array[0].ToString() + "-" + loc_menulog_array[1].ToString() + "-" + 
                                loc_menulog_array[2].ToString()); swse.Flush();

                            //drnew["starttime"] = s1.Substring(7,23);
                            //drnew["micsid"] = loc_menulog_array[0];
                            //drnew["fcsasess"] = loc_menulog_array[1];
                            //drnew["micsmenu"] = loc_menulog_array[2];
                            //oDTmenulogs.Rows.Add();

                            // s1 represents a key to the menulog session variable 
                            // this key is of the form MenuLog2022-01-16T09:38:28.3605955-05:00
                            // SQL will not store times with more than 3 digits for milliseconds
                            // so the line below reduces s1 to 2022-01-16T09:38:28.360 before attempting
                            // to insert the information into a web.menulogs record
                            string timetomillisecs = s1.Substring(7, 23);

                            strSql = "INSERT INTO web.menulogs VALUES('" + timetomillisecs + "','" + loc_menulog_array[0].ToString() + "','" +
                                loc_menulog_array[1].ToString() + "','" + loc_menulog_array[2].ToString() + "')";
                            swse.WriteLine(strSql);swse.Flush();

                            // insert menulogs record
                            try
                            {
                                using (OdbcCommand insert1 = new OdbcCommand(strSql, cn))
                                {
                                    insert1.ExecuteNonQuery();
                                }
                            }
                            catch (Exception ex)
                            {
                                swse.WriteLine("Insert failed:" + ex.Message); swse.Flush();
                            }
                        }

                        //swse.WriteLine(s1.Substring(7) + " " + ctx.Session[s1].ToString());
                    }
                    swse.Close();
                }
            }
            */

            // bulk load datatable
            /*
            try
            {
                SesUtils.LogSessionEnd(Application["web_drive"].ToString(), si);
                swse.WriteLine("Session end logged");
            }
            catch
            {
                swse.WriteLine("Session end log failed");
            }
            swse.Close();
            */
        }

        public static void EmailError(string esubject, string emailBody, string eattachment)
        {
            /*
            // this routine is used to send emails of error conditions to Simin/Jason/Bill

            HttpContext ctx = HttpContext.Current;

            MailMessage Message = new MailMessage();
            Message.From = new MailAddress("mics@fcsa.ca");
            Message.To.Add("jscott@fcsa.ca");
            Message.To.Add("sbekhsat@fcsa.ca");
            Message.Bcc.Add("ablesonb@icloud.com");
            Message.mailSubject = esubject;

            // load mailBody
            if (emailBody == "")
            {
                emailBody = "See attachment";
            }

            Message.Body = ebody;

           

            // send message
            send_email_message(Message);
            return;
            */
        }
        public static bool CheckTimedOut()
        {
            // tried other versions which failed - haven't tested stuff below

            // this routine checks if session has timed out 
            // and returns true if it has
            //if (HttpContext.Current == null )
            //{
            //    return true;
            //}
            //else
            //{
            return false;
            //}
        }
        public static bool send_email_message(MailMessage inMessage, Int32 FCSA, Boolean VENN)
        {
            if (IsOutgoingEmailDisabled())
            {
                LogSuppressedEmail("send_email_message",
                    inMessage != null ? inMessage.Subject : "",
                    inMessage != null ? inMessage.Body : "",
                    inMessage != null ? inMessage.To.ToString() : "",
                    inMessage != null ? inMessage.CC.ToString() : "");
                return true;
            }

            StreamWriter sw;
            HttpContext ctx = HttpContext.Current;
            string sesMID;
            // this try block handles case of sending email related to login errors, as mics user id is not known
            try
            {
                sesMID = ctx.Session["s_user"].ToString();
            }
            catch
            {
                sesMID = "mics";
            }
            string dbgfile = "D:\\extractlogs\\" + sesMID + "SendEmailMessage.txt";
            sw = new StreamWriter(dbgfile, true);
            DateTime logTime = DateTime.Now;
            sw.WriteLine("LOGTIME:" + logTime.ToString("yyyyMMddHHmmss.ffff"));
            sw.Flush();

            try
            {
                sw.WriteLine("From:" + inMessage.From.ToString());
                sw.Flush();
                sw.WriteLine("TO:" + inMessage.To.ToString());
                sw.Flush();
                sw.WriteLine("CC:" + inMessage.CC.ToString());
                sw.Flush();
                sw.WriteLine("Subject:" + inMessage.Subject.ToString());
                sw.Flush();
                sw.WriteLine("Body:" + inMessage.Body.ToString());
                sw.Close();
            }
            catch (Exception ea)
            {
                sw.WriteLine("Error writing email info (send_email_message):" + ea.Message);
                sw.Close();
                return false;
            }

            return true;
        }
        public static bool send_email_message2(MailMessage inMessage, Int32 FCSA, Boolean VENN)
        {
            return InsertEmailQueueFromMailMessage(inMessage, FCSA, VENN);
        }
        public static bool send_email_sql(string msgTo, string msgCC, string msgBCC, string msgSubject, string msgBody, string msgAttach, Int32 FCSA, Boolean VENN)
        {
            ApplyFcsaRecipients(ref msgTo, ref msgCC, ref msgBCC, FCSA, VENN);
            return InsertEmailQueue("mics@fcsa.ca", msgTo, msgCC, msgSubject, msgBody, msgAttach);
        }

        public static bool send_email_sql(MailMessage inMessage, Int32 FCSA, Boolean VENN)
        {
            return InsertEmailQueueFromMailMessage(inMessage, FCSA, VENN);
        }
        public static bool send_email_sql2(MailMessage inMessage, Int32 FCSA, Boolean VENN)
        {
            return InsertEmailQueueFromMailMessage(inMessage, FCSA, VENN);
        }
        public static bool send_email_sql3(structSqlMsg sSqlMsg, Int32 FCSA, Boolean VENN)
        {
            ApplyFcsaRecipients(ref sSqlMsg.emailTo, ref sSqlMsg.emailCC, ref sSqlMsg.emailBCC, FCSA, VENN);
            if (string.IsNullOrWhiteSpace(sSqlMsg.emailFrom))
                sSqlMsg.emailFrom = "mics@fcsa.ca";
            string body = sSqlMsg.emailBody != null ? sSqlMsg.emailBody.ToString() : "";
            return InsertEmailQueue(sSqlMsg.emailFrom, sSqlMsg.emailTo, sSqlMsg.emailCC, sSqlMsg.emailSubject, body, sSqlMsg.emailAttach);
        }
        public static void log_environment()
        {
            HttpContext ctx = HttpContext.Current;

            string logfile = "D:\\extractlogs\\" + ctx.Session["s_user"].ToString() + "logenv.txt";

            DateTime logTime = DateTime.Now;

            StreamWriter sw = new StreamWriter(logfile, false);
            sw.WriteLine(logTime.ToLongDateString());

            foreach (DictionaryEntry env in Environment.GetEnvironmentVariables())
            {
                sw.WriteLine(env.Key.ToString() + " " + env.Value);
            }
            sw.Close();

        }
    }
       public class SessionInfo
    {
        protected string m_sesUID;
        protected string m_sesSchema;
        protected string m_sesSID;
        protected string m_sesNSID;
        protected string m_sesCLOSETYPE;
        protected string m_sesTIMEOUT;
        protected string m_sesPROJSTART;
        protected string m_sesCNSTR;
        protected string m_sesDEFPROJ;
        protected string m_sesIISServerName;
        protected WindowsPrincipal m_sesWINPRIN;

        public string sesUID
        {
            get { return m_sesUID; }
            set { m_sesUID = value; }
        }

        public string sesSchema
        {
            get { return m_sesSchema; }
            set { m_sesSchema = value; }
        }

        public string sesSID
        {
            get { return m_sesSID; }
            set { m_sesSID = value; }
        }

        public string sesNSID
        {
            get { return m_sesNSID; }
            set { m_sesNSID = value; }
        }

        public string sesCLOSETYPE
        {
            get { return m_sesCLOSETYPE; }
            set { m_sesCLOSETYPE = value; }
        }

        public string sesTIMEOUT
        {
            get { return m_sesTIMEOUT; }
            set { m_sesTIMEOUT = value; }
        }
        public string sesPROJSTART
        {
            get { return m_sesPROJSTART; }
            set { m_sesPROJSTART = value; }
        }

        public string sesCNSTR
        {
            get { return m_sesCNSTR; }
            set { m_sesCNSTR = value; }
        }

        public string sesDEFPROJ
        {
            get { return m_sesDEFPROJ; }
            set { m_sesDEFPROJ = value; }
        }

        public WindowsPrincipal sesWINPRIN
        {
            get { return m_sesWINPRIN; }
            set { m_sesWINPRIN = value; }
        }

        public SessionInfo(string sesUID, string sesSchema, string sesSID,
                            string sesNSID, string sesCLOSETYPE, string sesTIMEOUT,
                            string sesPROJSTART, string sesCNSTR, string sesDEFPROJ,
                            WindowsPrincipal sesWINPRIN)
        {
            m_sesUID = sesUID;
            m_sesSchema = sesSchema;
            m_sesSID = sesSID;
            m_sesNSID = sesNSID;
            m_sesCLOSETYPE = sesCLOSETYPE;
            m_sesTIMEOUT = sesTIMEOUT;
            m_sesPROJSTART = sesPROJSTART;
            m_sesCNSTR = sesCNSTR;
            m_sesDEFPROJ = sesDEFPROJ;
            m_sesWINPRIN = sesWINPRIN;
        }
    }
}