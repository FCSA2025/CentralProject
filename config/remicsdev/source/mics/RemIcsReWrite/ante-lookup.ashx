<%@ WebHandler Language="C#" Class="RemIcsReWrite.AnteLookupHandler" %>

using System;
using System.Collections.Generic;
using System.Data.Odbc;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>
    /// Antenna finder: manufacturer / model / description / code across
    /// main.sd_ante and user SDF su_*_ante tables. Empty q returns a capped list.
    /// </summary>
    public class AnteLookupHandler : IHttpHandler, IRequiresSessionState
    {
        private const int MaxRows = 80;
        private const int MaxUserFiles = 12;

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

            string q = (context.Request["q"] ?? "").Trim();
            string acode = (context.Request["acode"] ?? "").Trim();
            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                using (var cn = new OdbcConnection(context.Session["s_cnString"].ToString()))
                {
                    cn.Open();
                    var rows = new List<object>();
                    string schema = context.Session["s_schema"].ToString();

                    foreach (string table in UserAnteTables(cn, schema))
                    {
                        if (rows.Count >= MaxRows) break;
                        AddRows(cn, table, "SDF " + FileNameFromTable(table), q, acode, rows);
                    }
                    if (rows.Count < MaxRows)
                        AddRows(cn, "main.sd_ante", "main.sd_ante", q, acode, rows);

                    WriteJson(response, new { ok = true, q = q, acode = acode, rows = rows, count = rows.Count });
                }
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        private static List<string> UserAnteTables(OdbcConnection cn, string schema)
        {
            var tables = new List<string>();
            string likePat = "su\\_%\\_ante";
            string sql = "SELECT RTRIM(table_name) FROM INFORMATION_SCHEMA.TABLES WHERE table_schema='" +
                         schema.Replace("'", "''") + "' AND table_name LIKE '" + likePat +
                         "' ESCAPE '\\' ORDER BY table_name";
            using (var cmd = new OdbcCommand(sql, cn))
            using (var dr = cmd.ExecuteReader())
            {
                while (dr.Read() && tables.Count < MaxUserFiles)
                {
                    string t = Convert.ToString(dr.GetValue(0)) ?? "";
                    if (t.Length > 8)
                        tables.Add(schema + "." + t);
                }
            }
            return tables;
        }

        private static string FileNameFromTable(string qualified)
        {
            int dot = qualified.LastIndexOf('.');
            string t = dot >= 0 ? qualified.Substring(dot + 1) : qualified;
            if (t.StartsWith("su_", StringComparison.OrdinalIgnoreCase) && t.EndsWith("_ante", StringComparison.OrdinalIgnoreCase))
                return t.Substring(3, t.Length - 8);
            return t;
        }

        private static void AddRows(OdbcConnection cn, string table, string source, string q, string acode, List<object> rows)
        {
            string where;
            if (!string.IsNullOrEmpty(acode))
            {
                where = "UPPER(RTRIM(CAST(acode AS VARCHAR(32)))) = '" + SqlLit(acode.ToUpperInvariant()) + "'";
            }
            else if (!string.IsNullOrEmpty(q))
            {
                string like = "%" + SqlLike(q.ToUpperInvariant()) + "%";
                where = "(UPPER(CAST(acode AS VARCHAR(32))) LIKE '" + like + "' ESCAPE '\\'" +
                        " OR UPPER(CAST(amanu AS VARCHAR(64))) LIKE '" + like + "' ESCAPE '\\'" +
                        " OR UPPER(CAST(amodel AS VARCHAR(64))) LIKE '" + like + "' ESCAPE '\\'" +
                        " OR UPPER(CAST(adesc AS VARCHAR(128))) LIKE '" + like + "' ESCAPE '\\')";
            }
            else
            {
                where = "1=1";
            }

            int take = MaxRows - rows.Count;
            if (take <= 0) return;
            string sql = "SELECT TOP " + take + " acode, amanu, amodel, adesc, again FROM " + table +
                         " WHERE " + where + " ORDER BY amodel, acode";
            try
            {
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        rows.Add(new
                        {
                            acode = Cell(dr, 0),
                            amanu = Cell(dr, 1),
                            amodel = Cell(dr, 2),
                            adesc = Cell(dr, 3),
                            again = Cell(dr, 4),
                            source = source
                        });
                    }
                }
            }
            catch
            {
                /* user SDF table may lack columns; skip */
            }
        }

        private static string Cell(OdbcDataReader dr, int i)
        {
            if (dr.IsDBNull(i)) return "";
            return (Convert.ToString(dr.GetValue(i)) ?? "").Trim();
        }

        private static string SqlLit(string s)
        {
            return (s ?? "").Replace("'", "''");
        }

        private static string SqlLike(string s)
        {
            return SqlLit(s).Replace("\\", "\\\\").Replace("%", "\\%").Replace("_", "\\_");
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            response.Write(new JavaScriptSerializer { MaxJsonLength = 4 * 1024 * 1024 }.Serialize(obj));
        }
    }
}
