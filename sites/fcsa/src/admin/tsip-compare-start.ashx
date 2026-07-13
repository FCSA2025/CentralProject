<%@ WebHandler Language="C#" Class="TsipCompareStartHandler" %>

using System;
using System.Diagnostics;
using System.IO;
using System.Web;

/// <summary>
/// Same-origin FCSA admin: start last-TSIP compare in the background and return jobId immediately.
/// Browser path: /admin/tsip-compare-start.ashx (no CORS).
/// </summary>
public class TsipCompareStartHandler : IHttpHandler
{
    private const string ScriptPath = @"E:\AIProjects\CentralProject\scripts\Invoke-LastTsipCompare.ps1";
    private const string WorkDir = @"E:\AIProjects\CentralProject";

    public bool IsReusable { get { return false; } }

    public void ProcessRequest(HttpContext context)
    {
        HttpResponse response = context.Response;
        response.ContentType = "application/json; charset=utf-8";
        response.Cache.SetCacheability(HttpCacheability.NoCache);

        try
        {
            string adminDir = Path.GetDirectoryName(context.Request.PhysicalPath);
            if (string.IsNullOrEmpty(adminDir))
                adminDir = @"D:\inetpub\fcsa\admin";

            string jobsDir = Path.Combine(adminDir, "jobs");
            if (!Directory.Exists(jobsDir))
                Directory.CreateDirectory(jobsDir);

            if (!File.Exists(ScriptPath))
            {
                response.StatusCode = 500;
                response.Write("{\"ok\":false,\"error\":\"Compare script not found\"}");
                return;
            }

            string jobId = Guid.NewGuid().ToString("N");
            string resultPath = Path.Combine(jobsDir, jobId + ".json");
            string logPath = Path.Combine(jobsDir, jobId + ".log");
            string startedUtc = DateTime.UtcNow.ToString("o");

            string runningJson = "{\"ok\":true,\"status\":\"running\",\"jobId\":\"" + jobId +
                                 "\",\"started_utc\":\"" + startedUtc + "\"}";
            File.WriteAllText(resultPath, runningJson);

            // Detach via cmd "start /b" so the worker survives after this request returns.
            // Redirect stdout/stderr to a log for diagnosis.
            string inner = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"" + ScriptPath +
                           "\" -Json -TimeoutSec 240 -ResultPath \"" + resultPath + "\" > \"" + logPath + "\" 2>&1";
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "cmd.exe";
            psi.Arguments = "/c start \"fcsa-tsip-" + jobId.Substring(0, 8) + "\" /b " + inner;
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

            // Give the worker a moment; if result already failed, surface it.
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
                           "\",\"status\":\"running\",\"started_utc\":\"" + startedUtc + "\"}");
        }
        catch (Exception ex)
        {
            response.StatusCode = 500;
            response.Write("{\"ok\":false,\"error\":" + HttpUtility.JavaScriptStringEncode(ex.Message, true) + "}");
        }
    }
}
