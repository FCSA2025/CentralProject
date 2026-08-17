<%@ WebHandler Language="C#" Class="RemIcsReWriteSessionHandler" %>

using System;
using System.Configuration;
using System.IO;
using System.Net;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.Security;
using System.Web.SessionState;
using SesUtilities;

/// <summary>JSON session health for RemIcsReWrite client diagnostics (Phase 5 IP cookie diag).</summary>
public class RemIcsReWriteSessionHandler : IHttpHandler, IRequiresSessionState
{
    public bool IsReusable { get { return false; } }

    public void ProcessRequest(HttpContext context)
    {
        var response = context.Response;
        var request = context.Request;
        response.ContentType = "application/json; charset=utf-8";
        response.Cache.SetCacheability(HttpCacheability.NoCache);

        var session = context.Session;
        string action = (request["action"] ?? "").Trim().ToLowerInvariant();
        if (action == "timeoutget" || action == "timeoutset")
        {
            HandleTimeout(context, action);
            return;
        }

        string host = request.Url.Host;
        bool isIp = SesUtils.IsRequestHostIp(request);

        string formsName = FormsAuthentication.FormsCookieName;
        bool cookieOnRequest = request.Cookies[formsName] != null;
        bool identityAuth = context.User != null && context.User.Identity != null && context.User.Identity.IsAuthenticated;

        string user = session != null && session["s_user"] != null ? session["s_user"].ToString() : null;
        string schema = session != null && session["s_schema"] != null ? session["s_schema"].ToString() : null;
        string project = session != null && session["defProject"] != null ? session["defProject"].ToString() : null;
        string fcsasess = session != null && session["FCSASESS"] != null ? session["FCSASESS"].ToString() : null;
        string loginType = session != null && session["loginType"] != null ? session["loginType"].ToString() : null;
        string userDir = session != null && session["user_dir"] != null ? session["user_dir"].ToString() : null;

        string siteDomainConfig = ConfigurationManager.AppSettings["SiteDomain"] ?? "";
        string siteNameConfig = ConfigurationManager.AppSettings["SiteName"] ?? "";
        bool prefUidOnRequest = request.Cookies["PrefUID"] != null;
        bool prefTimeOnRequest = request.Cookies["PrefTime"] != null;

        bool sessionReady = !string.IsNullOrEmpty(schema) && session != null && session["s_cnString"] != null;

        bool userDirExists = false;
        bool userDirWritable = false;
        int tsipErrCount = 0;
        string userDirHealth = null;
        if (!string.IsNullOrEmpty(userDir))
        {
            try
            {
                userDirExists = Directory.Exists(userDir);
                if (userDirExists)
                {
                    tsipErrCount = Directory.GetFiles(userDir, "tsip_*.ERR").Length;
                    var probe = Path.Combine(userDir, ".remics_write_probe_" + Guid.NewGuid().ToString("N"));
                    File.WriteAllText(probe, "ok");
                    File.Delete(probe);
                    userDirWritable = true;
                }
            }
            catch (Exception ex)
            {
                userDirHealth = ex.Message;
            }
        }

        string cookieAdvice;
        if (isIp)
            cookieAdvice = "Host is IP — Pref* cookies must be host-only (no Domain). Do not mix with hostname bookmarks in the same browser profile.";
        else
            cookieAdvice = "Host is DNS — Pref* cookies may use SiteDomain. Stay on this hostname for the session.";

        var payload = new
        {
            ok = sessionReady && identityAuth,
            status = sessionReady ? "ready" : (identityAuth ? "incomplete" : "unauthenticated"),
            user = user,
            schema = schema,
            project = project,
            fcsasess = fcsasess,
            host = host,
            isIp = isIp,
            siteDomainConfig = siteDomainConfig,
            siteNameConfig = siteNameConfig,
            loginType = loginType,
            user_dir = userDir,
            user_dir_exists = userDirExists,
            user_dir_writable = userDirWritable,
            tsip_err_count = tsipErrCount,
            user_dir_health = userDirHealth,
            authenticated = identityAuth,
            formsCookieName = formsName,
            formsCookieOnRequest = cookieOnRequest,
            cookieDiag = new
            {
                formsCookieOnRequest = cookieOnRequest,
                prefUidOnRequest = prefUidOnRequest,
                prefTimeOnRequest = prefTimeOnRequest,
                siteDomainConfig = siteDomainConfig,
                isIp = isIp,
                advice = cookieAdvice,
                documentCookieHint = "DevTools → Application → Cookies: on IP, .ADAuthCookie / ASP.NET_SessionId / Pref* should have empty Domain"
            },
            timeoutMinutes = session != null ? session.Timeout : 0,
            timestampUtc = DateTime.UtcNow.ToString("o")
        };

        if (!identityAuth)
            response.StatusCode = 401;

        var json = new JavaScriptSerializer().Serialize(payload);
        response.Write(json);
    }

    private static void HandleTimeout(HttpContext context, string action)
    {
        var response = context.Response;
        var session = context.Session;
        var ser = new JavaScriptSerializer();

        if (session == null || session["s_cnString"] == null || session["s_schema"] == null)
        {
            response.StatusCode = 401;
            response.Write(ser.Serialize(new { ok = false, error = "Session not initialized." }));
            return;
        }

        if (action == "timeoutget")
        {
            try { SesUtils.LogMenuUse("SetSessionTimeout"); } catch { }
            response.Write(ser.Serialize(new
            {
                ok = true,
                minutes = session.Timeout,
                defaultMinutes = 20
            }));
            return;
        }

        int minutes;
        if (!int.TryParse((context.Request["minutes"] ?? "").Trim(), out minutes))
        {
            response.StatusCode = 400;
            response.Write(ser.Serialize(new { ok = false, error = "Invalid timeout value: " + (context.Request["minutes"] ?? "") }));
            return;
        }
        if (minutes < 5)
        {
            response.StatusCode = 400;
            response.Write(ser.Serialize(new { ok = false, error = "Time must be >= 5" }));
            return;
        }

        session.Timeout = minutes;
        session["SESSLEN"] = session.Timeout;

        DateTime now = DateTime.Now;
        string siteDomain = session["Domain"] != null ? session["Domain"].ToString() : "";
        HttpCookie pref = new HttpCookie("PrefTime");
        pref.Path = session["Path"] != null ? session["Path"].ToString() : "/";
        pref.Expires = now.AddYears(1);
        pref.Value = minutes.ToString();
        SesUtils.ApplyPrefCookieDomain(pref, context.Request, siteDomain);
        response.Cookies.Add(pref);

        response.Write(ser.Serialize(new
        {
            ok = true,
            minutes = session.Timeout,
            message = "Session Timeout Changed to " + session.Timeout
        }));
    }
}
