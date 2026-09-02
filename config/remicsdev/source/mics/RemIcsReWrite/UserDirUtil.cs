using System;
using System.IO;

namespace RemIcsReWrite
{
    /// <summary>Resolve session user_dir to the on-disk path (canonical NTFS casing).</summary>
    public static class UserDirUtil
    {
        public static string Canonicalize(string userDir)
        {
            if (string.IsNullOrWhiteSpace(userDir))
                return userDir;

            userDir = userDir.Trim();
            try
            {
                if (Directory.Exists(userDir))
                    return new DirectoryInfo(userDir).FullName.TrimEnd('\\') + "\\";
            }
            catch
            {
                // fall through
            }

            return userDir.EndsWith("\\") ? userDir : userDir + "\\";
        }

        public static string SqlMicsUserEquals(string columnExpr, string user)
        {
            string u = (user ?? "").Trim().Replace("'", "''");
            return "RTRIM(" + columnExpr + ") COLLATE Latin1_General_CI_AI = '" + u + "' COLLATE Latin1_General_CI_AI";
        }
    }
}
