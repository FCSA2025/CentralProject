<%@ WebHandler Language="C#" Class="UpdatePipelineStatusHandler" %>

using System;
using System.IO;
using System.Text.RegularExpressions;
using System.Web;

/// <summary>
/// Poll DbUpdate pipeline job JSON under admin/update-pipeline/.
/// </summary>
public class UpdatePipelineStatusHandler : IHttpHandler
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

            string resultPath = Path.Combine(adminDir, "update-pipeline", jobId + ".json");
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
                response.Write("{\"ok\":true,\"status\":\"running\",\"jobId\":\"" + jobId + "\"}");
                return;
            }

            if (json.IndexOf("\"jobId\"", StringComparison.OrdinalIgnoreCase) < 0 &&
                json.IndexOf("\"job_id\"", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                json = json.Replace("\"job_id\"", "\"jobId\"");
            }
            if (json.IndexOf("\"status\"", StringComparison.OrdinalIgnoreCase) < 0 &&
                json.StartsWith("{"))
            {
                json = json.Substring(0, 1) + "\"status\":\"complete\"," + json.Substring(1);
            }

            response.Write(json);
        }
        catch (Exception ex)
        {
            response.StatusCode = 500;
            response.Write("{\"ok\":false,\"error\":" + HttpUtility.JavaScriptStringEncode(ex.Message, true) + "}");
        }
    }
}
