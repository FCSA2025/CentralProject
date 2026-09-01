using System;
using System.Text.RegularExpressions;
using System.Web.Security;
using System.Web.UI;

namespace mics
{
    public partial class RemIcsReWrite_file : Page
    {
        private static readonly Regex ValidName = new Regex(@"^[A-Za-z0-9_]{1,16}$", RegexOptions.Compiled);

        protected string MetaHtml = "";
        protected string DiagHtml = "";
        protected string JsFileName = "";
        protected string JsProjectCode = "";
        protected string JsSchema = "";
        protected string JsUser = "";
        protected string JsReportUrl = "";

        protected void Page_Load(object sender, EventArgs e)
        {
            if (Session["s_schema"] == null || Session["defProject"] == null)
            {
                Response.Redirect("../TloginValidate.aspx?rewrite=1", true);
                return;
            }

            string name = (Request.QueryString["name"] ?? "").Trim();
            if (!ValidName.IsMatch(name))
            {
                Response.StatusCode = 400;
                Response.Write("Invalid or missing file name.");
                Response.End();
                return;
            }

            string projectCode = Session["defProject"].ToString();
            string user = Session["s_user"] != null ? Session["s_user"].ToString().Trim().ToLowerInvariant() : "";
            string schema = Session["s_schema"].ToString().Trim().ToLowerInvariant();
            JsFileName = JsEncode(name);
            JsProjectCode = JsEncode(projectCode);
            JsSchema = JsEncode(schema);
            JsUser = JsEncode(user);
            JsReportUrl = JsEncode("../userdirs/" + schema + "/" + user + "/" + name + ".txt");
            bool hasCookie = Request.Cookies[FormsAuthentication.FormsCookieName] != null;

            MetaHtml = string.Format(
                "<div class=\"meta\"><strong>File:</strong> {0} &nbsp; <strong>User:</strong> {1} &nbsp; <strong>Schema:</strong> {2} &nbsp; <strong>Project:</strong> {3}</div>",
                Server.HtmlEncode(name), Server.HtmlEncode(user), Server.HtmlEncode(schema), Server.HtmlEncode(projectCode));

            DiagHtml = string.Format(
                "<dl class=\"diag\"><dt>Host</dt><dd>{0}</dd><dt>User.Identity.IsAuthenticated</dt><dd>{1}</dd><dt>{2} on request</dt><dd>{3}</dd></dl>",
                Server.HtmlEncode(Request.Url.Host),
                User.Identity.IsAuthenticated,
                Server.HtmlEncode(FormsAuthentication.FormsCookieName),
                hasCookie ? "yes" : "no");
        }

        private static string JsEncode(string value)
        {
            if (string.IsNullOrEmpty(value)) return "";
            return value.Replace("\\", "\\\\").Replace("\"", "\\\"");
        }
    }
}
