<%@ WebHandler Language="C#" Class="RemIcsReWrite.PdfEditHandler" %>

using System;
using System.Collections.Generic;
using System.Data.Odbc;
using System.Reflection;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using DBUtilities;
using SesUtilities;
using Tesmenu;
using Ttsmenu;

namespace RemIcsReWrite
{
    /// <summary>
    /// Phase 6.5 — Title / Site / Ante / Chan (+ ES Azimuth) load/save via classic DBIO + SQL lists.
    /// GET/POST action=...
    /// </summary>
    public class PdfEditHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly Regex ValidName = new Regex(@"^[A-Za-z0-9_]{1,16}$", RegexOptions.Compiled);
        private static readonly JavaScriptSerializer Ser = new JavaScriptSerializer { MaxJsonLength = 8 * 1024 * 1024 };

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
                        case "titleget": TitleGet(context); break;
                        case "titlesave": TitleSave(context); break;
                        case "siteslist": SitesList(context); break;
                        case "siteget": SiteGet(context); break;
                        case "sitesave": SiteSave(context, false); break;
                        case "sitenew": SiteSave(context, true); break;
                        case "anteslist": AntesList(context); break;
                        case "anteget": AnteGet(context); break;
                        case "antesave": AnteSave(context, false); break;
                        case "antenew": AnteSave(context, true); break;
                        case "chanslist": ChansList(context); break;
                        case "changet": ChanGet(context); break;
                        case "chansave": ChanSave(context, false); break;
                        case "channew": ChanSave(context, true); break;
                        case "azimslist": AzimsList(context); break;
                        case "azimget": AzimGet(context); break;
                        case "azimsave": AzimSave(context, false); break;
                        case "azimnew": AzimSave(context, true); break;
                        default:
                            response.StatusCode = 400;
                            WriteJson(response, new { ok = false, error = "Unknown action." });
                            break;
                    }
                }
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        private static bool ReadPdf(HttpRequest req, out string name, out string filetype)
        {
            name = (req["name"] ?? "").Trim();
            filetype = (req["filetype"] ?? "TS").Trim().ToUpperInvariant();
            if (!ValidName.IsMatch(name)) return false;
            if (filetype != "TS" && filetype != "ES") return false;
            return true;
        }

        private static string Pref(string filetype)
        {
            return filetype == "ES" ? "fe_" : "ft_";
        }

        private static void InvalidateTitle(HttpContext ctx, string name, string filetype)
        {
            string schema = ctx.Session["s_schema"].ToString();
            string cnstr = ctx.Session["s_cnString"].ToString();
            string titl = schema + "." + Pref(filetype) + name + "_titl";
            using (var cn = new OdbcConnection(cnstr))
            {
                cn.Open();
                using (var cmd = new OdbcCommand("UPDATE " + titl + " SET validated='N'", cn))
                    cmd.ExecuteNonQuery();
            }
        }

        private static void TitleGet(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "Invalid name/filetype." });
                return;
            }
            string schema = ctx.Session["s_schema"].ToString();
            string titl = schema + "." + Pref(filetype) + name + "_titl";
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                string sql = "SELECT validated, namef, source, descr, " +
                    " datepart(day, mdate) AS mDay, datepart(month, mdate) AS mMonth, datepart(year, mdate) AS mYear " +
                    " FROM " + titl;
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    if (!dr.Read())
                    {
                        WriteJson(ctx.Response, new { ok = false, error = "Title row not found." });
                        return;
                    }
                    WriteJson(ctx.Response, new
                    {
                        ok = true,
                        name = name,
                        filetype = filetype,
                        record = new
                        {
                            validated = DBUtils.GetDBString(dr, 0),
                            namef = DBUtils.GetDBString(dr, 1),
                            source = DBUtils.GetDBString(dr, 2),
                            descr = DBUtils.GetDBString(dr, 3),
                            mDay = dr.GetValue(4).ToString(),
                            mMonth = DBUtils.txtMonth(dr.GetValue(5).ToString()),
                            mYear = dr.GetValue(6).ToString()
                        }
                    });
                }
            }
        }

        private static void TitleSave(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "Invalid name/filetype." });
                return;
            }
            string schema = ctx.Session["s_schema"].ToString();
            string titl = schema + "." + Pref(filetype) + name + "_titl";
            string source = ctx.Request["source"] ?? "";
            string descr = ctx.Request["descr"] ?? "";
            string namef = ctx.Request["namef"] ?? "";
            string sql = "UPDATE " + titl + " SET source=" + DBUtils.chNull(source) +
                         ", descr=" + DBUtils.chNull(descr) +
                         ", namef=" + DBUtils.chNull(namef) +
                         ", validated='N'";
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                    cmd.ExecuteNonQuery();
            }
            WriteJson(ctx.Response, new { ok = true });
        }

        private static void SitesList(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "Invalid name/filetype." });
                return;
            }
            string schema = ctx.Session["s_schema"].ToString();
            string siteTable = schema + "." + Pref(filetype) + name + "_site";
            var sites = new List<object>();
            string keyCol = filetype == "ES" ? "location" : "call1";
            string sql = "SELECT " + keyCol + ", name, oper, prov FROM " + siteTable + " ORDER BY " + keyCol;
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        sites.Add(new
                        {
                            key = Cell(dr, 0),
                            name = Cell(dr, 1),
                            oper = Cell(dr, 2),
                            prov = Cell(dr, 3)
                        });
                    }
                }
            }
            WriteJson(ctx.Response, new { ok = true, sites = sites, keyField = keyCol });
        }

        private static void SiteGet(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "Invalid name/filetype." });
                return;
            }
            string key = NormalizeSiteKey((ctx.Request["key"] ?? "").Trim());
            if (string.IsNullOrEmpty(key))
            {
                WriteJson(ctx.Response, new { ok = false, error = "key required." });
                return;
            }
            if (filetype == "ES")
            {
                var dbio = new Tesmenu.DBIO();
                structESsite rec;
                string ret = dbio.ESsiteSelect(name, key, out rec);
                if (ret != "OK") { WriteJson(ctx.Response, new { ok = false, error = ret }); return; }
                WriteJson(ctx.Response, new { ok = true, record = StructToDict(rec) });
            }
            else
            {
                var dbio = new Ttsmenu.DBIO();
                structTSsite rec;
                string ret = dbio.TSsiteSelect(name, key, out rec);
                if (ret != "OK") { WriteJson(ctx.Response, new { ok = false, error = ret }); return; }
                WriteJson(ctx.Response, new { ok = true, record = StructToDict(rec) });
            }
        }

        private static void SiteSave(HttpContext ctx, bool isNew)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "Invalid name/filetype." });
                return;
            }
            var fields = ReadRecord(ctx.Request);
            string ret;
            if (filetype == "ES")
            {
                var dbio = new Tesmenu.DBIO();
                structESsite rec;
                dbio.ESsiteClear(out rec);
                DictToStruct(fields, ref rec);
                ret = isNew ? dbio.ESsiteInsert(name, rec) : dbio.ESsiteUpdate(name, rec);
            }
            else
            {
                var dbio = new Ttsmenu.DBIO();
                structTSsite rec;
                dbio.TSsiteClear(out rec);
                DictToStruct(fields, ref rec);
                ret = isNew ? dbio.TSsiteInsert(name, rec) : dbio.TSsiteUpdate(name, rec);
            }
            if (ret != "OK") { WriteJson(ctx.Response, new { ok = false, error = ret }); return; }
            InvalidateTitle(ctx, name, filetype);
            WriteJson(ctx.Response, new { ok = true });
        }

        private static void AntesList(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "Invalid name/filetype." });
                return;
            }
            string siteKey = (ctx.Request["siteKey"] ?? "").Trim();
            string schema = ctx.Session["s_schema"].ToString();
            string anteTable = schema + "." + Pref(filetype) + name + "_ante";
            var rows = new List<object>();
            string sql;
            if (filetype == "ES")
            {
                sql = "SELECT location, call1 FROM " + anteTable;
                if (!string.IsNullOrEmpty(siteKey))
                    sql += " WHERE location='" + siteKey.Replace("'", "''") + "'";
                sql += " ORDER BY location, call1";
            }
            else
            {
                sql = "SELECT call1, call2, bndcde, anum FROM " + anteTable;
                if (!string.IsNullOrEmpty(siteKey))
                    sql += " WHERE call1='" + siteKey.Replace("'", "''") + "'";
                sql += " ORDER BY call1, call2, bndcde, anum";
            }
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        if (filetype == "ES")
                        {
                            rows.Add(new
                            {
                                location = Cell(dr, 0),
                                call1 = Cell(dr, 1),
                                key = Cell(dr, 0) + "|" + Cell(dr, 1)
                            });
                        }
                        else
                        {
                            string c1 = Cell(dr, 0);
                            string c2 = Cell(dr, 1);
                            string bd = Cell(dr, 2);
                            string an = Cell(dr, 3);
                            rows.Add(new { call1 = c1, call2 = c2, bndcde = bd, anum = an, key = c1 + "|" + c2 + "|" + bd + "|" + an });
                        }
                    }
                }
            }
            WriteJson(ctx.Response, new { ok = true, antes = rows });
        }

        private static void AnteGet(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "Invalid name/filetype." });
                return;
            }
            if (filetype == "ES")
            {
                string location = ctx.Request["location"] ?? "";
                string call1 = ctx.Request["call1"] ?? "";
                var dbio = new Tesmenu.DBIO();
                structESante rec;
                string ret = dbio.ESanteSelect(name, location, call1, out rec);
                if (ret != "OK") { WriteJson(ctx.Response, new { ok = false, error = ret }); return; }
                WriteJson(ctx.Response, new { ok = true, record = StructToDict(rec) });
            }
            else
            {
                string call1 = ctx.Request["call1"] ?? "";
                string call2 = ctx.Request["call2"] ?? "";
                string bndcde = ctx.Request["bndcde"] ?? "";
                string anum = ctx.Request["anum"] ?? "";
                var dbio = new Ttsmenu.DBIO();
                structTSante rec;
                string ret = dbio.TSanteSelect(name, call1, call2, bndcde, anum, out rec);
                if (ret != "OK") { WriteJson(ctx.Response, new { ok = false, error = ret }); return; }
                WriteJson(ctx.Response, new { ok = true, record = StructToDict(rec) });
            }
        }

        private static void AnteSave(HttpContext ctx, bool isNew)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "Invalid name/filetype." });
                return;
            }
            var fields = ReadRecord(ctx.Request);
            string ret;
            if (filetype == "ES")
            {
                var dbio = new Tesmenu.DBIO();
                structESante rec;
                dbio.ESanteClear(out rec);
                DictToStruct(fields, ref rec);
                ret = isNew ? dbio.ESanteInsert(name, rec) : dbio.ESanteUpdate(name, rec);
            }
            else
            {
                var dbio = new Ttsmenu.DBIO();
                structTSante rec;
                dbio.TSanteClear(out rec);
                DictToStruct(fields, ref rec);
                ret = isNew ? dbio.TSanteInsert(name, rec) : dbio.TSanteUpdate(name, rec);
            }
            if (ret != "OK") { WriteJson(ctx.Response, new { ok = false, error = ret }); return; }
            InvalidateTitle(ctx, name, filetype);
            WriteJson(ctx.Response, new { ok = true });
        }

        private static void ChansList(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "Invalid name/filetype." });
                return;
            }
            string siteKey = (ctx.Request["siteKey"] ?? "").Trim();
            string schema = ctx.Session["s_schema"].ToString();
            string chanTable = schema + "." + Pref(filetype) + name + "_chan";
            var rows = new List<object>();
            string sql;
            if (filetype == "ES")
            {
                sql = "SELECT location, call1, chid FROM " + chanTable;
                if (!string.IsNullOrEmpty(siteKey))
                    sql += " WHERE location='" + siteKey.Replace("'", "''") + "'";
                sql += " ORDER BY location, call1, chid";
            }
            else
            {
                sql = "SELECT call1, call2, bndcde, chid FROM " + chanTable;
                if (!string.IsNullOrEmpty(siteKey))
                    sql += " WHERE call1='" + siteKey.Replace("'", "''") + "'";
                sql += " ORDER BY call1, call2, bndcde, chid";
            }
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        if (filetype == "ES")
                        {
                            string loc = Cell(dr, 0);
                            string c1 = Cell(dr, 1);
                            string ch = Cell(dr, 2);
                            rows.Add(new { location = loc, call1 = c1, chid = ch, key = loc + "|" + c1 + "|" + ch });
                        }
                        else
                        {
                            string c1 = Cell(dr, 0);
                            string c2 = Cell(dr, 1);
                            string bd = Cell(dr, 2);
                            string ch = Cell(dr, 3);
                            rows.Add(new { call1 = c1, call2 = c2, bndcde = bd, chid = ch, key = c1 + "|" + c2 + "|" + bd + "|" + ch });
                        }
                    }
                }
            }
            WriteJson(ctx.Response, new { ok = true, chans = rows });
        }

        private static void ChanGet(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "Invalid name/filetype." });
                return;
            }
            if (filetype == "ES")
            {
                var dbio = new Tesmenu.DBIO();
                structESchan rec;
                string ret = dbio.ESchanSelect(name, ctx.Request["location"] ?? "", ctx.Request["call1"] ?? "", ctx.Request["chid"] ?? "", out rec);
                if (ret != "OK") { WriteJson(ctx.Response, new { ok = false, error = ret }); return; }
                WriteJson(ctx.Response, new { ok = true, record = StructToDict(rec) });
            }
            else
            {
                var dbio = new Ttsmenu.DBIO();
                structTSchan rec;
                string ret = dbio.TSchanSelect(name, ctx.Request["call1"] ?? "", ctx.Request["call2"] ?? "",
                    ctx.Request["bndcde"] ?? "", ctx.Request["chid"] ?? "", out rec);
                if (ret != "OK") { WriteJson(ctx.Response, new { ok = false, error = ret }); return; }
                WriteJson(ctx.Response, new { ok = true, record = StructToDict(rec) });
            }
        }

        private static void ChanSave(HttpContext ctx, bool isNew)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "Invalid name/filetype." });
                return;
            }
            var fields = ReadRecord(ctx.Request);
            string ret;
            if (filetype == "ES")
            {
                var dbio = new Tesmenu.DBIO();
                structESchan rec;
                dbio.ESchanClear(out rec);
                DictToStruct(fields, ref rec);
                ret = isNew ? dbio.ESchanInsert(name, rec) : dbio.ESchanUpdate(name, rec);
            }
            else
            {
                var dbio = new Ttsmenu.DBIO();
                structTSchan rec;
                dbio.TSchanClear(out rec);
                DictToStruct(fields, ref rec);
                ret = isNew ? dbio.TSchanInsert(name, rec) : dbio.TSchanUpdate(name, rec);
            }
            if (ret != "OK") { WriteJson(ctx.Response, new { ok = false, error = ret }); return; }
            InvalidateTitle(ctx, name, filetype);
            WriteJson(ctx.Response, new { ok = true });
        }

        private static void AzimsList(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype) || filetype != "ES")
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "ES filetype required." });
                return;
            }
            string siteKey = (ctx.Request["siteKey"] ?? "").Trim();
            string call1 = (ctx.Request["call1"] ?? "").Trim();
            string schema = ctx.Session["s_schema"].ToString();
            string azTable = schema + ".fe_" + name + "_azim";
            var rows = new List<object>();
            string sql = "SELECT location, call1, azim FROM " + azTable + " WHERE 1=1";
            if (!string.IsNullOrEmpty(siteKey)) sql += " AND location='" + siteKey.Replace("'", "''") + "'";
            if (!string.IsNullOrEmpty(call1)) sql += " AND call1='" + call1.Replace("'", "''") + "'";
            sql += " ORDER BY location, call1, azim";
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        string loc = Cell(dr, 0);
                        string c1 = Cell(dr, 1);
                        string az = Cell(dr, 2);
                        rows.Add(new { location = loc, call1 = c1, azim = az, key = loc + "|" + c1 + "|" + az });
                    }
                }
            }
            WriteJson(ctx.Response, new { ok = true, azims = rows });
        }

        private static void AzimGet(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype) || filetype != "ES")
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "ES filetype required." });
                return;
            }
            var dbio = new Tesmenu.DBIO();
            structESazim rec;
            string ret = dbio.ESazimSelect(name, ctx.Request["location"] ?? "", ctx.Request["call1"] ?? "", ctx.Request["azim"] ?? "", out rec);
            if (ret != "OK") { WriteJson(ctx.Response, new { ok = false, error = ret }); return; }
            WriteJson(ctx.Response, new { ok = true, record = StructToDict(rec) });
        }

        private static void AzimSave(HttpContext ctx, bool isNew)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype) || filetype != "ES")
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "ES filetype required." });
                return;
            }
            var fields = ReadRecord(ctx.Request);
            var dbio = new Tesmenu.DBIO();
            structESazim rec;
            dbio.ESazimClear(out rec);
            DictToStruct(fields, ref rec);
            string ret = isNew ? dbio.ESazimInsert(name, rec) : dbio.ESazimUpdate(name, rec);
            if (ret != "OK") { WriteJson(ctx.Response, new { ok = false, error = ret }); return; }
            InvalidateTitle(ctx, name, filetype);
            WriteJson(ctx.Response, new { ok = true });
        }

        private static Dictionary<string, object> ReadRecord(HttpRequest req)
        {
            string json = req["record"] ?? req.Form["record"];
            if (!string.IsNullOrEmpty(json))
            {
                try
                {
                    var d = Ser.DeserializeObject(json) as Dictionary<string, object>;
                    if (d != null) return d;
                }
                catch { /* fall through */ }
            }
            var flat = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
            foreach (string key in req.Form.AllKeys)
            {
                if (key == null || key == "action" || key == "name" || key == "filetype" || key == "record") continue;
                flat[key] = req.Form[key];
            }
            return flat;
        }

        private static Dictionary<string, object> StructToDict<T>(T value) where T : struct
        {
            var d = new Dictionary<string, object>();
            foreach (FieldInfo f in typeof(T).GetFields(BindingFlags.Public | BindingFlags.Instance))
            {
                object v = f.GetValue(value);
                d[f.Name] = v == null ? "" : Convert.ToString(v);
            }
            return d;
        }

        private static void DictToStruct<T>(Dictionary<string, object> d, ref T value) where T : struct
        {
            object boxed = value;
            foreach (FieldInfo f in typeof(T).GetFields(BindingFlags.Public | BindingFlags.Instance))
            {
                object raw;
                if (!TryGet(d, f.Name, out raw) || raw == null) continue;
                f.SetValue(boxed, Convert.ToString(raw));
            }
            value = (T)boxed;
        }

        private static bool TryGet(Dictionary<string, object> d, string name, out object raw)
        {
            if (d.TryGetValue(name, out raw)) return true;
            foreach (var kv in d)
            {
                if (string.Equals(kv.Key, name, StringComparison.OrdinalIgnoreCase))
                {
                    raw = kv.Value;
                    return true;
                }
            }
            raw = null;
            return false;
        }

        private static string TreeKeyField(string key, int index)
        {
            if (string.IsNullOrEmpty(key)) return key ?? "";
            if (key.IndexOf('.') < 0) return key;
            var parts = key.Split('.');
            return parts.Length > index ? parts[index] : key;
        }

        private static string NormalizeSiteKey(string key)
        {
            if (string.IsNullOrEmpty(key)) return key;
            if (key.IndexOf('.') < 0) return key;
            var prefix = key.Substring(0, 1);
            if (prefix == "d" || prefix == "s") return TreeKeyField(key, 2);
            return key;
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
