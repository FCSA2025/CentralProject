using System;
using System.Security.Principal;
using System.IO;
using System.Data;
using System.Data.Odbc;
using System.Configuration;
using System.Net.Mail;
using System.Web;
using System.Web.UI;
using System.Threading;
using System.Runtime.InteropServices;
using SesUtilities;

namespace mics
{
    /// <summary>
    /// Summary description for Global.
    /// </summary>
    public class Global : System.Web.HttpApplication
    {
        /// <summary>
        /// Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        public Global()
        {
            InitializeComponent();
        }

        protected void Application_Start(Object sender, EventArgs e)
        {
            //string JQueryVer = "1.7.1";
            string JQueryVer = "1.11.0";
            ScriptManager.ScriptResourceMapping.AddDefinition("jquery", new ScriptResourceDefinition
            {
                Path = "~/Scripts/jquery-" + JQueryVer + ".min.js",
                DebugPath = "~/Scripts/jquery-" + JQueryVer + ".js",
                CdnPath = "http://ajax.aspnetcdn.com/ajax/jQuery/jquery-" + JQueryVer + ".min.js",
                CdnDebugPath = "http://ajax.aspnetcdn.com/ajax/jQuery/jquery-" + JQueryVer + ".js",
                CdnSupportsSecureConnection = true,
                LoadSuccessExpression = "window.jQuery"
            });

            bool logExists = System.Diagnostics.EventLog.Exists("Mics");

            // reset bad login count
            Application["badLoginCount"] = 0;
            // set number of allowed login failures before e-mail is sent 
            Application["badLoginLimit"] = 5;
            // clear active sessions list
            Application["sessions"] = "";
            // clear active windows users list
            Application["uusers"] = "";
            // clear active mics users list
            Application["musers"] = "";

            // get appsettings from web.config

            // set site active flag for current web site
            Application["site_active"] = ConfigurationManager.AppSettings["Site_active"];

            // set windows drive for current web site
            Application["web_drive"] = ConfigurationManager.AppSettings["Web_drive"];
            // set ODBC dataset name
            Application["ODBC_DSN"] = ConfigurationManager.AppSettings["ODBC_DSN"];
            // set sql instance name
            Application["Sql_Instance"] = ConfigurationManager.AppSettings["SQL_INSTANCE"];
            // set sql users list (these users can access sql via web)
            Application["Sql_Users"] = ConfigurationManager.AppSettings["SqlUsers"];
            // set SMTP Server name
            Application["SMTP_Server"] = ConfigurationManager.AppSettings["SMTP_server"];
            // set server name for remote production web site
            Application["remote_server"] = ConfigurationManager.AppSettings["Remote_server"];
            // set server name for disaster recovery web site
            Application["DR_server"] = ConfigurationManager.AppSettings["DR_server"];
            // set windows drive for remote production web site
            Application["remote_drive"] = ConfigurationManager.AppSettings["Remote_drive"];
            // set secure help site name
            Application["HelpUrl"] = ConfigurationManager.AppSettings["HelpUrl"];
            // set dev site name
            Application["DevUrl"] = ConfigurationManager.AppSettings["DevUrl"];
            // set test site name
            Application["TestUrl"] = ConfigurationManager.AppSettings["TestUrl"];
            // set prod site name
            Application["ProdUrl"] = ConfigurationManager.AppSettings["ProdUrl"];
            // set prod site name
            Application["ProdUrl2"] = ConfigurationManager.AppSettings["ProdUrl2"];
            // set max records to be saved or reported by TS datasearch
            Application["Max_TS_Ds"] = ConfigurationManager.AppSettings["Max_TS_Ds"];
            // set max records to be saved or reported by ES datasearch
            Application["Max_ES_Ds"] = ConfigurationManager.AppSettings["Max_ES_Ds"];
            // set membership default password timeout
            Application["PwdExpiry"] = ConfigurationManager.AppSettings["PwdExpiry"];
            // set membership default password timeout
            Application["PwdExpiryWarning"] = ConfigurationManager.AppSettings["PwdExpiryWarning"];
            // set external binary directory
            Application["ProgDir"] = ConfigurationManager.AppSettings["ProgDir"];
            // set Active Directory login domain
            Application["AD_Domain"] = ConfigurationManager.AppSettings["ADDomain"];
            // set users allowed to test new trees
            Application["TelerikUsers"] = ConfigurationManager.AppSettings["TelerikUsers"];
            // server name for IIS serrver for use by sql email
            Application["IISServerName"] = ConfigurationManager.AppSettings["IISServerName"];
            // application version of db_name to support password reset
            Application["db_name"] = ConfigurationManager.AppSettings["DBName"];
            // set site type (remicsdev/remicstest) etc
            Application["site_type"] = ConfigurationManager.AppSettings["SiteType"];
            // set application URL
            Application["site_name"] = ConfigurationManager.AppSettings["SiteName"];
            // set domain name of current site (for cookies) 
            Application["site_domain"] = ConfigurationManager.AppSettings["SiteDomain"];
            // set path of current site (for cookies) >
            Application["site_path"] = ConfigurationManager.AppSettings["SitePath"];
            // set ports for current site (for cookies)  -->
            Application["site_ports"] = ConfigurationManager.AppSettings["SitePorts"];
            // set full path to batch programs directory
            Application["prog_dir"] = Application["web_drive"].ToString() + Application["ProgDir"].ToString();
            // set up connection string for use as sqlclient
            Application["sqlclient_cnString"] = "Server=" + Application["Sql_Instance"].ToString() +
                                    ";Database=" + Application["db_name"].ToString() +
                                    ";Trusted_Connection=true;";
            // get AD info
            Application["ADconnect"] = ConfigurationManager.ConnectionStrings["ADConnectionString"];
            Application["ADUser"] = ConfigurationManager.AppSettings["ADUser"].ToString(); 
            Application["ADKey"] = ConfigurationManager.AppSettings["ADKey"].ToString();
            Application["ADappname"] = ConfigurationManager.AppSettings["ADapplicationname"].ToString();
        }
        protected void Session_Start(Object sender, EventArgs e)
        {
            Session["Active"] = "F";    // this is reset to T after a successful login
        }

        protected void Application_BeginRequest(Object sender, EventArgs e)
        {
            // this option requires integrated pipeline mode
            //Response.Headers.Add("X-UA-Compatible", "IE=edge");
        }

        protected void Application_PreRequestHandlerExecute(object sender, EventArgs e)
        {

            if (Request.Url.AbsoluteUri.IndexOf("Tlogin.aspx") == -1 &&
                Request.Url.AbsoluteUri.IndexOf("relogin.aspx") == -1 &&
                Request.Url.AbsoluteUri.IndexOf("reloginnewwin.aspx") == -1 &&
                Request.Url.AbsoluteUri.IndexOf("logoff.aspx") == -1 &&
                Request.Url.AbsoluteUri.IndexOf("pwdrecov.aspx") == -1 &&
                Request.Url.AbsoluteUri.IndexOf(".asmx") == -1 &&
                Request.Url.AbsoluteUri.IndexOf(".ashx") == -1 &&
                Request.Url.AbsoluteUri.IndexOf(".asd") == -1)
            {
                if (Thread.CurrentPrincipal.Identity.IsAuthenticated == true &&
                    HttpContext.Current.Session != null)
                {
                    // AD-free: no Windows token — keep Forms principal (app pool for SQL/files).
                    if (SesUtilities.MicsDbAuth.IsEnabled())
                    {
                        return;
                    }

                    WindowsPrincipal windowsPrincipal = (WindowsPrincipal)Session["principalw"];
                    //GenericPrincipal genericPrincipal = (GenericPrincipal)Session["principald"];
                    Thread.CurrentPrincipal = windowsPrincipal;
                    HttpContext.Current.User = windowsPrincipal;
                    try
                    {
                        HttpContext.Current.Items["identity"] = ((WindowsIdentity)windowsPrincipal.Identity).Impersonate();
                        HttpContext.Current.Items["genericPrincipal"] = (GenericPrincipal)Session["principald"];
                    }
                    catch
                    {
                        //Response.Redirect("login.aspx");
                        if (Request.Url.AbsoluteUri.IndexOf("/lu") == -1 && 
                            Request.Url.AbsoluteUri.IndexOf("emailus.aspx") == -1 &&
                            Request.Url.AbsoluteUri.IndexOf("dsESSave1.aspx") == -1 &&
                            Request.Url.AbsoluteUri.IndexOf("dsSDFSave1.aspx") == -1 &&
                            Request.Url.AbsoluteUri.IndexOf("dsTSSave1.aspx") == -1)
                        {
                            Response.Redirect(Request.Url.GetLeftPart(System.UriPartial.Authority) + "/mics/relogin.aspx");
                        }
                    }
                }
            }
        }

        protected void Application_PostRequestHandlerExecute(object sender, EventArgs e)
        {
           
            if ( HttpContext.Current.Session != null &&
                HttpContext.Current.Items["genericPrincipal"] != null)
            {
                GenericPrincipal genericPrincipal = (GenericPrincipal)HttpContext.Current.Items["genericPrincipal"];
                HttpContext.Current.Items["genericPrincipal"] = null;
                Thread.CurrentPrincipal = genericPrincipal;
                HttpContext.Current.User = genericPrincipal;
                try
                {
                    ((WindowsImpersonationContext)HttpContext.Current.Items["identity"]).Undo();
                }
                catch
                {
                }
            }
        }

        protected void Application_EndRequest(Object sender, EventArgs e)
        {

        }

        protected void Application_AuthenticateRequest(Object sender, EventArgs e)
        {

        }

        protected void Application_Error(Object sender, EventArgs e)
        {
            Exception exc = Server.GetLastError();
            if (exc == null)
                return;

            Exception root = exc.GetBaseException();
            string path = (Request.Path ?? "").ToLowerInvariant();
            bool isApi = path.IndexOf(".ashx") >= 0 || path.IndexOf(".asmx") >= 0;

            try
            {
                ExceptionUtility.LogException(exc, isApi ? "ApiHandler" : "DefaultPage");
                ExceptionUtility.NotifySystemOps(exc, isApi ? "ApiHandler" : "DefaultPage");
            }
            catch
            {
                // Never fail while handling an error.
            }

            // Handler may have already written JSON (e.g. pdf-edit save succeeded).
            if (Response.HeadersWritten)
            {
                Server.ClearError();
                return;
            }

            try
            {
                Response.Clear();
                Response.TrySkipIisCustomErrors = true;

                HttpException httpEx = exc as HttpException ?? root as HttpException;
                if (httpEx != null)
                {
                    if (httpEx.Message.Contains("NoCatch") || httpEx.Message.Contains("maxUrlLength"))
                    {
                        Server.ClearError();
                        return;
                    }

                    int code = httpEx.GetHttpCode();
                    if (code < 400)
                        code = 500;

                    if (isApi)
                    {
                        Response.ContentType = "application/json; charset=utf-8";
                        Response.StatusCode = code;
                        Response.Write("{\"ok\":false,\"error\":" + JsonQuote(httpEx.Message) + "}");
                    }
                    else
                    {
                        // Do not Server.Transfer — it fails when the source page has <% %> blocks.
                        Response.ContentType = "text/html; charset=utf-8";
                        Response.StatusCode = code;
                        Response.Write("<h2>HTTP Error</h2><p>" + Server.HtmlEncode(httpEx.Message) + "</p>");
                    }
                    Server.ClearError();
                    return;
                }

                if (isApi)
                {
                    Response.ContentType = "application/json; charset=utf-8";
                    Response.StatusCode = 500;
                    Response.Write("{\"ok\":false,\"error\":" + JsonQuote(root.Message) + "}");
                }
                else
                {
                    Response.ContentType = "text/html; charset=utf-8";
                    Response.Write("<h2>Global Page Error</h2>\n");
                    Response.Write("<p>" + Server.HtmlEncode(root.Message) + "</p>\n");
                    string siteName = (Application["site_name"] != null) ? Application["site_name"].ToString() : "/mics/";
                    Response.Write("Return to the <a href='" + siteName + "relogin.aspx?reason=2'>" + "Login Page</a>\n");
                }
                Server.ClearError();
            }
            catch
            {
                try { Server.ClearError(); } catch { }
            }
        }

        private static string JsonQuote(string value)
        {
            if (value == null)
                return "\"\"";
            return "\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n") + "\"";
        }

        /*  revised version of Session_end follows
         *  protected void Session_End(Object sender, EventArgs e)
        {
            try   // use try block to avoid case where we arrive here (probably due to abort) with no session info
            {
                if (Session["CloseReason"].ToString() == "T") // timeout
                {
                    // only write logging info if FCSASESS not 0
                    // value of 0 indicates user already logged out
                    if (Session["Active"].ToString() == "T")
                    {
                        string sesend = Application["web_drive"].ToString() + "\\perflogs\\sesend.txt";  // continuous log file for session ends
                        StreamWriter swse = new StreamWriter(sesend, true);

                        DateTime curTime = DateTime.Now;
                        string log_time = curTime.ToString("yyyy/MM/dd HH:mm:ss");

                        swse.WriteLine(log_time);
                        swse.WriteLine(Session["FCSASESS"].ToString());
                        swse.WriteLine(Session["CloseReason"].ToString());
                        swse.WriteLine(Session["Active"].ToString());

                        SessionInfo si = new SessionInfo(Session["s_user"].ToString(),
                            Session["s_schema"].ToString(),
                            Session["FCSASESS"].ToString(),
                            Session.SessionID.ToString(),
                            Session["CloseReason"].ToString(),
                            Session.Timeout.ToString(),
                            Session["ProjStart"].ToString(),
                            Session["s_cnString"].ToString(),
                            Session["defProject"].ToString(),
                            (WindowsPrincipal)Session["principalw"]);

                        char[] delimiter = ",".ToCharArray();

                        // remove entry from Application[sessions,uusers,musers]
                        Application.Lock();
                        swse.WriteLine("Before:" + Application["sessions"].ToString());
                        swse.Flush();
                        string[] loc_session_array = Application["sessions"].ToString().Split(delimiter);
                        string[] loc_uuser_array = Application["uusers"].ToString().Split(delimiter);
                        string[] loc_muser_array = Application["musers"].ToString().Split(delimiter);

                        Application["sessions"] = "";
                        Application["uusers"] = "";
                        Application["musers"] = "";
                        string comma = "";

                        for (int i = 0; i < loc_session_array.Length; i++)
                        {
                            swse.WriteLine(loc_session_array[i] + ":" + si.sesSID);
                            swse.Flush();
                            if (loc_session_array[i] != si.sesSID)
                            {
                                Application["sessions"] = Application["sessions"] + comma + loc_session_array[i];
                                Application["uusers"] = Application["uusers"] + comma + loc_uuser_array[i];
                                Application["musers"] = Application["musers"] + comma + loc_muser_array[i];
                                comma = ",";
                            }
                        }
                        Application.UnLock();
                        swse.WriteLine("After:" + Application["sessions"].ToString());

                        Session["CloseReason"] = "T"; // closereason = T for timeout
                        SesUtils.LogSessionEnd(Application["web_drive"].ToString(), si);
                    }
                }

                if (Session["CloseReason"].ToString() == "L") // logout 
                {
                    SesUtils.LogSessionEnd(Application["web_drive"].ToString(), si);
                    Session["Active"] = "F";  // this is reset to T after a successful login
                }
            }
            catch
            {
                
            }
        }
        */
        protected void Session_End(Object sender, EventArgs e)
        {
            try   // use try block to avoid case where we arrive here (probably due to abort) with no session info
            {
                // dummy asignment that will fail if there is no active session
                string treason = Session["CloseReason"].ToString();
            }
            catch
            {
                // there is no session info to log, so just return
                return;
            }

            // get current time
            DateTime curTime = DateTime.Now;

            // if session closing due to timeout subtract 20 min from current time
            if (Session["CloseReason"].ToString() == "T") // timeout
            {
                // set 20 min timespan 
                TimeSpan ts = new TimeSpan(0, 20, 0);
                // subtract 20 mins from current time
                curTime = DateTime.Now.Subtract(ts);
            }

            // only write logging info if Session["Active"] is T

            if (Session["Active"].ToString() == "T")
            {

                string sesend = Application["web_drive"].ToString() + "\\perflogs\\sesend.txt";  // continuous log file for session ends
                StreamWriter swse = new StreamWriter(sesend, true);

                string log_time = curTime.ToString("yyyy/MM/dd HH:mm:ss");

                swse.WriteLine(log_time);
                swse.WriteLine(Session["FCSASESS"].ToString());
                swse.WriteLine(Session["CloseReason"].ToString());
                swse.WriteLine(Session["Active"].ToString());

                SessionInfo si = new SessionInfo(Session["s_user"].ToString(),
                    Session["s_schema"].ToString(),
                    Session["FCSASESS"].ToString(),
                    Session.SessionID.ToString(),
                    Session["CloseReason"].ToString(),
                    Session.Timeout.ToString(),
                    Session["ProjStart"].ToString(),
                    Session["s_cnString"].ToString(),
                    Session["defProject"].ToString(),
                    Session["principalw"] as WindowsPrincipal);

                char[] delimiter = ",".ToCharArray();

                // remove entry from Application[sessions,uusers,musers]
                Application.Lock();
                swse.WriteLine("Before:" + Application["sessions"].ToString());
                swse.Flush();
                string[] loc_session_array = Application["sessions"].ToString().Split(delimiter);
                string[] loc_uuser_array = Application["uusers"].ToString().Split(delimiter);
                string[] loc_muser_array = Application["musers"].ToString().Split(delimiter);

                Application["sessions"] = "";
                Application["uusers"] = "";
                Application["musers"] = "";
                string comma = "";

                for (int i = 0; i < loc_session_array.Length; i++)
                {
                    swse.WriteLine(loc_session_array[i] + ":" + si.sesSID);
                    swse.Flush();
                    if (loc_session_array[i] != si.sesSID)
                    {
                        Application["sessions"] = Application["sessions"] + comma + loc_session_array[i];
                        Application["uusers"] = Application["uusers"] + comma + loc_uuser_array[i];
                        Application["musers"] = Application["musers"] + comma + loc_muser_array[i];
                        comma = ",";
                    }
                }
                Application.UnLock();
                swse.WriteLine("After:" + Application["sessions"].ToString());
                swse.Close();

                if (Session["CloseReason"].ToString() == "L") // logout 
                {
                    Session["Active"] = "F";  // this is reset to T after a successful login
                }
                SesUtils.LogSessionEnd(Application["web_drive"].ToString(), si);
            }
        }
        protected void Application_End(Object sender, EventArgs e)
        {
            StreamWriter swsae = null;
            try
            {
                if (Application["web_drive"] == null)
                    return;

                string badlogins = Application["web_drive"].ToString() + "\\perflogs\\badlogins.txt";  // continuous log file for bad logins
                string badlogin = Application["web_drive"].ToString() + "\\perflogs\\badlogin.txt";  // temp log file for max 5 bad logins
                swsae = new StreamWriter(badlogins, true);

                DateTime curTime = DateTime.Now;
                string log_time = curTime.ToString("yyyy/MM/dd HH:mm:ss");

                // email fcsa with any oustanding bad login messages for this application run
                // and log this activity in cumulative login error file
                if (File.Exists(badlogin))
                {
                    if (gmailbadlogin() == true)
                    {
                        swsae.WriteLine(log_time + " Email notice sent: Application End");
                        try { File.Delete(badlogin); } catch { }
                    }
                    else
                    {
                        swsae.WriteLine(log_time + " ERROR SENDING EMAIL NOTICE: Application End");
                    }
                }
            }
            catch
            {
                // Never throw during application shutdown (recycle / idle / config change).
            }
            finally
            {
                if (swsae != null)
                {
                    try { swsae.Close(); } catch { }
                }
            }
        }
        private bool gmailbadlogin()
        {
            // this routine sends emails of failed logins logged during last IIS application run
            // this information was accumulated in the file  <webdrive>/perflogs/badlogin.txt
            string loginPath = Application["web_drive"].ToString() + "\\perflogs\\badlogin.txt";
            if (!File.Exists(loginPath))
                return false;

            MailMessage Message = new MailMessage();
            Attachment loginfile = null;
            try
            {
                Message.Subject = "LOGIN FAILURES";
                Message.Body = "The attached file lists the unsent failed login attempts for the last application";
                loginfile = new Attachment(loginPath);
                Message.Attachments.Add(loginfile);
                return SesUtils.send_email_message2(Message, 1, true);
            }
            catch
            {
                return false;
            }
            finally
            {
                if (loginfile != null)
                {
                    try { loginfile.Dispose(); } catch { }
                }
            }
        }
        private static void RaiseLastError()
        {
            int errorCode = Marshal.GetLastWin32Error();
            //string errorMessage = GetErrorMessage(
            //errorCode );
            //throw new ApplicationException( errorMessage );
        }

        #region Web Form Designer generated code
        /// <summary>
        /// Required method for Designer support - do not modify
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            this.components = new System.ComponentModel.Container();
        }
        #endregion
    }
}

