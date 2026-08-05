<%@ WebHandler Language="C#" Class="RewriteSmokeStartHandler" %>

using System;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using System.Web;

/// <summary>
/// FCSA admin: start RemIcsReWrite feature smoke (ashx/views/dual-drive validate).
/// Query: user=rctl1|rctl3|xci1|dnd1&amp;fixture=cat&amp;skipValidate=0|1
/// Poll: /admin/fileop-status.ashx?jobId= (shared jobs folder)
/// </summary>
public class RewriteSmokeStartHandler : IHttpHandler
{
    private const string ScriptPath = @"E:\AIProjects\CentralProject\scripts\Invoke-RemicsReWriteFeatureSmoke.ps1";
    private const string WorkDir = @"E:\AIProjects\CentralProject";
    private static readonly Regex UserPattern = new Regex("^(rctl1|rctl3|xci1|dnd1)$", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex FixturePattern = new Regex("^[A-Za-z0-9_]{0,32}$", RegexOptions.Compiled);

    public bool IsReusable { get { return false; } }

    public void ProcessRequest(HttpContext context)
    {
        HttpResponse response = context.Response;
        HttpRequest request = context.Request;
        response.ContentType = "application/json; charset=utf-8";
        response.Cache.SetCacheability(HttpCacheability.NoCache);

        try
        {
            string user = (request.QueryString["user"] ?? "rctl1").Trim().ToLowerInvariant();
            string fixture = (request.QueryString["fixture"] ?? "cat").Trim();
            string skipVal = (request.QueryString["skipValidate"] ?? "0").Trim();

            if (!UserPattern.IsMatch(user))
            {
                response.StatusCode = 400;
                response.Write("{\"ok\":false,\"error\":\"Invalid user\"}");
                return;
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

            if (!File.Exists(ScriptPath))
            {
                response.StatusCode = 500;
                response.Write("{\"ok\":false,\"error\":\"Feature smoke script not found\"}");
                return;
            }

            string jobId = Guid.NewGuid().ToString("N");
            string resultPath = Path.Combine(jobsDir, jobId + ".json");
            string logPath = Path.Combine(jobsDir, jobId + ".log");
            string startedUtc = DateTime.UtcNow.ToString("o");

            string runningJson = "{\"ok\":true,\"status\":\"running\",\"jobId\":\"" + jobId +
                                 "\",\"op\":\"rewrite-feature-smoke\",\"user\":\"" + user +
                                 "\",\"fixture\":\"" + fixture +
                                 "\",\"started_utc\":\"" + startedUtc + "\"}";
            File.WriteAllText(resultPath, runningJson);

            string skipFlag = (skipVal == "1" || string.Equals(skipVal, "true", StringComparison.OrdinalIgnoreCase))
                ? " -SkipValidate" : "";

            string inner = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"" + ScriptPath +
                           "\" -User \"" + user + "\" -ValidateFixture \"" + fixture + "\"" + skipFlag +
                           " -Json -ResultPath \"" + resultPath +
                           "\" > \"" + logPath + "\" 2>&1";

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "cmd.exe";
            psi.Arguments = "/c start \"fcsa-rewrite-smoke-" + jobId.Substring(0, 8) + "\" /b " + inner;
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
                           "\",\"status\":\"running\",\"op\":\"rewrite-feature-smoke\",\"user\":\"" + user +
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
