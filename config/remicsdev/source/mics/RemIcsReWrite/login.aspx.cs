using System;
using System.Text;
using System.Web.Security;
using System.Web.UI;
using SesUtilities;

namespace mics
{
    public partial class RemIcsReWrite_login : Page
    {
        protected string UserNameValue = "";
        protected string ErrorHtml = "";
        protected string DiagHtml = "";

        protected void Page_Load(object sender, EventArgs e)
        {
            if (string.Equals(Request.HttpMethod, "POST", StringComparison.OrdinalIgnoreCase))
            {
                ProcessLoginPost();
                return;
            }

            if (User.Identity != null && User.Identity.IsAuthenticated && Session["s_user"] != null)
            {
                if (Session["s_schema"] != null && Session["s_cnString"] != null)
                    Response.Redirect("shell.aspx", true);
                else
                    Response.Redirect("../TloginValidate.aspx?rewrite=1", true);
                return;
            }
            DiagHtml = BuildDiagnostics(false, null);
        }

        private void ProcessLoginPost()
        {
            string user = (Request.Form["user"] ?? "").Trim();
            string password = Request.Form["password"] ?? "";
            UserNameValue = Server.HtmlEncode(user);

            if (string.IsNullOrEmpty(user) || string.IsNullOrEmpty(password))
            {
                ErrorHtml = "<p class=\"error\">Enter Mics ID and password.</p>";
                DiagHtml = BuildDiagnostics(false, user);
                return;
            }

            if (Session["FCSASESS"] != null)
            {
                ErrorHtml = "<p class=\"error\">A session is already open. Log off first.</p>";
                DiagHtml = BuildDiagnostics(false, user);
                return;
            }

            bool ok = false;
            try
            {
                if (MicsDbAuth.IsEnabled())
                    ok = MicsDbAuth.VerifyPassword(user, password);
                else
                    ok = Membership.ValidateUser(user, password);
            }
            catch (Exception ex)
            {
                ErrorHtml = "<p class=\"error\">Auth error: " + Server.HtmlEncode(ex.Message) + "</p>";
                DiagHtml = BuildDiagnostics(false, user);
                return;
            }

            if (!ok)
            {
                ErrorHtml = "<p class=\"error\">Invalid credentials.</p>";
                DiagHtml = BuildDiagnostics(false, user);
                return;
            }

            Session["DaystoPwdExpiry"] = 999;
            Session["s_user"] = user;
            Session["s_password"] = password;
            Session["loginType"] = MicsDbAuth.IsEnabled() ? "DB" : "2";
            MicsDbAuth.EnsureProcessPrincipalInSession(Session);

            // Host-only forms auth cookie (no Domain) — required for raw-IP access (Phase 5).
            FormsAuthentication.SetAuthCookie(user, false);

            // Relative redirect — never SiteName absolute URL.
            Response.Redirect("../TloginValidate.aspx?rewrite=1", true);
        }

        private string BuildDiagnostics(bool authenticated, string attemptedUser)
        {
            var sb = new StringBuilder();
            sb.Append("<dl class=\"diag\">");
            sb.Append("<dt>Host</dt><dd>").Append(Server.HtmlEncode(Request.Url.Host)).Append("</dd>");
            sb.Append("<dt>Is IP host</dt><dd>")
              .Append(SesUtils.IsRequestHostIp(Request) ? "true" : "false")
              .Append("</dd>");
            sb.Append("<dt>Forms cookie name</dt><dd>").Append(Server.HtmlEncode(FormsAuthentication.FormsCookieName)).Append("</dd>");
            sb.Append("<dt>Cookie received on request</dt><dd>")
              .Append(Request.Cookies[FormsAuthentication.FormsCookieName] != null ? "yes" : "no")
              .Append("</dd>");
            sb.Append("<dt>User.Identity.IsAuthenticated</dt><dd>").Append(authenticated ? "true" : "false").Append("</dd>");
            if (!string.IsNullOrEmpty(attemptedUser))
                sb.Append("<dt>Attempted user</dt><dd>").Append(Server.HtmlEncode(attemptedUser)).Append("</dd>");
            sb.Append("<dt>UseDbAuth</dt><dd>").Append(MicsDbAuth.IsEnabled() ? "true" : "false").Append("</dd>");
            sb.Append("<dt>Policy</dt><dd>One URL per session (IP or hostname). Clear cookies when switching.</dd>");
            sb.Append("</dl>");
            return sb.ToString();
        }
    }
}
