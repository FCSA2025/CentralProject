<%@ WebHandler Language="C#" Class="RemIcsReWrite.AuxCoordHandler" %>

using System;
using System.Collections.Generic;
using System.Data.Odbc;
using System.Globalization;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>Coordination Zone Check  -  parity with auxengmenu/AUXCoordChk1.</summary>
    public class AuxCoordHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly Regex NameOk = new Regex(@"^[A-Za-z0-9_]{1,16}$", RegexOptions.Compiled);

        public bool IsReusable { get { return false; } }

        public void ProcessRequest(HttpContext context)
        {
            var response = context.Response;
            response.ContentType = "application/json; charset=utf-8";
            response.Cache.SetCacheability(HttpCacheability.NoCache);

            if (context.Session == null || context.Session["s_cnString"] == null
                || context.Session["s_schema"] == null || context.Session["s_user"] == null)
            {
                response.StatusCode = 401;
                WriteJson(response, new { ok = false, error = "Session not initialized." });
                return;
            }

            try
            {
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(context.Session["principalw"]))
                {
                    HandleCheck(context);
                }
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        private static void HandleCheck(HttpContext context)
        {
            SesUtils.LogMenuUse("AUXCoordCheck");

            string filetype = (context.Request["filetype"] ?? "").Trim().ToUpperInvariant();
            string name = (context.Request["name"] ?? "").Trim();
            if (filetype != "TS" && filetype != "ES")
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Must chose one of the TS or ES pdfs" });
                return;
            }
            if (!NameOk.IsMatch(name))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Invalid file name." });
                return;
            }

            string schema = context.Session["s_schema"].ToString().Trim();
            if (!Regex.IsMatch(schema, @"^[A-Za-z][A-Za-z0-9_]*$"))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Invalid schema." });
                return;
            }

            bool isTs = filetype == "TS";
            string siteTable = schema + "." + (isTs ? "ft_" : "fe_") + name + "_site";
            string callCol = isTs ? "call1" : "location";
            string sql = "select " + callCol + " as call, name, latit, longit from " + siteTable +
                " where cmd != 'D' order by call";

            var rows = new List<object>();
            try
            {
                using (var cn = new OdbcConnection(context.Session["s_cnString"].ToString()))
                {
                    cn.Open();
                    using (var cmd = new OdbcCommand(sql, cn))
                    using (var dr = cmd.ExecuteReader())
                    {
                        while (dr.Read())
                        {
                            int lat = Convert.ToInt32(dr["latit"]);
                            int lng = Convert.ToInt32(dr["longit"]);
                            rows.Add(new
                            {
                                call = dr["call"] == DBNull.Value ? "" : dr["call"].ToString().Trim(),
                                name = dr["name"] == DBNull.Value ? "" : dr["name"].ToString().Trim(),
                                lat = DisplayLl(lat, 0),
                                lng = DisplayLl(lng, 1),
                                requiresCoord = CheckCoord(lat, lng)
                            });
                        }
                    }
                }
            }
            catch (OdbcException)
            {
                // Foreign or missing PDF — no site table in this schema.
                rows.Clear();
            }

            WriteJson(context.Response, new
            {
                ok = true,
                empty = rows.Count == 0,
                message = rows.Count == 0 ? "There are no sites in this file." : "",
                rows = rows
            });
        }

        private static string DisplayLl(double dSeconds, int nLat0Lng1)
        {
            string cSense;
            double dDegrees = dSeconds / 360000.0;
            if (dDegrees >= 0)
                cSense = (nLat0Lng1 == 0) ? "N" : "W";
            else
            {
                cSense = (nLat0Lng1 == 0) ? "S" : "E";
                dDegrees = -dDegrees;
            }
            double dDeg = Math.Floor(dDegrees);
            dDegrees = (dDegrees - dDeg) * 60.0;
            double dMin = Math.Floor(dDegrees);
            double dSec = ((dDegrees - dMin) * 60.0);
            if (dSec > 59.99) { dSec = 0; dMin++; }
            if (dMin > 59) { dMin = 0; dDeg++; }
            string cSec = dSec.ToString("00.00", CultureInfo.InvariantCulture);
            return dDeg.ToString("##0") + "-" +
                Math.Floor(dMin / 10.0).ToString("0") +
                ((dMin % 10).ToString("0") + "-") +
                cSec + cSense;
        }

        private static bool CheckCoord(int lat, int lng)
        {
            const int NZONES = 6;
            int[,] zoneDat = new int[,] {
                {226800, 262800, 180000, 0},
                {262800, 288000, 172800, 0},
                {288000, 316800, 176400, 0},
                {316800, 457200, 183600, 0},
                {450000, 486000, 219600, 190800},
                {486000, 507600, 259200, 208800}
            };
            lat /= 100;
            lng /= 100;
            for (int zone = 0; zone < NZONES; zone++)
            {
                if (lng >= zoneDat[zone, 0] && lng <= zoneDat[zone, 1] &&
                    lat <= zoneDat[zone, 2] && lat >= zoneDat[zone, 3])
                    return true;
            }
            return false;
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            response.Write(new JavaScriptSerializer().Serialize(obj));
        }
    }
}
