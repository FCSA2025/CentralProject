using System;
using System.Collections.Generic;
using System.Data;
using System.Data.Odbc;
using System.IO;
using System.Net.Mail;
using System.Text;
using System.Web;
using DBAccess;
using DBUtilities;
using ErrorUtilities;
using LongLatUtilities;
using SesUtilities;

namespace RemIcsReWrite
{
    /// <summary>
    /// CASEDET KML build + email  -  parity with Ttsipmenu CASEDETTSESkml / CASEDETTSTSkml.
    /// Writes under Session["user_dir"]; emails via SesUtils.send_email_message2 with attachments.
    /// Does not delete KML files after email.
    /// </summary>
    public class CaseDetKmlResult
    {
        public bool ok;
        public string error;
        public string message;
        public bool emailed;
        public List<string> files;

        public CaseDetKmlResult()
        {
            files = new List<string>();
            error = "";
            message = "";
        }
    }

    public static class CaseDetKml
    {
        public static CaseDetKmlResult Generate(HttpContext ctx, string mode, string pdf, string tsip, string protype, string reptype)
        {
            var result = new CaseDetKmlResult();
            if (ctx == null || ctx.Session == null
                || ctx.Session["s_cnString"] == null
                || ctx.Session["s_schema"] == null
                || ctx.Session["s_user"] == null
                || ctx.Session["user_dir"] == null)
            {
                result.ok = false;
                result.error = "Session not initialized.";
                return result;
            }

            string m = (mode ?? "").Trim().ToUpperInvariant();
            if (m != "TSES" && m != "TSTS")
            {
                result.ok = false;
                result.error = "mode must be TSES or TSTS.";
                return result;
            }

            string pdfname = (pdf ?? "").Trim();
            string tsipname = (tsip ?? "").Trim();
            string ptype = (protype ?? "").Trim();
            string rtype = (reptype ?? "").Trim().ToUpperInvariant();
            if (rtype != "C") rtype = "G";

            if (tsipname.Length == 0)
            {
                result.ok = false;
                result.error = "tsip is required.";
                return result;
            }

            try
            {
                var eng = new Engine(ctx, pdfname, tsipname, ptype, rtype);
                if (m == "TSES") eng.RunTses(result);
                else eng.RunTsts(result);
            }
            catch (Exception ex)
            {
                result.ok = false;
                result.error = ex.Message;
            }
            return result;
        }

        private class Engine
        {
            private readonly HttpContext ctx;
            private readonly string cnstr;
            private readonly string schema;
            private readonly string userDir;
            private readonly string pdfname;
            private readonly string tsipname;
            private readonly string protype;
            private readonly string reptype;
            private readonly string runinfo;

            private StreamWriter sw;
            private string filePathFlag = "";
            private const string format6 = "F6";
            private const string format2 = "F2";

            private DataTable tsipDataTE;
            private DataTable tsipDataET;
            private DataTable tsipDataTT;

            private string sitetable;
            private string antetable;
            private string chantable;

            private string listTE = "";
            private string listET = "";
            private string listTT = "";

            public Engine(HttpContext context, string pdf, string tsip, string ptype, string rtype)
            {
                ctx = context;
                cnstr = context.Session["s_cnString"].ToString();
                schema = context.Session["s_schema"].ToString();
                userDir = context.Session["user_dir"].ToString();
                pdfname = pdf;
                tsipname = tsip;
                protype = ptype;
                reptype = rtype;
                runinfo = tsipname.Replace("_", " - ");
            }

            public void RunTses(CaseDetKmlResult result)
            {
                sitetable = schema + ".te_" + tsipname + "_site";
                antetable = schema + ".te_" + tsipname + "_ante";
                chantable = schema + ".te_" + tsipname + "_chan";

                dbconnect oCn = new dbconnect();
                string strSql = "SELECT DISTINCT tecaseno FROM " + sitetable + " WHERE tereport > 0 ORDER BY tecaseno";
                DataTable oDTte = null;
                try
                {
                    oDTte = oCn.retrieve(strSql);
                }
                catch (Exception)
                {
                    oCn.dbdisconnect();
                    result.ok = false;
                    // W3-6: no SQL text to client.
                    result.error = "A database error occurred while building the CASEDET KML report.";
                    return;
                }

                if (oDTte != null && oDTte.Rows.Count > 0)
                {
                    string tsiprepname = "te_" + tsipname;
                    if (reptype == "G")
                    {
                        DoKmlTE(tsiprepname, 0);
                    }
                    else
                    {
                        foreach (DataRow oDRte in oDTte.Rows)
                            DoKmlTE(tsiprepname, Convert.ToInt32(oDRte["tecaseno"]));
                    }
                }

                strSql = "SELECT DISTINCT etcaseno FROM " + sitetable + " WHERE etreport > 0 ORDER BY etcaseno";
                DataTable oDTet = null;
                try
                {
                    oDTet = oCn.retrieve(strSql);
                }
                catch (Exception)
                {
                    oCn.dbdisconnect();
                    result.ok = false;
                    result.error = "A database error occurred while building the CASEDET KML report.";
                    return;
                }
                oCn.dbdisconnect();

                if (oDTet != null && oDTet.Rows.Count > 0)
                {
                    string tsiprepname = "et_" + tsipname;
                    if (reptype == "G")
                    {
                        DoKmlET(tsiprepname, 0);
                    }
                    else
                    {
                        foreach (DataRow oDRet in oDTet.Rows)
                            DoKmlET(tsiprepname, Convert.ToInt32(oDRet["etcaseno"]));
                    }
                }

                AppendBasenames(result.files, listTE);
                AppendBasenames(result.files, listET);
                Finish(result, listTE, listET, null);
            }

            public void RunTsts(CaseDetKmlResult result)
            {
                sitetable = schema + ".tt_" + tsipname + "_site";
                antetable = schema + ".tt_" + tsipname + "_ante";
                chantable = schema + ".tt_" + tsipname + "_chan";

                dbconnect oCn = new dbconnect();
                string strSql = "SELECT DISTINCT caseno FROM " + sitetable + " WHERE caseno> 0 AND report > 0 ORDER BY caseno";
                DataTable oDTtt = null;
                try
                {
                    oDTtt = oCn.retrieve(strSql);
                    oCn.dbdisconnect();
                }
                catch (Exception)
                {
                    oCn.dbdisconnect();
                    result.ok = false;
                    result.error = "A database error occurred while building the CASEDET KML report.";
                    return;
                }

                if (oDTtt == null || oDTtt.Rows.Count == 0)
                {
                    Finish(result, null, null, "");
                    return;
                }

                string tsiprepname = "tt_" + tsipname;
                if (reptype == "G")
                {
                    DoKmlTT(tsiprepname, 0);
                    CloseKmlIfOpen();
                }
                else
                {
                    foreach (DataRow oDR1 in oDTtt.Rows)
                    {
                        DoKmlTT(tsiprepname, Convert.ToInt32(oDR1["caseno"]));
                        CloseKmlIfOpen();
                    }
                }

                AppendBasenames(result.files, listTT);
                Finish(result, null, null, listTT);
            }

            private void Finish(CaseDetKmlResult result, string teList, string etList, string ttList)
            {
                bool haveFiles = result.files.Count > 0;
                if (!haveFiles)
                {
                    // W2-1: empty generate is failure, not success.
                    result.ok = false;
                    result.emailed = false;
                    result.error = "No files were created for run " + runinfo;
                    result.message = result.error;
                    return;
                }

                string emailError = "";
                int intended = 0;
                int sentCount = 0;
                if (ttList != null)
                {
                    intended = 1;
                    string err;
                    if (MailReports(reptype, "TT", tsipname, ttList, out err))
                        sentCount = 1;
                    else
                        emailError = err;
                }
                else
                {
                    if (!string.IsNullOrEmpty(teList))
                    {
                        intended++;
                        string err;
                        if (MailReports(reptype, "TE", tsipname, teList, out err))
                            sentCount++;
                        else
                            emailError = err;
                    }
                    if (!string.IsNullOrEmpty(etList))
                    {
                        intended++;
                        string err;
                        if (MailReports(reptype, "ET", tsipname, etList, out err))
                            sentCount++;
                        else if (string.IsNullOrEmpty(emailError))
                            emailError = err;
                    }
                }

                // W2-2: all intended emails must succeed for ok=true.
                if (intended > 0 && sentCount < intended)
                {
                    result.ok = false;
                    result.emailed = sentCount > 0;
                    result.error = string.IsNullOrEmpty(emailError)
                        ? "One or more KML emails failed to send."
                        : emailError;
                    result.message = sentCount > 0
                        ? ("Partial KML email for run " + runinfo + ": " + sentCount + " of " + intended + " sent. " + result.error)
                        : result.error;
                    return;
                }

                result.ok = true;
                result.emailed = sentCount > 0;
                result.error = "";
                result.message = "Your KML files for run " + runinfo + " have been e-mailed to you";
            }

            private static void AppendBasenames(List<string> dest, string reportlist)
            {
                if (string.IsNullOrEmpty(reportlist)) return;
                char[] delimiter = ";".ToCharArray();
                string[] flist = reportlist.Split(delimiter);
                for (int i = 0; i < flist.Length - 1; i++)
                    dest.Add(flist[i]);
            }

            private void CloseKmlIfOpen()
            {
                if (sw == null) return;
                sw.WriteLine("</Document>");
                sw.WriteLine("</kml>");
                sw.Close();
                sw = null;
            }

            private void DoKmlTE(string tsiprepname, Int32 caseno)
            {
                if (caseno == 0)
                    tsiprepname = tsiprepname + "all.kml";
                else
                    tsiprepname = tsiprepname + "-" + caseno.ToString() + ".kml";

                tsipDataTE = GetTsipDataTE(sitetable, antetable, chantable, caseno);
                if (tsipDataTE == null || tsipDataTE.Rows.Count == 0)
                    return;

                listTE += tsiprepname + ";";
                WriteKmlHeader("TE", tsiprepname);
                WriteTESiteInfo(pdfname, chantable);
                WriteTETTLinkInfo(pdfname, antetable, chantable);
                WriteTEInterInfo(pdfname, antetable, chantable);

                if (filePathFlag != "")
                {
                    sw.WriteLine("</Document>");
                    sw.WriteLine("</kml>");
                    sw.Close();
                    sw = null;
                }
            }

            private void DoKmlET(string tsiprepname, Int32 caseno)
            {
                if (caseno == 0)
                    tsiprepname = tsiprepname + "all.kml";
                else
                    tsiprepname = tsiprepname + "-" + caseno.ToString() + ".kml";

                tsipDataET = GetTsipDataET(sitetable, antetable, chantable, caseno);
                if (tsipDataET == null || tsipDataET.Rows.Count == 0)
                    return;

                listET += tsiprepname + ";";
                WriteKmlHeader("ET", tsiprepname);
                WriteETSiteInfo(pdfname, chantable);
                WriteETTTLinkInfo(pdfname, antetable, chantable);
                WriteETInterInfo(pdfname, antetable, chantable);

                if (filePathFlag != "")
                {
                    sw.WriteLine("</Document>");
                    sw.WriteLine("</kml>");
                    sw.Close();
                    sw = null;
                }
            }

            private void DoKmlTT(string tsiprepname, Int32 caseno)
            {
                if (caseno == 0)
                    tsiprepname = tsiprepname + "all.kml";
                else
                    tsiprepname = tsiprepname + "-" + caseno.ToString() + ".kml";

                tsipDataTT = GetTsipDataTT(sitetable, antetable, chantable, caseno);
                if (tsipDataTT == null || tsipDataTT.Rows.Count == 0)
                    return;

                listTT += tsiprepname + ";";
                WriteKmlHeaderTT(tsiprepname);
                WriteTTSiteInfo(pdfname, chantable, caseno);
                WriteTTLinkInfo(pdfname, antetable, chantable);
                WriteTTInterInfo(pdfname);
            }

            private void WriteTEInterInfo(string pdfnameArg, string antetableArg, string chantableArg)
            {
                foreach (DataRow oTErow in tsipDataTE.Rows)
                {
                    string icall1 = Convert.ToString(oTErow["terrcall1"]);
                    double idlat = Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oTErow["terrlatit"])));
                    double idlong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oTErow["terrlongit"])));
                    double idht = Convert.ToDouble(oTErow["terrht"]);
                    string ianum = Convert.ToString(oTErow["terranum"]);
                    string ifreqtx = Convert.ToString(oTErow["intfreqtx"]);

                    string vloc = Convert.ToString(oTErow["earthlocation"]);
                    double vdlat = Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oTErow["earthlatit"])));
                    double vdlong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oTErow["earthlongit"])));
                    double vdht = Convert.ToDouble(oTErow["earthht"]);
                    string vanum = Convert.ToString(oTErow["earthcall1"]);
                    string vfreqrx = Convert.ToString(oTErow["vicfreqrx"]);

                    string linkname = icall1.Trim() + "#" + ianum.Trim() + "(" + ifreqtx.Trim() + ") - " + vloc.Trim() + "#" + vanum.Trim() + "(" + vfreqrx.Trim() + ")";
                    WriteTEInter(oTErow, linkname, "antname", idlong, idlat, idht, vdlong, vdlat, vdht);
                }
            }

            private void WriteETInterInfo(string pdfnameArg, string antetableArg, string chantableArg)
            {
                foreach (DataRow oETrow in tsipDataET.Rows)
                {
                    string ilocat = Convert.ToString(oETrow["earthlocation"]);
                    double idlat = Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oETrow["earthlatit"])));
                    double idlong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oETrow["earthlongit"])));
                    double idht = Convert.ToDouble(oETrow["earthht"]);
                    string ianum = Convert.ToString(oETrow["earthcall1"]);
                    string ifreqtx = Convert.ToString(oETrow["intfreqtx"]);

                    string vcall1 = Convert.ToString(oETrow["terrcall1"]);
                    double vdlat = Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oETrow["terrlatit"])));
                    double vdlong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oETrow["terrlongit"])));
                    double vdht = Convert.ToDouble(oETrow["terrht"]);
                    string vanum = Convert.ToString(oETrow["terranum"]);
                    string vfreqrx = Convert.ToString(oETrow["vicfreqrx"]);
                    string linkname = ilocat.Trim() + "#" + ianum.Trim() + "(" + ifreqtx.Trim() + ") - " + vcall1.Trim() + "#" + vanum.Trim() + "(" + vfreqrx.Trim() + ")";
                    WriteETInter(oETrow, linkname, "antname", idlong, idlat, idht, vdlong, vdlat, vdht);
                }
            }

            private void WriteTESiteInfo(string pdfnameArg, string chantableArg)
            {
                string fesiteTable = schema + ".fe_" + pdfnameArg + "_site";
                string ftsiteTable = schema + ".ft_" + pdfnameArg + "_site";
                string mesiteTable = "main.me_site";
                string mtsiteTable = "main.mt_site";

                dbconnect oCn = new dbconnect();
                HashSet<string> callsigns = new HashSet<string>();

                DataView tsipTE = new DataView(tsipDataTE);
                DataTable terrcall1 = tsipTE.ToTable(true, "terrcall1");
                foreach (DataRow oTC1 in terrcall1.Rows)
                    callsigns.Add("T:" + Convert.ToString(oTC1["terrcall1"]) + "^");

                DataTable terrcall2 = tsipTE.ToTable(true, "terrcall2");
                foreach (DataRow oTC2 in terrcall2.Rows)
                    callsigns.Add("T:" + Convert.ToString(oTC2["terrcall2"]) + "^");

                DataTable earthloc = tsipTE.ToTable(true, "earthlocation");
                foreach (DataRow oEL1 in earthloc.Rows)
                    callsigns.Add("E:" + Convert.ToString(oEL1["earthlocation"]) + "^");

                string strSql1;
                foreach (string call1 in callsigns)
                {
                    char[] delimiter = ":^".ToCharArray();
                    string[] callparts = call1.Split(delimiter);

                    if (callparts[0] == "T")
                    {
                        if (protype == "T")
                        {
                            strSql1 = @"SELECT RTRIM(name) as name, latit, longit, grnd FROM " + ftsiteTable +
                                 " WHERE call1 = '" + callparts[1] + "'" +
                                 " UNION " +
                                 " SELECT RTRIM(name), latit, longit, grnd FROM " + mtsiteTable +
                                 " WHERE call1 = '" + callparts[1] + "'";
                        }
                        else
                        {
                            strSql1 = @"SELECT RTRIM(name) as name, latit, longit, grnd FROM " + mtsiteTable +
                                " WHERE call1 = '" + callparts[1] + "'";
                        }

                        DataTable TC1info = null;
                        try
                        {
                            TC1info = oCn.retrieve(strSql1);
                        }
                        catch (Exception)
                        {
                            oCn.dbdisconnect();
                            return;
                        }
                        foreach (DataRow oTC1i in TC1info.Rows)
                        {
                            double dlat = Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oTC1i["latit"])));
                            double dlong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oTC1i["longit"])));
                            double dalt = Convert.ToDouble(oTC1i["grnd"]);
                            WriteSitePoint(callparts[1], Convert.ToString(oTC1i["name"]), dlong, dlat, dalt);
                        }
                    }
                    else
                    {
                        string strSql3;
                        if (protype == "E")
                        {
                            strSql3 = @"SELECT RTRIM(name) as name, latit, longit, grnd FROM " + fesiteTable +
                                     " WHERE location = '" + callparts[1] + "'" +
                                     " UNION " +
                                     " SELECT RTRIM(name), latit, longit, grnd FROM " + mesiteTable +
                                     " WHERE location = '" + callparts[1] + "'";
                        }
                        else
                        {
                            strSql3 = @"SELECT RTRIM(name) as name, latit, longit, grnd FROM " + mesiteTable +
                                    " WHERE location = '" + callparts[1] + "'";
                        }

                        DataTable EL1info = null;
                        try
                        {
                            EL1info = oCn.retrieve(strSql3);
                        }
                        catch (Exception)
                        {
                            oCn.dbdisconnect();
                            return;
                        }
                        foreach (DataRow oEL1i in EL1info.Rows)
                        {
                            double dlat = Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oEL1i["latit"])));
                            double dlong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oEL1i["longit"])));
                            double dalt = Convert.ToDouble(oEL1i["grnd"]);
                            WriteSitePoint(callparts[1], Convert.ToString(oEL1i["name"]), dlong, dlat, dalt);
                        }
                    }
                }
                oCn.dbdisconnect();
            }

            private void WriteETSiteInfo(string pdfnameArg, string chantableArg)
            {
                string fesiteTable = schema + ".fe_" + pdfnameArg + "_site";
                string ftsiteTable = schema + ".ft_" + pdfnameArg + "_site";
                string mesiteTable = "main.me_site";
                string mtsiteTable = "main.mt_site";

                dbconnect oCn = new dbconnect();
                HashSet<string> callsigns = new HashSet<string>();

                DataView tsipET = new DataView(tsipDataET);
                DataTable terrcall1 = tsipET.ToTable(true, "terrcall1");
                foreach (DataRow oTC1 in terrcall1.Rows)
                    callsigns.Add("T:" + Convert.ToString(oTC1["terrcall1"]) + "^");

                DataTable terrcall2 = tsipET.ToTable(true, "terrcall2");
                foreach (DataRow oTC2 in terrcall2.Rows)
                    callsigns.Add("T:" + Convert.ToString(oTC2["terrcall2"]) + "^");

                DataTable earthloc = tsipET.ToTable(true, "earthlocation");
                foreach (DataRow oEL1 in earthloc.Rows)
                    callsigns.Add("E:" + Convert.ToString(oEL1["earthlocation"]) + "^");

                string strSql1;
                foreach (string call1 in callsigns)
                {
                    char[] delimiter = ":^".ToCharArray();
                    string[] callparts = call1.Split(delimiter);

                    if (callparts[0] == "T")
                    {
                        if (protype == "T")
                        {
                            strSql1 = @"SELECT RTRIM(name) as name, latit, longit, grnd FROM " + ftsiteTable +
                                 " WHERE call1 = '" + callparts[1] + "'" +
                                 " UNION " +
                                 " SELECT RTRIM(name), latit, longit, grnd FROM " + mtsiteTable +
                                 " WHERE call1 = '" + callparts[1] + "'";
                        }
                        else
                        {
                            strSql1 = @"SELECT RTRIM(name) as name, latit, longit, grnd FROM " + mtsiteTable +
                                " WHERE call1 = '" + callparts[1] + "'";
                        }

                        DataTable TC1info = null;
                        try
                        {
                            TC1info = oCn.retrieve(strSql1);
                        }
                        catch (Exception)
                        {
                            oCn.dbdisconnect();
                            return;
                        }
                        foreach (DataRow oTC1i in TC1info.Rows)
                        {
                            double dlat = Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oTC1i["latit"])));
                            double dlong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oTC1i["longit"])));
                            double dalt = Convert.ToDouble(oTC1i["grnd"]);
                            WriteSitePoint(callparts[1], Convert.ToString(oTC1i["name"]), dlong, dlat, dalt);
                        }
                    }
                    else
                    {
                        string strSql3;
                        if (protype == "E")
                        {
                            strSql3 = @"SELECT RTRIM(name) as name, latit, longit, grnd FROM " + fesiteTable +
                                     " WHERE location = '" + callparts[1] + "'" +
                                     " UNION " +
                                     " SELECT RTRIM(name), latit, longit, grnd FROM " + mesiteTable +
                                     " WHERE location = '" + callparts[1] + "'";
                        }
                        else
                        {
                            strSql3 = @"SELECT RTRIM(name) as name, latit, longit, grnd FROM " + mesiteTable +
                                    " WHERE location = '" + callparts[1] + "'";
                        }

                        DataTable EL1info = null;
                        try
                        {
                            EL1info = oCn.retrieve(strSql3);
                        }
                        catch (Exception)
                        {
                            oCn.dbdisconnect();
                            return;
                        }
                        foreach (DataRow oEL1i in EL1info.Rows)
                        {
                            double dlat = Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oEL1i["latit"])));
                            double dlong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oEL1i["longit"])));
                            double dalt = Convert.ToDouble(oEL1i["grnd"]);
                            WriteSitePoint(callparts[1], Convert.ToString(oEL1i["name"]), dlong, dlat, dalt);
                        }
                    }
                }
                oCn.dbdisconnect();
            }

            private void WriteSitePoint(string call1, string name, double sdeclong, double sdeclat, double salt)
            {
                sw.WriteLine("<Placemark>");
                sw.WriteLine("<name>" + call1 + "</name>");
                sw.WriteLine("<description> " + ConvertStrAmp(name) + "</description>");
                sw.WriteLine("<Point>");
                sw.WriteLine("<altitudeMode>absolute</altitudeMode>");
                sw.WriteLine("<coordinates>" + sdeclong.ToString(format6) + "," + sdeclat.ToString(format6) + "," + salt.ToString(format2) + "</coordinates>");
                sw.WriteLine("</Point>");
                sw.WriteLine("</Placemark>");
                sw.Flush();
            }

            private void WriteTETTLinkInfo(string pdfnameArg, string antetableArg, string chantableArg)
            {
                dbconnect oCn = new dbconnect();
                string mtsiteTable = "main.mt_site";

                string rcall1 = "";
                double rdlat = 0;
                double rdlong = 0;
                double rdsalt = 0;
                string ranum = "";
                double rdaalt = 0;

                string lcall1 = "";
                double ldlat = 0;
                double ldlong = 0;
                double ldht = 0;
                string lfreqtx = "";
                string lanum = "";

                DataView TTintview = new DataView(tsipDataTE);
                DataTable TTinter = TTintview.ToTable(true, "terrcall1", "terranum", "terrcall2", "intfreqtx", "terrname1", "terrlatit", "terrlongit", "terrht");

                foreach (DataRow oDR2 in TTinter.Rows)
                {
                    // W1-4: reset remote end each row; skip green link if site lookup misses.
                    rdlat = 0;
                    rdlong = 0;
                    rdsalt = 0;
                    ranum = "";
                    rdaalt = 0;
                    bool haveRemote = false;

                    lcall1 = Convert.ToString(oDR2["terrcall1"]);
                    lanum = Convert.ToString(oDR2["terranum"]);
                    rcall1 = Convert.ToString(oDR2["terrcall2"]);
                    lfreqtx = Convert.ToString(oDR2["intfreqtx"]);

                    ldlat = Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oDR2["terrlatit"])));
                    ldlong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oDR2["terrlongit"])));
                    ldht = Convert.ToDouble(oDR2["terrht"]);

                    string strSql = @"SELECT DISTINCT RTRIM(name) as name, latit, longit, grnd FROM " + mtsiteTable +
                            " WHERE call1 = '" + rcall1 + "'";
                    try
                    {
                        using (OdbcConnection cn = new OdbcConnection(cnstr))
                        {
                            cn.Open();
                            using (OdbcCommand select2 = new OdbcCommand(strSql, cn))
                            using (OdbcDataReader dr2 = select2.ExecuteReader())
                            {
                                if (dr2.HasRows)
                                {
                                    dr2.Read();
                                    rdlat = Convert.ToDouble(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr2, 1)));
                                    rdlong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr2, 2)));
                                    rdsalt = Convert.ToDouble(DBUtils.GetDBFloat(dr2, 3, 1));
                                    haveRemote = true;
                                }
                            }
                        }
                    }
                    catch (Exception ee)
                    {
                        ErrorUtils.NotifySystemOps(ee, "WriteTETTLinkInfo1");
                    }

                    if (!haveRemote)
                        continue;

                    string strSqlraht = @"SELECT c.antnumbrx1, a.aht FROM main.mt_chan c  " +
                            "INNER JOIN main.mt_ante a ON a.call1 = c.call1 AND a.call2 = c.call2 " +
                            "AND a.bndcde = c.bndcde AND a.anum = c.antnumbrx1 " +
                            "WHERE c.call1='" + rcall1 + "' AND c.call2='" + lcall1 +
                            "' AND c.freqrx=" + Convert.ToString(oDR2["intfreqtx"]);
                    try
                    {
                        using (OdbcConnection cn = new OdbcConnection(cnstr))
                        {
                            cn.Open();
                            using (OdbcCommand select3 = new OdbcCommand(strSqlraht, cn))
                            using (OdbcDataReader dr3 = select3.ExecuteReader())
                            {
                                if (dr3.HasRows)
                                {
                                    dr3.Read();
                                    ranum = Convert.ToString(dr3.GetValue(0));
                                    rdaalt = Convert.ToDouble(DBUtils.GetDBFloat(dr3, 1, 2));
                                }
                            }
                        }
                    }
                    catch (Exception ee)
                    {
                        ErrorUtils.NotifySystemOps(ee, "WriteTETTLinkInfo2");
                    }

                    string linkname = lcall1.Trim() + "#" + lanum.Trim() + "(" + lfreqtx.Trim() + ") - " + rcall1.Trim() + "#" + ranum.Trim();
                    WriteGELink(linkname, rdlong, rdlat, rdsalt + rdaalt, ldlong, ldlat, ldht);
                }
                oCn.dbdisconnect();
            }

            private void WriteETTTLinkInfo(string pdfnameArg, string antetableArg, string chantableArg)
            {
                dbconnect oCn = new dbconnect();
                string mtsiteTable = "main.mt_site";

                string rcall1 = "";
                double rdlat = 0;
                double rdlong = 0;
                double rdsalt = 0;
                string ranum = "";
                string rfreqtx = "";
                double rdaalt = 0;

                string lcall1 = "";
                double ldlat = 0;
                double ldlong = 0;
                double ldht = 0;
                string lanum = "";

                DataView TTvicview = new DataView(tsipDataET);
                DataTable TTvictim = TTvicview.ToTable(true, "terrcall1", "terranum", "terrcall2", "vicfreqrx", "terrname1", "terrlatit", "terrlongit", "terrht");

                foreach (DataRow oDR2 in TTvictim.Rows)
                {
                    // W1-4: reset remote end each row; skip green link if site lookup misses.
                    rdlat = 0;
                    rdlong = 0;
                    rdsalt = 0;
                    ranum = "";
                    rdaalt = 0;
                    bool haveRemote = false;

                    lcall1 = Convert.ToString(oDR2["terrcall1"]);
                    lanum = Convert.ToString(oDR2["terranum"]);
                    rcall1 = Convert.ToString(oDR2["terrcall2"]);
                    rfreqtx = Convert.ToString(oDR2["vicfreqrx"]);

                    ldlat = Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oDR2["terrlatit"])));
                    ldlong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oDR2["terrlongit"])));
                    ldht = Convert.ToDouble(oDR2["terrht"]);

                    string strSql = @"SELECT DISTINCT RTRIM(name) as name, latit, longit, grnd FROM " + mtsiteTable +
                            " WHERE call1 = '" + rcall1 + "'";
                    try
                    {
                        using (OdbcConnection cn = new OdbcConnection(cnstr))
                        {
                            cn.Open();
                            using (OdbcCommand select2 = new OdbcCommand(strSql, cn))
                            using (OdbcDataReader dr2 = select2.ExecuteReader())
                            {
                                if (dr2.HasRows)
                                {
                                    dr2.Read();
                                    rdlat = Convert.ToDouble(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr2, 1)));
                                    rdlong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr2, 2)));
                                    rdsalt = Convert.ToDouble(DBUtils.GetDBFloat(dr2, 3, 1));
                                    haveRemote = true;
                                }
                            }
                        }
                    }
                    catch (Exception ee)
                    {
                        ErrorUtils.NotifySystemOps(ee, "WriteETTTLinkInfo1");
                    }

                    if (!haveRemote)
                        continue;

                    string strSqlraht = @"SELECT c.antnumbtx1, a.aht FROM main.mt_chan c  " +
                            "INNER JOIN main.mt_ante a ON a.call1 = c.call1 AND a.call2 = c.call2 " +
                            "AND a.bndcde = c.bndcde AND a.anum = c.antnumbtx1 " +
                            "WHERE c.call1='" + rcall1 + "' AND c.call2='" + lcall1 +
                            "' AND c.freqtx=" + Convert.ToString(oDR2["vicfreqrx"]);
                    try
                    {
                        using (OdbcConnection cn = new OdbcConnection(cnstr))
                        {
                            cn.Open();
                            using (OdbcCommand select3 = new OdbcCommand(strSqlraht, cn))
                            using (OdbcDataReader dr3 = select3.ExecuteReader())
                            {
                                if (dr3.HasRows)
                                {
                                    dr3.Read();
                                    ranum = Convert.ToString(dr3.GetValue(0));
                                    rdaalt = Convert.ToDouble(DBUtils.GetDBFloat(dr3, 1, 2));
                                }
                            }
                        }
                    }
                    catch (Exception ee)
                    {
                        ErrorUtils.NotifySystemOps(ee, "WriteETTTLinkInfo2");
                    }

                    string linkname = rcall1.Trim() + "#" + ranum.Trim() + "(" + rfreqtx.Trim() + ") - " + lcall1.Trim() + "#" + lanum.Trim();
                    WriteGELink(linkname, rdlong, rdlat, rdsalt + rdaalt, ldlong, ldlat, ldht);
                }
                oCn.dbdisconnect();
            }

            private void WriteGELink(string slinkname, double dlongl, double dlatl, double saltl, double dlongr, double dlatr, double saltr)
            {
                double ptlong = dlongl + (dlongr - dlongl) / 2.0;
                double ptlat = dlatl + (dlatr - dlatl) / 2.0;
                double ptalt = saltl + (saltr - saltl) / 2.0;

                sw.WriteLine("<Placemark>");
                sw.WriteLine("<name></name>");
                sw.WriteLine("<description>" + slinkname + "</description>");
                sw.WriteLine("<styleUrl>#green</styleUrl>");
                sw.WriteLine("<MultiGeometry>");
                sw.WriteLine("<Point>");
                sw.WriteLine("<altitudeMode>absolute</altitudeMode>");
                sw.WriteLine("<coordinates>" + ptlong.ToString(format6) + "," + ptlat.ToString(format6) + "," + ptalt.ToString(format2) + "</coordinates>");
                sw.WriteLine("</Point>");
                sw.WriteLine("<LineString>");
                sw.WriteLine("<altitudeMode>absolute</altitudeMode>");
                sw.WriteLine("<coordinates>");
                sw.WriteLine(dlongl.ToString(format6) + "," + dlatl.ToString(format6) + "," + saltl.ToString(format2));
                sw.WriteLine(dlongr.ToString(format6) + "," + dlatr.ToString(format6) + "," + saltr.ToString(format2));
                sw.WriteLine("</coordinates>");
                sw.WriteLine("</LineString>");
                sw.WriteLine("</MultiGeometry>");
                sw.WriteLine("</Placemark>");
                sw.WriteLine("");
                sw.Flush();
            }

            private void WriteTEInter(DataRow oDR, string slinkname, string santname, double dlongl, double dlatl, double saltl, double dlongr, double dlatr, double saltr)
            {
                double ptlong = dlongl + (dlongr - dlongl) / 4.0;
                double ptlat = dlatl + (dlatr - dlatl) / 4.0;
                double ptalt = saltl + (saltr - saltl) / 4.0;

                sw.WriteLine("<Placemark>");
                sw.WriteLine("<name>TS-ES CASE " + Convert.ToString(oDR["tecaseno"]) + "-" + Convert.ToString(oDR["tesubcaseno"]) + "</name>");
                sw.WriteLine("<description>" + HtmlDescTE(oDR, dlongl, dlatl, dlongr, dlatr) + "</description>");
                sw.WriteLine("<styleUrl>#red</styleUrl>");
                sw.WriteLine("<MultiGeometry>");
                sw.WriteLine("<Point>");
                sw.WriteLine("<altitudeMode>absolute</altitudeMode>");
                sw.WriteLine("<coordinates>" + ptlong.ToString(format6) + "," + ptlat.ToString(format6) + "," + ptalt.ToString(format2) + "</coordinates>");
                sw.WriteLine("</Point>");
                sw.WriteLine("<LineString>");
                sw.WriteLine("<altitudeMode>absolute</altitudeMode>");
                sw.WriteLine("<coordinates>");
                sw.WriteLine(dlongl.ToString() + "," + dlatl.ToString() + "," + saltl.ToString());
                sw.WriteLine(dlongr.ToString() + "," + dlatr.ToString() + "," + saltr.ToString());
                sw.WriteLine("</coordinates>");
                sw.WriteLine("</LineString>");
                sw.WriteLine("</MultiGeometry>");
                sw.WriteLine("</Placemark>");
                sw.WriteLine("");
                sw.Flush();
            }

            private void WriteETInter(DataRow oDR, string slinkname, string santname, double dlongl, double dlatl, double saltl, double dlongr, double dlatr, double saltr)
            {
                double ptlong = dlongl + (dlongr - dlongl) / 4.0;
                double ptlat = dlatl + (dlatr - dlatl) / 4.0;
                double ptalt = saltl + (saltr - saltl) / 4.0;

                sw.WriteLine("<Placemark>");
                sw.WriteLine("<name>ES-TS CASE " + Convert.ToString(oDR["etcaseno"]) + "-" + Convert.ToString(oDR["etsubcaseno"]) + "</name>");
                sw.WriteLine("<description>" + HtmlDescET(oDR, dlongl, dlatl, dlongr, dlatr) + "</description>");
                sw.WriteLine("<styleUrl>#red</styleUrl>");
                sw.WriteLine("<MultiGeometry>");
                sw.WriteLine("<Point>");
                sw.WriteLine("<altitudeMode>absolute</altitudeMode>");
                sw.WriteLine("<coordinates>" + ptlong.ToString(format6) + "," + ptlat.ToString(format6) + "," + ptalt.ToString(format2) + "</coordinates>");
                sw.WriteLine("</Point>");
                sw.WriteLine("<LineString>");
                sw.WriteLine("<altitudeMode>absolute</altitudeMode>");
                sw.WriteLine("<coordinates>");
                sw.WriteLine(dlongl.ToString() + "," + dlatl.ToString() + "," + saltl.ToString());
                sw.WriteLine(dlongr.ToString() + "," + dlatr.ToString() + "," + saltr.ToString());
                sw.WriteLine("</coordinates>");
                sw.WriteLine("</LineString>");
                sw.WriteLine("</MultiGeometry>");
                sw.WriteLine("</Placemark>");
                sw.WriteLine("");
                sw.Flush();
            }

            private void WriteKmlHeader(string report_type, string inname)
            {
                string tsipkml = userDir + inname;
                filePathFlag = userDir;
                sw = new StreamWriter(tsipkml, false);

                sw.WriteLine("<?xml version=\"1.0\" encoding=\"utf-8\"?>");
                sw.WriteLine("<kml xmlns=\"http://earth.google.com/kml/2.2\">");
                sw.WriteLine("<Document>");
                sw.WriteLine("<name>TSIP (" + report_type + ") " + inname + "</name>");
                WriteLineStyles();
            }

            private void WriteKmlHeaderTT(string inname)
            {
                string tsipkml = userDir + inname;
                filePathFlag = userDir;
                sw = new StreamWriter(tsipkml, false);

                sw.WriteLine("<?xml version=\"1.0\" encoding=\"utf-8\"?>");
                sw.WriteLine("<kml xmlns=\"http://earth.google.com/kml/2.2\">");
                sw.WriteLine("<Document>");
                sw.WriteLine("<name>TSIP " + "TT" + "</name>");
                sw.WriteLine("<name>TSIP (TT) " + inname + "</name>");
                WriteLineStyles();
            }

            private void WriteLineStyles()
            {
                sw.WriteLine("<Style id='red'>");
                sw.WriteLine("  <IconStyle>");
                sw.WriteLine("    <color>7f0000ff</color>");
                sw.WriteLine("  </IconStyle>");
                sw.WriteLine("  <LineStyle>");
                sw.WriteLine("    <color>7f0000ff</color>");
                sw.WriteLine("    <width>3</width>");
                sw.WriteLine("  </LineStyle>");
                sw.WriteLine("</Style>");
                sw.WriteLine("");
                sw.WriteLine("<Style id='green'>");
                sw.WriteLine("  <IconStyle>");
                sw.WriteLine("    <color>7f00ff00</color>");
                sw.WriteLine("  </IconStyle>");
                sw.WriteLine("  <LineStyle>");
                sw.WriteLine("    <color>7f00ff00</color>");
                sw.WriteLine("    <width>3</width>");
                sw.WriteLine("  </LineStyle>");
                sw.WriteLine("</Style>");
            }

            private DataTable GetTsipDataTE(string siteTbl, string anteTbl, string chanTbl, Int32 caseno)
            {
                dbconnect oCn = new dbconnect();
                string casewhere = "0";
                if (caseno == 0)
                    casewhere = ">0";
                else
                    casewhere = "=" + caseno.ToString();

                string strSql = @"SELECT RTRIM(s.terrcall1) AS terrcall1, RTRIM(s.terrcall2) AS terrcall2, " +
                     " RTRIM(s.earthlocation) AS earthlocation, RTRIM(a.earthcall1) AS earthcall1, " +
                     " RTRIM(s.terrname1) AS terrname1, RTRIM(s.terrname2) AS terrname2, RTRIM(earthname) AS earthname, " +
                     " RTRIM(s.terroper) AS terroper, RTRIM(s.earthoper) AS earthoper, RTRIM(a.satname) as satname, RTRIM(a.satoper) as satoper, a.terranum, " +
                     " terrlatit, terrlongit, terrgrnd, terrht, a.ediscang, a.tdiscang, a.tesubcaseno, " +
                     " earthlatit, earthlongit, earthgrnd, earthht, a.satlongit, a.sarc1, a.sarc2, a.esazim, a.eselev, " +
                     " c.intfreqtx, c.vicfreqrx, c.inttxpwr, c.vicpwrrx, c.marg20mode1, c.marg01mode1, c.marg01mode2, s.etdist," +
                     " a.terracode, a.earthacode, inteqpttx, viceqptrx, inttraftx, victrafrx, tecaseno " +
                     " FROM " + chanTbl + " c INNER JOIN " + anteTbl + " a " +
                     " ON a.interferer=c.interferer " +
                     " AND a.terrcall1=c.terrcall1 AND a.terrcall2=c.terrcall2 " +
                     " AND a.earthlocation=c.earthlocation AND a.earthcall1=c.earthcall1 " +
                     " AND a.terrbndcde=c.terrbndcde AND a.terranum=c.terranum " +
                     " AND a.earthcall1=c.earthcall1 " +
                     " INNER JOIN " + siteTbl + " s ON " +
                     " s.terrcall1=c.terrcall1 AND s.terrcall2=c.terrcall2 " +
                     " AND s.earthlocation=c.earthlocation " +
                     " WHERE s.tecaseno " + casewhere +
                     " AND a.interferer = 'T' " +
                     " AND c.tereport > 0" +
                     " ORDER BY tecaseno, tesubcaseno";

                DataTable oDT = null;
                try
                {
                    oDT = oCn.retrieve(strSql);
                }
                catch (Exception)
                {
                    oCn.dbdisconnect();
                    return oDT;
                }
                oCn.dbdisconnect();
                return oDT;
            }

            private DataTable GetTsipDataET(string siteTbl, string anteTbl, string chanTbl, Int32 caseno)
            {
                dbconnect oCn = new dbconnect();
                string casewhere = "0";
                if (caseno == 0)
                    casewhere = ">0";
                else
                    casewhere = "=" + caseno.ToString();

                string strSql = @"SELECT RTRIM(s.terrcall1) AS terrcall1, RTRIM(s.terrcall2) AS terrcall2, " +
                     " RTRIM(s.earthlocation) AS earthlocation, RTRIM(a.earthcall1) AS earthcall1, " +
                     " RTRIM(s.terrname1) AS terrname1, RTRIM(s.terrname2) AS terrname2, RTRIM(earthname) AS earthname, " +
                     " RTRIM(s.terroper) AS terroper, RTRIM(s.earthoper) AS earthoper, RTRIM(a.satname) as satname, RTRIM(a.satoper) as satoper, a.terranum, " +
                     " terrlatit, terrlongit, terrgrnd, terrht, a.ediscang, a.tdiscang, a.etsubcaseno, " +
                     " earthlatit, earthlongit, earthgrnd, earthht, a.satlongit, a.sarc1, a.sarc2, a.esazim, a.eselev, " +
                     " c.intfreqtx, c.vicfreqrx, c.inttxpwr, c.vicpwrrx, c.marg20mode1, c.marg01mode1, c.marg01mode2, s.etdist," +
                     " a.terracode, a.earthacode, inteqpttx, viceqptrx, inttraftx, victrafrx, etcaseno " +
                     " FROM " + chanTbl + " c INNER JOIN " + anteTbl + " a " +
                     " ON a.interferer=c.interferer " +
                     " AND a.terrcall1=c.terrcall1 AND a.terrcall2=c.terrcall2 " +
                     " AND a.earthlocation=c.earthlocation AND a.earthcall1=c.earthcall1 " +
                     " AND a.terrbndcde=c.terrbndcde AND a.terranum=c.terranum " +
                     " AND a.earthcall1=c.earthcall1 " +
                     " INNER JOIN " + siteTbl + " s ON " +
                     " s.terrcall1=c.terrcall1 AND s.terrcall2=c.terrcall2 " +
                     " AND s.earthlocation=c.earthlocation " +
                     " WHERE s.etcaseno " + casewhere +
                     " AND a.interferer = 'E' " +
                     " AND c.ETreport > 0" +
                     " ORDER BY etcaseno, etsubcaseno";

                DataTable oDT = null;
                try
                {
                    oDT = oCn.retrieve(strSql);
                }
                catch (Exception)
                {
                    oCn.dbdisconnect();
                    return oDT;
                }
                oCn.dbdisconnect();
                return oDT;
            }

            private string HtmlDescTE(DataRow oDR, double dlongl, double dlatl, double dlongr, double dlatr)
            {
                StringBuilder htmldes = new StringBuilder("<![CDATA[", 1000);
                htmldes.Append("<table border=\"1\">");
                htmldes.Append("<tr>");
                htmldes.Append("<td></td>");
                htmldes.Append("<td>Interferer</td><td>Victim</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Call1-call2/location-call1</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["terrcall1"]) + "-" + Convert.ToString(oDR["terrcall2"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["earthlocation"]) + "-" + Convert.ToString(oDR["earthcall1"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Name1-Name2</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["terrname1"]) + "-" + Convert.ToString(oDR["terrname2"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["earthlocation"]) + "-" + Convert.ToString(oDR["earthname"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td></td>");
                htmldes.Append("<td colspan=\"2\" align=\"center\">" + Convert.ToString(oDR["terrcall1"]) + "-" + Convert.ToString(oDR["earthlocation"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Satellite</td>");
                htmldes.Append("<td></td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["satname"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Operator</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["terroper"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["earthoper"]) + "-" + Convert.ToString(oDR["satoper"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Latitude</td>");
                htmldes.Append("<td>" + dlatl.ToString(format6) + "</td>");
                htmldes.Append("<td>" + dlatr.ToString(format6) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Longitude</td>");
                htmldes.Append("<td>" + dlongl.ToString(format6) + "</td>");
                htmldes.Append("<td>" + dlongr.ToString(format6) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Ground (m)</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["terrgrnd"]).ToString(format2) + "</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["earthgrnd"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Sat Long</td>");
                htmldes.Append("<td></td>");
                double satlong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oDR["satlongit"])));
                htmldes.Append("<td>" + satlong.ToString(format6) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Arc1, Arc2</td>");
                htmldes.Append("<td></td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["sarc1"]).ToString(format2) + "," + Convert.ToDouble(oDR["sarc2"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Frequency</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["intfreqtx"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["vicfreqrx"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Power (dBm)-(dBW)</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["inttxpwr"]).ToString(format2) + "</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["vicpwrrx"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Ant Code</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["terracode"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["earthacode"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Ant Height (m)</td>");
                htmldes.Append("<td>" + (Convert.ToDouble(oDR["terrht"]) - Convert.ToDouble(oDR["terrgrnd"])).ToString(format2) + "</td>");
                htmldes.Append("<td>" + (Convert.ToDouble(oDR["earthht"]) - Convert.ToDouble(oDR["earthgrnd"])).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>T-E Distance (km)</td>");
                htmldes.Append("<td colspan=\"2\" align=\"center\">" + Convert.ToDouble(oDR["etdist"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Off Ax (UTE)-(SET)</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["tdiscang"]).ToString(format2) + "</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["ediscang"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>ES Azim (deg)</td>");
                htmldes.Append("<td></td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["esazim"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>ES Elev Angle (deg)</td>");
                htmldes.Append("<td></td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["eselev"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Eqpt Code</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["inteqpttx"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["viceqptrx"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Traf Code</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["inttraftx"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["victrafrx"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Int Margin 20%T(dB)</td>");
                htmldes.Append("<td colspan=\"2\" align=\"center\">" + Convert.ToDouble(oDR["marg20mode1"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Int Margin 0.01%T(dB)</td>");
                htmldes.Append("<td colspan=\"2\" align=\"center\">" + Convert.ToDouble(oDR["marg01mode1"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Int Margin 0.01%P(dB)</td>");
                htmldes.Append("<td colspan=\"2\" align=\"center\">" + Convert.ToDouble(oDR["marg01mode2"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("</table>");
                htmldes.Append("]]>");
                return htmldes.ToString();
            }

            private string HtmlDescET(DataRow oDR, double dlongl, double dlatl, double dlongr, double dlatr)
            {
                StringBuilder htmldes = new StringBuilder("<![CDATA[", 1000);
                htmldes.Append("<table border=\"1\">");
                htmldes.Append("<tr>");
                htmldes.Append("<td></td>");
                htmldes.Append("<td>Interferer</td><td>Victim</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Location-call1/call1-call2</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["earthlocation"]) + "-" + Convert.ToString(oDR["earthcall1"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["terrcall1"]) + "-" + Convert.ToString(oDR["terrcall2"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Name1-name2</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["earthlocation"]) + "-" + Convert.ToString(oDR["earthname"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["terrname1"]) + "-" + Convert.ToString(oDR["terrname2"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td></td>");
                htmldes.Append("<td colspan=\"2\" align=\"center\">" + Convert.ToString(oDR["earthlocation"]) + "-" + Convert.ToString(oDR["terrcall1"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Satellite</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["satname"]) + "</td>");
                htmldes.Append("<td></td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Operator</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["earthoper"]) + "-" + Convert.ToString(oDR["satoper"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["terroper"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Latitude</td>");
                // W1-5: Interferer = left (dlatl), Victim = right (dlatr) — match HtmlDescTE / column headers.
                htmldes.Append("<td>" + dlatl.ToString(format6) + "</td>");
                htmldes.Append("<td>" + dlatr.ToString(format6) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Longitude</td>");
                htmldes.Append("<td>" + dlongl.ToString(format6) + "</td>");
                htmldes.Append("<td>" + dlongr.ToString(format6) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Ground (m)</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["earthgrnd"]).ToString(format2) + "</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["terrgrnd"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Sat Long</td>");
                double satlong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oDR["satlongit"])));
                htmldes.Append("<td>" + satlong.ToString(format6) + "</td>");
                htmldes.Append("<td></td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Arc1, Arc2</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["sarc1"]).ToString(format2) + "," + Convert.ToDouble(oDR["sarc2"]).ToString(format2) + "</td>");
                htmldes.Append("<td></td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Frequency</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["intfreqtx"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["vicfreqrx"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Power (dBW)-(dBm)</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["inttxpwr"]).ToString(format2) + "</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["vicpwrrx"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Ant Code</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["earthacode"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["terracode"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Ant Height (m)</td>");
                htmldes.Append("<td>" + (Convert.ToDouble(oDR["earthht"]) - Convert.ToDouble(oDR["earthgrnd"])).ToString(format2) + "</td>");
                htmldes.Append("<td>" + (Convert.ToDouble(oDR["terrht"]) - Convert.ToDouble(oDR["terrgrnd"])).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>E-T Distance (km)</td>");
                htmldes.Append("<td colspan=\"2\" align=\"center\">" + Convert.ToDouble(oDR["etdist"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Off Ax (SET)-(UTE)</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["ediscang"]).ToString(format2) + "</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["tdiscang"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>ES Azim (deg)</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["esazim"]).ToString(format2) + "</td>");
                htmldes.Append("<td></td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>ES Elev Angle (deg)</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["eselev"]).ToString(format2) + "</td>");
                htmldes.Append("<td></td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Eqpt Code</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["inteqpttx"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["viceqptrx"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Traf Code</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["inttraftx"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["victrafrx"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Int Margin 20%T(dB)</td>");
                htmldes.Append("<td colspan=\"2\" align=\"center\">" + Convert.ToDouble(oDR["marg20mode1"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Int Margin 0.01%T(dB)</td>");
                htmldes.Append("<td colspan=\"2\" align=\"center\">" + Convert.ToDouble(oDR["marg01mode1"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Int Margin 0.01%P(dB)</td>");
                htmldes.Append("<td colspan=\"2\" align=\"center\">" + Convert.ToDouble(oDR["marg01mode2"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("</table>");
                htmldes.Append("]]>");
                return htmldes.ToString();
            }

            private static DataTable GetTsipDataTT(string siteTbl, string anteTbl, string chanTbl, Int32 caseno)
            {
                dbconnect oCn = new dbconnect();
                string casewhere = "";
                if (caseno == 0)
                    casewhere = "> 0";
                else
                    casewhere = "=" + caseno.ToString();

                string strSql = @"SELECT " +
                "s.interferer, " +
                "RTRIM(s.intcall1) as intcall1, RTRIM(s.intcall2) as intcall2, RTRIM(s.viccall1) as viccall1, RTRIM(s.viccall2) as viccall2, " +
                "RTRIM(s.intname1) as intname1, RTRIM(s.intname2) as intname2, RTRIM(s.vicname1) as vicname1, RTRIM(s.vicname2) as vicname2, " +
                "s.intoper, s.vicoper, " +
                "s.intlatit, s.intlongit, s.intgrnd, " +
                "a.intaht, " +
                "s.viclatit, s.viclongit, s.vicgrnd, " +
                "a.vicaht, " +
                "s.report, s.caseno, s.subcases, " +
                "s.int1vic1dist, " +
                "a.intbndcde, a.intanum, a.vicbndcde, a.vicanum, " +
                "a.intacode, a.vicacode, a.report as areport, a.subcaseno, " +
                "a.intoffantax, a.vicoffantax, " +
                "c.intchid, c.vicchid, c.intpolar, c.vicpolar, " +
                "c.inttraftx, c.victrafrx, " +
                "c.inteqpttx, c.viceqptrx, c.intfreqtx, c.vicfreqrx, " +
                "c.intpwrtx, c.vicpwrrx, " +
                "c.report as creport, " +
                "c.resti " +
                "FROM " + chanTbl + " c INNER JOIN " + anteTbl + " a " +
                "ON a.interferer=c.interferer " +
                "AND a.intcall1=c.intcall1 AND a.intcall2=c.intcall2 " +
                "AND a.viccall1=c.viccall1 AND a.viccall2=c.viccall2 " +
                "AND a.intbndcde=c.intbndcde AND a.intanum=c.intanum " +
                "AND a.vicanum=c.vicanum " +
                "AND a.caseno=c.caseno " +
                "INNER JOIN " + siteTbl + " s ON " +
                "s.intcall1=c.intcall1 AND s.intcall2=c.intcall2 " +
                "AND s.viccall1=c.viccall1 AND s.viccall2 = c.viccall2 " +
                "AND s.interferer = c.interferer " +
                "AND s.caseno=c.caseno " +
                "WHERE c.report > 0 " +
                "AND  s.caseno " + casewhere +
                " ORDER BY caseno, subcaseno";

                DataTable oDT = null;
                try
                {
                    oDT = oCn.retrieve(strSql);
                    oCn.dbdisconnect();
                }
                catch (Exception)
                {
                    oCn.dbdisconnect();
                    return oDT;
                }
                return oDT;
            }

            private void WriteTTInterInfo(string pdfnameArg)
            {
                foreach (DataRow oDR in tsipDataTT.Rows)
                {
                    double intdeclat = Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oDR["intlatit"])));
                    double intdeclong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oDR["intlongit"])));
                    double intaht = Convert.ToDouble(oDR["intgrnd"]) + Convert.ToDouble(oDR["intaht"]);

                    double vicdeclat = Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oDR["viclatit"])));
                    double vicdeclong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oDR["viclongit"])));
                    double vicaht = Convert.ToDouble(oDR["vicgrnd"]) + Convert.ToDouble(oDR["vicaht"]);

                    string linkname = "CASE " + Convert.ToString(oDR["caseno"]) + "-" + Convert.ToString(oDR["subcaseno"]);
                    WriteGEInter(oDR, linkname, "antname", intdeclong, intdeclat, intaht, vicdeclong, vicdeclat, vicaht);
                }
            }

            private void WriteGEInter(DataRow oDR, string slinkname, string santname, double dlongl, double dlatl, double saltl, double dlongr, double dlatr, double saltr)
            {
                double ptlong = dlongl + (dlongr - dlongl) / 4.0;
                double ptlat = dlatl + (dlatr - dlatl) / 4.0;
                double ptalt = saltl + (saltr - saltl) / 4.0;

                sw.WriteLine("<Placemark>");
                sw.WriteLine("<name>" + slinkname + "</name>");
                sw.WriteLine("<description>" + HtmlDescTT(oDR, dlongl, dlatl, dlongr, dlatr) + "</description>");
                sw.WriteLine("<styleUrl>#red</styleUrl>");
                sw.WriteLine("<MultiGeometry>");
                sw.WriteLine("<Point>");
                sw.WriteLine("<altitudeMode>absolute</altitudeMode>");
                sw.WriteLine("<coordinates>" + ptlong.ToString(format6) + "," + ptlat.ToString(format6) + "," + ptalt.ToString(format2) + "</coordinates>");
                sw.WriteLine("</Point>");
                sw.WriteLine("<LineString>");
                sw.WriteLine("<altitudeMode>absolute</altitudeMode>");
                sw.WriteLine("<coordinates>");
                sw.WriteLine(dlongl.ToString() + "," + dlatl.ToString() + "," + saltl.ToString());
                sw.WriteLine(dlongr.ToString() + "," + dlatr.ToString() + "," + saltr.ToString());
                sw.WriteLine("</coordinates>");
                sw.WriteLine("</LineString>");
                sw.WriteLine("</MultiGeometry>");
                sw.WriteLine("</Placemark>");
                sw.Flush();
            }

            private void WriteGELinkTT(string slinkname, double dlongl, double dlatl, double saltl, double dlongr, double dlatr, double saltr)
            {
                double ptlong = dlongl + (dlongr - dlongl) / 2.0;
                double ptlat = dlatl + (dlatr - dlatl) / 2.0;
                double ptalt = saltl + (saltr - saltl) / 2.0;

                sw.WriteLine("<Placemark>");
                sw.WriteLine("<name></name>");
                sw.WriteLine("<description>" + slinkname + "</description>");
                sw.WriteLine("<styleUrl>#green</styleUrl>");
                sw.WriteLine("<MultiGeometry>");
                sw.WriteLine("<Point>");
                sw.WriteLine("<altitudeMode>absolute</altitudeMode>");
                sw.WriteLine("<coordinates>" + ptlong.ToString(format6) + "," + ptlat.ToString(format6) + "," + ptalt.ToString(format2) + "</coordinates>");
                sw.WriteLine("</Point>");
                sw.WriteLine("<LineString>");
                sw.WriteLine("<altitudeMode>absolute</altitudeMode>");
                sw.WriteLine("<coordinates>");
                sw.WriteLine(dlongl.ToString(format6) + "," + dlatl.ToString(format6) + "," + saltl.ToString(format2));
                sw.WriteLine(dlongr.ToString(format6) + "," + dlatr.ToString(format6) + "," + saltr.ToString(format2));
                sw.WriteLine("</coordinates>");
                sw.WriteLine("</LineString>");
                sw.WriteLine("</MultiGeometry>");
                sw.WriteLine("</Placemark>");
                sw.Flush();
            }

            private string HtmlDescTT(DataRow oDR, double dlongl, double dlatl, double dlongr, double dlatr)
            {
                StringBuilder htmldes = new StringBuilder("<![CDATA[", 1000);
                htmldes.Append("<table border=\"1\">");
                htmldes.Append("<tr>");
                htmldes.Append("<td></td>");
                htmldes.Append("<td>Interferer</td><td>Victim</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Call1-call2</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["intcall1"]) + "-" + Convert.ToString(oDR["intcall2"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["viccall1"]) + "-" + Convert.ToString(oDR["viccall2"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Name1-name2</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["intname1"]) + "-" + Convert.ToString(oDR["intname2"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["vicname1"]) + "-" + Convert.ToString(oDR["vicname2"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td></td>");
                htmldes.Append("<td colspan=\"2\" align=\"center\">" + Convert.ToString(oDR["intcall1"]) + "-" + Convert.ToString(oDR["viccall1"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Operator</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["intoper"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["vicoper"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Latitude</td>");
                htmldes.Append("<td>" + dlatl.ToString(format6) + "</td>");
                htmldes.Append("<td>" + dlatr.ToString(format6) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Longitude</td>");
                htmldes.Append("<td>" + dlongl.ToString(format6) + "</td>");
                htmldes.Append("<td>" + dlongr.ToString(format6) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Ground (m)</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["intgrnd"]).ToString(format2) + "</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["vicgrnd"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Frequency</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["intfreqtx"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["vicfreqrx"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Polarity</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["intpolar"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["vicpolar"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Power (dBm)</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["intpwrtx"]).ToString(format2) + "</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["vicpwrrx"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Ant Code</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["intacode"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["vicacode"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Ant Height (m)</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["intaht"]).ToString(format2) + "</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["vicaht"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Distance (km)</td>");
                htmldes.Append("<td colspan=\"2\" align=\"center\">" + Convert.ToDouble(oDR["int1vic1dist"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Off Axis Angle</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["intoffantax"]).ToString(format2) + "</td>");
                htmldes.Append("<td>" + Convert.ToDouble(oDR["vicoffantax"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Eqpt Code</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["inteqpttx"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["viceqptrx"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Traf Code</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["inttraftx"]) + "</td>");
                htmldes.Append("<td>" + Convert.ToString(oDR["victrafrx"]) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("<tr>");
                htmldes.Append("<td>Interfering Margin</td>");
                htmldes.Append("<td colspan=\"2\" align=\"center\">" + Convert.ToDouble(oDR["resti"]).ToString(format2) + "</td>");
                htmldes.Append("</tr>");
                htmldes.Append("</table>");
                htmldes.Append("]]>");
                return htmldes.ToString();
            }

            private void WriteTTSiteInfo(string pdfnameArg, string chantableArg, Int32 caseno)
            {
                string ftsiteTable = schema + ".ft_" + pdfnameArg + "_site";
                string mtsiteTable = "main.mt_site";

                dbconnect oCn = new dbconnect();
                string casewhere = "0";
                if (caseno == 0)
                    casewhere = "> 0";
                else
                    casewhere = "=" + caseno.ToString();

                string strSql = @"SELECT DISTINCT intcall1 FROM " + chantableArg +
                            " WHERE caseno " + casewhere +
                            " UNION " +
                            "SELECT intcall2 FROM " + chantableArg +
                            " WHERE caseno " + casewhere +
                            " UNION " +
                            "SELECT viccall1 FROM " + chantableArg +
                            " WHERE caseno " + casewhere +
                            " UNION " +
                            "SELECT viccall2 FROM " + chantableArg +
                            " WHERE caseno " + casewhere;

                DataTable oDT = null;
                try
                {
                    oDT = oCn.retrieve(strSql);
                    oCn.dbdisconnect();
                }
                catch (Exception)
                {
                    oCn.dbdisconnect();
                    return;
                }

                using (OdbcConnection ucn1 = new OdbcConnection(cnstr))
                {
                    ucn1.Open();
                    foreach (DataRow oDR1 in oDT.Rows)
                    {
                        string lcall1 = Convert.ToString(oDR1["intcall1"]);
                        strSql = @"SELECT RTRIM(name) as name, latit, longit, grnd FROM " + ftsiteTable +
                            " WHERE call1 = '" + lcall1 + "'" +
                            " UNION " +
                            "SELECT RTRIM(name), latit, longit, grnd FROM " + mtsiteTable +
                            " WHERE call1 = '" + lcall1 + "'";

                        using (OdbcCommand select3 = new OdbcCommand(strSql, ucn1))
                        using (OdbcDataReader dr3 = select3.ExecuteReader())
                        {
                            if (dr3.HasRows)
                            {
                                dr3.Read();
                                double dlat = Convert.ToDouble(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr3, 1)));
                                double dlong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr3, 2)));
                                double dalt = Convert.ToDouble(DBUtils.GetDBFloat(dr3, 3, 1));
                                WriteSitePoint(lcall1, DBUtils.GetDBString(dr3, 0), dlong, dlat, dalt);
                            }
                        }
                    }
                }
            }

            private void WriteTTLinkInfo(string pdfnameArg, string antetableArg, string chantableArg)
            {
                string ftsiteTable = schema + ".ft_" + pdfnameArg + "_site";
                string ftanteTable = schema + ".ft_" + pdfnameArg + "_ante";
                string ftchanTable = schema + ".ft_" + pdfnameArg + "_chan";

                string rcall1 = "";
                double rdlat = 0;
                double rdlong = 0;
                double rdsalt = 0;
                double rdaalt = 0;
                string ranum = "";

                string lcall1 = "";
                double ldlat = 0;
                double ldlong = 0;
                double ldsalt = 0;
                double ldaalt = 0;
                string lanum = "";

                DataView TTvicview = new DataView(tsipDataTT);
                DataTable TTvictim = TTvicview.ToTable(true, "viccall1", "vicanum", "viccall2", "vicfreqrx", "vicname1", "viclatit", "viclongit", "vicgrnd", "vicaht");

                foreach (DataRow oDR2 in TTvictim.Rows)
                {
                    // W1-4: reset remote end each row; skip green link if remote lookup misses.
                    rdlat = 0;
                    rdlong = 0;
                    rdsalt = 0;
                    rdaalt = 0;
                    ranum = "";
                    bool haveRemote = false;

                    lcall1 = Convert.ToString(oDR2["viccall1"]);
                    lanum = Convert.ToString(oDR2["vicanum"]);
                    rcall1 = Convert.ToString(oDR2["viccall2"]);

                    ldlat = Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oDR2["viclatit"])));
                    ldlong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oDR2["viclongit"])));
                    ldsalt = Convert.ToDouble(oDR2["vicgrnd"]);
                    ldaalt = Convert.ToDouble(oDR2["vicaht"]);

                    string strSql = @"SELECT DISTINCT ms.name, ms.latit, ms.longit, ms.grnd, mc.antnumbtx1, ma.aht FROM main.mt_chan mc " +
                            "INNER JOIN main.mt_ante ma ON ma.call1 = mc.call1 AND ma.call2 = mc.call2 " +
                            "AND ma.bndcde = mc.bndcde AND ma.anum = mc.antnumbtx1 " +
                            "INNER JOIN main.mt_site ms ON ms.call1 = mc.call1 " +
                            "WHERE mc.call1='" + rcall1 + "' AND mc.call2='" + lcall1 + "' " +
                            "AND mc.freqtx=" + Convert.ToString(oDR2["vicfreqrx"]) +
                            "UNION " +
                            "SELECT fs.name, fs.latit, fs.longit, fs.grnd, fc.antnumbtx1, fa.aht FROM " + ftchanTable + " fc " +
                            "INNER JOIN " + ftanteTable + " fa ON fa.call1 = fc.call1 AND fa.call2 = fc.call2 " +
                            "AND fa.bndcde = fc.bndcde AND fa.anum = fc.antnumbtx1 " +
                            "INNER JOIN " + ftsiteTable + " fs ON fs.call1 = fc.call1 " +
                            "WHERE fc.call1='" + rcall1 + "' AND fc.call2='" + lcall1 + "' " +
                            "AND fc.freqtx=" + Convert.ToString(oDR2["vicfreqrx"]);
                    try
                    {
                        using (OdbcConnection ucn2 = new OdbcConnection(cnstr))
                        {
                            ucn2.Open();
                            using (OdbcCommand select1 = new OdbcCommand(strSql, ucn2))
                            using (OdbcDataReader dr1 = select1.ExecuteReader())
                            {
                                if (dr1.HasRows)
                                {
                                    dr1.Read();
                                    rdlat = Convert.ToDouble(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr1, 1)));
                                    rdlong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr1, 2)));
                                    rdsalt = Convert.ToDouble(DBUtils.GetDBFloat(dr1, 3, 1));
                                    ranum = Convert.ToString(dr1.GetValue(4));
                                    rdaalt = Convert.ToDouble(DBUtils.GetDBFloat(dr1, 5, 2));
                                    haveRemote = true;
                                }
                            }
                        }
                    }
                    catch (Exception ee)
                    {
                        ErrorUtils.NotifySystemOps(ee, "WriteLinkInfo3");
                    }

                    if (!haveRemote)
                        continue;

                    string linkname = rcall1 + "#" + ranum + "-" + lcall1 + "#" + lanum;
                    WriteGELinkTT(linkname, rdlong, rdlat, rdsalt + rdaalt, ldlong, ldlat, ldsalt + ldaalt);
                }

                rcall1 = "";
                rdlat = 0;
                rdlong = 0;
                rdsalt = 0;
                rdaalt = 0;
                ranum = "";
                lcall1 = "";
                ldlat = 0;
                ldlong = 0;
                ldsalt = 0;
                ldaalt = 0;
                lanum = "";

                DataView TTintview = new DataView(tsipDataTT);
                DataTable TTintterf = TTintview.ToTable(true, "intcall1", "intanum", "intcall2", "intfreqtx", "intname1", "intlatit", "intlongit", "intgrnd", "intaht");

                foreach (DataRow oDR2 in TTintterf.Rows)
                {
                    // W1-4: reset remote end each row; skip green link if remote lookup misses.
                    rdlat = 0;
                    rdlong = 0;
                    rdsalt = 0;
                    rdaalt = 0;
                    ranum = "";
                    bool haveRemote = false;

                    lcall1 = Convert.ToString(oDR2["intcall1"]);
                    lanum = Convert.ToString(oDR2["intanum"]);
                    rcall1 = Convert.ToString(oDR2["intcall2"]);

                    ldlat = Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oDR2["intlatit"])));
                    ldlong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(Convert.ToString(oDR2["intlongit"])));
                    ldsalt = Convert.ToDouble(oDR2["intgrnd"]);
                    ldaalt = Convert.ToDouble(oDR2["intaht"]);

                    string strSql = @"SELECT DISTINCT ms.name, ms.latit, ms.longit, ms.grnd, mc.antnumbtx1, ma.aht FROM main.mt_chan mc " +
                            "INNER JOIN main.mt_ante ma ON ma.call1 = mc.call1 AND ma.call2 = mc.call2 " +
                            "AND ma.bndcde = mc.bndcde AND ma.anum = mc.antnumbtx1 " +
                            "INNER JOIN main.mt_site ms ON ms.call1 = mc.call1 " +
                            "WHERE mc.call1='" + rcall1 + "' AND mc.call2='" + lcall1 + "' " +
                            "AND mc.freqrx=" + Convert.ToString(oDR2["intfreqtx"]) +
                            "UNION " +
                            "SELECT fs.name, fs.latit, fs.longit, fs.grnd, fc.antnumbtx1, fa.aht FROM " + ftchanTable + " fc " +
                            "INNER JOIN " + ftanteTable + " fa ON fa.call1 = fc.call1 AND fa.call2 = fc.call2 " +
                            "AND fa.bndcde = fc.bndcde AND fa.anum = fc.antnumbtx1 " +
                            "INNER JOIN " + ftsiteTable + " fs ON fs.call1 = fc.call1 " +
                            "WHERE fc.call1='" + rcall1 + "' AND fc.call2='" + lcall1 + "' " +
                            "AND fc.freqrx=" + Convert.ToString(oDR2["intfreqtx"]);
                    try
                    {
                        using (OdbcConnection ucn3 = new OdbcConnection(cnstr))
                        {
                            ucn3.Open();
                            using (OdbcCommand select2 = new OdbcCommand(strSql, ucn3))
                            using (OdbcDataReader dr2 = select2.ExecuteReader())
                            {
                                if (dr2.HasRows)
                                {
                                    dr2.Read();
                                    rdlat = Convert.ToDouble(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr2, 1)));
                                    rdlong = -1.0 * Convert.ToDouble(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr2, 2)));
                                    rdsalt = Convert.ToDouble(DBUtils.GetDBFloat(dr2, 3, 1));
                                    ranum = Convert.ToString(dr2.GetValue(4));
                                    rdaalt = Convert.ToDouble(DBUtils.GetDBFloat(dr2, 5, 2));
                                    haveRemote = true;
                                }
                            }
                        }
                    }
                    catch (Exception ee)
                    {
                        ErrorUtils.NotifySystemOps(ee, "WriteLinkInfo3");
                    }

                    if (!haveRemote)
                        continue;

                    string linkname = rcall1 + "#" + ranum + "-" + lcall1 + "#" + lanum;
                    WriteGELinkTT(linkname, rdlong, rdlat, rdsalt + rdaalt, ldlong, ldlat, ldsalt + ldaalt);
                }
            }

            private bool MailReports(string repType, string inttype, string tsip, string reportlist, out string error)
            {
                error = "";
                string email = LookupEmail(ctx);
                if (string.IsNullOrEmpty(email))
                {
                    error = "You do not have an e-mail address set up in the Mics database. Please contact FCSA to have one added.";
                    return false;
                }

                MailMessage RepsMsg = new MailMessage();
                try
                {
                    RepsMsg.To.Add(new MailAddress(email));
                    RepsMsg.From = new MailAddress("mics@fcsa.ca");

                    StringBuilder KMLText = new StringBuilder("", 1000);
                    if (inttype == "TE")
                    {
                        if (repType == "G")
                        {
                            KMLText.Append("Attached please find the combined KML file for terrestrial interference from TSIP run " + tsip);
                            RepsMsg.Subject = "TE combined KML file for TSIP run " + tsip;
                        }
                        else
                        {
                            KMLText.Append("Attached please find separate KML file(s) for terrestrial interference from TSIP run " + tsip);
                            RepsMsg.Subject = "TE separate KML file(s) for TSIP run " + tsip;
                        }
                    }
                    else if (inttype == "ET")
                    {
                        if (repType == "G")
                        {
                            KMLText.Append("Attached please find the combined KML file for earth station interference from TSIP run " + tsip);
                            RepsMsg.Subject = "ET combined KML file for TSIP run " + tsip;
                        }
                        else
                        {
                            KMLText.Append("Attached please find separate KML file(s) for earth station interference from TSIP run " + tsip);
                            RepsMsg.Subject = "ET separate KML file(s) for TSIP run " + tsip;
                        }
                    }
                    else
                    {
                        if (repType == "G")
                        {
                            KMLText.Append("Attached please find the combined KML file from TSIP run " + tsip);
                            RepsMsg.Subject = " TT combined KML file for TSIP run " + tsip;
                        }
                        else
                        {
                            KMLText.Append("Attached please find separate KML file(s) from TSIP run " + tsip);
                            RepsMsg.Subject = " TT separate KML file(s) for TSIP run " + tsip;
                        }
                    }

                    RepsMsg.Body = KMLText.ToString();
                    char[] delimiter = ";".ToCharArray();
                    string[] flist = reportlist.Split(delimiter);
                    for (int i = 0; i < flist.Length - 1; i++)
                    {
                        Attachment reportfile = new Attachment(userDir + flist[i]);
                        RepsMsg.Attachments.Add(reportfile);
                    }

                    if (!SesUtils.send_email_message2(RepsMsg, 0, false))
                    {
                        error = "System error sending email";
                        return false;
                    }
                    return true;
                }
                catch (Exception ea)
                {
                    error = "ERROR:" + ea.Message;
                    return false;
                }
                finally
                {
                    RepsMsg.Dispose();
                }
            }

            private static string LookupEmail(HttpContext context)
            {
                string ultrixid = context.Session["s_schema"].ToString();
                string micsid = context.Session["s_user"].ToString();
                string sourceTable = "adm.account_details";
                string site = "";
                if (context.Session["SiteName"] != null) site = context.Session["SiteName"].ToString();
                else if (context.Session["siteName"] != null) site = context.Session["siteName"].ToString();
                if (site.IndexOf("remicsdev", StringComparison.OrdinalIgnoreCase) >= 0
                    || site.IndexOf("micstest", StringComparison.OrdinalIgnoreCase) >= 0)
                    sourceTable = "adm.pcn_account_details";

                string cnstrLocal = context.Session["s_cnString"].ToString();
                try
                {
                    using (OdbcConnection cn = new OdbcConnection(cnstrLocal))
                    {
                        cn.Open();
                        string sql = "SELECT email FROM " + sourceTable +
                            " WHERE ultrixid = '" + Esc(ultrixid) + "' AND micsid = '" + Esc(micsid) + "'";
                        using (OdbcCommand cmd = new OdbcCommand(sql, cn))
                        {
                            object o = cmd.ExecuteScalar();
                            if (o != null && o != DBNull.Value)
                            {
                                string em = o.ToString().Trim();
                                if (em.Length > 0) return em;
                            }
                        }
                        sql = "SELECT email FROM dbo.t_UserDetails " +
                            "WHERE RTRIM(micsId) = '" + Esc(micsid) + "' AND RTRIM(IsActiveYN) = 'Y'";
                        using (OdbcCommand cmd = new OdbcCommand(sql, cn))
                        {
                            object o = cmd.ExecuteScalar();
                            if (o != null && o != DBNull.Value)
                            {
                                string em = o.ToString().Trim();
                                if (em.Length > 0) return em;
                            }
                        }
                    }
                }
                catch
                {
                    return "";
                }
                return "";
            }

            private static string Esc(string s)
            {
                return (s ?? "").Replace("'", "''");
            }

            private static string ConvertStrAmp(string instring)
            {
                if (instring == null) return "";
                return instring.Replace("&", "&amp;");
            }
        }
    }
}
