using System;
using System.Web;

namespace micsModules
{
    /// <summary>
    /// Return 401 JSON (not 302 Tlogin.aspx HTML) for unauthenticated .ashx/.asmx API calls.
    /// </summary>
    public class ApiAuthJsonModule : IHttpModule
    {
        public void Init(HttpApplication app)
        {
            app.PreSendRequestHeaders += OnPreSendRequestHeaders;
        }

        private static void OnPreSendRequestHeaders(object sender, EventArgs e)
        {
            var app = (HttpApplication)sender;
            var context = app.Context;
            if (context == null)
                return;

            var response = context.Response;
            var request = context.Request;
            if (response == null || request == null || response.HeadersWritten)
                return;

            string path = (request.Path ?? "").ToLowerInvariant();
            if (path.IndexOf(".ashx") < 0 && path.IndexOf(".asmx") < 0)
                return;
            if (response.StatusCode != 302)
                return;

            string loc = (response.RedirectLocation ?? response.Headers["Location"] ?? "").ToLowerInvariant();
            // Do not intercept redirects to RemIcsReWrite/login.aspx (e.g. logoff.ashx).
            if (loc.IndexOf("tlogin.aspx") < 0 && loc.IndexOf("relogin.aspx") < 0)
                return;

            response.Clear();
            response.TrySkipIisCustomErrors = true;
            response.StatusCode = 401;
            response.RedirectLocation = null;
            response.ContentType = "application/json; charset=utf-8";
            response.Write("{\"ok\":false,\"error\":\"Authentication required. Log off and sign in again via RemIcsReWrite/login.aspx.\"}");
        }

        public void Dispose()
        {
        }
    }
}
