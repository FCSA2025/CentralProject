<%@ WebHandler Language="C#" Class="RemIcsReWrite.DsSearchHandler" %>

using System;
using System.Collections.Generic;
using System.Data.Odbc;
using System.Text;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using DBAccess;
using DBUtilities;
using ErrorUtilities;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>
    /// Phase 6.5  -  Data Search JSON list (TS/ES). Cull/PDF insert stays on classic TwsdsTS/TwsdsES ASMX.
    /// </summary>
    public class DsSearchHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly JavaScriptSerializer Ser = new JavaScriptSerializer { MaxJsonLength = 16 * 1024 * 1024 };
        private static readonly Regex SafeToken = new Regex(@"^[A-Za-z0-9_\*\?\.\-\s/]{0,64}$", RegexOptions.Compiled);

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

            string action = (context.Request["action"] ?? "").Trim().ToLowerInvariant();
            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                {
                    switch (action)
                    {
                        case "searchts": SearchTs(context); break;
                        case "searches": SearchEs(context); break;
                        case "detailts": DetailTs(context); break;
                        case "detailes": DetailEs(context); break;
                        default:
                            response.StatusCode = 400;
                            WriteJson(response, new { ok = false, error = "action must be searchTs|searchEs|detailTs|detailEs" });
                            break;
                    }
                }
            }
            catch (Exception ex)
            {
                try
                {
                    // W3-6: no stack/SQL to client.
                    try { ErrorUtils.NotifySystemOps(ex, "ds-search"); } catch { }
                    response.Clear();
                    response.StatusCode = 500;
                    response.ContentType = "application/json; charset=utf-8";
                    WriteJson(response, new { ok = false, error = "Data search failed." });
                }
                catch
                {
                    response.StatusCode = 500;
                    response.Write("{\"ok\":false,\"error\":\"handler failure\"}");
                }
            }
        }

        private static string EscapeSql(string s)
        {
            return (s ?? "").Replace("'", "''");
        }

        private static string LikeValue(string raw)
        {
            if (string.IsNullOrEmpty(raw)) return "";
            string s = raw.Trim();
            bool wild = s.IndexOf('*') >= 0 || s.IndexOf('?') >= 0;
            s = s.Replace("*", "%").Replace("?", "_").Replace("'", "''").ToUpperInvariant();
            // Classic chars() appends % only when wildcards used and pattern does not already end with %
            if (wild && !s.EndsWith("%")) s = s + "%";
            return "'" + s + "'";
        }

        private static string OpClause(string alias, string col, string op, string value)
        {
            if (string.IsNullOrEmpty(value)) return "";
            if (!SafeToken.IsMatch(value) && op != "LIKE" && op != "=") return "";
            string a = alias + "." + col;
            op = (op ?? "=").ToUpperInvariant();
            if (op == "LIKE" || value.IndexOf('*') >= 0 || value.IndexOf('?') >= 0)
                return a + " LIKE " + LikeValue(value);
            if (op == "<>" || op == "!=") return a + " <> '" + EscapeSql(value).ToUpperInvariant() + "'";
            if (op == ">" || op == "<" || op == ">=" || op == "<=")
                return a + " " + op + " '" + EscapeSql(value) + "'";
            return a + " = '" + EscapeSql(value).ToUpperInvariant() + "'";
        }

        private static void And(StringBuilder sb, string clause)
        {
            if (string.IsNullOrEmpty(clause)) return;
            if (sb.Length > 0) sb.Append(" AND ");
            sb.Append(clause);
        }

        private static int MaxRecs(HttpContext ctx, string key, int fallback)
        {
            try
            {
                object v = ctx.Application[key];
                if (v != null) return Convert.ToInt32(v);
            }
            catch { }
            return fallback;
        }

        private static void SearchTs(HttpContext ctx)
        {
            var req = ctx.Request;
            string sqlcall1 = OpClause("s", "call1", req["call1Op"] ?? "LIKE", req["call1"]);
            string sqlcall2 = OpClause("a", "call2", req["call2Op"] ?? "LIKE", req["call2"]);
            string sqlbndcde = OpClause("a", "bndcde", req["bndcdeOp"] ?? "=", req["bndcde"]);
            string sqlchid = OpClause("c", "chid", req["chidOp"] ?? "=", req["chid"]);
            var owhere = new StringBuilder();
            And(owhere, OpClause("s", "name", "LIKE", req["name"]));
            And(owhere, OpClause("s", "oper", "LIKE", req["oper"]));
            And(owhere, OpClause("s", "prov", "=", req["prov"]));
            And(owhere, OpClause("s", "stats", "=", req["stats"]));
            And(owhere, OpClause("s", "reg", "=", req["reg"]));
            And(owhere, OpClause("s", "grnd", req["grndOp"] ?? "=", req["grnd"]));
            And(owhere, OpClause("a", "anum", req["anumOp"] ?? "=", req["anum"]));
            And(owhere, OpClause("a", "acode", req["acodeOp"] ?? "LIKE", req["acode"]));
            string sqltx = "";
            string sqlrx = "";
            if (!string.IsNullOrEmpty(req["freqtx"]))
                sqltx = OpClause("c", "freqtx", req["freqtxOp"] ?? "=", req["freqtx"]);
            if (!string.IsNullOrEmpty(req["freqrx"]))
                sqlrx = OpClause("c", "freqrx", req["freqrxOp"] ?? "=", req["freqrx"]);

            string sqllatlong = "";
            string radiusinfo = (req["radiusinfo"] ?? "").Trim();
            Dictionary<string, string> inCircle = null;
            bool radiussearch = false;

            if (!string.IsNullOrEmpty(radiusinfo))
            {
                string[] parts = radiusinfo.Split('^');
                if (parts.Length >= 3)
                {
                    radiussearch = true;
                    int latc = GeoSearch.ParseDegStr(parts[0]);
                    int longc = GeoSearch.ParseDegStr(parts[1]);
                    double radius = Convert.ToDouble(parts[2]);
                    var box = new GeoSearch(latc, longc, radius);
                    string longeast = GeoSearch.ToDegStr(box.BoxEastcSecs);
                    if (longeast.Length == 11) longeast = "0" + longeast;
                    string longwest = GeoSearch.ToDegStr(box.BoxWestcSecs);
                    if (longwest.Length == 11) longwest = "0" + longwest;
                    string latsouth = GeoSearch.ToDegStr(box.BoxSouthcSecs);
                    string latnorth = GeoSearch.ToDegStr(box.BoxNorthcSecs);
                    sqllatlong = "s.strlatit BETWEEN '" + latsouth + "' AND '" + latnorth +
                                 "' AND s.strlongit BETWEEN '" + longeast + "' AND '" + longwest + "'";
                    inCircle = FilterRadiusSites(ctx, latc, longc, radius, sqlcall1, sqlcall2, sqlbndcde, sqlchid, owhere.ToString(), sqllatlong, sqltx, sqlrx);
                }
            }
            else
            {
                And(owhere, OpClause("s", "strlatit", "LIKE", req["strlatit"]));
                And(owhere, OpClause("s", "strlongit", "LIKE", req["strlongit"]));
            }

            if (!string.IsNullOrEmpty(sqllatlong)) And(owhere, sqllatlong);
            if (!string.IsNullOrEmpty(sqltx) && !string.IsNullOrEmpty(sqlrx))
                And(owhere, "(" + sqltx + " OR " + sqlrx + ")");
            else if (!string.IsNullOrEmpty(sqltx)) And(owhere, "(" + sqltx + ")");
            else if (!string.IsNullOrEmpty(sqlrx)) And(owhere, "(" + sqlrx + ")");

            var kwhere = new StringBuilder();
            And(kwhere, sqlcall2);
            And(kwhere, sqlbndcde);
            And(kwhere, sqlchid);

            string connect = "";
            if (!string.IsNullOrEmpty(sqlcall1 + kwhere) && owhere.Length > 0) connect = " AND ";
            string where = sqlcall1 + (kwhere.Length > 0 ? ((string.IsNullOrEmpty(sqlcall1) ? "" : " AND ") + kwhere) : "") +
                           connect + owhere;

            if (string.IsNullOrEmpty(where.Trim()) || where.Trim() == "AND")
            {
                WriteJson(ctx.Response, new { ok = false, error = "Enter at least one search criterion." });
                return;
            }

            // Ensure WHERE has content  -  classic always has fragments; if only empty pieces, fail
            where = where.Trim();
            if (where.StartsWith("AND ")) where = where.Substring(4);

            int max = MaxRecs(ctx, "Max_TS_Ds", 9500);
            string sql = "SELECT DISTINCT s.call1, a.call2, a.bndcde, s.name, s.oper, s.prov, s.strlatit, s.strlongit, s.grnd, a.anum, c.chid " +
                         " FROM (main.mt_site s left outer join main.mt_ante a on s.call1=a.call1)" +
                         " left outer join main.mt_chan c on a.call1 = c.call1 and a.call2 = c.call2 and a.bndcde = c.bndcde " +
                         " WHERE " + where +
                         " ORDER BY s.call1,a.call2,a.bndcde,a.anum,c.chid";

            var sites = new List<object>();
            var links = new List<object>();
            var remotes = new List<object>();
            var seenSite = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var seenLink = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var seenRemote = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            int rowCount = 0;
            bool capped = false;

            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        string call1 = Cell(dr, 0);
                        if (radiussearch && inCircle != null && (!inCircle.ContainsKey(call1) || inCircle[call1] != "1"))
                            continue;

                        string call2 = Cell(dr, 1);
                        string bndcde = Cell(dr, 2);
                        rowCount++;
                        if (rowCount > max) { capped = true; break; }

                        if (seenSite.Add(call1))
                        {
                            sites.Add(new
                            {
                                call1 = call1,
                                name = Cell(dr, 3),
                                oper = Cell(dr, 4),
                                prov = Cell(dr, 5),
                                strlatit = Cell(dr, 6),
                                strlongit = Cell(dr, 7),
                                grnd = Cell(dr, 8)
                            });
                        }
                        if (!string.IsNullOrEmpty(call2) || !string.IsNullOrEmpty(bndcde))
                        {
                            string lkey = call1 + "," + call2 + "," + bndcde;
                            if (seenLink.Add(lkey))
                                links.Add(new { call1 = call1, call2 = call2, bndcde = bndcde });
                            string rkey = call2 + "," + call1 + "," + bndcde;
                            if (!string.IsNullOrEmpty(call2) && seenRemote.Add(rkey))
                                remotes.Add(new { call1 = call2, call2 = call1, bndcde = bndcde });
                        }
                    }
                }
            }

            // keyString format classic: call1}} separated by commas; checks parallel 0/1
            WriteJson(ctx.Response, new
            {
                ok = true,
                maxRecs = max,
                capped = capped,
                owhere = owhere.ToString(),
                kwhere = kwhere.ToString(),
                sites = sites,
                links = links,
                remotes = remotes,
                siteCount = sites.Count,
                linkCount = links.Count,
                remoteCount = remotes.Count
            });
        }

        private static Dictionary<string, string> FilterRadiusSites(
            HttpContext ctx, int latc, int longc, double radius,
            string sqlcall1, string sqlcall2, string sqlbndcde, string sqlchid,
            string owhere, string sqllatlong, string sqltx, string sqlrx)
        {
            // Lightweight pass: select candidate call1 lat/long and mark those within radius.
            var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var where = new StringBuilder();
            And(where, sqlcall1);
            And(where, sqlcall2);
            And(where, sqlbndcde);
            And(where, sqlchid);
            And(where, owhere);
            string w = where.ToString();
            if (string.IsNullOrEmpty(w)) w = "1=1";
            string sql = "SELECT DISTINCT s.call1, s.strlatit, s.strlongit FROM main.mt_site s " +
                         " left outer join main.mt_ante a on s.call1=a.call1 " +
                         " left outer join main.mt_chan c on a.call1=c.call1 and a.call2=c.call2 and a.bndcde=c.bndcde " +
                         " WHERE " + w;
            var box = new GeoSearch(latc, longc, radius);
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        string call1 = Cell(dr, 0);
                        int lat2 = GeoSearch.ParseDegStr(Cell(dr, 1));
                        int long2 = GeoSearch.ParseDegStr(Cell(dr, 2));
                        double dist = box.distance(lat2, long2);
                        result[call1] = dist <= radius ? "1" : "0";
                    }
                }
            }
            return result;
        }

        private static void SearchEs(HttpContext ctx)
        {
            var req = ctx.Request;
            var where = new StringBuilder();
            And(where, OpClause("s", "location", req["locationOp"] ?? "LIKE", req["location"]));
            And(where, OpClause("s", "name", "LIKE", req["name"]));
            And(where, OpClause("s", "oper", "LIKE", req["oper"]));
            And(where, OpClause("s", "prov", "=", req["prov"]));
            And(where, OpClause("s", "stats", "=", req["stats"]));
            And(where, OpClause("s", "grnd", req["grndOp"] ?? "=", req["grnd"]));
            And(where, OpClause("a", "call1", "LIKE", req["call1"]));
            And(where, OpClause("c", "chid", "=", req["chid"]));

            string radiusinfo = (req["radiusinfo"] ?? "").Trim();
            Dictionary<string, string> inCircle = null;
            if (!string.IsNullOrEmpty(radiusinfo))
            {
                string[] parts = radiusinfo.Split('^');
                if (parts.Length >= 3)
                {
                    int latc = GeoSearch.ParseDegStr(parts[0]);
                    int longc = GeoSearch.ParseDegStr(parts[1]);
                    double radius = Convert.ToDouble(parts[2]);
                    var box = new GeoSearch(latc, longc, radius);
                    string longeast = GeoSearch.ToDegStr(box.BoxEastcSecs);
                    if (longeast.Length == 11) longeast = "0" + longeast;
                    string longwest = GeoSearch.ToDegStr(box.BoxWestcSecs);
                    if (longwest.Length == 11) longwest = "0" + longwest;
                    And(where, "s.strlatit BETWEEN '" + GeoSearch.ToDegStr(box.BoxSouthcSecs) + "' AND '" +
                               GeoSearch.ToDegStr(box.BoxNorthcSecs) + "' AND s.strlongit BETWEEN '" +
                               longeast + "' AND '" + longwest + "'");
                    inCircle = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                    // filled after query
                    ctx.Items["esRadius"] = new object[] { latc, longc, radius, box };
                }
            }
            else
            {
                And(where, OpClause("s", "strlatit", "LIKE", req["strlatit"]));
                And(where, OpClause("s", "strlongit", "LIKE", req["strlongit"]));
            }

            if (where.Length == 0)
            {
                WriteJson(ctx.Response, new { ok = false, error = "Enter at least one search criterion." });
                return;
            }

            int max = MaxRecs(ctx, "Max_ES_Ds", 9500);
            string sql = "SELECT DISTINCT s.location, s.name, s.oper, s.prov, s.strlatit, s.strlongit, s.grnd " +
                         " FROM (main.me_site s left outer join main.me_ante a on s.location=a.location)" +
                         " left outer join main.me_chan c on a.location=c.location and a.call1=c.call1 " +
                         " WHERE " + where + " ORDER BY s.location";

            var sites = new List<object>();
            bool capped = false;
            int n = 0;
            object[] rad = ctx.Items["esRadius"] as object[];
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        string loc = Cell(dr, 0);
                        if (rad != null)
                        {
                            var box = (GeoSearch)rad[3];
                            int lat2 = GeoSearch.ParseDegStr(Cell(dr, 4));
                            int long2 = GeoSearch.ParseDegStr(Cell(dr, 5));
                            if (box.distance(lat2, long2) > (double)rad[2]) continue;
                        }
                        n++;
                        if (n > max) { capped = true; break; }
                        sites.Add(new
                        {
                            location = loc,
                            name = Cell(dr, 1),
                            oper = Cell(dr, 2),
                            prov = Cell(dr, 3),
                            strlatit = Cell(dr, 4),
                            strlongit = Cell(dr, 5),
                            grnd = Cell(dr, 6)
                        });
                    }
                }
            }
            WriteJson(ctx.Response, new
            {
                ok = true,
                maxRecs = max,
                capped = capped,
                owhere = where.ToString(),
                sites = sites,
                siteCount = sites.Count
            });
        }

        private static void DetailTs(HttpContext ctx)
        {
            string call1 = (ctx.Request["call1"] ?? "").Trim();
            if (string.IsNullOrEmpty(call1))
            {
                WriteJson(ctx.Response, new { ok = false, error = "call1 required." });
                return;
            }
            var antes = new List<object>();
            var chans = new List<object>();
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(
                    "SELECT call1, call2, bndcde, anum, azmth, aht FROM main.mt_ante WHERE call1='" + EscapeSql(call1) + "' ORDER BY call2, bndcde, anum", cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        antes.Add(new
                        {
                            call1 = Cell(dr, 0),
                            call2 = Cell(dr, 1),
                            bndcde = Cell(dr, 2),
                            anum = Cell(dr, 3),
                            azmth = Cell(dr, 4),
                            aht = Cell(dr, 5)
                        });
                    }
                }
                using (var cmd = new OdbcCommand(
                    "SELECT call1, call2, bndcde, chid, freqtx, freqrx FROM main.mt_chan WHERE call1='" + EscapeSql(call1) + "' ORDER BY call2, bndcde, chid", cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        chans.Add(new
                        {
                            call1 = Cell(dr, 0),
                            call2 = Cell(dr, 1),
                            bndcde = Cell(dr, 2),
                            chid = Cell(dr, 3),
                            freqtx = Cell(dr, 4),
                            freqrx = Cell(dr, 5)
                        });
                    }
                }
            }
            WriteJson(ctx.Response, new { ok = true, call1 = call1, antes = antes, chans = chans });
        }

        private static void DetailEs(HttpContext ctx)
        {
            string location = (ctx.Request["location"] ?? "").Trim();
            if (string.IsNullOrEmpty(location))
            {
                WriteJson(ctx.Response, new { ok = false, error = "location required." });
                return;
            }
            var antes = new List<object>();
            var chans = new List<object>();
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(
                    "SELECT location, call1 FROM main.me_ante WHERE location='" + EscapeSql(location) + "' ORDER BY call1", cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                        antes.Add(new { location = Cell(dr, 0), call1 = Cell(dr, 1) });
                }
                using (var cmd = new OdbcCommand(
                    "SELECT location, call1, chid, freqtx, freqrx FROM main.me_chan WHERE location='" + EscapeSql(location) + "' ORDER BY call1, chid", cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        chans.Add(new
                        {
                            location = Cell(dr, 0),
                            call1 = Cell(dr, 1),
                            chid = Cell(dr, 2),
                            freqtx = Cell(dr, 3),
                            freqrx = Cell(dr, 4)
                        });
                    }
                }
            }
            WriteJson(ctx.Response, new { ok = true, location = location, antes = antes, chans = chans });
        }

        private static string Cell(OdbcDataReader dr, int i)
        {
            if (dr.IsDBNull(i)) return "";
            return Convert.ToString(dr.GetValue(i)) ?? "";
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            response.Write(Ser.Serialize(obj));
        }
    }
}
