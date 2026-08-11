<%@ WebHandler Language="C#" Class="UpdatePipelineMoveFailedHandler" %>

using System;
using System.IO;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;

/// <summary>
/// Move a staging inbox file into errors/{jobId}/ without running the pipeline.
/// Query: file={stagingFileName}
/// </summary>
public class UpdatePipelineMoveFailedHandler : IHttpHandler
{
    private const string PrimaryRoot = @"D:\updates\primary";
    private static readonly Regex SafeFilePattern = new Regex(
        @"^([A-Za-z0-9]+_\d{10}_[A-Za-z0-9_.-]{1,64}\.txt|[A-Za-z0-9_]{1,16}\.txt)$",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    public bool IsReusable { get { return false; } }

    public void ProcessRequest(HttpContext context)
    {
        var response = context.Response;
        var request = context.Request;
        response.ContentType = "application/json; charset=utf-8";
        response.Cache.SetCacheability(HttpCacheability.NoCache);

        try
        {
            string file = (request.QueryString["file"] ?? "").Trim();
            if (string.IsNullOrEmpty(file))
            {
                response.StatusCode = 400;
                response.Write("{\"ok\":false,\"error\":\"Missing file parameter\"}");
                return;
            }

            string fileName = Path.GetFileName(file);
            if (!SafeFilePattern.IsMatch(fileName))
            {
                response.StatusCode = 400;
                response.Write("{\"ok\":false,\"error\":\"Invalid staging file name\"}");
                return;
            }

            string tsPath = Path.Combine(PrimaryRoot, fileName);
            string esPath = Path.Combine(PrimaryRoot, "UnprocessedESFiles", fileName);
            string sourcePath = null;
            string filetype = null;
            if (File.Exists(tsPath))
            {
                sourcePath = tsPath;
                filetype = "TS";
            }
            else if (File.Exists(esPath))
            {
                sourcePath = esPath;
                filetype = "ES";
            }

            if (sourcePath == null)
            {
                response.StatusCode = 404;
                response.Write("{\"ok\":false,\"error\":\"Staging file not found in inbox\"}");
                return;
            }

            string errorsRoot = Path.Combine(PrimaryRoot, "errors");
            if (!Directory.Exists(errorsRoot))
                Directory.CreateDirectory(errorsRoot);

            string jobId = Guid.NewGuid().ToString("N");
            string destDir = Path.Combine(errorsRoot, jobId);
            Directory.CreateDirectory(destDir);
            string destPath = Path.Combine(destDir, fileName);
            File.Move(sourcePath, destPath);

            var payload = new
            {
                ok = true,
                job_id = jobId,
                file = fileName,
                filetype = filetype,
                source_path = sourcePath,
                dest_path = destPath,
                errors_dir = destDir,
                failed_dir = destDir,
                moved_utc = DateTime.UtcNow.ToString("o")
            };
            response.Write(new JavaScriptSerializer().Serialize(payload));
        }
        catch (Exception ex)
        {
            response.StatusCode = 500;
            response.Write(new JavaScriptSerializer().Serialize(new { ok = false, error = ex.Message }));
        }
    }
}
