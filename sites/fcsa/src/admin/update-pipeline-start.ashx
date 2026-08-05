<%@ WebHandler Language="C#" Class="UpdatePipelineStartHandler" %>

using System;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using System.Web;

/// <summary>
/// Start DbUpdate staging pipeline (always runs as fwmda).
/// Query: file={stagingFileName}|fullPath&amp;mode=spoof-first|spoof-only|main-only&amp;retryJobId={guid}
/// </summary>
public class UpdatePipelineStartHandler : IHttpHandler
{
    private const string ScriptPath = @"E:\AIProjects\CentralProject\scripts\Invoke-RemicsUpdatePipeline.ps1";
    private const string WorkDir = @"E:\AIProjects\CentralProject";
    private const string PrimaryRoot = @"D:\updates\primary";
    private static readonly Regex JobIdPattern = new Regex("^[a-fA-F0-9]{32}$", RegexOptions.Compiled);
    private static readonly Regex SafeFilePattern = new Regex(
        @"^([A-Za-z0-9]+_\d{10}_[A-Za-z0-9_.-]{1,64}\.txt|[A-Za-z0-9_]{1,16}\.txt)$",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    public bool IsReusable { get { return false; } }

    public void ProcessRequest(HttpContext context)
    {
        HttpResponse response = context.Response;
        HttpRequest request = context.Request;
        response.ContentType = "application/json; charset=utf-8";
        response.Cache.SetCacheability(HttpCacheability.NoCache);

        try
        {
            string retryJobId = (request.QueryString["retryJobId"] ?? "").Trim();
            string file = (request.QueryString["file"] ?? "").Trim();
            string mode = (request.QueryString["mode"] ?? "spoof-first").Trim().ToLowerInvariant();
            // Legacy spoof=0 => main-only; spoof=1 without mode => spoof-only
            string spoofRaw = (request.QueryString["spoof"] ?? "").Trim();
            if (string.IsNullOrEmpty(request.QueryString["mode"]) && !string.IsNullOrEmpty(spoofRaw))
            {
                mode = (spoofRaw != "0" && !string.Equals(spoofRaw, "false", StringComparison.OrdinalIgnoreCase))
                    ? "spoof-only" : "main-only";
            }

            if (!File.Exists(ScriptPath))
            {
                response.StatusCode = 500;
                response.Write("{\"ok\":false,\"error\":\"Pipeline script not found\"}");
                return;
            }

            string adminDir = Path.GetDirectoryName(context.Request.PhysicalPath);
            if (string.IsNullOrEmpty(adminDir))
                adminDir = @"D:\inetpub\fcsa\admin";

            string jobsDir = Path.Combine(adminDir, "update-pipeline");
            if (!Directory.Exists(jobsDir))
                Directory.CreateDirectory(jobsDir);

            string jobId = JobIdPattern.IsMatch(retryJobId) ? retryJobId : Guid.NewGuid().ToString("N");
            string resultPath = Path.Combine(jobsDir, jobId + ".json");
            string logPath = Path.Combine(jobsDir, jobId + ".log");
            string startedUtc = DateTime.UtcNow.ToString("o");

            string psArgs;
            if (JobIdPattern.IsMatch(retryJobId))
            {
                psArgs = "-File \"" + ScriptPath + "\" -JobId \"" + retryJobId +
                         "\" -ResultPath \"" + resultPath + "\"";
            }
            else
            {
                if (string.IsNullOrEmpty(file))
                {
                    response.StatusCode = 400;
                    response.Write("{\"ok\":false,\"error\":\"Missing file parameter\"}");
                    return;
                }

                string stagingPath = file;
                if (!Path.IsPathRooted(stagingPath))
                {
                    if (!SafeFilePattern.IsMatch(Path.GetFileName(stagingPath)))
                    {
                        response.StatusCode = 400;
                        response.Write("{\"ok\":false,\"error\":\"Invalid staging file name\"}");
                        return;
                    }
                    string tsPath = Path.Combine(PrimaryRoot, Path.GetFileName(stagingPath));
                    string esPath = Path.Combine(PrimaryRoot, "UnprocessedESFiles", Path.GetFileName(stagingPath));
                    if (File.Exists(tsPath)) stagingPath = tsPath;
                    else if (File.Exists(esPath)) stagingPath = esPath;
                    else stagingPath = tsPath;
                }

                if (!File.Exists(stagingPath))
                {
                    response.StatusCode = 404;
                    response.Write("{\"ok\":false,\"error\":\"Staging file not found\"}");
                    return;
                }

                psArgs = "-File \"" + ScriptPath + "\" -StagingFile \"" + stagingPath + "\"" +
                         " -ResultPath \"" + resultPath + "\"";
            }

            if (mode == "main-only") psArgs += " -MainOnly";
            else if (mode == "spoof-only") psArgs += " -SpoofOnly";
            else psArgs += " -SpoofFirst";

            File.WriteAllText(resultPath,
                "{\"ok\":true,\"status\":\"running\",\"jobId\":\"" + jobId +
                "\",\"started_utc\":\"" + startedUtc + "\",\"execution_user\":\"fwmda\"}");

            string inner = "powershell.exe -NoProfile -ExecutionPolicy Bypass " + psArgs +
                           " > \"" + logPath + "\" 2>&1";
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "cmd.exe";
            psi.Arguments = "/c start \"fcsa-update-pipeline-" + jobId.Substring(0, 8) + "\" /b " + inner;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WorkingDirectory = WorkDir;

            using (Process p = Process.Start(psi))
            {
                if (p == null)
                {
                    File.WriteAllText(resultPath,
                        "{\"ok\":false,\"status\":\"complete\",\"error\":\"Failed to start worker\"}");
                    response.StatusCode = 500;
                    response.Write("{\"ok\":false,\"error\":\"Failed to start worker\"}");
                    return;
                }
                p.WaitForExit(5000);
            }

            System.Threading.Thread.Sleep(400);
            response.StatusCode = 200;
            response.Write("{\"ok\":true,\"jobId\":\"" + jobId +
                           "\",\"status\":\"running\",\"execution_user\":\"fwmda\",\"started_utc\":\"" + startedUtc + "\"}");
        }
        catch (Exception ex)
        {
            response.StatusCode = 500;
            response.Write("{\"ok\":false,\"error\":" + HttpUtility.JavaScriptStringEncode(ex.Message, true) + "}");
        }
    }
}
