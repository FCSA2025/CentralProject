<%@ WebHandler Language="C#" Class="RemIcsReWrite.AuxOhlHandler" %>

using System;
using System.Collections;
using System.Data;
using System.Data.Odbc;
using System.Data.SqlClient;
using System.Globalization;
using System.IO;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using DBAccess;
using JobSubmission;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>Over Horizon Loss  -  parity with auxengmenu/AUXOHLoss1 / getohlrep.</summary>
    public class AuxOhlHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly Regex CallOk = new Regex(@"^[A-Za-z0-9_%.\-]{1,16}$", RegexOptions.Compiled);
        private static readonly Regex TokenOk = new Regex(@"^[A-Za-z0-9+\-.]{1,24}$", RegexOptions.Compiled);
        private static readonly Regex SchemaOk = new Regex(@"^[A-Za-z][A-Za-z0-9_]*$", RegexOptions.Compiled);
        private static readonly Regex UserOk = new Regex(@"^[A-Za-z0-9_]{1,16}$", RegexOptions.Compiled);
        private static readonly Regex SerialOk = new Regex(@"^[A-Za-z0-9][A-Za-z0-9_-]{3,63}$", RegexOptions.Compiled);

        public bool IsReusable { get { return false; } }

        public void ProcessRequest(HttpContext context)
        {
            var response = context.Response;
            response.ContentType = "application/json; charset=utf-8";
            response.Cache.SetCacheability(HttpCacheability.NoCache);

            if (context.Session == null || context.Session["s_cnString"] == null
                || context.Session["s_schema"] == null || context.Session["s_user"] == null
                || context.Session["prog_dir"] == null || context.Session["db_name"] == null
                || context.Session["user_dir"] == null)
            {
                response.StatusCode = 401;
                WriteJson(response, new { ok = false, error = "Session not initialized." });
                return;
            }

            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                {
                    string action = (context.Request["action"] ?? "coords").Trim().ToLowerInvariant();
                    if (action == "email") HandleEmail(context);
                    else if (action == "run") HandleRun(context);
                    else HandleCoords(context);
                }
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        private static void HandleCoords(HttpContext context)
        {
            SesUtils.LogMenuUse("AUXOHLoss");

            string call = Norm(context.Request["call"]);
            string lat = Norm(context.Request["lat"]);
            string lng = Norm(context.Request["lng"]);
            string utmN = Norm(context.Request["utmNorth"]);
            string utmE = Norm(context.Request["utmEast"]);
            string utmZ = Norm(context.Request["utmZone"]);
            string antHt = Norm(context.Request["antHt"]);

            string mode, err;
            if (!PickMode(call, lat, lng, utmN, utmE, utmZ, out mode, out err))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = err });
                return;
            }

            string db = context.Session["db_name"].ToString();
            dblogger oLog = new dblogger(context.Session["prog_dir"].ToString() + "getcoords");
            if (mode == "CALL")
                oLog.logargs = db + " " + oLog.logserial + " CALL " + call;
            else if (mode == "LL")
                oLog.logargs = db + " " + oLog.logserial + " LL " + lat + " " + lng;
            else
                oLog.logargs = db + " " + oLog.logserial + " UTM " + utmN + " " + utmE + " " + utmZ;

            int timeout = 30;
            int parsedTimeout;
            if (int.TryParse((context.Request["timeout"] ?? "").Trim(), NumberStyles.Integer,
                CultureInfo.InvariantCulture, out parsedTimeout) && parsedTimeout >= 30 && parsedTimeout <= 90)
                timeout = parsedTimeout;
            string jobErr;
            dblogger done;
            ArrayList coords = RunGetCoords(context, oLog, timeout, out done, out jobErr);
            oLog = done ?? oLog;
            if (coords == null || coords.Count < 9)
            {
                if (oLog.logreturncode == 15)
                    jobErr = "Site not found.";
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = string.IsNullOrEmpty(jobErr) ? "No output was produced by the coord prog." : jobErr,
                    serial = oLog.logserial
                });
                return;
            }

            WriteJson(context.Response, new
            {
                ok = true,
                serial = oLog.logserial,
                call = BlankDash(coords[0]),
                siteName = BlankDash(coords[1]),
                lat84 = T(coords, 4),
                lng84 = T(coords, 5),
                utmNorth = T(coords, 6),
                utmEast = T(coords, 7),
                utmZone = T(coords, 8),
                antHt = antHt.Length == 0 ? "0" : antHt
            });
        }

        private static void HandleRun(HttpContext context)
        {
            string call1 = Dash(Norm(context.Request["call1"]));
            string name1 = Dash(Norm(context.Request["siteName1"]));
            string lat1 = Norm(context.Request["lat1"]);
            string lng1 = Norm(context.Request["lng1"]);
            string ant1 = NumOrZero(context.Request["antHt1"]);
            string call2 = Dash(Norm(context.Request["call2"]));
            string name2 = Dash(Norm(context.Request["siteName2"]));
            string lat2 = Norm(context.Request["lat2"]);
            string lng2 = Norm(context.Request["lng2"]);
            string ant2 = NumOrZero(context.Request["antHt2"]);
            string k = Norm(context.Request["k"]);
            string freq = Norm(context.Request["freq"]);
            string pol = Norm(context.Request["pol"]);
            string climate = Norm(context.Request["climate"]);
            string repType = Norm(context.Request["repType"]).ToUpperInvariant();

            if (k.Length == 0)
            {
                WriteJson(context.Response, new { ok = false, error = "You must enter a K value." });
                return;
            }
            if (freq.Length == 0)
            {
                WriteJson(context.Response, new { ok = false, error = "You must enter a frequency." });
                return;
            }
            if (!NumOk(k) || !NumOk(freq) || !NumOk(ant1) || !NumOk(ant2))
            {
                WriteJson(context.Response, new { ok = false, error = "K, frequency, and antenna heights must be numeric." });
                return;
            }
            if (pol != "0" && pol != "1")
            {
                WriteJson(context.Response, new { ok = false, error = "Select Horizontal or Vertical polarization." });
                return;
            }
            if (climate != "0" && climate != "1" && climate != "2")
            {
                WriteJson(context.Response, new { ok = false, error = "Select a climatic region." });
                return;
            }
            if (repType != "NOHTML" && repType != "HTML" && repType != "CSV")
            {
                WriteJson(context.Response, new { ok = false, error = "You must select at least one form of report." });
                return;
            }
            if (!TokenOk.IsMatch(lat1) || !TokenOk.IsMatch(lng1) || !TokenOk.IsMatch(lat2) || !TokenOk.IsMatch(lng2))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Both sites need resolved WGS84 coordinates." });
                return;
            }

            if (!CallOk.IsMatch(call1) && call1 != "-" && call1 != "--") call1 = "-";
            if (!CallOk.IsMatch(call2) && call2 != "-" && call2 != "--") call2 = "-";

            string cArgs = context.Session["db_name"].ToString() + " " + repType;
            cArgs += " " + lat1 + " " + lng1 + " " + lat2 + " " + lng2;
            cArgs += " " + ant1 + " " + ant2;
            cArgs += " " + k + " " + freq;
            cArgs += " " + pol + " " + climate;
            cArgs += " " + Quoted(call1) + " " + Quoted(name1) + " " + Quoted(call2) + " " + Quoted(name2) + " ";

            dblogger oLog = new dblogger(context.Session["prog_dir"].ToString() + "getohlrep", cArgs);
            string userDir = UserDir(context);
            string ext = OELSupport.ACfileext();
            string cOut = userDir + "p" + oLog.logserial + ext;

            oLog = JobSubmit.SubmitJob(oLog, cOut, 30);
            if (oLog.Finish() != 0)
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = "Database Server failed to update logger3."
                });
                return;
            }
            if (oLog.logerrorcode == -99)
            {
                WriteJson(context.Response, new { ok = false, error = "Program timed out while getting OH losses." });
                return;
            }
            if (oLog.logerrorcode == -98)
            {
                WriteJson(context.Response, new { ok = false, error = "Could not start the Over Horizon Loss prog." });
                return;
            }
            if (oLog.logerrorcode != 0)
            {
                string desc = oLog.logerrordesc != null ? oLog.logerrordesc.Trim() : "";
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = desc.Length > 0 ? desc : "The Over Horizon Loss prog failed."
                });
                return;
            }

            string prnName = "p" + oLog.logserial + ext;
            string htmName = "p" + oLog.logserial + ".htm";
            OELSupport.copy_html(prnName, htmName);

            string schema = context.Session["s_schema"].ToString().Trim();
            string user = context.Session["s_user"].ToString().Trim();
            if (!SchemaOk.IsMatch(schema) || !UserOk.IsMatch(user))
            {
                WriteJson(context.Response, new { ok = false, error = "Session not initialized." });
                return;
            }

            string html = ReadCapped(userDir + htmName);
            string text = ReadCapped(cOut);
            if (html.Length == 0 && text.Length > 0)
                html = "<pre>" + HttpUtility.HtmlEncode(text) + "</pre>";

            // W2-3: empty report after job success is failure.
            if (html.Length == 0 && text.Length == 0)
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = "Report file missing or empty after job completed.",
                    serial = oLog.logserial,
                    repType = repType,
                    url = "../userdirs/" + schema + "/" + user + "/" + htmName,
                    html = html,
                    text = text
                });
                return;
            }

            WriteJson(context.Response, new
            {
                ok = true,
                serial = oLog.logserial,
                repType = repType,
                url = "../userdirs/" + schema + "/" + user + "/" + htmName,
                html = html,
                text = text
            });
        }

        private static void HandleEmail(HttpContext context)
        {
            string serial = (context.Request["serial"] ?? "").Trim();
            if (!SerialOk.IsMatch(serial))
            {
                WriteJson(context.Response, new { ok = false, error = "Run the calculation first." });
                return;
            }
            string userDir = UserDir(context);
            string htmPath = userDir + "p" + serial + ".htm";
            string prnPath = userDir + "p" + serial + OELSupport.ACfileext();
            string attach = "";
            if (File.Exists(htmPath) && new FileInfo(htmPath).Length > 0) attach = htmPath;
            if (File.Exists(prnPath) && new FileInfo(prnPath).Length > 0
                && !string.Equals(prnPath, htmPath, StringComparison.OrdinalIgnoreCase))
            {
                if (attach.Length > 0) attach += ";";
                attach += prnPath;
            }
            if (attach.Length == 0)
            {
                WriteJson(context.Response, new { ok = false, error = "No report file to email." });
                return;
            }

            string schema = context.Session["s_schema"].ToString().Trim();
            string user = context.Session["s_user"].ToString().Trim();
            string mailTo = "";
            using (var cn = new OdbcConnection(context.Session["s_cnString"].ToString()))
            {
                cn.Open();
                mailTo = LookupEmail(cn, SourceTable(context), schema, user);
            }
            if (string.IsNullOrEmpty(mailTo))
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = "You do not have an e-mail address set up in the Mics database. Please contact FCSA to have one added."
                });
                return;
            }

            string subject = "MICS Over Horizon Loss report";
            string body = "The Over Horizon Loss report is attached.\n\nAccount: " + schema +
                "\nUser: " + user + "\n\nDelivery can take up to 20 minutes.\n";
            bool queued = SesUtils.InsertEmailQueue("mics@fcsa.ca", mailTo, null, subject, body, attach);
            if (!queued)
            {
                WriteJson(context.Response, new { ok = false, error = "The email queue insert failed." });
                return;
            }
            WriteJson(context.Response, new
            {
                ok = true,
                email = mailTo,
                message = "Email queued. Delivery can take up to 20 minutes."
            });
        }

        private static bool PickMode(string call, string lat, string lng, string utmN, string utmE, string utmZ,
            out string mode, out string error)
        {
            mode = "";
            error = "";
            if (call.Length > 0 && call != "--")
            {
                if (!CallOk.IsMatch(call)) { error = "Invalid call sign."; return false; }
                mode = "CALL";
                return true;
            }
            if (lat.Length > 0 || lng.Length > 0)
            {
                if (!TokenOk.IsMatch(lat) || !TokenOk.IsMatch(lng))
                {
                    error = "You must specify a call, the lat/longs or the UTM coords";
                    return false;
                }
                mode = "LL";
                return true;
            }
            if (utmN.Length > 0 || utmE.Length > 0)
            {
                if (!TokenOk.IsMatch(utmN) || !TokenOk.IsMatch(utmE) || !TokenOk.IsMatch(utmZ))
                {
                    error = "You must specify a call, the lat/longs or the UTM coords";
                    return false;
                }
                mode = "UTM";
                return true;
            }
            error = "You must specify a call, the lat/longs or the UTM coords";
            return false;
        }

        private static ArrayList RunGetCoords(HttpContext context, dblogger oLog, int timeout,
            out dblogger done, out string error)
        {
            error = null;
            done = JobSubmit.SubmitJob(oLog, " ", timeout);
            oLog = done;
            if (oLog.Finish() != 0)
            {
                error = "Database Server failed to update logger1.";
                return null;
            }
            if (oLog.logerrorcode == -99)
            {
                error = "Program timed out while getting coordinates.";
                return null;
            }
            if (oLog.logerrorcode == -98)
            {
                error = "Could not start the coordinate prog.";
                return null;
            }
            if (oLog.logreturncode != 0 && oLog.logerrorcode != 0)
            {
                error = "Coordinate program failed(3): " + oLog.logreturncode;
                return null;
            }
            string readErr;
            ArrayList vals = GetRetVals(context, oLog.logserial, out readErr);
            if (vals == null || vals.Count < 1)
            {
                error = string.IsNullOrEmpty(readErr) ? "No output was produced by the coord prog." : readErr;
                return null;
            }
            return vals;
        }

        private static ArrayList GetRetVals(HttpContext context, string key, out string error)
        {
            error = null;
            var list = new ArrayList();
            string schema = (context.Session["s_schema"] ?? "").ToString().Trim();
            if (!SchemaOk.IsMatch(schema) || string.IsNullOrEmpty(key) || key.IndexOf('\'') >= 0)
            {
                error = "No results found (invalid schema or job id).";
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
                error = "No results found (" + schema + " / " + key + ": " + ex.Message + ").";
                return null;
            }
            if (list.Count < 1)
                error = "No results found (job " + key + " wrote no rows in " + schema + ".returnvalues).";
            return list;
        }

        private static string SourceTable(HttpContext context)
        {
            string site = "";
            if (context.Session["SiteName"] != null) site = context.Session["SiteName"].ToString();
            else if (context.Session["siteName"] != null) site = context.Session["siteName"].ToString();
            if (site.IndexOf("remicsdev", StringComparison.OrdinalIgnoreCase) >= 0
                || site.IndexOf("micstest", StringComparison.OrdinalIgnoreCase) >= 0)
                return "adm.pcn_account_details";
            return "adm.account_details";
        }

        private static string LookupEmail(OdbcConnection cn, string sourceTable, string ultrixid, string micsid)
        {
            string sql = "SELECT email FROM " + sourceTable +
                " WHERE ultrixid = '" + Esc(ultrixid) + "' AND micsid = '" + Esc(micsid) + "'";
            using (var cmd = new OdbcCommand(sql, cn))
            {
                object o = cmd.ExecuteScalar();
                if (o != null && o != DBNull.Value)
                {
                    string em = o.ToString().Trim();
                    if (em.Length > 0) return em;
                }
            }
            sql = "SELECT email FROM dbo.t_UserDetails WHERE RTRIM(micsId) = '" + Esc(micsid) +
                "' AND RTRIM(IsActiveYN) = 'Y'";
            using (var cmd = new OdbcCommand(sql, cn))
            {
                object o = cmd.ExecuteScalar();
                if (o != null && o != DBNull.Value)
                {
                    string em = o.ToString().Trim();
                    if (em.Length > 0) return em;
                }
            }
            return "";
        }

        private static string UserDir(HttpContext context)
        {
            string userDir = context.Session["user_dir"].ToString();
            if (!userDir.EndsWith("\\") && !userDir.EndsWith("/")) userDir += "\\";
            return userDir;
        }

        private static string ReadCapped(string path)
        {
            if (!File.Exists(path)) return "";
            string text = File.ReadAllText(path);
            if (text.Length > 512 * 1024) return text.Substring(0, 512 * 1024);
            return text;
        }

        private static string Quoted(string s)
        {
            s = (s ?? "").Replace("\"", "").Trim();
            if (s.Length == 0) s = "-";
            return "\"" + s + "\"";
        }

        private static string Norm(string raw) { return (raw ?? "").Trim(); }
        private static string Dash(string s) { return s.Length == 0 ? "-" : s; }
        private static string T(ArrayList a, int i)
        {
            if (i >= a.Count || a[i] == null) return "";
            return a[i].ToString().Trim();
        }
        private static string BlankDash(object o)
        {
            string s = o == null ? "" : o.ToString().Trim();
            return s.Length == 0 ? "--" : s;
        }
        private static bool NumOk(string s)
        {
            double d;
            return s.Length > 0 && (double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out d)
                || double.TryParse(s, NumberStyles.Float, CultureInfo.CurrentCulture, out d));
        }
        private static string NumOrZero(string raw)
        {
            string s = Norm(raw);
            return NumOk(s) ? s : "0";
        }
        private static string Esc(string s)
        {
            return (s ?? "").Replace("'", "''");
        }
        private static void WriteJson(HttpResponse response, object obj)
        {
            var ser = new JavaScriptSerializer();
            ser.MaxJsonLength = int.MaxValue;
            response.Write(ser.Serialize(obj));
        }
    }
}
