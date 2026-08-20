using System;
using System.Web.Security;
using System.Web.UI;

namespace mics
{
    public partial class RemIcsReWrite_login : Page
    {
        protected string UserNameValue = "";
        protected string ErrorHtml = "";

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
        }

        private void ProcessLoginPost()
        {
            string user = (Request.Form["user"] ?? "").Trim();
            string password = Request.Form["password"] ?? "";
            UserNameValue = Server.HtmlEncode(user);

            if (string.IsNullOrEmpty(user) || string.IsNullOrEmpty(password))
            {
                ErrorHtml = "<p class=\"error\">Enter Mics ID and password.</p>";
                return;
            }

            if (Session["FCSASESS"] != null)
            {
                ErrorHtml = "<p class=\"error\">A session is already open. Log off first.</p>";
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
                return;
            }

            if (!ok)
            {
                ErrorHtml = "<p class=\"error\">Invalid credentials.</p>";
                return;
            }

            Session["DaystoPwdExpiry"] = 999;
            Session["s_user"] = user;
            Session["s_password"] = password;
            Session["loginType"] = MicsDbAuth.IsEnabled() ? "DB" : "2";
            MicsDbAuth.EnsureProcessPrincipalInSession(Session);

            // Host-only forms auth cookie (no Domain)  -  required for raw-IP access (Phase 5).
            FormsAuthentication.SetAuthCookie(user, false);

            // Relative redirect  -  never SiteName absolute URL.
            Response.Redirect("../TloginValidate.aspx?rewrite=1", true);
        }
    }
}
