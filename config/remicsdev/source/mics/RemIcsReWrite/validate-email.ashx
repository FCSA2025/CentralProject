<%@ WebHandler Language="C#" Class="RemIcsReWrite.ValidateEmailHandler" %>

using System;
using System.Data.Odbc;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>
    /// Email the existing validate report ({name}.txt in user_dir) to the user's Contact email.
    /// Does not re-run validate or reformat the file.
    /// POST name
    /// </summary>
    public class ValidateEmailHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly Regex ValidName = new Regex(@"^[A-Za-z0-9_]{1,16}$", RegexOptions.Compiled);

        public bool IsReusable { get { return false; } }

        public void ProcessRequest(HttpContext context)
        {
            var response = context.Response;
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
            string name = (context.Request["name"] ?? "").Trim();
            if (name.EndsWith(".txt", StringComparison.OrdinalIgnoreCase))
                name = name.Substring(0, name.Length - 4);
            if (!ValidName.IsMatch(name))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Invalid file name." });
                return;
            }

            string schema = context.Session["s_schema"].ToString();
            string user = context.Session["s_user"].ToString();
            string cnstr = context.Session["s_cnString"].ToString();
            string userDir = context.Session["user_dir"].ToString();
            if (!userDir.EndsWith("\\") && !userDir.EndsWith("/"))
                userDir += "\\";

            string outPath = Path.Combine(userDir, name + ".txt");
            if (!File.Exists(outPath))
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = "Validate report not found. Run Validate first, then Email Results."
                });
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

            var body = new StringBuilder();
            body.Append("Your MICS validate report is attached.\n\n");
            body.Append("Account: ").Append(schema).Append("\n");
            body.Append("User: ").Append(user).Append("\n");
            body.Append("File: ").Append(name).Append(".txt\n\n");
            body.Append("Delivery can take up to 20 minutes.\n");

            string subject = "MICS validate report: " + name;
            if (subject.Length > 100) subject = subject.Substring(0, 100);

            bool queued = SesUtils.InsertEmailQueue(
                "mics@fcsa.ca",
                mailTo,
                null,
                subject,
                body.ToString(),
                outPath);

            if (!queued)
            {
                context.Response.StatusCode = 500;
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = "Could not queue the validate report email."
                });
                return;
            }

            WriteJson(context.Response, new
            {
                ok = true,
                email = mailTo,
                file = name + ".txt",
                message = "Validate report emailed to " + mailTo + ". Delivery can take up to 20 minutes."
            });
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
