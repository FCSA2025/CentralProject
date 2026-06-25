using _Configuration;
using _DataStructures;
using _NewLib;
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace _Utillib
{
    using SQLHANDLE = IntPtr;
    using SQLHDBC = IntPtr;
    using SQLHSTMT = IntPtr;
    using SQLLEN = Int64;
    using SQLRETURN = Int16;

    /// <summary>One on-disk report file to cache into web.tsip_run_report_line.</summary>
    public class TsipArchiveReportFile
    {
        public string ReportType;
        public string FilePath;
    }

    /// <summary>Per-run archive state passed through the two-phase TpRunTsip hook.</summary>
    public class TsipArchiveContext
    {
        public long RunId;
        public string MicsUser;
        public string SourceSchema;
        public string ParmFile;
        public string RunName;
        public string ViewName;
        public string Protype;
        public bool IsTs;
        public string ParmTable;
        public string SiteTable;
        public string AnteTable;
        public string ChanTable;
        public string StatsumTable;
        public string StatsumEnvTable;
        public int NumIntCases;
        public int NumTeIntCases;
        public TpParm ParmStruct;

        internal readonly List<string> Warnings = new List<string>();
        internal bool RegistryInserted;
    }

    /// <summary>
    /// Archives TSIP run outputs into shared web.tsip_* tables (Phase 2).
    /// Failures are logged as warnings; they never abort the batch run.
    /// </summary>
    public static class TsipRunArchive
    {
        private const string TsSiteCols =
            "interferer,intcall1,intcall2,viccall1,viccall2,caseno,subcases,intname1,intname2,vicname1,vicname2," +
            "intoper,intoper2,vicoper,vicoper2,intlatit,intlongit,intgrnd,viclatit,viclongit,vicgrnd,report," +
            "int1int2dist,vic1vic2dist,int1vic1dist,distadv,intoffax,vicoffax,intvicaz,vicintaz,processed";

        private const string TsAnteCols =
            "interferer,intcall1,intcall2,intbndcde,intanum,viccall1,viccall2,vicbndcde,caseno,vicanum,intacode,vicacode," +
            "report,subcaseno,adiscctxh,adiscctxv,adisccrxh,adisccrxv,adiscxtxh,adiscxtxv,adiscxrxh,adiscxrxv,processed," +
            "intause,vicause,intoffaxa,vicoffaxa,intgain,vicgain,intaxref,intamodel,vicaxref,vicamodel,intaoffax,inthopaz," +
            "intantaz,intoffantax,vicaoffax,vichopaz,vicantaz,vicoffantax,intaht,vicaht,intvicel,vicintel,intelev,vicelev";

        private const string TsChanCols =
            "interferer,intcall1,intcall2,intbndcde,intanum,intchid,viccall1,viccall2,vicbndcde,vicanum,caseno,vicchid," +
            "intpolar,vicpolar,intstattx,vicstatrx,inttraftx,victrafrx,inteqpttx,viceqptrx,intfreqtx,vicfreqrx,vicpwrrx," +
            "intpwrtx,intafsltx,vicafslrx,rxant,txant,ctxinttraftx,ctxvictrafrx,ctxeqpt,calctype,report,totantdisc,freqsep," +
            "reqdcalc,patloss,calcico,calcixp,resti,eirpadv,tiltdisc,pathloss80,calcico80,calcixp80,reqd80,resti80," +
            "pathloss99,calcico99,calcixp99,reqd99,resti99,ohresult,rqco,processed,ctxinteqpt,inteqtype,viceqtype,intbwchans,vicbwchans";

        private const string ParmCols =
            "protype,envtype,proname,envname,tsorbout,spherecalc,fsep,coordist,analopt,margin,numchan,chancodes,tempant," +
            "tempctx,tempplan,tempequip,country,selsites,numcodes,codes,runname,reports,numcases,numtecases,parmparm,mdate,mtime";

        private const string TeSiteCols =
            "terrcall1,terrcall2,earthlocation,terrname1,terrname2,earthname,terroper,terroper2,earthoper,terrlatit," +
            "terrlongit,terrgrnd,earthlatit,earthlongit,earthgrnd,radiozone,rainzone,etreport,tereport,etcaseno,tecaseno," +
            "etsubcases,tesubcases,intreq,etdist,etazim,teazim,tudist,tuazim,utazim,eudist,euazim,ueazim,processed";

        private const string TeAnteCols =
            "interferer,terrcall1,terrcall2,terrbndcde,terranum,earthlocation,earthcall1,earthband,terracode,earthacode," +
            "satname,satoper,satlongit,txpre,txtro,rxpre,rxtro,sarc1,sarc2,mode1,mode2,intause,etreport,tereport,etsubcaseno," +
            "tesubcaseno,esazim,eselev,teelev,etelev,tuelev,utelev,euelev,ediscang,tdiscang,adisc_set,adisc_ute,terrht," +
            "earthht,tvazim,evazim,tvelev,evelev,tvdistes,tvdisttu,evdistes,evdisttu,angleutv,anglesev,tsoffaxis,tstrueaz," +
            "tstrueel,angleute,angleuta,angleeta,angleatv,adisc_atv,terragain,terramodel,terraxref,earthagain,earthamodel," +
            "earthaxref,processed";

        private const string TeChanCols =
            "interferer,terrcall1,terrcall2,terrbndcde,terranum,terrchid,earthlocation,earthcall1,earthchid,inttraftx,victrafrx," +
            "inteqpttx,viceqptrx,intfreqtx,inttxpwr,inttxpwr2,inttxafls,inttxafls2,vicrxafls,vicfreqrx,vicpwrrx,stattx,statrx," +
            "energy,etreport,tereport,ctxinttraftx,ctxvictrafrx,ctxeqpt,calctype,earthmdsc,terrmdsc,eartheirp,terreirp,freqsep," +
            "scang,loss20mode1,calci20mode1,loss01mode1,calci01mode1,loss01mode2,calci01mode2,reqd20mode1,reqd01mode1,reqd01mode2," +
            "marg20mode1,marg01mode1,marg01mode2,remterracode,remterragain,processed,terrant";

        public static TsipArchiveContext BuildContext(
            string parmFile,
            string viewName,
            TpParm parmStruct,
            bool isTs,
            string parmTable,
            string siteTable,
            string anteTable,
            string chanTable,
            int numIntCases,
            int numTeIntCases,
            string statsumTable,
            string statsumEnvTable)
        {
            string micsUser = Info.MicsUserName;
            if (String.IsNullOrWhiteSpace(micsUser))
            {
                micsUser = Environment.GetEnvironmentVariable("MicsUser");
            }

            string protype = "T";
            if (!String.IsNullOrWhiteSpace(parmStruct.protype))
            {
                protype = parmStruct.protype.Trim().Substring(0, 1).ToUpperInvariant();
            }
            if (!protype.Equals("T") && !protype.Equals("E"))
            {
                protype = isTs ? "T" : "E";
            }

            return new TsipArchiveContext
            {
                MicsUser = Trunc(micsUser, 32),
                SourceSchema = Trunc(Info.GlobalSchema, 128),
                ParmFile = Trunc(parmFile, 64),
                RunName = Trunc(parmStruct.runname, 64),
                ViewName = Trunc(viewName, 128),
                Protype = protype,
                IsTs = isTs,
                ParmTable = parmTable,
                SiteTable = siteTable,
                AnteTable = anteTable,
                ChanTable = chanTable,
                StatsumTable = statsumTable,
                StatsumEnvTable = statsumEnvTable,
                NumIntCases = numIntCases,
                NumTeIntCases = numTeIntCases,
                ParmStruct = parmStruct
            };
        }

        /// <summary>Registry insert, statsum capture, and working-table copy — before KillTable(cUnique).</summary>
        public static void TryArchiveBeforeKill(TsipArchiveContext ctx)
        {
            if (ctx == null)
            {
                return;
            }

            try
            {
                if (!InsertRunRegistry(ctx))
                {
                    Warn(ctx, "registry insert failed");
                    return;
                }

                CaptureStatsum(ctx);
                CopyWorkingTables(ctx);
            }
            catch (Exception ex)
            {
                Warn(ctx, "pre-kill archive exception: " + ex.Message);
                Log2.w("\nTsipRunArchive.TryArchiveBeforeKill(): WARNING: {0}\n{1}", ex.Message, ex.StackTrace);
            }
        }

        /// <summary>Parm snapshot, report-line cache, and registry finalize — after CloseReportStreams().</summary>
        public static void TryArchiveAfterClose(TsipArchiveContext ctx, IList<TsipArchiveReportFile> reportFiles)
        {
            if (ctx == null || !ctx.RegistryInserted || ctx.RunId <= 0)
            {
                return;
            }

            try
            {
                ArchiveParmSnapshot(ctx);
                ArchiveReportLines(ctx, reportFiles);
                FinalizeRegistry(ctx);
            }
            catch (Exception ex)
            {
                Warn(ctx, "post-close archive exception: " + ex.Message);
                Log2.w("\nTsipRunArchive.TryArchiveAfterClose(): WARNING: {0}\n{1}", ex.Message, ex.StackTrace);
                FinalizeRegistry(ctx);
            }
        }

        private static bool InsertRunRegistry(TsipArchiveContext ctx)
        {
            int? queueJobId = ParseQueueJobId();
            int caseCount = ctx.IsTs ? ctx.NumIntCases : ctx.NumTeIntCases;

            string sql = String.Format(
                "INSERT INTO web.tsip_run (mics_user, source_schema, parm_file, run_name, view_name, protype, num_int_cases, queue_job_id, archive_status) " +
                "OUTPUT INSERTED.run_id VALUES ({0}, {1}, {2}, {3}, {4}, {5}, {6}, {7}, 'pending')",
                SqlStr(ctx.MicsUser),
                SqlStr(ctx.SourceSchema),
                SqlStr(ctx.ParmFile),
                SqlStr(ctx.RunName),
                SqlStr(ctx.ViewName),
                SqlStr(ctx.Protype),
                caseCount.ToString(),
                queueJobId.HasValue ? queueJobId.Value.ToString() : "NULL");

            long? runId = ExecuteInsertIdentity(sql, "run_id");
            if (!runId.HasValue || runId.Value <= 0)
            {
                return false;
            }

            ctx.RunId = runId.Value;
            ctx.RegistryInserted = true;
            Console.WriteLine("TsipRunArchive: registered run_id={0} queue_job_id={1} for {2}/{3}",
                ctx.RunId,
                queueJobId.HasValue ? queueJobId.Value.ToString() : "NULL",
                ctx.ParmFile,
                ctx.RunName);
            return true;
        }

        private static void CaptureStatsum(TsipArchiveContext ctx)
        {
            if (String.IsNullOrWhiteSpace(ctx.StatsumTable))
            {
                return;
            }

            if (ctx.IsTs)
            {
                if (!CopyInsertSelect(
                    "web.tsip_arc_ts_statsum",
                    "run_id,tmpinter,tmpcall1,tmpname,tmpoper,tmplatit,tmplongit,tmpgrnd",
                    ctx.RunId + ",tmpinter,tmpcall1,tmpname,tmpoper,tmplatit,tmplongit,tmpgrnd",
                    ctx.StatsumTable))
                {
                    Warn(ctx, "ts statsum capture failed");
                }
            }
            else
            {
                if (!CopyInsertSelect(
                    "web.tsip_arc_te_statsum",
                    "run_id,statsum_part,tmpinter,tmplocat,tmpcall1,tmpname,tmpoper,tmplatit,tmplongit,tmpgrnd",
                    ctx.RunId + ",'P',tmpinter,tmplocat,tmpcall1,tmpname,tmpoper,tmplatit,tmplongit,tmpgrnd",
                    ctx.StatsumTable))
                {
                    Warn(ctx, "te statsum (proposed) capture failed");
                }

                if (!String.IsNullOrWhiteSpace(ctx.StatsumEnvTable) &&
                    !CopyInsertSelect(
                        "web.tsip_arc_te_statsum",
                        "run_id,statsum_part,tmpinter,tmplocat,tmpcall1,tmpname,tmpoper,tmplatit,tmplongit,tmpgrnd",
                        ctx.RunId + ",'E',tmpinter,tmplocat,tmpcall1,tmpname,tmpoper,tmplatit,tmplongit,tmpgrnd",
                        ctx.StatsumEnvTable))
                {
                    Warn(ctx, "te statsum (environment) capture failed");
                }
            }
        }

        private static void CopyWorkingTables(TsipArchiveContext ctx)
        {
            if (ctx.IsTs)
            {
                CopyLayer2(ctx, "web.tsip_arc_ts_site", TsSiteCols, ctx.SiteTable);
                CopyLayer2(ctx, "web.tsip_arc_ts_ante", TsAnteCols, ctx.AnteTable);
                CopyLayer2(ctx, "web.tsip_arc_ts_chan", TsChanCols, ctx.ChanTable);
                CopyLayer2(ctx, "web.tsip_arc_ts_parm", ParmCols, ctx.ParmTable);
            }
            else
            {
                CopyLayer2(ctx, "web.tsip_arc_te_site", TeSiteCols, ctx.SiteTable);
                CopyLayer2(ctx, "web.tsip_arc_te_ante", TeAnteCols, ctx.AnteTable);
                CopyLayer2(ctx, "web.tsip_arc_te_chan", TeChanCols, ctx.ChanTable);
                CopyLayer2(ctx, "web.tsip_arc_te_parm", ParmCols, ctx.ParmTable);
            }
        }

        private static void CopyLayer2(TsipArchiveContext ctx, string destTable, string dataCols, string sourceTable)
        {
            if (String.IsNullOrWhiteSpace(sourceTable))
            {
                Warn(ctx, "skip copy: missing source for " + destTable);
                return;
            }

            if (!CopyInsertSelect(destTable, "run_id," + dataCols, ctx.RunId + "," + dataCols, sourceTable))
            {
                Warn(ctx, "copy failed: " + destTable + " <- " + sourceTable);
            }
        }

        private static void ArchiveParmSnapshot(TsipArchiveContext ctx)
        {
            string dest = ctx.IsTs ? "web.tsip_run_parm_ts" : "web.tsip_run_parm_es";
            if (!CopyInsertSelect(dest, "run_id," + ParmCols, ctx.RunId + "," + ParmCols, ctx.ParmTable))
            {
                Warn(ctx, "parm snapshot failed");
            }
        }

        private static void ArchiveReportLines(TsipArchiveContext ctx, IList<TsipArchiveReportFile> reportFiles)
        {
            if (reportFiles == null || reportFiles.Count == 0)
            {
                return;
            }

            foreach (TsipArchiveReportFile report in reportFiles)
            {
                if (report == null ||
                    String.IsNullOrWhiteSpace(report.ReportType) ||
                    String.IsNullOrWhiteSpace(report.FilePath) ||
                    !File.Exists(report.FilePath))
                {
                    continue;
                }

                try
                {
                    string[] lines = File.ReadAllLines(report.FilePath);
                    InsertReportLines(ctx, report.ReportType, lines);
                }
                catch (Exception ex)
                {
                    Warn(ctx, "report line cache failed for " + report.ReportType + ": " + ex.Message);
                }
            }
        }

        private static void InsertReportLines(TsipArchiveContext ctx, string reportType, string[] lines)
        {
            const int batchSize = 40;
            int lineNo = 0;

            while (lineNo < lines.Length)
            {
                StringBuilder sb = new StringBuilder();
                sb.Append("INSERT INTO web.tsip_run_report_line (run_id, report_type, line_no, line_text) VALUES ");

                int batchCount = 0;
                while (lineNo < lines.Length && batchCount < batchSize)
                {
                    if (batchCount > 0)
                    {
                        sb.Append(",");
                    }

                    string text = lines[lineNo] ?? "";
                    sb.AppendFormat("({0},{1},{2},{3})",
                        ctx.RunId,
                        SqlStr(reportType),
                        (lineNo + 1).ToString(),
                        SqlStr(text, maxLen: 8000));
                    lineNo++;
                    batchCount++;
                }

                if (!DbExecute(sb.ToString()))
                {
                    Warn(ctx, "report line insert batch failed for " + reportType);
                    break;
                }
            }
        }

        private static void FinalizeRegistry(TsipArchiveContext ctx)
        {
            string status = ctx.Warnings.Count == 0 ? "complete" : "partial";

            string message = null;
            if (ctx.Warnings.Count > 0)
            {
                message = Trunc(String.Join("; ", ctx.Warnings), 500);
            }

            string sql = String.Format(
                "UPDATE web.tsip_run SET run_finished_utc = SYSUTCDATETIME(), archive_status = {0}, archive_message = {1} WHERE run_id = {2}",
                SqlStr(status),
                message == null ? "NULL" : SqlStr(message),
                ctx.RunId);

            if (!DbExecute(sql))
            {
                Log2.w("\nTsipRunArchive.FinalizeRegistry(): WARNING: could not update run_id={0}", ctx.RunId);
            }
        }

        private static bool CopyInsertSelect(string destTable, string destCols, string selectCols, string sourceTable)
        {
            string sql = String.Format(
                "INSERT INTO {0} ({1}) SELECT {2} FROM {3}",
                destTable,
                destCols,
                selectCols,
                sourceTable);
            return DbExecute(sql);
        }

        private static bool DbExecute(string query)
        {
            return Ssutil.DbExecute(query);
        }

        private static long? ExecuteInsertIdentity(string query, string identityColumn)
        {
            SQLHANDLE hStmt = IntPtr.Zero;
            SQLRETURN sqlRet;
            SQLHDBC hConn = Ssutil.NewConn();
            long? identity = null;

            try
            {
                sqlRet = ODBC.SQLAllocHandle(ODBC.SQL_HANDLE_STMT, hConn, out hStmt);
                if (!ODBC.IsOK(sqlRet))
                {
                    Log2.e("\nTsipRunArchive.ExecuteInsertIdentity(): ERROR: SQLAllocHandle failed.");
                    return null;
                }

                sqlRet = ODBC.SQLExecDirect(hStmt, query, query.Length);
                if (!ODBC.IsOK(sqlRet))
                {
                    Log2.e("\nTsipRunArchive.ExecuteInsertIdentity(): ERROR: {0}\n{1}", query, ODBC.GetDiagnostics(hStmt, query));
                    return null;
                }

                sqlRet = ODBC.SQLFetch(hStmt);
                if (ODBC.IsOK(sqlRet))
                {
                    SQLLEN nNull;
                    long value;
                    if (Ssutil.DbGetLong(hStmt, 1, "run_id", out value, out nNull) == Constant.SUCCESS &&
                        nNull != Constant.DB_NULL)
                    {
                        identity = value;
                    }
                }
            }
            finally
            {
                if (hStmt != IntPtr.Zero)
                {
                    ODBC.SQLFreeHandle(ODBC.SQL_HANDLE_STMT, hStmt);
                }
                Ssutil.DisConn(hConn);
            }

            return identity;
        }

        private static int? ParseQueueJobId()
        {
            string raw = Environment.GetEnvironmentVariable("TSIP_QUEUE_JOB");
            if (String.IsNullOrWhiteSpace(raw))
            {
                raw = Environment.GetEnvironmentVariable("TQ_Job");
            }

            int jobId;
            if (Int32.TryParse(raw, out jobId) && jobId > 0)
            {
                return jobId;
            }

            return null;
        }

        private static void Warn(TsipArchiveContext ctx, string message)
        {
            ctx.Warnings.Add(message);
            Log2.w("\nTsipRunArchive: WARNING run archive: {0}", message);
            Console.WriteLine("TsipRunArchive: WARNING: " + message);
        }

        private static string Trunc(string value, int maxLen)
        {
            if (String.IsNullOrEmpty(value))
            {
                return "";
            }

            value = value.Trim();
            if (value.Length <= maxLen)
            {
                return value;
            }

            return value.Substring(0, maxLen);
        }

        private static string SqlStr(string value)
        {
            return SqlStr(value, 4000);
        }

        private static string SqlStr(string value, int maxLen)
        {
            if (value == null)
            {
                return "NULL";
            }

            value = value.Replace("'", "''");
            if (value.Length > maxLen)
            {
                value = value.Substring(0, maxLen);
            }

            return "N'" + value + "'";
        }
    }
}
