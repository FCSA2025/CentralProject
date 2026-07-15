<%@ WebHandler Language="C#" Class="FileOpStatusHandler" %>

using System;
using System.IO;
using System.Text.RegularExpressions;
using System.Web;

/// <summary>
/// Same-origin FCSA admin: poll job status for file-op or TSIP jobs (shared jobs folder).
/// </summary>
public class FileOpStatusHandler : IHttpHandler
{
    private static readonly Regex JobIdPattern = new Regex("^[a-fA-F0-9]{32}$", RegexOptions.Compiled);

    public bool IsReusable { get { return false; } }

    public void ProcessRequest(HttpContext context)
    {
        HttpResponse response = context.Response;
        HttpRequest request = context.Request;
        response.ContentType = "application/json; charset=utf-8";
        response.Cache.SetCacheability(HttpCacheability.NoCache);

        string jobId = request.QueryString["jobId"] ?? "";
        if (!JobIdPattern.IsMatch(jobId))
        {
            response.StatusCode = 400;
            response.Write("{\"ok\":false,\"error\":\"Invalid or missing jobId\"}");
            return;
        }

        try
        {
            string adminDir = Path.GetDirectoryName(context.Request.PhysicalPath);
            if (string.IsNullOrEmpty(adminDir))
                adminDir = @"D:\inetpub\fcsa\admin";

            string resultPath = Path.Combine(adminDir, "jobs", jobId + ".json");
            if (!File.Exists(resultPath))
            {
                response.StatusCode = 404;
                response.Write("{\"ok\":false,\"status\":\"unknown\",\"error\":\"Unknown jobId\"}");
                return;
            }

            string json;
            using (FileStream fs = new FileStream(resultPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (StreamReader sr = new StreamReader(fs))
            {
                json = sr.ReadToEnd().Trim();
            }

            if (string.IsNullOrEmpty(json))
            {
                response.StatusCode = 200;
                response.Write("{\"ok\":true,\"status\":\"running\",\"jobId\":\"" + jobId + "\"}");
                return;
            }

            if (json.IndexOf("\"status\"", StringComparison.OrdinalIgnoreCase) < 0)
            {
                if (json.StartsWith("{"))
                    json = json.Substring(0, 1) + "\"status\":\"complete\"," + json.Substring(1);
            }

            response.StatusCode = 200;
            response.Write(json);
        }
        catch (Exception ex)
        {
            response.StatusCode = 500;
            response.Write("{\"ok\":false,\"error\":" + HttpUtility.JavaScriptStringEncode(ex.Message, true) + "}");
        }
    }
}
