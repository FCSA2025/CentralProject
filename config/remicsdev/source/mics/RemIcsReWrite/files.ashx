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

            string filetype = (request.QueryString["filetype"] ?? request.Form["filetype"] ?? "TS").Trim();
            string checkName = (request.QueryString["name"] ?? request.Form["name"] ?? "").Trim();
            if (checkName.Length > 0)
            {
                WriteExists(context, filetype, checkName);
                return;
            }

            if (filetype.Equals("TsipParm", StringComparison.OrdinalIgnoreCase) ||
                filetype.Equals("TSIPPARM", StringComparison.OrdinalIgnoreCase))
            {
                WriteTsipParmList(context);
                return;
            }

            filetype = filetype.ToUpperInvariant();
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

        private static void WriteTsipParmList(HttpContext context)
        {
            var response = context.Response;
            string schema = context.Session["s_schema"].ToString();
            string cnstr = context.Session["s_cnString"].ToString();
            var files = new List<object>();
            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                using (var ucn = new OdbcConnection(cnstr))
                {
                    ucn.Open();
                    string sql =
                        "SELECT t.TABLE_NAME, " +
                        "MAX(CASE WHEN c.COLUMN_NAME = 'runname' THEN 1 ELSE 0 END) AS has_runname, " +
                        "MAX(CASE WHEN c.COLUMN_NAME = 'protype' THEN 1 ELSE 0 END) AS has_protype " +
                        "FROM INFORMATION_SCHEMA.TABLES t " +
                        "JOIN INFORMATION_SCHEMA.COLUMNS c ON c.TABLE_SCHEMA = t.TABLE_SCHEMA AND c.TABLE_NAME = t.TABLE_NAME " +
                        "WHERE t.TABLE_SCHEMA = '" + schema.Replace("'", "''") + "' " +
                        "AND t.TABLE_NAME LIKE 'tp\\_%\\_parm' ESCAPE '\\' " +
                        "GROUP BY t.TABLE_NAME ORDER BY t.TABLE_NAME";
                    var rows = new List<object[]>();
                    using (var cmd = new OdbcCommand(sql, ucn))
                    using (var dr = cmd.ExecuteReader())
                    {
                        while (dr.Read())
                        {
                            string tablename = Convert.ToString(dr.GetValue(0)) ?? "";
                            if (tablename.Length < 9) continue;
                            string filename = tablename.Substring(3, tablename.Length - 8);
                            bool usable = Convert.ToInt32(dr.GetValue(1)) > 0 && Convert.ToInt32(dr.GetValue(2)) > 0;
                            rows.Add(new object[] { filename, usable, tablename });
                        }
                    }
                    for (int i = 0; i < rows.Count; i++)
                    {
                        string filename = (string)rows[i][0];
                        bool usable = (bool)rows[i][1];
                        string tablename = (string)rows[i][2];
                        int runCount = 0;
                        if (usable && System.Text.RegularExpressions.Regex.IsMatch(filename, @"^[A-Za-z0-9_]{1,16}$"))
                        {
                            string countSql = "SELECT COUNT(*) FROM [" + schema.Replace("]", "]]") + "].[" +
                                              tablename.Replace("]", "]]") + "]";
                            using (var countCmd = new OdbcCommand(countSql, ucn))
                            {
                                runCount = Convert.ToInt32(countCmd.ExecuteScalar());
                            }
                        }
                        files.Add(new { name = filename, usable = usable, table = tablename, runCount = runCount });
                    }
                }
                WriteJson(response, new { ok = true, schema = schema, filetype = "TsipParm", files = files });
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        private static void WriteExists(HttpContext context, string filetype, string name)
        {
            var response = context.Response;
            if (!System.Text.RegularExpressions.Regex.IsMatch(name, @"^[A-Za-z0-9_]{1,16}$"))
            {
                response.StatusCode = 400;
                WriteJson(response, new { ok = false, error = "Invalid file name." });
                return;
            }

            string table = MasterTableName(filetype, name);
            if (table == null)
            {
                WriteJson(response, new { ok = true, exists = false, supported = false, name = name, filetype = filetype });
                return;
            }

            string schema = context.Session["s_schema"].ToString();
            string cnstr = context.Session["s_cnString"].ToString();
            bool exists = false;
            bool catalogExists = false;
            int tabletype = TableTypeForFiletype(filetype);
            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                using (var ucn = new OdbcConnection(cnstr))
                {
                    ucn.Open();
                    string sql = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE table_schema = '" +
                                 schema.Replace("'", "''") + "' AND table_name = '" + table.Replace("'", "''") + "'";
                    using (var cmd = new OdbcCommand(sql, ucn))
                    {
                        exists = Convert.ToInt32(cmd.ExecuteScalar()) > 0;
                    }
                    if (tabletype >= 0)
                    {
                        string catSql = "SELECT COUNT(*) FROM web.user_tables_view WHERE operator = '" +
                                        schema.Replace("'", "''") + "' AND tabletype = " + tabletype +
                                        " AND file_name = '" + name.Replace("'", "''") + "'";
                        using (var catCmd = new OdbcCommand(catSql, ucn))
                        {
                            catalogExists = Convert.ToInt32(catCmd.ExecuteScalar()) > 0;
                        }
                    }
                }
                WriteJson(response, new
                {
                    ok = true,
                    exists = exists,
                    catalogExists = catalogExists,
                    catalogDrift = exists != catalogExists,
                    name = name,
                    table = table,
                    schema = schema,
                    filetype = filetype,
                    tabletype = tabletype >= 0 ? (object)tabletype : null
                });
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        private static string MasterTableName(string filetype, string name)
        {
            string ft = (filetype ?? "").Trim();
            if (ft.Equals("TS", StringComparison.OrdinalIgnoreCase)) return "ft_" + name + "_titl";
            if (ft.Equals("ES", StringComparison.OrdinalIgnoreCase)) return "fe_" + name + "_titl";
            if (ft.Equals("TsipParm", StringComparison.OrdinalIgnoreCase) || ft.Equals("TSIPPARM", StringComparison.OrdinalIgnoreCase))
                return "tp_" + name + "_parm";
            return null;
        }

        private static int TableTypeForFiletype(string filetype)
        {
            string ft = (filetype ?? "").Trim();
            if (ft.Equals("TS", StringComparison.OrdinalIgnoreCase)) return 0;
            if (ft.Equals("ES", StringComparison.OrdinalIgnoreCase)) return 5;
            if (ft.Equals("TsipParm", StringComparison.OrdinalIgnoreCase) || ft.Equals("TSIPPARM", StringComparison.OrdinalIgnoreCase))
                return 417;
            return -1;
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            response.Write(new JavaScriptSerializer().Serialize(obj));
        }
    }
}
