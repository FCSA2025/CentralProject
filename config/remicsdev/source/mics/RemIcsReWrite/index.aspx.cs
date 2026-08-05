using System;
using System.Data.Odbc;
using System.Text;
using System.Web.Security;
using System.Web.UI;
using SesUtilities;

namespace mics
{
    public partial class RemIcsReWrite_index : Page
    {
        protected string MetaHtml = "";
        protected string DiagHtml = "";
        protected string FilesHtml = "";

        protected void Page_Load(object sender, EventArgs e)
        {
            if (Session["s_schema"] == null || Session["s_cnString"] == null)
            {
                Response.Redirect("../TloginValidate.aspx?rewrite=1", true);
                return;
            }

            // Phase 0: index.aspx redirects to shell; keep file list logic for harness / deep links.
            if (string.IsNullOrEmpty(Request.QueryString["harness"]))
            {
                Response.Redirect("shell.aspx#/ts-tree", false);
                return;
            }

            string user = Session["s_user"] != null ? Session["s_user"].ToString() : "";
            string schema = Session["s_schema"].ToString();
            string project = Session["defProject"] != null ? Session["defProject"].ToString() : "";

            MetaHtml = string.Format(
                "<div class=\"meta\"><strong>User:</strong> {0} &nbsp; <strong>Schema:</strong> {1} &nbsp; <strong>Project:</strong> {2}</div>",
                Server.HtmlEncode(user), Server.HtmlEncode(schema), Server.HtmlEncode(project));

            bool hasCookie = Request.Cookies[FormsAuthentication.FormsCookieName] != null;
            DiagHtml = string.Format(
                "<dl class=\"diag\"><dt>Host</dt><dd>{0}</dd><dt>User.Identity.IsAuthenticated</dt><dd>{1}</dd><dt>{2} on request</dt><dd>{3}</dd><dt>Session FCSASESS</dt><dd>{4}</dd></dl>",
                Server.HtmlEncode(Request.Url.Host),
                User.Identity.IsAuthenticated,
                Server.HtmlEncode(FormsAuthentication.FormsCookieName),
                hasCookie ? "yes" : "no",
                Session["FCSASESS"] != null ? Session["FCSASESS"].ToString() : "(none)");

            FilesHtml = BuildFileList(schema);
        }

        private string BuildFileList(string schema)
        {
            var sb = new StringBuilder();
            sb.Append("<ul class=\"files\">");
            int count = 0;

            try
            {
                string cnstr = Session["s_cnString"].ToString();
                using (IDisposable wic = MicsDbAuth.ImpersonateForJob(Session["principalw"]))
                using (var ucn = new OdbcConnection(cnstr))
                {
                    ucn.Open();
                    string sql = "SELECT table_name FROM INFORMATION_SCHEMA.TABLES WHERE table_schema = '" +
                                 schema.Replace("'", "''") + "' AND table_name LIKE 'ft_%_titl' ORDER BY table_name";
                    using (var cmd = new OdbcCommand(sql, ucn))
                    using (var dr = cmd.ExecuteReader())
                    {
                        while (dr.Read())
                        {
                            string tablename = dr.GetString(0);
                            if (tablename.Length > 8)
                            {
                                string filename = tablename.Substring(3, tablename.Length - 8);
                                sb.Append("<li><a href=\"file.aspx?name=")
                                  .Append(Server.UrlEncode(filename))
                                  .Append("\">")
                                  .Append(Server.HtmlEncode(filename))
                                  .Append("</a></li>");
                                count++;
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                return "<p class=\"error\">Error loading TS list: " + Server.HtmlEncode(ex.Message) + "</p>";
            }

            if (count == 0)
                sb.Append("<li class=\"empty\">No TS files found.</li>");

            sb.Append("</ul>");
            return sb.ToString();
        }
    }
}
