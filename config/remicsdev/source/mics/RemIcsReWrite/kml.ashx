<%@ WebHandler Language="C#" Class="RemIcsReWrite.KmlHandler" %>

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
using KmlUtilities;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>
    /// TS file KML export  -  parity with Ttsmenu/tsPdfKml.aspx (build + email).
    /// POST action=export  name=  reptype=V
    /// </summary>
    public class KmlHandler : IHttpHandler, IRequiresSessionState
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

            string action = (request["action"] ?? request.QueryString["action"] ?? "export").Trim().ToLowerInvariant();
            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                {
                    if (action == "export") HandleExport(context);
                    else
                    {
                        response.StatusCode = 400;
                        WriteJson(response, new { ok = false, error = "action must be export" });
                    }
                }
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        private static void HandleExport(HttpContext context)
        {
            string name = (context.Request["name"] ?? context.Request["kmlName"] ?? "").Trim();
            if (!ValidName.IsMatch(name))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Invalid file name." });
                return;
            }
            string reptype = (context.Request["reptype"] ?? "V").Trim().ToUpperInvariant();
            if (reptype.Length == 0) reptype = "V";

            string statusinfo;
            string reportlist;
            if (!KmlUtils.build_kml(name, reptype, out statusinfo, out reportlist))
            {
                WriteJson(context.Response, new { ok = false, error = statusinfo ?? "KML build failed" });
                return;
            }

            string emailError;
            if (!MailReports(context, name, reptype, reportlist ?? "", out emailError))
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = emailError,
                    status = statusinfo ?? ""
                });
                return;
            }

            WriteJson(context.Response, new
            {
                ok = true,
                emailed = true,
                status = statusinfo ?? "",
                reports = reportlist ?? ""
            });
        }

        private static bool MailReports(HttpContext context, string pdfname, string reptype, string reportlist, out string error)
        {
            error = "";
            string schema = context.Session["s_schema"].ToString();
            string user = context.Session["s_user"].ToString();
            string userDir = context.Session["user_dir"].ToString();

            string email = LookupEmail(context, schema, user);
            if (string.IsNullOrEmpty(email))
            {
                error = "You do not have an e-mail address set up in the Mics database. Please contact FCSA to have one added.";
                return false;
            }

            var msg = new MailMessage();
            try
            {
                msg.To.Add(new MailAddress(email));
                msg.From = new MailAddress("mics@fcsa.ca");
                if (reptype == "H")
                {
                    msg.Body = "Attached please find the combined KML file from PDF " + pdfname;
                    msg.Subject = " Horizontal KML file for PDF " + pdfname;
                }
                else
                {
                    msg.Body = "Attached please find KML file from PDF " + pdfname;
                    msg.Subject = " KML file for PDF " + pdfname;
                }

                string[] flist = reportlist.Split(';');
                int attached = 0;
                for (int i = 0; i < flist.Length - 1; i++)
                {
                    string path = Path.Combine(userDir, flist[i]);
                    if (File.Exists(path))
                    {
                        msg.Attachments.Add(new Attachment(path));
                        attached++;
                    }
                }

                // W0-3: never claim email success with zero KML attachments.
                if (attached == 0)
                {
                    error = "No KML files were available to email. The build may have failed to write report files.";
                    return false;
                }

                if (!SesUtils.send_email_message2(msg, 0, false))
                {
                    error = "System error sending email";
                    return false;
                }

                for (int i = 0; i < flist.Length - 1; i++)
                {
                    string path = Path.Combine(userDir, flist[i]);
                    try { if (File.Exists(path)) File.Delete(path); } catch { /* ignore */ }
                }
                return true;
            }
            catch (Exception ex)
            {
                error = "System error adding cclist, body or attachment to email\n" + ex.Message;
                return false;
            }
            finally
            {
                msg.Dispose();
            }
        }

        private static string LookupEmail(HttpContext context, string ultrixid, string micsid)
        {
            string sourceTable = "adm.account_details";
            string site = "";
            if (context.Session["SiteName"] != null) site = context.Session["SiteName"].ToString();
            else if (context.Session["siteName"] != null) site = context.Session["siteName"].ToString();
            if (site.IndexOf("remicsdev", StringComparison.OrdinalIgnoreCase) >= 0
                || site.IndexOf("micstest", StringComparison.OrdinalIgnoreCase) >= 0)
                sourceTable = "adm.pcn_account_details";

            string cnstr = context.Session["s_cnString"].ToString();
            try
            {
                using (var cn = new OdbcConnection(cnstr))
                {
                    cn.Open();
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
                }
            }
            catch
            {
                return "";
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
