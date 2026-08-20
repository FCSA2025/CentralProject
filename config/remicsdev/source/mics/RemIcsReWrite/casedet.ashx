<%@ WebHandler Language="C#" Class="RemIcsReWrite.CaseDetHandler" %>

using System;
using System.Collections.Generic;
using System.Data.Odbc;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using DBUtilities;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>
    /// Phase 6.75  -  CASEDET run list + classic CSV/KML generator URLs (Ttsipmenu CASEDET*).
    /// </summary>
    public class CaseDetHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly JavaScriptSerializer Ser = new JavaScriptSerializer();

        public bool IsReusable { get { return false; } }

        public void ProcessRequest(HttpContext context)
        {
            var response = context.Response;
            response.ContentType = "application/json; charset=utf-8";
            response.Cache.SetCacheability(HttpCacheability.NoCache);

            if (context.Session == null || context.Session["s_cnString"] == null
                || context.Session["s_schema"] == null)
            {
                response.StatusCode = 401;
                WriteJson(response, new { ok = false, error = "Session not initialized." });
                return;
            }

            string action = (context.Request["action"] ?? "list").Trim().ToLowerInvariant();
            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                {
                    if (action == "list") ListRuns(context);
                    else if (action == "url") BuildUrl(context);
                    else
                    {
                        response.StatusCode = 400;
                        WriteJson(response, new { ok = false, error = "action must be list|url" });
                    }
                }
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        private static void ListRuns(HttpContext ctx)
        {
            string mode = (ctx.Request["mode"] ?? "TSES").Trim().ToUpperInvariant();
            bool tsEs = mode != "TSTS";
            string likePat = tsEs ? "te_%_chan" : "tt_%_chan";
            string schema = ctx.Session["s_schema"].ToString();
            var runs = new List<object>();
            string sql = "SELECT RTRIM(table_name) FROM INFORMATION_SCHEMA.TABLES WHERE table_schema = '" +
                         schema.Replace("'", "''") + "' AND RTRIM(table_name) LIKE '" +
                         likePat.Replace("_", "\\_") + "' ESCAPE '\\' ORDER BY table_name";
            // Simpler LIKE without escape for SQL Server:
            sql = "SELECT RTRIM(table_name) FROM INFORMATION_SCHEMA.TABLES WHERE table_schema = '" +
                  schema.Replace("'", "''") + "' AND table_name LIKE '" +
                  (tsEs ? "te\\_%\\_chan" : "tt\\_%\\_chan") + "' ESCAPE '\\' ORDER BY table_name";

            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        string tname = Convert.ToString(dr.GetValue(0)) ?? "";
                        string[] parts = tname.Split('_');
                        if (parts.Length < 4) continue;
                        // te|tt _{parm...}_{run}_chan
                        string parm = parts[1];
                        for (int i = 2; i < parts.Length - 2; i++)
                            parm += "_" + parts[i];
                        string run = parts[parts.Length - 2];
                        runs.Add(new { parm = parm, run = run, table = tname, label = parm + " - " + run });
                    }
                }
            }
            WriteJson(ctx.Response, new { ok = true, mode = mode, runs = runs });
        }

        private static void BuildUrl(HttpContext ctx)
        {
            string mode = (ctx.Request["mode"] ?? "TSES").Trim().ToUpperInvariant();
            string kind = (ctx.Request["kind"] ?? "csv").Trim().ToLowerInvariant(); // csv|kml
            string parm = (ctx.Request["parm"] ?? "").Trim();
            string run = (ctx.Request["run"] ?? "").Trim();
            string reptype = (ctx.Request["reptype"] ?? "G").Trim().ToUpperInvariant(); // G|C for KML
            if (string.IsNullOrEmpty(parm) || string.IsNullOrEmpty(run))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "parm and run required." });
                return;
            }

            bool tsEs = mode != "TSTS";
            string prefix = tsEs ? "te_" : "tt_";
            string schema = ctx.Session["s_schema"].ToString();
            string parmTable = schema + "." + prefix + parm + "_" + run + "_parm";
            string pdf = "";
            string protype = "T";
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                string sql = "SELECT proname, protype FROM " + parmTable;
                try
                {
                    using (var cmd = new OdbcCommand(sql, cn))
                    using (var dr = cmd.ExecuteReader())
                    {
                        if (dr.Read())
                        {
                            pdf = (Convert.ToString(dr.GetValue(0)) ?? "").Trim();
                            protype = (Convert.ToString(dr.GetValue(1)) ?? "T").Trim();
                        }
                    }
                }
                catch (Exception ex)
                {
                    WriteJson(ctx.Response, new { ok = false, error = "Parm table not found: " + ex.Message });
                    return;
                }
            }

            string tsip = parm + "_" + run;
            string page;
            string qs;
            if (kind == "kml")
            {
                page = tsEs ? "CASEDETTSESkml.aspx" : "CASEDETTSTSkml.aspx";
                qs = "pdf=" + Uri.EscapeDataString(pdf) + "&tsip=" + Uri.EscapeDataString(tsip) +
                     "&reptype=" + Uri.EscapeDataString(reptype);
                if (tsEs) qs += "&protype=" + Uri.EscapeDataString(protype);
            }
            else
            {
                page = tsEs ? "CASEDETTSEScsv.aspx" : "CASEDETTSTScsv.aspx";
                qs = "pdf=" + Uri.EscapeDataString(pdf) + "&tsip=" + Uri.EscapeDataString(tsip);
                if (tsEs) qs += "&protype=" + Uri.EscapeDataString(protype);
            }

            string url = "../Ttsipmenu/" + page + "?" + qs;
            WriteJson(ctx.Response, new
            {
                ok = true,
                url = url,
                pdf = pdf,
                tsip = tsip,
                protype = protype,
                page = page
            });
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            response.Write(Ser.Serialize(obj));
        }
    }
}
