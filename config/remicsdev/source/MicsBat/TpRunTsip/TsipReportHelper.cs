using _Configuration;
using _DataStructures;
using _NewLib;
using _Utillib;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace TpRunTsip
{
    /// <summary>
    /// Provides methods that help to keep track of
    /// the requirement to produce a User-defined set of reports
    /// from the multiplicity of available report types. This information
    /// is represented as a bitmap.
    /// </summary>
    /// <remarks>
    /// There are qty. 11 different types of report each with its own 
    /// Windows file extension:
    /// <list type="bullet">
    /// <item>.AGGINT.csv</item>
    /// <item>.AGGINT</item>
    /// <item>.CASEDET</item>
    /// <item>.CASEOHL</item>
    /// <item>.CASESUM</item>
    /// <item>.EXEC</item>
    /// <item>.EXPORT</item>
    /// <item>.HILO</item>
    /// <item>.ORBIT</item>
    /// <item>.STATSUM</item>
    /// <item>.STUDY</item>
    /// </list>
    /// </remarks>

    using SQLHANDLE = IntPtr;
    using SQLHDBC = IntPtr;
    using SQLHSTMT = IntPtr;
    using SQLLEN = Int64;
    using SQLPOINTER = IntPtr;
    using SQLRETURN = Int16;

    public class TsipReportHelper
    {
        // Static members.
        private static bool mOutputToFiles = false;
        private static bool mOutputToReportsTable = false;
        private static bool mReportsTableAlreadyCreated = false;
        private static string mReportsTableName = "";

        private static List<string> mListOfAllMD5 = new List<string>();

        public static bool OutputToFiles { get { return mOutputToFiles; } set { mOutputToFiles = value; } }
        public static bool OutputToTable { get { return mOutputToReportsTable; } set { mOutputToReportsTable = value; } }

        //-----------------------------------------------------------------

        // Requested file content flags.
        private bool mExec = false;
        private bool mTtStudy = false;
        private bool mTeStudy = false;
        private bool mEtStudy = false;
        private bool mTsTsStn = false;
        private bool mTsEsStn = false;
        private bool mEsTsStn = false;
        private bool mTsTsDet = false;
        private bool mTsTsSum = false;
        private bool mTsEsCase = false;
        private bool mEsTsCase = false;
        private bool mTsEsSum = false;
        private bool mEsTsSum = false;
        private bool mAggIntRep = false;
        private bool mAggIntCsv = false;
        private bool mTsTsOhl = false;
        private bool mHiloCheck = false;
        private bool mOrbit = false;
        private bool mExport = false;

        //----------------------------------------------------------------------------

        // Set to true when a report file is actually written to.
        private bool mAggIntCsvWritten = false;
        private bool mAggIntRepWritten = false;
        private bool mCaseDetWritten = false;
        private bool mCaseOhlWritten = false;
        private bool mCaseSumWritten = false;
        private bool mExecWritten = false;
        private bool mHiloWritten = false;
        private bool mOrbitWritten = false;
        private bool mStatSumWritten = false;
        private bool mStudyWritten = false;
        private bool mExportWritten = false;

        private static bool mErrWritten = false;

        //----------------------------------------------------------------------------

        // Report file paths.
        private string mAggIntCsvFilePath;
        private string mAggIntRepFilePath;
        private string mCaseDetFilePath;
        private string mCaseOhlFilePath;
        private string mCaseSumFilePath;
        private string mExecFilePath;
        private string mHiloFilePath;
        private string mOrbitFilePath;
        private string mStatSumFilePath;
        private string mStudyFilePath;
        private string mExportFilePath;

        private static string mErrFilePath;

        //----------------------------------------------------------------------------

        // MD5 checksum of normalized report content as hexadecimal strings.
        private string mAggIntCsvFileMD5;
        private string mAggIntRepFileMD5;
        private string mCaseDetFileMD5;
        private string mCaseOhlFileMD5;
        private string mCaseSumFileMD5;
        private string mExecFileMD5;
        private string mHiloFileMD5;
        private string mOrbitFileMD5;
        private string mStatSumFileMD5;
        private string mStudyFileMD5;
        private string mExportFileMD5;

        private static string mErrFileMD5;

        //----------------------------------------------------------------------------
        public bool Exec { get { return mExec; } }
        public bool TtStudy { get { return mTtStudy; } }
        public bool TeStudy { get { return mTeStudy; } }
        public bool EtStudy { get { return mEtStudy; } }
        public bool TsTsStn { get { return mTsTsStn; } }
        public bool TsEsStn { get { return mTsEsStn; } }
        public bool EsTsStn { get { return mEsTsStn; } }
        public bool TsTsDet { get { return mTsTsDet; } }
        public bool TsTsSum { get { return mTsTsSum; } }
        public bool TsEsCase { get { return mTsEsCase; } }
        public bool EsTsCase { get { return mEsTsCase; } }
        public bool TsEsSum { get { return mTsEsSum; } }
        public bool EsTsSum { get { return mEsTsSum; } }
        public bool AggIntRep { get { return mAggIntRep; } }
        public bool AggIntCsv { get { return mAggIntCsv; } }
        public bool TsTsOhl { get { return mTsTsOhl; } }
        public bool HiloCheck { get { return mHiloCheck; } }
        public bool Orbit { get { return mOrbit; } }
        public bool Export { get { return mExport; } }

        //----------------------------------------------------------------------------
        public string AggIntCsvFilePath { get { return mAggIntCsvFilePath; } set { mAggIntCsvFilePath = value; } }
        public string AggIntRepFilePath { get { return mAggIntRepFilePath; } set { mAggIntRepFilePath = value; } }
        public string CaseDetFilePath { get { return mCaseDetFilePath; } set { mCaseDetFilePath = value; } }
        public string CaseOhlFilePath { get { return mCaseOhlFilePath; } set { mCaseOhlFilePath = value; } }
        public string CaseSumFilePath { get { return mCaseSumFilePath; } set { mCaseSumFilePath = value; } }
        public string ExecFilePath { get { return mExecFilePath; } set { mExecFilePath = value; } }
        public string HiloFilePath { get { return mHiloFilePath; } set { mHiloFilePath = value; } }
        public string OrbitFilePath { get { return mOrbitFilePath; } set { mOrbitFilePath = value; } }
        public string StatSumFilePath { get { return mStatSumFilePath; } set { mStatSumFilePath = value; } }
        public string StudyFilePath { get { return mStudyFilePath; } set { mStudyFilePath = value; } }
        public string ExportFilePath { get { return mExportFilePath; } set { mExportFilePath = value; } }
        public static string ErrFilePath { get { return mErrFilePath; } set { mErrFilePath = value; } }

        public string AggIntCsvFileMD5 { get { return mAggIntCsvFileMD5; } set { mAggIntCsvFileMD5 = value; } }
        public string AggIntRepFileMD5 { get { return mAggIntRepFileMD5; } set { mAggIntRepFileMD5 = value; } }
        public string CaseDetFileMD5 { get { return mCaseDetFileMD5; } set { mCaseDetFileMD5 = value; } }
        public string CaseOhlFileMD5 { get { return mCaseOhlFileMD5; } set { mCaseOhlFileMD5 = value; } }
        public string CaseSumFileMD5 { get { return mCaseSumFileMD5; } set { mCaseSumFileMD5 = value; } }
        public string ExecFileMD5 { get { return mExecFileMD5; } set { mExecFileMD5 = value; } }
        public string HiloFileMD5 { get { return mHiloFileMD5; } set { mHiloFileMD5 = value; } }
        public string OrbitFileMD5 { get { return mOrbitFileMD5; } set { mOrbitFileMD5 = value; } }
        public string StatSumFileMD5 { get { return mStatSumFileMD5; } set { mStatSumFileMD5 = value; } }
        public string StudyFileMD5 { get { return mStudyFileMD5; } set { mStudyFileMD5 = value; } }
        public string ExportFileMD5 { get { return mExportFileMD5; } set { mExportFileMD5 = value; } }
        public static string ErrFileMD5 { get { return mErrFileMD5; } set { mErrFileMD5 = value; } }

        public bool AggIntCsvWritten { get { return mAggIntCsvWritten; } set { mAggIntCsvWritten = value; } }
        public bool AggIntRepWritten { get { return mAggIntRepWritten; } set { mAggIntRepWritten = value; } }
        public bool CaseDetWritten { get { return mCaseDetWritten; } set { mCaseDetWritten = value; } }
        public bool CaseOhlWritten { get { return mCaseOhlWritten; } set { mCaseOhlWritten = value; } }
        public bool CaseSumWritten { get { return mCaseSumWritten; } set { mCaseSumWritten = value; } }
        public bool ExecWritten { get { return mExecWritten; } set { mExecWritten = value; } }
        public bool HiloWritten { get { return mHiloWritten; } set { mHiloWritten = value; } }
        public bool OrbitWritten { get { return mOrbitWritten; } set { mOrbitWritten = value; } }
        public bool StatSumWritten { get { return mStatSumWritten; } set { mStatSumWritten = value; } }
        public bool StudyWritten { get { return mStudyWritten; } set { mStudyWritten = value; } }
        public bool ExportWritten { get { return mExportWritten; } set { mExportWritten = value; } }
        public static bool ErrWritten { get { return mErrWritten; } set { mErrWritten = value; } }
        //----------------------------------------------------------------------------

        // Bit-position versus report type.
        public const int EXEC = 0;
        public const int TTSTUDY = 1;
        public const int TESTUDY = 2;
        public const int ETSTUDY = 3;
        public const int TSTSSTN = 4;
        public const int TSESSTN = 5;
        public const int ESTSSTN = 6;
        public const int TSTSDET = 7;
        public const int TSTSSUM = 8;
        public const int TSESCASE = 9;
        public const int ESTSCASE = 10;
        public const int TSESSUM = 11;
        public const int ESTSSUM = 12;
        public const int AGGINTREP = 13;
        public const int AGGINTCSV = 14;
        public const int TSTSOHL = 15;
        public const int HILOCHECK = 16;
        public const int EXPORT = 17;

        // 32-bit integer value corresponding to just the 0th bit being set.
        private const uint BIT_ZERO = 0x80000000;

        //---------------------------------------------------------------------------

        /// <summary>
        /// This constructor method sets all report type bits to zero (i.e. 'not requested').
        /// </summary>
        /// <param name=""></param>
        /// <returns></returns>
        public TsipReportHelper()
        {
            SetAll(false);
        }

        /// <summary>
        /// This constructor method sets the private class bit flags using a prescribed
        /// integer 'mask'; it also tests whether tsorbout equals "Y" and, if so, 
        /// sets mOrbit to true..
        /// </summary>
        /// <param name=""></param>
        /// <returns></returns>
        public TsipReportHelper(int bitMask, string tsorbout)
        {
            SetUsingBitMask(bitMask);

            if (tsorbout.Equals("Y")) mOrbit = true;
        }

        /// <summary>
        /// This method sets all the internal (private) boolean flags
        /// to the prescribed true or false value. (true = report is requested).
        /// </summary>
        /// <param name="setting"></param>
        public void SetAll(bool setting)
        {
            mExec = setting;
            mTtStudy = setting;
            mTeStudy = setting;
            mEtStudy = setting;
            mTsTsStn = setting;
            mTsEsStn = setting;
            mEsTsStn = setting;
            mTsTsDet = setting;
            mTsTsSum = setting;
            mTsEsCase = setting;
            mEsTsCase = setting;
            mTsEsSum = setting;
            mEsTsSum = setting;
            mAggIntRep = setting;
            mAggIntCsv = setting;
            mTsTsOhl = setting;
            mHiloCheck = setting;
            mOrbit = setting;
            mExport = setting;
        }

        /// <summary>
        /// This method sets all the internal (private) boolean
        /// 'report requested' flags i.a.w. a prescribed bitmap.
        /// </summary>
        /// <param name="bitMask"></param>
        public void SetUsingBitMask(int bitMask)
        {
            mExec = TestBit(bitMask, EXEC);
            mTtStudy = TestBit(bitMask, TTSTUDY);
            mTeStudy = TestBit(bitMask, TESTUDY);
            mEtStudy = TestBit(bitMask, ETSTUDY);
            mTsTsStn = TestBit(bitMask, TSTSSTN);
            mTsEsStn = TestBit(bitMask, TSESSTN);
            mEsTsStn = TestBit(bitMask, ESTSSTN);
            mTsTsDet = TestBit(bitMask, TSTSDET);
            mTsTsSum = TestBit(bitMask, TSTSSUM);
            mTsEsCase = TestBit(bitMask, TSESCASE);
            mEsTsCase = TestBit(bitMask, ESTSCASE);
            mTsEsSum = TestBit(bitMask, TSESSUM);
            mEsTsSum = TestBit(bitMask, ESTSSUM);
            mAggIntRep = TestBit(bitMask, AGGINTREP);
            mAggIntCsv = TestBit(bitMask, AGGINTCSV);
            mTsTsOhl = TestBit(bitMask, TSTSOHL);
            mHiloCheck = TestBit(bitMask, HILOCHECK);
            mExport = TestBit(bitMask, EXPORT);
        }

        /// <summary>
        /// This method returns true if a prescribed bit position in a
        /// bitmap is set to 1.
        /// </summary>
        /// <param name="bitMap"></param>
        /// <param name="pseudoBitNum"></param>
        /// <returns></returns>
        private static bool TestBit(int bitMap, int pseudoBitNum)
        {
            uint mask;

            /* Check for valid bitnum */
            if (pseudoBitNum < 0 || (pseudoBitNum >= (1 << Constant.NUM_SHIFT)))
            {
                return (false);
            }

            mask = BIT_ZERO >> pseudoBitNum;
            // Test the bit.
            if ((bitMap & mask) > 0)
            {
                return (true);
            }
            else
            {
                return (false);
            }
        }

        /// <summary>
        /// The TSIP EXPORT report cannot be specifically requested by the user via WebMICS; instead
        /// the decision to create a TSIP EXPORT report is made in the TpRunTsip Main() code by calling
        /// this method.
        /// </summary>
        /// <param name="isRequested"> - true to request the creation of the TSIP EXPORT report.</param>
        public void RequestExportReport(bool isRequested)
        {
            if (isRequested)
            {
                mExport = true;
            }
            else
            {
                mExport = false;
            }
        }

        /// <summary>
        /// This method provides an annotated, formatted, multi-line
        /// string providing the current values of all private member
        /// boolean flags.
        /// </summary>
        /// <param name=""></param>
        /// <returns></returns>
        public override string ToString()
        {
            StringBuilder sb = new StringBuilder();

            sb.Append("\nmExec = " + mExec);
            sb.Append("\nmTtStudy   = " + mTtStudy);
            sb.Append("\nmTeStudy   = " + mTeStudy);
            sb.Append("\nmEtStudy   = " + mEtStudy);
            sb.Append("\nmTsTsStn   = " + mTsTsStn);
            sb.Append("\nmTsEsStn   = " + mTsEsStn);
            sb.Append("\nmEsTsStn   = " + mEsTsStn);
            sb.Append("\nmTsTsDet   = " + mTsTsDet);
            sb.Append("\nmTsTsSum   = " + mTsTsSum);
            sb.Append("\nmTsEsCase  = " + mTsEsCase);
            sb.Append("\nmEsTsCase  = " + mEsTsCase);
            sb.Append("\nmTsEsSum   = " + mTsEsSum);
            sb.Append("\nmEsTsSum   = " + mEsTsSum);
            sb.Append("\nmAggIntRep = " + mAggIntRep);
            sb.Append("\nmAggIntCsv = " + mAggIntCsv);
            sb.Append("\nmTsTsOhl = " + mTsTsOhl);
            sb.Append("\nmHiloCheck = " + mHiloCheck);
            sb.Append("\nmOrbit     = " + mOrbit);
            sb.Append("\nmExport    = " + mExport);
            sb.Append("\n");
            sb.Append("\nmAggIntCsvRequired = " + mAggIntCsvWritten);
            sb.Append("\nmAggIntRepRequired = " + mAggIntRepWritten);
            sb.Append("\nmCaseDetRequired   = " + mCaseDetWritten);
            sb.Append("\nmCaseOhlRequired   = " + mCaseOhlWritten);
            sb.Append("\nmCaseSumRequired   = " + mCaseSumWritten);
            sb.Append("\nmExecRequired      = " + mExecWritten);
            sb.Append("\nmHiloRequired      = " + mHiloWritten);
            sb.Append("\nmOrbitRequired     = " + mOrbitWritten);
            sb.Append("\nmStatSumRequired   = " + mStatSumWritten);
            sb.Append("\nmStudyRequired     = " + mStudyWritten);
            sb.Append("\nmExportRequired    = " + mExportWritten);
            sb.Append("\nmErrRequired       = " + mErrWritten);
            sb.Append("\n");
            sb.Append("\nmAggIntCsvFilePath = " + mAggIntCsvFilePath);
            sb.Append("\nmAggIntRepFilePath = " + mAggIntRepFilePath);
            sb.Append("\nmCaseDetFilePath   = " + mCaseDetFilePath);
            sb.Append("\nmCaseOhlFilePath   = " + mCaseOhlFilePath);
            sb.Append("\nmCaseSumFilePath   = " + mCaseSumFilePath);
            sb.Append("\nmExecFilePath      = " + mExecFilePath);
            sb.Append("\nmHiloFilePath      = " + mHiloFilePath);
            sb.Append("\nmOrbitFilePath     = " + mOrbitFilePath);
            sb.Append("\nmStatSumFilePath   = " + mStatSumFilePath);
            sb.Append("\nmStudyFilePath     = " + mStudyFilePath);
            sb.Append("\nmExportFilePath    = " + mExportFilePath);
            sb.Append("\nmErrFilePath       = " + mErrFilePath);

            return sb.ToString();
        }

        private static void CreateTsipReportsTable()
        {
            Log2.v("\n\nTsipReportHelper.CreateTsipReportsTable(): Entry");
            Log2.v(" " + mOutputToReportsTable);
            if (!mOutputToReportsTable) return;

            Log2.v(" " + mReportsTableAlreadyCreated);
            if (!mReportsTableAlreadyCreated)
            {
                //mReportsTableName = String.Format(Info.GlobalSchema + ".{0}.{1}_tsip_reports", Info.GlobalSchema, Info.PdfName);
                mReportsTableName = String.Format("{0}.{1}_tsip_reports", Info.GlobalSchema, Info.PdfName);
                DynTsipReports.DropTableIfExists(mReportsTableName);
                DynTsipReports.CreateTable(mReportsTableName);

                mReportsTableAlreadyCreated = true;
            }
        }

        public void WritePerRunReportsToDbTable()
        {
            Log2.v("\nin  WritePerRunReportsToDbTable-mOutputToReportsTable= " + mOutputToReportsTable);
            
            if (!mOutputToReportsTable) return;

            CreateTsipReportsTable();

            if (mAggIntCsvWritten)
            {
                CalculateMD5ofReport(mAggIntCsvFilePath);
            }

            if (mAggIntRepWritten)
            {
                CalculateMD5ofReport(mAggIntRepFilePath);
            }

            if (mCaseDetWritten)
            {
                CalculateMD5ofReport(mCaseDetFilePath);
            }

            if (mCaseOhlWritten)
            {
                CalculateMD5ofReport(mCaseOhlFilePath);
            }

            if (mCaseSumWritten)
            {
                CalculateMD5ofReport(mCaseSumFilePath);
            }

            if (mExecWritten)
            {
                CalculateMD5ofReport(mExecFilePath);
            }

            if (mExportWritten)
            {
                CalculateMD5ofReport(mExportFilePath);
            }

            if (mHiloWritten)
            {
                CalculateMD5ofReport(mHiloFilePath);
            }

            if (mOrbitWritten)
            {
                CalculateMD5ofReport(mOrbitFilePath);
            }

            if (mStatSumWritten)
            {
                CalculateMD5ofReport(mStatSumFilePath);
            }

            if (mStudyWritten)
            {
                CalculateMD5ofReport(mStudyFilePath);
            }

        }

        public void WriteRunReportToDbTable(string reportFilePath)
        {
            if (!mOutputToReportsTable) return;

            Log2.v("in WriteRunReportToDbTable");

            CreateTsipReportsTable();

            CalculateMD5ofReport(reportFilePath);
        }

        public string CalculateMD5ofReport(string reportFilePath)
        {
            Log2.v("CalculateMD5ofReport-reportFilePath:" + reportFilePath);
            Console.WriteLine("in CalculateMD5ofReport");

            string md5 = "";

            StringBuilder sb = new StringBuilder();

            try
            {
                string[] lines = File.ReadAllLines(reportFilePath);
                List<string> normalizedLines = new List<string>();

                foreach (string line in lines)
                {
                    string normalizedLine = NormalizedLine(line);
                    sb.AppendLine(normalizedLine);
                    normalizedLines.Add(normalizedLine);
                }

                md5 = CalculateMD5ofString(sb.ToString());

                mListOfAllMD5.Add(md5);

                Console.Write(sb.ToString());
                Console.Write("MD5 = {0}\n", md5);

                string runID = Info.RunID;

                string reportType = Path.GetExtension(reportFilePath).Replace(".", "");
                if (reportType.ToLower().Equals("csv")) reportType = "AGGINT.csv";
                if (reportType.ToLower().Equals("err")) runID = "";
                Console.Write("reportType = {0}\n", reportType);

                TsipReports tsipReports = new TsipReports();

                tsipReports.date = Info.Date;
                tsipReports.paramFile = Info.PdfName;
                tsipReports.runID = runID;
                tsipReports.reportType = reportType;
                tsipReports.lineNum = 0;
                tsipReports.line = md5;

                SQLLEN[] nullInds = NullHelper.CreateArrayOfNullInd(TsipReports.NUM_COLUMNS, NullHelper.ColumnStatus.NOT_NULL);
                DynTsipReports.Insert(mReportsTableName, tsipReports, nullInds);

                int lineNum = 1;
                foreach (string normalizedLine in normalizedLines)
                {
                    tsipReports = new TsipReports();

                    tsipReports.date = Info.Date;
                    tsipReports.time = Info.Time;
                    tsipReports.paramFile = Info.PdfName;
                    tsipReports.runID = runID;
                    tsipReports.reportType = reportType;
                    tsipReports.lineNum = lineNum++;
                    tsipReports.line = normalizedLine;
                    DynTsipReports.Insert(mReportsTableName, tsipReports, nullInds);
                }

            }
            catch (Exception e)
            {
                Log2.e("\n\nTsipReportHelper.CalculateNormalizedMD5(): ERROR: exception: {0}\n{1}\nreportFilePath = {2}", e.Message, reportFilePath, e.StackTrace);
            }

            return md5;
        }

        public static string NormalizedLine(string line)
        {
            string normalizedLine = line;

            // Single quotation characters in the report wreak havoc with SQL queries.
            if (line.Contains("'"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"'", "`");
            }

            // STUDY report.
            if (line.Contains("Interference Study Summary"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"\d\d:\d\d", "XX:XX");
            }
            if (line.Contains("Project Code"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @": \w+", ": XXX");
            }
            if (line.Contains("PDF File Name"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @": \w+", ": XXX");
            }
            if (line.Contains("Environment Name"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @": \w+", ": XXX");
            }
            if (line.Contains("Study Date"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @": \d\d\d\d\.\d\d\.\d\d", ": XXXX.XX.XX");
            }
            if (line.Contains("Study Time"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @": \d\d:\d\d", ": XX:XX");
            }
            if (line.Contains("CPU Time"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @": \d\d:\d\d:\d\d\.\d\d\d", ": XX:XX:XX.XXX");
            }
            if (line.Contains("Elapsed Time"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @": \d\d:\d\d:\d\d", ": XX:XX:XX");
            }
            if (line.Contains("Aggregate Interference CSV report is in file"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @": .*", ": X.AGGINT.csv ...");
            }

            // STATSUM report.
            if (line.Contains("FREQUENCY COORDINATION SYSTEM ASSOCIATION"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @": \d\d\d\d\.\d\d\.\d\d", ": XXXX.XX.XX");
            }
            if (line.Contains("Project Code"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"\[\w+\]", "[XXX]");
            }

            // HILO report.
            if (line.Contains("HiLoCheck Report for"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"HiLoCheck Report for \w+", "HiLoCheck Report for XXX");
            }
            if (line.StartsWith("At "))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"\d\d\d\d\.\d\d\.\d\d, \d\d:\d\d", "XXXX.XX.XX, XX:XX");
            }


            // EXEC report.
            if (line.Contains("FREQUENCY COORDINATION SYSTEM ASSOCIATION"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"\d\d\d\d\d\d-\d\d\d\d\/\d\d-\w", "XXXXXX-XXXX/XX-X");
            }
            if (line.Contains("Project Code:         "))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"Project Code:         (\w+)", "Project Code:         XXX");
            }
            if (line.Contains("Parameter File Name:  "))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"Parameter File Name:  (\w+)", "Parameter File Name:  XXX");
            }
            if (line.Contains("_parm Table"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"(\w+)_parm Table", "XXX_parm Table");
            }
            if (line.Contains("_site Table"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"(\w+)_site Table", "XXX_site Table");
            }
            if (line.Contains("_ante Table"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"(\w+)_ante Table", "XXX_ante Table");
            }
            if (line.Contains("_chan Table"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"(\w+)_chan Table", "XXX_chan Table");
            }
            if (line.Contains(".EXEC (Execution Report)"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"(\w+)\.EXEC \(Execution Report\)", "XXX.EXEC (Execution Report)");
            }
            if (line.Contains(".STUDY (TSIP Study Report)"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"(\w+)\.STUDY \(TSIP Study Report\)", "XXX.STUDY (TSIP Study Report)");
            }
            if (line.Contains(".STATSUM (Station Summary Report)"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"(\w+)\.STATSUM \(Station Summary Report\)", "XXX.STATSUM (Station Summary Report)");
            }
            if (line.Contains(".CASEDET (Case Detail Report)"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"(\w+)\.CASEDET \(Case Detail Report\)", "XXX.CASEDET (Case Detail Report)");
            }
            if (line.Contains(".CASESUM (Case Summary Report)"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"(\w+)\.CASESUM \(Case Summary Report\)", "XXX.CASESUM (Case Summary Report)");
            }
            if (line.Contains(".AGGINTREP (Aggregate Interference Report)"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"(\w+)\.AGGINTREP \(Aggregate Interference Report\)", "XXX.AGGINTREP (Aggregate Interference Report)");
            }
            if (line.Contains("AGGINT.CSV (Aggregate Interference CSV)"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"(\w+)AGGINT\.CSV \(Aggregate Interference CSV\)", "XXX_AGGINT.CSV (Aggregate Interference CSV)");
            }
            if (line.Contains(".EXEC (Execution Report)"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"(\w+)\.EXEC \(Execution Report\)", "XXX.EXEC (Execution Report)");
            }
            if (line.Contains("Date: "))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"Date: \d\d\d\d\.\d\d\.\d\d", "Date: XXXX.XX.XX");
            }
            if (line.Contains("Time: "))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"Time: \d\d:\d\d", "Time: XX:XX");
            }
            if (line.Contains("Antennas.:"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"Antennas\.:.+", "Antennas.:");
            }
            if (line.Contains("Equipment:"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"Equipment:.+", "Equipment:");
            }
            if (line.Contains("CTX Curve:"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"CTX Curve:.*", "CTX Curve:");
            }
            if (line.Contains("CTX Xref.:"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"CTX Xref\.:.*", "CTX Xref.:");
            }
            if (line.Contains("Analog...:"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"Analog\.\.\.:.*", "Analog...:");
            }
            if (line.Contains("Digital..:"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"Digital\.\.:.*", "Digital..:");
            }

            // CASESUM report.
            if (line.Contains("Date:"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"Date:\d\d\d\d\.\d\d\.\d\d", "Date:XXXX.XX.XX");
            }

            // CASEDET and CASOHL reports.
            if (line.Contains("Time:      "))
            {                                                                        
                normalizedLine = Regex.Replace(normalizedLine, @"Time:      \d\d:\d\d", "Time:      XX:XX");
            }
            if (line.Contains("Time:     "))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"Time:     \d\d:\d\d", "Time:     XX:XX");
            }

            // AGGINTREP report.
            if (line.Contains(", Culling Margin:"))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"for \w+, Culling Margin:", "for XXX, Culling Margin:");
            }

            // AGGINT.csv report.

            // ERR report.
            if (line.Contains("* TSIP PARAMETER FILE NAME: "))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"\* TSIP PARAMETER FILE NAME: \w+", "* TSIP PARAMETER FILE NAME: XXX");
            }
            if (line.Contains("Error Report for Run Name"))
            { 
                normalizedLine = Regex.Replace(normalizedLine, @"TSIP build \d\d\d\d\d\d-\d\d\d\d\/\d\d-\w Error Report for Run Name `.+`, at \d\d\d\d\.\d\d\.\d\d \d\d:\d\d", "TSIP build XXXXXX-XXXX/XX-X Error Report for Run Name `XXX`, at XXXX.XX.XX XX:XX");
            }
            if (line.Contains("Process ID "))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"Process ID \d+", "Process ID XXX");
            }
            if (line.Contains("Proposed Name...........: "))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"Proposed Name\.{11}: \w+", "Proposed Name...........: XXX");
            }
            if (line.Contains("Date....................: "))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"Date\.{20}: \d\d\d\d\.\d\d\.\d\d", "Date....................: XXXX.XX.XX");
            }
            if (line.Contains("Time....................: "))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"Time\.{20}: \d\d:\d\d", "Time....................: XX:XX");
            }

            // TS_EXPORT report.
            if (line.StartsWith("* TS-PDF: "))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"TS-PDF: \w+", "TS-PDF: XXX");

                normalizedLine = Regex.Replace(normalizedLine, @"\d\d\d\d\d\d-\d\d\d\d\/\d\d-\w", "XXXXXX-XXXX/XX-X");

                normalizedLine = Regex.Replace(normalizedLine, @"\d\d\d\d\.\d\d\.\d\d \d\d:\d\d:\d\d", "XXXX.XX.XX XX:XX:XX");
            }

            // ES_EXPORT report.
            if (line.Contains("ES-PDF NAME: "))
            {
                normalizedLine = Regex.Replace(normalizedLine, @"ES-PDF NAME: \w+", "ES-PDF NAME: XXX");

                normalizedLine = Regex.Replace(normalizedLine, @"\d\d\d\d\d\d-\d\d\d\d\/\d\d-\w", "XXXXXX-XXXX/XX-X");

                normalizedLine = Regex.Replace(normalizedLine, @"\d\d\d\d\.\d\d\.\d\d \d\d:\d\d:\d\d", "XXXX.XX.XX XX:XX:XX");
            }



            return normalizedLine;
        }

        public string InsertFinalMD5allRunsandReports()
        {
            if (!mOutputToReportsTable) return "";

            StringBuilder sb = new StringBuilder();

            foreach (string md5 in mListOfAllMD5)
            {
                sb.Append(md5);
            }

            string md5AllRunsandReports = CalculateMD5ofString(sb.ToString());

            try
            {
                Console.Write("md5AllRunsandReports = {0}\n", md5AllRunsandReports);

                TsipReports tsipReports = new TsipReports();

                tsipReports.date = Info.Date;
                tsipReports.time = Info.Time;
                tsipReports.paramFile = Info.PdfName;
                tsipReports.runID = "";
                tsipReports.reportType = "";
                tsipReports.lineNum = 0;
                tsipReports.line = md5AllRunsandReports;

                SQLLEN[] nullInds = NullHelper.CreateArrayOfNullInd(TsipReports.NUM_COLUMNS, NullHelper.ColumnStatus.NOT_NULL);
                DynTsipReports.Insert(mReportsTableName, tsipReports, nullInds);

            }
            catch (Exception e)
            {
                Log2.e("\n\nTsipReportHelper.InsertFinalMD5allRunsandReports(): ERROR: exception: {0}\n{1}", e.Message, e.StackTrace);
            }

            return md5AllRunsandReports;
        }

        /// <summary>
        /// This method returns the MD5 checksum of the concatanation of all current field values of
        /// all of the records used in this application as a 32-digit hexadecimal string; this
        /// is an expedient way of determining if any field values have changed compared to a
        /// previous time.
        /// </summary>
        /// <returns></returns>
        private static string CalculateMD5ofString(string content)
        {
            string checkSum = "";

            using (System.Security.Cryptography.MD5 md5 = System.Security.Cryptography.MD5.Create())
            {
                byte[] inputBytes = System.Text.Encoding.ASCII.GetBytes(content);
                byte[] hashBytes = md5.ComputeHash(inputBytes);

                checkSum = BytesToHexString(hashBytes);
            }

            return checkSum;
        }

        public static string BytesToHexString(byte[] arrInput)
        {
            int i;
            StringBuilder sOutput = new StringBuilder(arrInput.Length);
            for (i = 0; i < arrInput.Length; i++)
            {
                sOutput.Append(arrInput[i].ToString("X2"));
            }

            return sOutput.ToString();
        }

    }
}
