using System;
using System.Collections.Generic;
using _Configuration;
using _NewLib;
using System.Diagnostics;
using System.IO;
using System.Threading;

namespace _Utillib
{
    using _DataStructures;
    using SQLHANDLE = IntPtr;
    using SQLHDBC = IntPtr;
    using SQLLEN = Int64;
    using SQLRETURN = Int16;

    /// <summary>
    /// This class provides methods that implement queue creation and 
    /// dynamic TSIP job management used by TsipInitiator.
    /// </summary>
    public class TsipQ
    {
        private static string mglbGate;
        private static int mMaxTsips = -666;
        private const string TSIP_LOG_FILE_MUTEX_NAME = "TSIP_LOG_FILE_MUTEX_NAME";
        private static string mTsipLogFilePath = null;

        //-------------------------------------------------------------------------------
        private struct JobProcIdDyad
        {
            public int tQ_Job;
            public int tQ_ProcID;
        }

        //-------------------------------------------------------------------------------

        // This might be useful at some later date if signalling using UDP 
        // proves to be problematic.
#if false
        public class MyEventArgs : EventArgs
        {
            private string mEventName = null;

            public MyEventArgs(string EventName)
            {
                mEventName = EventName;
            }

            public string EventName
            {
                get { return mEventName; }
                set { mEventName = value; }
            }
        }

        // Name must be EventName + 'EventHandler'.
        public delegate void MyEventEventHandler(object sender, MyEventArgs myEventArgs);

        public event MyEventEventHandler MyEvent;

        protected virtual void OnMyEvent(MyEventArgs myEventArgs)
        {
            if (MyEvent != null)
            {
                MyEvent(this, myEventArgs);
            }
        }
#endif
        //-------------------------------------------------------------------------------

        /// <summary>
        /// Sets the gatename to be used to serialize access to the TSIP queue table. 
        /// </summary>
        /// <param name="dbase"> - name of database.</param>
        /// <returns></returns>
        public static int SetGateName(string dbase)
        {
            mglbGate = @"Global\TSIPQ" + dbase.ToUpper();

            return 0;
        }

        /// <summary>
        /// Gets the gatename that is used to serialize access to the TSIP queue table.
        /// </summary>
        /// <param name=""></param>
        /// <returns></returns>
        public static string GetGateName()
        {
            return mglbGate;
        }

        /// <summary>
        /// Insert a record into the tsip queue with a unique job number. The 
        /// record is initialized as waiting, and the database must already be 
        /// connected.  
        /// </summary>
        /// <param name="nJob"> - allocated TSIP job number.</param>
        /// <param name="dbName"> - name of database.</param>
        /// <param name="pcode"> - project code.</param>
        /// <param name="destarg"> - 'tag' prescribed for the TpRunTsip run.</param>
        /// <param name="cFileName"> - name of PDF file.</param>
        /// <param name="cEventName"> - TSIP job unique string used for signalling between multiple 
        /// concurrent instances of TsipInitiator. Example: Global_TSIPJOBfcsa677 where 677 is an assigned TSIP job number.
        /// </param>
        /// <param name="cMicsID"> - ID string of the MICS user.</param>
        /// <returns></returns>
        public static int InsertTsipQ(int nJob,
                                        string dbName,
                                        string pcode,
                                        string destarg,
                                        string cFileName,
                                        string cEventName,
                                        string cMicsID)
        {
            SQLHDBC hConn = Ssutil.NewConn();
            SQLHANDLE hStmt;
            SQLRETURN sqlRet;
            int nRet = -666;
            string cSQL;
            int nCount;

            sqlRet = ODBC.SQLAllocHandle(ODBC.SQL_HANDLE_STMT, hConn, out hStmt);

            // Check that the current job isn't in the queue already.
            cSQL = String.Format("TQ_ArgFile='{0}' and TQ_MicsID='{1}' and TQ_STATUS in ('W', 'X') ",
                                cFileName, cMicsID);

            //...Log2.v("\nTsipQ.InsertTsipQ(): cSQL = " + cSQL);

            nCount = Ssutil.DbCountRows("[web].[tsip_queue]", cSQL);

            if (nCount == 0)
            {
                // This is a new entry.
                nRet = Constant.SUCCESS;

                // AH: 20230222
                // Until we migrated to the AWS Cloud the databases had the 4-character names 'fcsa' or 'test'.
                // After the migration we use database names like 'micsprod' or 'micsdev'.
                // This causes a SQL error because the associated column, 'TQ_ArgDB', is defined as being [char](4).
                // It transpires that (a) this field is written to and read from but the read value is never used
                // for anything within MICS# and (b) it is redundant information because the SQL database table
                // has the same name.
                // The fix is to just leave the column value TQ_ArgDB blank.
                string blank = "";

                cSQL = String.Format("INSERT INTO [web].[tsip_queue] ([TQ_Job],[TQ_Status],[TQ_ArgDB],[TQ_ArgPC],[TQ_ArgDest], [TQ_ArgFile],[TQ_ProcID],[TQ_EventName],[TQ_MicsID],  [TQ_TimeIn]) VALUES ({0}, 'W', '{1}', '{2}', '{3}', '{4}', 0, '{5}', '{6}', CURRENT_TIMESTAMP)",
                                                 nJob, blank, pcode, destarg, cFileName, cEventName, cMicsID);

                sqlRet = ODBC.SQLExecDirect(hStmt, cSQL, cSQL.Length);
                if (!ODBC.IsOK(sqlRet))
                {
                    Log2.e(cSQL);
                    Log2.e("\nTsipQ.InsertTsipQ(): ERROR: call to ODBC.SQLExecDirect() failed.");
                    string str = String.Format("tsipQ: ERROR - Could not insert Job {0}, {1}",
                                    nJob, cFileName);
                    Ssutil.DbGetDiagStmt(hStmt, str);
                    nRet = Constant.FAILURE;
                }
                Log2.v("\nTsip queue entry added");
            }
            else
            {
                //	Duplicate entry already in Queue.
                Log2.e("\nTsipQ.InsertTsipQ(): ERROR: Duplicate entry already in Queue.");
                nRet = Error.ALREADY_IN_QUEUE;
            }

            // Tidy up.
            sqlRet = ODBC.SQLFreeHandle(ODBC.SQL_HANDLE_STMT, hStmt);
            Ssutil.DisConn(hConn);

            return nRet;
        }

        /// <summary>
        /// This method atomically determines if there are free 'slots' to spawn a new 
        /// TpRunTsip process and, if so, flags it as running. 
        /// </summary>
        /// <param name="cDatabase"></param>
        /// <param name="nJob"></param>
        /// <param name="cFlag"></param>
        /// <returns>
        /// This routine returns 0 if the job has been found tested and flagged; or 1 if 
        /// there are is currently no available free 'slot'; or 2 if the job has been 
        /// deleted; a negative return value indicates that an error occurred.
        /// </returns>
        public static int TestAndFlag(string cDatabase, int nJob, string cFlag)
        {
            int nMax;
            int nRunning;
            int nDel;
            int nRet;
            string cSQL;
            string cGateName;

            cGateName = GetGateName();

            if (String.IsNullOrWhiteSpace(cGateName))
            {
                Log2.e("\nTsipQ.TestAndFlag(): ERROR: gateName is invalid.");
                Application.Exit(666);
            }

            //-------------	Start the guarded code ----------------
            if (GuardIn(cGateName, 30) == 0)
            {
                //	Check that this job hasn't been deleted.
                cSQL = String.Format("TQ_Job = {0} and TQ_Status = 'D' ", nJob);
                nDel = Ssutil.DbCountRows("web.tsip_queue", cSQL);
                if (nDel > 0)
                {
                    // This job has been deleted.
                    nRet = Error.JOB_IN_QUEUE_HAS_BEEN_DELETED;
                }
                else
                {
                    //	Get the maximum number of tsips we can run at once.
                    nMax = GetMaxTsips();

                    nRunning = Ssutil.DbCountRows("web.tsip_queue", "TQ_Status = 'X' ");

                    //...Log2.v("\nTsipQ.TestAndFlag(): number of running tsips = " + nRunning);

                    if (nRunning < nMax)
                    {
                        cSQL = String.Format("Update web.tsip_queue set TQ_Status = '{0}', TQ_TimeIn = CURRENT_TIMESTAMP, TQ_ProcID = -1 where TQ_Job = {1}",
                                            cFlag, nJob);
                        nRet = Ssutil.DbExecute(cSQL) ? 0 : -2;
                    }
                    else
                    {
                        nRet = Error.JOB_HAS_NO_ROOM_TO_RUN;
                    }
                }
                GuardOut(cGateName);
            }
            else
            {
                nRet = Constant.FAILURE;
            }
            //-------------- End the guarded code -----------------

            //...Log2.v("\nTsipQ.TestAndFlag(): returned " + nRet);

            return nRet;
        }

        /// <summary>
        /// This method establishes a 'guard' that ensures that only one program 
        /// at a time can queue on the prescribed file name. This is achieved using
        /// a Mutex. The method will start to 'block' until entry into the Mutex becomes 
        /// available. The method also lifts the 'block' if too many seconds have elapsed. 
        /// </summary>
        /// <param name="cFileName"></param>
        /// <param name="nMaxSeconds"></param>
        /// <returns>
        /// Returns 0 if the 'guard' is successfully established; -1 if not.  
        /// </returns>
        public static int GuardIn(string cFileName, int nMaxSeconds)
        {
            int nRet;
            int nCount = 0;

            while ((nRet = GenUtil.FileGate(cFileName)) != 0 && nCount < nMaxSeconds)
            {
                Thread.Sleep(1);
                nCount++;
            }

            return (nRet == 0) ? Constant.SUCCESS : Constant.FAILURE;
        }

        /// <summary>
        /// This method dismisses the 'guard' created by a call to GuardIn().  
        /// </summary>
        /// <param name="cFileName"></param>
        /// <returns></returns>
        public static int GuardOut(string cFileName)
        {
            return (GenUtil.FileGateClose(cFileName));
        }

        /// <summary>
        /// This method returns the total number of TSIP 'slots' available, i.e.
        /// the maximum number of spawned instances of TpRunTsip.exe that will
        /// be allowed to execute at the same time.  
        /// </summary>
        /// <param name=""></param>
        /// <returns></returns>
        public static int GetMaxTsips()
        {
            SQLHDBC hConn = Ssutil.NewConn();
            SQLHANDLE hStmt;
            SQLRETURN sqlRet;
            SQLLEN nNull;
            string cSQL;

            // If we have called this member before we stored the return value in mMaxTsips.
            // If so, just return this stored value.
            if (mMaxTsips > 0)
            {
                return mMaxTsips;
            }

            sqlRet = ODBC.SQLAllocHandle(ODBC.SQL_HANDLE_STMT, hConn, out hStmt);

            cSQL = "Select MaxTsips from main.control";

            sqlRet = ODBC.SQLExecDirect(hStmt, cSQL, cSQL.Length);
            if (!ODBC.IsOK(sqlRet))
            {
                Log2.e("\nTsipQ.GetMaxTsips(): ERROR: call to ODBC.SQLExecDirect() failed for: " + cSQL);
                ODBC.SQLFreeHandle(ODBC.SQL_HANDLE_STMT, hStmt);
                Ssutil.DisConn(hConn);
                Application.Exit(666);
            }

            sqlRet = ODBC.SQLFetch(hStmt);
            if (!ODBC.IsOK(sqlRet))
            {
                Log2.e("\nTsipQ.GetMaxTsips(): ERROR: call to ODBC.SQLFetch() failed for: " + cSQL);
                ODBC.SQLFreeHandle(ODBC.SQL_HANDLE_STMT, hStmt);
                Ssutil.DisConn(hConn);
                Application.Exit(666);
            }


            sqlRet = (SQLRETURN)Ssutil.DbGetInt(hStmt, 1, "MaxTsips", out mMaxTsips, out nNull);

            ODBC.SQLFreeHandle(ODBC.SQL_HANDLE_STMT, hStmt);
            Ssutil.DisConn(hConn);

            //...Log2.v("\nTsipQ.GetMaxTsips(): MaxTsips = " + mMaxTsips);

            return mMaxTsips;
        }

        /// <summary>
        /// This method start execution of a TSIP job by spawning a new Windows 
        /// process that will run an instance of TpRunTsip.exe.
        /// </summary>
        /// <param name="database"> - name of database.</param>
        /// <param name="args"> - command line arguments for TsipInitiator.</param>
        /// <param name="destinationDir"> - directory path for TSIP report files.</param>
        /// <param name="nJob"> - TSIP job number.</param>
        /// <param name="tsipProcess"> - the process within which TpRunTsip will run.</param>
        /// <returns>The Windows process ID of the spawned TpRunTsip process.</returns>
        public static int StartTsip(string database, string[] args, string destinationDir, int nJob, out Process tsipProcess)
        {
            // 'out' requirement.
            tsipProcess = null;

            int tsipProcessID = 0; ;
            string cCommand;
            string cSQL;
            string cGateName;
            bool IsOK;
            Process currentProcess = null;

            // Get the full path of the TpRunTsip executable.
            cCommand = Ssutil.GetBinPath("tpRunTsip", database);

            // Flush the output to the console.
            Console.Out.Flush();
            Console.Error.Flush();

            //	Get the common gate name to update the tsip queue.
            cGateName = GetGateName();

            //-------------	Start the guarded code ----------------
            GuardIn(cGateName, 30);

            //	Now update the record in database table web.tsip_queue without the process id.
            cSQL = String.Format("update web.tsip_queue set TQ_ProcID = -1, TQ_TimeStart = CURRENT_TIMESTAMP where TQ_Job = {0} ", nJob);

            IsOK = Ssutil.DbExecute(cSQL);
            if (!IsOK)
            {
                Log2.e("\nTsipQ.StartTsip(): ERROR: call to DbExecute() failed for: " + cSQL);
                GuardOut(cGateName);
                return -1;
            }

            //	Spawn the job.  First, we raise our priority class to above_normal.
            //	The first thing that tpRunTsip does is set its priority class to normal
            //	so this allows us to regain execution immediately, and update the 
            //	web.tsip_queue with the process id.

            try
            {
                currentProcess = Process.GetCurrentProcess();
                currentProcess.PriorityClass = ProcessPriorityClass.AboveNormal;
            }
            catch (Exception e)
            {
                Log2.e("\nTsipQ.StartTsip(): ERROR: could not set current process priority to 'AboveNormal: " + e.Message);
                Console.Write("\nCould not raise our priority class!\n");
            }

            TsipQ.WriteToTsipLog(String.Format("\nSpawning [{0}]", cCommand));



            // Spawn another process that will be used to run TpRunTsip.
            tsipProcess = new Process();

            // Processes inherit their initial environment from their parents. 
            // Once the process is running, it is free to change its environment 
            // variables by calling Set­Environment­Variable, and those modified 
            // environment variables are passed to any child processes launched 
            // after the new variable is set. A parent process can also pass a 
            // custom environment to the child process using the StartInfo property.
            // A child process inherits its initial environment from its parent, 
            // but it only gets a snapshot of that environment. If the parent 
            // subsequently modifies its environment, the child environment is not updated.

            // Configure the process using the StartInfo properties.
            tsipProcess.StartInfo.FileName = cCommand;
            string commandLineArgs = "";
            foreach (string arg in args)
            {
                commandLineArgs += " " + arg;
            }

            tsipProcess.StartInfo.Arguments = commandLineArgs;
            tsipProcess.StartInfo.WindowStyle = ProcessWindowStyle.Hidden;

            tsipProcess.StartInfo.UseShellExecute = false;
            tsipProcess.StartInfo.EnvironmentVariables.Remove("TARGETDIRFORTSIPREPORTS");
            tsipProcess.StartInfo.EnvironmentVariables.Add("TARGETDIRFORTSIPREPORTS", destinationDir);
            tsipProcess.StartInfo.EnvironmentVariables.Remove("TSIP_QUEUE_JOB");
            tsipProcess.StartInfo.EnvironmentVariables.Add("TSIP_QUEUE_JOB", nJob.ToString());

            //...Log2.v("\nTsipQ.StartTsip(): command line = " + cCommand + " " + commandLineArgs);

            // Start the tpRunTsip process.
            tsipProcess.Start();

            tsipProcessID = tsipProcess.Id;
            //...Log2.v("\nTsipQ.StartTsip(): TpRunTsip execution has started, process ID = " + tsipProcessID);


            if (tsipProcessID > 0)
            {
                cSQL = String.Format("update web.tsip_queue set TQ_ProcID = {0}, TQ_Finish=0 where TQ_Job = {1} ", tsipProcessID, nJob);

                IsOK = Ssutil.DbExecute(cSQL);
                if (!IsOK)
                {
                    tsipProcessID = -2;
                }

                // Drop our priority class back to normal.
                try
                {
                    currentProcess.PriorityClass = ProcessPriorityClass.Normal;
                }
                catch (Exception e)
                {
                    Log2.e("\nTsipQ.StartTsip(): ERROR: could not reset current process priority to 'Normal: " + e.Message);
                    Console.Write("\nCould not reset our priority class to normal.\n");
                }

            }
            else
            {
                //	spawn error
                Log2.e("\nTsipQ.StartTsip(): ERROR: invalid process ID.");
                tsipProcessID = -3;
            }

            GuardOut(cGateName);
            // ----------- Out of the guard -----------------------------

            return tsipProcessID;
        }

        /// <summary>
        /// This method checks that all the tsips in the queue that are still flagged 
        /// as running are actually still running. Any that are not running will be 
        /// flagged as finished.
        /// </summary>
        /// <returns>
        /// A return value of 0 indicates that information in DB table <b>web.tsip_queue</b> 
        /// is now up-to-date..
        /// </returns>
        public static int CheckRunningProgs()
        {
            SQLHDBC hConn = Ssutil.NewConn();
            SQLHANDLE hStmt;
            SQLRETURN sqlRet;

            //	First we get a list of all the running processes on this computer.
            Process[] currentProcessesList = Process.GetProcesses();

            foreach (Process process in currentProcessesList)
            {
                //...Log2.v(String.Format("\nProcess: {0} ID: {1}", process.ProcessName, process.Id));
            }

            //	Now create a list of all the running tsips, and make sure they are still running.
            sqlRet = ODBC.SQLAllocHandle(ODBC.SQL_HANDLE_STMT, hConn, out hStmt);
            if (!ODBC.IsOK(sqlRet))
            {
                Log2.e("\nTsipQ.CheckRunningProgs(): ERROR: call to ODBC.SQLAllocHandle() failed.");
                Application.Exit(666);
            }

            string cSQL = "select TQ_Job, TQ_ProcID from web.tsip_queue where TQ_Status = 'X' and TQ_ProcID > 0";
            sqlRet = ODBC.SQLExecDirect(hStmt, cSQL, cSQL.Length);
            if (!ODBC.IsOK(sqlRet))
            {
                Log2.e("\nTsipQ.CheckRunningProgs(): ERROR: call to ODBC.SQLExecDirect() failed for: " + cSQL);
                Application.Exit(666);
            }

            // Create the list of all running tsips.
            List<JobProcIdDyad> shouldBeRunningTsips = new List<JobProcIdDyad>();

            while (true)
            {
                sqlRet = ODBC.SQLFetch(hStmt);
                if (!ODBC.IsOK(sqlRet))
                {
                    if (sqlRet == ODBC.SQL_NO_DATA)
                    {
                        // We have retrieved all relevant records from web.tsip_queue where TQ_Status = 'X'
                        // Break out of the while-loop.
                        break;
                    }
                    else
                    {
                        // Something bad happened.
                        Log2.e("\nTsipQ.CheckRunningProgs(): ERROR: call to ODBC.SQLSQLFetch() failed.");
                        Application.Exit(666);
                    }
                }

                // If we get here the call to ODBC.SQLFetch() successfully returned data.
                int tQ_Job;
                int tQ_ProcID;
                SQLLEN nullInd_Job;
                SQLLEN nullInd_ProcID;
                JobProcIdDyad dyad;
                try
                {
                    Ssutil.DbGetInt(hStmt, 1, "TQ_Job", out tQ_Job, out nullInd_Job);
                    Ssutil.DbGetInt(hStmt, 2, "TQ_ProcID", out tQ_ProcID, out nullInd_ProcID);
                }
                catch (Exception e)
                {
                    string str = String.Format("checkRunningProgs: Couldn't get tsips. [{0}]", e.Message);
                    Log2.e("\nTsipQ.CheckRunningProgs(): ERROR: call to Ssutil.DbGetInt() failed: " + e.Message);
                    Ssutil.DbGetDiagStmt(hStmt, str);
                    break;
                }

                if (nullInd_Job != Constant.DB_NULL && nullInd_Job != Constant.DB_NULL)
                {
                    dyad = new JobProcIdDyad();
                    dyad.tQ_Job = tQ_Job;
                    dyad.tQ_ProcID = tQ_ProcID;

                    shouldBeRunningTsips.Add(dyad);
                }

            }

            // Release ODBC resources.
            sqlRet = ODBC.SQLFreeHandle(ODBC.SQL_HANDLE_STMT, hStmt);
            Ssutil.DisConn(hConn);

            // Now check that each tsip procid corresponds to a currently executing process.
            foreach (JobProcIdDyad tsip in shouldBeRunningTsips)
            {
                bool matchFound = false;

                foreach (Process runningProcess in currentProcessesList)
                {
                    if (tsip.tQ_ProcID == runningProcess.Id)
                    {
                        // We have found a match; check the next shouldBeRunningTsip.
                        matchFound = true;
                        break;
                    }
                }

                if (!matchFound)
                {
                    // The shouldBeRunningTsip is not in the list of currently active processes.
                    // It must have finished executing so remove this tsip job from the queue.
                    Log2.e("\nTsipQ.CheckRunningProgs(): found zombie job: tQ_Job = " + tsip.tQ_Job + ", tQ_ProcID = " + tsip.tQ_ProcID);

                    EndJob(tsip.tQ_Job, "F", -129);
                }
            }

            return Constant.SUCCESS;
        }

        /// <summary>
        /// This method finishes a TSIP job by updating its record in the DB table <b>web.tsip_queue</b>. 
        /// The record's TQ_Status column is set to 'F' and TQ_TimeEnd is assigned a value.
        /// <b>IMPORTANT: This method also invokes a review of the current wait queue and will trigger
        /// the execution of one or more waiting TSIP jobs to consume any available free processing 'slots'.</b> 
        /// </summary>
        /// <param name="nJob"></param>
        /// <param name="nRet"></param>
        /// <returns></returns>
        public static int FinishJob(int nJob, int nRet)
        {
            return EndJob(nJob, "F", nRet);
        }

        /// <summary>
        /// This method ends a TSIP job by updating its record in the DB table <b>web.tsip_queue</b>. 
        /// The record's TQ_Status column is prescribed by the caller and TQ_TimeEnd is assigned a value.
        /// <b>IMPORTANT: This method reviews the current wait queue and will trigger
        /// the execution of one or more waiting TSIP jobs to consume any available free processing 'slots'.</b>   
        /// </summary>
        /// <param name="nJob"></param>
        /// <param name="cStatus"></param>
        /// <param name="nRet"></param>
        /// <returns></returns>
        public static int EndJob(int nJob, string cStatus, int nRet)
        {
            SQLHDBC hConn;
            SQLHANDLE hStmt;
            SQLRETURN sqlRet;
            string cSQL;
            bool IsOK;
            int nInd;
            string cEventName;
            SQLLEN nNull;
            int nToStart;
            string cGateName;
            int retVal;

            if (cStatus.Equals("D"))
            {
                return Constant.SUCCESS;
            }

            hConn = Ssutil.NewConn();

            sqlRet = ODBC.SQLAllocHandle(ODBC.SQL_HANDLE_STMT, hConn, out hStmt);

            cSQL = String.Format("update web.tsip_queue set TQ_Status = '{0}', TQ_Finish={1}, TQ_TimeEnd = CURRENT_TIMESTAMP where TQ_Job = {2} ",
                                 cStatus, nRet, nJob);

            IsOK = Ssutil.DbExecute(cSQL);

            //	Now we need to signal events to start new jobs.
            cGateName = GetGateName();
            // ------------------------

            // Attempt to initiate a guarded block of code.
            retVal = GuardIn(cGateName, 30);

            if (retVal != Constant.SUCCESS)
            {
                // The attempt to enter a guard failed.
                string str = String.Format("Could not gate {0}, job: {1}", cGateName, nJob);
                Log2.e("\nTsipQ.EndJob(): ERROR: call to GuardIn() failed: " + str);
                TsipQ.WriteToTsipLog(str);
                ODBC.SQLFreeHandle(ODBC.SQL_HANDLE_STMT, hStmt);
                Ssutil.DisConn(hConn);
                return Constant.FAILURE;  //	Could not gate
            }

            // Guarded code block successfully started.
            // Get the maximum allowed number of concurrent tsips.
            int nMaxTsips = GetMaxTsips();

            // Get the number of tsips currently running.
            int nTsipsRunning = Ssutil.DbCountRows("web.tsip_queue", "TQ_Status = 'X' ");

            // Calculate the maximum number of new tsips we can start to execute.
            nToStart = nMaxTsips - nTsipsRunning;

            // End the guard.
            GuardOut(cGateName);

            // ------------------------

            // Start the maximum number of new tsips that we are allowed.
            if (nToStart > 0)
            {
                // Identify ant tsip jobs that are currently marked as waiting (W).
                cSQL = "Select TQ_Job, TQ_EventName from web.tsip_queue where TQ_Status = 'W' order by TQ_Job ";

                sqlRet = ODBC.SQLExecDirect(hStmt, cSQL, cSQL.Length);
                if (!ODBC.IsOK(sqlRet))
                {
                    Log2.e("\nTsipQ.EndJob(): ERROR: call to ODBC.SQLExecDirect() failed for : " + cSQL);
                    ODBC.SQLFreeHandle(ODBC.SQL_HANDLE_STMT, hStmt);
                    Ssutil.DisConn(hConn);
                    return -666;
                }

                for (nInd = 0; nInd < nToStart; nInd++)
                {
                    // Get the next waiting tsip job from table web.tsip_queue
                    sqlRet = ODBC.SQLFetch(hStmt);
                    if (!ODBC.IsOK(sqlRet))
                    {
                        if (sqlRet == ODBC.SQL_NO_DATA)
                        {
                            // There are no more waiting tsip jobs.
                            // Break out of the for-loop.
                            break;
                        }
                        else
                        {
                            // Something bad happened.
                            Log2.e("\nTsipQ.EndJob(): ERROR: call to ODBC.SQLExecFetch() failed for : " + cSQL);
                            ODBC.SQLFreeHandle(ODBC.SQL_HANDLE_STMT, hStmt);
                            Ssutil.DisConn(hConn);
                        }
                    }

                    try
                    {
                        int targetJob;
                        Ssutil.DbGetInt(hStmt, 1, "TQ_Job", out targetJob, out nNull);
                        Ssutil.DbGetString(hStmt, 2, "TQ_EventName", out cEventName, Constant.MAX_EVENT_NAME_SZ, out nNull);

                        SignalEvent(targetJob);

                    }
                    catch (Exception e)
                    {
                        Log2.e("\nTsipQ.EndJob(): ERROR: call to ODBC Get attempt failed for : " + cSQL + " " + e.Message);
                        ODBC.SQLFreeHandle(ODBC.SQL_HANDLE_STMT, hStmt);
                        Ssutil.DisConn(hConn);
                    }

                }

            }

            // Release ODBC resources.
            ODBC.SQLFreeHandle(ODBC.SQL_HANDLE_STMT, hStmt);
            Ssutil.DisConn(hConn);

            return 0;
        }

        /// <summary>
        /// This method allows one instance of TsipInitiator to send a message
        /// to another instance of TsipInitiator; this is used by a TSIP job that
        /// is ending to instigate the execution of the next, waiting, TSIP job. 
        /// </summary>
        /// <param name="nJob"> - the assigned TSIP job number of the instance of TsipInitiator that is to be signalled.</param>
        /// <returns></returns>
        public static int SignalEvent(int nJob)
        {
            int port = SimpleUDP.HashToDynamicPortNumber(nJob);

            try
            {
                SimpleUDP.Send(port, "brocolli");

                //...Log2.v(String.Format("\nTsipQ.SignalEvent(): call to SimpleUDP.Send() succeeded: destination job {0} on port {1}.", nJob, port));
            }
            catch
            {
                Log2.e("\nTsipQ.SignalEvent(): ERROR: call to SimpleUDP.Send() failed for destination job {0} on port {1}.", nJob, port);

            }

            return Constant.SUCCESS;
        }

        /// <summary>
        /// This method allows one instance of TsipInitiator to wait for a message
        /// from another instance of TsipInitiator; this is used by a TSIP job in the 
        /// wait queue to be triggered into execution by another instance of TsipInitiator
        /// that is ending. This method 'blocks' until it receives its message.
        /// </summary>
        /// <param name="nJob"> - the TSIP job number of the instance of TsipInitiator that is waiting.</param>
        /// <returns></returns>
        public static int WaitForEvent(int nJob)
        {
            string message;

            int port = SimpleUDP.HashToDynamicPortNumber(nJob);

            //...Log2.v(String.Format("\nTsipQ.WaitForEvent(): job {0} waiting for message on port {1}", nJob, port));

            SimpleUDP.Receive(port, out message);

            //...Log2.v("\nTsipQ.WaitForEvent(): received message = " + message);

            //...Log2.v("\nTsipQ.WaitForEvent(): waiting has ended.");

            return Constant.SUCCESS;
        }

        /// <summary>
        /// This method initializes access to the (single) TSIP log file that
        /// is written to by all instances of TsipInitiator.
        /// </summary>
        /// <param name="database"> - name of database being used.</param>
        /// <returns></returns>
        public static int InitTsipLogFileAccess(string database)
        {
            int retVal = Constant.FAILURE;

            // Get the full path for the Tsip Log for the prescribed database.
            mTsipLogFilePath = Ssutil.GetTsipLogFileName(database);

            //...Log2.v("\nTsipQ.InitializeTsipLogFileAccess(): mTsipLogFilePath = " + mTsipLogFilePath);

            // Test that we can access the log using the mutex.
            using (var mutex = new Mutex(false, TSIP_LOG_FILE_MUTEX_NAME))
            {
                TextWriter twTsipLog;

                // Attempt to open the Tsip log file for write/append.
                try
                {
                    mutex.WaitOne();

                    twTsipLog = new StreamWriter(mTsipLogFilePath, true);  // Append mode.
                    twTsipLog.Close();

                    mutex.ReleaseMutex();

                    retVal = Constant.SUCCESS;

                    //...Log2.v("\nTsipQ.InitializeTsipLogFileAccess(): log file is accessible.");
                }
                catch (Exception)
                {
                    string str = String.Format("Can't access tsip log file: {0}\n", mTsipLogFilePath);
                    Console.Write("\n" + str);
                    Log2.e("\nTsipQ.InitTsipLogFileAccess(): ERROR: " + str);
                    twTsipLog = Console.Out;
                }

            }

            return retVal;
        }

        /// <summary>
        /// This method writes a message to the TSIP log file; because 
        /// multiple instances of TsipInitiator all want to write to the 
        /// same TSIP log file, a Mutex is used to queue for sole access
        /// to the log file.
        /// </summary>
        /// <param name="message"></param>
        /// <returns></returns>
        public static int WriteToTsipLog(string message)
        {
            int retVal = Constant.FAILURE;

            if (String.IsNullOrWhiteSpace(mTsipLogFilePath))
            {
                Log2.e("\nTsipQ.WriteToTsipLog(): ERROR: access has not been initialized.");
                return retVal;
            }

            if (String.IsNullOrEmpty(message))
            {
                return retVal;
            }

            using (var mutex = new Mutex(false, TSIP_LOG_FILE_MUTEX_NAME))
            {
                mutex.WaitOne();
                File.AppendAllText(mTsipLogFilePath, message);
                mutex.ReleaseMutex();
            }


            return retVal;
        }

        /// <summary>
        /// This method fetches a record from the database table <b>web.tsip_queue</b>
        /// that has the prescribed TSIP job number.
        /// </summary>
        /// <param name="nJob"> - number of TSIP job.</param>
        /// <param name="tQel"> - TSIPQ object populated with record data.</param>
        /// <returns></returns>
        public static int GetTsipQJob(int nJob, out TSIPQ tQel)
        {
            // 'out' requirement.
            tQel = null;

            SQLHDBC hConn = Ssutil.NewConn();
            SQLHANDLE hStmt;
            SQLRETURN sqlRet;
            int nRet = Constant.FAILURE;
            string cSQL;
            SQLLEN dbNull;
            ODBC.TIMESTAMP_STRUCT tSQLTime;

            sqlRet = ODBC.SQLAllocHandle(ODBC.SQL_HANDLE_STMT, hConn, out hStmt);
            if (!ODBC.IsOK(sqlRet))
            {
                Log2.e("\nTsipQ.GetTsipQJob(): ERROR: call to SQLAllocHandle() failed.");
                Application.Exit(666);
            }

            cSQL = String.Format("SELECT [TQ_Job],[TQ_Status],[TQ_Finish],[TQ_ArgDB],[TQ_ArgPC],[TQ_ArgDest], [TQ_ArgFile],[TQ_ProcID],[TQ_EventName],[TQ_MicsID],  [TQ_TimeIn],[TQ_TimeStart],[TQ_TimeEnd] FROM [web].[tsip_queue] WHERE [TQ_Job]={0} ", nJob);

            sqlRet = ODBC.SQLExecDirect(hStmt, cSQL, cSQL.Length);
            if (!ODBC.IsOK(sqlRet))
            {
                Log2.e("\nTsipQ.GetTsipQJob(): ERROR: call to SQLExecDirect() failed for " + cSQL);
                string str = String.Format("getTsipQJob: ERROR - Could not get Job {0}\n {1}", nJob, cSQL);
                Ssutil.DbGetDiagStmt(hStmt, str);
                sqlRet = ODBC.SQLFreeHandle(ODBC.SQL_HANDLE_STMT, hStmt);
                Ssutil.DisConn(hConn);
                return Constant.FAILURE;
            }

            //	Now fetch the record.
            sqlRet = ODBC.SQLFetch(hStmt);
            if (!ODBC.IsOK(sqlRet))
            {
                if (sqlRet == ODBC.SQL_NO_DATA)
                {
                    Log2.e("\nTsipQ.GetTsipQJob(): ERROR: call to SQLSQLFetch() returned SQL_NO_DATA for " + cSQL);
                    sqlRet = ODBC.SQLFreeHandle(ODBC.SQL_HANDLE_STMT, hStmt);
                    Ssutil.DisConn(hConn);
                    return 1;
                }
                else
                {
                    Log2.e("\r\nDynFeAzim.FeFetchAzim(): ERROR: ODBC.SQLFetch(): sqlRet = " + sqlRet);
                    sqlRet = ODBC.SQLFreeHandle(ODBC.SQL_HANDLE_STMT, hStmt);
                    Ssutil.DisConn(hConn);
                    return Constant.FAILURE;
                }
            }

            nRet = 0;
            tQel = new TSIPQ();

            try
            {
                Ssutil.DbStartGets();

                Ssutil.DbGetInt(hStmt, 0, "TQ_Job", out tQel.TQ_Job, out dbNull);
                Ssutil.DbGetString(hStmt, 0, "TQ_Status", out tQel.TQ_Status, TSIPQ.TQ_STATUS, out dbNull);
                Ssutil.DbGetInt(hStmt, 0, "TQ_Finish", out tQel.TQ_Finish, out dbNull);
                Ssutil.DbGetString(hStmt, 0, "TQ_ArgDB", out tQel.TQ_ArgDB, TSIPQ.TQ_ARGDB, out dbNull);
                Ssutil.DbGetString(hStmt, 0, "TQ_ArgPC", out tQel.TQ_ArgPC, TSIPQ.TQ_ARGPC, out dbNull);
                Ssutil.DbGetString(hStmt, 0, "TQ_ArgDest", out tQel.TQ_ArgDest, TSIPQ.TQ_ARGDEST, out dbNull);
                Ssutil.DbGetString(hStmt, 0, "TQ_ArgFile", out tQel.TQ_ArgFile, TSIPQ.TQ_ARGFILE, out dbNull);
                Ssutil.DbGetInt(hStmt, 0, "TQ_ProcID", out tQel.TQ_ProcID, out dbNull);
                Ssutil.DbGetString(hStmt, 0, "TQ_EventName", out tQel.TQ_EventName, TSIPQ.TQ_EVENTNAME, out dbNull);
                Ssutil.DbGetString(hStmt, 0, "TQ_MicsID", out tQel.TQ_MicsID, TSIPQ.TQ_MICSID, out dbNull);

                //...Log2.v("\nTsipQ.GetTsipQJob(): A");
                Ssutil.DbGetTimestamp(hStmt, 0, "TQ_TimeIn", out tSQLTime, out dbNull);
                Ssutil.DbTimestampToTime(tSQLTime, out tQel.TQ_TimeIn);

                Ssutil.DbGetTimestamp(hStmt, 0, "TQ_TimeStart", out tSQLTime, out dbNull);
                Ssutil.DbTimestampToTime(tSQLTime, out tQel.TQ_TimeStart);

                Ssutil.DbGetTimestamp(hStmt, 0, "TQ_TimeEnd", out tSQLTime, out dbNull);
                Ssutil.DbTimestampToTime(tSQLTime, out tQel.TQ_TimeEnd);

                //...Log2.v("\nTsipQ.GetTsipQJob(): Z");
                nRet = Constant.SUCCESS;
            }
            catch (Exception e)
            {
                Log2.e("\nTsipQ.GetTsipQJob(): ERROR: ODBC Get call failed: " + e.Message);
                Ssutil.DbGetDiagStmt(hStmt, "getTsipQJob: Could not bind column: " + e.Message);
                nRet = -2;
            }

            sqlRet = ODBC.SQLFreeHandle(ODBC.SQL_HANDLE_STMT, hStmt);
            Ssutil.DisConn(hConn);

            return nRet;
        }


    }
}
