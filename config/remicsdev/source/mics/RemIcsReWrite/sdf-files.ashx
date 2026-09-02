<%@ WebHandler Language="C#" Class="RemIcsReWrite.SdfFilesHandler" %>

using System;
using System.Collections.Generic;
using System.Data.Odbc;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using SesUtilities;
using ErrorUtilities;

namespace RemIcsReWrite
{
    /// <summary>Phase 6.75  -  SDF master file lists (su_%_{suffix}).</summary>
    public class SdfFilesHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly Dictionary<string, string> Suffix = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            { "Ante", "ante" }, { "Band", "band" }, { "Ctx", "ctx_" }, { "Eqpt", "eqpt" },
            { "Oper", "oper" }, { "Plan", "plan" }, { "Rout", "rout" }, { "Note", "note" },
            { "Towr", "towr" }, { "Town", "town" }, { "Traf", "traf" }
        };

        public bool IsReusable { get { return false; } }

        public void ProcessRequest(HttpContext context)
        {
            var response = context.Response;
            response.ContentType = "application/json; charset=utf-8";
            response.Cache.SetCacheability(HttpCacheability.NoCache);

            if (context.Session == null || context.Session["s_cnString"] == null || context.Session["s_schema"] == null)
            {
                response.StatusCode = 401;
                WriteJson(response, new { ok = false, error = "Session not initialized." });
                return;
            }

            string type = (context.Request["type"] ?? "Ante").Trim();
            string suffix;
            if (!Suffix.TryGetValue(type, out suffix))
            {
                response.StatusCode = 400;
                WriteJson(response, new { ok = false, error = "type must be Ante|Band|Ctx|Eqpt|Oper|Plan|Rout|Note|Towr|Town|Traf" });
                return;
            }

            string schema = context.Session["s_schema"].ToString();
            // Escape suffix for LIKE so Ctx "ctx_" is literal (not "_ = any char", which also matched ctxd).
            string likeSuffix = suffix.Replace("\\", "\\\\").Replace("%", "\\%").Replace("_", "\\_");
            string likePat = "su\\_%\\_" + likeSuffix;
            var files = new List<object>();
            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                using (var cn = new OdbcConnection(context.Session["s_cnString"].ToString()))
                {
                    cn.Open();
                    string sql = "SELECT RTRIM(table_name) FROM INFORMATION_SCHEMA.TABLES WHERE table_schema='" +
                                 schema.Replace("'", "''") + "' AND table_name LIKE '" + likePat +
                                 "' ESCAPE '\\' ORDER BY table_name";
                    using (var cmd = new OdbcCommand(sql, cn))
                    using (var dr = cmd.ExecuteReader())
                    {
                        while (dr.Read())
                        {
                            string t = Convert.ToString(dr.GetValue(0)) ?? "";
                            // su_{name}_{suffix}
                            if (t.Length > 3 + suffix.Length + 1)
                            {
                                string fname = t.Substring(3, t.Length - 3 - suffix.Length - 1);
                                files.Add(new { name = fname, type = type, table = t });
                            }
                        }
                    }
                }
                WriteJson(response, new { ok = true, type = type, files = files });
            }
            catch (Exception ex)
            {
                // W4-13: no exception text to client.
                try { ErrorUtils.NotifySystemOps(ex, "sdf-files"); } catch { }
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = "SDF file list request failed." });
            }
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            response.Write(new JavaScriptSerializer().Serialize(obj));
        }
    }
}
