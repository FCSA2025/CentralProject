<%@ WebHandler Language="C#" Class="RemIcsReWriteProjectsHandler" %>

using System;
using System.Collections.Generic;
using System.Data;
using System.Data.Odbc;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.SessionState;
using SesUtilities;

/// <summary>JSON project list + optional POST to set Session defProject.</summary>
public class RemIcsReWriteProjectsHandler : IHttpHandler, IRequiresSessionState
{
    public bool IsReusable { get { return false; } }

    public void ProcessRequest(HttpContext context)
    {
        var response = context.Response;
        var request = context.Request;
        response.ContentType = "application/json; charset=utf-8";
        response.Cache.SetCacheability(HttpCacheability.NoCache);

        if (context.Session == null || context.Session["s_cnString"] == null || context.Session["s_user"] == null)
        {
            response.StatusCode = 401;
            WriteJson(response, new { ok = false, error = "Session not initialized." });
            return;
        }

        if (string.Equals(request.HttpMethod, "POST", StringComparison.OrdinalIgnoreCase))
        {
            HandleSetProject(context);
            return;
        }

        string sesUser = context.Session["s_user"].ToString();
        string cnstr = context.Session["s_cnString"].ToString();
        string sql;
        if (MicsDbAuth.IsEnabled())
        {
            sql = "SELECT RTRIM(pcode) AS pcode, RTRIM(defaultcode) AS defaultcode " +
                  "FROM adm.project_ids " +
                  "WHERE RTRIM(micsid) = '" + sesUser.Replace("'", "''") + "' " +
                  "ORDER BY pcode";
        }
        else
        {
            sql = "SELECT pcode, defaultcode FROM adm.project_ids_view ORDER BY pcode";
        }

        var projects = new List<object>();
        string defaultProject = null;
        try
        {
            using (var cn = new OdbcConnection(cnstr))
            using (var da = new OdbcDataAdapter(sql, cn))
            {
                var dt = new DataTable();
                da.Fill(dt);
                for (int i = 0; i < dt.Rows.Count; i++)
                {
                    string pcode = dt.Rows[i]["pcode"].ToString().Trim();
                    string def = dt.Rows[i]["defaultcode"].ToString().Trim();
                    if (i == 0) defaultProject = pcode;
                    if (def == "*") defaultProject = pcode;
                    projects.Add(new { pcode = pcode, defaultcode = def });
                }
            }
        }
        catch (Exception ex)
        {
            response.StatusCode = 500;
            WriteJson(response, new { ok = false, error = ex.Message });
            return;
        }

        if (string.IsNullOrEmpty(defaultProject) && context.Session["defProject"] != null)
            defaultProject = context.Session["defProject"].ToString();

        if (!string.IsNullOrEmpty(defaultProject))
            context.Session["defProject"] = defaultProject;

        WriteJson(response, new
        {
            ok = true,
            projects = projects,
            current = defaultProject
        });
    }

    private void HandleSetProject(HttpContext context)
    {
        var response = context.Response;
        string pcode = (context.Request.Form["pcode"] ?? context.Request.QueryString["pcode"] ?? "").Trim();
        if (string.IsNullOrEmpty(pcode))
        {
            response.StatusCode = 400;
            WriteJson(response, new { ok = false, error = "Missing pcode." });
            return;
        }

        context.Session["defProject"] = pcode;
        WriteJson(response, new { ok = true, current = pcode });
    }

    private static void WriteJson(HttpResponse response, object data)
    {
        response.Write(new JavaScriptSerializer().Serialize(data));
    }
}
