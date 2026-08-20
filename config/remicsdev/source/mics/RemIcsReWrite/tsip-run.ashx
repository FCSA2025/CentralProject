<%@ WebHandler Language="C#" Class="RemIcsReWrite.TsipRunHandler" %>

using System;
using System.Collections.Generic;
using System.Data.Odbc;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using DBUtilities;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>
    /// Phase 6.5  -  TSIP run get/new/save/dup/delete (parity with tsipParm* + deleteRunName).
    /// </summary>
    public class TsipRunHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly Regex ValidParmName = new Regex(@"^[A-Za-z0-9_]{1,16}$", RegexOptions.Compiled);
        private static readonly Regex ValidRunName = new Regex(@"^[A-Za-z0-9_]{1,5}$", RegexOptions.Compiled);
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
                        case "get": HandleGet(context); break;
                        case "save": HandleSave(context, false); break;
                        case "new": HandleSave(context, true); break;
                        case "dup": HandleDup(context); break;
                        case "delete": HandleDelete(context); break;
                        default:
                            response.StatusCode = 400;
                            WriteJson(response, new { ok = false, error = "action must be get|new|save|dup|delete" });
                            break;
                    }
                }
            }
            catch (Exception ex)
            {
                try
                {
                    response.Clear();
                    response.StatusCode = 500;
                    response.ContentType = "application/json; charset=utf-8";
                    WriteJson(response, new { ok = false, error = ex.Message, detail = ex.ToString() });
                }
                catch
                {
                    response.StatusCode = 500;
                    response.Write("{\"ok\":false,\"error\":\"handler failure\"}");
                }
            }
        }

        private static string ParmTable(HttpContext ctx, string parm)
        {
            return ctx.Session["s_schema"].ToString() + ".tp_" + parm + "_parm";
        }

        private static bool ValidParm(string parm)
        {
            return !string.IsNullOrEmpty(parm) && ValidParmName.IsMatch(parm);
        }

        private static Dictionary<string, string> ReadFields(HttpRequest req)
        {
            var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            string[] keys = {
                "runname","protype","envtype","proname","envname","tsorbout","spherecalc",
                "fsep","coordist","analopt","margin","chancodes","numchan","country",
                "selsites","numcodes","codes","reports","parmparm","arc","cullmarg","hilosecs"
            };
            foreach (string k in keys)
            {
                string v = req[k];
                if (v != null) d[k] = v.Trim();
            }
            return d;
        }

        private static string BuildParmParm(Dictionary<string, string> f)
        {
            if (f.ContainsKey("parmparm") && !string.IsNullOrEmpty(f["parmparm"]))
                return f["parmparm"];
            string cParmParm = "";
            string protype = Get(f, "protype").ToUpperInvariant();
            string envtype = Get(f, "envtype").ToUpperInvariant();
            if (protype == "E" && !string.IsNullOrEmpty(Get(f, "arc")))
                cParmParm = "ARCSTEP=" + Get(f, "arc");
            if (protype == "T" && (envtype == "INTRA" || envtype == "MDB_TS" || envtype == "PDF_TS"))
            {
                if (!string.IsNullOrEmpty(Get(f, "cullmarg")))
                {
                    cParmParm += "CM=" + Get(f, "cullmarg");
                    if (!string.IsNullOrEmpty(Get(f, "hilosecs")))
                        cParmParm += ",HILO=" + Get(f, "hilosecs");
                }
                else if (!string.IsNullOrEmpty(Get(f, "hilosecs")))
                {
                    cParmParm = "HILO=" + Get(f, "hilosecs");
                }
            }
            return cParmParm;
        }

        private static string Get(Dictionary<string, string> f, string k)
        {
            string v;
            return f.TryGetValue(k, out v) ? (v ?? "") : "";
        }

        private static void HandleGet(HttpContext ctx)
        {
            string parm = (ctx.Request["parm"] ?? "").Trim();
            string runname = (ctx.Request["runname"] ?? "").Trim();
            if (!ValidParm(parm) || string.IsNullOrEmpty(runname))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "parm and runname required." });
                return;
            }
            // Match classic tsipParm.aspx SELECT (numcases/numtecases optional via try).
            string sql = "SELECT protype, envtype, proname, envname, tsorbout, spherecalc, fsep, coordist," +
                         " analopt, margin, numchan, chancodes, country, selsites, numcodes, codes," +
                         " runname, reports, parmparm, mdate FROM " + ParmTable(ctx, parm) +
                         " WHERE runname = '" + runname.Replace("'", "''") + "'";
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    if (!dr.Read())
                    {
                        WriteJson(ctx.Response, new { ok = false, error = "Run not found.", sql = sql });
                        return;
                    }
                    string parmparm = Cell(dr, 18);
                    WriteJson(ctx.Response, new
                    {
                        ok = true,
                        parm = parm,
                        record = new
                        {
                            protype = Cell(dr, 0),
                            envtype = Cell(dr, 1),
                            proname = Cell(dr, 2),
                            envname = Cell(dr, 3),
                            tsorbout = Cell(dr, 4),
                            spherecalc = Cell(dr, 5),
                            fsep = Cell(dr, 6),
                            coordist = Cell(dr, 7),
                            analopt = Cell(dr, 8),
                            margin = Cell(dr, 9),
                            numchan = Cell(dr, 10),
                            chancodes = Cell(dr, 11),
                            country = Cell(dr, 12),
                            selsites = Cell(dr, 13),
                            numcodes = Cell(dr, 14),
                            codes = Cell(dr, 15),
                            runname = Cell(dr, 16),
                            reports = Cell(dr, 17),
                            parmparm = parmparm,
                            mdate = Cell(dr, 19),
                            arc = ParseParmToken(parmparm, "ARCSTEP"),
                            cullmarg = ParseParmToken(parmparm, "CM"),
                            hilosecs = ParseParmToken(parmparm, "HILO")
                        }
                    });
                }
            }
        }

        private static string ParseParmToken(string parmparm, string key)
        {
            if (string.IsNullOrEmpty(parmparm)) return "";
            foreach (string part in parmparm.Split(','))
            {
                string p = part.Trim();
                int eq = p.IndexOf('=');
                if (eq <= 0) continue;
                if (string.Equals(p.Substring(0, eq).Trim(), key, StringComparison.OrdinalIgnoreCase))
                    return p.Substring(eq + 1).Trim();
            }
            return "";
        }

        private static void HandleSave(HttpContext ctx, bool isNew)
        {
            string parm = (ctx.Request["parm"] ?? "").Trim();
            var f = ReadFields(ctx.Request);
            string runname = Get(f, "runname");
            if (!ValidParm(parm) || string.IsNullOrEmpty(runname) || !ValidRunName.IsMatch(runname))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "parm and valid runname (1-5 A-Za-z0-9_) required." });
                return;
            }
            string table = ParmTable(ctx, parm);
            string cParmParm = BuildParmParm(f);
            DateTime cur = DateTime.Now;
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                if (isNew)
                {
                    using (var chk = new OdbcCommand("SELECT count(*) FROM " + table + " WHERE runname=" + DBUtils.chNull(runname), cn))
                    {
                        int exist = Convert.ToInt32(chk.ExecuteScalar());
                        if (exist > 0)
                        {
                            WriteJson(ctx.Response, new { ok = false, error = "The Run Name already exists. Please choose another Run Name" });
                            return;
                        }
                    }
                    string sql = "INSERT INTO " + table +
                        " (protype, envtype, proname, envname, tsorbout, spherecalc, fsep, coordist, analopt, " +
                        "margin, chancodes, numchan, country, selsites, numcodes, codes, runname, reports, " +
                        "mdate, mtime, parmparm) VALUES (" +
                        DBUtils.chNull(Get(f, "protype").ToUpperInvariant()) + ", " +
                        DBUtils.chNull(Get(f, "envtype").ToUpperInvariant()) + ", " +
                        DBUtils.chNull(Get(f, "proname")) + ", " +
                        DBUtils.chNull(Get(f, "envname")) + ", " +
                        DBUtils.chNull(string.IsNullOrEmpty(Get(f, "tsorbout")) ? "N" : Get(f, "tsorbout")) + ", " +
                        DBUtils.chNull(Get(f, "spherecalc")) + ", " +
                        DBUtils.numNull(Get(f, "fsep")) + ", " +
                        DBUtils.numNull(Get(f, "coordist")) + ", " +
                        DBUtils.chNull(Get(f, "analopt")) + ", " +
                        DBUtils.numNull(Get(f, "margin")) + ", " +
                        DBUtils.chNull(Get(f, "chancodes")) + ", " +
                        DBUtils.numNull(Get(f, "numchan")) + ", " +
                        DBUtils.chNull(Get(f, "country").ToUpperInvariant()) + ", " +
                        DBUtils.chNull(Get(f, "selsites").ToUpperInvariant()) + ", " +
                        DBUtils.numNull(Get(f, "numcodes")) + ", " +
                        DBUtils.chNull(Get(f, "codes")) + ", " +
                        DBUtils.chNull(runname) + ", " +
                        DBUtils.numNull(string.IsNullOrEmpty(Get(f, "reports")) ? "0" : Get(f, "reports")) + ", " +
                        DBUtils.chNull(cur.ToString("yyyy.MM.dd")) + ", " +
                        DBUtils.chNull(cur.ToString("HH:mm")) + ", " +
                        DBUtils.chNull(cParmParm) + ")";
                    using (var cmd = new OdbcCommand(sql, cn))
                        cmd.ExecuteNonQuery();
                }
                else
                {
                    string orig = (ctx.Request["origRunname"] ?? runname).Trim();
                    string sql = "UPDATE " + table + " SET " +
                        "protype=" + DBUtils.chNull(Get(f, "protype").ToUpperInvariant()) + ", " +
                        "envtype=" + DBUtils.chNull(Get(f, "envtype").ToUpperInvariant()) + ", " +
                        "proname=" + DBUtils.chNull(Get(f, "proname")) + ", " +
                        "envname=" + DBUtils.chNull(Get(f, "envname")) + ", " +
                        "tsorbout=" + DBUtils.chNull(Get(f, "tsorbout")) + ", " +
                        "spherecalc=" + DBUtils.chNull(Get(f, "spherecalc")) + ", " +
                        "fsep=" + DBUtils.numNull(Get(f, "fsep")) + ", " +
                        "coordist=" + DBUtils.numNull(Get(f, "coordist")) + ", " +
                        "analopt=" + DBUtils.chNull(Get(f, "analopt")) + ", " +
                        "margin=" + DBUtils.numNull(Get(f, "margin")) + ", " +
                        "chancodes=" + DBUtils.chNull(Get(f, "chancodes")) + ", " +
                        "numchan=" + DBUtils.numNull(Get(f, "numchan")) + ", " +
                        "country=" + DBUtils.chNull(Get(f, "country").ToUpperInvariant()) + ", " +
                        "selsites=" + DBUtils.chNull(Get(f, "selsites").ToUpperInvariant()) + ", " +
                        "numcodes=" + DBUtils.numNull(Get(f, "numcodes")) + ", " +
                        "codes=" + DBUtils.chNull(Get(f, "codes")) + ", " +
                        "runname=" + DBUtils.chNull(runname) + ", " +
                        "reports=" + DBUtils.numNull(Get(f, "reports")) + ", " +
                        "mdate=" + DBUtils.chNull(cur.ToString("yyyy.MM.dd")) + ", " +
                        "mtime=" + DBUtils.chNull(cur.ToString("HH:mm")) + ", " +
                        "parmparm=" + DBUtils.chNull(cParmParm) +
                        " WHERE runname=" + DBUtils.chNull(orig);
                    using (var cmd = new OdbcCommand(sql, cn))
                        cmd.ExecuteNonQuery();
                }
            }
            WriteJson(ctx.Response, new { ok = true, runname = runname, envtype = Get(f, "envtype") });
        }

        private static void HandleDup(HttpContext ctx)
        {
            string parm = (ctx.Request["parm"] ?? "").Trim();
            string fromRun = (ctx.Request["fromRun"] ?? "").Trim();
            string newRun = (ctx.Request["runname"] ?? "").Trim();
            if (!ValidParm(parm) || string.IsNullOrEmpty(fromRun) || !ValidRunName.IsMatch(newRun))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "parm, fromRun, and new runname (1-5 A-Za-z0-9_) required." });
                return;
            }
            string table = ParmTable(ctx, parm);
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var chk = new OdbcCommand("SELECT count(*) FROM " + table + " WHERE runname=" + DBUtils.chNull(newRun), cn))
                {
                    if (Convert.ToInt32(chk.ExecuteScalar()) > 0)
                    {
                        WriteJson(ctx.Response, new { ok = false, error = "The Run Name already exists." });
                        return;
                    }
                }
                DateTime cur = DateTime.Now;
                string sql = "INSERT INTO " + table +
                    " (protype, envtype, proname, envname, tsorbout, spherecalc, fsep, coordist, analopt, " +
                    "margin, chancodes, numchan, country, selsites, numcodes, codes, runname, reports, " +
                    "mdate, mtime, parmparm) " +
                    "SELECT protype, envtype, proname, envname, tsorbout, spherecalc, fsep, coordist, analopt, " +
                    "margin, chancodes, numchan, country, selsites, numcodes, codes, " +
                    DBUtils.chNull(newRun) + ", reports, " +
                    DBUtils.chNull(cur.ToString("yyyy.MM.dd")) + ", " +
                    DBUtils.chNull(cur.ToString("HH:mm")) + ", parmparm FROM " + table +
                    " WHERE runname=" + DBUtils.chNull(fromRun);
                using (var cmd = new OdbcCommand(sql, cn))
                {
                    int n = cmd.ExecuteNonQuery();
                    if (n < 1)
                    {
                        WriteJson(ctx.Response, new { ok = false, error = "Source run not found." });
                        return;
                    }
                }
            }
            WriteJson(ctx.Response, new { ok = true, runname = newRun });
        }

        private static void HandleDelete(HttpContext ctx)
        {
            string parm = (ctx.Request["parm"] ?? "").Trim();
            string runname = (ctx.Request["runname"] ?? "").Trim();
            if (!ValidParm(parm) || string.IsNullOrEmpty(runname))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "parm and runname required." });
                return;
            }
            string sql = "DELETE FROM " + ParmTable(ctx, parm) + " WHERE runname=" + DBUtils.chNull(runname);
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                    cmd.ExecuteNonQuery();
            }
            WriteJson(ctx.Response, new { ok = true });
        }

        private static string Cell(OdbcDataReader dr, int i)
        {
            if (dr.IsDBNull(i)) return "";
            return (Convert.ToString(dr.GetValue(i)) ?? "").Trim();
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            response.Write(Ser.Serialize(obj));
        }
    }
}
