<%@ WebHandler Language="C#" Class="RemIcsReWrite.AuxOrbitHandler" %>

using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using DBAccess;
using JobSubmission;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>Orbit Intersection  -  parity with auxengmenu/AUXOrbit.aspx.</summary>
    public class AuxOrbitHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly Regex CallOk = new Regex(@"^[A-Za-z0-9_%.\-]{1,16}$", RegexOptions.Compiled);
        private static readonly Regex TokenOk = new Regex(@"^[A-Za-z0-9+\-.]{1,24}$", RegexOptions.Compiled);
        private static readonly Regex SchemaOk = new Regex(@"^[A-Za-z][A-Za-z0-9_]*$", RegexOptions.Compiled);
        private static readonly Regex LatN = new Regex(@"^[0-9]{2}-[0-9]{2}-[0-9]{2}\.[0-9]{2}[nN]$", RegexOptions.Compiled);
        private static readonly Regex LngW = new Regex(@"^[0-9]{3}-[0-9]{2}-[0-9]{2}\.[0-9]{2}[wW]$", RegexOptions.Compiled);

        public bool IsReusable { get { return false; } }

        public void ProcessRequest(HttpContext context)
        {
            var response = context.Response;
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

            string action = (context.Request["action"] ?? "coords").Trim().ToLowerInvariant();
            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                {
                    if (action == "run") HandleRun(context);
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
            SesUtils.LogMenuUse("AUXOrbit");

            string call = Norm(context.Request["call"]);
            string lat = Norm(context.Request["lat"]);
            string lng = Norm(context.Request["lng"]);
            string utmN = Norm(context.Request["utmNorth"]);
            string utmE = Norm(context.Request["utmEast"]);
            string utmZ = Norm(context.Request["utmZone"]);
            string alt = Norm(context.Request["alt"]);
            string antHt = Norm(context.Request["antHt"]);

            string mode, err;
            if (!PickMode(call, lat, lng, utmN, utmE, utmZ, alt, antHt, out mode, out err))
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

            string jobErr;
            dblogger done;
            ArrayList coords = RunJob(context, oLog, 30, "getcoords", out done, out jobErr);
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

            string outCall = BlankDash(coords[0]);
            string siteName = BlankDash(coords[1]);
            string lat84 = T(coords, 4);
            string lng84 = T(coords, 5);
            if (alt.Length == 0 && coords.Count > 9 && T(coords, 9).Length > 0)
                alt = T(coords, 9);
            if (alt.Length == 0) alt = "0";

            WriteJson(context.Response, new
            {
                ok = true,
                serial = oLog.logserial,
                call = outCall,
                siteName = siteName,
                lat84 = lat84,
                lng84 = lng84,
                utmNorth = T(coords, 6),
                utmEast = T(coords, 7),
                utmZone = T(coords, 8),
                alt = alt,
                antHt = antHt
            });
        }

        private static void HandleRun(HttpContext context)
        {
            string call1 = Dash(Norm(context.Request["call1"]));
            string lat1 = Norm(context.Request["lat1"]);
            string lng1 = Norm(context.Request["lng1"]);
            string alt1 = NumOrZero(context.Request["alt1"]);
            string ant1 = NumOrZero(context.Request["antHt1"]);
            string call2 = Dash(Norm(context.Request["call2"]));
            string lat2 = Norm(context.Request["lat2"]);
            string lng2 = Norm(context.Request["lng2"]);
            string alt2 = NumOrZero(context.Request["alt2"]);
            string ant2 = NumOrZero(context.Request["antHt2"]);
            bool trueAz = ParseFlag(context.Request["trueAz"]);
            string taz = Norm(context.Request["trueAzVal"]);
            string tel = Norm(context.Request["trueElVal"]);

            if (!TokenOk.IsMatch(lat1) || !TokenOk.IsMatch(lng1) || !TokenOk.IsMatch(lat2) || !TokenOk.IsMatch(lng2))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Both sites need resolved WGS84 coordinates." });
                return;
            }
            if (trueAz)
            {
                double dEl, dAz;
                if (!double.TryParse(taz, NumberStyles.Float, CultureInfo.InvariantCulture, out dAz)
                    || !double.TryParse(tel, NumberStyles.Float, CultureInfo.InvariantCulture, out dEl)
                    || dEl > 90.0 || dEl < -90.0)
                {
                    WriteJson(context.Response, new
                    {
                        ok = false,
                        error = "True Elevation Angle must be between -90 and +90 degrees."
                    });
                    return;
                }
                taz = dAz.ToString(CultureInfo.InvariantCulture);
                tel = dEl.ToString(CultureInfo.InvariantCulture);
            }

            if (!CallOk.IsMatch(call1) && call1 != "-" && call1 != "--") call1 = "-";
            if (!CallOk.IsMatch(call2) && call2 != "-" && call2 != "--") call2 = "-";

            dblogger oLog = new dblogger(context.Session["prog_dir"].ToString() + "wOrbit");
            string cArgs = context.Session["db_name"].ToString() + " " + call1 + " " + lat1 + " " + lng1 +
                " " + alt1 + " " + ant1 + " " + call2 + " " + lat2 + " " + lng2 + " " + alt2 + " " + ant2;
            if (trueAz)
                cArgs += " T " + taz + " " + tel;
            else
                cArgs += " F 0 0";
            cArgs += " " + oLog.logserial;
            oLog.logargs = cArgs;

            string jobErr;
            dblogger done;
            ArrayList a = RunJob(context, oLog, 30, "wOrbit", out done, out jobErr);
            oLog = done ?? oLog;
            if (oLog.logreturncode != 0)
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = string.IsNullOrEmpty(jobErr)
                        ? ("wOrbit -- Error return: " + oLog.logreturncode)
                        : jobErr,
                    serial = oLog.logserial
                });
                return;
            }
            if (a == null || a.Count < 19)
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = string.IsNullOrEmpty(jobErr) ? "wOrbit -- Could not return values" : jobErr,
                    serial = oLog.logserial
                });
                return;
            }

            int nErr = ToInt(a[2]);
            double dDist = ToDbl(a[3]);
            double minAngSep = ToDbl(a[8]);
            double e1_10 = ToDbl(a[9]);
            int trans = ToInt(a[18]);

            string note = OrbitNote(nErr);
            if (nErr == 10 || nErr == 11)
                note += " ITU Algorithm used.  Angular Separation is: " + F(a[12], 2) + " degrees.";

            var sats = new List<object>();
            if (nErr == 3 || nErr == 6 || nErr == 7)
            {
                note += " The following satellites are within the critical longitudes.";
                try
                {
                    double dFrom = GetCoord(a[14].ToString(), a[15].ToString());
                    double dTo = GetCoord(a[16].ToString(), a[17].ToString());
                    geosats oGSs = new geosats();
                    geosat[] aGS = oGSs.getlist(dFrom, dTo);
                    foreach (geosat oGS in aGS)
                    {
                        sats.Add(new
                        {
                            norad = oGS.satNoradId,
                            name = oGS.satName,
                            orbit = oGS.satOrbit,
                            lng = oGS.satcLong
                        });
                    }
                }
                catch { /* classic still showed the report if geosats failed */ }
            }

            WriteJson(context.Response, new
            {
                ok = true,
                serial = oLog.logserial,
                call1 = call1,
                call2 = call2,
                lat1 = lat1,
                lng1 = lng1,
                lat2 = lat2,
                lng2 = lng2,
                alt1 = alt1,
                alt2 = alt2,
                antHt1 = ant1,
                antHt2 = ant2,
                dist = dDist == 0.0 ? "" : F(a[3], 2),
                azim = dDist == 0.0 ? "" : F(a[4], 1),
                elev = dDist == 0.0 ? "" : F(a[5], 2),
                insL = (nErr != 6 && nErr != 7 && minAngSep == 0.0) ? "" : F(a[6], 2),
                insLSense = (nErr != 6 && nErr != 7 && minAngSep == 0.0) ? "" : a[7].ToString().Trim(),
                minAngSep = (nErr != 6 && nErr != 7 && minAngSep == 0.0) ? "" : F(a[8], 2),
                e1_10 = e1_10 == 0.0 ? "" : F(a[9], 2),
                e10_15 = e1_10 == 0.0 ? "" : F(a[10], 2),
                eGt15 = e1_10 == 0.0 ? "" : F(a[11], 2),
                crAzSt = e1_10 == 0.0 ? "" : F(a[12], 2),
                crAzEnd = e1_10 == 0.0 ? "" : F(a[13], 2),
                crLongFrom = e1_10 == 0.0 ? "" : F(a[14], 2) + " " + a[15].ToString().Trim(),
                crLongTo = e1_10 == 0.0 ? "" : F(a[16], 2) + " " + a[17].ToString().Trim(),
                swapped = trans != 0,
                trueAz = trueAz,
                note = note,
                sats = sats
            });
        }

        private static bool PickMode(string call, string lat, string lng, string utmN, string utmE, string utmZ,
            string alt, string antHt, out string mode, out string error)
        {
            mode = "";
            error = "";
            if (call.Length > 0 && call != "--")
            {
                if (!CallOk.IsMatch(call)) { error = "Invalid call sign."; return false; }
                if (!NumOk(antHt))
                {
                    error = "You must specify an antenna height when entering a call sign";
                    return false;
                }
                mode = "CALL";
                return true;
            }
            if (lat.Length > 0 || lng.Length > 0)
            {
                string llErr;
                if (!ValidOrbitLl(lat, lng, out llErr)) { error = llErr; return false; }
                if (!NumOk(alt))
                {
                    error = "You must specify an altitude when entering lat/longs";
                    return false;
                }
                if (!NumOk(antHt))
                {
                    error = "You must specify an antenna height when entering lat/longs";
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
                if (!NumOk(alt))
                {
                    error = "You must specify an altitude when entering UTM coordinates";
                    return false;
                }
                if (!NumOk(antHt))
                {
                    error = "You must specify an antenna height when entering UTM coordinates";
                    return false;
                }
                mode = "UTM";
                return true;
            }
            error = "You must specify a call, the lat/longs or the UTM coords";
            return false;
        }

        private static bool ValidOrbitLl(string lat, string lng, out string error)
        {
            error = "";
            if (!LatN.IsMatch(lat)) { error = "Latitude format must be nn-nn-nn.nnN"; return false; }
            if (!LngW.IsMatch(lng)) { error = "Longitude format must be nnn-nn-nn.nnW"; return false; }
            int deg = int.Parse(lat.Substring(0, 2), CultureInfo.InvariantCulture);
            int min = int.Parse(lat.Substring(3, 2), CultureInfo.InvariantCulture);
            double sec = double.Parse(lat.Substring(6, 5), CultureInfo.InvariantCulture);
            if (deg > 90) { error = "Latitude degrees out of range"; return false; }
            if (min >= 60 || (deg == 90 && min > 0)) { error = "Latitude minutes out of range"; return false; }
            if (sec >= 60 || (deg == 90 && sec > 0)) { error = "Latitude seconds out of range"; return false; }
            deg = int.Parse(lng.Substring(0, 3), CultureInfo.InvariantCulture);
            min = int.Parse(lng.Substring(4, 2), CultureInfo.InvariantCulture);
            sec = double.Parse(lng.Substring(7, 5), CultureInfo.InvariantCulture);
            if (deg > 180) { error = "Longitude degrees out of range"; return false; }
            if (min >= 60 || (deg == 180 && min > 0)) { error = "Longitude minutes out of range"; return false; }
            if (sec >= 60 || (deg == 180 && sec > 0)) { error = "Longitude seconds out of range"; return false; }
            return true;
        }

        private static ArrayList RunJob(HttpContext context, dblogger oLog, int timeout, string name,
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
                error = name == "wOrbit"
                    ? "System timed out while getting orbit intersection report."
                    : "Program timed out while getting coordinates.";
                return null;
            }
            if (oLog.logerrorcode == -98)
            {
                error = name == "wOrbit"
                    ? "Could not start the orbit intersection program."
                    : "Could not start the coordinate prog.";
                return null;
            }
            // W4-8: non-zero process exit is failure for getcoords (was AND with logerrorcode).
            if (name == "getcoords" && oLog.logreturncode != 0)
            {
                error = "Coordinate program failed(3): " + oLog.logreturncode;
                return null;
            }
            string readErr;
            ArrayList vals = GetRetVals(context, oLog.logserial, out readErr);
            if (vals == null || vals.Count < 1)
            {
                error = string.IsNullOrEmpty(readErr) ? "No Response from Server" : readErr;
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

        private static string OrbitNote(int nErr)
        {
            switch (nErr)
            {
                case -2: return "No convergence to reference point for given refractivity.";
                case -3: return "No convergence while calculating critical azimuth";
                case -4: return "No convergence during angular separation calculation";
                case -5: return "SAT_CONVERG_FAIL";
                case -6: return "Return code not set in Orbit";
                case -7: return "Site too close to equator";
                case -8: return "Elev. Ang. points above the entire orbit";
                case -9: return "Elev. Ang. points below the sea level horizon";
                case -10: return "Invalid data on input from file";
                case -11: return "Processing complete";
                case -12: return "PAT_AF_FAIL";
                case -13: return "SAT_BHG_FAIL";
                case -14: return "Log of negative value";
                case -15: return "Log of negative value";
                case -16: return "PAS_DPE_FAIL";
                case -17: return "PAS_SP_FAIL";
                case -18: return "Invalid refractivity constant";
                case -19: return "Invalid Latitude on input";
                case -20: return "Invalid Longitude on input";
                case 2: return "No intersection, points above the refracted geostationary orbit - RGO (N=400), Min. Ang. Sep. is GT 5 degrees";
                case 3: return "Intersects the RGO (N=400)";
                case 4: return "Points above the GO (N=400)";
                case 5: return "Points above the RGO (N=400)";
                case 6: return "Intersects the RGO.";
                case 7: return "Intersection of beam";
                case 8: return "Points below the RGO (N=250)";
                case 9: return "Points below the RGO (N=250) Min. Ang. Sep. is GT 5 degrees";
                case 10: return "Antenna Elevation greater than 10 degrees.";
                case 11: return "Site Latitude greater than 60 degrees.";
                case 12: return "Error in ITU calculation of angular separation.";
                default: return "";
            }
        }

        private static double GetCoord(string cVal, string cSense)
        {
            double dDir = 1.0;
            if (!string.IsNullOrEmpty(cSense) && "nNwW".IndexOf(cSense[0]) < 0) dDir = -1.0;
            double dOut;
            if (!double.TryParse((cVal ?? "").Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out dOut))
                dOut = 0;
            return dOut * dDir;
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
            return s.Length > 0 && double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out d);
        }
        private static string NumOrZero(string raw)
        {
            string s = Norm(raw);
            return NumOk(s) ? s : "0";
        }
        private static bool ParseFlag(string raw)
        {
            raw = (raw ?? "").Trim();
            return raw == "1" || raw.Equals("true", StringComparison.OrdinalIgnoreCase) || raw.Equals("on", StringComparison.OrdinalIgnoreCase);
        }
        private static double ToDbl(object o)
        {
            double d;
            if (o == null) return 0;
            double.TryParse(o.ToString().Trim(), NumberStyles.Float, CultureInfo.CurrentCulture, out d);
            return d;
        }
        private static int ToInt(object o)
        {
            int n;
            if (o == null) return 0;
            int.TryParse(o.ToString().Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out n);
            return n;
        }
        private static string F(object o, int nDec)
        {
            return ToDbl(o).ToString("F" + nDec, CultureInfo.CurrentCulture);
        }
        private static void WriteJson(HttpResponse response, object obj)
        {
            var ser = new JavaScriptSerializer();
            ser.MaxJsonLength = int.MaxValue;
            response.Write(ser.Serialize(obj));
        }
    }
}
