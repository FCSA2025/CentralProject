using _Configuration;
using _NewLib;
using System;
using System.Collections.Generic;
using System.Configuration;
using System.Data.Odbc;
using System.IO;
using System.Text.RegularExpressions;

namespace _Utillib
{
    /// <summary>
    /// Queues outbound member email via adm.t_EmailQueue / adm.t_EmailQueue_local
    /// (same contract as TsipEmail / SesUtils.InsertEmailQueue). Used by PFDcont.
    /// </summary>
    public static class MicsEmail
    {
        // This regex to verify an email address string assumes that the text is in LOWER CASE.
        private const string VALID_EMAIL_ADDRESS_PATTERN = @"(?:[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*)@(?:(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)";

        public static int ValidateEmailParameters(string to, string subject, string body, List<string> attachmentFilePaths)
        {
            int retVal = Constant.SUCCESS;

            if (!IsValidEmailAddress(to))
            {
                retVal = Error.INVALIDEMAILADDRESS;
                TsipQ.WriteToTsipLog("\nMicsEmail.ValidateEmailParameters(): ERROR: " + Error.MsgForCode(retVal));
                return retVal;
            }

            if (String.IsNullOrWhiteSpace(subject))
            {
                retVal = Error.EMAILSUBJECTMISSING;
                TsipQ.WriteToTsipLog("\nMicsEmail.ValidateEmailParameters(): ERROR: " + Error.MsgForCode(retVal));
                return retVal;
            }

            if (body == null)
            {
                retVal = Error.EMAILBODYMISSING;
                TsipQ.WriteToTsipLog("\nMicsEmail.ValidateEmailParameters(): ERROR: " + Error.MsgForCode(retVal));
                return retVal;
            }

            if (attachmentFilePaths == null)
            {
                retVal = Error.EMAILATTACHMENTFILELISTISNULL;
                TsipQ.WriteToTsipLog("\nMicsEmail.ValidateEmailParameters(): ERROR: " + Error.MsgForCode(retVal));
                return retVal;
            }

            foreach (string filePath in attachmentFilePaths)
            {
                if (!File.Exists(filePath))
                {
                    Log2.e("\n\nMicsEmail.ValidateEmailParameters(): ERROR: call to File.Exists() returned FALSE for filePath = " + filePath);
                    TsipQ.WriteToTsipLog("\nMicsEmail.ValidateEmailParameters(): ERROR: call to File.Exists() returned FALSE for filePath = " + filePath);
                    return Error.EMAILATTACHMENTINVALIDFILEPATH;
                }
            }

            return retVal;
        }

        public static bool IsValidEmailAddress(string emailAddress)
        {
            if (String.IsNullOrWhiteSpace(emailAddress)) return false;
            return Regex.IsMatch(emailAddress.ToLower(), VALID_EMAIL_ADDRESS_PATTERN);
        }

        /// <summary>
        /// Queue one email with optional attachments (semicolon paths staged for SQL Agent).
        /// Preferred entry point for batch programs (PFDcont Products.SendEmail).
        /// </summary>
        public static int SendSql(string to, string subject, string body, string attachmentFilePath, out string errMsg)
        {
            List<string> paths = new List<string>();
            if (!String.IsNullOrWhiteSpace(attachmentFilePath))
                paths.Add(attachmentFilePath);
            return SendSql(to, subject, body, paths, out errMsg);
        }

        public static int SendSql(string to, string subject, string body, List<string> attachmentFilePaths, out string errMsg)
        {
            errMsg = "";
            if (attachmentFilePaths == null) attachmentFilePaths = new List<string>();
            if (body == null) body = "";

            int errorCode = ValidateEmailParameters(to, subject, body, attachmentFilePaths);
            if (errorCode != Constant.SUCCESS)
            {
                errMsg = Error.MsgForCode(errorCode);
                Log2.e("\n\nMicsEmail.SendSql(): ERROR: " + errMsg);
                return errorCode;
            }

            try
            {
                string mailTo = to;
                string mailCC = null;
                string redirectTo = ConfigurationManager.AppSettings["EmailRedirectAllTo"];
                if (!String.IsNullOrWhiteSpace(redirectTo))
                {
                    body = body + "\n\nOriginal recipients: To=" + (mailTo ?? "") + " CC=";
                    mailTo = redirectTo.Trim().Replace(',', ';');
                    mailCC = null;
                }

                string filelist = String.Join(";", attachmentFilePaths.ToArray());
                string stagedAttach = StageAttachmentsForSqlAgent(filelist);
                if (!String.IsNullOrWhiteSpace(filelist) && String.IsNullOrWhiteSpace(stagedAttach))
                {
                    errMsg = "Failed to stage email attachments for SQL Agent (check D:\\MicsEmailStaging and App.config UNC root).";
                    Log2.e("\n\nMicsEmail.SendSql(): ERROR: " + errMsg);
                    return Error.EMAILSENDATTEMPTFAILED;
                }

                string attachSql = String.IsNullOrWhiteSpace(stagedAttach) ? "NULL" : "'" + EscapeSql(stagedAttach) + "'";
                string ccSql = String.IsNullOrWhiteSpace(mailCC) ? "NULL" : "'" + EscapeSql(mailCC) + "'";
                string queueTable = GetEmailQueueTable();

                if (String.IsNullOrWhiteSpace(Info.DbName))
                {
                    errMsg = "Info.DbName is not set; cannot INSERT email queue row.";
                    Log2.e("\n\nMicsEmail.SendSql(): ERROR: " + errMsg);
                    return Error.EMAILSENDATTEMPTFAILED;
                }

                string cnstr = String.Format("DSN={0};DATABASE={0};Trusted_Connection=yes", Info.DbName);
                string strSql = "INSERT INTO " + queueTable +
                    " (mailFrom, mailTo, mailCC, mailSubject, mailBody, mailBodyFormat, mailAttachments, sentYN) " +
                    " VALUES ('mics@fcsa.ca','" + EscapeSql(mailTo) + "'," + ccSql +
                    ",'" + EscapeSql(subject) + "','" + EscapeSql(body) + "','TEXT'," + attachSql + ",'N')";

                using (OdbcConnection cn = new OdbcConnection(cnstr))
                {
                    cn.Open();
                    using (OdbcCommand cmd = new OdbcCommand(strSql, cn))
                    {
                        int rows = cmd.ExecuteNonQuery();
                        if (rows != 1)
                        {
                            errMsg = "Email queue INSERT affected " + rows + " rows (expected 1).";
                            Log2.e("\n\nMicsEmail.SendSql(): ERROR: " + errMsg);
                            return Error.EMAILSENDATTEMPTFAILED;
                        }
                    }
                }

                return Constant.SUCCESS;
            }
            catch (Exception e)
            {
                errMsg = e.Message;
                Log2.e("\n\nMicsEmail.SendSql(): ERROR: exception: " + e.Message);
                Log2.e("\n" + e.StackTrace);
                TsipQ.WriteToTsipLog("\n\nMicsEmail.SendSql(): ERROR: exception: " + e.Message + "\n" + e.StackTrace);
                return Error.EMAILSENDATTEMPTFAILED;
            }
        }

        /// <summary>
        /// Legacy entry used by deployed PFDcont.exe; now queues via SendSql (was a no-op).
        /// </summary>
        public static int Send(string to, string subject, string body, List<string> attachmentFilePaths, bool addTxtExtn, out string errMsg)
        {
            // addTxtExtn unused for queue path (attachments keep real names for SQL Agent).
            return SendSql(to, subject, body, attachmentFilePaths, out errMsg);
        }

        public static int Send(string to, string subject, string body, List<string> attachmentFilePaths, out string errMsg)
        {
            return Send(to, subject, body, attachmentFilePaths, false, out errMsg);
        }

        public static int Send(string to, string subject, string body, out string errMsg)
        {
            errMsg = "";
            return Send(to, subject, body, new List<string>(), false, out errMsg);
        }

        public static int Send(string to, string subject, string body, string attachmentFilePath, out string errMsg)
        {
            errMsg = "";
            List<string> attachFilePaths = new List<string>();
            attachFilePaths.Add(attachmentFilePath);
            return Send(to, subject, body, attachFilePaths, false, out errMsg);
        }

        private static string GetEmailQueueTable()
        {
            string v = ConfigurationManager.AppSettings["EmailQueueTable"];
            if (String.IsNullOrWhiteSpace(v))
                return "adm.t_EmailQueue";
            v = v.Trim();
            if (v == "adm.t_EmailQueue" || v == "adm.t_EmailQueue_local")
                return v;
            return "adm.t_EmailQueue";
        }

        private static string StageAttachmentsForSqlAgent(string semicolonPaths)
        {
            if (String.IsNullOrWhiteSpace(semicolonPaths)) return null;

            string stageRoot = ConfigurationManager.AppSettings["EmailAttachStagingRoot"];
            if (String.IsNullOrWhiteSpace(stageRoot))
                stageRoot = @"D:\MicsEmailStaging";
            stageRoot = stageRoot.TrimEnd('\\');

            string uncRoot = ConfigurationManager.AppSettings["EmailAttachStagingUncRoot"];
            if (String.IsNullOrWhiteSpace(uncRoot))
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

            return staged.Count == 0 ? null : String.Join(";", staged.ToArray());
        }

        private static string EscapeSql(string value)
        {
            if (value == null) return "";
            return value.Replace("'", "''");
        }
    }
}
