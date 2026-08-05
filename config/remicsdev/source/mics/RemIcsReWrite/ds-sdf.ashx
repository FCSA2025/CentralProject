<%@ WebHandler Language="C#" Class="RemIcsReWrite.DsSdfHandler" %>

using System;
using System.Collections.Generic;
using System.Data.Odbc;
using System.Text;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>Phase 6.75 — SDF catalog search against main.sd_* (Tdssdf parity MVP).</summary>
    public class DsSdfHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly Dictionary<string, SdfMeta> Meta = new Dictionary<string, SdfMeta>(StringComparer.OrdinalIgnoreCase)
        {
            { "Ante", new SdfMeta("sd_ante", "acode", new[] { "acode", "amanu", "adesc", "again" }) },
            { "Band", new SdfMeta("sd_band", "bndcde", new[] { "bndcde", "blo", "bmidf", "bhi", "badj" }) },
            { "Ctx", new SdfMeta("sd_ctx", "tfcr", new[] { "tfcr", "tfci", "rxeqp", "ctxdesc" }) },
            { "Eqpt", new SdfMeta("sd_eqpt", "ecode", new[] { "ecode", "emanu", "emodel", "edesc" }) },
            { "Oper", new SdfMeta("sd_oper", "oper", new[] { "oper", "nameop", "city", "prstat" }) },
            { "Plan", new SdfMeta("sd_plan", "splan", new[] { "sband", "splan" }) },
            { "Rout", new SdfMeta("sd_rout", "routnumb", new[] { "rtname", "rcomp", "routnumb" }) },
            { "Note", new SdfMeta("sd_note", "nonum", new[] { "oper", "nonum", "note" }) },
            { "Towr", new SdfMeta("sd_towr", "twcode", new[] { "twcode", "twdesc" }) },
            { "Town", new SdfMeta("sd_town", "call1", new[] { "call1", "atwrno", "oper" }) },
            { "Traf", new SdfMeta("sd_traf", "trafcode", new[] { "trafcode", "ecode", "trdesc" }) }
        };

        private class SdfMeta
        {
            public string Table;
            public string KeyCol;
            public string[] Cols;
            public SdfMeta(string t, string k, string[] c) { Table = t; KeyCol = k; Cols = c; }
        }

        public bool IsReusable { get { return false; } }

        public void ProcessRequest(HttpContext context)
        {
            var response = context.Response;
            response.ContentType = "application/json; charset=utf-8";
            response.Cache.SetCacheability(HttpCacheability.NoCache);

            if (context.Session == null || context.Session["s_cnString"] == null)
            {
                response.StatusCode = 401;
                WriteJson(response, new { ok = false, error = "Session not initialized." });
                return;
            }

            string action = (context.Request["action"] ?? "search").Trim().ToLowerInvariant();
            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                {
                    if (action == "search") Search(context);
                    else if (action == "types") WriteJson(response, new { ok = true, types = new List<string>(Meta.Keys) });
                    else
                    {
                        response.StatusCode = 400;
                        WriteJson(response, new { ok = false, error = "action must be search|types" });
                    }
                }
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message, detail = ex.ToString() });
            }
        }

        private static void Search(HttpContext ctx)
        {
            string type = (ctx.Request["type"] ?? "Ante").Trim();
            SdfMeta m;
            if (!Meta.TryGetValue(type, out m))
            {
                WriteJson(ctx.Response, new { ok = false, error = "Unknown SDF type." });
                return;
            }
            string q = (ctx.Request["q"] ?? "").Trim();
            var where = new StringBuilder("1=1");
            bool anyFilter = false;

            foreach (var col in m.Cols)
            {
                string val = (ctx.Request[col] ?? "").Trim();
                if (string.IsNullOrEmpty(val)) continue;
                anyFilter = true;
                string like = val.Replace("*", "%").Replace("?", "_").Replace("'", "''").ToUpperInvariant();
                if (!like.Contains("%")) like = like + "%";
                where.Append(" AND UPPER(CAST(").Append(col).Append(" AS VARCHAR(128))) LIKE '").Append(like).Append("'");
            }

            if (!string.IsNullOrEmpty(q))
            {
                anyFilter = true;
                string like = q.Replace("*", "%").Replace("?", "_").Replace("'", "''").ToUpperInvariant();
                if (!like.Contains("%")) like = like + "%";
                where.Append(" AND UPPER(CAST(").Append(m.KeyCol).Append(" AS VARCHAR(64))) LIKE '").Append(like).Append("'");
            }

            if (!anyFilter)
            {
                WriteJson(ctx.Response, new { ok = false, error = "Enter at least one search criterion." });
                return;
            }
            string cols = string.Join(", ", m.Cols);
            string sql = "SELECT TOP 500 " + cols + " FROM main." + m.Table + " a WHERE " + where + " ORDER BY " + m.KeyCol;
            var rows = new List<Dictionary<string, string>>();
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        var d = new Dictionary<string, string>();
                        for (int i = 0; i < m.Cols.Length; i++)
                            d[m.Cols[i]] = dr.IsDBNull(i) ? "" : (Convert.ToString(dr.GetValue(i)) ?? "").Trim();
                        rows.Add(d);
                    }
                }
            }
            WriteJson(ctx.Response, new { ok = true, type = type, keyCol = m.KeyCol, columns = m.Cols, rows = rows, count = rows.Count });
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            response.Write(new JavaScriptSerializer { MaxJsonLength = 8 * 1024 * 1024 }.Serialize(obj));
        }
    }
}
