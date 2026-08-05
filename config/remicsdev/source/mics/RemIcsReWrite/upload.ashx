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

            string userDir = context.Session["user_dir"].ToString();
            string txtPath = Path.Combine(userDir, name + ".txt");
            string tmpPath = Path.Combine(userDir, name + ".tmp");

            try
            {
                Directory.CreateDirectory(userDir);
                file.SaveAs(txtPath);

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
                            lines++;
                        }
                    }
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

        private static void WriteJson(HttpResponse response, object obj)
        {
            response.Write(new JavaScriptSerializer().Serialize(obj));
        }
    }
}
