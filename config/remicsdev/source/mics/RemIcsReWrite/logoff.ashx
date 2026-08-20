<%@ WebHandler Language="C#" Class="RemIcsReWriteLogoffHandler" %>

using System;
using System.Web;
using System.Web.Security;
using System.Web.SessionState;
using SesUtilities;

/// <summary>RemIcsReWrite logout  -  ends session and returns to RemIcsReWrite login (not classic Tlogin).</summary>
public class RemIcsReWriteLogoffHandler : IHttpHandler, IRequiresSessionState
{
    public bool IsReusable { get { return false; } }

    public void ProcessRequest(HttpContext context)
    {
        var response = context.Response;
        var session = context.Session;
        var app = context.Application;

        try
        {
            if (session != null && session["s_user"] != null && session["s_schema"] != null && session["FCSASESS"] != null)
            {
                var si = new SessionInfo(
                    session["s_user"].ToString(),
                    session["s_schema"].ToString(),
                    session["FCSASESS"].ToString(),
                    session.SessionID,
                    "1",
                    session.Timeout.ToString(),
                    session["ProjStart"] != null ? session["ProjStart"].ToString() : "",
                    session["s_cnString"] != null ? session["s_cnString"].ToString() : "",
                    session["defProject"] != null ? session["defProject"].ToString() : "",
                    session["principalw"] as System.Security.Principal.WindowsPrincipal);
                if (app["web_drive"] != null)
                    SesUtils.LogSessionEnd(app["web_drive"].ToString(), si);
            }
        }
        catch { /* session may already be partial */ }

        try
        {
            if (session != null)
            {
                session["Active"] = "F";
                session.Abandon();
            }
        }
        catch { /* ignore */ }

        try
        {
            var sessionCookie = new HttpCookie("ASP.NET_SessionId", "");
            sessionCookie.Expires = DateTime.Now.AddYears(-1);
            response.Cookies.Add(sessionCookie);
        }
        catch { /* ignore */ }

        try
        {
            FormsAuthentication.SignOut();
            var authCookie = new HttpCookie(FormsAuthentication.FormsCookieName, "");
            authCookie.Expires = DateTime.Now.AddYears(-1);
            response.Cookies.Add(authCookie);
        }
        catch { /* ignore */ }

        response.Redirect("login.aspx?loggedout=1", true);
    }
}
