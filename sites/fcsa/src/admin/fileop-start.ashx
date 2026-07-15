<%@ WebHandler Language="C#" Class="FileOpStartHandler" %>

using System;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using System.Web;

/// <summary>
/// Same-origin FCSA admin: start print/import/validate/roundtrip job and return jobId.
/// Query: op=print|import|validate|roundtrip&amp;fixture=cat|ecomm2602|ecomm2601b
/// </summary>
public class FileOpStartHandler : IHttpHandler
{
    private const string ScriptPath = @"E:\AIProjects\CentralProject\scripts\Invoke-MicsFileOpCompare.ps1";
    private const string WorkDir = @"E:\AIProjects\CentralProject";
    private static readonly Regex OpPattern = new Regex("^(print|import|validate|roundtrip)$", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex FixturePattern = new Regex("^[A-Za-z0-9_]{1,32}$", RegexOptions.Compiled);

    public bool IsReusable { get { return false; } }

    public void ProcessRequest(HttpContext context)
    {
        HttpResponse response = context.Response;
        HttpRequest request = context.Request;
        response.ContentType = "application/json; charset=utf-8";
        response.Cache.SetCacheability(HttpCacheability.NoCache);

        try
        {
            string op = (request.QueryString["op"] ?? "").Trim().ToLowerInvariant();
            string fixture = (request.QueryString["fixture"] ?? "").Trim();
            if (!OpPattern.IsMatch(op))
            {
                response.StatusCode = 400;
                response.Write("{\"ok\":false,\"error\":\"Invalid or missing op (print|import|validate|roundtrip)\"}");
                return;
            }
            if (string.IsNullOrEmpty(fixture))
            {
                // Defaults match baselines.yaml
                if (op == "validate") fixture = "cat";
                else fixture = "ecomm2602";
            }
            if (!FixturePattern.IsMatch(fixture))
            {
                response.StatusCode = 400;
                response.Write("{\"ok\":false,\"error\":\"Invalid fixture\"}");
                return;
            }

            string adminDir = Path.GetDirectoryName(context.Request.PhysicalPath);
            if (string.IsNullOrEmpty(adminDir))
                adminDir = @"D:\inetpub\fcsa\admin";

            string jobsDir = Path.Combine(adminDir, "jobs");
            if (!Directory.Exists(jobsDir))
                Directory.CreateDirectory(jobsDir);

            string fileOpsDir = Path.Combine(adminDir, "file-ops");
            if (!Directory.Exists(fileOpsDir))
                Directory.CreateDirectory(fileOpsDir);

            if (!File.Exists(ScriptPath))
            {
                response.StatusCode = 500;
                response.Write("{\"ok\":false,\"error\":\"File-op script not found\"}");
                return;
            }

            string jobId = Guid.NewGuid().ToString("N");
            string resultPath = Path.Combine(jobsDir, jobId + ".json");
            string logPath = Path.Combine(jobsDir, jobId + ".log");
            string startedUtc = DateTime.UtcNow.ToString("o");

            string runningJson = "{\"ok\":true,\"status\":\"running\",\"jobId\":\"" + jobId +
                                 "\",\"op\":\"" + op + "\",\"fixture\":\"" + fixture +
                                 "\",\"started_utc\":\"" + startedUtc + "\"}";
            File.WriteAllText(resultPath, runningJson);

            string inner = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"" + ScriptPath +
                           "\" -Op " + op + " -Fixture \"" + fixture +
                           "\" -Json -TimeoutSec 180 -ResultPath \"" + resultPath +
                           "\" > \"" + logPath + "\" 2>&1";
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "cmd.exe";
            psi.Arguments = "/c start \"fcsa-fileop-" + jobId.Substring(0, 8) + "\" /b " + inner;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WorkingDirectory = WorkDir;

            using (Process p = Process.Start(psi))
            {
                if (p == null)
                {
                    File.WriteAllText(resultPath,
                        "{\"ok\":false,\"status\":\"complete\",\"error\":\"Failed to start cmd/powershell\"}");
                    response.StatusCode = 500;
                    response.Write("{\"ok\":false,\"error\":\"Failed to start worker\"}");
                    return;
                }
                p.WaitForExit(5000);
            }

            System.Threading.Thread.Sleep(400);
            string early = File.ReadAllText(resultPath);
            if (early.IndexOf("\"status\":\"complete\"", StringComparison.OrdinalIgnoreCase) >= 0 &&
                early.IndexOf("\"ok\":false", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                response.StatusCode = 500;
                response.Write(early);
                return;
            }

            response.StatusCode = 200;
            response.Write("{\"ok\":true,\"jobId\":\"" + jobId +
                           "\",\"status\":\"running\",\"op\":\"" + op +
                           "\",\"fixture\":\"" + fixture +
                           "\",\"started_utc\":\"" + startedUtc + "\"}");
        }
        catch (Exception ex)
        {
            response.StatusCode = 500;
            response.Write("{\"ok\":false,\"error\":" + HttpUtility.JavaScriptStringEncode(ex.Message, true) + "}");
        }
    }
}
