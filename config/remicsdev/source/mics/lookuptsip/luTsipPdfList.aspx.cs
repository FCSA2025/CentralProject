using System;
using System.Text;
using System.Data.Odbc;
using DBUtilities;

namespace lookuptsip
{
	/// <summary>
	/// Summary description for luTsipPdfList.
	/// </summary>
	public partial class luTsipPdfList : System.Web.UI.Page
	{

		private string cnstr;
		private OdbcConnection cn;
        private string schema;

		protected void Page_Load(object sender, System.EventArgs e)
		{
			txtErrorMsg.Value = "";
			try
			{
				cnstr = Session["s_cnString"].ToString();
			}
			catch(Exception ex)
			{
				sesSiteName.Value = "Timeout" + ":" + ex.Message;
				return;
			}

			sesSiteName.Value = Session["SiteName"].ToString();
			string type = Request.QueryString["type"];
			txtType.Value = type;
			string textin = Request.QueryString["text"].ToUpper();
		
			char [] delimiter = "^".ToCharArray();
			string [] keyparts = textin.Split(delimiter);

			string pdftype = keyparts[0];
			string text = keyparts[1];

            schema = Session["s_schema"].ToString();

            //Selects all validated pdf names from web.user_tables table
            //Single or multiple selects are driven by value of type, which will be "ed" or "ds"

			cn = new OdbcConnection(cnstr);
			cn.Open();

			string uuser = Session["s_user"].ToString().ToLower();
			string strSql;
			string op = schema.Replace("'", "''");
			//SQL:VIEW:web.user_tables_view — limit to this login's company schema (operator)
			if (pdftype == "T")
			{
                strSql = "SELECT file_name FROM web.user_tables_view WHERE tabletype = 0 AND operator = '" + op +
					"' AND validstat IN('S','T','U','K','M','L') ORDER BY file_name";
			}
			else //pdftype is then E
			{
                strSql = "SELECT file_name FROM web.user_tables_view WHERE tabletype = 5 AND operator = '" + op +
					"' AND validstat IN('S','T','U','K','M','L') ORDER BY file_name";
			}
			OdbcCommand select1 = new OdbcCommand(strSql);
			select1.Connection = cn;
			OdbcDataReader dr;

			try
			{
				dr = select1.ExecuteReader();
			}
			catch (Exception es)
			{
				cn.Close();
				txtErrorMsg.Value = "ERRORSQL:" + strSql + ":" + es.Message;
				return;
			}

			StringBuilder hh = new StringBuilder("",1000);
			StringBuilder ih = new StringBuilder("",1000);
			

			string textstr;
			
			if(dr.HasRows)
			{
				txtDisplayCnt.Value = "1";
				ih.Append("<select class='lu' name='cboCode' size='15'>");
				ih.Append("<option class='lu' value=''>PDF</option>");
			
				while(dr.Read())
				{
					textstr = DBUtils.GetDBString(dr,0);
                    ih.Append("<option class='lu' value='" + DBUtils.GetDBString(dr, 0) + "'>" + textstr + "</option>");
				}
				ih.Append("</select>");
				choices.InnerHtml = ih.ToString();
			}
			else // no codes found
			{
				txtDisplayCnt.Value = "0";
				ih.Append("There were no codes found.");
				ih.Append("<br/><br/><input type='button' name='btnClose' value='Close' onclick='sclose()'>");
				choices.InnerHtml = ih.ToString();
			}
			dr.Close();
			cn.Close();
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
		}
		#endregion
	}
}
