<%@ WebHandler Language="C#" Class="RemIcsReWrite.PrintEmailHandler" %>

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
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>
    /// Print selected TS/ES files to the user directory (ftPrint / fePrint) and queue them as email attachments.
    /// POST names, filetype, projectCode
    /// </summary>
    public class PrintEmailHandler : IHttpHandler, IRequiresSessionState
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

            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                {
                    HandleSend(context);
                }
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        private static void HandleSend(HttpContext context)
        {
            string filetype = (context.Request["filetype"] ?? "TS").Trim().ToUpperInvariant();
            if (filetype != "TS" && filetype != "ES")
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "filetype must be TS or ES." });
                return;
            }

            var names = ParseNames(context.Request["names"] ?? context.Request["name"]);
            if (names.Count == 0)
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Select at least one file." });
                return;
            }
            if (names.Count > 12)
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Email at most 12 files at a time." });
                return;
            }

            string projectCode = (context.Request["projectCode"] ?? "").Trim();
            if (string.IsNullOrEmpty(projectCode) && context.Session["defProject"] != null)
                projectCode = context.Session["defProject"].ToString();

            string schema = context.Session["s_schema"].ToString();
            string user = context.Session["s_user"].ToString();
            string cnstr = context.Session["s_cnString"].ToString();
            string userDir = context.Session["user_dir"].ToString();
            if (!userDir.EndsWith("\\") && !userDir.EndsWith("/"))
                userDir += "\\";

            string progDir = context.Session["prog_dir"] != null ? context.Session["prog_dir"].ToString() : "";
            string dbName = context.Session["db_name"] != null ? context.Session["db_name"].ToString() : "";
            if (string.IsNullOrEmpty(progDir) || string.IsNullOrEmpty(dbName))
            {
                context.Response.StatusCode = 500;
                WriteJson(context.Response, new { ok = false, error = "Session missing prog_dir or db_name." });
                return;
            }

            string mailTo = "";
            using (var cn = new OdbcConnection(cnstr))
            {
                cn.Open();
                mailTo = LookupEmail(cn, SourceTable(context), schema, user);
            }
            if (string.IsNullOrEmpty(mailTo))
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = "You do not have an e-mail address set up in MICS. Update Contact or ask FCSA to add one."
                });
                return;
            }

            var printed = new List<string>();
            var attachPaths = new StringBuilder();
            foreach (string name in names)
            {
                string err = PrintFileToUserDir(progDir, dbName, projectCode, userDir, filetype, name);
                if (err != null)
                {
                    context.Response.StatusCode = 500;
                    WriteJson(context.Response, new { ok = false, error = err, printed = printed.ToArray() });
                    return;
                }
                string outPath = Path.Combine(userDir, name + ".txt");
                printed.Add(name + ".txt");
                if (attachPaths.Length > 0) attachPaths.Append(';');
                attachPaths.Append(outPath);
            }

            var body = new StringBuilder();
            body.Append("The following ").Append(filetype).Append(" file(s) were printed to your MICS user directory\n");
            body.Append("and are attached. Delivery can take up to 20 minutes.\n\n");
            body.Append("Account: ").Append(schema).Append("\n");
            body.Append("User: ").Append(user).Append("\n\n");
            foreach (string f in printed)
                body.Append("  ").Append(f).Append("\n");

            string subject = "MICS " + filetype + " print files";
            if (subject.Length > 100) subject = subject.Substring(0, 100);

            bool queued = SesUtils.InsertEmailQueue(
                "mics@fcsa.ca",
                mailTo,
                null,
                subject,
                body.ToString(),
                attachPaths.ToString());

            if (!queued)
            {
                context.Response.StatusCode = 500;
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = "Printed files to your directory, but the email queue insert failed.",
                    printed = printed.ToArray()
                });
                return;
            }

            WriteJson(context.Response, new
            {
                ok = true,
                email = mailTo,
                filetype = filetype,
                files = printed.ToArray(),
                message = "Email queued. Delivery can take up to 20 minutes."
            });
        }

        private static string PrintFileToUserDir(string progDir, string dbName, string projectCode,
            string userDir, string filetype, string name)
        {
            string outfile = name + ".txt";
            string outPath = Path.Combine(userDir, outfile);
            try
            {
                if (File.Exists(outPath)) File.Delete(outPath);
            }
            catch (Exception ex)
            {
                return "Could not replace existing print file " + outfile + ": " + ex.Message;
            }

            var oLog = new dblogger(progDir + "sdfPrint");
            if (string.Equals(filetype, "ES", StringComparison.OrdinalIgnoreCase))
            {
                oLog.logprogram = progDir + "fePrint";
                oLog.logargs = dbName + " " + projectCode + " -o" + userDir + outfile + " " + name;
            }
            else
            {
                oLog.logprogram = progDir + "ftPrint";
                oLog.logargs = dbName + " " + projectCode + " -o" + userDir + outfile + " L " + name;
            }

            oLog = JobSubmit.SubmitJob(oLog, outfile, 0);
            oLog.Finish();

            if (oLog.logerrorcode == -98)
                return "Unable to start " + oLog.logprogram;
            if (oLog.logerrorcode != 0)
                return (oLog.logerrordesc ?? ("Print job error " + oLog.logerrorcode)) + " for " + name;

            switch (oLog.logreturncode)
            {
                case 0:
                    break;
                case 1:
                    return "Could not open connection to database for " + name;
                case 2:
                    return "Could not determine default schema for " + name;
                case 3:
                    return "No default schema specified for " + name;
                case 7:
                    return "Print/export failed for " + name;
                case 99:
                    return "Fatal error printing " + name;
                case 100:
                    return "The database is currently locked - please try again later.";
                default:
                    return "Print returned code " + oLog.logreturncode + " for " + name;
            }

            if (!File.Exists(outPath))
                return "Print finished but " + outfile + " was not written to your directory.";
            return null;
        }

        private static List<string> ParseNames(string raw)
        {
            var names = new List<string>();
            if (string.IsNullOrWhiteSpace(raw)) return names;
            foreach (string part in raw.Split(new[] { ',', ';', '\n', '\r', ' ' }, StringSplitOptions.RemoveEmptyEntries))
            {
                string name = part.Trim();
                if (name.EndsWith(".txt", StringComparison.OrdinalIgnoreCase))
                    name = name.Substring(0, name.Length - 4);
                if (!ValidName.IsMatch(name)) continue;
                bool dup = false;
                foreach (string existing in names)
                {
                    if (string.Equals(existing, name, StringComparison.OrdinalIgnoreCase)) { dup = true; break; }
                }
                if (!dup) names.Add(name);
            }
            return names;
        }

        private static string SourceTable(HttpContext context)
        {
            string site = "";
            if (context.Session["SiteName"] != null) site = context.Session["SiteName"].ToString();
            else if (context.Session["siteName"] != null) site = context.Session["siteName"].ToString();
            if (site.IndexOf("remicsdev", StringComparison.OrdinalIgnoreCase) >= 0
                || site.IndexOf("micstest", StringComparison.OrdinalIgnoreCase) >= 0)
                return "adm.pcn_account_details";
            return "adm.account_details";
        }

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
