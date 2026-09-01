<%@ WebHandler Language="C#" Class="RemIcsReWrite.ReconcileHandler" %>

using System;
using System.Data.Odbc;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>
    /// On-demand web.user_tables reconcile for the logged-in company schema (Gate B).
    /// Wraps web.ReconcileUserTables for types 0 / 5 / 417 only.
    /// </summary>
    public class ReconcileHandler : IHttpHandler, IRequiresSessionState
    {
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

            string schema = context.Session["s_schema"].ToString().Trim();
            string cnstr = context.Session["s_cnString"].ToString();
            bool dryRun = string.Equals(context.Request["dryRun"], "1", StringComparison.OrdinalIgnoreCase)
                || string.Equals(context.Request["dryrun"], "true", StringComparison.OrdinalIgnoreCase);

            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                using (var cn = new OdbcConnection(cnstr))
                {
                    cn.Open();
                    using (var cmd = new OdbcCommand(
                        "SET NOCOUNT ON; EXEC web.ReconcileUserTables @Operator = '" +
                        schema.Replace("'", "''") + "', @DryRun = " + (dryRun ? "1" : "0") +
                        ", @SyncValidstat = 1", cn))
                    {
                        int runId = 0;
                        int deleted = 0, inserted = 0, updated = 0;
                        string mode = dryRun ? "DRY" : "LIVE";

                        using (var dr = cmd.ExecuteReader())
                        {
                            if (dr.Read())
                            {
                                runId = Convert.ToInt32(dr["run_id"]);
                                mode = Convert.ToString(dr["mode"]);
                                deleted = Convert.ToInt32(dr["deleted_orphans"]);
                                inserted = Convert.ToInt32(dr["inserted_missing"]);
                                updated = Convert.ToInt32(dr["updated_validstat"]);
                            }
                        }

                        WriteJson(response, new
                        {
                            ok = true,
                            schema = schema,
                            dryRun = dryRun,
                            run_id = runId,
                            mode = mode,
                            deleted_orphans = deleted,
                            inserted_missing = inserted,
                            updated_validstat = updated
                        });
                    }
                }
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            response.Write(new JavaScriptSerializer().Serialize(obj));
        }
    }
}
