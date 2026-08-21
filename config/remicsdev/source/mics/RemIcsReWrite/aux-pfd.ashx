<%@ WebHandler Language="C#" Class="RemIcsReWrite.AuxPfdHandler" %>

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
    /// <summary>PFD / Coverage Contours  -  parity with auxengmenu/AUXpfdc1 / pfdcont.</summary>
    public class AuxPfdHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly Regex CallOk = new Regex(@"^[A-Za-z0-9_%.\-]{1,16}$", RegexOptions.Compiled);
        private static readonly Regex TokenOk = new Regex(@"^[A-Za-z0-9+\-.]{1,24}$", RegexOptions.Compiled);
        private static readonly Regex SchemaOk = new Regex(@"^[A-Za-z][A-Za-z0-9_]*$", RegexOptions.Compiled);
        private static readonly Regex AcodeOk = new Regex(@"^[A-Za-z0-9._\-]{1,12}$", RegexOptions.Compiled);

        private class Antenna
        {
            public int anum;
            public string acode;
            public double aht;
            public double azmth;
            public string offazm;
            public double tazmth;
            public string bndcde;
            public string call2;
            public double txpwr;
            public double fsl;
        }

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
            SesUtils.LogMenuUse("AUXPowerFlux");

            string call = Norm(context.Request["call"]);
            string lat = Norm(context.Request["lat"]);
            string lng = Norm(context.Request["lng"]);
            string alt = Norm(context.Request["alt"]);
            string utmN = Norm(context.Request["utmNorth"]);
            string utmE = Norm(context.Request["utmEast"]);
            string utmZ = Norm(context.Request["utmZone"]);
            string contour = Norm(context.Request["contour"]).ToLowerInvariant();
            string loss = Norm(context.Request["loss"]).ToLowerInvariant();
            if (contour != "pfd" && contour != "cov") contour = "pfd";
            if (loss != "sph" && loss != "ter") loss = "sph";

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

            string jobErr;
            dblogger done;
            ArrayList coords = RunGetCoords(context, oLog, 30, out done, out jobErr);
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
            if (alt.Length == 0 && coords.Count > 9 && T(coords, 9).Length > 0)
                alt = T(coords, 9);

            var ants = new List<object>();
            if (outCall != "--")
                ants = LoadAntennas(context, outCall);

            string analysis = (contour == "pfd" ? "Power Flux Density Contours" : "Coverage Contours")
                + (loss == "sph" ? " with Spherical Earth Losses" : " with Terrain Losses");

            WriteJson(context.Response, new
            {
                ok = true,
                serial = oLog.logserial,
                call = outCall,
                siteName = siteName,
                lat84 = T(coords, 4),
                lng84 = T(coords, 5),
                utmNorth = T(coords, 6),
                utmEast = T(coords, 7),
                utmZone = T(coords, 8),
                alt = alt,
                contour = contour,
                loss = loss,
                analysis = analysis,
                antennas = ants
            });
        }

        private static void HandleRun(HttpContext context)
        {
            string call = Dash(Norm(context.Request["call"]));
            string lat = Norm(context.Request["lat"]);
            string lng = Norm(context.Request["lng"]);
            string contour = Norm(context.Request["contour"]).ToLowerInvariant();
            string loss = Norm(context.Request["loss"]).ToLowerInvariant();
            string acode = Norm(context.Request["acode"]);
            string aht = Norm(context.Request["aht"]);
            string azim = Norm(context.Request["azim"]);
            string txpwr = Norm(context.Request["txpwr"]);
            string fsl = Norm(context.Request["fsl"]);
            string altR = Norm(context.Request["altR"]);
            string rxht = Norm(context.Request["rxht"]);
            string bandwidth = Norm(context.Request["bandwidth"]);
            string freq = Norm(context.Request["freq"]);
            string attatten = Norm(context.Request["attatten"]);
            string minPfd = Norm(context.Request["minPfd"]);
            string maxPfd = Norm(context.Request["maxPfd"]);
            string minRx = Norm(context.Request["minRx"]);
            string climate = Norm(context.Request["climate"]).ToUpperInvariant();
            bool outR = Flag(context.Request["outR"]);
            bool outC = Flag(context.Request["outC"]);
            bool outM = Flag(context.Request["outM"]);

            if (contour != "pfd" && contour != "cov")
            {
                WriteJson(context.Response, new { ok = false, error = "Select Power Flux Density or Coverage Contours." });
                return;
            }
            if (loss != "sph" && loss != "ter")
            {
                WriteJson(context.Response, new { ok = false, error = "Select Spherical Earth or Terrain losses." });
                return;
            }
            if (!TokenOk.IsMatch(lat) || !TokenOk.IsMatch(lng))
            {
                WriteJson(context.Response, new { ok = false, error = "Site needs resolved WGS84 coordinates." });
                return;
            }
            if (!AcodeOk.IsMatch(acode) || !NumOk(aht) || !NumOk(azim) || !NumOk(txpwr) || !NumOk(fsl))
            {
                WriteJson(context.Response, new { ok = false, error = "Enter antenna Code, Height, Azimuth, Power, and FSL." });
                return;
            }
            if (!NumOk(altR) || !NumOk(rxht) || !NumOk(bandwidth) || !NumOk(freq) || !NumOk(attatten))
            {
                WriteJson(context.Response, new { ok = false, error = "Enter Ground Ht, Rx Height, Bandwidth, Frequency, and At. Atten." });
                return;
            }
            if (contour == "pfd")
            {
                if (!NumOk(minPfd) || !NumOk(maxPfd))
                {
                    WriteJson(context.Response, new { ok = false, error = "Enter minimum and maximum PFD levels." });
                    return;
                }
            }
            else
            {
                if (!NumOk(minRx))
                {
                    WriteJson(context.Response, new { ok = false, error = "Enter minimum RX power." });
                    return;
                }
                if (climate != "C" && climate != "M") climate = "C";
            }
            if (!outR && !outC && !outM) outR = true;

            if (!CallOk.IsMatch(call) && call != "-" && call != "--") call = "-";
            string callArg = (call == "-" || call == "--" || call.Length == 0) ? "0" : call;

            dblogger oLog = new dblogger(context.Session["prog_dir"].ToString() + "pfdcont", "");
            string userDir = context.Session["user_dir"].ToString();
            if (!userDir.EndsWith("\\") && !userDir.EndsWith("/")) userDir += "\\";

            string cArgs = context.Session["db_name"].ToString();
            cArgs += contour == "pfd" ? " P" : " C";
            cArgs += loss == "sph" ? " S" : " T";
            cArgs += " " + callArg;
            cArgs += " " + lat + " " + lng;
            cArgs += " " + acode + " " + aht + " " + azim + " " + txpwr + " " + fsl;
            cArgs += " " + altR + " " + rxht + " " + bandwidth + " " + freq + " " + attatten;
            if (contour == "pfd")
                cArgs += " " + minPfd + " " + maxPfd;
            else
                cArgs += " " + minRx + " " + climate;
            cArgs += outR ? " R" : " 0";
            cArgs += (outC ? "C" : "0") + (outM ? "M" : "0");
            cArgs += " " + userDir + "p" + oLog.logserial;
            oLog.logargs = cArgs;

            oLog = JobSubmit.SubmitJob(oLog, " ", -1);
            if (oLog.Finish() != 0)
            {
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = "Error updating logger. Return code (" + oLog.logreturncode + ") Error code (" +
                        oLog.logerrorcode + ") " + (oLog.logerrordesc ?? "")
                });
                return;
            }
            if (oLog.logerrorcode == -98)
            {
                WriteJson(context.Response, new { ok = false, error = "Could not start the contour program." });
                return;
            }
            if (oLog.logerrorcode != 0 && oLog.logerrorcode != -99)
            {
                string desc = oLog.logerrordesc != null ? oLog.logerrordesc.Trim() : "";
                WriteJson(context.Response, new
                {
                    ok = false,
                    error = desc.Length > 0 ? desc : ("Contour program failed: " + oLog.logreturncode)
                });
                return;
            }

            WriteJson(context.Response, new
            {
                ok = true,
                serial = oLog.logserial,
                message = "The program has been submitted. You should expect the reports you requested to be emailed to you when they are finished. The file reference for this run is: p" + oLog.logserial
            });
        }

        private static List<object> LoadAntennas(HttpContext context, string call1)
        {
            var list = new List<object>();
            string schema = (context.Session["s_schema"] ?? "").ToString().Trim();
            if (!SchemaOk.IsMatch(schema) || !CallOk.IsMatch(call1)) return list;

            var ants = new List<Antenna>();
            try
            {
                using (var cn = new SqlConnection(MicsDbAuth.GetSqlClientConnectionString()))
                {
                    cn.Open();
                    using (var cmd = new SqlCommand(
                        "SELECT anum, acode, aht, azmth, offazm, tazmth, bndcde, call2 FROM " + schema +
                        ".mt_ante WHERE call1=@c AND (ause='TX' OR ause='TR')", cn))
                    {
                        cmd.Parameters.Add("@c", SqlDbType.VarChar, 16).Value = call1;
                        using (var dr = cmd.ExecuteReader())
                        {
                            while (dr.Read())
                            {
                                var ant = new Antenna();
                                ant.anum = ToInt(dr["anum"]);
                                ant.acode = TObj(dr["acode"]);
                                ant.aht = ToDbl(dr["aht"]);
                                ant.azmth = ToDbl(dr["azmth"]);
                                ant.offazm = TObj(dr["offazm"]);
                                ant.tazmth = ToDbl(dr["tazmth"]);
                                ant.bndcde = TObj(dr["bndcde"]);
                                ant.call2 = TObj(dr["call2"]);
                                ant.txpwr = 0.0;
                                ant.fsl = 999.9;
                                if (ant.offazm == "Y") ant.azmth = ant.tazmth;
                                ants.Add(ant);
                            }
                        }
                    }
                    if (ants.Count == 0) return list;

                    using (var cmd = new SqlCommand(
                        "SELECT call2, bndcde, pwrtx, antnumbtx1, afsltx1, antnumbtx2, afsltx2 FROM " + schema +
                        ".mt_chan WHERE call1=@c AND ISNULL(freqtx, 0.0) > 0.0", cn))
                    {
                        cmd.Parameters.Add("@c", SqlDbType.VarChar, 16).Value = call1;
                        using (var dr = cmd.ExecuteReader())
                        {
                            while (dr.Read())
                            {
                                string call2 = TObj(dr["call2"]);
                                string bnd = TObj(dr["bndcde"]);
                                double pwrtx = ToDbl(dr["pwrtx"]);
                                AddPower(ants, call2, bnd, pwrtx, ToInt(dr["antnumbtx1"]), ToDbl(dr["afsltx1"]));
                                AddPower(ants, call2, bnd, pwrtx, ToInt(dr["antnumbtx2"]), ToDbl(dr["afsltx2"]));
                            }
                        }
                    }
                }
            }
            catch
            {
                return list;
            }

            foreach (Antenna ant in ants)
            {
                list.Add(new
                {
                    acode = ant.acode,
                    aht = ant.aht.ToString("#0.0", CultureInfo.InvariantCulture),
                    azim = ant.azmth.ToString("#0.0", CultureInfo.InvariantCulture),
                    txpwr = (ant.txpwr - 30.0).ToString("#0.0", CultureInfo.InvariantCulture),
                    fsl = ant.fsl.ToString("#0.00", CultureInfo.InvariantCulture)
                });
            }
            return list;
        }

        private static void AddPower(List<Antenna> ants, string call2, string bndcde, double pwrtx, int antnum, double afsl)
        {
            if (antnum == 0 || afsl == 0.0) return;
            for (int i = 0; i < ants.Count; i++)
            {
                if (ants[i].call2 == call2 && ants[i].bndcde == bndcde && ants[i].anum == antnum)
                {
                    if (pwrtx - afsl > ants[i].txpwr - ants[i].fsl)
                    {
                        ants[i].txpwr = pwrtx;
                        ants[i].fsl = afsl;
                    }
                    return;
                }
            }
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
                error = "Database Server failed to update logger.";
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

        private static string Norm(string raw) { return (raw ?? "").Trim(); }
        private static string Dash(string s) { return s.Length == 0 ? "-" : s; }
        private static string T(ArrayList a, int i)
        {
            if (i >= a.Count || a[i] == null) return "";
            return a[i].ToString().Trim();
        }
        private static string TObj(object o)
        {
            return o == null || o == DBNull.Value ? "" : o.ToString().Trim();
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
        private static bool Flag(string raw)
        {
            raw = (raw ?? "").Trim();
            return raw == "1" || raw.Equals("true", StringComparison.OrdinalIgnoreCase)
                || raw.Equals("on", StringComparison.OrdinalIgnoreCase);
        }
        private static double ToDbl(object o)
        {
            double d;
            if (o == null || o == DBNull.Value) return 0;
            if (double.TryParse(o.ToString().Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out d)) return d;
            double.TryParse(o.ToString().Trim(), NumberStyles.Float, CultureInfo.CurrentCulture, out d);
            return d;
        }
        private static int ToInt(object o)
        {
            int n;
            if (o == null || o == DBNull.Value) return 0;
            int.TryParse(o.ToString().Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out n);
            return n;
        }
        private static void WriteJson(HttpResponse response, object obj)
        {
            var ser = new JavaScriptSerializer();
            ser.MaxJsonLength = int.MaxValue;
            response.Write(ser.Serialize(obj));
        }
    }
}
