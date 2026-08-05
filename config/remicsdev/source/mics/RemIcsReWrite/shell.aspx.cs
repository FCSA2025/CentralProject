using System;
using System.Web.Security;
using System.Web.UI;

namespace mics
{
    public partial class RemIcsReWrite_shell : Page
    {
        protected string JsUser = "";
        protected string JsSchema = "";
        protected string JsProject = "";

        protected void Page_Load(object sender, EventArgs e)
        {
            if (Session["s_schema"] == null || Session["s_cnString"] == null)
            {
                Response.Redirect("../TloginValidate.aspx?rewrite=1", true);
                return;
            }

            JsUser = EscapeJs(Session["s_user"] != null ? Session["s_user"].ToString() : "");
            JsSchema = EscapeJs(Session["s_schema"].ToString());
            JsProject = EscapeJs(Session["defProject"] != null ? Session["defProject"].ToString() : "");
        }

        private static string EscapeJs(string value)
        {
            if (string.IsNullOrEmpty(value)) return "";
            return value.Replace("\\", "\\\\").Replace("\"", "\\\"");
        }
    }
}
