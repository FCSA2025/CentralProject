<%@ WebHandler Language="C#" Class="RemIcsReWriteSessionHandler" %>

using System;
using System.Configuration;
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
            timestampUtc = DateTime.UtcNow.ToString("o")
        };

        if (!identityAuth)
            response.StatusCode = 401;

        var json = new JavaScriptSerializer().Serialize(payload);
        response.Write(json);
    }
}
