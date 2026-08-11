<%@ WebHandler Language="C#" Class="UpdatePipelineListHandler" %>

using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;

/// <summary>
/// List DbUpdate staging files in D:\updates\primary and in-flight job folders.
/// Merges last validate-all results from validate-cache.json when present.
/// Merges inbox processing registry rows from registry-cache.json when present.
/// </summary>
public class UpdatePipelineListHandler : IHttpHandler
{
    private const string PrimaryRoot = @"D:\updates\primary";
    private const string WorkDir = @"E:\AIProjects\CentralProject";
    private static readonly Regex StagingPattern = new Regex(
        @"^([A-Za-z0-9]+)_(\d{10})_(.+)\.txt$", RegexOptions.Compiled | RegexOptions.IgnoreCase);
    private static readonly Regex PlainPattern = new Regex(
        @"^([A-Za-z0-9_]{1,16})\.txt$", RegexOptions.Compiled | RegexOptions.IgnoreCase);
    private static readonly Regex JobIdPattern = new Regex(
        @"^[a-fA-F0-9]{32}$", RegexOptions.Compiled);

    public bool IsReusable { get { return false; } }

    public void ProcessRequest(HttpContext context)
    {
        var response = context.Response;
        response.ContentType = "application/json; charset=utf-8";
        response.Cache.SetCacheability(HttpCacheability.NoCache);

        try
        {
            string adminDir = Path.GetDirectoryName(context.Request.PhysicalPath);
            if (string.IsNullOrEmpty(adminDir))
                adminDir = @"D:\inetpub\fcsa\admin";

            var validateCache = LoadValidateCache(Path.Combine(adminDir, "update-pipeline", "validate-cache.json"));
            var registryCache = LoadRegistryCache(Path.Combine(adminDir, "update-pipeline", "registry-cache.json"));

            var inbox = new List<object>();
            CollectInbox(inbox, PrimaryRoot, "TS", validateCache, registryCache);
            CollectInbox(inbox, Path.Combine(PrimaryRoot, "UnprocessedESFiles"), "ES", validateCache, registryCache);

            var inflight = new List<object>();
            CollectJobs(inflight, Path.Combine(PrimaryRoot, "processing"), "processing", registryCache);
            CollectJobs(inflight, Path.Combine(PrimaryRoot, "errors"), "errors", registryCache);
            CollectJobs(inflight, Path.Combine(PrimaryRoot, "failed"), "failed", registryCache);

            var payload = new
            {
                ok = true,
                primary_root = PrimaryRoot,
                ts_inbox = PrimaryRoot,
                es_inbox = Path.Combine(PrimaryRoot, "UnprocessedESFiles"),
                errors_root = Path.Combine(PrimaryRoot, "errors"),
                failed_root = Path.Combine(PrimaryRoot, "failed"),
                fixture_root = Path.Combine(WorkDir, "tests", "remicsdev", "fixtures", "files", "updates-primary"),
                inbox = inbox,
                inflight = inflight,
                validate_cache = validateCache != null ? validateCache.Summary : null,
                registry_cache = registryCache != null ? registryCache.Summary : null,
                registry_rows = registryCache != null ? registryCache.Rows : null
            };
            response.Write(new JavaScriptSerializer().Serialize(payload));
        }
        catch (Exception ex)
        {
            response.StatusCode = 500;
            response.Write(new JavaScriptSerializer().Serialize(new { ok = false, error = ex.Message }));
        }
    }

    private class ValidateCacheData
    {
        public Dictionary<string, object> Files = new Dictionary<string, object>();
        public object Summary;
    }

    private class RegistryCacheData
    {
        public Dictionary<string, Dictionary<string, object>> ByStagingFile = new Dictionary<string, Dictionary<string, object>>();
        public List<object> Rows = new List<object>();
        public object Summary;
    }

    private static ValidateCacheData LoadValidateCache(string cachePath)
    {
        if (!File.Exists(cachePath)) return null;
        try
        {
            string json = File.ReadAllText(cachePath);
            var ser = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
            var root = ser.DeserializeObject(json) as Dictionary<string, object>;
            if (root == null) return null;

            var data = new ValidateCacheData();
            object filesObj;
            if (root.TryGetValue("files", out filesObj))
            {
                var filesDict = filesObj as Dictionary<string, object>;
                if (filesDict != null)
                    data.Files = filesDict;
            }

            data.Summary = new
            {
                job_id = GetString(root, "job_id"),
                updated_utc = GetString(root, "updated_utc"),
                completed_utc = GetString(root, "completed_utc"),
                passed = GetInt(root, "passed"),
                failed = GetInt(root, "failed"),
                files_total = GetInt(root, "files_total")
            };
            return data;
        }
        catch
        {
            return null;
        }
    }

    private static RegistryCacheData LoadRegistryCache(string cachePath)
    {
        if (!File.Exists(cachePath)) return null;
        try
        {
            string json = File.ReadAllText(cachePath);
            var ser = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
            var root = ser.DeserializeObject(json) as Dictionary<string, object>;
            if (root == null) return null;

            var data = new RegistryCacheData();
            object rowsObj;
            if (root.TryGetValue("rows", out rowsObj))
            {
                var rows = rowsObj as ArrayList;
                if (rows != null)
                {
                    foreach (var rowObj in rows)
                    {
                        var row = rowObj as Dictionary<string, object>;
                        if (row == null) continue;
                        data.Rows.Add(row);
                        string stagingFile = GetString(row, "staging_file");
                        if (!string.IsNullOrEmpty(stagingFile))
                            data.ByStagingFile[stagingFile] = row;
                    }
                }
            }

            data.Summary = new
            {
                updated_utc = GetString(root, "updated_utc"),
                row_count = data.Rows.Count
            };
            return data;
        }
        catch
        {
            return null;
        }
    }

    private static string GetString(Dictionary<string, object> d, string key)
    {
        object v;
        return d.TryGetValue(key, out v) && v != null ? v.ToString() : "";
    }

    private static int GetInt(Dictionary<string, object> d, string key)
    {
        object v;
        if (!d.TryGetValue(key, out v) || v == null) return 0;
        int n;
        return int.TryParse(v.ToString(), out n) ? n : 0;
    }

    private static void CollectInbox(List<object> items, string dir, string filetype, ValidateCacheData validateCache, RegistryCacheData registryCache)
    {
        if (!Directory.Exists(dir)) return;
        foreach (var fi in new DirectoryInfo(dir).GetFiles("*.txt"))
        {
            var meta = ParseName(fi.Name);
            object validation = null;
            if (validateCache != null && validateCache.Files.ContainsKey(fi.Name))
                validation = validateCache.Files[fi.Name];

            object registry = null;
            if (registryCache != null && registryCache.ByStagingFile.ContainsKey(fi.Name))
                registry = registryCache.ByStagingFile[fi.Name];

            items.Add(new
            {
                name = fi.Name,
                path = fi.FullName,
                filetype = meta != null && !string.IsNullOrEmpty(meta.Filetype) ? meta.Filetype : filetype,
                submitter = meta != null ? meta.Submitter : "",
                pdfname = meta != null ? meta.Pdfname : fi.Name,
                bytes = fi.Length,
                modified_utc = fi.LastWriteTimeUtc.ToString("o"),
                validation = validation,
                registry = registry
            });
        }
    }

    private static void CollectJobs(List<object> items, string root, string state, RegistryCacheData registryCache)
    {
        if (!Directory.Exists(root)) return;
        foreach (var jobDir in new DirectoryInfo(root).GetDirectories())
        {
            if (!JobIdPattern.IsMatch(jobDir.Name)) continue;
            string stagingName = null;
            string stagingPath = null;
            foreach (var fi in jobDir.GetFiles("*.txt"))
            {
                stagingName = fi.Name;
                stagingPath = fi.FullName;
                break;
            }
            var meta = stagingName != null ? ParseName(stagingName) : null;
            object registry = null;
            if (registryCache != null && stagingName != null && registryCache.ByStagingFile.ContainsKey(stagingName))
                registry = registryCache.ByStagingFile[stagingName];
            items.Add(new
            {
                job_id = jobDir.Name,
                state = state,
                staging_file = stagingName,
                staging_path = stagingPath,
                submitter = meta != null ? meta.Submitter : "",
                pdfname = meta != null ? meta.Pdfname : stagingName,
                modified_utc = jobDir.LastWriteTimeUtc.ToString("o"),
                registry = registry
            });
        }
    }

    private class Meta
    {
        public string Submitter;
        public string Pdfname;
        public string Filetype;
    }

    private static Meta ParseName(string fileName)
    {
        var m = StagingPattern.Match(fileName);
        if (m.Success)
        {
            return new Meta { Submitter = m.Groups[1].Value, Pdfname = m.Groups[3].Value, Filetype = null };
        }
        m = PlainPattern.Match(fileName);
        if (m.Success)
        {
            return new Meta { Submitter = "", Pdfname = m.Groups[1].Value, Filetype = null };
        }
        return null;
    }
}

