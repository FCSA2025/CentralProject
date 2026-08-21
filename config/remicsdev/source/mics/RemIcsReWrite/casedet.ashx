<%@ WebHandler Language="C#" Class="RemIcsReWrite.CaseDetHandler" %>
<%@ Assembly Src="CaseDetCsv.cs" %>
<%@ Assembly Src="CaseDetKml.cs" %>

using System;
using System.Collections.Generic;
using System.Data.Odbc;
using System.IO;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>
    /// CASEDET run list + in-shell CSV/KML generation (no Ttsipmenu wrap).
    /// </summary>
    public class CaseDetHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly JavaScriptSerializer Ser = new JavaScriptSerializer();
        private static readonly Regex Ident = new Regex(@"^[A-Za-z0-9_]{1,64}$", RegexOptions.Compiled);
        private static readonly Regex DownloadName = new Regex(@"^[A-Za-z0-9_.\-]+\.(csv|kml)$", RegexOptions.IgnoreCase | RegexOptions.Compiled);

        public bool IsReusable { get { return false; } }

        public void ProcessRequest(HttpContext context)
        {
            var response = context.Response;
            response.Cache.SetCacheability(HttpCacheability.NoCache);

            if (context.Session == null || context.Session["s_cnString"] == null
                || context.Session["s_schema"] == null)
            {
                response.ContentType = "application/json; charset=utf-8";
                response.StatusCode = 401;
                WriteJson(response, new { ok = false, error = "Session not initialized." });
                return;
            }

            string action = (context.Request["action"] ?? "list").Trim().ToLowerInvariant();
            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                {
                    if (action == "list")
                    {
                        response.ContentType = "application/json; charset=utf-8";
                        ListRuns(context);
                    }
                    else if (action == "generate")
                    {
                        response.ContentType = "application/json; charset=utf-8";
                        Generate(context);
                    }
                    else if (action == "download")
                    {
                        Download(context);
                    }
                    else
                    {
                        response.ContentType = "application/json; charset=utf-8";
                        response.StatusCode = 400;
                        WriteJson(response, new { ok = false, error = "action must be list|generate|download" });
                    }
                }
            }
            catch (Exception ex)
            {
                if (action == "download") throw;
                response.ContentType = "application/json; charset=utf-8";
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        private static void ListRuns(HttpContext ctx)
        {
            string mode = (ctx.Request["mode"] ?? "TSES").Trim().ToUpperInvariant();
            bool tsEs = mode != "TSTS";
            string schema = ctx.Session["s_schema"].ToString();
            var runs = new List<object>();
            string sql = "SELECT RTRIM(table_name) FROM INFORMATION_SCHEMA.TABLES WHERE table_schema = '" +
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

        private static void Generate(HttpContext ctx)
        {
            string mode = (ctx.Request["mode"] ?? "TSES").Trim().ToUpperInvariant();
            string kind = (ctx.Request["kind"] ?? "csv").Trim().ToLowerInvariant();
            string parm = (ctx.Request["parm"] ?? "").Trim();
            string run = (ctx.Request["run"] ?? "").Trim();
            string reptype = (ctx.Request["reptype"] ?? "G").Trim().ToUpperInvariant();
            if (mode != "TSTS") mode = "TSES";
            if (kind != "kml") kind = "csv";
            if (reptype != "C") reptype = "G";
            if (!Ident.IsMatch(parm) || !Ident.IsMatch(run))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "parm and run required." });
                return;
            }

            try
            {
                SesUtils.LogMenuUse(MenuUse(mode, kind));
            }
            catch { }

            string pdf;
            string protype;
            string lookupError;
            if (!LookupParm(ctx, mode, parm, run, out pdf, out protype, out lookupError))
            {
                WriteJson(ctx.Response, new { ok = false, error = lookupError });
                return;
            }

            string tsip = parm + "_" + run;
            if (kind == "kml")
            {
                CaseDetKmlResult k = CaseDetKml.Generate(ctx, mode, pdf, tsip, protype, reptype);
                WriteJson(ctx.Response, new
                {
                    ok = k.ok,
                    error = k.error,
                    message = k.message,
                    emailed = k.emailed,
                    files = k.files,
                    tsip = tsip,
                    kind = "kml"
                });
                return;
            }

            CaseDetCsvResult c = CaseDetCsv.Generate(ctx, mode, pdf, tsip, protype);
            WriteJson(ctx.Response, new
            {
                ok = c.ok,
                error = c.error,
                message = c.message,
                files = c.files,
                tsip = tsip,
                kind = "csv"
            });
        }

        private static void Download(HttpContext ctx)
        {
            string name = (ctx.Request["file"] ?? "").Trim();
            if (!DownloadName.IsMatch(name))
            {
                ctx.Response.StatusCode = 400;
                ctx.Response.ContentType = "text/plain; charset=utf-8";
                ctx.Response.Write("Invalid file name.");
                return;
            }
            if (ctx.Session["user_dir"] == null)
            {
                ctx.Response.StatusCode = 401;
                ctx.Response.ContentType = "text/plain; charset=utf-8";
                ctx.Response.Write("Session not initialized.");
                return;
            }
            string path = Path.Combine(ctx.Session["user_dir"].ToString(), name);
            if (!File.Exists(path))
            {
                ctx.Response.StatusCode = 404;
                ctx.Response.ContentType = "text/plain; charset=utf-8";
                ctx.Response.Write("File not found.");
                return;
            }
            string mime = name.EndsWith(".kml", StringComparison.OrdinalIgnoreCase)
                ? "application/vnd.google-earth.kml+xml"
                : "text/csv";
            ctx.Response.ContentType = mime;
            ctx.Response.AppendHeader("Content-Disposition", "attachment; filename=\"" + name + "\"");
            ctx.Response.TransmitFile(path);
        }

        private static bool LookupParm(HttpContext ctx, string mode, string parm, string run,
            out string pdf, out string protype, out string error)
        {
            pdf = "";
            protype = "T";
            error = "";
            bool tsEs = mode != "TSTS";
            string schema = ctx.Session["s_schema"].ToString();
            string parmTable = schema + "." + (tsEs ? "te_" : "tt_") + parm + "_" + run + "_parm";
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                try
                {
                    using (var cmd = new OdbcCommand("SELECT proname, protype FROM " + parmTable, cn))
                    using (var dr = cmd.ExecuteReader())
                    {
                        if (!dr.Read())
                        {
                            error = "Parm table not found.";
                            return false;
                        }
                        pdf = (Convert.ToString(dr.GetValue(0)) ?? "").Trim();
                        protype = (Convert.ToString(dr.GetValue(1)) ?? "T").Trim();
                        return true;
                    }
                }
                catch (Exception ex)
                {
                    error = "Parm table not found: " + ex.Message;
                    return false;
                }
            }
        }

        private static string MenuUse(string mode, string kind)
        {
            if (mode == "TSTS")
                return kind == "kml" ? "TSIP_TS_TS_KML" : "TSIP_TS_TS_CSV";
            return kind == "kml" ? "TSIP_TS_ES_KML" : "TSIP_TS_ES_CSV";
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            response.Write(Ser.Serialize(obj));
        }
    }
}
