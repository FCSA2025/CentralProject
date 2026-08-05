<%@ WebHandler Language="C#" Class="RemIcsReWrite.TsipStatusHandler" %>

using System;
using System.Collections.Generic;
using System.Data.Odbc;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>Poll web.tsip_queue for the current MICS user (active + recent finished).</summary>
    public class TsipStatusHandler : IHttpHandler, IRequiresSessionState
    {
        public bool IsReusable { get { return false; } }

        public void ProcessRequest(HttpContext context)
        {
            var response = context.Response;
            response.ContentType = "application/json; charset=utf-8";
            response.Cache.SetCacheability(HttpCacheability.NoCache);

            if (context.Session == null || context.Session["s_cnString"] == null || context.Session["s_user"] == null)
            {
                response.StatusCode = 401;
                WriteJson(response, new { ok = false, error = "Session not initialized." });
                return;
            }

            string user = context.Session["s_user"].ToString();
            string cnstr = context.Session["s_cnString"].ToString();
            var jobs = new List<object>();

            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                using (var cn = new OdbcConnection(cnstr))
                {
                    cn.Open();
                    // Active first, then recently finished (last 20 for this user).
                    string sql =
                        "SELECT TOP 40 TQ_Job, RTRIM(TQ_Status) AS TQ_Status, TQ_Finish, " +
                        "RTRIM(TQ_ArgFile) AS TQ_ArgFile, RTRIM(TQ_MicsID) AS TQ_MicsID, " +
                        "TQ_TimeIn, TQ_TimeStart, TQ_TimeEnd " +
                        "FROM web.tsip_queue " +
                        "WHERE RTRIM(TQ_MicsID) = '" + user.Replace("'", "''") + "' " +
                        "ORDER BY CASE WHEN RTRIM(TQ_Status) IN ('W','X') THEN 0 ELSE 1 END, TQ_Job DESC";

                    using (var cmd = new OdbcCommand(sql, cn))
                    using (var dr = cmd.ExecuteReader())
                    {
                        while (dr.Read())
                        {
                            string st = dr["TQ_Status"] != DBNull.Value ? dr["TQ_Status"].ToString().Trim() : "";
                            object finish = dr["TQ_Finish"];
                            jobs.Add(new
                            {
                                job = Convert.ToInt32(dr["TQ_Job"]),
                                status = st,
                                finish = finish == DBNull.Value ? (int?)null : Convert.ToInt32(finish),
                                parm = dr["TQ_ArgFile"] != DBNull.Value ? dr["TQ_ArgFile"].ToString().Trim() : "",
                                micsid = dr["TQ_MicsID"] != DBNull.Value ? dr["TQ_MicsID"].ToString().Trim() : "",
                                timeIn = dr["TQ_TimeIn"] == DBNull.Value ? null : Convert.ToDateTime(dr["TQ_TimeIn"]).ToString("yyyy-MM-dd HH:mm:ss"),
                                timeStart = dr["TQ_TimeStart"] == DBNull.Value ? null : Convert.ToDateTime(dr["TQ_TimeStart"]).ToString("yyyy-MM-dd HH:mm:ss"),
                                timeEnd = dr["TQ_TimeEnd"] == DBNull.Value ? null : Convert.ToDateTime(dr["TQ_TimeEnd"]).ToString("yyyy-MM-dd HH:mm:ss"),
                                active = st == "W" || st == "X"
                            });
                        }
                    }
                }

                WriteJson(response, new { ok = true, user = user, jobs = jobs });
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
