<%@ WebHandler Language="C#" Class="RemIcsReWrite.AuxSatazeHandler" %>

using System;
using System.Collections;
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
    /// <summary>Satellite Bearings  -  parity with auxengmenu/AUXSataze1 + AUXSataze2.</summary>
    public class AuxSatazeHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly Regex CallOk = new Regex(@"^[A-Za-z0-9_%.\-]{1,16}$", RegexOptions.Compiled);
        private static readonly Regex TokenOk = new Regex(@"^[A-Za-z0-9+\-.]{1,24}$", RegexOptions.Compiled);
        private static readonly Regex SchemaOk = new Regex(@"^[A-Za-z][A-Za-z0-9_]*$", RegexOptions.Compiled);

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

            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                {
                    HandleRun(context);
                }
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        private static void HandleRun(HttpContext context)
        {
            SesUtils.LogMenuUse("AUXSatBearing");

            string call = Norm(context.Request["call"]);
            string lat = Norm(context.Request["lat"]);
            string lng = Norm(context.Request["lng"]);
            string utmN = Norm(context.Request["utmNorth"]);
            string utmE = Norm(context.Request["utmEast"]);
            string utmZ = Norm(context.Request["utmZone"]);
            string grnd = Norm(context.Request["grnd"]);
            string antHt = Norm(context.Request["antHt"]);
            string satName = (context.Request["satName"] ?? "").Trim();
            if (satName.Length > 40) satName = satName.Substring(0, 40);
            string satLng = Norm(context.Request["satLng"]);
            string refract = Norm(context.Request["refract"]);
            if (refract.Length == 0) refract = "330";

            string mode;
            string coordsErr;
            if (!PickMode(call, lat, lng, utmN, utmE, utmZ, antHt, grnd, satName, satLng, refract,
                out mode, out coordsErr))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = coordsErr });
                return;
            }

            string db = context.Session["db_name"].ToString();
            string progDir = context.Session["prog_dir"].ToString();

            dblogger oLog = new dblogger(progDir + "getcoords");
            if (mode == "LOC")
                oLog.logargs = db + " " + oLog.logserial + " LOC " + call;
            else if (mode == "LL")
                oLog.logargs = db + " " + oLog.logserial + " LL " + lat + " " + lng;
            else
                oLog.logargs = db + " " + oLog.logserial + " UTM " + utmN + " " + utmE + " " + utmZ;

            string jobErr;
            dblogger done;
            ArrayList coords = RunJob(context, oLog, 30, "getcoords", out done, out jobErr);
            oLog = done ?? oLog;
            if (coords == null)
            {
                if (oLog.logreturncode == 15 || oLog.logreturncode == 16)
                    jobErr = "Could not find the ES site: " + call;
                WriteJson(context.Response, new { ok = false, error = jobErr, serial = oLog.logserial });
                return;
            }
            if (coords.Count < 9)
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = "Coordinate program returned no usable values.",
                    serial = oLog.logserial
                });
                return;
            }

            string outCall = BlankDash(coords[0]);
            string siteName = BlankDash(coords[1]);
            string lat84 = coords.Count > 4 ? coords[4].ToString().Trim() : "";
            string lng84 = coords.Count > 5 ? coords[5].ToString().Trim() : "";
            string outUtmN = coords.Count > 6 ? coords[6].ToString().Trim() : "";
            string outUtmE = coords.Count > 7 ? coords[7].ToString().Trim() : "";
            string outUtmZ = coords.Count > 8 ? coords[8].ToString().Trim() : "";
            if (grnd.Length == 0 && coords.Count > 9)
                grnd = coords[9].ToString().Trim();
            if (grnd.Length == 0) grnd = "0";

            if (!TokenOk.IsMatch(lat84) || !TokenOk.IsMatch(lng84) || !NumOk(grnd) || !NumOk(antHt)
                || !NumOk(satLng) || !NumOk(refract))
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = "Coordinate conversion did not produce values wSataze can use."
                });
                return;
            }

            oLog = new dblogger(progDir + "wSataze");
            oLog.logargs = db + " " + lat84 + " " + lng84 + " " + grnd + " " + antHt + " " +
                satLng + " " + refract + " " + oLog.logserial;

            ArrayList bearings = RunJob(context, oLog, 60, "wSataze", out done, out jobErr);
            oLog = done ?? oLog;
            if (bearings == null || bearings.Count < 4)
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = string.IsNullOrEmpty(jobErr) ? "No Response from Server" : jobErr,
                    serial = oLog.logserial
                });
                return;
            }

            WriteJson(context.Response, new
            {
                ok = true,
                serial = oLog.logserial,
                call = outCall,
                siteName = siteName,
                lat84 = lat84,
                lng84 = lng84,
                grnd = grnd,
                utmNorth = outUtmN,
                utmEast = outUtmE,
                utmZone = outUtmZ,
                antHt = antHt,
                satName = satName,
                satLng = satLng,
                refract = refract,
                azimuth = bearings[1].ToString().Trim(),
                elevation = bearings[2].ToString().Trim(),
                refElevation = bearings[3].ToString().Trim()
            });
        }

        private static bool PickMode(string call, string lat, string lng, string utmN, string utmE, string utmZ,
            string antHt, string grnd, string satName, string satLng, string refract,
            out string mode, out string error)
        {
            mode = "";
            error = "";
            if (satName.Length == 0 || !NumOk(satLng) || !NumOk(refract) || !NumOk(antHt))
            {
                error = "You must enter Antenna Height, Satellite Name, Longitude, and Refraction Index.";
                return false;
            }
            if (call.Length > 0)
            {
                if (!CallOk.IsMatch(call))
                {
                    error = "Invalid location code.";
                    return false;
                }
                mode = "LOC";
                return true;
            }
            if (lat.Length > 0 || lng.Length > 0)
            {
                if (lat.Length == 0 || lng.Length == 0)
                {
                    error = "You must enter both Latitude and Longitude.";
                    return false;
                }
                if (!TokenOk.IsMatch(lat) || !TokenOk.IsMatch(lng))
                {
                    error = "Latitude/Longitude is not a valid token.";
                    return false;
                }
                if (!NumOk(grnd))
                {
                    error = "You must enter Altitude, Antenna Height, Satellite Name, Longitude, and Refraction Index.";
                    return false;
                }
                mode = "LL";
                return true;
            }
            if (utmN.Length > 0 || utmE.Length > 0 || utmZ.Length > 0)
            {
                if (utmN.Length == 0 || utmE.Length == 0 || utmZ.Length == 0)
                {
                    error = "You must enter all the UTM coordinates.";
                    return false;
                }
                if (!TokenOk.IsMatch(utmN) || !TokenOk.IsMatch(utmE) || !TokenOk.IsMatch(utmZ))
                {
                    error = "UTM coordinates are not valid.";
                    return false;
                }
                if (!NumOk(grnd))
                {
                    error = "You must enter Altitude, Antenna Height, Satellite Name, Longitude, and Refraction Index.";
                    return false;
                }
                mode = "UTM";
                return true;
            }
            error = "You must enter a call sign or coordinates.";
            return false;
        }

        private static ArrayList RunJob(HttpContext context, dblogger oLog, int timeout, string name,
            out dblogger done, out string error)
        {
            error = null;
            done = JobSubmit.SubmitJob(oLog, " ", timeout);
            oLog = done;
            if (oLog.Finish() != 0)
            {
                error = "Database Server failed to update logger.";
                return null;
            }
            switch (oLog.logerrorcode)
            {
                case 0:
                    break;
                case -99:
                    error = name == "wSataze"
                        ? "System timed out while running wSataze."
                        : "Program timed out while getting coordinates.";
                    return null;
                case -98:
                    error = name == "wSataze"
                        ? "Could not start the wSataze prog"
                        : "Could not start the coordinate prog.";
                    return null;
                default:
                    error = name == "wSataze"
                        ? "wSataze program failed : " + oLog.logreturncode
                        : "Coordinate program failed: " + oLog.logreturncode;
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
            if (!SchemaOk.IsMatch(schema))
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
                error = "No results found (" + schema + " / " + key + ": " + ex.Message + ").";
                return null;
            }
            if (list.Count < 1)
                error = "No results found (job " + key + " wrote no rows in " + schema + ".returnvalues).";
            return list;
        }

        private static string Norm(string raw)
        {
            return (raw ?? "").Trim();
        }

        private static bool NumOk(string s)
        {
            double d;
            return s.Length > 0 && double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out d);
        }

        private static string BlankDash(object o)
        {
            string s = o == null ? "" : o.ToString().Trim();
            return s.Length == 0 ? "--" : s;
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            var ser = new JavaScriptSerializer();
            ser.MaxJsonLength = int.MaxValue;
            response.Write(ser.Serialize(obj));
        }
    }
}
