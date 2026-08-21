<%@ WebHandler Language="C#" Class="RemIcsReWrite.AuxPassiveHandler" %>

using System;
using System.Data.Odbc;
using System.Globalization;
using System.IO;
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
    /// <summary>Passive Calculations  -  parity with auxengmenu/AUXpassive1 + AUXpassive2 / wPassive.</summary>
    public class AuxPassiveHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly Regex SchemaOk = new Regex(@"^[A-Za-z][A-Za-z0-9_]*$", RegexOptions.Compiled);
        private static readonly Regex UserOk = new Regex(@"^[A-Za-z0-9_]{1,16}$", RegexOptions.Compiled);
        private static readonly Regex LatOk = new Regex(@"^[0-9]{1,2}-[0-9]{1,2}-[0-9]{1,2}(\.[0-9]+)?[NnSs]$", RegexOptions.Compiled);
        private static readonly Regex LngOk = new Regex(@"^[0-9]{1,3}-[0-9]{1,2}-[0-9]{1,2}(\.[0-9]+)?[WwEe]$", RegexOptions.Compiled);

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
                    string action = (context.Request["action"] ?? "run").Trim().ToLowerInvariant();
                    if (action == "email") HandleEmail(context);
                    else HandleRun(context);
                }
            }
            catch (Exception ex)
            {
                context.Response.StatusCode = 500;
                WriteJson(context.Response, new { ok = false, error = ex.Message });
            }
        }

        private static void HandleRun(HttpContext context)
        {
            SesUtils.LogMenuUse("AUXPassive");

            bool isLl = (context.Request["mode"] ?? "").Trim().ToUpperInvariant() == "L";
            int nPass;
            if (!int.TryParse((context.Request["nPass"] ?? "").Trim(), NumberStyles.Integer,
                CultureInfo.InvariantCulture, out nPass) || nPass < 1 || nPass > 4)
            {
                WriteJson(context.Response, new { ok = false, error = "Add at least one passive and the last active." });
                return;
            }

            string freq, power0, again0, fsl0, power5, again5, fsl5;
            if (!CsvNum(context.Request["freq"], out freq)
                || !CsvNum(context.Request["power0"], out power0)
                || !CsvNum(context.Request["again0"], out again0)
                || !CsvNum(context.Request["fsl0"], out fsl0))
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = "You must enter all of Frequency, Power, Gain, and FSL on the first active."
                });
                return;
            }
            if (!CsvNum(context.Request["power5"], out power5)
                || !CsvNum(context.Request["again5"], out again5)
                || !CsvNum(context.Request["fsl5"], out fsl5))
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = "You must enter the Last Active's Power, Gain, and FSL."
                });
                return;
            }

            var sb = new StringBuilder();
            sb.AppendLine((isLl ? "L" : "D") + "," + nPass.ToString(CultureInfo.InvariantCulture) + "," + freq);

            string err;
            if (isLl)
            {
                string a1;
                if (!LlHop(context, 0, true, out a1, out err))
                {
                    WriteJson(context.Response, new { ok = false, error = err });
                    return;
                }
                sb.AppendLine("Active#1," + power0 + "," + again0 + "," + fsl0 + "," + a1);
                for (int i = 1; i <= nPass; i++)
                {
                    string wd, ht, hop;
                    if (!CsvNum(context.Request["wd" + i], out wd) || !CsvNum(context.Request["ht" + i], out ht))
                    {
                        WriteJson(context.Response, new
                        {
                            ok = false,
                            error = "You must enter the antenna Width and Height for passive " + i
                        });
                        return;
                    }
                    if (!LlHop(context, i, false, out hop, out err))
                    {
                        WriteJson(context.Response, new { ok = false, error = err });
                        return;
                    }
                    sb.AppendLine("Passive#" + i + "," + wd + "," + ht + "," + hop);
                }
                string a2;
                if (!LlHop(context, 5, true, out a2, out err))
                {
                    WriteJson(context.Response, new { ok = false, error = err });
                    return;
                }
                sb.AppendLine("Active#2," + power5 + "," + again5 + "," + fsl5 + "," + a2);
            }
            else
            {
                string dst0;
                if (!CsvNum(context.Request["dst0"], out dst0))
                {
                    WriteJson(context.Response, new { ok = false, error = "You must enter a distance." });
                    return;
                }
                sb.AppendLine("Active#1," + power0 + "," + again0 + "," + fsl0 + "," + dst0);
                for (int i = 1; i <= nPass; i++)
                {
                    string wd, ht, ang, dst;
                    if (!CsvNum(context.Request["wd" + i], out wd) || !CsvNum(context.Request["ht" + i], out ht))
                    {
                        WriteJson(context.Response, new
                        {
                            ok = false,
                            error = "You must enter the antenna Width and Height for passive " + i
                        });
                        return;
                    }
                    if (!CsvNum(context.Request["dst" + i], out dst) || !CsvNum(context.Request["ang" + i], out ang))
                    {
                        WriteJson(context.Response, new
                        {
                            ok = false,
                            error = "You must enter distance and included angle for Passive " + i
                        });
                        return;
                    }
                    sb.AppendLine("Passive#" + i + "," + wd + "," + ht + "," + ang + "," + dst);
                }
                sb.AppendLine("Active#2," + power5 + "," + again5 + "," + fsl5);
            }

            dblogger oLog = new dblogger(context.Session["prog_dir"].ToString() + "wPassive");
            string cInFile = "p" + oLog.logserial + ".in";
            string cOut = context.Session["user_dir"].ToString() + cInFile;
            try
            {
                File.WriteAllText(cOut, sb.ToString(), Encoding.ASCII);
            }
            catch (Exception ex)
            {
                WriteJson(context.Response, new { ok = false, error = "Could not create file: " + ex.Message });
                return;
            }

            oLog.logargs = context.Session["db_name"].ToString() + " " + cOut + " " + oLog.logserial;
            oLog = JobSubmit.SubmitJob(oLog, " ", 60);
            if (oLog.Finish() != 0)
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = "Database Server failed to update logger." + (oLog.logerrordesc ?? "")
                });
                return;
            }

            if (oLog.logerrorcode == -99)
            {
                WriteJson(context.Response, new { ok = false, error = "Program timed out: " + (oLog.logerrordesc ?? "") });
                return;
            }
            if (oLog.logerrorcode == -98)
            {
                WriteJson(context.Response, new { ok = false, error = "Could not start program for reason: " + (oLog.logerrordesc ?? "") });
                return;
            }
            if (oLog.logerrorcode != 0)
            {
                string desc = oLog.logerrordesc != null ? oLog.logerrordesc.Trim() : "";
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = desc.Length > 0 ? desc : "Program execution error."
                });
                return;
            }

            string txtName = "p" + oLog.logserial + ".txt";
            string txtPath = context.Session["user_dir"].ToString() + txtName;
            string schema = context.Session["s_schema"].ToString().Trim();
            string user = context.Session["s_user"].ToString().Trim();
            if (!SchemaOk.IsMatch(schema) || !UserOk.IsMatch(user))
            {
                WriteJson(context.Response, new { ok = false, error = "Session not initialized." });
                return;
            }
            string url = "../userdirs/" + schema + "/" + user + "/" + txtName;
            string text = "";
            string note = "";
            if (!File.Exists(txtPath))
                note = "File: " + txtPath + " does not exist";
            else
            {
                FileInfo info = new FileInfo(txtPath);
                if (info.Length > 0)
                {
                    if (info.Length > 512 * 1024)
                        text = File.ReadAllText(txtPath).Substring(0, 512 * 1024);
                    else
                        text = File.ReadAllText(txtPath);
                }
            }

            WriteJson(context.Response, new
            {
                ok = true,
                serial = oLog.logserial,
                url = url,
                text = text,
                note = note
            });
        }

        private static bool LlHop(HttpContext context, int i, bool isActive, out string hop, out string error)
        {
            hop = "";
            string lat = (context.Request["lat" + i] ?? "").Trim();
            string lng = (context.Request["lng" + i] ?? "").Trim();
            string alt, ant;
            if (!LatOk.IsMatch(lat) || !LngOk.IsMatch(lng) || !CsvNum(context.Request["alt" + i], out alt)
                || !CsvNum(context.Request["ant" + i], out ant))
            {
                error = isActive
                    ? (i == 0
                        ? "You must enter lat/long, altitude and Antenna Height for the first active."
                        : "You must enter lat/long, altitude and Antenna Height for the last active.")
                    : ("You must enter Lat/Long, altitude, and Ant. Height for Passive " + i);
                return false;
            }
            string latCsv, lngCsv;
            if (!PackLl(lat, 90, "NS", out latCsv, out error) || !PackLl(lng, 180, "WE", out lngCsv, out error))
            {
                error = "Lat/Long error on " + (isActive ? (i == 0 ? "active#1" : "last active") : ("passive#" + i)) + ": " + error;
                return false;
            }
            hop = latCsv + "," + lngCsv + "," + alt + "," + ant;
            error = "";
            return true;
        }

        private static bool PackLl(string raw, int nMax, string senses, out string csv, out string error)
        {
            csv = "";
            error = "";
            Match m = Regex.Match(raw.Trim(),
                @"^(\d{1,3})-(\d{1,2})-(\d{1,2})(?:\.(\d+))?([NnSsEeWw])$");
            if (!m.Success) { error = "No Match"; return false; }
            int deg = int.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture);
            int min = int.Parse(m.Groups[2].Value, CultureInfo.InvariantCulture);
            int sec = int.Parse(m.Groups[3].Value, CultureInfo.InvariantCulture);
            string sense = m.Groups[5].Value.ToUpperInvariant();
            if (senses.IndexOf(sense) < 0)
            {
                error = "Sense must be " + senses[0] + " or " + senses[1];
                return false;
            }
            if (sec >= 60) { error = "60 seconds or more."; return false; }
            if (min >= 60) { error = "60 minutes or more."; return false; }
            if (deg > nMax) { error = "More than " + nMax + " degrees."; return false; }
            int packed = deg * 10000 + min * 100 + sec;
            csv = packed.ToString(CultureInfo.InvariantCulture) + "," + sense;
            return true;
        }

        private static bool CsvNum(string raw, out string val)
        {
            val = (raw ?? "").Trim();
            if (val.Length == 0 || val.Length > 24 || val.IndexOf(',') >= 0 || val.IndexOf('\n') >= 0
                || val.IndexOf('\r') >= 0)
                return false;
            double d;
            return double.TryParse(val, NumberStyles.Float, CultureInfo.InvariantCulture, out d)
                || double.TryParse(val, NumberStyles.Float, CultureInfo.CurrentCulture, out d);
        }

        private static void HandleEmail(HttpContext context)
        {
            string serial = (context.Request["serial"] ?? "").Trim();
            if (!SerialOk.IsMatch(serial))
            {
                WriteJson(context.Response, new { ok = false, error = "Run the calculation first." });
                return;
            }
            string userDir = context.Session["user_dir"].ToString();
            if (!userDir.EndsWith("\\") && !userDir.EndsWith("/")) userDir += "\\";
            string path = userDir + "p" + serial + ".txt";
            if (!File.Exists(path) || new FileInfo(path).Length < 1)
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

            string subject = "MICS Passive Calculation report";
            string body = "The Passive Calculation report is attached.\n\nAccount: " + schema +
                "\nUser: " + user + "\n\nDelivery can take up to 20 minutes.\n";
            bool queued = SesUtils.InsertEmailQueue("mics@fcsa.ca", mailTo, null, subject, body, path);
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
                " WHERE ultrixid = '" + (ultrixid ?? "").Replace("'", "''") +
                "' AND micsid = '" + (micsid ?? "").Replace("'", "''") + "'";
            using (var cmd = new OdbcCommand(sql, cn))
            {
                object o = cmd.ExecuteScalar();
                if (o != null && o != DBNull.Value)
                {
                    string em = o.ToString().Trim();
                    if (em.Length > 0) return em;
                }
            }
            sql = "SELECT email FROM dbo.t_UserDetails WHERE RTRIM(micsId) = '" +
                (micsid ?? "").Replace("'", "''") + "' AND RTRIM(IsActiveYN) = 'Y'";
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

        private static void WriteJson(HttpResponse response, object obj)
        {
            var ser = new JavaScriptSerializer();
            ser.MaxJsonLength = int.MaxValue;
            response.Write(ser.Serialize(obj));
        }
    }
}
