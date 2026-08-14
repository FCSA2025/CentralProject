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
        // lookupfcns.js ends with stray HTML (<p>) after the script block; strip all tags.
        text = Regex.Replace(text, @"<[^>]+>", "", RegexOptions.IgnoreCase);

        response.ContentType = "application/javascript; charset=utf-8";
        response.Cache.SetCacheability(HttpCacheability.Public);
        response.Cache.SetExpires(DateTime.UtcNow.AddDays(7));
        response.Write(text);
    }
}
