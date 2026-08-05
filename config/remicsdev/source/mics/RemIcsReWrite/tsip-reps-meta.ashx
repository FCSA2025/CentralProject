<%@ WebHandler Language="C#" Class="RemIcsReWrite.TsipRepsMetaHandler" %>

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
    /// Case-count glance for TSIP report runs.
    /// Prefer web.tsip_run.num_int_cases; else CASEDET "Case Number :" headers; else CASESUM "Number of reporting cases".
    /// </summary>
    public class TsipRepsMetaHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly Regex CaseNumberLine = new Regex(
            @"Case Number\s*:\s*(\d+)", RegexOptions.IgnoreCase | RegexOptions.Compiled);

        private static readonly Regex ReportingCasesLine = new Regex(
            @"Number of reporting cases\s*:\s*(\d+)", RegexOptions.IgnoreCase | RegexOptions.Compiled);

        public bool IsReusable { get { return false; } }

        public void ProcessRequest(HttpContext context)
        {
            var response = context.Response;
            response.ContentType = "application/json; charset=utf-8";
            response.Cache.SetCacheability(HttpCacheability.NoCache);

            if (context.Session == null || context.Session["s_cnString"] == null || context.Session["s_user"] == null
                || context.Session["user_dir"] == null)
            {
                response.StatusCode = 401;
                WriteJson(response, new { ok = false, error = "Session not initialized." });
                return;
            }

            string user = context.Session["s_user"].ToString();
            string cnstr = context.Session["s_cnString"].ToString();
            string userDir = context.Session["user_dir"].ToString();
            string parmFilter = (context.Request["parm"] ?? "").Trim();
            int? jobFilter = null;
            int jobTmp;
            if (int.TryParse(context.Request["job"], out jobTmp)) jobFilter = jobTmp;

            try
            {
                var byKey = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);

                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                {
                    LoadFromArchive(cnstr, user, parmFilter, jobFilter, byKey);
                    LoadFromDisk(userDir, parmFilter, byKey);
                }

                var runs = new List<object>();
                foreach (var kv in byKey)
                    runs.Add(kv.Value);

                WriteJson(response, new { ok = true, user = user, runs = runs });
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        private static void LoadFromArchive(
            string cnstr, string user, string parmFilter, int? jobFilter,
            Dictionary<string, object> byKey)
        {
            string sql =
                "SELECT TOP 80 run_id, RTRIM(parm_file) AS parm_file, RTRIM(run_name) AS run_name, " +
                "num_int_cases, queue_job_id, RTRIM(archive_status) AS archive_status " +
                "FROM web.tsip_run " +
                "WHERE RTRIM(mics_user) = '" + user.Replace("'", "''") + "' ";
            if (!string.IsNullOrEmpty(parmFilter))
                sql += "AND RTRIM(parm_file) = '" + parmFilter.Replace("'", "''") + "' ";
            if (jobFilter.HasValue)
                sql += "AND queue_job_id = " + jobFilter.Value + " ";
            sql += "ORDER BY run_id DESC";

            using (var cn = new OdbcConnection(cnstr))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        string parm = dr["parm_file"] != DBNull.Value ? dr["parm_file"].ToString().Trim() : "";
                        string run = dr["run_name"] != DBNull.Value ? dr["run_name"].ToString().Trim() : "";
                        if (parm.Length == 0 || run.Length == 0) continue;
                        string key = parm + "\t" + run;
                        if (byKey.ContainsKey(key)) continue; // newest first

                        int? cases = null;
                        if (dr["num_int_cases"] != DBNull.Value)
                            cases = Convert.ToInt32(dr["num_int_cases"]);

                        object jobId = dr["queue_job_id"] == DBNull.Value ? null : (object)Convert.ToInt32(dr["queue_job_id"]);
                        string status = dr["archive_status"] != DBNull.Value ? dr["archive_status"].ToString().Trim() : "";

                        byKey[key] = BuildRun(parm, run, cases, "archive", status, jobId,
                            Convert.ToInt64(dr["run_id"]));
                    }
                }
            }
        }

        private static void LoadFromDisk(string userDir, string parmFilter, Dictionary<string, object> byKey)
        {
            if (string.IsNullOrEmpty(userDir) || !Directory.Exists(userDir)) return;

            string[] files = Directory.GetFiles(userDir, "tsip_*");
            // Collect run stems that have CASEDET or CASESUM (not .txt copies)
            var stems = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
            foreach (string path in files)
            {
                string name = Path.GetFileName(path);
                if (name.EndsWith(".txt", StringComparison.OrdinalIgnoreCase)) continue;
                // tsip_{parm}_{run}.CASEDET / .CASESUM
                Match m = Regex.Match(name, @"^tsip_(.+)_(.+)\.(CASEDET|CASESUM)$", RegexOptions.IgnoreCase);
                if (!m.Success) continue;
                string parm = m.Groups[1].Value;
                string run = m.Groups[2].Value;
                if (!string.IsNullOrEmpty(parmFilter) &&
                    !string.Equals(parm, parmFilter, StringComparison.OrdinalIgnoreCase))
                    continue;
                stems[parm + "\t" + run] = true;
            }

            foreach (string key in stems.Keys)
            {
                if (byKey.ContainsKey(key)) continue; // archive already has it
                string[] parts = key.Split('\t');
                string parm = parts[0];
                string run = parts[1];
                string basePath = Path.Combine(userDir, "tsip_" + parm + "_" + run);

                int? cases = null;
                string source = "none";

                string casedet = basePath + ".CASEDET";
                if (File.Exists(casedet))
                {
                    int n = CountCaseNumberHeaders(casedet);
                    cases = n;
                    source = "casedet";
                }
                else
                {
                    string casesum = basePath + ".CASESUM";
                    if (File.Exists(casesum))
                    {
                        int? n = ParseReportingCases(casesum);
                        if (n.HasValue)
                        {
                            cases = n.Value;
                            source = "casesum";
                        }
                    }
                }

                byKey[key] = BuildRun(parm, run, cases, source, null, null, null);
            }
        }

        private static int CountCaseNumberHeaders(string path)
        {
            int n = 0;
            foreach (string line in File.ReadLines(path))
            {
                if (CaseNumberLine.IsMatch(line)) n++;
            }
            return n;
        }

        private static int? ParseReportingCases(string path)
        {
            foreach (string line in File.ReadLines(path))
            {
                Match m = ReportingCasesLine.Match(line);
                if (m.Success)
                    return int.Parse(m.Groups[1].Value);
            }
            return null;
        }

        private static object BuildRun(
            string parm, string run, int? cases, string source, string archiveStatus,
            object queueJobId, object runId)
        {
            string glance;
            string glanceKind;
            if (!cases.HasValue)
            {
                glanceKind = "unknown";
                glance = "Unknown result — see report files for details";
            }
            else if (cases.Value == 0)
            {
                glanceKind = "none";
                glance = "No cases detected";
            }
            else
            {
                glanceKind = "cases";
                glance = cases.Value == 1
                    ? "1 interference case"
                    : (cases.Value + " interference cases");
            }

            return new
            {
                parm = parm,
                run = run,
                cases = cases,
                source = source,
                glanceKind = glanceKind,
                glance = glance,
                archiveStatus = archiveStatus,
                queueJobId = queueJobId,
                runId = runId
            };
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            response.Write(new JavaScriptSerializer().Serialize(obj));
        }
    }
}
