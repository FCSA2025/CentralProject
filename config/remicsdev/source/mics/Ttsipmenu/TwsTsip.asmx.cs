using System;
using System.IO;
using System.ComponentModel;
using System.Data;
using System.Data.Odbc;
using System.Web.Services;
using System.Security.Principal;
using DBUtilities;
using DBAccess;
using JobSubmission;
using ErrorUtilities;

namespace Ttsipmenu
{
    [WebService(Namespace = "https://mics.fcsa.ca/webservices/")]
    /// <summary>
	/// Summary description for wsTsip.
	/// </summary>
    // To allow this Web Service to be called from script, using ASP.NET AJAX, uncomment the following line. 
    [System.Web.Script.Services.ScriptService]
    public class wsTsip : System.Web.Services.WebService
	{
        private string cnstr = "";
        private string sesUser;
        private string sesSchema;
        private StreamWriter sw;
        
        public wsTsip()
		{
			//CODEGEN: This call is required by the ASP.NET Web Services Designer
			InitializeComponent();
		}

		#region Component Designer generated code
		
		//Required by the Web Services Designer 
		private IContainer components = null;
				
		/// <summary>
		/// Required method for Designer support - do not modify
		/// the contents of this method with the code editor.
		/// </summary>
		private void InitializeComponent()
		{
		}

		/// <summary>
		/// Clean up any resources being used.
		/// </summary>
		protected override void Dispose( bool disposing )
		{
			if(disposing && components != null)
			{
				components.Dispose();
			}
			base.Dispose(disposing);		
		}
		
		#endregion


		private bool getconnstring()
		{
			try
			{
				cnstr = Session["s_cnString"].ToString();
				return true;
			}
			catch(Exception ex)
			{
				cnstr = "timeout" + ex.Message;
				return false;
			}
		}
        [WebMethod(EnableSession = true)]
        public string tsipValidate(string type, string pdfname)
        {
            // this if clause forces return if session has timed out
            if (!getconnstring())
            {
                return cnstr;
            }

            string valid = "";

            try
            {
                using (IDisposable WIC = SesUtilities.MicsDbAuth.ImpersonateForJob(Session["principalw"]))
                {

                    using (OdbcConnection ucn = new OdbcConnection(cnstr))
                    {
                        ucn.Open();

                        //Table Names
                        sesSchema = Session["s_schema"].ToString();

                        string strSql;

                        if (type == "ft_")
                        {
                            //SQL:VIEW:web.user_tables_view — own schema only
                            strSql = "select validstat from web.user_tables_view " +
                                     " where tabletype = 0 " +
                                     "   and file_name ='" + pdfname + "'" +
                                     "   and operator ='" + sesSchema.Replace("'", "''") + "'";
                        }
                        else
                        {
                            //SQL:VIEW:web.user_tables_view — own schema only
                            strSql = "select validstat from web.user_tables_view " +
                                     " where tabletype = 5 " +
                                     "   and file_name ='" + pdfname + "'" +
                                     "   and operator ='" + sesSchema.Replace("'", "''") + "'";
                        }

                        using (OdbcCommand select1 = new OdbcCommand(strSql, ucn))
                        {
                            using (OdbcDataReader dr1 = select1.ExecuteReader())
                            {
                                if (dr1.HasRows)
                                {
                                    dr1.Read();
                                    valid = DBUtils.GetDBString(dr1, 0);
                                }
                                else
                                {
                                    valid = "not found";
                                }
                            }
                        }  // end command
                    }  // end connection
                }  // end impersonation
            }
            catch (Exception ee)
            {
                ErrorUtils.NotifySystemOps(ee, "tsipValidate");
                return "ERRORSYS:" + ee.Message;
            }
            return valid;
        }
        [WebMethod(EnableSession=true)]
		public string tsipValidateAll(string tsipparmname)
		{
            // this if clause forces return if session has timed out
            if (!getconnstring())
            {
                return cnstr;
            }
            
            string valid = "";
            string retval = "";
            string caret = "";

            //string logfile = Application["web_drive"].ToString() + "\\extractlogs\\" + sesUser + "tsipValidateAll.txt";

            //sw = new StreamWriter(logfile, false);

            try
            {
                using (IDisposable WIC = SesUtilities.MicsDbAuth.ImpersonateForJob(Session["principalw"]))
                {
                    using (OdbcConnection oCn = new OdbcConnection(cnstr))
                    {
                        oCn.Open();

                        string strSql;
                        string validflags = "UTKML";

                        // get info for all runs in tsipparm
                        strSql = "select protype, RTRIM(envtype) as renvtype, RTRIM(proname) as rproname, " +
                            "RTRIM(envname) as renvname, RTRIM(runname) AS rrunname from " +
                            Session["s_schema"].ToString() + ".tp_" + tsipparmname + "_parm";
                        //sw.WriteLine(strSql); //sw.Flush();

                        using (DataTable oDTtsip = new DataTable())
                        {
                            OdbcDataAdapter Da1 = new OdbcDataAdapter();
                            Da1.SelectCommand = new OdbcCommand(strSql, oCn);
                            OdbcCommandBuilder sqlCb1 = new OdbcCommandBuilder(Da1);
                            Da1.Fill(oDTtsip);

                            // loop through tsip parameter runs and check existence and valid state of files
                            foreach (DataRow oDRtsip in oDTtsip.Rows)
                            {
                                string runname = oDRtsip["rrunname"].ToString();
                                string protype = oDRtsip["protype"].ToString();
                                int tabletype = protype == "E" ? 5 : 0;
                                AppendPdfCatalogCheck(oCn, ref retval, ref caret, validflags, runname, tabletype,
                                    oDRtsip["rproname"].ToString());

                                string envtype = oDRtsip["renvtype"].ToString().Trim();
                                if (envtype == "PDF_TS" || envtype == "PDF_ES")
                                {
                                    int envTabletype = envtype == "PDF_ES" ? 5 : 0;
                                    AppendPdfCatalogCheck(oCn, ref retval, ref caret, validflags, runname, envTabletype,
                                        oDRtsip["renvname"].ToString());
                                }
                            }   // end foreach
                        } // end using datable
                    }  // end connection
                }  // end impersonation
                //sw.Write(retval);
                //sw.Close();
                return retval;
            }
            catch (Exception ee)
            {
                ErrorUtils.NotifySystemOps(ee, "tsipValidateAll");
                return "ERRORSYS:" + ee.Message;
            }
            //return valid;
		}

        /// <summary>Gate A: append validate failure when PDF is missing or invalid for this operator only.</summary>
        private void AppendPdfCatalogCheck(OdbcConnection oCn, ref string retval, ref string caret,
            string validflags, string runname, int tabletype, string pdfname)
        {
            if (string.IsNullOrWhiteSpace(pdfname))
            {
                // W2-7: blank PDF name is a validate failure (not Ready).
                retval += caret + runname + "," + (pdfname ?? "").Trim() + ",1";
                caret = "^";
                return;
            }

            string schema = Session["s_schema"].ToString().Replace("'", "''");
            string safeName = pdfname.Trim().Replace("'", "''");
            string sql = "SELECT validstat FROM web.user_tables_view WHERE tabletype = " + tabletype +
                " AND file_name = '" + safeName + "' AND operator = '" + schema + "'";

            using (OdbcCommand cmd = new OdbcCommand(sql, oCn))
            using (OdbcDataReader dr = cmd.ExecuteReader())
            {
                if (dr.HasRows)
                {
                    dr.Read();
                    string valid = DBUtils.GetDBString(dr, 0);
                    if (validflags.IndexOf(valid) == -1)
                    {
                        retval += caret + runname + "," + pdfname.Trim() + ",2";
                        caret = "^";
                    }
                }
                else
                {
                    retval += caret + runname + "," + pdfname.Trim() + ",1";
                    caret = "^";
                }
            }
        }

		[WebMethod(EnableSession=true)]
		public string tsipRun(string parmfile)
		{
            // this if clause forces return if session has timed out
            if (!getconnstring())
            {
                return cnstr;
            }

            try
            {
                using (IDisposable WIC = SesUtilities.MicsDbAuth.ImpersonateForJob(Session["principalw"]))
                {
                    // set up user and final program variables
                    sesUser = Session["s_user"].ToString();
                    sesSchema = Session["s_schema"].ToString();
                    string work_dir = Session["user_dir"].ToString();

                    // set debug log file
                    string logfile = Application["web_drive"].ToString() + "\\extractlogs\\" + sesUser + "tsip.txt";

                    sw = new StreamWriter(logfile, false);
                    sw.WriteLine(DateTime.Now + " : " + Session["FCSASESS"].ToString());
                    sw.WriteLine(sesUser + " " + sesSchema + " " + work_dir);
                    sw.Flush();

                    // open a new logger to control job
                    dblogger oLog = new dblogger(Session["prog_dir"].ToString() + "TsipInitiator");

                    string projectCode = Session["defProject"].ToString();
                    oLog.logargs = Session["db_name"].ToString() + " " + projectCode + " -otsip " + parmfile + " -p" + Session["prog_dir"].ToString();

                    sw.WriteLine(oLog.logprogram + " " + oLog.logargs);
                    sw.Flush();

                    string retval = "";

                    // submit program 
                    // SubmitJob will submit the job to queue and wait up to 1 second for return
                    // This allows time to detect duplicate entry in queue
                    oLog = JobSubmit.SubmitJob(oLog, " ", 2);

                    // update web.dblogger with results of batch submission
                    sw.WriteLine("after submit " + retval);
                    sw.Close();

                    // update web.logger record for this process
                    int logret;
                    logret = oLog.Finish();

                    switch (oLog.logerrorcode)
                    {
                        case 0:  // submission succeeded
                            return "OK:0";
                        case 2:  // duplicate submission
                            return "OK:2";
                        case -99:  // timeout
                            // this should never happen
                            break;
                        case -98:
                            return "ERROR: Unable to start TsipInitiator program";
                        default:
                            return "ERROR: Unexpected return code " + oLog.logerrorcode.ToString();
                    }

                    return retval;
                }  // end impersonation
            }
            catch (Exception ee)
            {
                ErrorUtils.NotifySystemOps(ee, "tsipRun");
                return "ERRORSYS:" + ee.Message;
            }
		}
		[WebMethod(EnableSession=true)]
		public string tsipDelete(string jobno)
		{
            // this if clause forces return if session has timed out
            if (!getconnstring())
            {
                return cnstr;
            }

            try
            {
                using (IDisposable WIC = SesUtilities.MicsDbAuth.ImpersonateForJob(Session["principalw"]))
                {

                    sesSchema = Session["s_schema"].ToString();
                    sesUser = Session["s_user"].ToString();
                    string logprogram = Session["prog_dir"].ToString() + "tsipQdelete";
                    string logargs = Session["db_name"].ToString() + jobno;
                    string projectCode = Session["defProject"].ToString();
////
                   // set debug log file
                    string logfile = Application["web_drive"].ToString() + "\\extractlogs\\" + sesUser + "tsipDelete.txt";

                    sw = new StreamWriter(logfile, false);
                    sw.WriteLine(DateTime.Now + " : " + Session["FCSASESS"].ToString());
                    sw.Flush();

                    // open a new logger to control job
                    dblogger oLog = new dblogger(Session["prog_dir"].ToString() + "tsipQdelete");

                    oLog.logargs = Session["db_name"].ToString() + " " + jobno;

                    sw.WriteLine(oLog.logprogram + " " + oLog.logargs);
                    sw.Flush();

                    string retval = "";

                    // submit program 
                    // SubmitJob will submit the job to queue and wait up to 1 second for return
                    // This allows time to detect duplicate entry in queue
                    oLog = JobSubmit.SubmitJob(oLog, " ", 2);

                    sw.WriteLine("after submit " + retval);
                    sw.WriteLine(oLog.logerrorcode);

                    sw.Close();////

                    switch (oLog.logreturncode)
                    {
                        case 0: // job queue updated (status set to 'D')
                            retval = "OK:0";
                            break;
                        case 1: // job not found
                            retval = "OK:1";
                            break;
                        case 2: // job belongs to other user
                            retval = "OK:2";
                            break;
                        case 3: // job finished or being deleted
                            retval = "OK:3";
                            break;
                        case 10: // error updating queue record
                            retval = "ERROR:10";
                            break;
                        case 123: // job queue busy
                            retval = "ERROR:123";
                            break;
                        case 125: // could not open database
                            retval = "ERROR:125";
                            break;
                        default:
                            retval = "ERROR:OTHER";
                            break;
                    }
                    return retval;
                }  // end impersonate
            }
            catch (Exception ee)
            {
                ErrorUtils.NotifySystemOps(ee, "tsipDelete");
                return "ERRORSYS:" + ee.Message;
            }
		}	

		private bool copy_prn(string serial, string newname)
		{

                string unixprn = Application["unix_drive"].ToString() + "\\" + sesSchema + "\\" + sesUser + "\\p" + serial + ".prn";
                checkDir(Application["web_drive"].ToString() + "\\Inetpub\\userdirs\\" + sesSchema);
                checkDir(Application["web_drive"].ToString() + "\\Inetpub\\userdirs\\" + sesSchema + "\\" + sesUser);
                string wincstxt = Application["web_drive"].ToString() + "\\Inetpub\\userdirs\\" + sesSchema + "\\" + sesUser + "\\" + newname;

                // delete target file if present
                if (File.Exists(wincstxt))
                {
                    File.Delete(wincstxt);
                }

                // this loop avoids problem of trying to move file before unix has released it
                while (!File.Exists(unixprn)) { }

                // move unix .prn to windows .txt file for browser display

                File.Move(unixprn, wincstxt);

                return true;
		}
		private bool delete_prn(string serial)
		{
			string unixprn = Application["unix_drive"].ToString() + "\\" + sesSchema + "\\" + sesUser + "\\p" + serial + ".prn";
			
			// this loop avoids problem of trying to delete file before unix has released it
			while(!File.Exists(unixprn)){}

			// delete unix .prn 
                  
			File.Delete(unixprn);

			return true;
		}
		private void checkDir(string dirname)
		{
			if(!Directory.Exists(dirname))
			{
				Directory.CreateDirectory(dirname);
			}
		}	
	}
}


