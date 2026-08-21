<%@ WebHandler Language="C#" Class="RemIcsReWrite.GenCtxHandler" %>

using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using DBAccess;
using JobSubmission;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>
    /// Generate CTX Curves  -  parity with auxengmenu/AUXgenctx1 + AUXgenctx2.
    /// POST action=generate|save|spectra
    /// </summary>
    public class GenCtxHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly Regex CodeOk = new Regex(@"^[A-Za-z0-9_\-./]{1,16}$", RegexOptions.Compiled);

        public bool IsReusable { get { return false; } }

        public void ProcessRequest(HttpContext context)
        {
            var response = context.Response;
            var request = context.Request;
            response.ContentType = "application/json; charset=utf-8";
            response.Cache.SetCacheability(HttpCacheability.NoCache);

            if (context.Session == null || context.Session["s_cnString"] == null
                || context.Session["s_schema"] == null || context.Session["s_user"] == null
                || context.Session["prog_dir"] == null || context.Session["db_name"] == null)
            {
                response.StatusCode = 401;
                WriteJson(response, new { ok = false, error = "Session not initialized." });
                return;
            }

            string action = (request["action"] ?? request.QueryString["action"] ?? "").Trim().ToLowerInvariant();
            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                {
                    switch (action)
                    {
                        case "generate": HandleGenerate(context); break;
                        case "save": HandleSave(context); break;
                        case "spectra": HandleSpectra(context); break;
                        case "eqpttraf": HandleEqptTraf(context); break;
                        default:
                            response.StatusCode = 400;
                            WriteJson(response, new { ok = false, error = "action must be generate|save|spectra|eqpttraf" });
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

        private static void HandleEqptTraf(HttpContext context)
        {
            string ecode = NormCode(context.Request["ecode"] ?? context.Request["equip"]);
            if (ecode.Length == 0)
            {
                WriteJson(context.Response, new { ok = false, error = "Equipment code required." });
                return;
            }

            var trafs = new List<string>();
            using (var cn = new SqlConnection(MicsDbAuth.GetSqlClientConnectionString()))
            {
                cn.Open();
                using (var cmd = new SqlCommand(
                    "SELECT DISTINCT LTRIM(RTRIM(etraf)) FROM main.sd_eqpt " +
                    "WHERE RTRIM(ecode)=@e AND etraf IS NOT NULL AND LTRIM(RTRIM(etraf)) <> ''", cn))
                {
                    cmd.Parameters.Add("@e", SqlDbType.VarChar, 16).Value = ecode;
                    using (var dr = cmd.ExecuteReader())
                    {
                        while (dr.Read())
                        {
                            string t = dr[0] == DBNull.Value ? "" : dr[0].ToString().Trim().ToUpperInvariant();
                            if (t.Length > 0 && trafs.IndexOf(t) < 0) trafs.Add(t);
                        }
                    }
                }
            }

            WriteJson(context.Response, new
            {
                ok = true,
                ecode = ecode,
                traf = trafs.Count == 1 ? trafs[0] : "",
                trafs = trafs.ToArray()
            });
        }

        private static void HandleGenerate(HttpContext context)
        {
            SesUtils.LogMenuUse("AUXGenCTX");

            string vicEquip, vicTraf, intEquip, intTraf;
            if (!ReadCodes(context.Request, out vicEquip, out vicTraf, out intEquip, out intTraf))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "You must enter all the fields." });
                return;
            }

            bool esVictim = ParseFlag(context.Request["esVictim"]);
            var extraFreqs = ParseFreqs(context.Request["freqs"]);

            var oLog = new dblogger(context.Session["prog_dir"].ToString() + "genctx");
            oLog.logargs = esVictim ? "-E " : "";
            oLog.logargs += context.Session["db_name"].ToString() + " " +
                vicEquip + " " + vicTraf + " " + intEquip + " " + intTraf + " " + oLog.logserial;
            foreach (string freq in extraFreqs)
            {
                if (oLog.logargs.Length >= 255) break;
                oLog.logargs += " " + freq;
            }

            oLog = JobSubmit.SubmitJob(oLog, " ", 30);
            int logret;
            if ((logret = oLog.Finish()) != 0)
            {
                WriteJobFail(context, oLog, "The gentx program failed");
                return;
            }

            switch (oLog.logerrorcode)
            {
                case 0:
                    break;
                case -99:
                    WriteJobFail(context, oLog, "The genctx program timed out.");
                    return;
                case -98:
                    WriteJobFail(context, oLog, "Could not start the gentx program");
                    return;
                default:
                    WriteJobFail(context, oLog, "The gentx program failed");
                    return;
            }

            string readErr;
            ArrayList alVals = GetRetVals(context, oLog.logserial, out readErr);
            if (alVals == null || alVals.Count < 1)
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    noResults = true,
                    error = string.IsNullOrEmpty(readErr) ? "No results found." : readErr,
                    serial = oLog.logserial
                });
                return;
            }

            int nPrefix = Convert.ToInt32(alVals[0].ToString());
            string vicEq = alVals.Count > 1 ? alVals[1].ToString().Trim() : "";
            string vicTr = alVals.Count > 2 ? alVals[2].ToString().Trim() : "";
            string intEq = alVals.Count > 3 ? alVals[3].ToString().Trim() : "";
            string intTr = alVals.Count > 4 ? alVals[4].ToString().Trim() : "";
            string vicParm = alVals.Count > 5 ? alVals[5].ToString() : "";
            string intParm = alVals.Count > 6 ? alVals[6].ToString() : "";

            var rows = new List<object>();
            for (int nInd = nPrefix; nInd < alVals.Count; nInd++)
            {
                string[] parts = alVals[nInd].ToString().Split(',');
                if (parts.Length < 2) continue;
                double sep, req;
                if (!double.TryParse(parts[0].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out sep)) continue;
                if (!double.TryParse(parts[1].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out req)) continue;
                rows.Add(new { sep = sep, req = req });
            }

            WriteJson(context.Response, new
            {
                ok = true,
                serial = oLog.logserial,
                vicEquip = vicEq,
                vicTraf = vicTr,
                intEquip = intEq,
                intTraf = intTr,
                vicParm = vicParm,
                intParm = intParm,
                rows = rows,
                noResults = rows.Count == 0
            });
        }

        private static void HandleSave(HttpContext context)
        {
            string serial = (context.Request["serial"] ?? "").Trim();
            if (serial.Length == 0)
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "serial required." });
                return;
            }

            string readErr;
            ArrayList aVals = GetRetVals(context, serial, out readErr);
            if (aVals == null || aVals.Count < 1)
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = string.IsNullOrEmpty(readErr) ? "No Return values." : readErr
                });
                return;
            }

            int nPrefix = Convert.ToInt32(aVals[0].ToString());
            var sb = new StringBuilder();
            for (int nNum = 0; nNum < aVals.Count; nNum++)
            {
                if (nNum < nPrefix)
                {
                    sb.AppendLine(aVals[nNum].ToString());
                }
                else
                {
                    if (nNum == nPrefix) sb.AppendLine("FrequencySep,InterferenceReq");
                    string[] aOneLine = aVals[nNum].ToString().Split(',');
                    if (aOneLine.Length >= 2)
                        sb.AppendLine(aOneLine[0].Trim() + "," + aOneLine[1].Trim());
                }
            }

            WriteJson(context.Response, new
            {
                ok = true,
                fileName = serial + ".csv",
                csv = sb.ToString()
            });
        }

        private static void HandleSpectra(HttpContext context)
        {
            string vicEquip, vicTraf, intEquip, intTraf;
            if (!ReadCodes(context.Request, out vicEquip, out vicTraf, out intEquip, out intTraf))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "You must enter all the fields." });
                return;
            }
            string vicParm = context.Request["vicParm"] ?? "";
            string intParm = context.Request["intParm"] ?? "";

            var filter = LoadCtxFps(vicEquip, vicTraf, "F");
            var power = LoadCtxFps(intEquip, intTraf, "P");
            WriteJson(context.Response, new
            {
                ok = true,
                filterTitle = "Filter Attenuation for " + vicEquip + "/" + vicTraf,
                powerTitle = "Power Spectrum for " + intEquip + "/" + intTraf,
                filterNote = filter.Count == 0 ? vicParm.Trim() : "",
                powerNote = power.Count == 0 ? intParm.Trim() : "",
                filter = filter,
                power = power
            });
        }

        private static List<object> LoadCtxFps(string eqpt, string traf, string ctype)
        {
            var rows = new List<object>();
            var oCn = new dbconnect();
            try
            {
                string sql = "Select fs, value from tsip.ctxfps where ctype='" + Esc(ctype) +
                    "' and ecode='" + Esc(eqpt) + "' and trafcode='" + Esc(traf) + "' order by fs";
                DataTable dt = oCn.retrieve(sql);
                if (dt != null)
                {
                    foreach (DataRow dr in dt.Rows)
                    {
                        rows.Add(new
                        {
                            fs = Convert.ToDouble(dr["fs"]),
                            value = Convert.ToDouble(dr["value"])
                        });
                    }
                }
            }
            catch
            {
                rows.Clear();
            }
            finally
            {
                oCn.dbdisconnect();
            }
            return rows;
        }

        private static ArrayList GetRetVals(HttpContext context, string key, out string error)
        {
            error = null;
            var list = new ArrayList();
            string schema = (context.Session["s_schema"] ?? "").ToString().Trim();
            if (!Regex.IsMatch(schema, @"^[A-Za-z][A-Za-z0-9_]*$"))
            {
                error = "No results found (invalid schema).";
                return list;
            }
            if (string.IsNullOrEmpty(key) || key.IndexOf('\'') >= 0)
            {
                error = "No results found (invalid job id).";
                return list;
            }

            try
            {
                using (var cn = new SqlConnection(MicsDbAuth.GetSqlClientConnectionString()))
                {
                    cn.Open();
                    using (var cmd = new SqlCommand(
                        "SELECT retval FROM " + schema + ".returnvalues WHERE RTRIM(retkey)=@k ORDER BY retind", cn))
                    {
                        cmd.Parameters.Add("@k", SqlDbType.VarChar, 20).Value = key;
                        using (var dr = cmd.ExecuteReader())
                        {
                            while (dr.Read())
                                list.Add(dr[0] == DBNull.Value ? "" : dr[0].ToString().TrimEnd());
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                error = "No results found (" + schema + " / " + key + ": " + StripTags(ex.Message) + ").";
                return null;
            }

            if (list.Count < 1)
                error = "No results found (job " + key + " wrote no rows in " + schema + ".returnvalues).";
            return list;
        }

        private static void WriteJobFail(HttpContext context, dblogger oLog, string fallback)
        {
            string desc = oLog != null ? StripTags(oLog.logerrordesc) : "";
            string msg = desc.Length > 0 ? desc : fallback;
            WriteJson(context.Response, new
            {
                ok = false,
                noResults = true,
                error = msg,
                logerrorcode = oLog != null ? oLog.logerrorcode : 0
            });
        }

        private static string StripTags(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return Regex.Replace(s.Replace("<br />", " ").Replace("<br/>", " ").Replace("<br>", " "),
                "<[^>]+>", "").Trim();
        }

        private static bool ReadCodes(HttpRequest request, out string vicEquip, out string vicTraf, out string intEquip, out string intTraf)
        {
            vicEquip = NormCode(request["vicEquip"]);
            vicTraf = NormCode(request["vicTraf"]);
            intEquip = NormCode(request["intEquip"]);
            intTraf = NormCode(request["intTraf"]);
            return vicEquip.Length > 0 && vicTraf.Length > 0 && intEquip.Length > 0 && intTraf.Length > 0;
        }

        private static string NormCode(string raw)
        {
            string s = (raw ?? "").Trim().ToUpperInvariant();
            return CodeOk.IsMatch(s) ? s : "";
        }

        private static List<string> ParseFreqs(string raw)
        {
            var list = new List<string>();
            if (string.IsNullOrWhiteSpace(raw)) return list;
            foreach (string part in raw.Split(new[] { '\n', '\r', ',', ';' }, StringSplitOptions.RemoveEmptyEntries))
            {
                double d;
                if (!double.TryParse(part.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out d)) continue;
                if (d < 0.0 || d > 5000.0) continue;
                list.Add(d.ToString("0.000", CultureInfo.InvariantCulture));
            }
            return list;
        }

        private static bool ParseFlag(string raw)
        {
            if (string.IsNullOrWhiteSpace(raw)) return false;
            raw = raw.Trim();
            return raw == "1" || raw.Equals("true", StringComparison.OrdinalIgnoreCase) || raw.Equals("on", StringComparison.OrdinalIgnoreCase);
        }

        private static string Esc(string s)
        {
            return (s ?? "").Replace("'", "''");
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            response.Write(new JavaScriptSerializer().Serialize(obj));
        }
    }
}
