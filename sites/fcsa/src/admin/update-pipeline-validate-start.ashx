<%@ WebHandler Language="C#" Class="UpdatePipelineValidateStartHandler" %>

using System;
using System.Diagnostics;
using System.IO;
using System.Web;

/// <summary>
/// Start batch import+validate for all DbUpdate staging inbox files (fwmda).
/// </summary>
public class UpdatePipelineValidateStartHandler : IHttpHandler
{
    private const string ScriptPath = @"E:\AIProjects\CentralProject\scripts\Invoke-RemicsUpdateValidateAll.ps1";
    private const string WorkDir = @"E:\AIProjects\CentralProject";

    public bool IsReusable { get { return false; } }

    public void ProcessRequest(HttpContext context)
    {
        HttpResponse response = context.Response;
        response.ContentType = "application/json; charset=utf-8";
        response.Cache.SetCacheability(HttpCacheability.NoCache);

        try
        {
            if (!File.Exists(ScriptPath))
            {
                response.StatusCode = 500;
                response.Write("{\"ok\":false,\"error\":\"Validate-all script not found\"}");
                return;
            }

            string adminDir = Path.GetDirectoryName(context.Request.PhysicalPath);
            if (string.IsNullOrEmpty(adminDir))
                adminDir = @"D:\inetpub\fcsa\admin";

            string jobsDir = Path.Combine(adminDir, "update-pipeline");
            if (!Directory.Exists(jobsDir))
                Directory.CreateDirectory(jobsDir);

            string jobId = Guid.NewGuid().ToString("N");
            string resultPath = Path.Combine(jobsDir, jobId + ".json");
            string cachePath = Path.Combine(jobsDir, "validate-cache.json");
            string logPath = Path.Combine(jobsDir, jobId + ".log");
            string startedUtc = DateTime.UtcNow.ToString("o");

            File.WriteAllText(resultPath,
                "{\"ok\":true,\"status\":\"running\",\"jobId\":\"" + jobId +
                "\",\"type\":\"validate_all\",\"started_utc\":\"" + startedUtc + "\"}");

            string psArgs = "-File \"" + ScriptPath + "\" -ResultPath \"" + resultPath +
                            "\" -CachePath \"" + cachePath + "\"";
            string inner = "powershell.exe -NoProfile -ExecutionPolicy Bypass " + psArgs +
                           " > \"" + logPath + "\" 2>&1";

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "cmd.exe";
            psi.Arguments = "/c start \"fcsa-validate-all-" + jobId.Substring(0, 8) + "\" /b " + inner;
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
                           "\",\"status\":\"running\",\"type\":\"validate_all\",\"started_utc\":\"" + startedUtc + "\"}");
        }
        catch (Exception ex)
        {
            response.StatusCode = 500;
            response.Write("{\"ok\":false,\"error\":" + HttpUtility.JavaScriptStringEncode(ex.Message, true) + "}");
        }
    }
}
