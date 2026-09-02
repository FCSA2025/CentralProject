<%@ WebHandler Language="C#" Class="RemIcsReWrite.SdfEditHandler" %>

using System;
using System.Collections.Generic;
using System.Data.Odbc;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using DBAccess;
using DBUtilities;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>
    /// SDF record load/save for Ante, Band, and remaining types, plus child rows.
    /// </summary>
    public class SdfEditHandler : IHttpHandler, IRequiresSessionState
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
                        case "anteget": AnteGet(context); break;
                        case "antesave": AnteSave(context, false); break;
                        case "antenew": AnteSave(context, true); break;
                        case "bandget": BandGet(context); break;
                        case "bandsave": BandSave(context, false); break;
                        case "bandnew": BandSave(context, true); break;
                        case "recget": RecGet(context); break;
                        case "recsave": RecSave(context, false); break;
                        case "recnew": RecSave(context, true); break;
                        case "childget": ChildGet(context); break;
                        case "childsave": ChildSave(context, false); break;
                        case "childnew": ChildSave(context, true); break;
                        case "childdelete": ChildDelete(context); break;
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

        private static bool ReadName(HttpRequest req, out string name)
        {
            name = (req["name"] ?? "").Trim();
            string key = (req["key"] ?? "").Trim();
            if (key.IndexOf('^') >= 0)
            {
                string[] parts = key.Split('^');
                if (parts.Length >= 2 && string.IsNullOrEmpty(name))
                    name = parts[1];
            }
            return ValidName.IsMatch(name);
        }

        private static string ReadKey(HttpRequest req)
        {
            string key = (req["key"] ?? "").Trim();
            if (key.IndexOf('^') >= 0)
            {
                string[] parts = key.Split('^');
                if (parts.Length >= 3) key = parts[2];
            }
            return key;
        }

        private static bool ValidAcode(string acode)
        {
            return !string.IsNullOrEmpty(acode) && acode.Length <= 12 && acode.IndexOf('\'') < 0;
        }

        private static bool ValidBndcde(string bndcde)
        {
            return !string.IsNullOrEmpty(bndcde) && bndcde.Length <= 4 && bndcde.IndexOf('\'') < 0;
        }

        private static string SqlLit(string value)
        {
            return "'" + (value ?? "").Replace("'", "''") + "'";
        }

        private static string Cell(OdbcDataReader dr, int i)
        {
            if (dr.IsDBNull(i)) return "";
            return Convert.ToString(dr.GetValue(i)) ?? "";
        }

        private static string NumCell(OdbcDataReader dr, int i, int decimals)
        {
            if (dr.IsDBNull(i)) return "";
            try
            {
                return Convert.ToDouble(dr.GetValue(i)).ToString("F" + decimals);
            }
            catch
            {
                return Cell(dr, i);
            }
        }

        private static string Req(HttpRequest req, string name)
        {
            return req[name] ?? "";
        }

        private static void AnteResetAnip(HttpContext ctx, string name, string acode)
        {
            string schema = ctx.Session["s_schema"].ToString();
            string anteTable = schema + ".su_" + name + "_ante";
            string antdTable = schema + ".su_" + name + "_antd";
            string sql = "UPDATE " + anteTable +
                " SET anip = (SELECT count(*) FROM " + antdTable + " WHERE acode=" + SqlLit(acode) + ")" +
                " WHERE acode=" + SqlLit(acode);
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                    cmd.ExecuteNonQuery();
            }
        }

        private static List<object> AnteDiscrRows(HttpContext ctx, string name, string acode)
        {
            var rows = new List<object>();
            string schema = ctx.Session["s_schema"].ToString();
            string antdTable = schema + ".su_" + name + "_antd";
            string sql = "SELECT cmd, antang, dcov, dxpv, dcoh, dxph, dtilt, interpstat" +
                " FROM " + antdTable + " WHERE acode=" + SqlLit(acode) + " ORDER BY antang";
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        rows.Add(new
                        {
                            cmd = Cell(dr, 0),
                            antang = NumCell(dr, 1, 2),
                            dcov = NumCell(dr, 2, 2),
                            dxpv = NumCell(dr, 3, 2),
                            dcoh = NumCell(dr, 4, 2),
                            dxph = NumCell(dr, 5, 2),
                            dtilt = NumCell(dr, 6, 2),
                            interpstat = Cell(dr, 7)
                        });
                    }
                }
            }
            return rows;
        }

        private static bool AnteInterpolated(HttpContext ctx, string name, string acode)
        {
            string schema = ctx.Session["s_schema"].ToString();
            string antdTable = schema + ".su_" + name + "_antd";
            string sql = "SELECT COUNT(*) FROM " + antdTable +
                " WHERE acode=" + SqlLit(acode) + " AND interpstat IS NOT NULL AND interpstat <> 0";
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                {
                    object n = cmd.ExecuteScalar();
                    return n != null && Convert.ToInt32(n) > 0;
                }
            }
        }

        private static bool AnteExists(HttpContext ctx, string name, string acode)
        {
            string schema = ctx.Session["s_schema"].ToString();
            string anteTable = schema + ".su_" + name + "_ante";
            string sql = "SELECT acode FROM " + anteTable + " WHERE acode=" + SqlLit(acode);
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                    return dr.Read();
            }
        }

        private static void AnteCopyDiscr(HttpContext ctx, string name, string oldAcode, string newAcode)
        {
            if (string.IsNullOrEmpty(oldAcode) || string.Equals(oldAcode, newAcode, StringComparison.OrdinalIgnoreCase))
                return;
            string schema = ctx.Session["s_schema"].ToString();
            string antdTable = schema + ".su_" + name + "_antd";
            string sql = "INSERT INTO " + antdTable +
                " (cmd, acode, antang, dcov, dxpv, dcoh, dxph, dtilt, interpstat, mdate, mtime)" +
                " SELECT 'A'," + SqlLit(newAcode) + ",antang, dcov, dxpv, dcoh, dxph, dtilt, interpstat, mdate, mtime" +
                " FROM " + antdTable + " WHERE acode=" + SqlLit(oldAcode);
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                    cmd.ExecuteNonQuery();
            }
        }

        private static void AnteGet(HttpContext ctx)
        {
            string name;
            if (!ReadName(ctx.Request, out name))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "Invalid SDF name." });
                return;
            }
            string acode = ReadKey(ctx.Request);
            if (string.IsNullOrEmpty(acode)) acode = (ctx.Request["acode"] ?? "").Trim();
            if (!ValidAcode(acode))
            {
                WriteJson(ctx.Response, new { ok = false, error = "Antenna code required." });
                return;
            }

            AnteResetAnip(ctx, name, acode);

            string schema = ctx.Session["s_schema"].ToString();
            string anteTable = schema + ".su_" + name + "_ante";
            string sql = "SELECT cmd, acode, axtype, again, axref, abw, arms, aband, amanu, apattern," +
                " amodel, adesc, antype, aftbr, lofreq, hifreq, bandcodes, ax0, anip," +
                " datepart(day, mdate), datepart(month, mdate), datepart(year, mdate)" +
                " FROM " + anteTable + " WHERE acode=" + SqlLit(acode);
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    if (!dr.Read())
                    {
                        WriteJson(ctx.Response, new { ok = false, error = "No record found for acode: " + acode });
                        return;
                    }
                    var rec = new
                    {
                        cmd = Cell(dr, 0),
                        acode = Cell(dr, 1),
                        axtype = Cell(dr, 2),
                        again = NumCell(dr, 3, 1),
                        axref = Cell(dr, 4),
                        abw = NumCell(dr, 5, 1),
                        arms = Cell(dr, 6),
                        aband = Cell(dr, 7),
                        amanu = Cell(dr, 8),
                        apattern = Cell(dr, 9),
                        amodel = Cell(dr, 10),
                        adesc = Cell(dr, 11),
                        antype = Cell(dr, 12),
                        aftbr = NumCell(dr, 13, 1),
                        lofreq = NumCell(dr, 14, 2),
                        hifreq = NumCell(dr, 15, 2),
                        bandcodes = Cell(dr, 16),
                        ax0 = NumCell(dr, 17, 2),
                        anip = Cell(dr, 18),
                        mDay = Cell(dr, 19),
                        mMonth = DBUtils.txtMonth(Cell(dr, 20)),
                        mYear = Cell(dr, 21)
                    };
                    dr.Close();
                    WriteJson(ctx.Response, new
                    {
                        ok = true,
                        name = name,
                        key = rec.acode,
                        record = rec,
                        discr = AnteDiscrRows(ctx, name, acode),
                        interpolated = AnteInterpolated(ctx, name, acode)
                    });
                }
            }
        }

        private static void AnteSave(HttpContext ctx, bool isNew)
        {
            string name;
            if (!ReadName(ctx.Request, out name))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "Invalid SDF name." });
                return;
            }
            string acode = (ctx.Request["acode"] ?? ReadKey(ctx.Request) ?? "").Trim().ToUpperInvariant();
            if (!ValidAcode(acode))
            {
                WriteJson(ctx.Response, new { ok = false, error = "You must enter an antenna code to continue" });
                return;
            }

            if (isNew && AnteExists(ctx, name, acode))
            {
                WriteJson(ctx.Response, new { ok = false, error = "The Antenna Code " + acode + " already exists in this file.  Please enter a new value." });
                return;
            }

            string schema = ctx.Session["s_schema"].ToString();
            string anteTable = schema + ".su_" + name + "_ante";
            string cmdVal = (Req(ctx.Request, "cmd") ?? "").Trim().ToUpperInvariant();
            if (isNew) cmdVal = "A";
            string adesc = DBUtils.charQuote((Req(ctx.Request, "adesc") ?? "").ToUpperInvariant());
            string sql;
            if (isNew)
            {
                sql = "INSERT INTO " + anteTable +
                    " (cmd, recstat, acode, axtype, again, axref, abw, arms, aband, amanu, apattern," +
                    " amodel, anip, ax0, adesc, antype, aftbr, lofreq, hifreq, bandcodes) VALUES (" +
                    "'A','U'," + SqlLit(acode) + "," +
                    DBUtils.numNull(Req(ctx.Request, "axtype")) + "," +
                    DBUtils.numNull(Req(ctx.Request, "again")) + "," +
                    DBUtils.chNull((Req(ctx.Request, "axref") ?? "").ToUpperInvariant()) + "," +
                    DBUtils.numNull(Req(ctx.Request, "abw")) + "," +
                    DBUtils.numNull(Req(ctx.Request, "arms")) + "," +
                    DBUtils.chNull((Req(ctx.Request, "aband") ?? "").ToUpperInvariant()) + "," +
                    DBUtils.chNull((Req(ctx.Request, "amanu") ?? "").ToUpperInvariant()) + "," +
                    DBUtils.chNull((Req(ctx.Request, "apattern") ?? "").ToUpperInvariant()) + "," +
                    DBUtils.chNull((Req(ctx.Request, "amodel") ?? "").ToUpperInvariant()) + "," +
                    DBUtils.numNull(Req(ctx.Request, "anip")) + "," +
                    DBUtils.numNull(Req(ctx.Request, "ax0")) + "," +
                    DBUtils.chNull(adesc) + "," +
                    DBUtils.chNull((Req(ctx.Request, "antype") ?? "").ToUpperInvariant()) + "," +
                    DBUtils.numNull(Req(ctx.Request, "aftbr")) + "," +
                    DBUtils.numNull(Req(ctx.Request, "lofreq")) + "," +
                    DBUtils.numNull(Req(ctx.Request, "hifreq")) + "," +
                    DBUtils.chNull((Req(ctx.Request, "bandcodes") ?? "").ToUpperInvariant()) + ")";
            }
            else
            {
                sql = "UPDATE " + anteTable + " SET " +
                    "cmd=" + SqlLit(cmdVal) + ", recstat='U', " +
                    "axtype=" + DBUtils.numNull(Req(ctx.Request, "axtype")) + ", " +
                    "again=" + DBUtils.numNull(Req(ctx.Request, "again")) + ", " +
                    "axref=" + DBUtils.chNull((Req(ctx.Request, "axref") ?? "").ToUpperInvariant()) + ", " +
                    "abw=" + DBUtils.numNull(Req(ctx.Request, "abw")) + ", " +
                    "arms=" + DBUtils.numNull(Req(ctx.Request, "arms")) + ", " +
                    "aband=" + DBUtils.chNull((Req(ctx.Request, "aband") ?? "").ToUpperInvariant()) + ", " +
                    "amanu=" + DBUtils.chNull((Req(ctx.Request, "amanu") ?? "").ToUpperInvariant()) + ", " +
                    "apattern=" + DBUtils.chNull((Req(ctx.Request, "apattern") ?? "").ToUpperInvariant()) + ", " +
                    "amodel=" + DBUtils.chNull((Req(ctx.Request, "amodel") ?? "").ToUpperInvariant()) + ", " +
                    "adesc=" + DBUtils.chNull(adesc) + ", " +
                    "antype=" + DBUtils.chNull((Req(ctx.Request, "antype") ?? "").ToUpperInvariant()) + ", " +
                    "aftbr=" + DBUtils.numNull(Req(ctx.Request, "aftbr")) + ", " +
                    "lofreq=" + DBUtils.numNull(Req(ctx.Request, "lofreq")) + ", " +
                    "hifreq=" + DBUtils.numNull(Req(ctx.Request, "hifreq")) + ", " +
                    "bandcodes=" + DBUtils.chNull((Req(ctx.Request, "bandcodes") ?? "").ToUpperInvariant()) + ", " +
                    "ax0=" + DBUtils.numNull(Req(ctx.Request, "ax0")) +
                    " WHERE acode=" + SqlLit(acode);
            }

            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                    cmd.ExecuteNonQuery();
            }

            if (isNew)
            {
                string orig = (ctx.Request["origAcode"] ?? "").Trim();
                if (!string.IsNullOrEmpty(orig) && ValidAcode(orig))
                    AnteCopyDiscr(ctx, name, orig, acode);
            }

            if (!UserTable.SetUserValidFlag(schema, 301, name, "N"))
            {
                WriteJson(ctx.Response, new { ok = false, error = "ERROR updating valid status" });
                return;
            }
            WriteJson(ctx.Response, new { ok = true, key = acode });
        }

        private static bool BandExists(HttpContext ctx, string name, string bndcde)
        {
            string schema = ctx.Session["s_schema"].ToString();
            string bandTable = schema + ".su_" + name + "_band";
            string sql = "SELECT bndcde FROM " + bandTable + " WHERE bndcde=" + SqlLit(bndcde);
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                    return dr.Read();
            }
        }

        private static void BandGet(HttpContext ctx)
        {
            string name;
            if (!ReadName(ctx.Request, out name))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "Invalid SDF name." });
                return;
            }
            string bndcde = ReadKey(ctx.Request);
            if (string.IsNullOrEmpty(bndcde)) bndcde = (ctx.Request["bndcde"] ?? "").Trim();
            if (!ValidBndcde(bndcde))
            {
                WriteJson(ctx.Response, new { ok = false, error = "Band code required." });
                return;
            }

            string schema = ctx.Session["s_schema"].ToString();
            string bandTable = schema + ".su_" + name + "_band";
            string sql = "SELECT cmd, bandbitpos, blo, bmidf, bhi, badj," +
                " datepart(day, mdate), datepart(month, mdate), datepart(year, mdate)" +
                " FROM " + bandTable + " WHERE bndcde=" + SqlLit(bndcde);
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    if (!dr.Read())
                    {
                        WriteJson(ctx.Response, new { ok = false, error = "No record found for band: " + bndcde });
                        return;
                    }
                    WriteJson(ctx.Response, new
                    {
                        ok = true,
                        name = name,
                        key = bndcde,
                        record = new
                        {
                            cmd = Cell(dr, 0),
                            bndcde = bndcde,
                            bandbitpos = Cell(dr, 1),
                            blo = NumCell(dr, 2, 2),
                            bmidf = NumCell(dr, 3, 2),
                            bhi = NumCell(dr, 4, 2),
                            badj = Cell(dr, 5),
                            mDay = Cell(dr, 6),
                            mMonth = DBUtils.txtMonth(Cell(dr, 7)),
                            mYear = Cell(dr, 8)
                        }
                    });
                }
            }
        }

        private static void BandSave(HttpContext ctx, bool isNew)
        {
            string name;
            if (!ReadName(ctx.Request, out name))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "Invalid SDF name." });
                return;
            }
            string bndcde = (ctx.Request["bndcde"] ?? ReadKey(ctx.Request) ?? "").Trim().ToUpperInvariant();
            if (!ValidBndcde(bndcde))
            {
                WriteJson(ctx.Response, new { ok = false, error = "You must enter a Band Code to continue" });
                return;
            }

            if (isNew && BandExists(ctx, name, bndcde))
            {
                WriteJson(ctx.Response, new { ok = false, error = "A band already exists in this file with this key" });
                return;
            }

            string schema = ctx.Session["s_schema"].ToString();
            string bandTable = schema + ".su_" + name + "_band";
            string cmdVal = (Req(ctx.Request, "cmd") ?? "").Trim().ToUpperInvariant();
            string sql;
            if (isNew)
            {
                sql = "INSERT INTO " + bandTable +
                    " (cmd, recstat, bndcde, blo, bmidf, bhi, badj) VALUES (" +
                    "'A','U'," + SqlLit(bndcde) + "," +
                    DBUtils.numNull(Req(ctx.Request, "blo")) + "," +
                    DBUtils.numNull(Req(ctx.Request, "bmidf")) + "," +
                    DBUtils.numNull(Req(ctx.Request, "bhi")) + "," +
                    DBUtils.chNull((Req(ctx.Request, "badj") ?? "").ToUpperInvariant()) + ")";
            }
            else
            {
                sql = "UPDATE " + bandTable + " SET " +
                    "cmd=" + SqlLit(cmdVal) + ", recstat='U', " +
                    "blo=" + DBUtils.numNull(Req(ctx.Request, "blo")) + ", " +
                    "bmidf=" + DBUtils.numNull(Req(ctx.Request, "bmidf")) + ", " +
                    "bhi=" + DBUtils.numNull(Req(ctx.Request, "bhi")) + ", " +
                    "badj=" + DBUtils.chNull((Req(ctx.Request, "badj") ?? "").ToUpperInvariant()) +
                    " WHERE bndcde=" + SqlLit(bndcde);
            }

            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                    cmd.ExecuteNonQuery();
            }

            if (!UserTable.SetUserValidFlag(schema, 300, name, "N"))
            {
                WriteJson(ctx.Response, new { ok = false, error = "ERROR updating valid status" });
                return;
            }
            WriteJson(ctx.Response, new { ok = true, key = bndcde });
        }

        private sealed class RecField
        {
            public string Name;
            public string Kind;
            public bool IsKey;
            public int Decimals;
            public string DatePrefix;
            public RecField(string name, string kind, bool isKey, int decimals, string datePrefix)
            {
                Name = name; Kind = kind; IsKey = isKey; Decimals = decimals; DatePrefix = datePrefix;
            }
        }

        private sealed class RecSpec
        {
            public string Type;
            public string Suffix;
            public int ValidFlag;
            public string KeyMsg;
            public RecField[] Fields;
            public string ChildSuffix;
            public string ChildKey;
        }

        private static RecSpec FindSpec(string type)
        {
            type = (type ?? "").Trim();
            if (type.Equals("Eqpt", StringComparison.OrdinalIgnoreCase))
                return new RecSpec { Type = "Eqpt", Suffix = "eqpt", ValidFlag = 305, KeyMsg = "You must enter an Equipment Code to continue",
                    Fields = new[] {
                        new RecField("ecode", "ch", true, 0, null), new RecField("etraf", "ch", false, 0, null),
                        new RecField("estab", "num", false, 6, null), new RecField("emission", "ch", false, 0, null),
                        new RecField("exref", "ch", false, 0, null), new RecField("ebndcde", "ch", false, 0, null),
                        new RecField("etype", "ch", false, 0, null), new RecField("emanu", "ch", false, 0, null),
                        new RecField("emodel", "ch", false, 0, null), new RecField("edesc", "quote", false, 0, null),
                        new RecField("e1stif", "num", false, 1, null), new RecField("e2ndif", "num", false, 1, null),
                        new RecField("thhold", "num", false, 1, null)
                    } };
            if (type.Equals("Oper", StringComparison.OrdinalIgnoreCase))
                return new RecSpec { Type = "Oper", Suffix = "oper", ValidFlag = 308, KeyMsg = "You must enter an Operator code to continue",
                    Fields = new[] {
                        new RecField("oper", "ch", true, 0, null), new RecField("nameop", "quote", false, 0, null),
                        new RecField("admin", "quote", false, 0, null), new RecField("cooper", "quote", false, 0, null),
                        new RecField("mdbm", "quote", false, 0, null), new RecField("addr", "quote", false, 0, null),
                        new RecField("city", "quote", false, 0, null), new RecField("prstat", "ch", false, 0, null),
                        new RecField("zippc", "ch", false, 0, null), new RecField("namep", "quote", false, 0, null),
                        new RecField("email", "ch", false, 0, null), new RecField("dept", "quote", false, 0, null),
                        new RecField("phonep", "ch", false, 0, null), new RecField("opnote", "quote", false, 0, null),
                        new RecField("faxnum", "ch", false, 0, null)
                    } };
            if (type.Equals("Note", StringComparison.OrdinalIgnoreCase))
                return new RecSpec { Type = "Note", Suffix = "note", ValidFlag = 306, KeyMsg = "You must enter Operator and Note Number to continue",
                    Fields = new[] {
                        new RecField("oper", "ch", true, 0, null), new RecField("nonum", "ch", true, 0, null),
                        new RecField("note", "quote", false, 0, null)
                    } };
            if (type.Equals("Traf", StringComparison.OrdinalIgnoreCase))
                return new RecSpec { Type = "Traf", Suffix = "traf", ValidFlag = 314, KeyMsg = "You must enter Traffic Code and Equipment Code to continue",
                    Fields = new[] {
                        new RecField("trafcode", "ch", true, 0, null), new RecField("ecode", "ch", true, 0, null),
                        new RecField("xreftrcde", "ch", false, 0, null), new RecField("xrefeqcde", "ch", false, 0, null),
                        new RecField("trdesc", "quote", false, 0, null)
                    } };
            if (type.Equals("Rout", StringComparison.OrdinalIgnoreCase))
                return new RecSpec { Type = "Rout", Suffix = "rout", ValidFlag = 309, KeyMsg = "You must enter Operator and Route Number to continue",
                    Fields = new[] {
                        new RecField("rcomp", "ch", true, 0, null), new RecField("routnumb", "ch", true, 0, null),
                        new RecField("rtprov", "ch", false, 0, null), new RecField("rtcall", "ch", false, 0, null),
                        new RecField("rtname", "quote", false, 0, null)
                    } };
            if (type.Equals("Towr", StringComparison.OrdinalIgnoreCase))
                return new RecSpec { Type = "Towr", Suffix = "towr", ValidFlag = 312, KeyMsg = "You must enter a Tower Code to continue",
                    Fields = new[] {
                        new RecField("twcode", "ch", true, 0, null), new RecField("twdesc", "quote", false, 0, null)
                    } };
            if (type.Equals("Town", StringComparison.OrdinalIgnoreCase))
                return new RecSpec { Type = "Town", Suffix = "town", ValidFlag = 313, KeyMsg = "You must enter Call Sign and Tower Number to continue",
                    Fields = new[] {
                        new RecField("call1", "ch", true, 0, null), new RecField("atwrno", "num", true, 0, null),
                        new RecField("oper", "ch", false, 0, null), new RecField("twcode", "ch", false, 0, null),
                        new RecField("twht", "num", false, 2, null), new RecField("twpa", "radio", false, 0, null),
                        new RecField("twli", "radio", false, 0, null), new RecField("nott", "ch", false, 0, null),
                        new RecField("tpoint", "ch", false, 0, null),
                        new RecField("adate", "date3", false, 0, "a"), new RecField("sdate", "date3", false, 0, "s")
                    } };
            if (type.Equals("Ctx", StringComparison.OrdinalIgnoreCase))
                return new RecSpec { Type = "Ctx", Suffix = "ctx_", ValidFlag = 303, KeyMsg = "You must enter Desired, Interfering, and Receive Equipment to continue",
                    ChildSuffix = "ctxd", ChildKey = "fsep",
                    Fields = new[] {
                        new RecField("tfcr", "ch", true, 0, null), new RecField("tfci", "ch", true, 0, null),
                        new RecField("rxeqp", "ch", true, 0, null), new RecField("rqco", "num", false, 1, null),
                        new RecField("rqcull", "num", false, 1, null), new RecField("rqwrst", "num", false, 1, null),
                        new RecField("ctxndp", "num", false, 0, null), new RecField("ctxdesc", "quote", false, 0, null)
                    } };
            if (type.Equals("Plan", StringComparison.OrdinalIgnoreCase))
                return new RecSpec { Type = "Plan", Suffix = "plan", ValidFlag = 310, KeyMsg = "You must enter Band and Plan to continue",
                    ChildSuffix = "plnd", ChildKey = "spno",
                    Fields = new[] {
                        new RecField("sband", "ch", true, 0, null), new RecField("splan", "ch", true, 0, null),
                        new RecField("srsp", "ch", false, 0, null), new RecField("srspiss", "ch", false, 0, null),
                        new RecField("conform", "radio", false, 0, null), new RecField("uscan", "radio", false, 0, null)
                    } };
            if (type.Equals("Ante", StringComparison.OrdinalIgnoreCase))
                return new RecSpec { Type = "Ante", Suffix = "ante", ValidFlag = 301, ChildSuffix = "antd", ChildKey = "antang" };
            return null;
        }

        private static string RecTable(HttpContext ctx, RecSpec spec, string name)
        {
            return ctx.Session["s_schema"] + ".su_" + name + "_" + spec.Suffix;
        }

        private static string[] RecKeyValues(HttpRequest req, RecSpec spec)
        {
            var keys = new List<string>();
            bool all = true;
            foreach (RecField f in spec.Fields)
            {
                if (!f.IsKey) continue;
                string v = (req[f.Name] ?? "").Trim();
                if (string.IsNullOrEmpty(v)) all = false;
                keys.Add(v);
            }
            if (all && keys.Count > 0) return keys.ToArray();
            string key = (req["key"] ?? "").Trim();
            if (string.IsNullOrEmpty(key)) return keys.ToArray();
            string[] parts = key.Split('^');
            int start = 0;
            if (parts.Length >= 3 && parts[0] == "d") start = 2;
            var list = new List<string>();
            for (int i = start; i < parts.Length; i++) list.Add(parts[i]);
            return list.ToArray();
        }

        private static bool ValidKeyPart(string v)
        {
            return !string.IsNullOrEmpty(v) && v.IndexOf('\'') < 0 && v.Length <= 16;
        }

        private static string RecWhere(RecSpec spec, string[] keys)
        {
            var parts = new List<string>();
            int i = 0;
            foreach (RecField f in spec.Fields)
            {
                if (!f.IsKey) continue;
                string v = i < keys.Length ? keys[i] : "";
                i++;
                if (f.Kind == "num") parts.Add(f.Name + "=" + DBUtils.numNull(v));
                else parts.Add(f.Name + "=" + SqlLit(v));
            }
            return string.Join(" AND ", parts.ToArray());
        }

        private static string RecKeyJoin(string[] keys)
        {
            return string.Join("^", keys ?? new string[0]);
        }

        private static string SqlVal(HttpRequest req, RecField f)
        {
            if (f.Kind == "num") return DBUtils.numNull(Req(req, f.Name));
            if (f.Kind == "quote") return DBUtils.chNull(DBUtils.charQuote((Req(req, f.Name) ?? "").ToUpperInvariant()));
            if (f.Kind == "radio")
            {
                string v = (Req(req, f.Name) ?? "").Trim().ToUpperInvariant();
                return DBUtils.chNull(v);
            }
            if (f.Kind == "date3")
            {
                string p = f.DatePrefix ?? "";
                return DBUtils.dates(Req(req, p + "Day"), Req(req, p + "Month"), Req(req, p + "Year"));
            }
            return DBUtils.chNull((Req(req, f.Name) ?? "").ToUpperInvariant());
        }

        private static bool RecExists(HttpContext ctx, RecSpec spec, string name, string[] keys)
        {
            string sql = "SELECT 1 FROM " + RecTable(ctx, spec, name) + " WHERE " + RecWhere(spec, keys);
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                    return dr.Read();
            }
        }

        private static void RecGet(HttpContext ctx)
        {
            RecSpec spec = FindSpec(ctx.Request["type"]);
            if (spec == null || spec.Fields == null)
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "Unknown SDF type." });
                return;
            }
            string name;
            if (!ReadName(ctx.Request, out name))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "Invalid SDF name." });
                return;
            }
            string[] keys = RecKeyValues(ctx.Request, spec);
            foreach (string k in keys)
            {
                if (!ValidKeyPart(k))
                {
                    WriteJson(ctx.Response, new { ok = false, error = spec.KeyMsg });
                    return;
                }
            }
            if (spec.Type == "Ctx") CtxResetNdp(ctx, name, keys);
            var rec = new Dictionary<string, string>();
            var select = new List<string>();
            select.Add("cmd");
            foreach (RecField f in spec.Fields)
            {
                if (f.Kind == "date3")
                {
                    string p = f.DatePrefix ?? "";
                    select.Add("datepart(day, " + f.Name + ")");
                    select.Add("datepart(month, " + f.Name + ")");
                    select.Add("datepart(year, " + f.Name + ")");
                }
                else select.Add(f.Name);
            }
            select.Add("datepart(day, mdate)");
            select.Add("datepart(month, mdate)");
            select.Add("datepart(year, mdate)");
            string sql = "SELECT " + string.Join(", ", select.ToArray()) +
                " FROM " + RecTable(ctx, spec, name) + " WHERE " + RecWhere(spec, keys);
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    if (!dr.Read())
                    {
                        WriteJson(ctx.Response, new { ok = false, error = "No record found." });
                        return;
                    }
                    int i = 0;
                    rec["cmd"] = Cell(dr, i++);
                    foreach (RecField f in spec.Fields)
                    {
                        if (f.Kind == "date3")
                        {
                            string p = f.DatePrefix ?? "";
                            rec[p + "Day"] = Cell(dr, i++);
                            rec[p + "Month"] = DBUtils.txtMonth(Cell(dr, i++));
                            rec[p + "Year"] = Cell(dr, i++);
                        }
                        else if (f.Kind == "num") rec[f.Name] = NumCell(dr, i++, f.Decimals);
                        else rec[f.Name] = Cell(dr, i++);
                    }
                    rec["mDay"] = Cell(dr, i++);
                    rec["mMonth"] = DBUtils.txtMonth(Cell(dr, i++));
                    rec["mYear"] = Cell(dr, i++);
                }
            }
            WriteJson(ctx.Response, new
            {
                ok = true,
                name = name,
                key = RecKeyJoin(keys),
                record = rec,
                children = RecChildRows(ctx, spec, name, keys)
            });
        }

        private static void RecSave(HttpContext ctx, bool isNew)
        {
            RecSpec spec = FindSpec(ctx.Request["type"]);
            if (spec == null || spec.Fields == null)
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "Unknown SDF type." });
                return;
            }
            string name;
            if (!ReadName(ctx.Request, out name))
            {
                ctx.Response.StatusCode = 400;
                WriteJson(ctx.Response, new { ok = false, error = "Invalid SDF name." });
                return;
            }
            string[] keys = RecKeyValues(ctx.Request, spec);
            foreach (string k in keys)
            {
                if (!ValidKeyPart(k))
                {
                    WriteJson(ctx.Response, new { ok = false, error = spec.KeyMsg });
                    return;
                }
            }
            if (isNew && RecExists(ctx, spec, name, keys))
            {
                WriteJson(ctx.Response, new { ok = false, error = "A record already exists in this file with this key" });
                return;
            }
            string cmdVal = (Req(ctx.Request, "cmd") ?? "").Trim().ToUpperInvariant();
            if (isNew) cmdVal = "A";
            string sql;
            if (isNew)
            {
                var cols = new List<string>();
                var vals = new List<string>();
                cols.Add("cmd"); vals.Add("'A'");
                cols.Add("recstat"); vals.Add("'U'");
                foreach (RecField f in spec.Fields)
                {
                    if (f.Name == "ctxndp") continue;
                    cols.Add(f.Name);
                    vals.Add(SqlVal(ctx.Request, f));
                }
                if (spec.Type == "Oper")
                {
                    cols.Add("telecom");
                    vals.Add("'N'");
                }
                sql = "INSERT INTO " + RecTable(ctx, spec, name) + " (" + string.Join(", ", cols.ToArray()) +
                    ") VALUES (" + string.Join(", ", vals.ToArray()) + ")";
            }
            else
            {
                var sets = new List<string>();
                sets.Add("cmd=" + SqlLit(cmdVal));
                sets.Add("recstat='U'");
                foreach (RecField f in spec.Fields)
                {
                    if (f.IsKey || f.Name == "ctxndp") continue;
                    sets.Add(f.Name + "=" + SqlVal(ctx.Request, f));
                }
                sql = "UPDATE " + RecTable(ctx, spec, name) + " SET " + string.Join(", ", sets.ToArray()) +
                    " WHERE " + RecWhere(spec, keys);
            }
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                    cmd.ExecuteNonQuery();
            }
            if (isNew)
            {
                string orig = (ctx.Request["origKey"] ?? "").Trim();
                if (!string.IsNullOrEmpty(orig))
                    RecCopyChildren(ctx, spec, name, orig.Split('^'), keys);
            }
            if (!UserTable.SetUserValidFlag(ctx.Session["s_schema"].ToString(), spec.ValidFlag, name, "N"))
            {
                WriteJson(ctx.Response, new { ok = false, error = "ERROR updating valid status" });
                return;
            }
            WriteJson(ctx.Response, new { ok = true, key = RecKeyJoin(keys) });
        }

        private static void RecCopyChildren(HttpContext ctx, RecSpec spec, string name, string[] oldKeys, string[] newKeys)
        {
            if (spec.Type == "Ctx" && oldKeys.Length >= 3 && newKeys.Length >= 3)
            {
                string table = ctx.Session["s_schema"] + ".su_" + name + "_ctxd";
                string sql = "INSERT INTO " + table + " (cmd, tfcr, tfci, rxeqp, fsep, rq, mdate, mtime) SELECT 'A'," +
                    SqlLit(newKeys[0]) + "," + SqlLit(newKeys[1]) + "," + SqlLit(newKeys[2]) +
                    ",fsep,rq,mdate,mtime FROM " + table + " WHERE tfcr=" + SqlLit(oldKeys[0]) +
                    " AND tfci=" + SqlLit(oldKeys[1]) + " AND rxeqp=" + SqlLit(oldKeys[2]);
                ExecSql(ctx, sql);
                CtxResetNdp(ctx, name, newKeys);
            }
            else if (spec.Type == "Plan" && oldKeys.Length >= 2 && newKeys.Length >= 2)
            {
                string table = ctx.Session["s_schema"] + ".su_" + name + "_plnd";
                string sql = "INSERT INTO " + table +
                    " (cmd,sband,splan,spno,set1,s1chid,set2,s2chid,set3,s3chid,set4,s4chid,mdate,mtime) SELECT 'A'," +
                    SqlLit(newKeys[0]) + "," + SqlLit(newKeys[1]) +
                    ",spno,set1,s1chid,set2,s2chid,set3,s3chid,set4,s4chid,mdate,mtime FROM " + table +
                    " WHERE sband=" + SqlLit(oldKeys[0]) + " AND splan=" + SqlLit(oldKeys[1]);
                ExecSql(ctx, sql);
            }
        }

        private static void ExecSql(HttpContext ctx, string sql)
        {
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                    cmd.ExecuteNonQuery();
            }
        }

        private static void CtxResetNdp(HttpContext ctx, string name, string[] keys)
        {
            if (keys == null || keys.Length < 3) return;
            string schema = ctx.Session["s_schema"].ToString();
            string ctxTable = schema + ".su_" + name + "_ctx_";
            string ctxdTable = schema + ".su_" + name + "_ctxd";
            string sql = "UPDATE " + ctxTable + " SET ctxndp=(SELECT count(*) FROM " + ctxdTable +
                " WHERE tfcr=" + SqlLit(keys[0]) + " AND tfci=" + SqlLit(keys[1]) + " AND rxeqp=" + SqlLit(keys[2]) + ")" +
                " WHERE tfcr=" + SqlLit(keys[0]) + " AND tfci=" + SqlLit(keys[1]) + " AND rxeqp=" + SqlLit(keys[2]);
            ExecSql(ctx, sql);
        }

        private static List<object> RecChildRows(HttpContext ctx, RecSpec spec, string name, string[] keys)
        {
            var rows = new List<object>();
            if (spec.Type == "Ctx") return CtxChildRows(ctx, name, keys);
            if (spec.Type == "Plan") return PlanChildRows(ctx, name, keys);
            return rows;
        }

        private static List<object> CtxChildRows(HttpContext ctx, string name, string[] keys)
        {
            var rows = new List<object>();
            if (keys == null || keys.Length < 3) return rows;
            string table = ctx.Session["s_schema"] + ".su_" + name + "_ctxd";
            string sql = "SELECT cmd, fsep, rq FROM " + table + " WHERE tfcr=" + SqlLit(keys[0]) +
                " AND tfci=" + SqlLit(keys[1]) + " AND rxeqp=" + SqlLit(keys[2]) + " ORDER BY fsep";
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        rows.Add(new { cmd = Cell(dr, 0), fsep = NumCell(dr, 1, 2), rq = NumCell(dr, 2, 1) });
                    }
                }
            }
            return rows;
        }

        private static List<object> PlanChildRows(HttpContext ctx, string name, string[] keys)
        {
            var rows = new List<object>();
            if (keys == null || keys.Length < 2) return rows;
            string table = ctx.Session["s_schema"] + ".su_" + name + "_plnd";
            string sql = "SELECT cmd, spno, set1, s1chid, set2, s2chid, set3, s3chid, set4, s4chid FROM " + table +
                " WHERE sband=" + SqlLit(keys[0]) + " AND splan=" + SqlLit(keys[1]) + " ORDER BY spno";
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        rows.Add(new
                        {
                            cmd = Cell(dr, 0),
                            spno = Cell(dr, 1),
                            set1 = NumCell(dr, 2, 2),
                            s1chid = Cell(dr, 3),
                            set2 = NumCell(dr, 4, 2),
                            s2chid = Cell(dr, 5),
                            set3 = NumCell(dr, 6, 2),
                            s3chid = Cell(dr, 7),
                            set4 = NumCell(dr, 8, 2),
                            s4chid = Cell(dr, 9)
                        });
                    }
                }
            }
            return rows;
        }

        private static RecSpec ChildParentSpec(HttpRequest req)
        {
            string type = (req["type"] ?? "").Trim();
            if (type.Equals("Ante", StringComparison.OrdinalIgnoreCase))
                return new RecSpec { Type = "Ante", Suffix = "ante", ChildSuffix = "antd", ChildKey = "antang" };
            return FindSpec(type);
        }

        private static string[] ParentKeys(HttpRequest req, RecSpec spec)
        {
            if (spec.Type == "Ante")
            {
                string k = (req["key"] ?? req["acode"] ?? "").Trim();
                if (k.IndexOf('^') >= 0)
                {
                    string[] parts = k.Split('^');
                    if (parts.Length >= 3 && parts[0] == "d") k = parts[2];
                }
                return new[] { k };
            }
            return RecKeyValues(req, spec);
        }

        private static void ChildGet(HttpContext ctx)
        {
            RecSpec spec = ChildParentSpec(ctx.Request);
            if (spec == null || string.IsNullOrEmpty(spec.ChildSuffix))
            {
                WriteJson(ctx.Response, new { ok = false, error = "No child table for this type." });
                return;
            }
            string name;
            if (!ReadName(ctx.Request, out name))
            {
                WriteJson(ctx.Response, new { ok = false, error = "Invalid SDF name." });
                return;
            }
            string childKey = (ctx.Request["childKey"] ?? "").Trim();
            if (!ValidKeyPart(childKey) && spec.ChildKey != "antang" && spec.ChildKey != "fsep" && spec.ChildKey != "spno")
            {
                WriteJson(ctx.Response, new { ok = false, error = "Child key required." });
                return;
            }
            string[] pkeys = ParentKeys(ctx.Request, spec);
            Dictionary<string, string> rec = LoadChildRow(ctx, spec, name, pkeys, childKey);
            if (rec == null)
            {
                WriteJson(ctx.Response, new { ok = false, error = "No child record found." });
                return;
            }
            WriteJson(ctx.Response, new { ok = true, record = rec });
        }

        private static Dictionary<string, string> LoadChildRow(HttpContext ctx, RecSpec spec, string name, string[] pkeys, string childKey)
        {
            string table = ctx.Session["s_schema"] + ".su_" + name + "_" + spec.ChildSuffix;
            string sql;
            if (spec.Type == "Ante")
                sql = "SELECT cmd, antang, dcov, dxpv, dcoh, dxph, dtilt, datepart(day, mdate), datepart(month, mdate), datepart(year, mdate) FROM " +
                    table + " WHERE acode=" + SqlLit(pkeys[0]) + " AND antang=" + DBUtils.numNull(childKey);
            else if (spec.Type == "Ctx")
                sql = "SELECT cmd, fsep, rq, datepart(day, mdate), datepart(month, mdate), datepart(year, mdate) FROM " +
                    table + " WHERE tfcr=" + SqlLit(pkeys[0]) + " AND tfci=" + SqlLit(pkeys[1]) +
                    " AND rxeqp=" + SqlLit(pkeys[2]) + " AND fsep=" + DBUtils.numNull(childKey);
            else
                sql = "SELECT cmd, spno, set1, s1chid, set2, s2chid, set3, s3chid, set4, s4chid, datepart(day, mdate), datepart(month, mdate), datepart(year, mdate) FROM " +
                    table + " WHERE sband=" + SqlLit(pkeys[0]) + " AND splan=" + SqlLit(pkeys[1]) +
                    " AND spno=" + DBUtils.numNull(childKey);
            using (var cn = new OdbcConnection(ctx.Session["s_cnString"].ToString()))
            {
                cn.Open();
                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    if (!dr.Read()) return null;
                    var rec = new Dictionary<string, string>();
                    rec["cmd"] = Cell(dr, 0);
                    if (spec.Type == "Ante")
                    {
                        rec["antang"] = NumCell(dr, 1, 2);
                        rec["dcov"] = NumCell(dr, 2, 2);
                        rec["dxpv"] = NumCell(dr, 3, 2);
                        rec["dcoh"] = NumCell(dr, 4, 2);
                        rec["dxph"] = NumCell(dr, 5, 2);
                        rec["dtilt"] = NumCell(dr, 6, 2);
                        rec["mDay"] = Cell(dr, 7);
                        rec["mMonth"] = DBUtils.txtMonth(Cell(dr, 8));
                        rec["mYear"] = Cell(dr, 9);
                    }
                    else if (spec.Type == "Ctx")
                    {
                        rec["fsep"] = NumCell(dr, 1, 2);
                        rec["rq"] = NumCell(dr, 2, 1);
                        rec["mDay"] = Cell(dr, 3);
                        rec["mMonth"] = DBUtils.txtMonth(Cell(dr, 4));
                        rec["mYear"] = Cell(dr, 5);
                    }
                    else
                    {
                        rec["spno"] = Cell(dr, 1);
                        rec["set1"] = NumCell(dr, 2, 2);
                        rec["s1chid"] = Cell(dr, 3);
                        rec["set2"] = NumCell(dr, 4, 2);
                        rec["s2chid"] = Cell(dr, 5);
                        rec["set3"] = NumCell(dr, 6, 2);
                        rec["s3chid"] = Cell(dr, 7);
                        rec["set4"] = NumCell(dr, 8, 2);
                        rec["s4chid"] = Cell(dr, 9);
                        rec["mDay"] = Cell(dr, 10);
                        rec["mMonth"] = DBUtils.txtMonth(Cell(dr, 11));
                        rec["mYear"] = Cell(dr, 12);
                    }
                    return rec;
                }
            }
        }

        private static void ChildSave(HttpContext ctx, bool isNew)
        {
            RecSpec spec = ChildParentSpec(ctx.Request);
            if (spec == null || string.IsNullOrEmpty(spec.ChildSuffix))
            {
                WriteJson(ctx.Response, new { ok = false, error = "No child table for this type." });
                return;
            }
            string name;
            if (!ReadName(ctx.Request, out name))
            {
                WriteJson(ctx.Response, new { ok = false, error = "Invalid SDF name." });
                return;
            }
            string[] pkeys = ParentKeys(ctx.Request, spec);
            string childKey = (ctx.Request["childKey"] ?? ctx.Request[spec.ChildKey] ?? "").Trim();
            if (string.IsNullOrEmpty(childKey))
            {
                WriteJson(ctx.Response, new { ok = false, error = "Child key required." });
                return;
            }
            string table = ctx.Session["s_schema"] + ".su_" + name + "_" + spec.ChildSuffix;
            string cmdVal = (Req(ctx.Request, "cmd") ?? "").Trim().ToUpperInvariant();
            if (isNew) cmdVal = "A";
            string sql;
            if (spec.Type == "Ante")
            {
                if (isNew)
                    sql = "INSERT INTO " + table + " (cmd, interpstat, acode, antang, dcov, dxpv, dcoh, dxph, dtilt) VALUES ('A',0," +
                        SqlLit(pkeys[0]) + "," + DBUtils.numNull(childKey) + "," +
                        DBUtils.numNull(Req(ctx.Request, "dcov")) + "," + DBUtils.numNull(Req(ctx.Request, "dxpv")) + "," +
                        DBUtils.numNull(Req(ctx.Request, "dcoh")) + "," + DBUtils.numNull(Req(ctx.Request, "dxph")) + "," +
                        DBUtils.numNull(Req(ctx.Request, "dtilt")) + ")";
                else
                    sql = "UPDATE " + table + " SET cmd=" + SqlLit(cmdVal) + ", dcov=" + DBUtils.numNull(Req(ctx.Request, "dcov")) +
                        ", dxpv=" + DBUtils.numNull(Req(ctx.Request, "dxpv")) + ", dcoh=" + DBUtils.numNull(Req(ctx.Request, "dcoh")) +
                        ", dxph=" + DBUtils.numNull(Req(ctx.Request, "dxph")) + ", dtilt=" + DBUtils.numNull(Req(ctx.Request, "dtilt")) +
                        " WHERE acode=" + SqlLit(pkeys[0]) + " AND antang=" + DBUtils.numNull(childKey);
            }
            else if (spec.Type == "Ctx")
            {
                if (isNew)
                    sql = "INSERT INTO " + table + " (cmd, recstat, tfcr, tfci, rxeqp, fsep, rq) VALUES ('A','U'," +
                        SqlLit(pkeys[0]) + "," + SqlLit(pkeys[1]) + "," + SqlLit(pkeys[2]) + "," +
                        DBUtils.numNull(childKey) + "," + DBUtils.numNull(Req(ctx.Request, "rq")) + ")";
                else
                    sql = "UPDATE " + table + " SET cmd=" + SqlLit(cmdVal) + ", recstat='U', rq=" + DBUtils.numNull(Req(ctx.Request, "rq")) +
                        " WHERE tfcr=" + SqlLit(pkeys[0]) + " AND tfci=" + SqlLit(pkeys[1]) +
                        " AND rxeqp=" + SqlLit(pkeys[2]) + " AND fsep=" + DBUtils.numNull(childKey);
            }
            else
            {
                if (isNew)
                    sql = "INSERT INTO " + table + " (cmd, recstat, sband, splan, spno, set1, s1chid, set2, s2chid, set3, s3chid, set4, s4chid) VALUES ('A','U'," +
                        SqlLit(pkeys[0]) + "," + SqlLit(pkeys[1]) + "," + DBUtils.numNull(childKey) + "," +
                        DBUtils.numNull(Req(ctx.Request, "set1")) + "," + SqlLit((Req(ctx.Request, "s1chid") ?? "").ToUpperInvariant()) + "," +
                        DBUtils.numNull(Req(ctx.Request, "set2")) + "," + SqlLit((Req(ctx.Request, "s2chid") ?? "").ToUpperInvariant()) + "," +
                        DBUtils.numNull(Req(ctx.Request, "set3")) + "," + SqlLit((Req(ctx.Request, "s3chid") ?? "").ToUpperInvariant()) + "," +
                        DBUtils.numNull(Req(ctx.Request, "set4")) + "," + SqlLit((Req(ctx.Request, "s4chid") ?? "").ToUpperInvariant()) + ")";
                else
                    sql = "UPDATE " + table + " SET cmd=" + SqlLit(cmdVal) + ", recstat='U', set1=" + DBUtils.numNull(Req(ctx.Request, "set1")) +
                        ", s1chid=" + SqlLit((Req(ctx.Request, "s1chid") ?? "").ToUpperInvariant()) +
                        ", set2=" + DBUtils.numNull(Req(ctx.Request, "set2")) +
                        ", s2chid=" + SqlLit((Req(ctx.Request, "s2chid") ?? "").ToUpperInvariant()) +
                        ", set3=" + DBUtils.numNull(Req(ctx.Request, "set3")) +
                        ", s3chid=" + SqlLit((Req(ctx.Request, "s3chid") ?? "").ToUpperInvariant()) +
                        ", set4=" + DBUtils.numNull(Req(ctx.Request, "set4")) +
                        ", s4chid=" + SqlLit((Req(ctx.Request, "s4chid") ?? "").ToUpperInvariant()) +
                        " WHERE sband=" + SqlLit(pkeys[0]) + " AND splan=" + SqlLit(pkeys[1]) +
                        " AND spno=" + DBUtils.numNull(childKey);
            }
            try
            {
                ExecSql(ctx, sql);
            }
            catch (Exception ex)
            {
                WriteJson(ctx.Response, new { ok = false, error = ex.Message });
                return;
            }
            if (spec.Type == "Ante") AnteResetAnip(ctx, name, pkeys[0]);
            if (spec.Type == "Ctx") CtxResetNdp(ctx, name, pkeys);
            int flag = spec.Type == "Ante" ? 301 : (spec.Type == "Ctx" ? 303 : 310);
            // W2-6: honor SetUserValidFlag like parent saves.
            if (!UserTable.SetUserValidFlag(ctx.Session["s_schema"].ToString(), flag, name, "N"))
            {
                WriteJson(ctx.Response, new { ok = false, error = "ERROR updating valid status" });
                return;
            }
            WriteJson(ctx.Response, new { ok = true, childKey = childKey });
        }

        private static void ChildDelete(HttpContext ctx)
        {
            RecSpec spec = ChildParentSpec(ctx.Request);
            if (spec == null || string.IsNullOrEmpty(spec.ChildSuffix))
            {
                WriteJson(ctx.Response, new { ok = false, error = "No child table for this type." });
                return;
            }
            string name;
            if (!ReadName(ctx.Request, out name))
            {
                WriteJson(ctx.Response, new { ok = false, error = "Invalid SDF name." });
                return;
            }
            string[] pkeys = ParentKeys(ctx.Request, spec);
            string childKey = (ctx.Request["childKey"] ?? "").Trim();
            string table = ctx.Session["s_schema"] + ".su_" + name + "_" + spec.ChildSuffix;
            string sql;
            if (spec.Type == "Ante")
                sql = "DELETE FROM " + table + " WHERE acode=" + SqlLit(pkeys[0]) + " AND antang=" + DBUtils.numNull(childKey);
            else if (spec.Type == "Ctx")
                sql = "DELETE FROM " + table + " WHERE tfcr=" + SqlLit(pkeys[0]) + " AND tfci=" + SqlLit(pkeys[1]) +
                    " AND rxeqp=" + SqlLit(pkeys[2]) + " AND fsep=" + DBUtils.numNull(childKey);
            else
                sql = "DELETE FROM " + table + " WHERE sband=" + SqlLit(pkeys[0]) + " AND splan=" + SqlLit(pkeys[1]) +
                    " AND spno=" + DBUtils.numNull(childKey);
            ExecSql(ctx, sql);
            if (spec.Type == "Ante") AnteResetAnip(ctx, name, pkeys[0]);
            if (spec.Type == "Ctx") CtxResetNdp(ctx, name, pkeys);
            int flag = spec.Type == "Ante" ? 301 : (spec.Type == "Ctx" ? 303 : 310);
            if (!UserTable.SetUserValidFlag(ctx.Session["s_schema"].ToString(), flag, name, "N"))
            {
                WriteJson(ctx.Response, new { ok = false, error = "ERROR updating valid status" });
                return;
            }
            WriteJson(ctx.Response, new { ok = true });
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            response.Write(Ser.Serialize(obj));
        }
    }
}
