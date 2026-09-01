using _Configuration;
using _NewLib;
using System;
using System.Collections.Generic;
using System.Configuration;
using System.Data.Odbc;
using System.IO;
using System.Text;

namespace TsipInitiator
{
    /// <summary>
    /// This class provides private members and public methods that encapsulate
    /// the data and functionality required to send an email to a WebMICS user
    /// whose attachments are TSIP output reports.
    /// </summary>
    public static class TsipEmail
    {
        private static string mTsipFileFolder;
        private static string mTsipFileRoot;
        private static string mEmailAddress;
        private static string mDelFlag;
        private static List<string> mRuns;

        public static string TsipFileFolder
        {
            get { return mTsipFileFolder; }
            set { mTsipFileFolder = value; }
        }
        public static string TsipFileRoot
        {
            get { return mTsipFileRoot; }
            set { mTsipFileRoot = value; }
        }
        public static string EmailAddress
        {
            get { return mEmailAddress; }
            set { mEmailAddress = value; }
        }
        public static string DelFlag
        {
            get { return mDelFlag; }
            set { mDelFlag = value; }
        }
        public static List<string> Runs
        {
            get { return mRuns; }
            set { mRuns = value; }
        }

        /// <summary>
        /// This is the private static class constructor; it initializes all private
        /// string members to empty strings and instantiates a list of string that
        /// will hold the TSIP paramater file 'run' names.
        /// </summary>
        static TsipEmail()
        {
            mTsipFileFolder = "";
            mTsipFileRoot = "";
            mEmailAddress = "";
            mDelFlag = "";
            mRuns = new List<string>();
        }

        /// <summary>
        /// This method returns true if the currently set values of the email parameters
        /// are all valid.
        /// </summary>
        /// <returns></returns>
        public static bool EmailParametersAreValid()
        {
            bool result = true;

            if (
                String.IsNullOrWhiteSpace(mTsipFileFolder) ||
                String.IsNullOrWhiteSpace(mTsipFileRoot) ||
                String.IsNullOrWhiteSpace(mEmailAddress) ||
                String.IsNullOrWhiteSpace(mDelFlag) ||
                mRuns == null ||
                mRuns.Count == 0
                )
            {
                result = false;
            }

            return result;
        }

        /// <summary>
        /// This method returns an annotated, formatted, multi-line string that
        /// provides the current values of the static class's members.
        /// </summary>
        /// <returns></returns>
        public new static string ToString()
        {
            StringBuilder sb = new StringBuilder();

            sb.Append("\ntsipFileFolder = " + mTsipFileFolder);
            sb.Append("\ntsipFileRoot   = " + mTsipFileRoot);
            sb.Append("\nemailAddress   = " + mEmailAddress);
            sb.Append("\ndelFlag        = " + mDelFlag);

            if (mRuns == null)
            {
                sb.Append("\nRuns           = NULL");
            }
            else if (mRuns.Count == 0)
            {
                sb.Append("\nRuns           = Is empty.");
            }
            else
            {
                int n = 0;
                foreach (string run in mRuns)
                {
                    sb.Append(String.Format("\n    run[{0}] = {1}", n++, run));
                }
            }

            return sb.ToString();
        }

               
        /// <summary>
        /// This method implements the sending of TSIP result reports to the user's
        /// email address using SQL email server.
        /// </summary>
        /// <param name="errMsg"></param>
        /// <returns></returns>
        public static int Send(out string errMsg)
        {
            // 'out' requirement.
            errMsg = "";

            string subject = "";
            string body = "";

            int retVal = Constant.SUCCESS;

            // set up log file
            StreamWriter sw = new StreamWriter(@"d:\MicsBatchLogs\TsipEmail.log");
            
            try
            {
                bool IsDel;
                string cBodyfile = "";
                List<FileInfo> fiDeleteList = new List<FileInfo>();

                DateTime theNu = DateTime.Now;
                sw.WriteLine("\nSending TSIP reports to user via email with timestamp: {0}", theNu);

                if (mDelFlag == "D")
                {
                    //	The tsip run was deleted while executing or queued.
                }
                else
                {
                    cBodyfile = mTsipFileFolder + "\\" + mTsipFileRoot + ".ERR";
                    if (File.Exists(cBodyfile))
                    {
                        sw.WriteLine("\nSending files:- {0}\n", mTsipFileFolder + "\\" + mTsipFileRoot + "_" + mRuns[0]);
                    }
                    else
                    {
                        errMsg = String.Format("Could not find files for: {0}", mTsipFileFolder + "\\" + mTsipFileRoot + "_" + mRuns[0]);
                        sw.WriteLine("\n\n{0}\n", errMsg);
                        return 126;
                    }
                }

                // Specify the message content.
                StreamReader BodyFile = new StreamReader(cBodyfile);
                body = BodyFile.ReadToEnd();
                BodyFile.Close();

                // Construct a list of strings whose elements are paths to files to be
                // attached to the email.
                //List<string> attachmentFilePaths = new List<string>();

                // Construct a string to hold a list ofsemicolon separated file paths
                StringBuilder filelist = new StringBuilder("", 100);

                // Scan the body for the name of the first file in the err report
                int nInd = body.IndexOf("Proposed Name...........:") + 26;
                //	Now find the end of the file name.
                const int FILE_LENGTH = 32;
                char[] end_chars = { ' ', '\u000D', '\u000A' };
                int nInd1 = body.IndexOfAny(end_chars, nInd, nInd + FILE_LENGTH);
                if (nInd1 == -1)
                {
                    nInd1 = nInd + FILE_LENGTH;
                }
                String cFileName = body.Substring(nInd, nInd1 - nInd);

                if (mDelFlag != "D")
                {
                    subject = "TSIP output for " + mTsipFileRoot + ", first filename: " + cFileName + " at " + theNu.ToString();

                    IsDel = mDelFlag.ToUpper() == "Y";
                    DirectoryInfo dDir = new DirectoryInfo(mTsipFileFolder);
                    if (dDir.Exists)
                    {
                        int nEndmark = mTsipFileRoot.Length;
                        string semicolon = "";

                        foreach (string run in mRuns)
                        {
                            FileInfo[] fiDirFiles = dDir.GetFiles(mTsipFileRoot + "_" + run + ".*");
                            foreach (FileInfo fiFile in fiDirFiles)
                            {
                                string str = fiFile.FullName;

                                filelist.Append(semicolon + fiFile.FullName);
                                semicolon = ";";
                                Log2.v(filelist.ToString() + "\n");

                                if (IsDel)
                                {
                                    fiDeleteList.Add(fiFile);
                                }
                            }
                        }
                        if (IsDel)
                        {
                            fiDeleteList.Add(new FileInfo(cBodyfile));
                        }
                        body = "No Errors";
                    }
                    else
                    {
                        //	Send the err file anyway.
                        body = "No files found, this is the .ERR file:-\n\n";
                        BodyFile = new StreamReader(cBodyfile);
                        body = BodyFile.ReadToEnd();
                        //body = "No Errors";
                        BodyFile.Close();
                    }
                }
                else
                {
                    subject = "TSIP Run for " + mTsipFileRoot + " DELETED.";
                    body = "See Subject.";
                }


                string mailTo = mEmailAddress;
                string mailCC = null;
                string redirectTo = ConfigurationManager.AppSettings["EmailRedirectAllTo"];
                if (!string.IsNullOrWhiteSpace(redirectTo))
                {
                    body = body + "\n\nOriginal recipients: To=" + (mailTo ?? "") + " CC=";
                    mailTo = redirectTo.Trim().Replace(',', ';');
                    mailCC = null;
                }

                sw.WriteLine("To: " + mailTo);
                sw.WriteLine("Subject: " + subject);
                sw.WriteLine("Body: " + body);
                sw.WriteLine("Source files: " + filelist);

                string stagedAttach = StageAttachmentsForSqlAgent(filelist.ToString());
                if (!string.IsNullOrWhiteSpace(filelist.ToString()) && string.IsNullOrWhiteSpace(stagedAttach))
                {
                    errMsg = "Failed to stage TSIP attachments for SQL Agent (check D:\\MicsEmailStaging and App.config UNC root).";
                    sw.WriteLine(errMsg);
                    sw.WriteLine("Unstaged source files: " + filelist);
                    return 127;
                }

                string attachSql = string.IsNullOrWhiteSpace(stagedAttach) ? "NULL" : "'" + EscapeSql(stagedAttach) + "'";
                string queueTable = GetEmailQueueTable();

                sw.WriteLine("Staged attachments: " + (stagedAttach ?? "(none)"));

                // insert record into local email queue (UNC paths under MicsEmailStaging for SQL Agent)
                try
                {
                    string cnstr = String.Format("DSN={0};DATABASE={0};Trusted_Connection=yes", Info.DbName);
                    sw.WriteLine("Connection=" + cnstr);

                    string ccSql = string.IsNullOrWhiteSpace(mailCC) ? "NULL" : "'" + EscapeSql(mailCC) + "'";
                    string strSql = "INSERT INTO " + queueTable +
                        " (mailFrom, mailTo, mailCC, mailSubject, mailBody, mailBodyFormat, mailAttachments, sentYN) " +
                        " VALUES ('mics@fcsa.ca','" + EscapeSql(mailTo) + "'," + ccSql +
                        ",'" + EscapeSql(subject) + "','" + EscapeSql(body) + "','TEXT'," + attachSql + ",'N')";
                    sw.WriteLine(strSql);

                    using (OdbcConnection cn = new OdbcConnection(cnstr))
                    {
                        cn.Open();
                        using (OdbcCommand addemail = new OdbcCommand(strSql, cn))
                        {
                            retVal = addemail.ExecuteNonQuery();
                        }
                        sw.WriteLine("Rows inserted=" + retVal);
                    }
                    sw.Close();
                    if (retVal != 1)
                    {
                        string msg = String.Format("\n\nTsipEmail.Send(): ERROR: call to MicsEmail.Send() FAILED, retVal = {0}\n{1}", retVal, Error.MsgForCode(retVal));
                        Log2.e(msg);
                    }

                    //if (fiDeleteList.Count() > 0)
                    //{
                    //    foreach (FileInfo fi in fiDeleteList)
                    //    {
                    //	The delete switch was set.  We have to save the file names and delete them
                    //	after sending because they are not included in the message until they are
                    //	sent, and so are kept open and locked.
                    //        fi.Delete();
                    //    }
                    //    sw.WriteLine("Deleted {0} files.", fiDeleteList.Count());
                    //}

                }
                catch (Exception ex)
                {
                    Log2.e("Error inserting tsip queue record: " + ex.Message);
                }
            }
            catch (Exception e)
            {
                retVal = 314259;
                Log2.e("\n\nTsipEmail.Send(): ERROR: exception: " + e.Message);
                errMsg = e.Message + "\n" + e.StackTrace;
                return retVal;
            }

            if (retVal == Constant.SUCCESS)
            {
                Console.WriteLine("\nEmail sent.");
                sw.WriteLine("\nEmail sent.");
                return retVal;
            }
            return Constant.SUCCESS;
        }

        /*
        public static bool send_email_sql(string ToAddress, string subject, string body, bool retval, out string errMsg)
        {
            string dbgfile = "D:\\MicsBatchLogs\\SendTsipEmailSql.txt";
            StreamWriter sw = new StreamWriter(dbgfile, false);
            DateTime logTime = DateTime.Now;
            sw.WriteLine("LOGTIME:" + logTime.ToString("yyyyMMddHHmmss.ffff"));

            // set mandatory FROM address
            string From = "mics@fcsa.ca";


            if (ToAddress.ToString() == "")
            {
                sw.WriteLine("ToAddress is empty");
                sw.Close();
                errMsg = "No ToAddress was specified";
                return false;
            }
            else
            {
                sw.WriteLine(ToAddress.ToString());
            }

            if (subject == "")
            {
                sw.WriteLine("Subject is empty");
                sw.Close();
                errMsg = "No Subject was specified";
                return false;
            }
            else
            {
                sw.WriteLine(subject);
            }

            if (body == "")
            {
                sw.WriteLine("body is empty");
                sw.Close();
                errMsg = "No body was specified";
                return false;
            }
            else
            {
                sw.WriteLine(body);
                sw.Flush();
            }

            string mailCC = "";
            
            // split attachment list from body
            string body1;
            string body2;
            int ATTptr;

            ATTptr = body.IndexOf("^^^");
            if (ATTptr == -1) // no attachments
            {
                body1 = body;
                body2 = "";
            }
            else
            {
                body1 = body.ToString().Substring(0, ATTptr);
                body2 = body.ToString().Substring(ATTptr + 3).Replace("^", ";");
            }

            body = body1;
            sw.WriteLine(body1);
            sw.WriteLine(body2);
            sw.Flush();
            string strSql;
                       
            try
            {
                string cnstr = "DSN=remicsdev;DATABASE=remicsdev;Trusted_Connection=yes";
                using (OdbcConnection cn = new OdbcConnection(cnstr))
                {
                    cn.Open();

                    strSql = "INSERT INTO adm.t_EmailQueue " +
                                " (mailFrom, mailTo, mailCC, mailSubject, mailBody, mailAttachments) " +
                                " VALUES ('mics@fcsa.ca" +
                                "','" + ToAddress +
                                "','" + subject +
                                "','" + mailCC +
                                "','" + body1 +
                                "','" + body2 + "')";

                    sw.WriteLine(strSql);
                    sw.Flush();

                }

                sw.Close();
                errMsg = "";
                return true;
            }
            catch (Exception em1)   // write error log and notify user
            {
                try
                {   sw.WriteLine("From:" + From);
                    sw.WriteLine("TO:" + ToAddress);
                    sw.WriteLine("CC:" + mailCC);
                    sw.WriteLine("mailSubject:" + subject);
                    sw.WriteLine("Body:" + body1);
                    sw.WriteLine("Attachments:" + body2);
                    sw.WriteLine("ERROR:" + em1.Message);
                    sw.WriteLine("");
                 }
                 catch (Exception ea)
                 {
                     sw.WriteLine("Error writing email info (send_email_message2):" + ea.Message);
                 }
  
                sw.Close();
                errMsg = em1.Message;
                return false;
            }
        
        }
        */
        private static string GetEmailQueueTable()
        {
            string v = ConfigurationManager.AppSettings["EmailQueueTable"];
            if (string.IsNullOrWhiteSpace(v))
                return "adm.t_EmailQueue";
            v = v.Trim();
            if (v == "adm.t_EmailQueue" || v == "adm.t_EmailQueue_local")
                return v;
            return "adm.t_EmailQueue";
        }

        private static string StageAttachmentsForSqlAgent(string semicolonPaths)
        {
            if (string.IsNullOrWhiteSpace(semicolonPaths)) return null;

            string stageRoot = ConfigurationManager.AppSettings["EmailAttachStagingRoot"];
            if (string.IsNullOrWhiteSpace(stageRoot))
                stageRoot = @"D:\MicsEmailStaging";
            stageRoot = stageRoot.TrimEnd('\\');

            string uncRoot = ConfigurationManager.AppSettings["EmailAttachStagingUncRoot"];
            if (string.IsNullOrWhiteSpace(uncRoot))
                uncRoot = @"\\IIS-REMICS-PROD\MicsEmailStaging";
            uncRoot = uncRoot.TrimEnd('\\');

            string stageDir = Path.Combine(stageRoot, DateTime.Now.ToString("yyyyMMddHHmmss") + "_" + Guid.NewGuid().ToString("N").Substring(0, 8));
            Directory.CreateDirectory(stageDir);

            var staged = new List<string>();
            foreach (string part in semicolonPaths.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries))
            {
                string src = part.Trim();
                if (src.Length == 0 || !File.Exists(src)) continue;
                string dest = Path.Combine(stageDir, Path.GetFileName(src));
                if (File.Exists(dest)) File.Delete(dest);
                File.Copy(src, dest);
                string queuePath = uncRoot + dest.Substring(stageRoot.Length);
                staged.Add(queuePath);
            }

            return staged.Count == 0 ? null : string.Join(";", staged);
        }

        private static string EscapeSql(string value)
        {
            if (value == null) return "";
            return value.Replace("'", "''");
        }
    }
}
