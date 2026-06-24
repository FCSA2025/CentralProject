using _Configuration;
using _DataStructures;
using _NewLib;
using _OHloss;
using _Utillib;
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.Odbc;
using System.Diagnostics;
using System.IO;
using System.Text;
using static System.Math;
using static System.Net.WebRequestMethods;

/// <summary>
/// This Terrestial Station (TS) and Earth Station (ES) interference analysis program is
/// the core of the MICS system. It inputs data describing new or modified radio systems
/// and identifies cases of interference with existing radio systems. TSIP provides
/// detailed analysis reports for TS-TS, TS-ES and ES-TS interference cases.
/// </summary>
/// <remarks>
/// The command-line usage is:
/// \image html "Usage - TpRunTsip.PNG" ""
/// </remarks>
namespace TpRunTsip
{
    using System.Collections;
    using System.Runtime.InteropServices;
    using System.Xml;
    using SQLHANDLE = IntPtr;
    using SQLLEN = Int64;
    using SQLRETURN = Int16;

    /// <summary>
    /// Provides the 'Main()' method that provides top-level 
    /// control of the TSIP setup, microwave system calculations and
    /// the production of reports.
    /// </summary>
    public class TpRunTsip
    {
        private static int mGlbIsCtxCalc;
        public static TsipReportHelper mReports;
        public static string mMicsUserViaCommandLine = "";

        public static int GlbIsCtxCalc
        {
            get { return mGlbIsCtxCalc; }
        }

        // The following pair of variables were previously combined in the native code
        // struct glbParmparm.
        public static double mdCull = 0.0;
        public static double mdArcStep;

        // Make a copy of the initial value of the stream Console.out
        // so that it can be restored at a later time.
        private static TextWriter mStandardConsoleOut = Console.Out;

        // TextWriters for the error stream; make it globally accessible.
        public static TextWriter mTW_ERR = null;

        // TextWriters for the reports.
        private static TextWriter mTW_AGGINTCSV = null;
        private static TextWriter mTW_AGGINTREP = null;
        private static TextWriter mTW_CASEDET = null;
        private static TextWriter mTW_CASEOHL = null;
        private static TextWriter mTW_CASESUM = null;
        private static TextWriter mTW_EXEC = null;
        private static TextWriter mTW_EXPORT = null;
        private static TextWriter mTW_HILO = null;
        public static TextWriter mTW_ORBIT = null;
        private static TextWriter mTW_STATSUM = null;
        private static TextWriter mTW_STUDY = null;

        /*	ES to TS coordination distances.  Saved here for the final report. */
        private static double mdTxTro = double.MinValue;
        private static double mdTxPre = double.MinValue;
        private static double mdRxTro = double.MinValue;
        private static double mdRxPre = double.MinValue;

        public class ParmTableWN
        {
            public TpParm parmStruct = new TpParm();
            public SQLLEN[] parmNulls = NullHelper.CreateArrayOfNullInd(TpParm.NUM_COLUMNS, NullHelper.ColumnStatus.NULL);

            /// <summary>
            /// This method returns a string that lists the field values
            /// of this instance of ParmTableWN.
            /// </summary>
            /// <returns></returns>
            public override string ToString()
            { return parmStruct.ToString(); }

            /// <summary>
            /// This method returns a string that lists the field values
            /// of this instance of ParmTableWN together with the field null
            /// indicators.
            /// </summary>
            /// <param name=""></param>
            /// <returns></returns>
            public string ToStringWN()
            {
                return parmStruct.ToStringWN(parmNulls);
            }
        }

        /// <summary>
        /// This method that provides top-level 
        /// control of the TSIP setup, microwave system calculations and
        /// the production of reports.
        /// </summary>
        /// <param name="args"></param>
        static void Main(string[] args)
        {
            int exitCode;
            int nRet;
            int rc;
            int numStnGroups = 0, TsEsStnGroups = 0, EsTsStnGroups = 0;
            int userSession = 1;
            UserInfoData userInfo;
            List<ParmTableWN> parmTables = new List<ParmTableWN>();
            int parmTableCount = 0;
            string cProNameTrimmed;
            string cRunNameTrimmed;
            string cLockFile;
            int numIntCases;
            int numTeIntCases;
            string startDate;
            string startTime;
            bool isTS = false;
            string viewName, parmName, siteName, endDate, endTime;
            string anteName = null, chanName = null;
            string sqlCommand;
            int clockTime;
            string cUnique, cUniqueEnv;

            //----------------------------------------------------------------------

            try
            {
#if true
                string mLog2FilePath = @"d:\MicsBatchLogs\TpRunTsip.log";
                if (Log2.SetLogFilePath(mLog2FilePath))
                {
                    Log2.Erase();
                    Log2.Set(Log2.FileOpenClose.PER_SESSION);
                    Log2.Set(Log2.WriteMode.ENABLED);
                    Log2.Set(Log2.Level.VERBOSE);
                    Info.BuildMetaData = Info.CollateExeMetaData();
                    //...Log2.v("\nBuild: " + Info.BuildMetaData);
                }
                else
                {
                    Console.Error.Write("\r\nERROR: could not open Log2 file: " + mLog2FilePath);
                }
#endif
                exitCode = Constant.SUCCESS;

                // Set our priority class to normal.  This will allow tsipInitiator to continue executing
                // while it updates the tsip queue after we have started.
                Application.SetPriority(ProcessPriorityClass.Normal);

                // Parse the command line.
                ParseCommandLineArguments(args);

                // Report the version.
                Console.Write("\ntpRunTsip Build {0} Process {1}\n\n", Info.ManagedBuildInfo(), Info.ProcessID);

                // Get all remaining Windows environment variables and system data 
                // used by TpRunTsip.
                GetEnvVarsAndSysData();
                Console.Write("Env variables read in\n");

                // Now queue for access.
                 nRet = Qutils.EnterQueue(Info.DbName, "READ", 30);
                if (nRet != Constant.SUCCESS)
                {
                    Qutils.ExplainQueue(Info.DbName, "READ", nRet, null);    //	Explain any error message.
                    Application.Exit(Error.UNABLE_TO_ENTER_QUEUE);
                }
                Console.Write("Entered queue\n");

                // This tests for the environment variable MICS_CTX_CALC. If it is present
                // and non-zero, then all ctx values are the result of calculations.
                if (Info.MicsCtxCalc != null)
                {
                    mGlbIsCtxCalc = Convert.ToInt32(Info.MicsCtxCalc);
                    if (mGlbIsCtxCalc != 0)
                    {
                        Console.Write("All CTX values will be obtained by calculation ({0}).\n", mGlbIsCtxCalc);
                    }
                }
                else
                {
                    mGlbIsCtxCalc = 0;
                }
                Console.Write("mGlbIsCtxCalc:" + mGlbIsCtxCalc + "\n");

                // Initialize the directories that will be used in ohloss.
                string dir250k;
                string dir50k;

                if (Info.FcsaMaps50K == null)
                {
                    dir50k = "d:\\dted50\\data";
                }
                else
                {
                    dir50k = Info.FcsaMaps50K;
                }

                if (Info.FcsaMaps250K == null)
                {
                    dir250k = "d:\\dted250\\data";
                }
                else
                {
                    dir250k = Info.FcsaMaps250K;
                }

                CTEfunctions.Init_Directories(dir250k, dir50k);
                Console.Write("FCSA MAPS LOADED\n");

                // Connect to the database and start the processing.
                rc = Ssutil.UtConnect(Info.DbName, userSession);

                if (rc != 0)
                {
                    /* Can't connect to database */
                    ErrMsg.UtPrintMessage(Error.NODATABASE, Info.DbName);
                    Qutils.ExitQueue(Info.DbName, "READ");
                    Log2.e("\nTpRunTsip.Main(): Ssutil.UtConnect(): ERROR: Can't connect to database");
                    Application.Exit(Constant.FAILURE);
                }

                // AH: unsolicited bug fix; dated 20210222
                // Do an early check that the user has defined some TSIP 'run' records,
                // i.e. the PARM table has one or more records in it.
                string parmTablename;
                Console.Write("Checking for parm records for " + Info.PdfName + "\n");
                GenUtil.UtCvtName(Constant.TP_PARM, Info.PdfName, out parmTablename);
                Console.Write("GenUtil.UtCvtName returned: " + parmTablename + "\n");

                nRet = Ssutil.DbCountRows(parmTablename, "");
                if (nRet == Error.ODBC_EXECDIRECT_FAILED)
                {
                    string str = String.Format("ERROR: The TSIP run parameters table {0} does not exist.", parmTablename);
                    Console.Write("\n\nTpRunTsip.Main(): " + str);
                    Log2.e("\n\nTpRunTsip.Main(): " + str);
                    Application.Exit(Error.PARMTABLEDOESNOTEXIST);
                }
                else if (nRet < 1)
                {
                    string str = String.Format("ERROR: The TSIP run parameters table {0} contains no records.", parmTablename);
                    Console.Write("\n\nTpRunTsip.Main(): " + str);
                    Log2.e("\n\nTpRunTsip.Main(): " + str);
                    Application.Exit(Error.PARMTABLEHASNORECORDS);
                }

                Console.Write("TpRunTsip before BiUtil.BiBillingRec\n");
                BiUtil.BiBillingRec("TPRUNTSIP", Info.PdfName);
                Console.Write("TpRunTsip after BiUtil.BiBillingRec\n");

                if (UserInfo.UtGetUserInfo(out userInfo) != Constant.SUCCESS)
                {
                    Console.Write("TpRunTsip UtGetUserInfo failed\n");
                    ErrMsg.UtPrintMessage(Error.PERMISSIONDENIED);
                    Ssutil.UtDisconnect(userSession);
                    Qutils.ExitQueue(Info.DbName, "READ");
                    Log2.e("\nTpRunTsip.Main(): UtGetUserInfo(): ERROR: call failed.");
                    Application.Exit(Constant.FAILURE);
                }

                Console.Write("TpRunTsip UtGetUserInfo succeeded\n");
                // A single error file is created for all the tsip parameter records. 
                // The null argument indicates that the file is to be created and truncated.
                // This call instantiates the TextWriter mTW_ERR.
                CreateErrorFile(Info.DestName, Info.PdfName, null);
                Console.Write("Create error file succeeded\n");

                // Tell ErrMsg where to stream its output.
                ErrMsg.SetDefaultOutputStream(mTW_ERR);

                Console.Write("TpRunTsip before ParmFileInit\n");
                // load all records from the current parm file into memory.
                rc = ParmFileInit(Info.PdfName, ref parmTableCount, out parmTables);
                if (rc != Constant.SUCCESS)
                {
                    Console.Write("TpRunTsip ParmFileInit failed\n");
                    mTW_ERR.Write("\r\nInvalid Parm File, probably doesn't exist ({0}).\r\n", rc);
                    mTW_ERR.Close();
                    Qutils.ExitQueue(Info.DbName, "READ");
                    Log2.e("\nTpRunTsip.Main(): ParmFileInit(): ERROR: call failed.");
                    Application.Exit(Constant.FAILURE);
                }
                Console.Write("TpRunTsip ParmFileInit succeeded\n");

                // Get the startDate and startTime to be used as fields in the TsipReports table.
                GenUtil.UtGetDateTime(out startDate, out startTime);
                Info.Date = startDate;
                Info.Time = startTime;

                // All the parameter records have now been read in; now start to process them.

                ////////////////////////////////////////////////
                // For each parameter record in the current parameter file ...
                foreach (ParmTableWN currParm in parmTables)
                {
                    Console.Write("TpRunTsip ParmTableLoop processing: " + currParm.parmStruct.runname + "\n");
                    Console.Write("\n" + currParm.ToStringWN());

                    // Determine which reports types have been requested.
                    mReports = new TsipReportHelper(currParm.parmStruct.reports, currParm.parmStruct.tsorbout);

                    // Enhancement 180301A.
                    //             =======
                    // Attach TS or ES export data file for each run to the email sent to the user.
                    // 'Export' data is produced by FtPrint and/or FePrint.
                    // To implement this enhancement the simplest approach is to invent two new
                    // TSIP report types whose file name ends with .TS_EXPORT and/or ES_EXPORT.
                    // WebMICS will remain unchanged so this is not an optional report that the
                    // user can select. Instead, we will force the EXPORT report to be written for
                    // each distinct run.
                    mReports.RequestExportReport(true);

                    Console.Write("\n" + mReports.ToString());

                    //	Clear out the study files in case of a rerun.
                    RemoveStudyFiles(Info.DestName, Info.PdfName, currParm.parmStruct.runname);
                    Console.Write("After RemoveStudyFiles\n");

                    // Make the runname available via global static.
                    Info.RunID = currParm.parmStruct.runname;
                    Console.Write("After setting Info.RunID\n");

                    // AH: New
                    // The following method assigns a TextWriter stream for every report type.
                    OpenReportStreams(Info.PdfName, currParm.parmStruct.runname, currParm.parmStruct.protype);
                    Console.Write("After OpenReportStreams\n");

                    // Make sure that there is no other tsip running this file.  
                    // First create a unique file name.
                    cProNameTrimmed = currParm.parmStruct.proname.Trim();
                    cRunNameTrimmed = currParm.parmStruct.runname.Trim();
                    cLockFile = String.Format("{0}_{1}_{2}_LOCK", Info.DbName, cProNameTrimmed, cRunNameTrimmed);
                    Console.Write("Create lockFile: " + cLockFile + "\n");

                    if (GenUtil.FileGate(cLockFile) != Constant.SUCCESS)
                    {
                        /*	We have a locking situation.  Tell the user to come back later */
                        mTW_ERR.Write("*ERROR* - TSIP is currently being run on this combination. Try again later.\r\n");
                        Log2.w("\nTpRunTsip.Main(): FileGate(): WARNING: call failed.");
                        continue; // Process the next parameter table.
                    }

                    // Re-open the Error file for this Tsip parameter record.
                    // This is necessary for multiple records since the output is
                    // redirected for reports after each Tsip parameter record is
                    // processed.
                    CreateErrorFile(Info.DestName, Info.PdfName, currParm.parmStruct.runname);
                    Console.Write("Error File created\n");

                    // The following code is here to provide compatability between the
                    // old TSIP parameter files with Propogation Loss Method selection
                    // for the ES side only, and the new files which permit up to 5
                    // propogation loss methods for the TS side. Old TSIP parameter
                    // files may have NULL spherecalc fields--this must be caught and
                    // converted here.
                    if (currParm.parmNulls[TpParm.SPHERECALC] == Constant.DB_NULL)
                    {
                        currParm.parmStruct.spherecalc = "3";
                        currParm.parmNulls[TpParm.SPHERECALC] = Constant.DB_NOT_NULL;
                        Console.WriteLine("Null SPHERECALC");
                    }
                    else
                    {
                        if (Strings.FirstCharIs(currParm.parmStruct.spherecalc, 'N'))
                        {
                            currParm.parmStruct.spherecalc = "1";
                        }
                        if (Strings.FirstCharIs(currParm.parmStruct.spherecalc, 'Y'))
                        {
                            currParm.parmStruct.spherecalc = "2";
                        }
                        Console.WriteLine("SPHERECALC:" + currParm.parmStruct.spherecalc);
                    }

                    //	If this is an ohloss calculation, print the directories...
                    if (currParm.parmStruct.spherecalc[0] == '5')
                    {
                        string str = String.Format("\r\nOver Horizon Loss Calculation Directories:-\r\n1:250K - {0}\r\n1:50K  - {1}\r\n", dir250k, dir50k);
                        mTW_ERR.Write(str);
                        Console.WriteLine("\nOver Horizon Loss Calculation Directories:-\r\n1:250K - {0}\r\n1:50K  - {1}\r\n", dir250k, dir50k);

                    }

                    // Check whether this is a PLAN mode analysis. If it is,
                    // generate a temporaray PDF with all the PLAN channels in it. The
                    // name of this new PDF becomes the PDf name in the parmStruct. The
                    // PDF will be deleted at the end of the tsip run.
                    Console.WriteLine("Processing PLAN option");
                    if ((currParm.parmStruct.analopt.Equals("PLAN")) &&
                                                 (currParm.parmStruct.protype.Equals("T")))
                    {
                        if (TpPlanChan.GenChan(currParm.parmStruct) != Constant.SUCCESS)
                        {
                            ErrMsg.UtPrintMessage(Error.NOPLANPDF);
                            exitCode = Constant.FAILURE;
                            continue;
                        }

                        Console.WriteLine("Updating Central Table");
                        UserInfo.UtUpdateCentralTable("A", currParm.parmStruct.proname, Constant.FT, "T", "N");
                        UserInfo.UtUpdateCentralTable("U", currParm.parmStruct.proname, Constant.FT, "T", "N");
                        Console.WriteLine("Central Table Updated ");
                    }
                    Console.WriteLine("Processing PLAN option complete");

                    // Initialize the number of interference cases found for this tsip run.
                    numIntCases = 0;
                    numTeIntCases = 0;

                    // Start a stop watch to calculate elapsed real-time.
                    Stopwatch stopWatch = Stopwatch.StartNew();

                    // Get the startDate and startTime to include in the exec report.
                    GenUtil.UtGetDateTime(out startDate, out startTime);

                    // ParmRecInit() write the current parm rec to mTW_ERR.
                    // Also, check the validation status of the PDFs.
                    //
                    // Note:
                    // ====
                    // This method also changes the value of the field currParm.coord from that read in 
                    // from the Parm table in the DB. However, the corresponding nullInd is NOT changed. 
                    // This is important when the updated Parm object is inserted back into the DB 
                    // because a coordist that is read in as NULL gets written back to the Parm table as NULL.
                    Console.WriteLine("Before parmrec init");
                    if ((rc = ParmRecInit(currParm)) != Constant.SUCCESS)
                    {
                        Console.WriteLine("Parmrec init failed");
                        if (rc != Constant.FAILURE)
                        {
                            ErrMsg.UtPrintMessage(rc);
                            ErrMsg.UtPrintMessage(Error.DYN_MS_SQL_SERVER_ERR);
                        }

                        CloseReportStreams();
                        DeleteUnwantedReportFiles();

                        exitCode = Constant.FAILURE;
                        continue;  // skip to the next run.
                    }
                    Console.WriteLine("Before parmrec init succeeded");
                    // AH: Supercedes original comment text.
                    // The call below is a 'legacy' subroutine name retained for convenience.
                    // Although the call's name says 'Create', the Orbit report has already
                    // been created, above, along with all the other report types.
                    // This method just writes a text 'header' into the (so far) empty
                    // Orbit report file.
                    // We do this here because we will be writing to the ORBIT reports an
                    // unknown number of times.

                    Console.WriteLine("Before CreateOrbitFile");
                    rc = CreateOrbitFile(Info.DestName, Info.PdfName, currParm.parmStruct.runname);

                    viewName = String.Format("{0}_{1}", Info.PdfName, currParm.parmStruct.runname);

                    /*****************************************************************/
                    if ((currParm.parmStruct.protype.Equals("E")) ||
                            (currParm.parmStruct.envtype.Equals("PDF_ES")) ||
                            (currParm.parmStruct.envtype.Equals("MDB_ES")))
                    {
                        Console.WriteLine("Processing type E");
                        isTS = false;
                        GenUtil.UtCvtName(Constant.TE_PARM, viewName, out parmName);
                        GenUtil.UtCvtName(Constant.TE_SITE, viewName, out siteName);
                        GenUtil.UtCvtName(Constant.TE_ANTE, viewName, out anteName);

                        // Cull, build and populate the ES SH Tables.
                        // This is the call that begins the TSIP computation for ES cases.
                        rc = TeBuildSH.TeBuildSHTable(viewName,
                                                                Info.PdfName,
                                                                ref currParm.parmStruct,
                                                                ref currParm.parmNulls,
                                                                ref numIntCases,
                                                                ref numTeIntCases,
                                                                startDate,
                                                                startTime);

                        //Console.Write(currParm.parmStruct.ToStringWN(currParm.parmNulls));

                        if (rc == Constant.FAILURE)
                        {
                            Console.WriteLine("TeBuildSHTable failed");
                            mTW_ERR.Write("FATAL ES ERROR({0}): PROCESSING TERMINATED\r\n", rc);
                            GenUtil.UtGetDateTime(out endDate, out endTime);
                            sqlCommand = String.Format("Time: {0}\n", endTime.PadRight(12));
                            ErrMsg.UtPrintMessage(Error.GENERROR, sqlCommand);
                            if (!String.IsNullOrWhiteSpace(GenUtil.GetUserMess()))
                            {
                                mTW_ERR.Write("*ERROR : {0}\r\n", GenUtil.GetUserMess());
                            }

                            exitCode = Constant.FAILURE;
                            continue;
                        }
                        Console.WriteLine("TeBuildSHTable succeeded");

                        // We have completed the TSIP calculations, now start on the reports.  
                        // Print out the times.
                        Console.WriteLine("Before UtGetInterferenceGroups");
                        TpMdbPdfGet.UtGetInterferenceGroups(currParm.parmStruct.runname,
                                                                    siteName,
                                                                    anteName,
                                                                    out TsEsStnGroups,
                                                                    out EsTsStnGroups);
                        Console.WriteLine("After UtGetInterferenceGroups");
                        numStnGroups = TsEsStnGroups + EsTsStnGroups;

                    }
                    else  /*********************************************************/
                    {
                        Console.Write("Processing TT record\n ");
                        isTS = true;
                        GenUtil.UtCvtName(Constant.TT_PARM, viewName, out parmName);
                        GenUtil.UtCvtName(Constant.TT_SITE, viewName, out siteName);

                        Console.Write("Before TtBuildSHTable\n");
                        // Cull, build and populate the TS SH Tables.
                        // This is the call that begins the TSIP computation for TS cases.
                        rc = TtBuildSH.TtBuildSHTable(viewName,
                                                                ref currParm.parmStruct,
                                                                ref currParm.parmNulls,
                                                                ref numIntCases,
                                                                startDate,
                                                                startTime);

                        if (rc != Constant.SUCCESS)
                        {
                           Console.Write("\nTpRunTsip.Main(): ERROR: TtBuildSH.TtBuildSHTable() returned " + rc);

                            mTW_ERR.Write("FATAL TS ERROR({0}): PROCESSING TERMINATED\r\n", rc);
                            GenUtil.UtGetDateTime(out endDate, out endTime);
                            sqlCommand = String.Format(" Time: {0}\n", endTime.PadRight(12));
                            ErrMsg.UtPrintMessage(Error.GENERROR, sqlCommand);
                            if (!String.IsNullOrWhiteSpace(GenUtil.GetUserMess()))
                            {
                                mTW_ERR.Write("*ERROR : {0}\r\n", GenUtil.GetUserMess());
                            }

                            exitCode = Constant.FAILURE;
                            continue;
                        }

                        numStnGroups = Ssutil.DbCountRows(siteName, null);
                    }  /*******************************************************************************/

                    // Delete the temporary PDF.
                    Console.WriteLine("Before UtDropTable ");
                    if (currParm.parmStruct.analopt.Equals("PLAN") &&
                          currParm.parmStruct.protype.Equals("T"))
                    {
                        Ssutil.UtDropTable(Constant.FT, currParm.parmStruct.proname);
                    }
                    Console.WriteLine("After UtDropTable ");

                    // Update parm rec with the number of cases where interference was found.
                    Console.WriteLine("Before UpdateParmRec ");
                    if ((rc = UpdateParmRec(numIntCases, numTeIntCases, parmName, currParm)) != Constant.SUCCESS)
                    {
                        Console.WriteLine("UpdateParmRec failed ");
                        ErrMsg.UtPrintMessage(rc);
                        exitCode = Constant.FAILURE;
                        continue;
                    }
                    Console.WriteLine("UpdateParmRec succeeded ");
                    //AH: HERE   
                    Console.Out.Flush();

                    // Get the total elapsed real-time.
                    double timeDiff = stopWatch.Elapsed.TotalSeconds;

                    // Get the sum of the 'User' and 'Kernel' CPU times for the current process.
                    clockTime = GenUtil.WinClock();

                    // Get the end date and time.
                    GenUtil.UtGetDateTime(out endDate, out endTime);

                    //================================
                    // Start of report production.   =
                    //================================

                    Console.WriteLine("Before ReportStudy");
                    if ((rc = ReportStudy(Info.DbName, Info.PdfName, Info.ProjectCode, currParm,
                                                                parmName, siteName, anteName, chanName,
                                          clockTime, timeDiff, numStnGroups, TsEsStnGroups,
                                          EsTsStnGroups, Info.DestName)) != Constant.SUCCESS)
                    {
                        Console.WriteLine("ReportStudy failed");
                        ErrMsg.UtPrintMessage(rc);
                        exitCode = Constant.FAILURE;
                        continue;
                    }
                    else if (numTeIntCases < 0)
                    {
                        Console.WriteLine("No interference cases to report");
                        ErrMsg.UtPrintMessage(Error.GENERROR, "No interference cases to report");
                    }

                    if (isTS)
                    {
                        //...Log2.v("\nMain1");
                        GenUtil.UtCvtName(Constant.TT_ANTE, viewName, out anteName);
                        GenUtil.UtCvtName(Constant.TT_CHAN, viewName, out chanName);

                        TpReport.CreateTTStatRep(currParm.parmStruct.protype, siteName, out cUnique); /*	cUnique is the name of the temporary table
                        																	**	created in this routine, used later. */

                        cUniqueEnv = "";     /*	Only used in ES */

                    }
                    else
                    {
                        //...Log2.v("\nMain2");
                        GenUtil.UtCvtName(Constant.TE_SITE, viewName, out siteName);
                        GenUtil.UtCvtName(Constant.TE_ANTE, viewName, out anteName);
                        GenUtil.UtCvtName(Constant.TE_CHAN, viewName, out chanName);

                        TpReport.CreateETStatRep(currParm.parmStruct.protype, siteName, anteName,
                                                        out cUnique, out cUniqueEnv);
                    }
                    //...Log2.v("\nMain3");
                    rc = ReportNew(Info.DbName, Info.PdfName, currParm, numIntCases,
                        numTeIntCases, numStnGroups, viewName, Info.DestName,
                        cUnique, cUniqueEnv, isTS);

                    if (rc != Constant.SUCCESS)
                    {
                        ErrMsg.UtPrintMessage(rc);
                        exitCode = Constant.FAILURE;
                        continue;
                    }
                    else
                    {
                        if (numTeIntCases < 0)
                        {
                            ErrMsg.UtPrintMessage(Error.GENERROR, "No interference cases to report");
                        }
                    }
                    //...Log2.v("\nMain4");
                    /* if user requested an execution report, write it */
                    if (mReports.Exec)
                    {
                        //AH: the following P/Invoke call can be removed once all code is in C#.
                        //mdArcStep = getGlbParmParmArcStep();

                        mReports.ExecWritten = true;

                        TpExecRpt(mTW_EXEC, Info.PdfName, currParm.parmStruct, startTime, startDate,
                                  endTime, endDate, isTS, numStnGroups, TsEsStnGroups,
                                  EsTsStnGroups, numIntCases, numTeIntCases,
                                  currParm.parmStruct.tsorbout, Info.DestName);
                    }
                    //...Log2.v("\nMain5");
                    /* Write the EXPORT report */
                    if (mReports.Export)
                    {
                        mReports.ExportWritten = true;
                        // commented out BA 2026/03/26
                        TpExportRpt(currParm.parmStruct.proname, currParm.parmStruct.protype);
                    }

                    //...Log2.v("\n\nTpRunTsip.Main(): mReports = " + mReports);

                    /*+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                    + We can now remove the temporary table tsip_stat_rep
                    +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++*/
                    //...Log2.v("\nMain6");
                    Ssutil.KillTable(cUnique);

                    GenUtil.FileGateClose(cLockFile);  /* Allow others to run this combo */

                    //...Log2.v("\nMain7");
                    // Report sets are 'per-record' so we need to close the TextWriter
                    // streams and tidy-up.
                    Console.Write("\n{0}", mReports.ToString());
                    CloseReportStreams();
                    DeleteUnwantedReportFiles();

                    //...Log2.v("\nMain8");
                    // Calculate and write normalized report content MD5 checksums into a table.
                    mReports.WritePerRunReportsToDbTable();

                    //...Log2.v("\nMain9");
                } /* end for (each parameter record) */

                // Close the error stream.
                mTW_ERR.Close();
                //...Log2.v("\nMain10");
                // There is one ERR report created that encompasses multiple runs.
                // We can only calculate the normalized MD5 checksum of the ERR report
                // after all runs have been completed and its textwriter has been closed.
                mReports.WriteRunReportToDbTable(TsipReportHelper.ErrFilePath);

                //...Log2.v("\nMain11");
                // Insert a final record in the TsipReports table that provides a
                // "checksum of all checksums".
                mReports.InsertFinalMD5allRunsandReports();

                //...Log2.v("\nMain12");
                // We have a normal completion of Main() - perform final housekeeping and exit.
                BiUtil.BiBillingRec(Constant.BI_END, "");

                //...Log2.v("\nMain13");
                Ssutil.UtDisconnect(userSession);

                Log2.v("\nMain14");
                Qutils.ExitQueue(Info.DbName, "READ");

                Console.Out.Flush();

                Application.Exit("Successful normal exit from TpRunTsip.Main()", exitCode);
            }
            catch (Exception e)
            {
                Qutils.ExitQueue(Info.DbName, "READ");

                Log2.v("\n\nTpRunTsip.Main(): exception caught: " + e.Message);
                Console.WriteLine("\n\nTpRunTsip.Main(): stack trace: \n\n" + e.StackTrace);

                Application.Exit(Error.FATAL_EXCEPTION);
            }
        } // End of Main()

        /// <summary>
        /// This method writes a 'usage' message to Console.Out that provides a 
        /// succinct summary of mandatory and optional arguments when the program
        /// is run from the Windows command line.
        /// </summary>
        public static void WriteUsageToConsole()
        {
            Console.Write("\r\n");
            Console.Write("\r\n This Terrestial Station (TS) and Earth Station (ES) interference analysis program is  +  ");
            Console.Write("\r\n the core of the MICS system. It inputs data describing new or modified radio systems  +");
            Console.Write("\r\n and identifies cases of interference with existing radio systems. TSIP provides ");
            Console.Write("\r\n detailed analysis reports for TS-TS, TS-ES and ES-TS interference cases.");
            Console.Write("\r\n");
            Console.Write("\r\n USAGE: TpRunTsip <dbName> <projCode> <paramTableName> [-o<prefix>] [-u<micsUser>] [-t]");
            Console.Write("\r\n ===== ");
            Console.Write("\r\n");
            Console.Write("\r\n        dbName           : database name, e.g. 'fcsa'.");
            Console.Write("\r\n        projCode         : user's project 'charge' code.");
            Console.Write("\r\n        paramTableName   : the XXX in TSIP parameter table tp_XXX_parm listed by WebMICS using:");
            Console.Write("\r\n                                --> Interference Analysis (TSIP)");
            Console.Write("\r\n                                    --> Open TSIP Parameter Files");
            Console.Write("\r\n");
            Console.Write("\r\n        --- Options ---------------------------------------------------------------------------");
            Console.Write("\r\n");
            Console.Write("\r\n        -o<prefix>       : the output reports are named <prefix>_<tableName>.CASEDET etc.");
            Console.Write("\r\n        -u<micsUser>     : overrides the environment variable 'MICSUSER'.");
            Console.Write("\r\n");
            Console.Write("\r\n        -t               : writes all reports, for all runs, into a single DB table, ");
            Console.Write("\r\n                         : if <paramTableName> is \"tstest0183\" the table name is \"tstest0183_tsip_reports\" .");
            Console.Write("\r\n");
            Console.Write("\r\n <...>  indicates a mandatory argument.\r\n");
            Console.Write("\r\n [...]  indicates an optional argument.");
            Console.Write("\r\n");
            Console.Write("\r\n e.g.");
            Console.Write("\r\n        TpRunTsip  fcsa  hulme1_0  es300km  -oTSIP -t");
            Console.Write("\r\n");
            Console.Write("\r\n Notes:");
            Console.Write("\r\n");
            Console.Write("\r\n       1. This program *must* be called with qty. 3 mandatory command-line arguments.");
            Console.Write("\r\n       2. The default is that all reports are written to the console.");
            Console.Write("\r\n       3. If the -o<prefix> option is used then reports are written to files.");
            Console.Write("\r\n       4. Multiple files are written, one for each report type.");
            Console.Write("\r\n");
            Console.Write("\r\n TSIP reports directory:");
            Console.Write("\r\n");
            Console.Write("\r\n      1. If TpRunTsip is launched by TsipInitiator then the required TSIP reports");
            Console.Write("\r\n         directory is passed via the environment variable TARGETDIRFORTSIPREPORTS.");
            Console.Write("\r\n      2. TpRunTsip.exe checks to see if TARGETDIRFORTSIPREPORTS has been set, or not:");
            Console.Write("\r\n            - if TARGETDIRFORTSIPREPORTS is set then its value provides the ");
            Console.Write("\r\n              target directory for the TSIP reports.");
            Console.Write("\r\n            - if TARGETDIRFORTSIPREPORTS is not set then the TSIP reports ");
            Console.Write("\r\n              are written to the Windows environment's current directory.");
            Console.Write("\r\n");
            Console.Write("\r\n\r\n Build: {0}\r\n", Info.ManagedBuildInfo());
        }

        /// <summary>
        /// This method parses the command line arguments prescribed by the user.
        /// </summary>
        /// <param name="args"> - User prescribed command line arguments.</param>
        private static void ParseCommandLineArguments(string[] args)
        {
            if (args.Length == 0)
            {
                WriteUsageToConsole();
                Application.ExitQuietly(Error.COMMAND_LINE_ERROR);
            }

            // Create separate lists of 'flag' args prefixed with '-' and those that
            // are not.
            List<string> flagArgs = new List<string>();
            List<string> regularArgs = new List<string>();

            foreach (string arg in args)
            {
                if (Strings.IsNumeric(arg))
                {
                    regularArgs.Add(arg);
                }
                else if (arg.StartsWith("-"))
                {
                    flagArgs.Add(arg);
                }
                else
                {
                    regularArgs.Add(arg);
                }
            }

            // Parse the flags.
            foreach (string arg in flagArgs)
            {
                // Check that we don't just have a minus character.
                if (arg.Length == 1)
                {
                    Console.Write("\r\n Invalid flag: '{0}'", arg);
                    WriteUsageToConsole();
                    Application.ExitQuietly(Error.COMMAND_LINE_ERROR);
                }

                // Process the flags.
                string flag = arg.Substring(0, 2).ToUpper();
                switch (flag)
                {
                    case "-O":
                        Info.DestName = arg.Substring(2);

                        if (Strings.HasValidFileNameChars(Info.DestName))
                        {
                            TsipReportHelper.OutputToFiles = true;
                        }
                        else
                        {
                            string str = " ERROR: string following -o contains invalid characters.";
                            Log2.e("\n\nTpRunTsip.ParseCommandLineArguments(): " + str);
                            Application.Exit(str, 1);
                        }
                        break;
                    case "-U":
                        mMicsUserViaCommandLine = arg.Substring(2);

                        if (String.IsNullOrWhiteSpace(mMicsUserViaCommandLine))
                        {
                            string str = " ERROR: string following -u must be a valid MICSUSER name.";
                            Log2.e("\n\nTpRunTsip.ParseCommandLineArguments(): " + str);
                            Application.Exit(str, 1);
                        }
                        break;
                    case "-T":
                        if (arg.ToUpper() == "-T") TsipReportHelper.OutputToTable = true;
                        break;
                    default:
                        Console.Write("\r\n ERROR: Invalid flag: {0}\r\n", arg);
                        WriteUsageToConsole();
                        Application.ExitQuietly(Error.COMMAND_LINE_ERROR);
                        break;
                }
            }

            // Parse the mandatory arguments; there must be qty. 3 of them.
            if (regularArgs.Count != 3)
            {
                Console.Write("\r\n ERROR: Invalid number of arguments.\r\n");
                WriteUsageToConsole();
                Application.ExitQuietly(Error.COMMAND_LINE_ERROR);
            }

            // Parse the args.
            Info.DbName = regularArgs[0];
            Info.ProjectCode = regularArgs[1];

            // This is more precisely the XXX in the parameter table schema.tp_XXX_parm
            Info.PdfName = regularArgs[2];

            //...Log2.v("\nInfo.DbName      = " + Info.DbName);
            //...Log2.v("\nInfo.ProjectCode = " + Info.ProjectCode);
            //...Log2.v("\nInfo.DestName    = " + Info.DestName);
            //...Log2.v("\nInfo.PdfName     = " + Info.PdfName);
        }

        /// <summary>
        /// This method attempts to get the values of a prescribed set of
        /// environmental variables that the USER may have set in the Windows
        /// environment in which this application is being executed. 

        /// </summary>
        /// <remarks>
        /// Only two 
        /// variables *must* be set in the User's environment: 'MICSUSER' and 
        /// 'PASSWORD'. The actual value of PASSWORD can be anything; TSIP does 
        /// not use its value.
        /// </remarks>
        /// <param name=""></param>
        private static void GetEnvVarsAndSysData()
        {
            // Windows environment.
            Info.MicsUserName = Environment.GetEnvironmentVariable("MICSUSER");     // REQUIRED.
            Info.Password = Environment.GetEnvironmentVariable("PASSWORD");         // REQUIRED (but can be anything).
            Info.MicsCtxCalc = Environment.GetEnvironmentVariable("MICS_CTX_CALC");
            Info.FcsaMaps50K = Environment.GetEnvironmentVariable("FCSAMAPS50K");
            Info.FcsaMaps250K = Environment.GetEnvironmentVariable("FCSAMAPS250K");
            Info.TsipReportsDir = Environment.GetEnvironmentVariable("TARGETDIRFORTSIPREPORTS");
            Info.WorkDir = Environment.GetEnvironmentVariable("WORK_DIR");

            // If TpRunTsip is launched using WebMICS, as a process spawned by 
            // TsipInitiator, then WebMICS sets MICSUSER and PASSWORD as per
            // the user's WebMICS login paramaters.

            // Check if the value to be used for MICSUSER was prescribed on the command-line.
            if (!String.IsNullOrWhiteSpace(mMicsUserViaCommandLine))
            {
                Info.MicsUserName = mMicsUserViaCommandLine;
            }

            // MICSUSER *must* be set in the user's environment.
            if (Info.MicsUserName == null)
            {
                Log2.e("\nTpRunTsip.GetEnvVarsAndSysData(): ERROR: Environment variable MICSUSER is not set.");
                Application.Exit(387);
            }

            // PASSWORD *should* be set in the user's environment but it can have 
            // any non-blank value.
            if (Info.Password == null)
            {
                //...Log2.v("\nTpRunTsip.GetEnvVarsAndSysData(): Environment variable PASSWORD is not set.");
                Info.Password = "TheUserDidNotSetApassword";
            }

            // Set the TSIP reports directory.
            // If this instance of TpRunTsip was spawned by TsipInitiator then
            // the required TSIP reports directory is passed via the environment
            // variable TARGETDIRFORTSIPREPORTS.
            //
            // TpRunTsip.exe checks to see if TARGETDIRFORTSIPREPORTS has been set.
            //     - If TARGETDIRFORTSIPREPORTS is set then its value provides the 
            //       target directory for the TSIP reports.
            //     - If TARGETDIRFORTSIPREPORTS is not set then the TSIP reports 
            //       are written to the Windows environment's current directory.

            if (Info.TsipReportsDir == null)
            {
                // The environment variable TARGETDIRFORTSIPREPORTS has not been set.
                // We need to provide an alternative destination for the TSIP report files.
                // Use the directory Windows defaults to for File i/0 for relative file paths;
                // If TpRunTsip is run in a Windows command prompt window, the default relative
                // directory is the current directory.
                //...Log2.v("\nTpRunTsip.GetEnvVarsAndSysData(): Environment variable TARGETDIRFORTSIPREPORTS is not set.");

                Info.TsipReportsDir = "";
            }
            else
            {
                // Ensure that the last char is a backslash.
                if (!Strings.LastCharIs(Info.TsipReportsDir, '\\'))
                {
                    Info.TsipReportsDir += @"\";
                }
            }

            //...Log2.v("\nInfo:\n" + Info.ToString());

        }


        /// <summary>
        /// This method creates the TSIP error file (truncating it if runname is
        /// NULL), and redirects output to it before each Tsip parameter record is
        /// processed. For each Tsip parameter record, a header is created that
        /// includes the runname. This is neccessary because the reports redirect
        /// the output, and the errors would be written to the EXEC report if this
        /// were not done.
        /// </summary>
        /// <param name="destname"> - the destination name given by the user.</param>
        /// <param name="tempName"> - the name of the Parameter file.</param>
        /// <param name="runname"> - the run name given within the Parameter record 
        /// (null indicates that the file is to be created and truncated for the beginning of the TSIP run.</param>
        /// <returns>Constant.SUCCESS or Constant.FAILURE</returns>
        private static int CreateErrorFile(string destname, string tempName, string runname)
        {
            //...Log2.v("\nTpRunTsip.CreateErrorFile(): Entry: " + destname + "   " + tempName);

            string errorrep;
            string shortrunname;
            string cDate;
            string cTime;

            // The first call to CreateErrorFile() should have runname set to null to
            // indicate that the error report file is to be created and truncated for 
            // for the beginning of the TSIP run.
            // Subsequent calls to CreateErrorFile() should set runname to a non-null 
            // value indicating that we will append to the existing contents of the 
            // error report file.
            if (runname == null)
            {
                //...Log2.v("\nTpRunTsip.CreateErrorFile(): runname is NULL.");

                // If redirection of output to file was NOT prescribed on the command line
                // then we just have to set the mTW_ERR TextWriter stream to standard Console.Out
                if (TsipReportHelper.OutputToFiles)
                {
                    // Construct the full name of the error report file.
                    errorrep = Info.TsipReportsDir + String.Format("{0}_{1}.ERR", destname, tempName);

                    // There is only one ERR report created even if the parameter file comprises multiple runs.
                    // Hence the following are statics.
                    TsipReportHelper.ErrWritten = true;
                    TsipReportHelper.ErrFilePath = errorrep;

                    try
                    {
                        System.IO.File.Delete(destname);
                        string path = Path.Combine(Info.TsipReportsDir, errorrep);
                        mTW_ERR = new StreamWriter(path, false);  // Truncate.

                        //...Log2.v("\nTpRunTsip.CreateErrorFile(): error report = " + path);
                    }
                    catch (Exception e)
                    {
                        // Could not open error report file for writing.
                        Log2.e("\nTpRunTsip.CreateErrorFile(): ERROR: " + e.Message);
                        string str = String.Format("\nERROR OPENING ERROR FILE - '{0}'\n", errorrep);
                        Log2.e(str);
                        return Constant.FAILURE;
                    }
                }
                else
                {
                    //...Log2.v("\nTpRunTsip.CreateErrorFile(): error report: to stdout");
                    mTW_ERR = mStandardConsoleOut;
                }
            }
            else  // not the first call
            {
                //...Log2.v("\nTpRunTsip.CreateErrorFile(): runname is not NULL.");

                GenUtil.UtGetDateTime(out cDate, out cTime);
                shortrunname = runname.Trim();
                StringBuilder sb = new StringBuilder();
                sb.Append("\r\nFREQUENCY COORDINATION SYSTEM ASSOCIATION\r\n\r\n");
                sb.Append(String.Format("TSIP build {0} Error Report for Run Name '{1}', at {2} {3}\r\nProject Code [{4}] Process ID {5}\r\n",
                                        Info.BuildMetaData, shortrunname, cDate, cTime, Info.ProjectCode, Info.ProcessID));
                mTW_ERR.Write(sb);
                mTW_ERR.Flush();
            }

            //...Log2.v("\nTpRunTsip.CreateErrorFile(): runname = " + runname);
            return (Constant.SUCCESS);
        }

        /// <summary>
        /// ParmFileInit reads the parameter records from a DB 'tt_*_parm' table, and stores 
        /// them in an internal array of parameter records.  
        /// </summary>
        /// <param name="tempName"> - prescribed unique file name substring.</param>
        /// <param name="parmTableCount"> - provides a cummulative 'running' count of parm tables.</param>
        /// <param name="currParmTableList"> - list of ParmTableWN objects; WN = 'with nulls'.</param>
        /// <returns></returns>
        private static int ParmFileInit(string tempName, ref int parmTableCount, out List<ParmTableWN> currParmTableList)
        {
            //...Log2.v("\nTpRunTsip.ParmFileInit(): Entry");

            string tableName;
            int parmHandle;
            int rc;
            currParmTableList = null;

            GenUtil.UtCvtName(Constant.TP_PARM, tempName, out tableName);

            /* initialize */
            string str = String.Format("\r\n{0}\r\n{0} TSIP PARAMETER FILE NAME: {1}\r\n{0} Project Code [{2}]\r\n",
                Constant.COMMENT_CHAR, tempName, Info.ProjectCode);
            mTW_ERR.Write(str);

            // Read all parameter records from file and populate the parameter table.
            parmHandle = TpDynParm.TpSelectParm(tableName, "", "runname");

            if (parmHandle < 0)
            {
                mTW_ERR.Write("\r\n*ERROR* parmFileInit: Could not open parameter table ({0}):-\r\n{1}\r\n",
                                parmHandle, GenUtil.GetUserMess());
                Log2.e("\n\nTpRunTsip.ParmFileInit(): call to TpDynParm.TpSelectParm() FAILED for tableName = " + tableName);
                return (parmHandle);
            }

            //...Log2.v("\n\nTpRunTsip.ParmFileInit(): call to TpDynParm.TpSelectParm() SUCCEEDED for tableName = " + tableName);

            TpParm tpParm;
            SQLLEN[] nullInd;
            currParmTableList = new List<ParmTableWN>();

            while ((rc = TpDynParm.TpFetchParm(parmHandle, out tpParm, out nullInd)) == Constant.SUCCESS)
            {
                ParmTableWN parmTable = new ParmTableWN();
                parmTable.parmStruct = tpParm;
                parmTable.parmNulls = nullInd;
                currParmTableList.Add(parmTable);

                parmTableCount++;
                if (parmTableCount >= Constant.MAXPARMREC)
                {
                    ErrMsg.UtPrintMessage(Error.MAXPARMS, Constant.MAXPARMREC.ToString());
                    break;
                }
            }

            if (rc != Constant.NOMORERECS)
            {
                mTW_ERR.Write("\r\n*ERROR* parmFileInit: Could not fetch parameter record({0}):-\r\n{1}\r\n",
                                    rc, GenUtil.GetUserMess());
                return (rc);
            }

            TpDynParm.TpCloseParm(parmHandle);

            //...Log2.v("\nTpRunTsip.ParmFileInit(): Exit");
            return (Constant.SUCCESS);
        }

        /// <summary>
        /// This method deletes any existing reports produced by previous runs
        /// of TSIP with the same destination directory argument as the current run.
        /// </summary>
        /// <param name="destName"> - directory that new TSIP reports shall be written to.</param>
        /// <param name="tempName"> - PDF table name</param>
        /// <param name="runName"> - name that User prescribed to identify this run.</param>
        public static void RemoveStudyFiles(string destName, string tempName, string runName)
        {
            if (destName == null || tempName == null || runName == null)
            {
                Log2.e("\nTpRunTsip.RemoveStudyFiles(): Error: at least one of the three input strings was null.");
                return;
            }

            // Just in case ...
            destName = destName.Trim();
            tempName = tempName.Trim();
            runName = runName.Trim();

            string fileStub = String.Format("{0}_{1}_{2}", destName, tempName, runName);

            // Behaviour of File.Delete(): 
            // If the file to be deleted does not exist, no exception is thrown.
            // There are many reasons why an exception *could* be thrown, 
            // e.g. the file path is invalid, the user does not have sufficient permissions,
            // the specified file has been openned for use by another process etc.
            try
            {
                /*	If there is a destName, then these files may have been created */
                System.IO.File.Delete(fileStub + ".EXEC");

                System.IO.File.Delete(fileStub + ".STATSUM");

                System.IO.File.Delete(fileStub + ".CASEDET");

                System.IO.File.Delete(fileStub + ".CASESUM");

                System.IO.File.Delete(fileStub + ".STUDY");

                System.IO.File.Delete(fileStub + ".ORBIT");

                System.IO.File.Delete(fileStub + ".AGGINTREP");

                System.IO.File.Delete(fileStub + ".HILO");

                System.IO.File.Delete(fileStub + "_ts.EXPORT");

                System.IO.File.Delete(fileStub + "_es.EXPORT");

                /*	If this is created, it always created as a file */
                System.IO.File.Delete(fileStub + ".CSV");
            }
            catch (Exception e)
            {
                Log2.e("\nTpRunTsip.RemoveStudyFiles(): Error: File.Delete() threw an exception: " + e.Message);
            }

            //...Log2.v("\nTpRunTsip.RemoveStudyFiles(): fileStub = " + fileStub);
            return;
        }

        /// <summary>
        /// This method prints a flat-file representation of the current record, and 
        /// copies the record to a 'tt_*_parm' or 'te_*_parm' table to be saved as part of 
        /// the SH Tables.  
        /// </summary>
        /// <param name="currParm"> - ParmTableWN object containing parameter values and associated ODBC nullInds. </param>
        /// <returns></returns>
        public static int ParmRecInit(ParmTableWN currParm)
        {
            //...Log2.v("\nTpRunTsip.ParmRecInit(): Entry");

            bool isValid;         /* return code from TsipValid */
            string type;    /* ES or TS - type of pdf */

            /*	Zero the maximums for the calculations and the report */
            mdTxTro = 0.0;
            mdRxTro = 0.0;
            mdTxPre = 0.0;
            mdRxPre = 0.0;

            StringBuilder sb = new StringBuilder();
            sb.Append("Proposed type...........: {0}\r\n");
            sb.Append("Environment type........: {1}\r\n");
            sb.Append("Proposed Name...........: {2}\r\n");
            sb.Append("Environment Name........: {3}\r\n");
            sb.Append("TSORB Report............: {4}\r\n");
            sb.Append("Loss Calculation Type...: {5}\r\n");
            sb.Append("Frequency Separation....: {6:#.00}");

            mTW_ERR.Write(sb.ToString(),
                            currParm.parmStruct.protype.Trim(),
                            currParm.parmStruct.envtype.Trim(),
                            currParm.parmStruct.proname.Trim(),
                            currParm.parmStruct.envname.Trim(),
                            currParm.parmStruct.tsorbout.Trim(),
                            currParm.parmStruct.spherecalc.Trim(),
                            currParm.parmStruct.fsep);

            //	Set the frequency separation for the band adjacency seaisValidh
            Suutils.SuSetAdjFreq(currParm.parmStruct.fsep);

            if (currParm.parmStruct.protype.Equals("E"))
            {
                /*	Es Coordination distance is taken from the antenna records */
                string cLastLoc = "";
                string cNextLoc;
                FeSiteStr feSiteStr;
                int nInd;

                mTW_ERR.Write("\r\nCoordination Distance...:- (by site)");
                while (FeUtils.FeNextSite(cLastLoc, out cNextLoc, out feSiteStr, 2,
                                                 currParm.parmStruct.proname) == 0)
                {
                    mTW_ERR.Write("\r\n             {0}   Call1            Tropo Precip",
                                 feSiteStr.stSite.location.PadRight(10));
                    for (nInd = 0; nInd < feSiteStr.nNumAnts; nInd++)
                    {
                        mTW_ERR.Write("\r\n                        : {0} TX {1,6:#.} {1,6:#.}\r\n                                       RX {2,6:#.} {3,6:#.}",
                                     feSiteStr.stAnts[nInd].call1.PadRight(12),
                                     feSiteStr.stAnts[nInd].txtro, feSiteStr.stAnts[nInd].txpre,
                                     feSiteStr.stAnts[nInd].rxtro, feSiteStr.stAnts[nInd].rxpre);

                        /*	Now save the maximums for the Study report */
                        if (feSiteStr.stAnts[nInd].txtro > mdTxTro)
                        {
                            mdTxTro = feSiteStr.stAnts[nInd].txtro;
                        }
                        if (feSiteStr.stAnts[nInd].txpre > mdTxPre)
                        {
                            mdTxPre = feSiteStr.stAnts[nInd].txpre;
                        }
                        if (feSiteStr.stAnts[nInd].rxtro > mdRxTro)
                        {
                            mdRxTro = feSiteStr.stAnts[nInd].rxtro;
                        }
                        if (feSiteStr.stAnts[nInd].rxpre > mdRxPre)
                        {
                            mdRxPre = feSiteStr.stAnts[nInd].rxpre;
                        }
                    }

                    cLastLoc = cNextLoc;  /*	Get the next after this. */
                }

                // Store the max for final printout.
                // We intentionally do not set the corresponding nullInd for the coordist column
                // so that, if it is initially NULL in the Parm table, then it is written back to
                // the Parm table as a NULL.
                currParm.parmStruct.coordist = Max(Max(mdTxTro, mdTxPre), Max(mdRxTro, mdRxPre));
            }
            else
            {
                /*	Tx coordination distance is taken from the input parameters. */
                mTW_ERR.Write("\r\nCoordination Distance...: {0:#.00}", currParm.parmStruct.coordist);
            }

            mTW_ERR.Write("\r\nAnalysis Option.........: {0}\r\nMargin Requested........: {1:0.00}\r\nChannel Status Codes....: ({2}) {3}\r\nCountry Selection.......: {4}\r\nSite Selection..........: {5}\r\nCodes...................: ({6}) {7}\r\nRun Name................: {8}\r\nKeyword Parameter Field.: \"{9}\"\r\nDate....................: {10}\r\nTime....................: {11}\r\n",
                         currParm.parmStruct.analopt.Trim(),
                         currParm.parmStruct.margin,
                         currParm.parmStruct.numchan,
                         currParm.parmStruct.chancodes.Trim(),
                         currParm.parmStruct.country.Trim(),
                         currParm.parmStruct.selsites.Trim(),
                         currParm.parmStruct.numcodes,
                         currParm.parmStruct.codes.Trim(),
                         currParm.parmStruct.runname.Trim(),
                         currParm.parmStruct.parmparm.Trim(),
                         currParm.parmStruct.mdate.Trim(),
                         currParm.parmStruct.mtime.Trim());

            mTW_ERR.Write(Error.MsgForCode(Error.WORKING) + "\r\n");
            mTW_ERR.Flush();

            // --- This section checks validation status -----------------------------------------

            /* check validation of proposed pdf */
            int retCode;

            if (currParm.parmStruct.protype.Equals("E"))
            {
                type = "ES";
                isValid = TsipValid(Constant.FE, currParm.parmStruct.proname, out retCode);
            }
            else
            {
                type = "TS";
                isValid = TsipValid(Constant.FT, currParm.parmStruct.proname, out retCode);
            }

            if (!isValid)
            {
                if (retCode == Constant.FAILURE)
                {
                    ErrMsg.UtPrintMessage(Error.NOTTSIPVALID, type, currParm.parmStruct.proname);
                }
                Log2.e("\nTpRunTsip.ParmRecInit(): ERROR: TsipValid() returned false: A");
                return (retCode);
            }

            // check validation of environment pdf ------------------------------------------------
            if (currParm.parmStruct.envtype.Equals("PDF_ES"))
            {
                type = "ES";
                isValid = TsipValid(Constant.FE, currParm.parmStruct.envname, out retCode);
            }
            else if (currParm.parmStruct.envtype.Equals("PDF_TS"))
            {
                type = "TS";
                isValid = TsipValid(Constant.FT, currParm.parmStruct.envname, out retCode);
            }

            if (!isValid)
            {
                if (retCode == Constant.FAILURE)
                {
                    ErrMsg.UtPrintMessage(Error.NOTTSIPVALID, type, currParm.parmStruct.envname);
                }
                Log2.e("\nTpRunTsip.ParmRecInit(): ERROR: TsipValid() returned false: B");
                return (retCode);
            }

            //...Log2.v("\nTpRunTsip.ParmRecInit(): Exit: SUCCESS");
            return (Constant.SUCCESS);
        }

        /// <summary>
        /// TsipValid checks the validation status of the proposed file, and the 
        /// environment file for proper validation to run TSIP.  
        /// </summary>
        /// <param name="tableType"> - eponym</param>
        /// <param name="tableName"> - eponym</param>
        /// /// <param name="retCode"> - return code.</param>
        /// <returns></returns>
        static bool TsipValid(int tableType, string tableName, out int retCode)
        {
            // 'out' requirement.
            retCode = Int32.MinValue;

            string validatedFor;
            bool result = false;

            if (FilewUtil.UtFilewValidated(tableType, tableName, out validatedFor) != Constant.SUCCESS)
            {
                // False.
                retCode = Error.FILEWVAL;
                return false;
            }

            switch (validatedFor[0])
            {
                case Constant.TSIP_VALIDATED:
                case Constant.UPDATE_VALIDATED:
                case Constant.UPDATE_POSTED:
                    retCode = Constant.SUCCESS;
                    result = true;
                    break;
                case Constant.M_UPDATE_VALIDATED:
                case Constant.M_TSIP_VALIDATED:
                    TpRunTsip.mTW_ERR.Write("\nSome sites are missing.  Links to them will be ignored in processing.\n");
                    retCode = Constant.SUCCESS;
                    result = true;
                    break;
                default:
                    // Must be false.
                    retCode = Constant.FAILURE;
                    result = false;
                    break;
            }

            return result;
        }

        /// <summary>
        /// This methods constructs a textual .ORBIT report and
        /// writes it to a file.
        /// </summary>
        /// <param name="destname"> - target directory.</param>
        /// <param name="tempName"> - name of PDF file.</param>
        /// <param name="runname"> - User prescribed ID for this run.</param>
        /// <returns></returns>
        static int CreateOrbitFile(string destname, string tempName, string runname)
        {
            // The Orbit textWriter is already instantiated.

            string projCode;
            GenUtil.GetProjectCode(out projCode);

            StringBuilder sb = new StringBuilder();

            sb.Append("                    ");
            sb.Append("FREQUENCY COORDINATION SYSTEM ASSOCIATION\r\n\r\n\r\n");
            sb.Append("                                 ");
            sb.Append("MICS Orbit Report\r\nProject Code ");
            sb.Append("[" + projCode + "]\r\n\r\n");

            mTW_ORBIT.Write(sb);
            mTW_ORBIT.Flush();

            return (Constant.SUCCESS);
        }

        /// <summary>
        /// This method updates the parameter table with the value of the current 
        /// parameter record.  
        /// </summary>
        /// <param name="numCases"> - number of cases.</param>
        /// <param name="numTeCases"> - number of TE cases.</param>
        /// <param name="parmName"> - name of paramater file.</param>
        /// <param name="currParm"> - ParmTableWN object containing paramter values and associated ODBC nullInds.</param>
        /// <returns> - Constant.SUCCESS or non-zero failure code.</returns>
        static int UpdateParmRec(int numCases, int numTeCases, string parmName, ParmTableWN currParm)
        {
            int rc, parmHandle;
            string select;

            TpParm tmpParm;
            SQLLEN[] tmpNulls = new SQLLEN[TpParm.NUM_COLUMNS];

            // Update parm rec w/ numCases.
            select = String.Format("runname = '{0}'", currParm.parmStruct.runname.PadRight(5));

            if ((parmHandle = TpDynParm.TpSelectParm(parmName, select, "")) >= 0)
            {
                if ((rc = TpDynParm.TpFetchParm(parmHandle, out tmpParm, out tmpNulls)) != Constant.SUCCESS)
                {
                    return (rc);
                }
                tmpParm.numcases = numCases;
                tmpParm.numtecases = numTeCases;
                tmpNulls[TpParm.NUMCASES] = Constant.DB_NOT_NULL;
                tmpNulls[TpParm.NUMTECASES] = Constant.DB_NOT_NULL;
                currParm.parmStruct.numcases = numCases;
                currParm.parmStruct.numtecases = numTeCases;

                if ((rc = TpDynParm.TpUpdateParm(parmHandle, tmpParm, tmpNulls)) != Constant.SUCCESS)
                {
                    return (rc);
                }

                TpDynParm.TpCloseParm(parmHandle);
            }
            else
            {
                return (parmHandle);
            }

            return (Constant.SUCCESS);
        }

        /// <summary>
        /// This method creates a '.STUDY' report and writes it out to file.
        /// </summary>
        /// <param name="dBaseName"> - name of DB.</param>
        /// <param name="tempname"> - name of PDF file.</param>
        /// <param name="pcode"> - project code.</param>
        /// <param name="currParm"> - ParmTableWN object providing parameter values and associated nullInds.</param>
        /// <param name="parmName"> - name of '_parm' parameter file.</param>
        /// <param name="siteName"> - eponym.</param>
        /// <param name="anteName"> - eponym.</param>
        /// <param name="chanName"> - eponym.</param>
        /// <param name="clocktime"> - eponym.</param>
        /// <param name="timediff"> - eponym.</param>
        /// <param name="numStns"> - number of stations.</param>
        /// <param name="tsesStns"> - number of TsEs stations.</param>
        /// <param name="estsStns"> - number of EsTs stations.</param>
        /// <param name="destname"> - name of directory that reports are to be written to.</param>
        /// <returns></returns>
        private static int ReportStudy(string dBaseName,
                                                string tempname,
                                                string pcode,
                                                ParmTableWN currParm,
                                                string parmName,
                                                string siteName,
                                                string anteName,
                                                string chanName,
                                                int clocktime,
                                                double timediff,
                                                int numStns,
                                                int tsesStns,
                                                int estsStns,
                                                string destname)
        {
            Console.WriteLine("\nTpRunTsip.ReportStudy(): Entry");

            int hours, minutes, seconds, cpuhour, cpumins, cpusecs, cpumsec, tempdiff;
            string cDistStr;
            int rc;
            string cTableName;

            string q;
            string r;
            string s;
            string t;
            string u;
            string v;
            string w;
            string x;
            string y;
            string et = "";
            bool IsTS;

            tempdiff = (int)timediff;
            minutes = (int)timediff / 60;
            hours = minutes / 60;
            minutes %= 60;
            seconds = tempdiff % 60;
            r = String.Format("{0:D2}:{1:D2}:{2:D2}", hours, minutes, seconds);

            cpumsec = clocktime % 1000;
            cpusecs = ((clocktime / 1000) % 60);
            cpumins = ((clocktime / 60000) % 60);
            cpuhour = (clocktime / 3600000);
            q = String.Format("{0:D2}:{1:D2}:{2:D2}.{3:D3}", cpuhour, cpumins, cpusecs, cpumsec);

            if ((currParm.parmStruct.protype.Equals("E")) ||
                (currParm.parmStruct.envtype.Equals("PDF_ES")) ||
                    (currParm.parmStruct.envtype.Equals("MDB_ES")))
            {
                s = String.Format("{0}", tsesStns);
                et = String.Format("{0}", estsStns);
                IsTS = false;   //	It's an es study
                Console.WriteLine("ES study");
            }
            else
            {
                s = String.Format("{0}", numStns);
                IsTS = true;
                Console.WriteLine("TS study");
            }

            Console.WriteLine("ReportStudy1");
            if (mReports.Exec)
            {
                t = "Y";
            }
            else
            {
                t = "N";
            }
            Console.WriteLine("ReportStudy1 t=" + t);
            Console.WriteLine("ReportStudy2");
            if ((mReports.TtStudy) ||
               (mReports.TeStudy) ||
               (mReports.EtStudy))
            {
                u = "Y";
            }
            else
            {
                u = "N";
            }
            Console.WriteLine("ReportStudy2 u=" + u);
            /*	Pass in the max coordination distances for an ETSTUDY  */
            Console.WriteLine("ReportStudy3");
            if (mReports.EtStudy)
            {
                cDistStr = String.Format("\",txtro=\"{0:F0}\",txpre=\"{1:F0}\",rxtro=\"{2:F0}\",rxpre=\"{3:F0}",
                                mdTxTro, mdTxPre, mdRxTro, mdRxPre);
                Console.WriteLine(cDistStr);
            }

            Console.WriteLine("ReportStudy4");
            if ((mReports.TsTsStn) ||
               (mReports.TsEsStn) ||
               (mReports.EsTsStn))
            {
                v = "Y";
            }
            else
            {
                v = "N";
            }
            Console.WriteLine("ReportStudy4 v=" + v);
            Console.WriteLine("ReportStudy5");
            if ((mReports.TsTsDet) ||
               (mReports.TsEsCase) ||
               (mReports.EsTsCase))
            {
                w = "Y";
            }
            else
            {
                w = "N";
            }
            Console.WriteLine("ReportStudy5 w=" + w);
            Console.WriteLine("ReportStudy6");
            if ((mReports.TsTsSum) ||
               (mReports.EsTsSum) ||
               (mReports.EsTsSum))
            {
                x = "Y";
            }
            else
            {
                x = "N";
            }
            Console.WriteLine("ReportStudy6 x=" + x);
            /*	The aggregate interference reports are carried in a two character field */
            Console.WriteLine("ReportStudy7");
            if ((mReports.AggIntRep))
            {
                y = "Y";
            }
            else
            {
                y = "N";
            }
            Console.WriteLine("ReportStudy7 y=" + y);
            Console.WriteLine("ReportStudy8");
            if ((mReports.AggIntCsv))
            {
                y += "Y";
            }
            else
            {
                y += "N";
            }
            Console.WriteLine("ReportStudy8 y=" + y);

            cTableName = String.Format("{0}_{1}", tempname, currParm.parmStruct.runname);
            if (cTableName.Length > Constant.MAX_DISP_TAB_LEN)
            {
                mTW_ERR.Write("\r\nreportStudy01: Output table name {0} is too long.  Max length is {1}\r\n",
                             cTableName, Constant.MAX_DISP_TAB_LEN);
                return Constant.FAILURE;
            }
            Console.WriteLine("ReportStudy9");
            if (IsTS && mReports.TtStudy)
            {
                mReports.StudyWritten = true;

                rc = Tstsrp1.TsTsRp1(mTW_STUDY, (currParm.parmStruct), cTableName, pcode, q, r, s, t, u, v, w, x, y);
                if (rc != Constant.SUCCESS)
                {
                    ErrMsg.UtPrintMessage(mTW_STUDY, Error.REPORT_ERROR);
                }

            }
            Console.WriteLine("ReportStudy10");
            if (!IsTS && mReports.TeStudy)
            {
                mReports.StudyWritten = true;

                rc = Tsesrp1.TsEsRp1(mTW_STUDY, (currParm.parmStruct), cTableName, pcode, q, r, s, t, u, v, w, x, et);
                if (rc != 0)
                {
                    ErrMsg.UtPrintMessage(mTW_STUDY, Error.REPORT_ERROR);
                }
            }
            Console.WriteLine("ReportStudy11");
            if (!IsTS && mReports.EtStudy)
            {
                mReports.StudyWritten = true;

                rc = Estsrp1.EsTsRp1(mTW_STUDY, currParm.parmStruct, cTableName, pcode, q, r, s, t, u, v, w, x, et,
                                         mdTxTro, mdRxTro, mdTxPre, mdRxPre, currParm.parmStruct.coordist);
                if (rc != 0)
                {
                    ErrMsg.UtPrintMessage(mTW_STUDY, Error.REPORT_ERROR);
                }
            }

            Console.WriteLine("\nTpRunTsip.ReportStudy(): Exit");
            return Constant.SUCCESS;
        }


        /// <summary>
        /// This method instantiates a set of TextWriter objects, one for each of the
        /// different report types.
        /// </summary>
        /// <param name="tableName"> - name of PDF.</param>
        /// <param name="runname"> - User prescribed unique ID for this run.</param>
        /// <param name="protype"> - User prescribed run type: either "T" for Terrestial Station or "E"" for Earth Station.</param>
        private static void OpenReportStreams(string tableName, string runname, string protype)
        {
            Console.Write("In OpenReportStreams\n");
            string aggintCsv;
            string aggintRep;
            string caseDet;
            string caseOhl;
            string caseSum;
            string exec;
            string hilo;
            string orbit;
            string statSum;
            string study;
            string export;

            string tsOrEs = protype == "T" ? "TS" : "ES";

            if (TsipReportHelper.OutputToFiles)
            {
                aggintCsv = String.Format("{0}_{1}_{2}.AGGINT.csv", Info.DestName, tableName, runname);
                aggintRep = String.Format("{0}_{1}_{2}.AGGINTREP", Info.DestName, tableName, runname);
                caseDet = String.Format("{0}_{1}_{2}.CASEDET", Info.DestName, tableName, runname);
                caseOhl = String.Format("{0}_{1}_{2}.CASEOHL", Info.DestName, tableName, runname);
                caseSum = String.Format("{0}_{1}_{2}.CASESUM", Info.DestName, tableName, runname);
                exec = String.Format("{0}_{1}_{2}.EXEC", Info.DestName, tableName, runname);
                export = String.Format("{0}_{1}_{2}.{3}_EXPORT", Info.DestName, tableName, runname, tsOrEs);
                hilo = String.Format("{0}_{1}_{2}.HILO", Info.DestName, tableName, runname);
                orbit = String.Format("{0}_{1}_{2}.ORBIT", Info.DestName, tableName, runname);
                statSum = String.Format("{0}_{1}_{2}.STATSUM", Info.DestName, tableName, runname);
                study = String.Format("{0}_{1}_{2}.STUDY", Info.DestName, tableName, runname);

                // Set the report file paths.
                mReports.AggIntCsvFilePath = Info.TsipReportsDir + aggintCsv;
                mReports.AggIntRepFilePath = Info.TsipReportsDir + aggintRep;
                mReports.CaseDetFilePath = Info.TsipReportsDir + caseDet;
                mReports.CaseOhlFilePath = Info.TsipReportsDir + caseOhl;
                mReports.CaseSumFilePath = Info.TsipReportsDir + caseSum;
                mReports.ExecFilePath = Info.TsipReportsDir + exec;
                mReports.ExportFilePath = Info.TsipReportsDir + export;
                mReports.HiloFilePath = Info.TsipReportsDir + hilo;
                mReports.OrbitFilePath = Info.TsipReportsDir + orbit;
                mReports.StatSumFilePath = Info.TsipReportsDir + statSum;
                mReports.StudyFilePath = Info.TsipReportsDir + study;


                Console.WriteLine("\n\nTpRunTsip.OpenReportStreams()1:\n");

                try
                {
                    // Instantiate all the StreamWriters.
                    mTW_AGGINTCSV = new StreamWriter(mReports.AggIntCsvFilePath, false);  // Truncate.
                    mTW_AGGINTREP = new StreamWriter(mReports.AggIntRepFilePath, false);  // Truncate.
                    mTW_CASEDET = new StreamWriter(mReports.CaseDetFilePath, false);  // Truncate.
                    mTW_CASEOHL = new StreamWriter(mReports.CaseOhlFilePath, false);  // Truncate.
                    mTW_CASESUM = new StreamWriter(mReports.CaseSumFilePath, false);  // Truncate.
                    mTW_EXEC = new StreamWriter(mReports.ExecFilePath, false);  // Truncate.
                    mTW_EXPORT = new StreamWriter(mReports.ExportFilePath, false);  // Truncate.
                    mTW_HILO = new StreamWriter(mReports.HiloFilePath, false);  // Truncate.
                    mTW_ORBIT = new StreamWriter(mReports.OrbitFilePath, false);  // Truncate.
                    mTW_STATSUM = new StreamWriter(mReports.StatSumFilePath, false);  // Truncate.
                    mTW_STUDY = new StreamWriter(mReports.StudyFilePath, false);  // Truncate.
                }
                catch (Exception e)
                {
                    // Could not open an output file for writing.
                    Console.WriteLine("TpRunTsip.OpenReportStreams ERROR: failed to open file for writing: \n" + e.Message);
                    Log2.e("\nTpRunTsip.OpenReportStreams(): ERROR: failed to open file for writing: \n" + e.Message);
                    //...Log2.v("\nERROR OPENING OUTPUT FILE - (STUDY)\n");
                    Application.Exit(666);
                }

            }
            else
            {
                Console.WriteLine("\n\nTpRunTsip.OpenReportStreams()5:\n");

                // All output streams are routed to Console.Out except the .csv file that
                // is always written to a disk file.
                mTW_AGGINTREP = mStandardConsoleOut;
                mTW_CASEDET = mStandardConsoleOut;
                mTW_CASEOHL = mStandardConsoleOut;
                mTW_CASESUM = mStandardConsoleOut;
                mTW_EXEC = mStandardConsoleOut;
                mTW_EXPORT = mStandardConsoleOut;
                mTW_HILO = mStandardConsoleOut;
                mTW_ORBIT = mStandardConsoleOut;
                mTW_STATSUM = mStandardConsoleOut;
                mTW_STUDY = mStandardConsoleOut;

                // Handle the special case of the AGGINT.csv report
                aggintCsv = String.Format("{0}_{1}_{2}.AGGINT.csv", Info.DestName, tableName, runname);
                mReports.AggIntCsvFilePath = aggintCsv;

                Console.WriteLine("\n\nTpRunTsip.OpenReportStreams()6:\n");

                try
                {
                    mTW_AGGINTCSV = new StreamWriter(aggintCsv, false);  // Truncate.
                }
                catch (Exception e)
                {
                    // Could not open an output file for writing.
                    Log2.e("\nTpRunTsip.OpenReportStreams(): ERROR: failed to open file for writing: \n" + e.Message);
                    //...Log2.v("\nERROR OPENING OUTPUT FILE - (STUDY)\n");
                    Application.Exit(666);
                }
                Console.WriteLine("\n\nTpRunTsip.OpenReportStreams()7:\n");

            }
        }

        /// <summary>
        /// This method flushes and closes all of the TextWriter objects that were previously
        /// created for each of the different report types.
        /// </summary>
        /// <param name=""></param>
        private static void CloseReportStreams()
        {
            if (TsipReportHelper.OutputToFiles)
            {
                mTW_AGGINTCSV.Close();
                mTW_AGGINTREP.Close();
                mTW_CASEDET.Close();
                mTW_CASEOHL.Close();
                mTW_CASESUM.Close();
                mTW_EXEC.Close();
                mTW_EXPORT.Close();
                mTW_HILO.Close();
                mTW_ORBIT.Close();
                mTW_STATSUM.Close();
                mTW_STUDY.Close();
            }
        }

        /// <summary>
        /// This method deletes any of the repertoir of report files that were
        /// written to disk that have no text content, i.e. file size is zero bytes. 
        /// </summary>
        /// <remarks>
        /// A report file is created but remains empty during a TSIP run if a report
        /// of that type is not explicitely requested by the MICS User. Thus, this method
        /// 'cleans up' unwanted report types.
        /// </remarks>
        /// <param name=""></param>
        private static void DeleteUnwantedReportFiles()
        {
            //...Log2.v("\n" + mReports);

            if (!mReports.AggIntCsvWritten)
            {
                DeleteFile(mReports.AggIntCsvFilePath);
            }

            if (!mReports.AggIntRepWritten)
            {
                DeleteFile(mReports.AggIntRepFilePath);
            }

            if (!mReports.CaseDetWritten)
            {
                DeleteFile(mReports.CaseDetFilePath);
            }

            if (!mReports.CaseOhlWritten)
            {
                DeleteFile(mReports.CaseOhlFilePath);
            }

            if (!mReports.CaseSumWritten)
            {
                DeleteFile(mReports.CaseSumFilePath);
            }

            if (!mReports.ExecWritten)
            {
                DeleteFile(mReports.ExecFilePath);
            }

            if (!mReports.ExportWritten)
            {
                DeleteFile(mReports.ExportFilePath);
            }

            if (!mReports.HiloWritten)
            {
                DeleteFile(mReports.HiloFilePath);
            }

            if (!mReports.OrbitWritten)
            {
                DeleteFile(mReports.OrbitFilePath);
            }

            if (!mReports.StatSumWritten)
            {
                DeleteFile(mReports.StatSumFilePath);
            }

            if (!mReports.StudyWritten)
            {
                DeleteFile(mReports.StudyFilePath);
            }

        }

        /// <summary>
        /// This method deletes an individual report file that was
        /// written to disk but has no text content, i.e. file size is zero bytes. 
        /// </summary>
        /// <remarks>
        /// A report file is created but remains empty during a TSIP run if a report
        /// of that type is not explicitely requested by the MICS User. Thus, this method
        /// 'cleans up' unwanted report types.
        /// </remarks>
        /// <param name="fileName"> - eponym.</param>
        private static void DeleteEmptyReports(string fileName)
        {
            if (TsipReportHelper.OutputToFiles)
            {
                if (System.IO.File.Exists(fileName))
                {
                    FileInfo fileInfo = new FileInfo(fileName);
                    if (fileInfo.Length == 0)
                    {
                        try
                        {
                            System.IO.File.Delete(fileName);
                        }
                        catch (Exception e)
                        {
                            Log2.e("\nTpRunTsip.DeleteFileIfExistsAndEmpty(): ERROR: File.Delete()");
                            Log2.e("\n" + e.Message);
                        }
                    }
                }
            }

        }

        /// <summary>
        /// This method checks whether the precribed file exists and,
        /// if so, deletes it.
        /// </summary>
        /// <param name="fileName"> - eponym.</param>
        private static void DeleteFile(string fileName)
        {
            if (System.IO.File.Exists(fileName))
            {
                FileInfo fileInfo = new FileInfo(fileName);

                try
                {
                    System.IO.File.Delete(fileName);
                }
                catch (Exception e)
                {
                    Log2.e("\nTpRunTsip.DeleteFileIfExistsAndEmpty(): ERROR: File.Delete()");
                    Log2.e("\n" + e.Message);
                }

            }
        }

        /// <summary>
        /// This method deletes the '.ORBIT' file from the repertoir of reports
        /// previously written to disk if the MICS User did not explicitely request
        /// an '.ORBIT' report.
        /// </summary>
        /// <param name=""></param>
        private static void DeleteOrbitReportIfNotRequested()
        {
            if (!mReports.Orbit)
            {
                if (System.IO.File.Exists(mReports.OrbitFilePath))
                {
                    try
                    {
                        System.IO.File.Delete(mReports.OrbitFilePath);
                    }
                    catch (Exception e)
                    {
                        Log2.e("\nTpRunTsip.DeleteOrbitReportIfNotRequested(): ERROR: File.Delete()");
                        Log2.e("\n" + e.Message);
                    }
                }
            }
        }

        /// <summary>
        /// Set up the various report types to be produced.  
        /// </summary>
        /// <param name="dBaseName"> - name of DB.</param>
        /// <param name="tempName"> - PDF name.</param>
        /// <param name="currParm"> - ParmTableWN object providing paramater values and associated ODBC nullInds.</param>
        /// <param name="numCases"> - number of cases.</param>
        /// <param name="numteCases"> - number of Te cases.</param>
        /// <param name="numStats"> - number of statistics to be reported.</param>
        /// <param name="viewName"> - name of the Tt PDF file.</param>
        /// <param name="destname"> - directory to which the reports are to be written.</param>
        /// <param name="cUnique"> - common DB report table name tag.</param>
        /// <param name="cUniqueEnv"> - DB report table name tag for '.STATSUM' report.</param>
        /// <param name="isTS"> - eponym.</param>
        /// <returns></returns>
        private static int ReportNew(string dBaseName,
                                         string tempName, ParmTableWN currParm,
                                      int numCases,
                                      int numteCases,
                                      int numStats,
                                      string viewName,
                                      string destname,
                                            string cUnique, /* stat rep table */
                                            string cUniqueEnv,
                                            bool isTS)
        {
            //...Log2.v("\nTpRunTsip.ReportNew(): Entry");

            int nRet;
            bool IsTSTSDet = false;
            bool IsTSESDet = false;
            bool IsESTSDet = false;
            bool IsES;
            bool IsTS;
            int nDist = 0;

            IsTS = isTS;
            IsES = !IsTS;

            /*++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
            + Set up the reports for the TS/TS TSIP reports
            +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++*/

            if (mReports.TsTsStn ||
                 mReports.TsEsStn ||
                 mReports.EsTsStn)
            {
                /*	One of the station lists is requested.  They all go to the same output
                *		file (.STATSUM) -- 1149 - GJS - 2007.08 */

                mReports.StatSumWritten = true;

                if (IsTS && mReports.TsTsStn)
                {
                    Tstsrp2.TsTsRp2(mTW_STATSUM, cUnique);

                    mTW_STATSUM.Flush();
                }


                /*++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                + Set up the reports for the TS/ES proposed TSIP reports
                +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++*/

                if (IsES &&
                        (currParm.parmStruct.protype.Equals("T") &&
                        (mReports.TsEsStn)) ||
                         (currParm.parmStruct.protype.Equals("E") &&
                        (mReports.EsTsStn)))
                {
                    if (numStats > 0)
                    {
                        nRet = Tsesprop.TsEsProp(mTW_STATSUM, cUnique);

                        mTW_STATSUM.Flush();
                    }
                }

                /*++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                + Set up the reports for the TS/ES proposed TSIP reports
                +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++*/

                if (IsES &&
                        (currParm.parmStruct.protype.Equals("T") &&
                         (mReports.TsEsStn)) ||
                        (currParm.parmStruct.protype.Equals("E") &&
                         (mReports.EsTsStn)))
                {
                    if (numStats > 0)
                    {
                        mTW_STATSUM.Write("\f");  //	Start on a new page.

                        nRet = Tsesenv.TsEsEnv(mTW_STATSUM, cUniqueEnv);

                        mTW_STATSUM.Flush();
                    }
                }

            }

            /*++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
            +		Set up the reports for the TSIP CASEDET reports
            +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++*/

            IsTSTSDet = mReports.TsTsDet;
            //	Set both if even one is present.
            IsESTSDet = mReports.EsTsCase ||
                                   mReports.TsEsCase;
            IsTSESDet = IsESTSDet;

            ErrMsg.SetDefaultOutputStream(mTW_CASEDET);

            if (IsTSTSDet || IsTSESDet || IsESTSDet)
            {
                if (IsTS && IsTSTSDet)
                {
                    mReports.CaseDetWritten = true;

                    if (numCases > 0)
                    {
                        //...Log2.v("\nTpRunTsip.ReportNew(): CASEDET, before call to TsTsRp3");

                        if (Tstsrp3.TsTsRp3(mTW_CASEDET, viewName, currParm.parmStruct, false) != Constant.SUCCESS)
                        {
                            ErrMsg.UtPrintMessage(mTW_CASEDET, Error.REPORT_ERROR);
                        }
                    }
                    else
                    {
                        //...Log2.v("\nTpRunTsip.ReportNew(): No TS-TS interference cases to report");
                        ErrMsg.UtPrintMessage(mTW_CASEDET, Error.GENERROR, "No TS-TS interference cases to report");
                    }
                }
            }
            mTW_CASEDET.Flush();

            // The Case detail ohloss only report.
            if (IsTS && mReports.TsTsOhl)
            {
                if (IsTSTSDet)
                {                    
                    // The following line was originally inside the the following if {} block
                    // so when there are no interference cases the CASEOHL report would not persist.
                    // Peter requested that a CASEOHL report always be generated even if there are 
                    // no interference cases.
                    mReports.CaseOhlWritten = true;

                    if (numCases > 0)
                    {
                        if (Tstsrp3.TsTsRp3(mTW_CASEOHL, viewName, currParm.parmStruct, true) != Constant.SUCCESS)
                        {
                            ErrMsg.UtPrintMessage(mTW_CASEOHL, Error.REPORT_ERROR);
                        }
                    }
                    else
                    {
                        ErrMsg.UtPrintMessage(mTW_CASEOHL, Error.GENERROR, "No TS-TS interference cases to report");
                    }
                }
            }
            mTW_CASEOHL.Flush();

            if (IsES && IsESTSDet)
            {
                mReports.CaseDetWritten = true;

                nRet = Estsrp3.EsTsRp3(mTW_CASEDET, viewName, currParm.parmStruct);
            }

            if (IsES && IsTSESDet)
            {
                mReports.CaseDetWritten = true;

                nRet = Tsesrp3.TsEsRp3(mTW_CASEDET, viewName, currParm.parmStruct);
            }

            mTW_CASEDET.Flush();

            /*++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
            +		Set up the TSIP CASESUM report.
            +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++*/

            if (IsTS && mReports.TsTsSum)
            {
                mReports.CaseSumWritten = true;

                if (numCases > 0)
                {
                    if (Tstsrp4.TsTsRp4(mTW_CASESUM, viewName) != Constant.SUCCESS)
                    {
                        ErrMsg.UtPrintMessage(mTW_CASESUM, Error.REPORT_ERROR);
                    }
                }
                else
                {
                    ErrMsg.UtPrintMessage(mTW_CASESUM, Error.GENERROR, "No interference cases to report");
                }
            }
            mTW_CASESUM.Flush();

            /*	Produce the Aggregate Interference report for TS - 1181 - GJS - 2006.01
            *		Ensure that AggInt reps are not run for BAND analysis, as we don't have
            *		the values stored. - GJS - 1219 - 2006.06.23 */
            if (IsTS &&
                    mReports.AggIntRep &&
                    !currParm.parmStruct.analopt.Equals("BAND"))
            {
                ParmStrct parms;
                string cCull;

                //WAS_FPRINTF("\n\f");    /*	Print a form feed */

                /*	Retrieve the Culling Margin from the parmparm field.  It is
                *	entered as CM=<margin> */
                parms = GenUtil.ParmBreakOut(currParm.parmStruct.parmparm);
                if (parms != null)
                {
                    cCull = GenUtil.ParmByName(parms, "CM");
                    if (cCull != null && cCull.Length > 0)
                    {
                        // The following conversion could throw an exception.
                        mdCull = Convert.ToDouble(cCull);
                    }
                }

                mReports.AggIntRepWritten = true;

                AggInt.AggIntRep(mTW_AGGINTREP, viewName, currParm.parmStruct.spherecalc, mdCull);

            }

            mTW_AGGINTREP.Flush();


            /*	Produce the Aggregate Interference CSV for TS - 1181 - GJS - 2006.01
            *		Ensure that AggInt reps are not run for BAND analysis, as we don't have
            *		the values stored. - GJS - 1219 - 2006.06.23 */
            if (IsTS &&
                    mReports.AggIntCsv &&
                    !currParm.parmStruct.analopt.Equals("BAND"))
            {
                ParmStrct parms;
                string cCull;

                /*	Retrieve the Culling Margin from the parmparm field.  It is
                *		entered as CM=<margin> */
                parms = GenUtil.ParmBreakOut(currParm.parmStruct.parmparm);
                if (parms != null)
                {
                    cCull = GenUtil.ParmByName(parms, "CM");
                    if (cCull != null && cCull.Length > 0)
                    {
                        // The following conversion could throw an exception.
                        mdCull = Convert.ToDouble(cCull);
                    }
                }

                mReports.AggIntCsvWritten = true;

                AggInt.AggIntCSV(mTW_AGGINTCSV, viewName, currParm.parmStruct.spherecalc, mdCull);

                mTW_STUDY.Write("\r\n\r\nAggregate Interference CSV report is in file: {0} ... \r\n", mReports.AggIntCsvFilePath);
                mTW_STUDY.Flush();

                mTW_AGGINTCSV.Flush();
            }

            /****************************************************************************\
            *
            *		If this is a TS (and if it is asked for) do the hilo check.
            *
            \****************************************************************************/

            if (mReports.HiloCheck && IsTS)
            {
                double dDistKm;
                string cDate;
                string cTime;
                ParmStrct parms;
                string cCull;

                /*	Retrieve the hilo check distance from the parmparm field.  It is
                *		entered as HILO=<distance in seconds> */
                parms = GenUtil.ParmBreakOut(currParm.parmStruct.parmparm);

                if (parms != null)
                {
                    cCull = GenUtil.ParmByName(parms, "HILO");
                    if (cCull != null && cCull.Length > 0)
                    {
                        // The following conversion could throw an exception.
                        nDist = Convert.ToInt32(cCull);
                    }
                }

                if (nDist >= 0)
                {
                    //	A negative nDist also means no report. 
                    /*	Open the report file */

                    if (nDist == 0)
                    {
                        nDist = 7;
                    }
                    dDistKm = nDist * 0.03087;  //	Convert from seconds at the earth's surface to Km.

                    GenUtil.UtGetDateTime(out cDate, out cTime);

                    mReports.HiloWritten = true;

                    mTW_HILO.Write("HiLoCheck Report for {0} for distance: {1:F2}Km ({2} Seconds)\r\nAt {3}, {4}\r\n",
                              currParm.parmStruct.proname, dDistKm, nDist, cDate, cTime);

                    nRet = HiLoAnalysis2021.HiloCheckFunc(currParm.parmStruct.proname, false, dDistKm, mTW_HILO);

                    if (nRet < 0)
                    {
                        mTW_HILO.Write("WARNING - There were hilo processing errors in the file.\r\n");
                    }
                    else
                    {
                        mTW_HILO.Write("There were {0} hilo violations.\r\n", nRet);
                    }
                }
            }

            //...Log2.v("\nTpRunTsip.ReportNew(): Exit, final.");
            return (Constant.SUCCESS);
        }

        /// <summary>
        /// This method manages the output of the TSIP execution report ('.EXEC').  
        /// </summary>
        /// <param name="tw"> - TextWriter object for .EXEC report.</param>
        /// <param name="tempName"> - PDF name.</param>
        /// <param name="currParm"> - TpParm object providing parameter values.</param>
        /// <param name="startTime"> - eponym.</param>
        /// <param name="startDate"> - eponym.</param>
        /// <param name="endTime"> - eponym.</param>
        /// <param name="endDate"> - eponym.</param>
        /// <param name="isTS"> - eponym.</param>
        /// <param name="numStnGroups"> - eponym.</param>
        /// <param name="tsesNumStns"> - eponym.</param>
        /// <param name="estsNumStns"> - eponym.</param>
        /// <param name="numIntCases"> - eponym.</param>
        /// <param name="numTeIntCases"> - eponym.</param>
        /// <param name="tsoCalc"> - NOT USED.</param>
        /// <param name="destname"> - directory into which the .EXEC report is to be written.</param>
        private static void TpExecRpt(TextWriter tw, string tempName, TpParm currParm,
                                        string startTime,
                                        string startDate,
                                        string endTime,
                                        string endDate,
                                        bool isTS,
                                        int numStnGroups,
                                        int tsesNumStns,
                                        int estsNumStns,
                                        int numIntCases,
                                        int numTeIntCases,
                                        string tsoCalc,
                                        string destname)
        {
            tw.Write("                    FREQUENCY COORDINATION SYSTEM ASSOCIATION {0,16}\r\n", Info.BuildMetaData);
            if (isTS == true)
            {
                tw.Write("                      MICS TSIP Ts-Ts Execution Information\r\n");
            }
            else
            {
                tw.Write("                  MICS TSIP Es-Ts / Ts-Es Execution Information\r\n");
            }
            tw.Write("   Inputs:\r\n");
            tw.Write("             Project Code:         {0}\r\n", Info.ProjectCode);
            tw.Write("             Parameter File Name:  {0}\r\n", tempName);
            tw.Write("             TSIP Run Name:        {0}\r\n", currParm.runname);
            tw.Write("   Outputs:\r\n");

            tw.Write("             Interference Tables\r\n");

            // The original C/C++ code used the printf format "%.10s" that means
            // write a string but truncate it if it is over 10 characters long.
            string tName;
            if (tempName.Length > 10)
            {
                tName = tempName.Substring(0, 10);
            }
            else
            {
                tName = tempName;
            }

            if (isTS == true)
            {
                tw.Write("                 tt_{0}_{1}_parm Table\r\n", tName, currParm.runname);
                tw.Write("                 tt_{0}_{1}_site Table\r\n", tName, currParm.runname);
                tw.Write("                 tt_{0}_{1}_ante Table\r\n", tName, currParm.runname);
                tw.Write("                 tt_{0}_{1}_chan Table\r\n", tName, currParm.runname);
            }
            else
            {
                tw.Write("                 te_{0}_{1}_parm Table\r\n", tName, currParm.runname);
                tw.Write("                 te_{0}_{1}_site Table\r\n", tName, currParm.runname);
                tw.Write("                 te_{0}_{1}_ante Table\r\n", tName, currParm.runname);
                tw.Write("                 te_{0}_{1}_chan Table\r\n", tName, currParm.runname);
            }

            if (!destname.Equals("\0"))
            {
                tw.Write("             Report files\r\n");
                if (mReports.Exec)
                {
                    tw.Write("                 {0}_{1}_{2}.EXEC (Execution Report)\r\n",
                        destname, tempName, currParm.runname);
                }

                if (mReports.TtStudy ||
                    mReports.TeStudy ||
                    mReports.EtStudy)
                {
                    tw.Write("                 {0}_{1}_{2}.STUDY (TSIP Study Report)\r\n",
                        destname, tempName, currParm.runname);
                }

                Console.WriteLine("TpRunTsip 2461 TsTs:" + mReports.TsTsStn + " TsEs " + mReports.TsEsStn + " EsTs " + mReports.EsTsStn);
                if (mReports.TsTsStn ||
                    mReports.TsEsStn ||
                    mReports.EsTsStn)
                {
                    tw.Write("                 {0}_{1}_{2}.STATSUM (Station Summary Report)\r\n",
                        destname, tempName, currParm.runname);
                }

                if (mReports.TsTsDet ||
                    mReports.TsEsCase ||
                    mReports.EsTsCase)
                {
                    tw.Write("                 {0}_{1}_{2}.CASEDET (Case Detail Report)\r\n",
                        destname, tempName, currParm.runname);
                }

                if (mReports.TsTsSum ||
                    mReports.TsTsSum ||
                    mReports.TsTsSum)
                {
                    tw.Write("                 {0}_{1}_{2}.CASESUM (Case Summary Report)\r\n",
                        destname, tempName, currParm.runname);
                }

                if (mReports.AggIntRep)
                {
                    tw.Write("                 {0}_{1}_{2}.AGGINTREP (Aggregate Interference Report)\r\n",
                        destname, tempName, currParm.runname);
                }

                if (mReports.AggIntCsv)
                {
                    tw.Write("                 {0}_{1}_{2}_AGGINT.CSV (Aggregate Interference CSV)\r\n",
                        destname, tempName, currParm.runname);
                }

                if (currParm.tsorbout.Equals("Y"))
                {
                    tw.Write("                 {0}_{1}_{2}.ORBIT (Orbit Report)\r\n",
                        destname, tempName, currParm.runname);
                }
            }

            tw.Write("\r\n");

            /*
             * TASK 421: Additional line to show user the Propogation Loss Model
             */
            tw.Write("   Propagation Loss Calculation Model:  ");
            switch (currParm.spherecalc)
            {
                case "1":
                    tw.Write("TSIP CCIR-SJM\r\n");
                    break;
                case "2":
                    tw.Write("Spherical Earth\r\n");
                    break;
                case "3":
                    tw.Write("Free Space\r\n");
                    break;
                case "4":
                    tw.Write("PCS\r\n");
                    break;
                case "5":
                    tw.Write("Over Horizon Loss\r\n");
                    break;
            }

            /*
             * TASK 466: Extra line to show Frequency Separation
             */
            tw.Write("   Maximum Frequency Separation      :  {0,7:F1}\r\n", currParm.fsep);
            tw.Write("   Coordination Distance             :  {0,7:F1}\r\n", currParm.coordist);
            if (isTS)
            {
                tw.Write("   Culling Margin used               :  {0,7:F1}\r\n", mdCull);
            }
            else
            {
                tw.Write("   Arc Step Value used               :  {0,7:F1}\r\n", mdArcStep);
            }


            if (isTS == true)
            {
                tw.Write("   Number of Station Groups Passed to Analysis:  {0}\r\n", numStnGroups);
            }
            else
            {
                tw.Write("   Number of TS->ES Station Groups Passed to Analysis:  {0}\r\n", tsesNumStns);
                tw.Write("   Number of ES->TS Station Groups Passed to Analysis:  {0}\r\n", estsNumStns);
            }

            if (isTS == true)
            {
                tw.Write("   Number of Interference Cases Reported:        {0}\r\n\r\n\r\n", numIntCases);
            }
            else
            {
                tw.Write("   Number of TS->ES Interference Cases Reported      :  {0}\r\n", numTeIntCases);
                tw.Write("   Number of ES->TS Interference Cases Reported      :  {0}\r\n\r\n\r\n", numIntCases);
            }
            tw.Write("   Start of TSIP Run                                End of TSIP Run\r\n");
            tw.Write("    Date: {0,-12}                               Date: {1,-12}\r\n", startDate, endDate);
            tw.Write("    Time: {0,-12}                               Time: {1,-12}\r\n", startTime, endTime);

            /*  Display caching information */
            {
                /*  Antenna Cache */
                int nCalls;
                int nHits;
                int nSize;
                int nUsed;

                tw.Write("\r\nCache info:-\r\nCache       Calls  Hits  Size  Used\r\n");

                Suutils.GetAntCacheInfo(out nCalls, out nHits, out nSize, out nUsed);
                tw.Write("Antennas.: {0,6:D}{1,6:D}{2,6:D}{3,6:D}\r\n", nCalls, nHits, nSize, nUsed);

                Suutils.GetEqptCacheInfo(out nCalls, out nHits, out nSize, out nUsed);
                tw.Write("Equipment: {0,6:D}{1,6:D}{2,6:D}{3,6:D}\r\n", nCalls, nHits, nSize, nUsed);

                Suutils.GetCTXCacheInfo(out nCalls, out nHits, out nSize, out nUsed);
                tw.Write("CTX Curve: {0,6:D}{1,6:D}{2,6:D}{3,6:D}\r\n", nCalls, nHits, nSize, nUsed);

                Suutils.GetCTXxCacheInfo(out nCalls, out nHits, out nSize, out nUsed);
                tw.Write("CTX Xref.: {0,6:D}{1,6:D}{2,6:D}{3,6:D}\r\n", nCalls, nHits, nSize, nUsed);

                CtxUtil.GetAnalogCacheInfo(out nCalls, out nHits, out nSize, out nUsed);
                tw.Write("Analog...: {0,6:D}{1,6:D}{2,6:D}{3,6:D}\r\n", nCalls, nHits, nSize, nUsed);

                CtxUtil.GetDigitalCacheInfo(out nCalls, out nHits, out nSize, out nUsed);
                tw.Write("Digital..: {0,6:D}{1,6:D}{2,6:D}{3,6:D}\r\n", nCalls, nHits, nSize, nUsed);

                tw.Write("\r\n");
            }

            tw.Flush();
        }

        /// <summary>
        /// This method creates and writes the content of the TSIP EXPORT report to file; the
        /// actual content creation is performed by executing FtPrint.exe or FePrint.exe in a
        /// Windows command shell.
        /// </summary>
        /// <param name="pdfName"> - the name of a DB PDF table set.</param>
        /// <param name="pdfType"> - the type of the PDF table set; "T" for TS or "E" for ES.</param>
        private static void TpExportRpt(string pdfName, string pdfType)
        {
            // USAGE: FtPrint <dbname> <projectCode> [-o<outFilePath>] <printFlag> <pdfName>
            // USAGE: FePrint <dbname> <projectCode>                               <pdfName>

            string programName = pdfType == "T" ? "FtPrint" : "FePrint";

            string programPath = Ssutil.GetBinPath(programName, Info.DbName);

            string[] clArgs = new string[4];
            clArgs[0] = Info.DbName;
            clArgs[1] = Info.ProjectCode;
            clArgs[2] = pdfType == "T" ? "X" : "";
            clArgs[3] = pdfName;

            // Run FtPrint or FePrint in a Windows  command shell with output to the shell's stdout.

            string stdout;
            string stderr;
            int exitCode;
            int retVal;

            retVal = WindowsShell.RunCommand(programPath, clArgs, out stdout, out stderr, out exitCode);

            if (retVal != Constant.SUCCESS)
            {
                stdout = String.Format("\r\nTpRunTsip.TpExportRpt(): ERROR: call to WindowsShell.RunCommand() failed for:\r\n\t{0} {1} {2} {3} {4}\r\n\tExitCode = {5}\r\n",
                                            programPath, clArgs[0], clArgs[1], clArgs[2], clArgs[3], exitCode);
                Log2.e("\n" + stdout);

                mTW_ERR.Write(stdout);
                mTW_ERR.Flush();
            }

            // Write the output of the FtPrint or FePrint to the assigned TextWriter.
            mTW_EXPORT.Write(stdout);
            mTW_EXPORT.Flush();
        }








    } // class
} // namespace
