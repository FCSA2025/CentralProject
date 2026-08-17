using System;
using System.Web.UI;
using System.Web.UI.WebControls;
using System.Data;
using System.Data.Odbc;
using System.Collections;
using System.IO;

namespace Maintenance
{
    public partial class UserInfo : System.Web.UI.Page
    {
        string schema;
        string micsuser;
        string sourcetable;

        // controls on form

        //************************************************************************
        //
        //   ROUTINE: Page_Load
        //
        //   DESCRIPTION: This routine provides the event handler for the page
        //                load event.  It is responsible for initializing the
        //                controls on the page.
        //------------------------------------------------------------------------
        private void Page_Load(object sender, System.EventArgs e)
        {
            try
            {
                schema = Session["s_schema"].ToString();
            }
            catch (Exception)
            {
                Response.Redirect("../relogin.aspx");
            }
            micsuser = Session["s_user"].ToString();
            
            txtSourceTableType.Value = Request.QueryString["tabletype"];
            string sourcetabletype = Request.QueryString["tabletype"];
            if(sourcetabletype == "active")
            {
                sourcetable = "web.UserDetails";
                edittype.InnerText = "Display / Edit Production User Data";
            }
            else
            {
                sourcetable = "web.UserDetails_devtest_pcn";
                edittype.InnerText = "Display / Edit Development Test Data";
            }

            if (!Page.IsPostBack)
            {
                // check if current user is a manager
                string strSql1 = "SELECT IsManagerYN FROM " + sourcetable +
                    " WHERE ultrixid = '" + schema + "' AND micsid = '" + micsuser + "'";

                // load company/schema dropdown list
                string strSql2 = "SELECT distinct ultrixid FROM " + sourcetable + " ORDER BY ultrixid";

                using (OdbcConnection connection = new OdbcConnection(Session["s_cnString"].ToString()))
                {
                    connection.Open();

                    OdbcCommand cmd = new OdbcCommand(strSql1, connection);
                    txtismanager.Value = Convert.ToString(cmd.ExecuteScalar());
                    
                    using (DataTable oDTcompany = new DataTable())
                    {
                        OdbcDataAdapter Da1 = new OdbcDataAdapter();
                        Da1.SelectCommand = new OdbcCommand(strSql2, connection);
                        //OdbcCommandBuilder sqlCb1 = new OdbcCommandBuilder(Da1);
                        Da1.Fill(oDTcompany);

                        DataRow drow = oDTcompany.NewRow();

                        drow["ultrixid"] = "Select a company";

                        oDTcompany.Rows.InsertAt(drow, 0);

                        CompanyList.DataSource = oDTcompany;
                        CompanyList.DataValueField = "ultrixid";
                        CompanyList.DataTextField = "ultrixid";
                        CompanyList.DataBind();
                    }
                }


                //  bind data to GridView
                bindData();
            }

            if (Page.IsPostBack == false)  // initial load
            {
                // load full data to GridView
                bindData();
            }

        }  // Page_Load
        
       
        //************************************************************************
        //
        //   ROUTINE: bindData
        //
        //   DESCRIPTION: This routine queries the database for the data to be
        //                displayed and binds it to the repeater
        //------------------------------------------------------------------------
        private void bindData()
        {
            OdbcDataAdapter da = null;
            DataSet ds = null;

            // build WHERE clause to handle FCSA staff vs users display
            // FCSA staff can see all info
            // users can only see their companys info

            // set list of internal users
            string internal_users = "fwmda,fwmda2,fwoad,fwrse,hulme1,venn1";

            string whrclause = "";

            txtisfcsa.Value = "Y";
            if (internal_users.IndexOf(micsuser) == -1)
            {
                whrclause = " WHERE ultrixid = '" + schema + "'";
                txtisfcsa.Value = "N";
            }

            // build the query string to get the user data from the database
            
            string strSql = "SELECT DISTINCT ultrixid, micsid, Email, PhoneNumber, MobilePhoneNumber, " +
            " send_pcnYN, SendPhantomLinksReportYN, " +
            " SendMissingLinksReportYN, IsManagerYN, " +
            " IsMMCRepresentativeYN, IsMTGRepresentativeYN " +
            " FROM " + sourcetable +
            " " + whrclause +
            " ORDER BY ultrixid, micsid ";
            //InfoTextBox.Text = strSql;
            using (OdbcConnection connection = new OdbcConnection(Session["s_cnString"].ToString()))
            {
                connection.Open();

                try
                {
                    da = new OdbcDataAdapter(strSql, connection);
                    ds = new DataSet();
                    da.Fill(ds);

                    // set the source of the data for the gridview control and bind it
                    gvUserInfo.DataSource = ds;
                    gvUserInfo.DataBind();
                }
                catch (Exception ex1)
                {
                    InfoTextBox.Text += strSql + ":" + ex1.Message;
                }

            }

            // disable edit button for non-manager user

        }  // bindData

        protected void gvUserInfo_RowDataBound(object sender, System.Web.UI.WebControls.GridViewRowEventArgs e)
        {
            // if micsuser is an fcsa user, use grid edit defaults
            if (txtisfcsa.Value.ToString() == "Y") return;

            // otherwise, if micsuser is a manager, they can see and edit edit all records for their company
            // if micsuser is not a manager, they can see all their company users, but can only edit their own
            
            //Checking the RowType of the Row (to ensure is is a data row, not a title row) 
            if (e.Row.RowType == DataControlRowType.DataRow)
            {
                Button EditButton = (Button)e.Row.FindControl("btn_Edit");
                DataRowView dataRecord = (DataRowView)e.Row.DataItem;
                
                if (e.Row.Cells[2].Text.Trim() != micsuser && txtismanager.Value == "N")
                {
                    EditButton.Enabled = false;
                }
                else
                {
                    //sw.WriteLine("Enabled true");
                }
                //If row is not current user's then disable edit 
                //if (e.Row.Cells[2].Text == "fwrse1")
                //{
                //    e.Row.Enabled = false;
                //}
            }
        }
        protected void gvUserInfo_RowEditing(object sender, System.Web.UI.WebControls.GridViewEditEventArgs e)
        {
            //NewEditIndex property used to determine the index of the row being edited.  
            gvUserInfo.EditIndex = e.NewEditIndex;
            bindData();
        }
        protected void gvUserInfo_RowUpdating(object sender, System.Web.UI.WebControls.GridViewUpdateEventArgs e)
        {
            //Finding the controls from Gridview for the row which is going to update 
            InfoTextBox.Text += e.RowIndex.ToString() + "\n";
            string oprtyp = e.NewValues[0].ToString();
                        
            string ultrixid = gvUserInfo.Rows[e.RowIndex].Cells[1].Text.ToString();
            string micsid = gvUserInfo.Rows[e.RowIndex].Cells[2].Text.ToString();
            InfoTextBox.Text += ultrixid + "\n";
            InfoTextBox.Text += micsid + "\n";
            //InfoTextBox.Text += acct + "\n";
            /////////////////////////
            ///
            string logfile = Application["web_drive"].ToString() + "\\extractlogs\\" + Session["s_user"].ToString() + "UserInfo.txt";
            StreamWriter sw = new StreamWriter(logfile, true);

            //sw.WriteLine(e.NewValues.Count.ToString());

            // this loop to build update is required because blank fields in a grid row
            // translate to undefined in the e.NewValues dictio nary and cause program to fail
            // the following code only updates the record with new or existing values
            string strSql = "UPDATE " + sourcetable + " SET ";
            string comma = "";

            int fldnum = 0;
            foreach (DictionaryEntry entry in e.NewValues)
            {
                 if (entry.Value != null) { 
                    // check if fields ending in YN have Y or N value
                    if(entry.Key.ToString().IndexOf("YN") > 0)
                    {
                        if(entry.Value.ToString().Length != 1)
                        {
                            InfoTextBox.Text += "Value of field " + (fldnum + 3).ToString() + " must be a single character";
                            return;
                        }
                        if (entry.Value.ToString().ToUpper() != "Y" && entry.Value.ToString().ToUpper() != "N")
                        {
                            InfoTextBox.Text += "Value of field " + (fldnum + 3).ToString() + " must be Y or N";
                            return;
                        }
                        strSql += comma + entry.Key.ToString() + "='" + entry.Value.ToString().ToUpper() + "'";
                    }
                    else
                    {
                        strSql += comma + entry.Key.ToString() + "='" + entry.Value.ToString() + "'";
                    }
                }
                fldnum++;
                comma = ",";
            }
            strSql += " WHERE ultrixid = '" + ultrixid.Trim() + "' AND micsid = '" + micsid.Trim() + "'";
            sw.WriteLine(strSql);
            sw.Close();

            using (OdbcConnection connection = new OdbcConnection(Session["s_cnString"].ToString()))
            {
                connection.Open();
                int reccount;
                InfoTextBox.Text += strSql + "\n";

                OdbcCommand cmd = new OdbcCommand(strSql, connection);
                reccount = cmd.ExecuteNonQuery();
                InfoTextBox.Text += reccount.ToString() + " records updated in " + sourcetable + "\n";
            }

            //Setting the EditIndex property to -1 to cancel the Edit mode in Gridview  
            gvUserInfo.EditIndex = -1;

            //Call bindData method for displaying updated data  
            bindData();

        }
        protected void gvUserInfo_RowCancelingEdit(object sender, System.Web.UI.WebControls.GridViewCancelEditEventArgs e)
        {
            //Setting the EditIndex property to -1 to cancel the Edit mode in Gridview  
            gvUserInfo.EditIndex = -1;
            bindData();
        }

        protected void cbpartial_CheckedChanged(object sender, EventArgs e)
        {
            bindData();
        }
        protected void btnAddUser_Click(object sender, EventArgs e)
        {
            string strSql;

            // check if user already exists
            strSql = "SELECT count(*) FROM " + sourcetable + " WHERE ultrixid='" + CompanyList.SelectedValue.Trim() +
                "' AND micsid = '" + txtumicsuser.Text + "'";
            InfoTextBox.Text += strSql + "\n";

            using (OdbcConnection connection = new OdbcConnection(Session["s_cnString"].ToString()))
            {
                connection.Open();
                Int32 selcount;

                // check if project exists in adm.project_ids

                OdbcCommand userexists = new OdbcCommand(strSql, connection);
                selcount = (Int32)userexists.ExecuteScalar();

                if (selcount != 0)   // user already exists
                {
                    InfoTextBox.Text += "User already exists";
                    return;
                }
                else   // add new user
                {
                    //SQL:TABLE:adm.project_ids
                    strSql = "INSERT INTO " + sourcetable + " (ultrixid, micsid) VALUES('" + CompanyList.SelectedValue.Trim() +
                                    "','" + txtumicsuser.Text + "')";
                    InfoTextBox.Text += strSql + "\n";

                    OdbcCommand adduser = new OdbcCommand(strSql, connection);
                    selcount = adduser.ExecuteNonQuery();

                    InfoTextBox.Text += selcount.ToString() + " user added\n";
                    EnsureUserDir(CompanyList.SelectedValue.Trim(), txtumicsuser.Text.Trim());
                }
            }
        }

        private void EnsureUserDir(string company, string micsid)
        {
            if (string.IsNullOrWhiteSpace(company) || string.IsNullOrWhiteSpace(micsid)) return;
            try
            {
                string drive = Application["web_drive"] != null ? Application["web_drive"].ToString() : "D:";
                string site = Session["site_type"] != null ? Session["site_type"].ToString() : "remicsdev";
                string companyDir = drive + "\\Inetpub\\" + site + "\\mics\\userdirs\\" + company;
                string userDir = companyDir + "\\" + micsid;
                if (!Directory.Exists(companyDir)) Directory.CreateDirectory(companyDir);
                if (!Directory.Exists(userDir)) Directory.CreateDirectory(userDir);
                InfoTextBox.Text += "userdirs: " + userDir + "\n";
            }
            catch (Exception ex)
            {
                InfoTextBox.Text += "userdirs create failed: " + ex.Message + "\n";
            }
        }
    }
}