<%@ WebHandler Language="C#" Class="RemIcsReWrite.DbUpdateHandler" %>

using System;
using System.Data.Odbc;
using System.IO;
using System.Net.Mail;
using System.Text;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using DBAccess;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>
    /// DbUpdate gate + email notify  -  parity with Tpcnmenu/DbUpdate.aspx (not the batch export itself).
    /// GET  ?name=&amp;filetype=TS → validation flag gate
    /// POST name, filetype, userFcsa → EMAIL_Click equivalent
    /// </summary>
    public class DbUpdateHandler : IHttpHandler, IRequiresSessionState
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
                || context.Session["s_schema"] == null || context.Session["s_user"] == null)
            {
                response.StatusCode = 401;
                WriteJson(response, new { ok = false, error = "Session not initialized." });
                return;
            }

            if (string.Equals(request.HttpMethod, "GET", StringComparison.OrdinalIgnoreCase))
            {
                HandleGate(context);
                return;
            }

            if (string.Equals(request.HttpMethod, "POST", StringComparison.OrdinalIgnoreCase))
            {
                HandleNotify(context);
                return;
            }

            response.StatusCode = 405;
            WriteJson(response, new { ok = false, error = "GET or POST required." });
        }

        private static void HandleGate(HttpContext context)
        {
            string name = (context.Request.QueryString["name"] ?? "").Trim();
            string filetype = (context.Request.QueryString["filetype"] ?? "TS").Trim().ToUpperInvariant();
            if (!ValidName.IsMatch(name))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Invalid file name." });
                return;
            }
            if (filetype != "TS" && filetype != "ES")
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "filetype must be TS or ES." });
                return;
            }

            string schema = context.Session["s_schema"].ToString();
            int tableType = filetype == "ES" ? 5 : 0;
            string validated = UserTable.GetUserValidFlag(schema, tableType, name);

            string errorcode = "0";
            string errortext = "";
            bool allowTransfer = true;

            if (string.IsNullOrEmpty(validated))
            {
                errorcode = "1";
                errortext = "Unable to read validation status for this file.";
                allowTransfer = false;
            }
            else
            {
                switch (validated)
                {
                    case "U":
                    case "M":
                        errortext = "";
                        break;
                    case "P":
                        errortext = "Already Posted";
                        break;
                    case "T":
                        errorcode = "1";
                        errortext = "Validated only for a TSIP run, contains temporary codes";
                        allowTransfer = false;
                        break;
                    case "S":
                        errortext = "Validated, contains data belonging to another operator";
                        break;
                    case "N":
                        errorcode = "1";
                        errortext = "Not Validated or failed Validate";
                        allowTransfer = false;
                        break;
                    case "L":
                        errorcode = "1";
                        errortext = "At least one end of hop missing from file, contains temporary codes";
                        allowTransfer = false;
                        break;
                    case "K":
                        errortext = "At least one end of hop missing from file, contains data belonging to another operator, contains temporary codes";
                        break;
                    default:
                        errorcode = "1";
                        errortext = "Unknown error";
                        allowTransfer = false;
                        break;
                }
            }

            WriteJson(context.Response, new
            {
                ok = true,
                name = name,
                filetype = filetype,
                validated = validated ?? "",
                errorcode = errorcode,
                errortext = errortext,
                allowTransfer = allowTransfer,
                userUpdate = false
            });
        }

        private static void HandleNotify(HttpContext context)
        {
            string name = (context.Request.Form["name"] ?? "").Trim();
            string filetype = (context.Request.Form["filetype"] ?? "TS").Trim().ToUpperInvariant();
            string userFcsa = (context.Request.Form["userFcsa"] ?? "F").Trim().ToUpperInvariant();
            if (userFcsa != "U") userFcsa = "F";

            if (!ValidName.IsMatch(name))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Invalid file name." });
                return;
            }

            string schema = context.Session["s_schema"].ToString();
            string user = context.Session["s_user"].ToString();
            string cnstr = context.Session["s_cnString"].ToString();

            string strFrom = "";
            try
            {
                using (var cn = new OdbcConnection(cnstr))
                {
                    cn.Open();
                    strFrom = LookupEmail(cn, SourceTable(context), schema, user);
                }
            }
            catch (Exception ex)
            {
                context.Response.StatusCode = 500;
                WriteJson(context.Response, new { ok = false, error = "ERRORSQL: email lookup: " + ex.Message });
                return;
            }

            if (string.IsNullOrEmpty(strFrom))
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = "You do not have an e-mail address set up in the Mics database. Please contact FCSA to have one added."
                });
                return;
            }

            string dbgfile = context.Application["web_drive"].ToString() + "\\extractlogs\\" + user + "PCNDbUpdate.txt";
            bool emailOk = false;
            try
            {
                using (var sw = new StreamWriter(dbgfile, true))
                {
                    sw.WriteLine("LOGTIME:" + DateTime.Now.ToString("yyyyMMddHHmmss.ffff"));
                    sw.WriteLine("RemIcsReWrite/dbupdate.ashx notify");

                    var message = new MailMessage();
                    var maSender = new MailAddress(strFrom);
                    message.CC.Add(maSender);
                    message.Subject = "Database Update Request for " + filetype + " file " + name;

                    var updateText = new StringBuilder("", 1000);
                    updateText.Append("The " + filetype + " file " + name);
                    if (userFcsa == "U")
                        updateText.Append(" has been submitted for user update of MICS by\n\n");
                    else
                        updateText.Append(" has been released for FCSA update of MICS by\n\n");
                    updateText.Append("ACCOUNT ID: " + schema + "\n\n");
                    updateText.Append("USER ID: " + user + "\n\n");
                    message.Body = updateText.ToString();

                    sw.WriteLine("Subject: " + message.Subject);
                    sw.WriteLine("Body: " + message.Body);
                    emailOk = SesUtils.send_email_message2(message, 1, false);
                    sw.WriteLine(emailOk ? "Email sent" : "Email failed");
                }

                bool queueOk = false;
                string stagingFile = null;
                string stagingPath = null;
                try
                {
                    FindNewestStagingExport(user, name, filetype, out stagingFile, out stagingPath);
                    if (!string.IsNullOrEmpty(stagingFile) && !string.IsNullOrEmpty(stagingPath))
                        queueOk = SesUtils.InsertUpdateQueue(stagingFile, stagingPath, user, name, filetype, strFrom);
                }
                catch { /* do not fail notify on queue insert */ }

                using (var sw2 = new StreamWriter(dbgfile, true))
                {
                    sw2.WriteLine("UpdateQueue:" + (queueOk ? "OK" : "skip/fail") + " file=" + (stagingFile ?? ""));
                }
            }
            catch (Exception ex)
            {
                context.Response.StatusCode = 500;
                WriteJson(context.Response, new { ok = false, error = "Email send error: " + ex.Message });
                return;
            }

            // W2-4: transfer may succeed while notify fails — never claim "complete" alone.
            string message;
            if (!emailOk)
            {
                message = userFcsa == "U"
                    ? "Database update transfer succeeded, but notification email failed. See extractlogs."
                    : "Transfer for database update succeeded, but notification email failed. See extractlogs.";
            }
            else
            {
                message = userFcsa == "U"
                    ? "Database update complete."
                    : "Transfer for database update complete.";
            }

            WriteJson(context.Response, new
            {
                ok = true,
                emailSent = emailOk,
                userFcsa = userFcsa,
                message = message
            });
        }

        private static void FindNewestStagingExport(string user, string pdfName, string filetype, out string stagingFile, out string stagingPath)
        {
            stagingFile = null;
            stagingPath = null;
            string primaryRoot = @"D:\updates\primary";
            string searchDir = string.Equals(filetype, "ES", StringComparison.OrdinalIgnoreCase)
                ? Path.Combine(primaryRoot, "UnprocessedESFiles")
                : primaryRoot;
            if (!Directory.Exists(searchDir)) return;

            string prefix = user + "_";
            string suffix = "_" + pdfName + ".txt";
            FileInfo newest = null;
            foreach (string path in Directory.GetFiles(searchDir, "*.txt"))
            {
                string fn = Path.GetFileName(path);
                if (!fn.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) continue;
                if (!fn.EndsWith(suffix, StringComparison.OrdinalIgnoreCase)) continue;
                var fi = new FileInfo(path);
                if (newest == null || fi.LastWriteTimeUtc > newest.LastWriteTimeUtc)
                    newest = fi;
            }
            if (newest != null)
            {
                stagingFile = newest.Name;
                stagingPath = newest.FullName;
            }
        }

        /// <summary>
        /// Same lookup order as PCN / Contact: remicsdev uses pcn_account_details,
        /// then dbo.t_UserDetails if adm email is blank.
        /// </summary>
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
