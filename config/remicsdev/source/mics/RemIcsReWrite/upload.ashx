<%@ WebHandler Language="C#" Class="RemIcsReWrite.UploadHandler" %>

using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;

namespace RemIcsReWrite
{
    public class UploadHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly Regex ValidName = new Regex(@"^[A-Za-z0-9_]{1,16}$", RegexOptions.Compiled);

        public bool IsReusable { get { return false; } }

        public void ProcessRequest(HttpContext context)
        {
            var response = context.Response;
            var request = context.Request;
            response.ContentType = "application/json; charset=utf-8";
            response.Cache.SetCacheability(HttpCacheability.NoCache);

            if (context.User == null || context.User.Identity == null || !context.User.Identity.IsAuthenticated
                || context.Session == null || context.Session["user_dir"] == null)
            {
                response.StatusCode = 401;
                WriteJson(response, new { ok = false, error = "Not authenticated or session not initialized." });
                return;
            }

            if (!string.Equals(request.HttpMethod, "POST", StringComparison.OrdinalIgnoreCase))
            {
                response.StatusCode = 405;
                WriteJson(response, new { ok = false, error = "POST required." });
                return;
            }

            string name = (request.Form["name"] ?? "").Trim();
            if (!ValidName.IsMatch(name))
            {
                response.StatusCode = 400;
                WriteJson(response, new { ok = false, error = "Invalid target name." });
                return;
            }

            HttpPostedFile file = request.Files["file"];
            if (file == null || file.ContentLength == 0)
            {
                response.StatusCode = 400;
                WriteJson(response, new { ok = false, error = "No file uploaded." });
                return;
            }

            string filetype = (request.Form["filetype"] ?? "").Trim().ToUpperInvariant();
            if (filetype != "TS" && filetype != "ES") filetype = "";

            string userDir = context.Session["user_dir"].ToString();
            string txtPath = Path.Combine(userDir, name + ".txt");
            string tmpPath = Path.Combine(userDir, name + ".tmp");

            try
            {
                Directory.CreateDirectory(userDir);
                file.SaveAs(txtPath);

                var keys = new KeyCheck();
                int lines = 0;
                using (var sr = new StreamReader(txtPath, Encoding.Default))
                using (var sw = new StreamWriter(tmpPath, false, Encoding.Default))
                {
                    string line;
                    while ((line = sr.ReadLine()) != null)
                    {
                        if (line.Trim().Length >= 1)
                        {
                            sw.WriteLine(line);
                            if (filetype == "TS" || filetype == "ES")
                                keys.AddLine(filetype, line);
                            lines++;
                        }
                    }
                }

                string missingAnte, missingAzim, missingChan;
                if ((filetype == "TS" || filetype == "ES")
                    && keys.HasMissing(filetype, out missingAnte, out missingAzim, out missingChan))
                {
                    try { if (File.Exists(tmpPath)) File.Delete(tmpPath); } catch { }
                    response.StatusCode = 400;
                    WriteJson(response, new
                    {
                        ok = false,
                        code = "MISSING",
                        missingAnte = missingAnte,
                        missingAzim = missingAzim,
                        missingChan = missingChan,
                        error = "Import cancelled: antenna, azimuth, or channel keys have no matching site."
                    });
                    return;
                }

                var fi = new FileInfo(tmpPath);
                WriteJson(response, new
                {
                    ok = true,
                    path = tmpPath,
                    bytes = fi.Exists ? fi.Length : 0,
                    lines = lines
                });
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        /// <summary>Classic import.aspx.cs load_keys / check_keys (SK/AK/CK, ES ZK).</summary>
        private class KeyCheck
        {
            private readonly StringBuilder _sites = new StringBuilder();
            private readonly StringBuilder _antes = new StringBuilder();
            private readonly StringBuilder _chans = new StringBuilder();
            private readonly StringBuilder _azims = new StringBuilder();

            public void AddLine(string filetype, string line)
            {
                string[] p = line.Split(',');
                if (p.Length == 0) return;
                string rec = p[0];
                if (rec == "SK")
                    _sites.Append(p.Length >= 4 ? p[3] + "," : ",");
                else if (rec == "AK")
                    _antes.Append(p.Length >= 4 ? p[3] + "," : ",");
                else if (rec == "CK")
                    _chans.Append(p.Length >= 4 ? p[3] + "," : ",");
                else if (filetype == "ES" && rec == "ZK")
                    _azims.Append(p.Length >= 5 ? p[4] + "," : ",");
            }

            public bool HasMissing(string filetype, out string ante, out string azim, out string chan)
            {
                string sites = _sites.ToString();
                ante = Missing(sites, _antes);
                azim = filetype == "ES" ? Missing(sites, _azims) : "";
                chan = Missing(sites, _chans);
                string packed = filetype == "TS"
                    ? ante + "^^" + chan
                    : ante + "^" + azim + "^" + chan;
                return packed.Length > 2;
            }

            private static string Missing(string siteCsv, StringBuilder refs)
            {
                var bad = new StringBuilder();
                string[] keys = refs.ToString().Split(',');
                if (keys.Length == 0) return "";
                Array.Sort(keys);
                for (int i = 1; i < keys.Length; i++)
                {
                    if (siteCsv.IndexOf(keys[i], StringComparison.Ordinal) < 0)
                        bad.Append(keys[i] + ",");
                }
                return bad.ToString();
            }
        }

        private static void WriteJson(HttpResponse response, object obj)
        {
            response.Write(new JavaScriptSerializer().Serialize(obj));
        }
    }
}
