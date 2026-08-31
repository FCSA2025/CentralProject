<%@ WebHandler Language="C#" Class="LookupJsHandler" %>

using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;
using System.Web;

/// <summary>
/// Serves classic lookup *.js SSI fragments as plain JavaScript (script wrappers stripped).
/// </summary>
public class LookupJsHandler : IHttpHandler
{
    static readonly Dictionary<string, string> Files = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        { "lookupfcns", "lookupfcns.js" },
        { "lookuped", "lookuped.js" },
        { "lookuptsip", "../lookuptsip/lookuptsip.js" }
    };

    public bool IsReusable { get { return true; } }

    public void ProcessRequest(HttpContext context)
    {
        var response = context.Response;
        var request = context.Request;
        var key = (request.QueryString["f"] ?? "").Trim();

        string relative;
        if (!Files.TryGetValue(key, out relative))
        {
            response.StatusCode = 404;
            response.ContentType = "text/plain";
            response.Write("Unknown lookup script: " + key);
            return;
        }

        var baseDir = Path.GetDirectoryName(request.PhysicalPath) ?? "";
        var fullPath = Path.GetFullPath(Path.Combine(baseDir, relative));
        var allowedRoot = Path.GetFullPath(Path.Combine(baseDir, ".."));
        if (!fullPath.StartsWith(allowedRoot, StringComparison.OrdinalIgnoreCase) || !File.Exists(fullPath))
        {
            response.StatusCode = 404;
            response.ContentType = "text/plain";
            response.Write("Lookup script not found.");
            return;
        }

        var text = File.ReadAllText(fullPath);
        text = Regex.Replace(text, @"<script[^>]*>\s*", "", RegexOptions.IgnoreCase);
        text = Regex.Replace(text, @"</script>\s*", "", RegexOptions.IgnoreCase);
        text = text.Replace("<!--", "").Replace("-->", "");
        // Strip only real HTML tags. NEVER use <[^>]+> — that also matches JS operators
        // like <= and destroys for-loops in lookuptsip.js / lookupfcns.js, so every
        // Tsip* function fails to parse and lookup1 reports "Unknown lookup type".
        text = Regex.Replace(text, @"</?[A-Za-z][A-Za-z0-9]*\b[^>]*>", "", RegexOptions.IgnoreCase);

        response.ContentType = "application/javascript; charset=utf-8";
        // Do not long-cache: a bad strip previously poisoned browsers for days.
        response.Cache.SetCacheability(HttpCacheability.NoCache);
        response.Cache.SetNoStore();
        response.Write(text);
    }
}
