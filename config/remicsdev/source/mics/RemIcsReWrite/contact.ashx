<%@ WebHandler Language="C#" Class="RemIcsReWrite.ContactHandler" %>

using System;
using System.Collections.Generic;
using System.Data.Odbc;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;

namespace RemIcsReWrite
{
    /// <summary>
    /// Contact update for the signed-in user. Managers (same company) and FCSA can edit employees.
    /// Writes dbo.t_UserDetails and both adm.account_details / adm.pcn_account_details.
    /// </summary>
    public class ContactHandler : IHttpHandler, IRequiresSessionState
    {
        private static readonly JavaScriptSerializer Ser = new JavaScriptSerializer();
        private static readonly Regex EmailOk = new Regex(@"^[^@\s]+@[^@\s]+\.[^@\s]+$", RegexOptions.IgnoreCase);
        private static readonly Regex MicsIdOk = new Regex(@"^[A-Za-z0-9_]{1,10}$");

        public bool IsReusable { get { return false; } }

        public void ProcessRequest(HttpContext context)
        {
            var response = context.Response;
            var session = context.Session;
            response.ContentType = "application/json; charset=utf-8";
            response.Cache.SetCacheability(HttpCacheability.NoCache);

            if (session == null || session["s_cnString"] == null || session["s_schema"] == null || session["s_user"] == null)
            {
                response.StatusCode = 401;
                WriteJson(response, new { ok = false, error = "Session not initialized." });
                return;
            }

            string action = (context.Request["action"] ?? "get").Trim().ToLowerInvariant();
            if (action == "list") { HandleList(context); return; }
            if (action == "get") { HandleGet(context); return; }
            if (action == "set") { HandleSet(context); return; }
            response.StatusCode = 400;
            WriteJson(response, new { ok = false, error = "Unknown action." });
        }

        private static void HandleList(HttpContext context)
        {
            string actor = context.Session["s_user"].ToString().Trim();
            string schema = context.Session["s_schema"].ToString().Trim();
            string cnstr = context.Session["s_cnString"].ToString();
            var people = new List<object>();
            bool isManager = false;
            bool isFcsa = false;

            using (var cn = new OdbcConnection(cnstr))
            {
                cn.Open();
                ReadFlags(cn, actor, out isManager, out isFcsa);
                string sql = "SELECT RTRIM(micsId), RTRIM(ISNULL(FirstName,'')), RTRIM(ISNULL(LastName,'')), " +
                    "RTRIM(ISNULL(email,'')), RTRIM(ISNULL(ultrixid,'')), RTRIM(ISNULL(PrimarySchema,'')) " +
                    "FROM dbo.t_UserDetails WHERE RTRIM(IsActiveYN) = 'Y' ";
                if (!isFcsa)
                    sql += "AND (RTRIM(ultrixid) = '" + Esc(schema) + "' OR RTRIM(PrimarySchema) = '" + Esc(schema) + "') ";
                if (!isManager && !isFcsa)
                    sql += "AND RTRIM(micsId) = '" + Esc(actor) + "' ";
                sql += "ORDER BY micsId";

                using (var cmd = new OdbcCommand(sql, cn))
                using (var dr = cmd.ExecuteReader())
                {
                    while (dr.Read())
                    {
                        string mid = GetStr(dr, 0);
                        if (mid.Length == 0) continue;
                        string fn = GetStr(dr, 1);
                        string ln = GetStr(dr, 2);
                        string em = GetStr(dr, 3);
                        string label = mid;
                        if (fn.Length > 0 || ln.Length > 0) label += "  -  " + (fn + " " + ln).Trim();
                        people.Add(new
                        {
                            micsid = mid,
                            firstName = fn,
                            lastName = ln,
                            email = em,
                            display = label,
                            isSelf = string.Equals(mid, actor, StringComparison.OrdinalIgnoreCase)
                        });
                    }
                }
            }

            WriteJson(context.Response, new
            {
                ok = true,
                actor = actor,
                isManager = isManager,
                isFcsa = isFcsa,
                canEditOthers = isManager || isFcsa,
                people = people
            });
        }

        private static void HandleGet(HttpContext context)
        {
            string actor = context.Session["s_user"].ToString().Trim();
            string schema = context.Session["s_schema"].ToString().Trim();
            string cnstr = context.Session["s_cnString"].ToString();
            string target;
            if (!TryRequestMicsId(context, actor, out target))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Invalid MICS ID." });
                return;
            }

            using (var cn = new OdbcConnection(cnstr))
            {
                cn.Open();
                string deny;
                string targetSchema;
                if (!CanEdit(cn, actor, schema, target, out targetSchema, out deny))
                {
                    context.Response.StatusCode = 403;
                    WriteJson(context.Response, new { ok = false, error = deny });
                    return;
                }
                WriteContact(context.Response, cn, actor, schema, target, targetSchema);
            }
        }

        private static void HandleSet(HttpContext context)
        {
            string actor = context.Session["s_user"].ToString().Trim();
            string schema = context.Session["s_schema"].ToString().Trim();
            string cnstr = context.Session["s_cnString"].ToString();
            string target;
            if (!TryRequestMicsId(context, actor, out target))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Invalid MICS ID." });
                return;
            }

            string email = (context.Request["email"] ?? "").Trim();
            string email2 = (context.Request["emailConfirm"] ?? "").Trim();
            string phone = Clip((context.Request["phone"] ?? "").Trim(), 15);
            string mobile = Clip((context.Request["mobile"] ?? "").Trim(), 15);
            bool sendPcnOn = ParseYn(context.Request["sendPcn"]);
            string sendPcn = sendPcnOn ? "y" : "n";

            if (email.Length == 0 || !EmailOk.IsMatch(email) || email.Length > 128)
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Enter a valid email address." });
                return;
            }
            if (email2.Length == 0 || !string.Equals(email, email2, StringComparison.OrdinalIgnoreCase))
            {
                context.Response.StatusCode = 400;
                WriteJson(context.Response, new { ok = false, error = "Email and confirmation must match." });
                return;
            }

            var updated = new StringBuilder();
            StreamWriter sw = TryOpenExtractLog(context, actor + "ContactUpdate.txt");
            try
            {
                if (sw != null)
                {
                    sw.WriteLine("LOGTIME:" + DateTime.Now.ToString("yyyyMMddHHmmss.ffff"));
                    sw.WriteLine("ACTOR:" + actor + " TARGET:" + target + " SCHEMA:" + schema);
                    sw.WriteLine("EMAIL:" + email + " SEND_PCN:" + sendPcn);
                }

                using (var cn = new OdbcConnection(cnstr))
                {
                    cn.Open();
                    string deny;
                    string targetSchema;
                    if (!CanEdit(cn, actor, schema, target, out targetSchema, out deny))
                    {
                        context.Response.StatusCode = 403;
                        WriteJson(context.Response, new { ok = false, error = deny });
                        return;
                    }

                    int nUd = Exec(cn,
                        "UPDATE dbo.t_UserDetails SET email = '" + Esc(email) + "', " +
                        "PhoneNumber = '" + Esc(phone) + "', MobilePhoneNumber = '" + Esc(mobile) + "' " +
                        "WHERE RTRIM(micsId) = '" + Esc(target) + "' AND RTRIM(IsActiveYN) = 'Y'");
                    if (nUd > 0) updated.Append("t_UserDetails");
                    if (sw != null) sw.WriteLine("t_UserDetails rows=" + nUd);

                    UpsertAdm(cn, "adm.account_details", targetSchema, target, email, sendPcn, sw, updated);
                    UpsertAdm(cn, "adm.pcn_account_details", targetSchema, target, email, sendPcn, sw, updated);

                    if (updated.Length == 0)
                    {
                        context.Response.StatusCode = 400;
                        WriteJson(context.Response, new { ok = false, error = "No matching user row was found to update. Please contact FCSA." });
                        return;
                    }
                    WriteContact(context.Response, cn, actor, schema, target, targetSchema, "Contact information saved.");
                }
            }
            catch (Exception ex)
            {
                try { if (sw != null) sw.WriteLine("ERROR:" + ex.Message); } catch { }
                context.Response.StatusCode = 500;
                WriteJson(context.Response, new { ok = false, error = ex.Message });
            }
            finally
            {
                if (sw != null)
                {
                    try { sw.Flush(); sw.Close(); } catch { }
                }
            }
        }

        private static void WriteContact(HttpResponse response, OdbcConnection cn, string actor, string actorSchema,
            string target, string targetSchema)
        {
            WriteContact(response, cn, actor, actorSchema, target, targetSchema, null);
        }

        private static void WriteContact(HttpResponse response, OdbcConnection cn, string actor, string actorSchema,
            string target, string targetSchema, string message)
        {
            string firstName = "", lastName = "", emailUd = "", phone = "", mobile = "";
            string emailAdm = "", sendPcnAdm = "";
            string emailPcn = "", sendPcnPcn = "";
            bool hasUd = false, hasAdm = false, hasPcn = false;
            bool isManager, isFcsa;
            ReadFlags(cn, actor, out isManager, out isFcsa);

            using (var cmd = new OdbcCommand(
                "SELECT RTRIM(ISNULL(FirstName,'')), RTRIM(ISNULL(LastName,'')), RTRIM(ISNULL(email,'')), " +
                "RTRIM(ISNULL(PhoneNumber,'')), RTRIM(ISNULL(MobilePhoneNumber,'')) " +
                "FROM dbo.t_UserDetails WHERE RTRIM(micsId) = '" + Esc(target) + "' AND RTRIM(IsActiveYN) = 'Y'", cn))
            using (var dr = cmd.ExecuteReader())
            {
                if (dr.Read())
                {
                    hasUd = true;
                    firstName = GetStr(dr, 0);
                    lastName = GetStr(dr, 1);
                    emailUd = GetStr(dr, 2);
                    phone = GetStr(dr, 3);
                    mobile = GetStr(dr, 4);
                }
            }
            ReadAdmRow(cn, "adm.account_details", targetSchema, target, out emailAdm, out sendPcnAdm, out hasAdm);
            ReadAdmRow(cn, "adm.pcn_account_details", targetSchema, target, out emailPcn, out sendPcnPcn, out hasPcn);

            string email = FirstNonEmpty(emailUd, emailAdm, emailPcn);
            string sendPcn = FirstNonEmpty(sendPcnPcn, sendPcnAdm, "y");
            bool sendPcnOn = string.Equals(sendPcn, "y", StringComparison.OrdinalIgnoreCase);

            WriteJson(response, new
            {
                ok = true,
                message = message,
                actor = actor,
                micsid = target,
                ultrixid = targetSchema,
                isSelf = string.Equals(target, actor, StringComparison.OrdinalIgnoreCase),
                isManager = isManager,
                isFcsa = isFcsa,
                canEditOthers = isManager || isFcsa,
                email = email,
                phone = phone,
                mobile = mobile,
                firstName = firstName,
                lastName = lastName,
                sendPcn = sendPcnOn,
                hasUserDetails = hasUd,
                hasAccountDetails = hasAdm,
                hasPcnAccountDetails = hasPcn
            });
        }

        private static bool TryRequestMicsId(HttpContext context, string actor, out string target)
        {
            string raw = (context.Request["micsid"] ?? "").Trim();
            if (raw.Length == 0)
            {
                target = actor;
                return true;
            }
            if (!MicsIdOk.IsMatch(raw))
            {
                target = "";
                return false;
            }
            target = raw;
            return true;
        }

        private static StreamWriter TryOpenExtractLog(HttpContext context, string fileName)
        {
            try
            {
                string drive = "D:";
                if (context != null && context.Application["web_drive"] != null)
                {
                    string w = context.Application["web_drive"].ToString();
                    if (!string.IsNullOrEmpty(w)) drive = w;
                }
                string dir = Path.Combine(drive, "extractlogs");
                Directory.CreateDirectory(dir);
                return new StreamWriter(Path.Combine(dir, fileName), true);
            }
            catch
            {
                return null;
            }
        }

        private static bool CanEdit(OdbcConnection cn, string actor, string actorSchema, string target,
            out string targetSchema, out string deny)
        {
            targetSchema = actorSchema;
            deny = "";
            if (!MicsIdOk.IsMatch(target ?? ""))
            {
                deny = "Invalid MICS ID.";
                return false;
            }
            if (string.Equals(actor, target, StringComparison.OrdinalIgnoreCase))
            {
                targetSchema = ResolveUserSchema(cn, target, actorSchema);
                return true;
            }
            bool isManager, isFcsa;
            ReadFlags(cn, actor, out isManager, out isFcsa);
            if (!isManager && !isFcsa)
            {
                deny = "Only a company manager can edit another user's contact information.";
                return false;
            }
            targetSchema = ResolveUserSchema(cn, target, actorSchema);
            if (isFcsa) return true;
            if (!string.Equals(targetSchema, actorSchema, StringComparison.OrdinalIgnoreCase))
            {
                deny = "Managers can only edit users in their own company.";
                return false;
            }
            return true;
        }

        private static string ResolveUserSchema(OdbcConnection cn, string micsid, string fallback)
        {
            using (var cmd = new OdbcCommand(
                "SELECT RTRIM(ISNULL(ultrixid,'')), RTRIM(ISNULL(PrimarySchema,'')) FROM dbo.t_UserDetails " +
                "WHERE RTRIM(micsId) = '" + Esc(micsid) + "' AND RTRIM(IsActiveYN) = 'Y'", cn))
            using (var dr = cmd.ExecuteReader())
            {
                if (dr.Read())
                {
                    string u = GetStr(dr, 0);
                    string p = GetStr(dr, 1);
                    if (u.Length > 0) return u;
                    if (p.Length > 0) return p;
                }
            }
            return fallback;
        }

        private static void ReadFlags(OdbcConnection cn, string micsid, out bool isManager, out bool isFcsa)
        {
            isManager = false;
            isFcsa = false;
            using (var cmd = new OdbcCommand(
                "SELECT RTRIM(ISNULL(IsManagerYN,'N')), RTRIM(ISNULL(IsFCSAYN,'N')) FROM dbo.t_UserDetails " +
                "WHERE RTRIM(micsId) = '" + Esc(micsid) + "' AND RTRIM(IsActiveYN) = 'Y'", cn))
            using (var dr = cmd.ExecuteReader())
            {
                if (dr.Read())
                {
                    isManager = string.Equals(GetStr(dr, 0), "Y", StringComparison.OrdinalIgnoreCase);
                    isFcsa = string.Equals(GetStr(dr, 1), "Y", StringComparison.OrdinalIgnoreCase);
                }
            }
        }

        private static void UpsertAdm(OdbcConnection cn, string table, string schema, string user,
            string email, string sendPcn, StreamWriter sw, StringBuilder updated)
        {
            int n = Exec(cn,
                "UPDATE " + table + " SET email = '" + Esc(email) + "', send_pcn = '" + Esc(sendPcn) + "' " +
                "WHERE RTRIM(ultrixid) = '" + Esc(schema) + "' AND RTRIM(micsid) = '" + Esc(user) + "'");
            if (n == 0)
            {
                n = Exec(cn,
                    "INSERT INTO " + table + " (ultrixid, micsid, email, send_pcn, tsip_email, auto_delete) " +
                    "VALUES ('" + Esc(schema) + "','" + Esc(user) + "','" + Esc(email) + "','" + Esc(sendPcn) + "','y','n')");
                if (sw != null) sw.WriteLine(table + " inserted=" + n);
            }
            else if (sw != null) sw.WriteLine(table + " updated=" + n);
            if (n > 0)
            {
                if (updated.Length > 0) updated.Append(",");
                updated.Append(table);
            }
        }

        private static void ReadAdmRow(OdbcConnection cn, string table, string schema, string user,
            out string email, out string sendPcn, out bool found)
        {
            email = "";
            sendPcn = "";
            found = false;
            using (var cmd = new OdbcCommand(
                "SELECT RTRIM(ISNULL(email,'')), RTRIM(ISNULL(send_pcn,'')) FROM " + table +
                " WHERE RTRIM(ultrixid) = '" + Esc(schema) + "' AND RTRIM(micsid) = '" + Esc(user) + "'", cn))
            using (var dr = cmd.ExecuteReader())
            {
                if (dr.Read())
                {
                    found = true;
                    email = GetStr(dr, 0);
                    sendPcn = GetStr(dr, 1);
                }
            }
        }

        private static int Exec(OdbcConnection cn, string sql)
        {
            using (var cmd = new OdbcCommand(sql, cn))
                return cmd.ExecuteNonQuery();
        }

        private static string FirstNonEmpty(params string[] vals)
        {
            if (vals == null) return "";
            for (int i = 0; i < vals.Length; i++)
            {
                if (!string.IsNullOrWhiteSpace(vals[i])) return vals[i].Trim();
            }
            return "";
        }

        private static bool ParseYn(string raw)
        {
            raw = (raw ?? "").Trim();
            return raw == "1" || raw == "y" || raw == "Y" || string.Equals(raw, "true", StringComparison.OrdinalIgnoreCase);
        }

        private static string Clip(string s, int max)
        {
            if (s == null) return "";
            return s.Length <= max ? s : s.Substring(0, max);
        }

        private static string GetStr(OdbcDataReader dr, int i)
        {
            if (dr.IsDBNull(i)) return "";
            return (dr[i] ?? "").ToString().Trim();
        }

        private static string Esc(string s)
        {
            return (s ?? "").Replace("'", "''");
        }

        private static void WriteJson(HttpResponse response, object payload)
        {
            response.Write(Ser.Serialize(payload));
        }
    }
}
