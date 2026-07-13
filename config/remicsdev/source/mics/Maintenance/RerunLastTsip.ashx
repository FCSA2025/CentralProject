<%@ WebHandler Language="C#" Class="RerunLastTsipHandler" %>

using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Web;

public class RerunLastTsipHandler : IHttpHandler
{
    // Temporary testing endpoint — prefer FCSA same-origin handlers:
    //   http://localhost/admin/tsip-compare-start.ashx
    //   http://localhost/admin/tsip-compare-status.ashx
    // This remicsdev ashx remains for CLI/curl debugging (sync wait).
    private const string ExpectedKeyEnv = "FCSA_TSIP_TEST_KEY";
    private const string DefaultKey = "fcsa-local-tsip-test";

    public bool IsReusable { get { return false; } }

    public void ProcessRequest(HttpContext context)
    {
        HttpResponse response = context.Response;
        HttpRequest request = context.Request;
        response.ContentType = "application/json; charset=utf-8";
        response.AddHeader("Access-Control-Allow-Origin", "*");
        response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        response.AddHeader("Access-Control-Allow-Headers", "Content-Type, X-Fcsa-Test-Key");

        if (string.Equals(request.HttpMethod, "OPTIONS", StringComparison.OrdinalIgnoreCase))
        {
            response.StatusCode = 204;
            return;
        }

        string remote = request.UserHostAddress ?? "";
        bool local =
            remote == "127.0.0.1" ||
            remote == "::1" ||
            remote.StartsWith("192.168.") ||
            remote.StartsWith("10.") ||
            string.Equals(remote, context.Request.ServerVariables["LOCAL_ADDR"], StringComparison.OrdinalIgnoreCase);

        // Also allow same-machine browser hits that show as the public/private NIC.
        string host = (request.Url.Host ?? "").ToLowerInvariant();
        bool hostOk = host == "localhost" || host == "127.0.0.1" || host.Contains("cloudmicsdev") || host == "remicsdev";

        string key = request.Headers["X-Fcsa-Test-Key"];
        if (string.IsNullOrEmpty(key)) key = request.QueryString["key"];
        string expected = Environment.GetEnvironmentVariable(ExpectedKeyEnv);
        if (string.IsNullOrEmpty(expected)) expected = DefaultKey;

        if (!local && !hostOk)
        {
            response.StatusCode = 403;
            response.Write("{\"ok\":false,\"error\":\"Forbidden: local/server use only\"}");
            return;
        }
        if (!string.Equals(key, expected, StringComparison.Ordinal))
        {
            response.StatusCode = 403;
            response.Write("{\"ok\":false,\"error\":\"Forbidden: missing or invalid test key\"}");
            return;
        }

        string script = @"E:\AIProjects\CentralProject\scripts\Invoke-LastTsipCompare.ps1";
        if (!File.Exists(script))
        {
            response.StatusCode = 500;
            response.Write("{\"ok\":false,\"error\":\"Compare script not found\"}");
            return;
        }

        try
        {
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -Json -TimeoutSec 240";
            psi.UseShellExecute = false;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.CreateNoWindow = true;
            psi.WorkingDirectory = @"E:\AIProjects\CentralProject";

            using (Process p = Process.Start(psi))
            {
                // TSIP can take 1–3 minutes
                string stdout = p.StandardOutput.ReadToEnd();
                string stderr = p.StandardError.ReadToEnd();
                p.WaitForExit(300000);

                if (p.ExitCode != 0 && string.IsNullOrWhiteSpace(stdout))
                {
                    response.StatusCode = 500;
                    response.Write("{\"ok\":false,\"error\":\"Script failed\",\"exit_code\":" + p.ExitCode +
                                   ",\"stderr\":" + HttpUtility.JavaScriptStringEncode(stderr, true) + "}");
                    return;
                }

                string json = stdout.Trim();
                // Prefer the first complete JSON object line
                string chosen = null;
                foreach (string line in stdout.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    string t = line.Trim();
                    if (t.StartsWith("{") && t.EndsWith("}"))
                    {
                        chosen = t;
                        break;
                    }
                }
                if (chosen == null)
                {
                    int firstBrace = json.IndexOf('{');
                    int lastBrace = json.LastIndexOf('}');
                    if (firstBrace >= 0 && lastBrace > firstBrace)
                        chosen = json.Substring(firstBrace, lastBrace - firstBrace + 1);
                    else
                        chosen = json;
                }

                response.StatusCode = (p.ExitCode == 0) ? 200 : 500;
                response.Write(string.IsNullOrWhiteSpace(chosen)
                    ? "{\"ok\":false,\"error\":\"Empty script output\",\"stderr\":" + HttpUtility.JavaScriptStringEncode(stderr, true) + "}"
                    : chosen);
            }
        }
        catch (Exception ex)
        {
            response.StatusCode = 500;
            response.Write("{\"ok\":false,\"error\":" + HttpUtility.JavaScriptStringEncode(ex.Message, true) + "}");
        }
    }
}
