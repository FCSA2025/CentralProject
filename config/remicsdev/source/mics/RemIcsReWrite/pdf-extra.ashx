<%@ WebHandler Language="C#" Class="RemIcsReWrite.PdfExtraHandler" %>

using System;
using System.Collections.Generic;
using System.Data.Odbc;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using DBUtilities;
using DBAccess;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>
    /// Phase 6.75  -  TS Link helper, Change of Call Sign, ES Change of Location / Call Sign.
    /// </summary>
    public class PdfExtraHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly Regex ValidName = new Regex(@"^[A-Za-z0-9_]{1,16}$", RegexOptions.Compiled);
        private static readonly JavaScriptSerializer Ser = new JavaScriptSerializer();

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
                        case "chnglist": ChngList(context); break;
                        case "chngsave": ChngSave(context); break;
                        case "chngdelete": ChngDelete(context); break;
                        case "cloclist": ClocList(context); break;
                        case "clocsave": ClocSave(context); break;
                        case "clocdelete": ClocDelete(context); break;
                        case "ccallist": CcalList(context); break;
                        case "ccalsave": CcalSave(context); break;
                        case "ccaldelete": CcalDelete(context); break;
                        case "linksites": LinkSites(context); break;
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
            return ValidName.IsMatch(name) && (filetype == "TS" || filetype == "ES");
        }

        private static string Cell(OdbcDataReader dr, int i)
        {
            if (dr.IsDBNull(i)) return "";
            return (Convert.ToString(dr.GetValue(i)) ?? "").Trim();
        }

        /// <summary>
        /// W4-2: clear both titl.validated and catalog validstat (TSIP reads the catalog).
        /// </summary>
        private static bool Invalidate(HttpContext ctx, string name, string filetype)
        {
            string schema = ctx.Session["s_schema"].ToString();
            string pref = filetype == "ES" ? "fe_" : "ft_";
            string sql = "UPDATE " + schema + "." + pref + name + "_titl SET validated='N'";
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                    cmd.ExecuteNonQuery();
            }
            int tableType = filetype == "ES" ? 5 : 0;
            return UserTable.SetUserValidFlag(schema, tableType, name, "N");
        }

        private static void FailInvalidate(HttpContext ctx)
        {
            WriteJson(ctx.Response, new { ok = false, error = "Saved but catalog valid status could not be updated." });
        }

        private static void ChngList(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype) || filetype != "TS")
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "TS name required." });
                return;
            }
            string schema = ctx.Session["s_schema"].ToString();
            var rows = new List<object>();
            string sql = "SELECT oldcall1, newcall1, name FROM " + schema + ".ft_" + name + "_chng ORDER BY oldcall1";
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                        rows.Add(new { oldcall1 = Cell(dr, 0), newcall1 = Cell(dr, 1), name = Cell(dr, 2) });
                }
            }
            WriteJson(ctx.Response, new { ok = true, rows = rows });
        }

        private static void ChngSave(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype) || filetype != "TS")
            {
                WriteJson(ctx.Response, new { ok = false, error = "TS name required." });
                return;
            }
            string oldc = (ctx.Request["oldcall1"] ?? "").Trim().ToUpperInvariant();
            string newc = (ctx.Request["newcall1"] ?? "").Trim().ToUpperInvariant();
            string sname = (ctx.Request["sitename"] ?? "").Trim().ToUpperInvariant();
            string orig = (ctx.Request["origoldcall1"] ?? "").Trim().ToUpperInvariant();
            if (oldc == "" || newc == "")
            {
                WriteJson(ctx.Response, new { ok = false, error = "oldcall1 and newcall1 required." });
                return;
            }
            if (sname == "")
            {
                WriteJson(ctx.Response, new { ok = false, error = "Must Enter Name field." });
                return;
            }
            string schema = ctx.Session["s_schema"].ToString();
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                if (orig != "")
                {
                    if (!string.Equals(orig, oldc, StringComparison.OrdinalIgnoreCase))
                    {
                        using (var chk = new OdbcCommand(
                            "SELECT count(*) FROM " + schema + ".ft_" + name + "_chng WHERE oldcall1=" + DBUtils.chNull(oldc), cn))
                        {
                            if (Convert.ToInt32(chk.ExecuteScalar()) > 0)
                            {
                                WriteJson(ctx.Response, new { ok = false, error = "A change of call sign for this site already exists." });
                                return;
                            }
                        }
                    }
                    string usql = "UPDATE " + schema + ".ft_" + name + "_chng SET oldcall1=" + DBUtils.chNull(oldc) +
                                  ", newcall1=" + DBUtils.chNull(newc) + ", name=" + DBUtils.chNull(sname) +
                                  " WHERE oldcall1=" + DBUtils.chNull(orig);
                    using (var cmd = new OdbcCommand(usql, cn))
                    {
                        if (cmd.ExecuteNonQuery() == 0)
                        {
                            WriteJson(ctx.Response, new { ok = false, error = "Original change record was not found." });
                            return;
                        }
                    }
                }
                else
                {
                    using (var chk = new OdbcCommand(
                        "SELECT count(*) FROM " + schema + ".ft_" + name + "_chng WHERE oldcall1=" + DBUtils.chNull(oldc), cn))
                    {
                        if (Convert.ToInt32(chk.ExecuteScalar()) > 0)
                        {
                            WriteJson(ctx.Response, new { ok = false, error = "A change of call sign for this site already exists." });
                            return;
                        }
                    }
                    string sql = "INSERT INTO " + schema + ".ft_" + name + "_chng (oldcall1, newcall1, name) VALUES (" +
                                 DBUtils.chNull(oldc) + ", " + DBUtils.chNull(newc) + ", " + DBUtils.chNull(sname) + ")";
                    using (var cmd = new OdbcCommand(sql, cn))
                        cmd.ExecuteNonQuery();
                }
            }
            if (!Invalidate(ctx, name, "TS")) { FailInvalidate(ctx); return; }
            WriteJson(ctx.Response, new { ok = true });
        }

        private static void ChngDelete(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype) || filetype != "TS")
            {
                WriteJson(ctx.Response, new { ok = false, error = "TS name required." });
                return;
            }
            string oldc = (ctx.Request["oldcall1"] ?? "").Trim().ToUpperInvariant();
            string newc = (ctx.Request["newcall1"] ?? "").Trim().ToUpperInvariant();
            string schema = ctx.Session["s_schema"].ToString();
            string sql = "DELETE FROM " + schema + ".ft_" + name + "_chng WHERE oldcall1=" + DBUtils.chNull(oldc) +
                         " AND newcall1=" + DBUtils.chNull(newc);
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                {
                    // W4-21: 0-row delete is failure.
                    if (cmd.ExecuteNonQuery() < 1)
                    {
                        WriteJson(ctx.Response, new { ok = false, error = "Callsign change was not deleted (no matching row)." });
                        return;
                    }
                }
            }
            if (!Invalidate(ctx, name, "TS")) { FailInvalidate(ctx); return; }
            WriteJson(ctx.Response, new { ok = true });
        }

        private static void ClocList(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype) || filetype != "ES")
            {
                WriteJson(ctx.Response, new { ok = false, error = "ES name required." });
                return;
            }
            string schema = ctx.Session["s_schema"].ToString();
            var rows = new List<object>();
            string sql = "SELECT oldlocation, newlocation, name FROM " + schema + ".fe_" + name + "_cloc ORDER BY oldlocation";
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                        rows.Add(new { oldlocation = Cell(dr, 0), newlocation = Cell(dr, 1), name = Cell(dr, 2) });
                }
            }
            WriteJson(ctx.Response, new { ok = true, rows = rows });
        }

        private static void ClocSave(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype) || filetype != "ES")
            {
                WriteJson(ctx.Response, new { ok = false, error = "ES name required." });
                return;
            }
            string oldl = (ctx.Request["oldlocation"] ?? "").Trim().ToUpperInvariant();
            string newl = (ctx.Request["newlocation"] ?? "").Trim().ToUpperInvariant();
            string sname = (ctx.Request["sitename"] ?? "").Trim().ToUpperInvariant();
            string orig = (ctx.Request["origoldlocation"] ?? "").Trim().ToUpperInvariant();
            if (oldl == "" || newl == "")
            {
                WriteJson(ctx.Response, new { ok = false, error = "oldlocation and newlocation required." });
                return;
            }
            string schema = ctx.Session["s_schema"].ToString();
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                if (orig != "")
                {
                    if (!string.Equals(orig, oldl, StringComparison.OrdinalIgnoreCase))
                    {
                        using (var chk = new OdbcCommand(
                            "SELECT count(*) FROM " + schema + ".fe_" + name + "_cloc WHERE oldlocation=" + DBUtils.chNull(oldl), cn))
                        {
                            if (Convert.ToInt32(chk.ExecuteScalar()) > 0)
                            {
                                WriteJson(ctx.Response, new { ok = false, error = "A change of location for this site already exists." });
                                return;
                            }
                        }
                    }
                    string usql = "UPDATE " + schema + ".fe_" + name + "_cloc SET oldlocation=" + DBUtils.chNull(oldl) +
                                  ", newlocation=" + DBUtils.chNull(newl) + ", name=" + DBUtils.chNull(sname) +
                                  " WHERE oldlocation=" + DBUtils.chNull(orig);
                    using (var cmd = new OdbcCommand(usql, cn))
                    {
                        if (cmd.ExecuteNonQuery() == 0)
                        {
                            WriteJson(ctx.Response, new { ok = false, error = "Original change record was not found." });
                            return;
                        }
                    }
                }
                else
                {
                    using (var chk = new OdbcCommand(
                        "SELECT count(*) FROM " + schema + ".fe_" + name + "_cloc WHERE oldlocation=" + DBUtils.chNull(oldl), cn))
                    {
                        if (Convert.ToInt32(chk.ExecuteScalar()) > 0)
                        {
                            WriteJson(ctx.Response, new { ok = false, error = "A change of location for this site already exists." });
                            return;
                        }
                    }
                    string sql = "INSERT INTO " + schema + ".fe_" + name + "_cloc (oldlocation, newlocation, name) VALUES (" +
                                 DBUtils.chNull(oldl) + ", " + DBUtils.chNull(newl) + ", " + DBUtils.chNull(sname) + ")";
                    using (var cmd = new OdbcCommand(sql, cn))
                        cmd.ExecuteNonQuery();
                }
            }
            if (!Invalidate(ctx, name, "ES")) { FailInvalidate(ctx); return; }
            WriteJson(ctx.Response, new { ok = true });
        }

        private static void ClocDelete(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype) || filetype != "ES")
            {
                WriteJson(ctx.Response, new { ok = false, error = "ES name required." });
                return;
            }
            string oldl = (ctx.Request["oldlocation"] ?? "").Trim().ToUpperInvariant();
            string newl = (ctx.Request["newlocation"] ?? "").Trim().ToUpperInvariant();
            string schema = ctx.Session["s_schema"].ToString();
            string sql = "DELETE FROM " + schema + ".fe_" + name + "_cloc WHERE oldlocation=" + DBUtils.chNull(oldl) +
                         " AND newlocation=" + DBUtils.chNull(newl);
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                {
                    // W4-21: 0-row delete is failure.
                    if (cmd.ExecuteNonQuery() < 1)
                    {
                        WriteJson(ctx.Response, new { ok = false, error = "Location change was not deleted (no matching row)." });
                        return;
                    }
                }
            }
            if (!Invalidate(ctx, name, "ES")) { FailInvalidate(ctx); return; }
            WriteJson(ctx.Response, new { ok = true });
        }

        private static void CcalList(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype) || filetype != "ES")
            {
                WriteJson(ctx.Response, new { ok = false, error = "ES name required." });
                return;
            }
            string schema = ctx.Session["s_schema"].ToString();
            var rows = new List<object>();
            string sql = "SELECT oldcallsign, newcallsign FROM " + schema + ".fe_" + name + "_ccal ORDER BY oldcallsign";
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                        rows.Add(new { oldcallsign = Cell(dr, 0), newcallsign = Cell(dr, 1) });
                }
            }
            WriteJson(ctx.Response, new { ok = true, rows = rows });
        }

        private static void CcalSave(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype) || filetype != "ES")
            {
                WriteJson(ctx.Response, new { ok = false, error = "ES name required." });
                return;
            }
            string oldc = (ctx.Request["oldcallsign"] ?? "").Trim().ToUpperInvariant();
            string newc = (ctx.Request["newcallsign"] ?? "").Trim().ToUpperInvariant();
            string orig = (ctx.Request["origoldcallsign"] ?? "").Trim().ToUpperInvariant();
            if (oldc == "" || newc == "")
            {
                WriteJson(ctx.Response, new { ok = false, error = "oldcallsign and newcallsign required." });
                return;
            }
            string schema = ctx.Session["s_schema"].ToString();
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                if (orig != "")
                {
                    if (!string.Equals(orig, oldc, StringComparison.OrdinalIgnoreCase))
                    {
                        using (var chk = new OdbcCommand(
                            "SELECT count(*) FROM " + schema + ".fe_" + name + "_ccal WHERE oldcallsign=" + DBUtils.chNull(oldc), cn))
                        {
                            if (Convert.ToInt32(chk.ExecuteScalar()) > 0)
                            {
                                WriteJson(ctx.Response, new { ok = false, error = "A change of call sign for this site already exists." });
                                return;
                            }
                        }
                    }
                    string usql = "UPDATE " + schema + ".fe_" + name + "_ccal SET oldcallsign=" + DBUtils.chNull(oldc) +
                                  ", newcallsign=" + DBUtils.chNull(newc) +
                                  " WHERE oldcallsign=" + DBUtils.chNull(orig);
                    using (var cmd = new OdbcCommand(usql, cn))
                    {
                        if (cmd.ExecuteNonQuery() == 0)
                        {
                            WriteJson(ctx.Response, new { ok = false, error = "Original change record was not found." });
                            return;
                        }
                    }
                }
                else
                {
                    using (var chk = new OdbcCommand(
                        "SELECT count(*) FROM " + schema + ".fe_" + name + "_ccal WHERE oldcallsign=" + DBUtils.chNull(oldc), cn))
                    {
                        if (Convert.ToInt32(chk.ExecuteScalar()) > 0)
                        {
                            WriteJson(ctx.Response, new { ok = false, error = "A change of call sign for this site already exists." });
                            return;
                        }
                    }
                    string sql = "INSERT INTO " + schema + ".fe_" + name + "_ccal (oldcallsign, newcallsign) VALUES (" +
                                 DBUtils.chNull(oldc) + ", " + DBUtils.chNull(newc) + ")";
                    using (var cmd = new OdbcCommand(sql, cn))
                        cmd.ExecuteNonQuery();
                }
            }
            if (!Invalidate(ctx, name, "ES")) { FailInvalidate(ctx); return; }
            WriteJson(ctx.Response, new { ok = true });
        }

        private static void CcalDelete(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype) || filetype != "ES")
            {
                WriteJson(ctx.Response, new { ok = false, error = "ES name required." });
                return;
            }
            string oldc = (ctx.Request["oldcallsign"] ?? "").Trim().ToUpperInvariant();
            string newc = (ctx.Request["newcallsign"] ?? "").Trim().ToUpperInvariant();
            string schema = ctx.Session["s_schema"].ToString();
            string sql = "DELETE FROM " + schema + ".fe_" + name + "_ccal WHERE oldcallsign=" + DBUtils.chNull(oldc) +
                         " AND newcallsign=" + DBUtils.chNull(newc);
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                {
                    // W4-21: 0-row delete is failure.
                    if (cmd.ExecuteNonQuery() < 1)
                    {
                        WriteJson(ctx.Response, new { ok = false, error = "Callsign change was not deleted (no matching row)." });
                        return;
                    }
                }
            }
            if (!Invalidate(ctx, name, "ES")) { FailInvalidate(ctx); return; }
            WriteJson(ctx.Response, new { ok = true });
        }

        /// <summary>Sites available for linking under a call1 (local PDF + ante pairs).</summary>
        private static void LinkSites(HttpContext ctx)
        {
            string name, filetype;
            if (!ReadPdf(ctx.Request, out name, out filetype) || filetype != "TS")
            {
                WriteJson(ctx.Response, new { ok = false, error = "TS name required." });
                return;
            }
            string call1 = (ctx.Request["call1"] ?? "").Trim().ToUpperInvariant();
            string schema = ctx.Session["s_schema"].ToString();
            var links = new List<object>();
            string sql = "SELECT DISTINCT call1, call2, bndcde FROM " + schema + ".ft_" + name + "_ante";
            if (!string.IsNullOrEmpty(call1))
                sql += " WHERE call1=" + DBUtils.chNull(call1);
            sql += " ORDER BY call1, call2, bndcde";
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                        links.Add(new { call1 = Cell(dr, 0), call2 = Cell(dr, 1), bndcde = Cell(dr, 2) });
                }
            }
            WriteJson(ctx.Response, new
            {
                ok = true,
                links = links,
                note = "TS Link in classic adds tree nodes via verifySite; antennas/channels are keyed by call1/call2/bndcde. Use Ante/Chan panels to create link ends."
            });
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            response.Write(Ser.Serialize(obj));
        }
    }
}
