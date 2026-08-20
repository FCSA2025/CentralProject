<%@ WebHandler Language="C#" Class="RemIcsReWriteSessionHandler" %>

using System;
using System.Configuration;
using System.Data.Odbc;
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
        if (action == "timeoutget" || action == "timeoutset" || action == "extrahelpset")
        {
            HandlePrefs(context, action);
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
        bool isFcsa = ReadIsFcsa(session);
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
            cookieAdvice = "Host is IP  -  Pref* cookies must be host-only (no Domain). Do not mix with hostname bookmarks in the same browser profile.";
        else
            cookieAdvice = "Host is DNS  -  Pref* cookies may use SiteDomain. Stay on this hostname for the session.";

        var payload = new
        {
            ok = sessionReady && identityAuth,
            status = sessionReady ? "ready" : (identityAuth ? "incomplete" : "unauthenticated"),
            user = user,
            schema = schema,
            project = project,
            fcsasess = fcsasess,
            isFcsa = isFcsa,
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

    /// <summary>dbo.t_UserDetails.IsFCSAYN = Y. Cached on Session["IsFCSAYN"]. Not FCSASESS (that is a session id).</summary>
    private static bool ReadIsFcsa(HttpSessionState session)
    {
        if (session == null) return false;
        if (session["IsFCSAYN"] != null)
            return string.Equals(session["IsFCSAYN"].ToString(), "Y", StringComparison.OrdinalIgnoreCase);

        bool fcsa = false;
        try
        {
            string user = session["s_user"] != null ? session["s_user"].ToString().Trim() : "";
            string cnstr = session["s_cnString"] != null ? session["s_cnString"].ToString() : "";
            if (user.Length > 0 && cnstr.Length > 0)
            {
                using (var cn = new OdbcConnection(cnstr))
                {
                    cn.Open();
                    string esc = user.Replace("'", "''");
                    using (var cmd = new OdbcCommand(
                        "SELECT RTRIM(ISNULL(IsFCSAYN,'N')) FROM dbo.t_UserDetails " +
                        "WHERE RTRIM(micsId) = '" + esc + "' AND RTRIM(IsActiveYN) = 'Y'", cn))
                    using (var dr = cmd.ExecuteReader())
                    {
                        if (dr.Read() && dr[0] != DBNull.Value)
                            fcsa = string.Equals(dr[0].ToString().Trim(), "Y", StringComparison.OrdinalIgnoreCase);
                    }
                }
            }
        }
        catch { /* treat as not FCSA */ }

        session["IsFCSAYN"] = fcsa ? "Y" : "N";
        return fcsa;
    }

    private static bool ReadExtraHelp(HttpRequest request)
    {
        var c = request.Cookies["PrefExtraHelp"];
        if (c == null || string.IsNullOrEmpty(c.Value)) return true;
        return c.Value != "0";
    }

    private static void WritePrefCookie(HttpContext context, string name, string value)
    {
        var session = context.Session;
        string siteDomain = session != null && session["Domain"] != null ? session["Domain"].ToString() : "";
        HttpCookie pref = new HttpCookie(name);
        pref.Path = session != null && session["Path"] != null ? session["Path"].ToString() : "/";
        pref.Expires = DateTime.Now.AddYears(1);
        pref.Value = value;
        SesUtils.ApplyPrefCookieDomain(pref, context.Request, siteDomain);
        context.Response.Cookies.Add(pref);
    }

    private static bool ParseExtraHelp(string raw)
    {
        raw = (raw ?? "").Trim();
        return raw != "0" && !string.Equals(raw, "false", StringComparison.OrdinalIgnoreCase);
    }

    private static void HandlePrefs(HttpContext context, string action)
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
                defaultMinutes = 60,
                extraHelp = ReadExtraHelp(context.Request)
            }));
            return;
        }

        if (action == "extrahelpset")
        {
            bool extraOn = ParseExtraHelp(context.Request["extraHelp"]);
            WritePrefCookie(context, "PrefExtraHelp", extraOn ? "1" : "0");
            response.Write(ser.Serialize(new { ok = true, extraHelp = extraOn }));
            return;
        }

        int minutes;
        if (!int.TryParse((context.Request["minutes"] ?? "").Trim(), out minutes))
        {
            response.StatusCode = 400;
            response.Write(ser.Serialize(new { ok = false, error = "Invalid timeout value: " + (context.Request["minutes"] ?? "") }));
            return;
        }
        if (minutes < 60)
        {
            response.StatusCode = 400;
            response.Write(ser.Serialize(new { ok = false, error = "Time must be >= 60" }));
            return;
        }

        session.Timeout = minutes;
        session["SESSLEN"] = session.Timeout;
        WritePrefCookie(context, "PrefTime", minutes.ToString());

        bool extraHelp = ReadExtraHelp(context.Request);
        if (context.Request["extraHelp"] != null)
        {
            extraHelp = ParseExtraHelp(context.Request["extraHelp"]);
            WritePrefCookie(context, "PrefExtraHelp", extraHelp ? "1" : "0");
        }

        response.Write(ser.Serialize(new
        {
            ok = true,
            minutes = session.Timeout,
            extraHelp = extraHelp,
            message = "Session Timeout Changed to " + session.Timeout
        }));
    }
}
