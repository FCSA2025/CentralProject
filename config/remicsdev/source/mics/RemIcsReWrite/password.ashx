<%@ WebHandler Language="C#" Class="RemIcsReWrite.PasswordHandler" %>

using System;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>
    /// Logged-in change password — same MicsDbAuth.SetPassword path as classic loginPassword.aspx.
    /// </summary>
    public class PasswordHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly JavaScriptSerializer Ser = new JavaScriptSerializer();

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

            string action = (context.Request["action"] ?? "change").Trim().ToLowerInvariant();
            if (action != "change")
            {
                WriteJson(response, new { ok = false, error = "Unknown action." });
                return;
            }

            string uid = context.Session["s_user"].ToString();
            string oldPwd = context.Request["oldPassword"] ?? "";
            string newPwd = context.Request["newPassword"] ?? "";

            if (string.IsNullOrEmpty(oldPwd) || string.IsNullOrEmpty(newPwd))
            {
                WriteJson(response, new { ok = false, code = "missing", error = "Enter current and new password." });
                return;
            }
            if (newPwd.Length < 8)
            {
                WriteJson(response, new { ok = false, code = "policy", error = "New password must be at least 8 characters." });
                return;
            }
            if (string.Equals(oldPwd, newPwd, StringComparison.Ordinal))
            {
                WriteJson(response, new { ok = false, code = "same", error = "New password must be different from current password." });
                return;
            }

            if (!MicsDbAuth.IsEnabled())
            {
                WriteJson(response, new { ok = false, error = "DB auth is not enabled; use classic Change Password." });
                return;
            }

            try
            {
                if (!MicsDbAuth.VerifyPassword(uid, oldPwd))
                {
                    WriteJson(response, new { ok = false, code = "badold", error = "The specified Current Password is not correct." });
                    return;
                }
                if (!MicsDbAuth.SetPassword(uid, newPwd))
                {
                    WriteJson(response, new { ok = false, code = "setfail", error = "Failed to update password." });
                    return;
                }
                context.Session["s_password"] = newPwd;
                WriteJson(response, new { ok = true, user = uid, reLogin = true });
            }
            catch (Exception ex)
            {
                response.StatusCode = 500;
                WriteJson(response, new { ok = false, error = ex.Message });
            }
        }

        private static void WriteJson(HttpResponse response, object payload)
        {
            response.Write(Ser.Serialize(payload));
        }
    }
}
