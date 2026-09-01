using System;
using System.Data.Odbc;
using System.Security.Principal;
using DBUtilities;
using ErrorUtilities;

namespace Tfileactions
{
    /// <summary>
    /// Summary description for copy.
    /// </summary>
    public partial class copy : System.Web.UI.Page
    {
        protected string JsOldName = "";
        protected string JsNewName = "";
        protected string JsFileType = "TS";
        protected string JsProjectCode = "";

        private static string JsEncode(string value)
        {
            if (string.IsNullOrEmpty(value)) return "";
            return value.Replace("\\", "\\\\").Replace("\"", "\\\"");
        }

        private string cnstr;

        //private OdbcConnection cn;

        private void Page_Load(object sender, System.EventArgs e)
        {
            int tabtype;

            try
            {
                cnstr = Session["s_cnString"].ToString();
            }
            catch (Exception)
            {
                Response.Redirect("../relogin.aspx?reason=0&errcode=&source=copy.aspx");
            }

            sesSiteName.Value = Session["SiteName"].ToString();
            txtsType.Value = Request.QueryString["sType"].ToString();
            txtOldName.Value = Request.QueryString["oldName"].ToString();
            txtNewName.Value = Request.QueryString["newName"].ToString();
            string newName = Request.QueryString["newName"].ToString();
            JsOldName = JsEncode(txtOldName.Value);
            JsNewName = JsEncode(txtNewName.Value);
            JsFileType = JsEncode(txtsType.Value.Trim());
            JsProjectCode = JsEncode(Session["defProject"] != null ? Session["defProject"].ToString() : "");

            frmHeader.InnerHtml = "<h3>	From " + txtOldName.Value + " to " + txtNewName.Value + "</h3>";

            switch (txtsType.Value.Trim())
            {
                case "TS":
                    tabtype = 0;
                    break;

                case "ES":
                    tabtype = 5;
                    break;

                case "Ante":
                    tabtype = 301;
                    break;

                case "Band":
                    tabtype = 300;
                    break;

                case "Ctx":
                    tabtype = 303;
                    break;

                case "Eqpt":
                    tabtype = 305;
                    break;

                case "Note":
                    tabtype = 306;
                    break;

                case "Oper":
                    tabtype = 308;
                    break;

                case "Rout":
                    tabtype = 309;
                    break;

                case "Plan":
                    tabtype = 310;
                    break;

                case "Towr":
                    tabtype = 312;
                    break;

                case "Town":
                    tabtype = 313;
                    break;

                case "Traf":
                    tabtype = 314;
                    break;

                case "TsipParm":
                    tabtype = 417;
                    break;

                case "STATION":
                    tabtype = -99;
                    break;

                case "SDFREP":
                    tabtype = -99;
                    break;

                default:
                    txtErrorMsg.Value = "Invalid file type";
                    return;

            } // end of switch

            try
            {
                using (IDisposable WIC = SesUtilities.MicsDbAuth.ImpersonateForJob(Session["principalw"]))
                {
                    using (OdbcConnection cn = new OdbcConnection(cnstr))
                    {
                        cn.Open();

                        //SQL:VIEW:web.user_tables_view
                        string strSql = "SELECT file_name from web.user_tables_view " +
                            " where file_name = '" + newName.Trim() +
                            "' AND tabletype = " + tabtype +
                            " AND operator = '" + Session["s_schema"].ToString().Trim() + "'";

                        using (OdbcCommand select1 = new OdbcCommand(strSql, cn))
                        {
                            using (OdbcDataReader dr1 = select1.ExecuteReader())
                            {
                                if (dr1.HasRows)
                                {
                                    txtExists.Value = "t";
                                }
                                else
                                {
                                    txtExists.Value = "f";
                                }
                            }
                        }
                    }
                }
            }
            catch (Exception ee)
            {
                ErrorUtils.NotifySystemOps(ee, "CopyFile");
                //return "ERRORSYS:" + ee.Message;
            }
            //catch (Exception e1)
            //{
            //    cn.Close();
            //    txtErrorMsg.Value = "ERRORSQL:" + strSql + ":" + e1.Message;
            //    return;
            //}
        }

        #region Web Form Designer generated code
        override protected void OnInit(EventArgs e)
        {
            //
            // CODEGEN: This call is required by the ASP.NET Web Form Designer.
            //
            InitializeComponent();
            base.OnInit(e);
        }

        /// <summary>
        /// Required method for Designer support - do not modify
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            this.Load += new System.EventHandler(this.Page_Load);
        }
        #endregion
    }
}
