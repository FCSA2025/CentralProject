<%@ WebHandler Language="C#" Class="RemIcsReWrite.PcnHandler" %>

using System;
using System.Collections.Generic;
using System.Data.Odbc;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using DBAccess;
using JobSubmission;
using KmlUtilities;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>
    /// PCN Coordination  -  parity with Tpcnmenu PcnTS/PcnES → PcnLookup → PcnDisplay send.
    /// GET  action=gate|operators
    /// POST action=scan|send|attach
    /// </summary>
    public class PcnHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly Regex ValidName = new Regex(@"^[A-Za-z0-9_]{1,16}$", RegexOptions.Compiled);

        public bool IsReusable { get { return false; } }

        public void ProcessRequest(HttpContext context)
        {
            var response = context.Response;
            var request = context.Request;
            response.ContentType = "application/json; charset=utf-8";
            response.Cache.SetCacheability(HttpCacheability.NoCache);

            if (context.Session == null || context.Session["s_cnString"] == null
                || context.Session["s_schema"] == null || context.Session["s_user"] == null
                || context.Session["user_dir"] == null)
            {
                response.StatusCode = 401;
                WriteJson(response, new { ok = false, error = "Session not initialized." });
                return;
            }

            string action = (request["action"] ?? request.QueryString["action"] ?? "").Trim().ToLowerInvariant();
            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                {
                    switch (action)
                    {
                        case "gate": HandleGate(context); break;
                        case "scan": HandleScan(context); break;
                        case "operators": HandleOperators(context); break;
                        case "send": HandleSend(context); break;
                        case "attach": HandleAttach(context); break;
                        case "discard": HandleDiscard(context); break;
                        default:
                            response.StatusCode = 400;
                            WriteJson(response, new { ok = false, error = "action must be gate|scan|operators|send|attach|discard" });
                            break;
                    }
                }
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        private static void HandleGate(HttpContext context)
        {
            string name, filetype;
            if (!ReadNameType(context.Request, out name, out filetype))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Invalid name or filetype." });
                return;
            }

            string schema = context.Session["s_schema"].ToString();
            string cnstr = context.Session["s_cnString"].ToString();
            int tableType = filetype == "ES" ? 5 : 0;
            string validated = UserTable.GetUserValidFlag(schema, tableType, name);
            bool allow = !string.IsNullOrEmpty(validated) && "MUSK".IndexOf(validated) >= 0;

            if (!allow)
            {
                WriteJson(context.Response, new
                {
                    ok = true,
                    allow = false,
                    validated = validated ?? "",
                    filetype = filetype,
                    name = name,
                    skipReason = "File is not validated for PCN (need status M, U, S, or K).",
                    cDist = (double?)null
                });
                return;
            }

            if (filetype == "TS")
            {
                WriteJson(context.Response, new
                {
                    ok = true,
                    allow = true,
                    validated = validated,
                    filetype = filetype,
                    name = name,
                    skipReason = (string)null,
                    cDist = 200.0,
                    distanceEditable = true
                });
                return;
            }

            // ES: TX channels + scatter distance
            using (var cn = new OdbcConnection(cnstr))
            {
                cn.Open();
                string sqlTx = "SELECT COUNT(*) FROM " + schema + ".fe_" + name + "_chan WHERE freqtx <> 0.0";
                int txCount;
                using (var cmd = new OdbcCommand(sqlTx, cn))
                    txCount = Convert.ToInt32(cmd.ExecuteScalar());

                if (txCount == 0)
                {
                    WriteJson(context.Response, new
                    {
                        ok = true,
                        allow = false,
                        validated = validated,
                        filetype = filetype,
                        name = name,
                        skipReason = "Receive-only ES file (no TX channels)  -  PCN scan skipped.",
                        cDist = (double?)null,
                        skipCode = -2
                    });
                    return;
                }

                string sqlAnte = "SELECT MAX(txtro), MAX(txpre) FROM " + schema + ".fe_" + name + "_ante";
                double maxtro = 0, maxpre = 0;
                using (var cmd = new OdbcCommand(sqlAnte, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    if (dr.Read())
                    {
                        if (dr[0] != DBNull.Value) maxtro = Convert.ToDouble(dr[0]);
                        if (dr[1] != DBNull.Value) maxpre = Convert.ToDouble(dr[1]);
                    }
                }
                double cDist = Math.Max(maxtro, maxpre);
                if (cDist <= 0)
                {
                    WriteJson(context.Response, new
                    {
                        ok = true,
                        allow = false,
                        validated = validated,
                        filetype = filetype,
                        name = name,
                        skipReason = "All scatter distances are zero  -  PCN scan skipped.",
                        cDist = 0.0,
                        skipCode = -1
                    });
                    return;
                }

                WriteJson(context.Response, new
                {
                    ok = true,
                    allow = true,
                    validated = validated,
                    filetype = filetype,
                    name = name,
                    skipReason = (string)null,
                    cDist = cDist,
                    distanceEditable = false
                });
            }
        }

        private static void HandleScan(HttpContext context)
        {
            string name, filetype;
            if (!ReadNameType(context.Request, out name, out filetype))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Invalid name or filetype." });
                return;
            }

            string cDist = (context.Request["cDist"] ?? "200").Trim();
            double d;
            if (!double.TryParse(cDist, out d) || d <= 0)
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Invalid cDist." });
                return;
            }

            string projectCode = (context.Request["projectCode"] ?? "").Trim();
            if (string.IsNullOrEmpty(projectCode) && context.Session["defProject"] != null)
                projectCode = context.Session["defProject"].ToString();

            string progDir = context.Session["prog_dir"] != null ? context.Session["prog_dir"].ToString() : "";
            string dbName = context.Session["db_name"] != null ? context.Session["db_name"].ToString() : "";
            if (string.IsNullOrEmpty(progDir) || string.IsNullOrEmpty(dbName))
            {
                context.Response.StatusCode = 500;
                WriteJson(context.Response, new { ok = false, error = "Session missing prog_dir or db_name." });
                return;
            }

            var oLog = new dblogger(progDir + "pcnscan");
            oLog.logargs = dbName + " " + projectCode + " " + name + " " + filetype + " " + cDist + " " +
                           oLog.logserial + " D:\\extractlogs\\pcn" + oLog.logserial;
            oLog = JobSubmit.SubmitJob(oLog, " ", 0);
            oLog.Finish();

            if (oLog.logerrorcode != 0)
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = oLog.logerrordesc ?? ("JobSubmit error " + oLog.logerrorcode),
                    logserial = oLog.logserial
                });
                return;
            }

            if (oLog.logreturncode == -1)
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = "Fatal error in pcnscan",
                    returnCode = -1,
                    logserial = oLog.logserial
                });
                return;
            }

            if (oLog.logreturncode == 201)
            {
                string userDir = context.Session["user_dir"].ToString();
                string winprn = Path.Combine(userDir, "p" + oLog.logserial + ".prn");
                string wintxt = Path.Combine(userDir, "p" + oLog.logserial + ".txt");
                if (File.Exists(wintxt)) File.Delete(wintxt);
                if (File.Exists(winprn)) File.Move(winprn, wintxt);
                string schema = context.Session["s_schema"].ToString();
                string user = context.Session["s_user"].ToString();
                string reportUrl = "../userdirs/" + schema + "/" + user + "/p" + oLog.logserial + ".txt";
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = "pcnscan reported errors  -  see error file",
                    returnCode = 201,
                    logserial = oLog.logserial,
                    errorReportUrl = reportUrl,
                    errorReportFile = "p" + oLog.logserial
                });
                return;
            }

            WriteJson(context.Response, new
            {
                ok = true,
                logserial = oLog.logserial,
                returnCode = oLog.logreturncode,
                name = name,
                filetype = filetype,
                cDist = d
            });
        }

        private static void HandleOperators(HttpContext context)
        {
            string name, filetype;
            if (!ReadNameType(context.Request, out name, out filetype))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Invalid name or filetype." });
                return;
            }
            string logserial = (context.Request["logserial"] ?? context.Request.QueryString["logserial"] ?? "").Trim();
            if (string.IsNullOrEmpty(logserial))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "logserial required." });
                return;
            }

            string schema = context.Session["s_schema"].ToString();
            string user = context.Session["s_user"].ToString();
            string cnstr = context.Session["s_cnString"].ToString();
            string sourceTable = PcnSourceTable(context);
            bool includeOwn = string.Equals(context.Request["includeOwn"] ?? "1", "1", StringComparison.OrdinalIgnoreCase)
                || string.Equals(context.Request["includeOwn"], "true", StringComparison.OrdinalIgnoreCase);

            var operators = new List<object>();
            var emails = new List<object>();
            var missingEmails = new List<object>();
            var operUltrix = new List<string>();
            bool ownCompanyAffected = false;
            int otherMicsInCompany = 0;
            string senderEmail = "";

            using (var cn = new OdbcConnection(cnstr))
            {
                cn.Open();

                string strSql = "SELECT rv.retval, so.nameop, ai.oper FROM " + schema + ".returnvalues rv, adm.account_ids ai, main.sd_oper so " +
                    "WHERE rv.retkey='" + Esc(logserial) + "' " +
                    "AND rv.retval = ai.ultrixid AND ai.oper = so.oper ORDER BY so.nameop";

                using (var cmd = new OdbcCommand(strSql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        string ultrix = dr[0] != DBNull.Value ? dr[0].ToString().Trim() : "";
                        string nameop = dr[1] != DBNull.Value ? dr[1].ToString().Trim() : "";
                        string oper = dr[2] != DBNull.Value ? dr[2].ToString().Trim() : "";
                        if (ultrix.Length == 0) continue;
                        if (string.Equals(ultrix, schema, StringComparison.OrdinalIgnoreCase))
                            ownCompanyAffected = true;
                        operUltrix.Add(ultrix);
                        operators.Add(new { ultrixid = ultrix, oper = oper, name = nameop });
                    }
                }

                if (operators.Count == 0)
                {
                    WriteJson(context.Response, new
                    {
                        ok = true,
                        empty = true,
                        message = "There are no other companies' sites within the specified distance.",
                        operators = operators,
                        emails = emails,
                        logserial = logserial,
                        tmpdir = (string)null,
                        senderEmail = ""
                    });
                    return;
                }

                if (ownCompanyAffected)
                {
                    // Fixed classic stray-quote bug on table name.
                    strSql = "SELECT COUNT(*) FROM " + sourceTable + " WHERE ultrixid = '" + Esc(schema) +
                             "' AND NOT micsid = '" + Esc(user) + "' AND send_pcn = 'y'";
                    using (var cmd = new OdbcCommand(strSql, cn))
                        otherMicsInCompany = Convert.ToInt32(cmd.ExecuteScalar());
                }

                senderEmail = LookupEmail(cn, sourceTable, schema, user);

                if (string.IsNullOrEmpty(senderEmail))
                {
                    WriteJson(context.Response, new
                    {
                        ok = false,
                        error = "You do not have an e-mail address set up in the Mics database. Please contact FCSA to have one added."
                    });
                    return;
                }

                var inList = new StringBuilder();
                string comma = "";
                foreach (string u in operUltrix)
                {
                    if (!includeOwn && string.Equals(u, schema, StringComparison.OrdinalIgnoreCase))
                        continue;
                    inList.Append(comma).Append("'").Append(Esc(u)).Append("'");
                    comma = ",";
                }

                if (inList.Length > 0)
                {
                    // Prefer account_ids join (classic sd_oper join on ultrixid=oper is unreliable).
                    strSql = "SELECT DISTINCT " +
                             "COALESCE(NULLIF(LTRIM(RTRIM(ad.email)), ''), NULLIF(LTRIM(RTRIM(ud.email)), '')), " +
                             "so.nameop FROM " + sourceTable + " ad " +
                             "INNER JOIN adm.account_ids ai ON ad.ultrixid = ai.ultrixid " +
                             "INNER JOIN main.sd_oper so ON ai.oper = so.oper " +
                             "LEFT JOIN dbo.t_UserDetails ud ON RTRIM(ud.micsId) = RTRIM(ad.micsid) " +
                             "AND RTRIM(ud.IsActiveYN) = 'Y' " +
                             "WHERE ad.send_pcn = 'y' AND ad.ultrixid IN (" + inList + ") " +
                             "AND ( " +
                             "(ad.email IS NOT NULL AND LTRIM(RTRIM(ad.email)) <> '') " +
                             "OR (ud.email IS NOT NULL AND LTRIM(RTRIM(ud.email)) <> '') " +
                             ") " +
                             "AND COALESCE(NULLIF(LTRIM(RTRIM(ad.email)), ''), NULLIF(LTRIM(RTRIM(ud.email)), '')) " +
                             "<> '" + Esc(senderEmail) + "' " +
                             "ORDER BY so.nameop";
                    using (var cmd = new OdbcCommand(strSql, cn))
                    using (var dr = cmd.ExecuteReader())
                    {
                        while (dr.Read())
                        {
                            string em = dr[0] != DBNull.Value ? dr[0].ToString().Trim() : "";
                            string nm = dr[1] != DBNull.Value ? dr[1].ToString().Trim() : "";
                            if (em.Length == 0) continue;
                            emails.Add(new { email = em, name = nm, display = nm + ": " + em });
                        }
                    }
                }

                missingEmails = NotifyMissingEmails(cn, sourceTable, inList.ToString(),
                    senderEmail, user, filetype, name);
            }

            string tmpdir = user + name + DateTime.Now.ToString("yyyyMMddHHmm");
            string emailpath = Path.Combine("D:\\Temp", tmpdir);
            if (!Directory.Exists(emailpath)) Directory.CreateDirectory(emailpath);

            WriteJson(context.Response, new
            {
                ok = true,
                empty = false,
                logserial = logserial,
                name = name,
                filetype = filetype,
                operators = operators,
                emails = emails,
                missingEmails = missingEmails,
                senderEmail = senderEmail,
                ownCompanyAffected = ownCompanyAffected,
                otherMicsInCompany = otherMicsInCompany,
                tmpdir = tmpdir,
                includeOwnDefault = !ownCompanyAffected || otherMicsInCompany == 0
            });
        }

        private static void HandleAttach(HttpContext context)
        {
            string tmpdir = (context.Request["tmpdir"] ?? "").Trim();
            if (string.IsNullOrEmpty(tmpdir) || tmpdir.IndexOf("..") >= 0 || tmpdir.IndexOf('\\') >= 0 || tmpdir.IndexOf('/') >= 0)
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Invalid tmpdir." });
                return;
            }
            string emailpath = Path.Combine("D:\\Temp", tmpdir);
            if (!Directory.Exists(emailpath)) Directory.CreateDirectory(emailpath);

            HttpPostedFile file = context.Request.Files["file"];
            if (file == null || file.ContentLength <= 0)
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "No file uploaded." });
                return;
            }
            string safe = Path.GetFileName(file.FileName);
            if (string.IsNullOrEmpty(safe))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Bad file name." });
                return;
            }
            string dest = Path.Combine(emailpath, safe);
            file.SaveAs(dest);
            WriteJson(context.Response, new { ok = true, tmpdir = tmpdir, fileName = safe });
        }

        private static void HandleDiscard(HttpContext context)
        {
            string tmpdir = (context.Request["tmpdir"] ?? "").Trim();
            if (string.IsNullOrEmpty(tmpdir) || tmpdir.IndexOf("..") >= 0 || tmpdir.IndexOf('\\') >= 0 || tmpdir.IndexOf('/') >= 0)
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Invalid tmpdir." });
                return;
            }
            string emailpath = Path.Combine("D:\\Temp", tmpdir);
            try
            {
                if (Directory.Exists(emailpath))
                    Directory.Delete(emailpath, true);
            }
            catch (Exception ex)
            {
                WriteJson(context.Response, new { ok = false, error = ex.Message });
                return;
            }
            WriteJson(context.Response, new { ok = true });
        }

        private static void HandleSend(HttpContext context)
        {
            string name, filetype;
            if (!ReadNameType(context.Request, out name, out filetype))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Invalid name or filetype." });
                return;
            }

            string tmpdir = (context.Request["tmpdir"] ?? "").Trim();
            string notes = context.Request["notes"] ?? "";
            string ccList = context.Request["cc"] ?? "";
            string senderEmail = (context.Request["senderEmail"] ?? "").Trim();
            string toEmailsRaw = context.Request["toEmails"] ?? "";
            bool attachKml = string.Equals(context.Request["attachKml"], "1", StringComparison.OrdinalIgnoreCase)
                || string.Equals(context.Request["attachKml"], "true", StringComparison.OrdinalIgnoreCase);

            if (string.IsNullOrEmpty(tmpdir) || tmpdir.IndexOf("..") >= 0)
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "tmpdir required." });
                return;
            }
            if (string.IsNullOrEmpty(senderEmail))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "senderEmail required." });
                return;
            }

            string userDir = context.Session["user_dir"].ToString();
            string user = context.Session["s_user"].ToString();
            string emailpath = Path.Combine("D:\\Temp", tmpdir);
            if (!Directory.Exists(emailpath)) Directory.CreateDirectory(emailpath);

            string webDrive = context.Application["web_drive"] != null
                ? context.Application["web_drive"].ToString()
                : "D:";
            string dbgfile = Path.Combine(webDrive, "extractlogs", user + "PCNSend.txt");
            using (var swsend = new StreamWriter(dbgfile, false))
            {
                swsend.WriteLine("LOGTIME:" + DateTime.Now.ToString("yyyyMMddHHmmss.ffff"));
                swsend.WriteLine("sType: " + filetype);
                swsend.WriteLine("pdfName: " + name);

                if (filetype == "TS" && attachKml)
                {
                    string statusinfo;
                    string kmlreplist;
                    if (!KmlUtils.build_kml(name, "V", out statusinfo, out kmlreplist))
                    {
                        swsend.WriteLine("KML FAILED:" + statusinfo);
                        WriteJson(context.Response, new { ok = false, error = statusinfo ?? "KML build failed" });
                        return;
                    }
                    string kmlrepname = (kmlreplist ?? "").Split(';')[0];
                    if (!string.IsNullOrEmpty(kmlrepname))
                    {
                        string kmlSrc = Path.Combine(userDir, kmlrepname);
                        string kmlDest = Path.Combine(emailpath, kmlrepname);
                        if (File.Exists(kmlSrc))
                        {
                            if (File.Exists(kmlDest)) File.Delete(kmlDest);
                            File.Copy(kmlSrc, kmlDest);
                            swsend.WriteLine("KML file moved to " + kmlDest);
                        }
                    }
                }

                string exportSrc = Path.Combine(userDir, name + ".txt");
                string exportDest = Path.Combine(emailpath, name + ".txt");
                if (!File.Exists(exportSrc))
                {
                    WriteJson(context.Response, new { ok = false, error = "Export file missing  -  run exportTable first: " + name + ".txt" });
                    return;
                }
                if (File.Exists(exportDest)) File.Delete(exportDest);
                File.Copy(exportSrc, exportDest);
                swsend.WriteLine("EXPORT file moved to " + exportDest);

                var body = new StringBuilder();
                body.Append("This PCN has been sent by: ").Append(senderEmail).Append("\n\n");
                body.Append("Please be advised, the following file has been submitted for coordination:\n\n");
                body.Append(filetype).Append(" ").Append(name).Append("\n\n");
                body.Append("A copy is attached for import to Webmics. Recipients must respond with any objections\n");
                body.Append("within 30 days from the date and time of this notice.\n\n");
                body.Append("Note: ").Append(notes);

                string subject = "PCN Notification for " + filetype + " file " + name;
                var toList = new List<string>();
                if (!string.IsNullOrWhiteSpace(senderEmail)) toList.Add(senderEmail.Trim());

                foreach (string part in toEmailsRaw.Split(new[] { ';', ',', '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    string em = part.Trim();
                    if (em.Length == 0) continue;
                    int colon = em.LastIndexOf(':');
                    if (colon >= 0 && em.IndexOf('@') > colon) em = em.Substring(colon + 1).Trim();
                    if (em.IndexOf('@') >= 0)
                    {
                        bool dup = false;
                        foreach (string existing in toList)
                        {
                            if (string.Equals(existing, em, StringComparison.OrdinalIgnoreCase)) { dup = true; break; }
                        }
                        if (!dup) toList.Add(em);
                    }
                    else if (em.IndexOf('@') < 0)
                        swsend.WriteLine("SKIP TO:" + em);
                }

                string mailTo = string.Join(",", toList);
                string mailCC = string.IsNullOrWhiteSpace(ccList) ? null : ccList.Trim();

                var attachPaths = new StringBuilder();
                foreach (string f in Directory.GetFiles(emailpath))
                {
                    if (attachPaths.Length > 0) attachPaths.Append(';');
                    attachPaths.Append(f);
                    swsend.WriteLine("ATTACH:" + f);
                }

                string siteName = context.Session["SiteName"] != null ? context.Session["SiteName"].ToString() : "";
                bool isDev = siteName.IndexOf("remicsdev", StringComparison.OrdinalIgnoreCase) >= 0
                    || siteName.IndexOf("micstest", StringComparison.OrdinalIgnoreCase) >= 0;
                int fcsaFlag = 2;
                if (isDev)
                {
                    toList.Clear();
                    if (!string.IsNullOrWhiteSpace(senderEmail)) toList.Add(senderEmail.Trim());
                    toList.Add("plin@fcsa.ca");
                    toList.Add("jscott@fcsa.ca");
                    mailTo = string.Join(",", toList);
                    mailCC = null;
                    body.Append("TEST FROM DEV - PLEASE CONFIRM RECEIPT");
                    fcsaFlag = 0;
                    swsend.WriteLine("In remicsdev/micstest override");
                }
                else if (fcsaFlag == 2)
                {
                    mailTo = string.IsNullOrWhiteSpace(mailTo)
                        ? "jscott@fcsa.ca,sbekhsat@fcsa.ca"
                        : mailTo.TrimEnd(',') + ",jscott@fcsa.ca,sbekhsat@fcsa.ca";
                }

                swsend.WriteLine("TO: " + mailTo);
                swsend.WriteLine("CC: " + (mailCC ?? ""));
                swsend.WriteLine("SUBJECT: " + subject);
                swsend.WriteLine("BODY: " + body);
                swsend.WriteLine("ATTACH: " + attachPaths);
                swsend.Flush();

                bool sent = SesUtils.InsertEmailQueue("mics@fcsa.ca", mailTo, mailCC, subject, body.ToString(), attachPaths.Length > 0 ? attachPaths.ToString() : null);
                swsend.WriteLine(sent ? "PCNMsg Queued" : "PCNMsg Queue Failed");

                // W0-2: only clean up staging/export after a successful queue insert.
                // On failure keep userdirs export so the user can retry.
                if (!sent)
                {
                    swsend.WriteLine("EXPORT PRESERVED:" + exportSrc);
                    swsend.Flush();
                    WriteJson(context.Response, new
                    {
                        ok = false,
                        error = "PCN notification failed to queue for delivery. The export file was left in place so you can retry. See extractlogs.",
                        name = name,
                        filetype = filetype,
                        queued = false
                    });
                    return;
                }

                // Queue insert copies attachments to MicsEmailStaging; D:\Temp\{tmpdir} is leftover.
                try
                {
                    if (Directory.Exists(emailpath))
                        Directory.Delete(emailpath, true);
                    swsend.WriteLine("TEMP DIR CLEANED:" + emailpath);
                }
                catch (Exception cex)
                {
                    swsend.WriteLine("TEMP DIR CLEANUP FAILED:" + cex.Message);
                }

                try
                {
                    if (File.Exists(exportSrc)) File.Delete(exportSrc);
                }
                catch { /* classic cleanup.aspx */ }
            }

            WriteJson(context.Response, new
            {
                ok = true,
                message = "PCN notification queued for delivery (see extractlogs).",
                name = name,
                filetype = filetype,
                queued = true
            });
        }

        /// <summary>
        /// Adm account_details / pcn_account_details first; dbo.t_UserDetails.email if adm is blank.
        /// </summary>
        private static string LookupEmail(OdbcConnection cn, string sourceTable, string ultrixid, string micsid)
        {
            string sql = "SELECT email FROM " + sourceTable +
                " WHERE ultrixid = '" + Esc(ultrixid) + "' AND micsid = '" + Esc(micsid) + "'";
            using (var cmd = new OdbcCommand(sql, cn))
            {
                object o = cmd.ExecuteScalar();
                if (o != null && o != DBNull.Value)
                {
                    string em = o.ToString().Trim();
                    if (em.Length > 0) return em;
                }
            }
            sql = "SELECT email FROM dbo.t_UserDetails " +
                "WHERE RTRIM(micsId) = '" + Esc(micsid) + "' AND RTRIM(IsActiveYN) = 'Y'";
            using (var cmd = new OdbcCommand(sql, cn))
            {
                object o = cmd.ExecuteScalar();
                if (o != null && o != DBNull.Value)
                {
                    string em = o.ToString().Trim();
                    if (em.Length > 0) return em;
                }
            }
            return "";
        }

        /// <summary>
        /// Classic PcnDisplay BuildEmails: notify FCSA (CC sender) for send_pcn users with no address.
        /// Parentheses fix the classic OR-precedence bug on empty email.
        /// t_UserDetails is a fallback  -  only missing if both adm and t_UserDetails are blank.
        /// </summary>
        private static List<object> NotifyMissingEmails(OdbcConnection cn, string sourceTable, string inList,
            string senderEmail, string user, string filetype, string name)
        {
            var missing = new List<object>();
            if (string.IsNullOrEmpty(inList)) return missing;

            StreamWriter sw = TryOpenExtractLog((user ?? "mics") + "BuildEmails.txt");
            try
            {
                if (sw != null)
                {
                    sw.WriteLine("LOGTIME:" + DateTime.Now.ToString("yyyyMMddHHmmss.ffff"));
                    sw.WriteLine("Missing-email check for " + filetype + " " + name);
                }

                string strSql = "SELECT DISTINCT ad.ultrixid, ad.micsid FROM " + sourceTable + " ad " +
                    "LEFT JOIN dbo.t_UserDetails ud ON RTRIM(ud.micsId) = RTRIM(ad.micsid) " +
                    "AND RTRIM(ud.IsActiveYN) = 'Y' " +
                    "WHERE ad.send_pcn = 'y' AND ad.ultrixid IN (" + inList + ") " +
                    "AND (ad.email IS NULL OR LTRIM(RTRIM(ad.email)) = '') " +
                    "AND (ud.email IS NULL OR LTRIM(RTRIM(ud.email)) = '')";
                if (sw != null) sw.WriteLine("strSql:" + strSql);

                var rows = new List<string[]>();
                using (var cmd = new OdbcCommand(strSql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        string ultrix = dr[0] != DBNull.Value ? dr[0].ToString().Trim() : "";
                        string micsid = dr[1] != DBNull.Value ? dr[1].ToString().Trim() : "";
                        if (ultrix.Length == 0 && micsid.Length == 0) continue;
                        rows.Add(new[] { ultrix, micsid });
                        if (sw != null) sw.WriteLine("Missing email: " + ultrix + " " + micsid);
                    }
                }

                if (rows.Count == 0)
                {
                    if (sw != null) sw.WriteLine("No missing emails");
                    return missing;
                }

                foreach (string[] row in rows)
                {
                    string ultrix = row[0];
                    string micsid = row[1];
                    missing.Add(new { ultrixid = ultrix, micsid = micsid });
                    var body = new StringBuilder();
                    body.Append("The following user has no e-mail address specified in Webmics.\n\n");
                    body.Append("As a result they did not receive the PCN notice for ");
                    body.Append(filetype).Append(" ").Append(name);
                    body.Append(".\n\n Account ID: ").Append(ultrix);
                    body.Append(" Mics ID: ").Append(micsid);
                    string subject = "Missing email address for " + filetype + " file " + name;
                    bool queued = SesUtils.InsertEmailQueue(
                        "mics@fcsa.ca",
                        "jscott@fcsa.ca,sbekhsat@fcsa.ca",
                        senderEmail,
                        subject,
                        body.ToString(),
                        null);
                    if (sw != null)
                    {
                        sw.WriteLine(queued ? "PCNMsgm1 Queued" : "PCNMsgm1 Queue Failed");
                        sw.WriteLine("ONE MISSING SUBJECT: " + subject);
                        sw.WriteLine("ONE MISSING BODY: " + body);
                    }
                }
            }
            catch (Exception ex)
            {
                try { if (sw != null) sw.WriteLine("Missing-email notify failed: " + ex.Message); } catch { }
            }
            finally
            {
                if (sw != null)
                {
                    try { sw.Flush(); sw.Close(); } catch { }
                }
            }
            return missing;
        }

        private static StreamWriter TryOpenExtractLog(string fileName)
        {
            try
            {
                string drive = "D:";
                HttpContext ctx = HttpContext.Current;
                if (ctx != null && ctx.Application["web_drive"] != null)
                {
                    string w = ctx.Application["web_drive"].ToString();
                    if (!string.IsNullOrEmpty(w)) drive = w;
                }
                string dir = Path.Combine(drive, "extractlogs");
                Directory.CreateDirectory(dir);
                return new StreamWriter(Path.Combine(dir, fileName), true);
            }
            catch
            {
                return null;
            }
        }

        private static string PcnSourceTable(HttpContext context)
        {
            string site = "";
            if (context.Session["SiteName"] != null) site = context.Session["SiteName"].ToString();
            else if (context.Session["siteName"] != null) site = context.Session["siteName"].ToString();
            if (site.IndexOf("remicsdev", StringComparison.OrdinalIgnoreCase) >= 0
                || site.IndexOf("micstest", StringComparison.OrdinalIgnoreCase) >= 0)
                return "adm.pcn_account_details";
            return "adm.account_details";
        }

        private static bool ReadNameType(HttpRequest request, out string name, out string filetype)
        {
            name = (request["name"] ?? request.QueryString["name"] ?? "").Trim();
            filetype = (request["filetype"] ?? request.QueryString["filetype"] ?? "TS").Trim().ToUpperInvariant();
            if (!ValidName.IsMatch(name)) return false;
            if (filetype != "TS" && filetype != "ES") return false;
            return true;
        }

        private static string Esc(string s)
        {
            return (s ?? "").Replace("'", "''");
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            response.Write(new JavaScriptSerializer().Serialize(obj));
        }
    }
}
