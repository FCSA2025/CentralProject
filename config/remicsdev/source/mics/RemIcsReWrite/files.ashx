<%@ WebHandler Language="C#" Class="RemIcsReWrite.FilesHandler" %>

using System;
using System.Collections.Generic;
using System.Data.Odbc;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>JSON TS/ES file list  -  INFORMATION_SCHEMA ft_%_titl / fe_%_titl (classic tsTree / esTree).</summary>
    public class FilesHandler : IHttpHandler, IRequiresSessionState
    {
        public bool IsReusable { get { return false; } }

        public void ProcessRequest(HttpContext context)
        {
            var response = context.Response;
            var request = context.Request;
            response.ContentType = "application/json; charset=utf-8";
            response.Cache.SetCacheability(HttpCacheability.NoCache);

            if (context.Session == null || context.Session["s_cnString"] == null || context.Session["s_schema"] == null)
            {
                response.StatusCode = 401;
                WriteJson(response, new { ok = false, error = "Session not initialized." });
                return;
            }

            string filetype = (request.QueryString["filetype"] ?? "TS").Trim().ToUpperInvariant();
            if (filetype != "TS" && filetype != "ES")
            {
                response.StatusCode = 400;
                WriteJson(response, new { ok = false, error = "filetype must be TS or ES." });
                return;
            }

            string schema = context.Session["s_schema"].ToString();
            string cnstr = context.Session["s_cnString"].ToString();
            string likePat = filetype == "ES" ? "fe\\_%\\_titl" : "ft\\_%\\_titl";
            var files = new List<object>();

            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                using (var ucn = new OdbcConnection(cnstr))
                {
                    ucn.Open();
                    string sql = "SELECT table_name FROM INFORMATION_SCHEMA.TABLES WHERE table_schema = '" +
                                 schema.Replace("'", "''") + "' AND table_name LIKE '" + likePat +
                                 "' ESCAPE '\\' ORDER BY table_name";
                    using (var cmd = new OdbcCommand(sql, ucn))
                    using (var dr = cmd.ExecuteReader())
                    {
                        while (dr.Read())
                        {
                            string tablename = dr.GetString(0);
                            if (tablename.Length > 8)
                            {
                                string filename = tablename.Substring(3, tablename.Length - 8);
                                files.Add(new { name = filename, filetype = filetype });
                            }
                        }
                    }
                }

                WriteJson(response, new
                {
                    ok = true,
                    schema = schema,
                    filetype = filetype,
                    project = context.Session["defProject"] != null ? context.Session["defProject"].ToString() : "",
                    user = context.Session["s_user"] != null ? context.Session["s_user"].ToString() : "",
                    files = files
                });
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
