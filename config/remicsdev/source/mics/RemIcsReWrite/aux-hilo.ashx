<%@ WebHandler Language="C#" Class="RemIcsReWrite.AuxHiloHandler" %>

using System;
using System.Data.Odbc;
using System.IO;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using DBAccess;
using JobSubmission;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>Check Band HiLo Frequencies  -  parity with auxengmenu/AUXHilo1.</summary>
    public class AuxHiloHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly Regex NameOk = new Regex(@"^[A-Za-z0-9_]{1,16}$", RegexOptions.Compiled);

        public bool IsReusable { get { return false; } }

        public void ProcessRequest(HttpContext context)
        {
            var response = context.Response;
            response.ContentType = "application/json; charset=utf-8";
            response.Cache.SetCacheability(HttpCacheability.NoCache);

            if (context.Session == null || context.Session["s_cnString"] == null
                || context.Session["s_schema"] == null || context.Session["s_user"] == null
                || context.Session["prog_dir"] == null || context.Session["db_name"] == null
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
                    HandleRun(context);
                }
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        private static void HandleRun(HttpContext context)
        {
            // W3-4: classic AUXHilo1 incorrectly logged AUXGenCTX; use distinct HiLo code.
            SesUtils.LogMenuUse("AUXHiLo");

            string name = (context.Request["name"] ?? "").Trim();
            if (!NameOk.IsMatch(name))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "You must select one of the proposed files." });
                return;
            }

            string schema = context.Session["s_schema"].ToString().Trim();
            if (!OwnTsFile(context, schema, name))
            {
                WriteJson(context.Response, new { ok = false, error = "TS file not found for this company." });
                return;
            }

            int nDist = 5;
            int parsed;
            string distNote = "";
            if (!int.TryParse((context.Request["dist"] ?? "").Trim(), out parsed) || parsed < 0)
            {
                distNote = "Incorrect distance. A distance of 5 seconds of latitude will be used.";
                nDist = 5;
            }
            else
            {
                nDist = parsed;
            }

            var oLog = new dblogger(context.Session["prog_dir"].ToString() + "hilocheck");
            string cOut = context.Session["user_dir"].ToString() + "p" + oLog.logserial + OELSupport.ACfileext();
            oLog.logargs = context.Session["db_name"].ToString() + " " + name +
                " /m:" + nDist.ToString() + " /o:" + cOut;

            oLog = JobSubmit.SubmitJob(oLog, " ", 90);
            if (oLog.Finish() != 0)
            {
                WriteJson(context.Response, new { ok = false, error = "The hilocheck program failed" });
                return;
            }

            switch (oLog.logerrorcode)
            {
                case 0:
                    break;
                case -99:
                    WriteJson(context.Response, new { ok = false, error = "The hilocheck program timed out." });
                    return;
                case -98:
                    WriteJson(context.Response, new { ok = false, error = "Could not start the hilocheck program" });
                    return;
                default:
                    string desc = oLog.logerrordesc != null ? oLog.logerrordesc.Trim() : "";
                    WriteJson(context.Response, new
                    {
                        ok = false,
                        error = desc.Length > 0 ? desc : "The hilocheck program failed"
                    });
                    return;
            }

            string prnName = "p" + oLog.logserial + OELSupport.ACfileext();
            string htmName = "p" + oLog.logserial + ".htm";
            OELSupport.copy_html(prnName, htmName);

            string html = "";
            string htmPath = context.Session["user_dir"].ToString() + htmName;
            if (File.Exists(htmPath))
                html = File.ReadAllText(htmPath);
            else if (File.Exists(cOut))
                html = "<pre>" + File.ReadAllText(cOut) + "</pre>";

            WriteJson(context.Response, new
            {
                ok = true,
                note = distNote,
                serial = oLog.logserial,
                html = html
            });
        }

        private static bool OwnTsFile(HttpContext context, string schema, string name)
        {
            string table = "ft_" + name + "_titl";
            string sql = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE table_schema = '" +
                         schema.Replace("'", "''") + "' AND table_name = '" + table.Replace("'", "''") + "'";
            using (var cn = new OdbcConnection(context.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                {
                    return Convert.ToInt32(cmd.ExecuteScalar()) > 0;
                }
            }
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            var ser = new JavaScriptSerializer();
            ser.MaxJsonLength = int.MaxValue;
            response.Write(ser.Serialize(obj));
        }
    }
}
