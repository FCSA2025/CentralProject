<%@ WebHandler Language="C#" Class="RemIcsReWrite.PwdRecoveryHandler" %>
<%@ Assembly Name="System.Security, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a" %>

using System;
using System.Data;
using System.Data.SqlClient;
using System.Security.Cryptography;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>
    /// Logged-in password-recovery Q/A setup. Writes dbo.resetqa with windowsid = micsid
    /// (insertqa uses SQL USER, which is the app pool under UseDbAuth).
    /// Crypto matches RemIcsReWrite/pwd-reset.aspx and classic Maintenance/pwdqa.aspx.
    /// </summary>
    public class PwdRecoveryHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly JavaScriptSerializer Ser = new JavaScriptSerializer();
        private static readonly byte[] AdditionalEntropy = { 23, 17, 41, 57, 71 };
        private const int SaltSize = 10;

        public bool IsReusable { get { return false; } }

        public void ProcessRequest(HttpContext context)
        {
            var response = context.Response;
            response.ContentType = "application/json; charset=utf-8";
            response.Cache.SetCacheability(HttpCacheability.NoCache);

            if (context.Session == null || context.Session["s_user"] == null)
            {
                response.StatusCode = 401;
                WriteJson(response, new { ok = false, error = "Session not initialized." });
                return;
            }

            string action = (context.Request["action"] ?? "setup").Trim().ToLowerInvariant();
            if (action != "setup")
            {
                WriteJson(response, new { ok = false, error = "Unknown action." });
                return;
            }

            if (!MicsDbAuth.IsEnabled())
            {
                WriteJson(response, new { ok = false, error = "Password recovery requires database authentication (UseDbAuth)." });
                return;
            }

            string uid = context.Session["s_user"].ToString().Trim();
            if (uid.Length > 10) uid = uid.Substring(0, 10);

            string fixedQ = (context.Request["fixedQuestion"] ?? "").Trim();
            string fixedA = (context.Request["fixedAnswer"] ?? "").Trim();
            string userQ = (context.Request["userQuestion"] ?? "").Trim();
            string userA = (context.Request["userAnswer"] ?? "").Trim();

            if (fixedQ.Length == 0 || userQ.Length == 0
                || string.IsNullOrEmpty(fixedA) || string.IsNullOrEmpty(userA))
            {
                WriteJson(response, new { ok = false, code = "missing", error = "All four fields must have a value" });
                return;
            }
            if (fixedQ.Length > 32 || userQ.Length > 32 || fixedA.Length > 32 || userA.Length > 32)
            {
                WriteJson(response, new { ok = false, code = "length", error = "Each field must be 32 characters or fewer." });
                return;
            }

            try
            {
                try { SesUtils.LogMenuUse("SetPwdRecovery"); } catch { }

                byte[] encryptFq = ProtectedData.Protect(GetBytes(fixedQ), AdditionalEntropy, DataProtectionScope.LocalMachine);
                byte[] encryptUq = ProtectedData.Protect(GetBytes(userQ), AdditionalEntropy, DataProtectionScope.LocalMachine);

                byte[] salt = new byte[SaltSize];
                using (var rng = new RNGCryptoServiceProvider())
                    rng.GetBytes(salt);

                byte[] hashFa;
                byte[] hashUa;
                using (var sha = new SHA256Managed())
                {
                    hashFa = sha.ComputeHash(SaltAnswer(salt, fixedA));
                    hashUa = sha.ComputeHash(SaltAnswer(salt, userA));
                }

                using (SqlConnection cn = new SqlConnection(MicsDbAuth.GetSqlClientConnectionString()))
                {
                    cn.Open();
                    string email = LookupEmail(cn, context, uid);
                    if (string.IsNullOrWhiteSpace(email))
                    {
                        WriteJson(response, new
                        {
                            ok = false,
                            code = "noemail",
                            error = "You do not have an e-mail address set up in the Mics database. Please contact FCSA to have one added."
                        });
                        return;
                    }

                    SaveQa(cn, uid, encryptFq, hashFa, encryptUq, hashUa, salt);

                    bool userQueued = SesUtils.InsertEmailQueue("mics@fcsa.ca", email, null,
                        "MICS password reset info update",
                        "The password reset questions and answers for user " + uid + " were updated successfully.\n"
                        + "If you did not make these changes please contact FCSA immediately",
                        null);
                    bool fcsaQueued = SesUtils.send_email_sql(null, null, null,
                        "MICS password reset info update",
                        "The password reset questions and answers for user " + uid + " were updated successfully.",
                        null, 1, false);

                    if (!userQueued || !fcsaQueued)
                    {
                        WriteJson(response, new
                        {
                            ok = true,
                            saved = true,
                            email = false,
                            user = uid,
                            message = "Information saved but e-mail failed. Please contact FCSA."
                        });
                        return;
                    }

                    WriteJson(response, new
                    {
                        ok = true,
                        saved = true,
                        email = true,
                        user = uid,
                        message = "Information saved and E-mail sent"
                    });
                }
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        static void SaveQa(SqlConnection cn, string uid, byte[] fq, byte[] fa, byte[] uq, byte[] ua, byte[] salt)
        {
            const string sql = @"
SET NOCOUNT ON;
IF EXISTS (SELECT 1 FROM dbo.resetqa WHERE windowsid = @id)
BEGIN
    UPDATE dbo.resetqa
    SET fixed_questione = @fq, fixed_answere = @fa,
        user_questione = @uq, user_answere = @ua,
        salt = @salt, reset_count = reset_count + 1, try_count = 0
    WHERE windowsid = @id;
END
ELSE
BEGIN
    INSERT INTO dbo.resetqa
        (windowsid, fixed_questione, fixed_answere, user_questione, user_answere, salt, reset_count, try_count)
    VALUES
        (@id, @fq, @fa, @uq, @ua, @salt, 0, 0);
END";
            using (SqlCommand cmd = new SqlCommand(sql, cn))
            {
                cmd.Parameters.Add("@id", SqlDbType.VarChar, 10).Value = uid;
                cmd.Parameters.Add("@fq", SqlDbType.VarBinary, 500).Value = fq;
                cmd.Parameters.Add("@fa", SqlDbType.VarBinary, 500).Value = fa;
                cmd.Parameters.Add("@uq", SqlDbType.VarBinary, 500).Value = uq;
                cmd.Parameters.Add("@ua", SqlDbType.VarBinary, 500).Value = ua;
                cmd.Parameters.Add("@salt", SqlDbType.VarBinary, 500).Value = salt;
                cmd.ExecuteNonQuery();
            }
        }

        // W3-3: after selectemail, prefer schema-scoped adm lookup (micsid + ultrixid).
        static string LookupEmail(SqlConnection cn, HttpContext context, string uid)
        {
            using (SqlCommand cmd = new SqlCommand("select email from dbo.selectemail(@id)", cn))
            {
                cmd.Parameters.Add("@id", SqlDbType.VarChar, 32).Value = uid;
                object result = cmd.ExecuteScalar();
                if (result != null && result != DBNull.Value)
                {
                    string e = result.ToString().Trim();
                    if (e.Length > 0) return e;
                }
            }
            string ultrix = "";
            if (context.Session != null && context.Session["s_schema"] != null)
                ultrix = context.Session["s_schema"].ToString().Trim();
            foreach (string table in EmailTables(context))
            {
                string sql = ultrix.Length > 0
                    ? "SELECT TOP 1 RTRIM(email) FROM " + table +
                      " WHERE RTRIM(micsid) = @id AND RTRIM(ultrixid) = @ultrix"
                    : "SELECT TOP 1 RTRIM(email) FROM " + table + " WHERE RTRIM(micsid) = @id";
                using (SqlCommand cmd = new SqlCommand(sql, cn))
                {
                    cmd.Parameters.Add("@id", SqlDbType.VarChar, 32).Value = uid;
                    if (ultrix.Length > 0)
                        cmd.Parameters.Add("@ultrix", SqlDbType.VarChar, 32).Value = ultrix;
                    object result = cmd.ExecuteScalar();
                    if (result != null && result != DBNull.Value)
                    {
                        string e = result.ToString().Trim();
                        if (e.Length > 0) return e;
                    }
                }
            }
            using (SqlCommand cmd = new SqlCommand(
                "SELECT TOP 1 RTRIM(email) FROM dbo.t_UserDetails WHERE RTRIM(micsId) = @id AND RTRIM(IsActiveYN) = 'Y'", cn))
            {
                cmd.Parameters.Add("@id", SqlDbType.VarChar, 32).Value = uid;
                object result = cmd.ExecuteScalar();
                return result == null || result == DBNull.Value ? "" : result.ToString().Trim();
            }
        }

        static string[] EmailTables(HttpContext context)
        {
            string site = "";
            if (context.Session != null)
            {
                if (context.Session["SiteName"] != null) site = context.Session["SiteName"].ToString();
                else if (context.Session["siteName"] != null) site = context.Session["siteName"].ToString();
            }
            if (site.IndexOf("remicsdev", StringComparison.OrdinalIgnoreCase) >= 0
                || site.IndexOf("micstest", StringComparison.OrdinalIgnoreCase) >= 0)
                return new[] { "adm.pcn_account_details", "adm.account_details" };
            return new[] { "adm.account_details", "adm.pcn_account_details" };
        }

        static byte[] SaltAnswer(byte[] salt, string answer)
        {
            byte[] raw = GetBytes(answer);
            byte[] salted = new byte[salt.Length + raw.Length];
            Buffer.BlockCopy(salt, 0, salted, 0, salt.Length);
            Buffer.BlockCopy(raw, 0, salted, salt.Length, raw.Length);
            return salted;
        }

        static byte[] GetBytes(string instr)
        {
            byte[] bytes = new byte[instr.Length * 2];
            Buffer.BlockCopy(instr.ToCharArray(), 0, bytes, 0, instr.Length * 2);
            return bytes;
        }

        static void WriteJson(HttpResponse response, object payload)
        {
            response.Write(Ser.Serialize(payload));
        }
    }
}
