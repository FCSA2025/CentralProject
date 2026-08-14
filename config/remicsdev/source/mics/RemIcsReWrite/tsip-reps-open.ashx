<%@ WebHandler Language="C#" Class="RemIcsReWrite.TsipRepsOpenHandler" %>

using System;
using System.Collections.Generic;
using System.Data.Odbc;
using System.IO;
using System.Text;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>
    /// Open a TSIP report for browser display — disk file (classic CopyToTxt) or archive lines.
    /// </summary>
    public class TsipRepsOpenHandler : IHttpHandler, IRequiresSessionState
    {
        public bool IsReusable { get { return false; } }

        public void ProcessRequest(HttpContext context)
        {
            var response = context.Response;
            response.ContentType = "application/json; charset=utf-8";
            response.Cache.SetCacheability(HttpCacheability.NoCache);

            if (context.Session == null || context.Session["s_cnString"] == null
                || context.Session["s_user"] == null || context.Session["user_dir"] == null)
            {
                response.StatusCode = 401;
                WriteJson(response, new { ok = false, error = "Session not initialized." });
                return;
            }

            string user = context.Session["s_user"].ToString();
            string cnstr = context.Session["s_cnString"].ToString();
            string userDir = context.Session["user_dir"].ToString();

            OpenRequest req;
            try
            {
                string body;
                using (var reader = new StreamReader(context.Request.InputStream, context.Request.ContentEncoding))
                    body = reader.ReadToEnd();
                req = new JavaScriptSerializer().Deserialize<OpenRequest>(body ?? "{}");
            }
            catch
            {
                req = new OpenRequest();
            }

            if (req == null) req = new OpenRequest();
            string parm = (req.parm ?? "").Trim();
            string run = (req.run ?? "").Trim();
            string fileType = (req.fileType ?? req.type ?? "").Trim().ToUpperInvariant();
            bool isErr = fileType == "ERR" || fileType == "ERRORS";

            if (parm.Length == 0)
            {
                response.StatusCode = 400;
                WriteJson(response, new { ok = false, error = "parm is required." });
                return;
            }
            if (!isErr && run.Length == 0)
            {
                response.StatusCode = 400;
                WriteJson(response, new { ok = false, error = "run is required for report files." });
                return;
            }

            string baseName = isErr
                ? ("tsip_" + parm + ".ERR")
                : ("tsip_" + parm + "_" + run + "." + fileType);

            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                {
                    string diskPath = Path.Combine(userDir, baseName);
                    if (File.Exists(diskPath))
                    {
                        string dest = diskPath + ".txt";
                        if (File.Exists(dest)) File.Delete(dest);
                        File.Copy(diskPath, dest);
                        WriteJson(response, new { ok = true, baseName = baseName, source = "disk" });
                        return;
                    }

                    if (isErr)
                    {
                        WriteJson(response, new
                        {
                            ok = false,
                            error = "ERR summary file tsip_" + parm + ".ERR is not in your user folder. " +
                                    "Expand a run below to view archived report types."
                        });
                        return;
                    }

                    long? runId = req.runId;
                    if (!runId.HasValue)
                        runId = ResolveRunId(cnstr, user, parm, run);

                    if (!runId.HasValue)
                    {
                        WriteJson(response, new
                        {
                            ok = false,
                            error = "No archived run found for " + parm + " / " + run + "."
                        });
                        return;
                    }

                    string text = LoadReportText(cnstr, runId.Value, fileType);
                    if (text == null)
                    {
                        WriteJson(response, new
                        {
                            ok = false,
                            error = "Report " + fileType + " not found on disk or in archive (run_id=" + runId + ")."
                        });
                        return;
                    }

                    string destPath = Path.Combine(userDir, baseName + ".txt");
                    File.WriteAllText(destPath, text, Encoding.UTF8);
                    WriteJson(response, new
                    {
                        ok = true,
                        baseName = baseName,
                        source = "archive",
                        runId = runId.Value
                    });
                }
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        private static long? ResolveRunId(string cnstr, string user, string parm, string run)
        {
            string sql =
                "SELECT TOP 1 run_id FROM web.tsip_run " +
                "WHERE RTRIM(mics_user) = '" + user.Replace("'", "''") + "' " +
                "AND RTRIM(parm_file) = '" + parm.Replace("'", "''") + "' " +
                "AND RTRIM(run_name) = '" + run.Replace("'", "''") + "' " +
                "ORDER BY run_id DESC";

            using (var cn = new OdbcConnection(cnstr))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                {
                    object val = cmd.ExecuteScalar();
                    if (val == null || val == DBNull.Value) return null;
                    return Convert.ToInt64(val);
                }
            }
        }

        private static string LoadReportText(string cnstr, long runId, string reportType)
        {
            string sql =
                "SELECT line_text FROM web.tsip_run_report_line " +
                "WHERE run_id = " + runId + " AND RTRIM(report_type) = '" + reportType.Replace("'", "''") + "' " +
                "ORDER BY line_no";

            var lines = new List<string>();
            using (var cn = new OdbcConnection(cnstr))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        if (dr["line_text"] == DBNull.Value) continue;
                        lines.Add(dr["line_text"].ToString());
                    }
                }
            }

            if (lines.Count == 0) return null;
            return string.Join("\r\n", lines.ToArray());
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            response.Write(new JavaScriptSerializer().Serialize(obj));
        }

        private class OpenRequest
        {
            public string parm { get; set; }
            public string run { get; set; }
            public string fileType { get; set; }
            public string type { get; set; }
            public long? runId { get; set; }
        }
    }
}
