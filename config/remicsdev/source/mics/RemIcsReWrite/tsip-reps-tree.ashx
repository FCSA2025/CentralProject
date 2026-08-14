<%@ WebHandler Language="C#" Class="RemIcsReWrite.TsipRepsTreeHandler" %>

using System;
using System.Collections.Generic;
using System.Data.Odbc;
using System.IO;
using System.Linq;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>
    /// TSIP report tree for RemIcsReWrite — merges on-disk userdir files (classic)
    /// with web.tsip_run / web.tsip_run_report_line archive when disk copies are gone.
    /// </summary>
    public class TsipRepsTreeHandler : IHttpHandler, IRequiresSessionState
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
            string mode = (context.Request["mode"] ?? "root").Trim().ToLowerInvariant();
            string parm = (context.Request["parm"] ?? "").Trim();

            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                {
                    if (mode == "parm")
                    {
                        if (string.IsNullOrEmpty(parm))
                        {
                            response.StatusCode = 400;
                            WriteJson(response, new { ok = false, error = "parm is required." });
                            return;
                        }
                        WriteJson(response, BuildParmTree(cnstr, user, userDir, parm));
                        return;
                    }

                    WriteJson(response, BuildRootTree(cnstr, user, userDir));
                }
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        private static object BuildRootTree(string cnstr, string user, string userDir)
        {
            var parms = new Dictionary<string, Dictionary<string, object>>(StringComparer.OrdinalIgnoreCase);

            if (Directory.Exists(userDir))
            {
                foreach (string path in Directory.GetFiles(userDir))
                {
                    string name = Path.GetFileName(path);
                    if (name.IndexOf("tsip_", StringComparison.OrdinalIgnoreCase) < 0) continue;
                    if (name.IndexOf(".ERR", StringComparison.OrdinalIgnoreCase) < 0) continue;
                    if (name.EndsWith(".txt", StringComparison.OrdinalIgnoreCase)) continue;

                    int us = name.IndexOf('_');
                    int err = name.IndexOf(".ERR", StringComparison.OrdinalIgnoreCase);
                    if (us < 0 || err <= us + 1) continue;
                    string parmName = name.Substring(us + 1, err - us - 1);
                    if (parmName.Length == 0) continue;

                    if (!parms.ContainsKey(parmName))
                    {
                        parms[parmName] = new Dictionary<string, object> {
                            { "parm", parmName },
                            { "disk", false },
                            { "archive", false }
                        };
                    }
                    parms[parmName]["disk"] = true;
                }
            }

            string sql =
                "SELECT DISTINCT RTRIM(parm_file) AS parm_file FROM web.tsip_run " +
                "WHERE RTRIM(mics_user) = '" + user.Replace("'", "''") + "' " +
                "AND RTRIM(parm_file) <> '' ORDER BY parm_file";

            using (var cn = new OdbcConnection(cnstr))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        string p = dr["parm_file"] != DBNull.Value ? dr["parm_file"].ToString().Trim() : "";
                        if (p.Length == 0) continue;
                        if (!parms.ContainsKey(p))
                        {
                            parms[p] = new Dictionary<string, object> {
                                { "parm", p },
                                { "disk", false },
                                { "archive", false }
                            };
                        }
                        parms[p]["archive"] = true;
                    }
                }
            }

            var list = parms.Values.OrderBy(x => x["parm"].ToString(), StringComparer.OrdinalIgnoreCase).ToList();
            return new
            {
                ok = true,
                user = user,
                userDir = userDir,
                parms = list
            };
        }

        private static object BuildParmTree(string cnstr, string user, string userDir, string parm)
        {
            var runs = new Dictionary<string, RunNode>(StringComparer.OrdinalIgnoreCase);
            bool hasErrors = false;
            bool errorsOnDisk = false;

            string errPath = Path.Combine(userDir, "tsip_" + parm + ".ERR");
            if (File.Exists(errPath))
            {
                hasErrors = true;
                errorsOnDisk = true;
            }

            string froot = "tsip_" + parm + "_";
            if (Directory.Exists(userDir))
            {
                foreach (string path in Directory.GetFiles(userDir))
                {
                    string name = Path.GetFileName(path);
                    if (!name.StartsWith(froot, StringComparison.OrdinalIgnoreCase)) continue;
                    if (name.IndexOf(".ERR", StringComparison.OrdinalIgnoreCase) >= 0) continue;
                    if (name.EndsWith(".txt", StringComparison.OrdinalIgnoreCase)) continue;

                    string tail = name.Substring(froot.Length);
                    int dot = tail.IndexOf('.');
                    if (dot <= 0) continue;
                    string run = tail.Substring(0, dot);
                    string ftype = tail.Substring(dot + 1);
                    if (run.Length == 0 || ftype.Length == 0) continue;

                    RunNode rn = GetRun(runs, parm, run, null);
                    AddFile(rn, ftype, ftype, "disk", null);
                }
            }

            string runSql =
                "SELECT run_id, RTRIM(run_name) AS run_name " +
                "FROM web.tsip_run " +
                "WHERE RTRIM(mics_user) = '" + user.Replace("'", "''") + "' " +
                "AND RTRIM(parm_file) = '" + parm.Replace("'", "''") + "' " +
                "ORDER BY run_id DESC";

            using (var cn = new OdbcConnection(cnstr))
            {
                cn.Open();
                var seenRuns = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                using (var cmd = new OdbcCommand(runSql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        string run = dr["run_name"] != DBNull.Value ? dr["run_name"].ToString().Trim() : "";
                        if (run.Length == 0 || seenRuns.Contains(run)) continue;
                        seenRuns.Add(run);

                        long runId = Convert.ToInt64(dr["run_id"]);
                        RunNode rn = GetRun(runs, parm, run, runId);

                        string typeSql =
                            "SELECT DISTINCT RTRIM(report_type) AS report_type " +
                            "FROM web.tsip_run_report_line WHERE run_id = " + runId +
                            " ORDER BY report_type";
                        using (var typeCmd = new OdbcCommand(typeSql, cn))
                        using (var typeDr = typeCmd.ExecuteReader())
                        {
                            while (typeDr.Read())
                            {
                                string rt = typeDr["report_type"] != DBNull.Value
                                    ? typeDr["report_type"].ToString().Trim() : "";
                                if (rt.Length == 0) continue;
                                AddFile(rn, rt, rt, "archive", runId);
                            }
                        }
                    }
                }
            }

            // Archive-only parms have no .ERR summary file; individual report types still load.

            var runList = runs.Values
                .OrderBy(r => r.run, StringComparer.OrdinalIgnoreCase)
                .Select(r => new
                {
                    run = r.run,
                    runId = r.runId,
                    label = "Run-" + r.run,
                    files = r.files.OrderBy(f => f.type, StringComparer.OrdinalIgnoreCase).ToList()
                })
                .ToList();

            return new
            {
                ok = true,
                parm = parm,
                hasErrors = hasErrors,
                errorsOnDisk = errorsOnDisk,
                runs = runList
            };
        }

        private static RunNode GetRun(
            Dictionary<string, RunNode> runs, string parm, string run, long? runId)
        {
            RunNode rn;
            if (!runs.TryGetValue(run, out rn))
            {
                rn = new RunNode { parm = parm, run = run, runId = runId };
                runs[run] = rn;
            }
            else if (!rn.runId.HasValue && runId.HasValue)
            {
                rn.runId = runId;
            }
            return rn;
        }

        private static void AddFile(RunNode rn, string type, string label, string source, long? runId)
        {
            foreach (var f in rn.files)
            {
                if (string.Equals(f.type, type, StringComparison.OrdinalIgnoreCase))
                {
                    if (f.source == "disk" || source == "disk")
                        f.source = "disk";
                    if (!f.runId.HasValue && runId.HasValue)
                        f.runId = runId;
                    return;
                }
            }
            rn.files.Add(new FileNode
            {
                type = type,
                label = label,
                source = source,
                runId = runId ?? rn.runId
            });
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            response.Write(new JavaScriptSerializer().Serialize(obj));
        }

        private class RunNode
        {
            public string parm;
            public string run;
            public long? runId;
            public List<FileNode> files = new List<FileNode>();
        }

        private class FileNode
        {
            public string type;
            public string label;
            public string source;
            public long? runId;
        }
    }
}
