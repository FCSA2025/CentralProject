using System;
using System.Collections.Generic;
using System.Data.Odbc;
using System.IO;
using System.Text;
using System.Web;
using DBUtilities;
using ErrorUtilities;
using LongLatUtilities;

namespace RemIcsReWrite
{
    public class CaseDetCsvResult
    {
        public bool ok;
        public string error;
        public string message;
        public List<string> files;

        public CaseDetCsvResult()
        {
            files = new List<string>();
        }
    }

    /// <summary>
    /// CASEDET CSV generators ported from Ttsipmenu CASEDETTSEScsv / CASEDETTSTScsv.
    /// Writes te_{tsip}.csv / et_{tsip}.csv (TSES) or tt_{tsip}.csv (TSTS) under Session["user_dir"].
    /// </summary>
    public static class CaseDetCsv
    {
        public static CaseDetCsvResult Generate(HttpContext ctx, string mode, string pdf, string tsip, string protype)
        {
            CaseDetCsvResult result = new CaseDetCsvResult();
            try
            {
                if (ctx == null || ctx.Session == null
                    || ctx.Session["s_cnString"] == null
                    || ctx.Session["s_schema"] == null
                    || ctx.Session["user_dir"] == null)
                {
                    result.ok = false;
                    result.error = "Session not initialized.";
                    return result;
                }

                string cnstr;
                try
                {
                    cnstr = ctx.Session["s_cnString"].ToString();
                }
                catch (Exception)
                {
                    result.ok = false;
                    result.error = "Session not initialized.";
                    return result;
                }

                string schema = ctx.Session["s_schema"].ToString();
                string userDir = ctx.Session["user_dir"].ToString();
                string modeKey = (mode ?? "").Trim().ToUpperInvariant();
                string pdfname = pdf ?? "";
                string tsipname = tsip ?? "";
                string ptype = protype ?? "";

                if (modeKey == "TSES")
                    return new TsesGen(ctx, cnstr, schema, userDir, pdfname, tsipname, ptype).Run();
                if (modeKey == "TSTS")
                    return new TstsGen(cnstr, schema, userDir, pdfname, tsipname).Run();

                result.ok = false;
                result.error = "mode must be TSES or TSTS";
                return result;
            }
            catch (Exception ex)
            {
                result.ok = false;
                result.error = ex.Message;
                return result;
            }
        }

        private static string SqlError(string strSql, Exception ex)
        {
            // W3-6: never return SQL text or exception detail to the client.
            try { ErrorUtils.NotifySystemOps(ex, "CaseDetCsv"); } catch { }
            return "A database error occurred while building the CASEDET CSV report.";
        }

        /// <summary>TS-ES CASEDET CSV  -  CASEDETTSEScsv.aspx.cs</summary>
        private class TsesGen
        {
            private readonly HttpContext ctx;
            private readonly string cnstr;
            private string schema;
            private readonly string userDir;
            private readonly string pdfname;
            private readonly string tsipname;
            private readonly string protype;
            private readonly string sitetable;
            private readonly string antetable;
            private readonly string chantable;
            private string tsiprepname;
            private StringBuilder sbSql;
            private StringBuilder wl;
            private StreamWriter sw;
            private string sqlError;
            private readonly List<string> files = new List<string>();

            private string terrcall1;
            private string terrcall2;
            private string terrbndcde;
            private string terranum;
            private string terrlatit2;
            private string terrlongit2;
            private string terrgrnd2;
            private string terranum2;
            private string terracode2;
            private string terrht2;

            public TsesGen(HttpContext ctx, string cnstr, string schema, string userDir,
                string pdfname, string tsipname, string protype)
            {
                this.ctx = ctx;
                this.cnstr = cnstr;
                this.schema = schema;
                this.userDir = userDir;
                this.pdfname = pdfname;
                this.tsipname = tsipname;
                this.protype = protype;
                sitetable = schema + ".te_" + tsipname + "_site";
                antetable = schema + ".te_" + tsipname + "_ante";
                chantable = schema + ".te_" + tsipname + "_chan";
                tsiprepname = "te_" + tsipname + ".csv";
            }

            public CaseDetCsvResult Run()
            {
                CaseDetCsvResult result = new CaseDetCsvResult();
                buildsql_sel();

                StringBuilder sbSqlw1 = new StringBuilder("", 1000);
                sbSqlw1.Append(" FROM " + chantable + " c, " + antetable + " a, " + sitetable + " s");
                sbSqlw1.Append(" WHERE a.interferer=c.interferer");
                sbSqlw1.Append(" and a.terrcall1=c.terrcall1 and a.terrcall2=c.terrcall2");
                sbSqlw1.Append(" and a.earthlocation=c.earthlocation and a.earthcall1=c.earthcall1");
                sbSqlw1.Append(" and a.terrbndcde=c.terrbndcde and a.terranum=c.terranum");
                sbSqlw1.Append(" and s.terrcall1=c.terrcall1 and s.terrcall2=c.terrcall2");
                sbSqlw1.Append(" and s.earthlocation=c.earthlocation");
                sbSqlw1.Append(" and c.tereport > 0");

                StringBuilder sbSqlw2 = new StringBuilder("", 1000);
                sbSqlw2.Append(" FROM " + chantable + " c, " + antetable + " a, " + sitetable + " s");
                sbSqlw2.Append(" WHERE a.interferer=c.interferer");
                sbSqlw2.Append(" and a.terrcall1=c.terrcall1 and a.terrcall2=c.terrcall2");
                sbSqlw2.Append(" and a.earthlocation=c.earthlocation and a.earthcall1=c.earthcall1");
                sbSqlw2.Append(" and a.terrbndcde=c.terrbndcde and a.terranum=c.terranum");
                sbSqlw2.Append(" and s.terrcall1=c.terrcall1 and s.terrcall2=c.terrcall2");
                sbSqlw2.Append(" and s.earthlocation=c.earthlocation");
                sbSqlw2.Append(" and c.etreport > 0");

                do_report(sbSql.ToString() + sbSqlw1.ToString());
                tsiprepname = "et_" + tsipname + ".csv";
                do_report(sbSql.ToString() + sbSqlw2.ToString());

                result.files.AddRange(files);
                if (!string.IsNullOrEmpty(sqlError))
                {
                    result.ok = false;
                    result.error = sqlError;
                    return result;
                }
                if (files.Count == 0)
                {
                    result.ok = false;
                    result.error = "No reports were created for run " + tsipname.Replace("_", " - ");
                    return result;
                }
                result.ok = true;
                result.message = files.Count == 1
                    ? ("Created " + files[0])
                    : ("Created " + string.Join(", ", files.ToArray()));
                return result;
            }

            private void do_report(string strSql)
            {
                OdbcConnection cn = new OdbcConnection(cnstr);
                cn.Open();
                OdbcCommand select3 = new OdbcCommand(strSql);
                select3.Connection = cn;
                OdbcDataReader dr3 = null;
                try
                {
                    try
                    {
                        dr3 = select3.ExecuteReader();
                    }
                    catch (Exception e3)
                    {
                        sqlError = SqlError(strSql, e3);
                        return;
                    }

                    if (dr3.HasRows)
                    {
                        writeheader(tsiprepname);
                        try
                        {
                            while (dr3.Read())
                            {
                                wl = new StringBuilder("", 1000);

                                terrcall1 = DBUtils.GetDBString(dr3, 0);
                                terrcall2 = DBUtils.GetDBString(dr3, 1);
                                terrbndcde = DBUtils.GetDBString(dr3, 35);
                                terranum = DBUtils.GetDBInt16(dr3, 36);

                                if (protype == "T")
                                    get_terrinfo_ft(pdfname);
                                else
                                    get_terrinfo_mt();

                                wl.Append(DBUtils.GetDBString(dr3, 0) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 1) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 2) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 3) + ",");

                                wl.Append(DBUtils.GetDBString(dr3, 4) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 5) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 6) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 7) + ",");

                                wl.Append(DBUtils.GetDBString(dr3, 8) + ",");
                                wl.Append(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr3, 9)) + ",");
                                wl.Append(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr3, 10)) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 11, 1) + ",");

                                wl.Append(terrlatit2 + ",");
                                wl.Append(terrlongit2 + ",");
                                wl.Append(terrgrnd2 + ",");

                                wl.Append(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr3, 12)) + ",");
                                wl.Append(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr3, 13)) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 14, 1) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 15) + ",");

                                wl.Append(DBUtils.GetDBInt16(dr3, 16) + ",");
                                wl.Append(DBUtils.GetDBInt16(dr3, 17) + ",");
                                wl.Append(DBUtils.GetDBInt16(dr3, 18) + ",");

                                wl.Append(DBUtils.GetDBInt32(dr3, 19) + ",");
                                wl.Append(DBUtils.GetDBInt32(dr3, 20) + ",");
                                wl.Append(DBUtils.GetDBInt32(dr3, 21) + ",");
                                wl.Append(DBUtils.GetDBInt32(dr3, 22) + ",");

                                wl.Append(DBUtils.GetDBString(dr3, 23) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 24, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 25, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 26, 2) + ",");

                                wl.Append(DBUtils.GetDBDouble(dr3, 27, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 28, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 29, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 30, 2) + ",");

                                wl.Append(DBUtils.GetDBDouble(dr3, 31, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 32, 2) + ",");
                                wl.Append(DBUtils.GetDBInt32(dr3, 33) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 34) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 35) + ",");
                                wl.Append(DBUtils.GetDBInt16(dr3, 36) + ",");

                                wl.Append(terranum2 + ",");

                                wl.Append(DBUtils.GetDBString(dr3, 37) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 38) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 39) + ",");

                                wl.Append(terracode2 + ",");

                                wl.Append(DBUtils.GetDBString(dr3, 40) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 41) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 42) + ",");

                                wl.Append(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr3, 43)) + ",");
                                wl.Append(DBUtils.GetDBFloat(dr3, 44, 2) + ",");
                                wl.Append(DBUtils.GetDBFloat(dr3, 45, 2) + ",");
                                wl.Append(DBUtils.GetDBFloat(dr3, 46, 2) + ",");

                                wl.Append(DBUtils.GetDBFloat(dr3, 47, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 48, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 49, 2) + ",");
                                wl.Append(DBUtils.GetDBInt16(dr3, 50) + ",");

                                wl.Append(DBUtils.GetDBInt16(dr3, 51) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 52) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 53, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 54, 2) + ",");

                                wl.Append(DBUtils.GetDBDouble(dr3, 55, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 56, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 57, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 58, 2) + ",");

                                wl.Append(DBUtils.GetDBDouble(dr3, 59, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 60, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 61, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 62, 2) + ",");

                                wl.Append(DBUtils.GetDBDouble(dr3, 63, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 64, 2) + ",");

                                wl.Append(terrht2 + ",");

                                wl.Append(DBUtils.GetDBDouble(dr3, 65, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 66, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 67, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 68, 2) + ",");

                                wl.Append(DBUtils.GetDBDouble(dr3, 69, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 70, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 71, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 72, 2) + ",");

                                wl.Append(DBUtils.GetDBDouble(dr3, 73, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 74, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 75, 2) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 76) + ",");

                                wl.Append(DBUtils.GetDBDouble(dr3, 77, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 78, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 79, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 80, 2) + ",");

                                wl.Append(DBUtils.GetDBString(dr3, 81) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 82, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 83, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 84, 2) + ",");

                                wl.Append(DBUtils.GetDBString(dr3, 85) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 86) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 87, 2) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 88) + ",");

                                wl.Append(DBUtils.GetDBString(dr3, 89) + ",");
                                wl.Append(DBUtils.GetDBInt32(dr3, 90) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 91) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 92) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 93) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 94) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 95) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 96) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 97, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 98, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 99, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 100, 1) + ",");

                                wl.Append(DBUtils.GetDBDouble(dr3, 101, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 102, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 103, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 104, 1) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 105) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 106) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 107, 1) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 108) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 109) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 110) + ",");

                                wl.Append(DBUtils.GetDBString(dr3, 111) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 112, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 113, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 114, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 115, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 116, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 117, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 118, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 119, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 120, 1) + ",");

                                wl.Append(DBUtils.GetDBDouble(dr3, 121, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 122, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 123, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 124, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 125, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 126, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 127, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 128, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 129, 1) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 130) + ",");

                                wl.Append(DBUtils.GetDBDouble(dr3, 131, 1) + ",");
                                wl.Append(DBUtils.GetDBInt32(dr3, 132) + ",");
                                wl.Append(DBUtils.GetDBInt16(dr3, 133) + ",");

                                sw.WriteLine(wl.ToString());
                            }
                        }
                        finally
                        {
                            if (sw != null)
                            {
                                sw.Close();
                                sw = null;
                            }
                        }
                    }
                }
                finally
                {
                    if (dr3 != null)
                        dr3.Close();
                    cn.Close();
                }
            }

            private void buildsql_sel()
            {
                sbSql = new StringBuilder("SELECT ", 1000);

                sbSql.Append("s.terrcall1,s.terrcall2,s.earthlocation,s.terrname1,");
                sbSql.Append("s.terrname2,s.earthname,s.terroper,s.terroper2,");
                sbSql.Append("s.earthoper,s.terrlatit,s.terrlongit,s.terrgrnd,");

                sbSql.Append("s.earthlatit,s.earthlongit,s.earthgrnd,s.radiozone,");
                sbSql.Append("s.rainzone,s.etreport,s.tereport,");
                sbSql.Append("s.etcaseno,s.tecaseno,s.etsubcases,s.tesubcases,");
                sbSql.Append("s.intreq,s.etdist,s.etazim,s.teazim,");
                sbSql.Append("s.tudist,s.tuazim,s.utazim,s.eudist,");
                sbSql.Append("s.euazim,s.ueazim,s.processed as sprocessed,");

                sbSql.Append("a.interferer,a.terrbndcde,a.terranum,");

                sbSql.Append("a.earthcall1,a.earthband,a.terracode,");

                sbSql.Append("a.earthacode,a.satname,a.satoper,a.satlongit,");
                sbSql.Append("a.txpre,a.txtro,a.rxpre,a.rxtro,");
                sbSql.Append("a.sarc1,a.sarc2,a.mode1,a.mode2,");
                sbSql.Append("a.intause,a.esazim,a.eselev,a.teelev,");
                sbSql.Append("a.etelev,a.tuelev,a.utelev,a.euelev,");
                sbSql.Append("a.ediscang,a.tdiscang,a.adisc_set,a.adisc_ute,");
                sbSql.Append("a.terrht,");

                sbSql.Append("a.earthht,a.tvazim,a.evazim,a.tvelev,");
                sbSql.Append("a.evelev,a.tvdistes,a.tvdisttu,a.evdistes,");
                sbSql.Append("a.evdisttu,a.angleutv,a.anglesev,a.tsoffaxis,");
                sbSql.Append("a.tstrueaz,a.tstrueel,a.angleute,a.angleuta,");
                sbSql.Append("a.angleeta,a.angleatv,a.adisc_atv,a.terragain,");
                sbSql.Append("a.terramodel,a.terraxref,a.earthagain,a.earthamodel,");
                sbSql.Append("a.earthaxref,a.processed as aprocessed,");

                sbSql.Append("c.terrchid,c.earthchid,c.inttraftx,c.victrafrx,");
                sbSql.Append("c.inteqpttx,c.viceqptrx,c.intfreqtx,c.inttxpwr,");
                sbSql.Append("c.inttxpwr2,c.inttxafls,c.inttxafls2,c.vicrxafls,");
                sbSql.Append("c.vicfreqrx,c.vicpwrrx,c.stattx,c.statrx,");
                sbSql.Append("c.energy,c.ctxinttraftx,c.ctxvictrafrx,c.ctxeqpt,");
                sbSql.Append("c.calctype,c.earthmdsc,c.terrmdsc,c.eartheirp,");
                sbSql.Append("c.terreirp,c.freqsep,c.scang,c.loss20mode1,");
                sbSql.Append("c.calci20mode1,c.loss01mode1,c.calci01mode1,c.loss01mode2,");
                sbSql.Append("c.calci01mode2,c.reqd20mode1,c.reqd01mode1,c.reqd01mode2,");
                sbSql.Append("c.marg20mode1,c.marg01mode1,c.marg01mode2,c.remterracode,");
                sbSql.Append("c.remterragain,c.processed as cprocessed,c.terrant");
            }

            private bool get_terrinfo_ft(string pdfnameArg)
            {
                schema = ctx.Session["s_schema"].ToString();
                string siteTable = schema + ".ft_" + pdfnameArg + "_site";
                string anteTable = schema + ".ft_" + pdfnameArg + "_ante";

                string strSql = "SELECT s.latit, s.longit, s.grnd, a.anum, a.acode, a.aht " +
                    "FROM " + siteTable + " s, " + anteTable + " a" +
                    " WHERE s.call1 = a.call1" +
                    " AND a.call1 = '" + terrcall2 + "'" +
                    " AND a.call2 = '" + terrcall1 + "'" +
                    " AND a.bndcde = '" + terrbndcde + "'" +
                    " AND a.anum = " + terranum;

                return get_terrinfo(strSql);
            }

            private bool get_terrinfo_mt()
            {
                string strSql = "SELECT s.latit, s.longit, s.grnd, a.anum, a.acode, a.aht " +
                    "FROM main.mt_site s, main.mt_ante a" +
                    " WHERE s.call1 = a.call1" +
                    " AND a.call1 = '" + terrcall2 + "'" +
                    " AND a.call2 = '" + terrcall1 + "'" +
                    " AND a.bndcde = '" + terrbndcde + "'" +
                    " AND a.anum = " + terranum;

                return get_terrinfo(strSql);
            }

            private bool get_terrinfo(string strSql)
            {
                // W1-3: reset secondary terr fields every call so a miss does not reuse the prior row.
                terrlatit2 = "";
                terrlongit2 = "";
                terrgrnd2 = "";
                terranum2 = "";
                terracode2 = "";
                terrht2 = "";

                OdbcConnection cn1 = new OdbcConnection(cnstr);
                cn1.Open();
                OdbcCommand select1 = new OdbcCommand(strSql);
                select1.Connection = cn1;
                OdbcDataReader dr1 = null;
                try
                {
                    dr1 = select1.ExecuteReader();
                }
                catch (Exception e1)
                {
                    cn1.Close();
                    sqlError = SqlError(strSql, e1);
                    return false;
                }

                if (dr1.HasRows)
                {
                    dr1.Read();
                    terrlatit2 = LongLatUtils.decdeg(DBUtils.GetDBInt32(dr1, 0));
                    terrlongit2 = LongLatUtils.decdeg(DBUtils.GetDBInt32(dr1, 1));
                    terrgrnd2 = DBUtils.GetDBFloat(dr1, 2, 1);
                    terranum2 = DBUtils.GetDBInt16(dr1, 3);
                    terracode2 = DBUtils.GetDBString(dr1, 4);
                    terrht2 = DBUtils.GetDBFloat(dr1, 5, 1);
                }
                dr1.Close();
                cn1.Close();
                return true;
            }

            private void writeheader(string inname)
            {
                string tsipcsv = userDir + inname;
                sw = new StreamWriter(tsipcsv, false);
                files.Add(inname);

                sw.WriteLine("terrcall1,terrcall2,earthlocation,terrname1," +
                    "terrname2,earthname,terroper,terroper2," +
                    "earthoper,terrlatit,terrlongit,terrgrnd," +
                    "terrlatit2,terrlongit2,terrgrnd2," +
                    "earthlatit,earthlongit,earthgrnd,radiozone," +
                    "rainzone,etreport,tereport," +
                    "etcaseno,tecaseno,etsubcases,tesubcases," +
                    "intreq,etdist,etazim,teazim," +
                    "tudist,tuazim,utazim,eudist," +
                    "euazim,ueazim,processed," +
                    "interferer,terrbndcde,terranum,terranum2," +
                    "earthcall1,earthband,terracode,terracode2," +
                    "earthacode,satname,satoper,satlongit," +
                    "txpre,txtro,rxpre,rxtro," +
                    "sarc1,sarc2,mode1,mode2," +
                    "intause,esazim,eselev,teelev," +
                    "etelev,tuelev,utelev,euelev," +
                    "ediscang,tdiscang,adisc_set,adisc_ute," +
                    "terrht,terrht2," +
                    "earthht,tvazim,evazim,tvelev," +
                    "evelev,tvdistes,tvdisttu,evdistes," +
                    "evdisttu,angleutv,anglesev,tsoffaxis," +
                    "tstrueaz,tstrueel,angleute,angleuta," +
                    "angleeta,angleatv,adisc_atv,terragain," +
                    "terramodel,terraxref,earthagain,earthamodel," +
                    "earthaxref,aprocessed," +
                    "terrchid,earthchid,inttraftx,victrafrx," +
                    "inteqpttx,viceqptrx,intfreqtx,inttxpwr," +
                    "inttxpwr2,inttxafls,inttxafls2,vicrxafls," +
                    "vicfreqrx,vicpwrrx,stattx,statrx," +
                    "energy,ctxinttraftx,ctxvictrafrx,ctxeqpt," +
                    "calctype,earthmdsc,terrmdsc,eartheirp," +
                    "terreirp,freqsep,scang,loss20mode1," +
                    "calci20mode1,loss01mode1,calci01mode1,loss01mode2," +
                    "calci01mode2,reqd20mode1,reqd01mode1,reqd01mode2," +
                    "marg20mode1,marg01mode1,marg01mode2,remterracode," +
                    "remterragain,cprocessed,terrant");
            }
        }

        /// <summary>TS-TS CASEDET CSV  -  CASEDETTSTScsv.aspx.cs</summary>
        private class TstsGen
        {
            private readonly string cnstr;
            private readonly string schema;
            private readonly string userDir;
            private readonly string pdfname;
            private readonly string tsipname;
            private StringBuilder wl;
            private StreamWriter swout;
            private string sqlError;
            private readonly List<string> files = new List<string>();

            public TstsGen(string cnstr, string schema, string userDir,
                string pdfname, string tsipname)
            {
                this.cnstr = cnstr;
                this.schema = schema;
                this.userDir = userDir;
                this.pdfname = pdfname;
                this.tsipname = tsipname;
            }

            public CaseDetCsvResult Run()
            {
                CaseDetCsvResult result = new CaseDetCsvResult();
                string sitetable = schema + ".tt_" + tsipname + "_site";
                string antetable = schema + ".tt_" + tsipname + "_ante";
                string chantable = schema + ".tt_" + tsipname + "_chan";
                string tsiprepname = "tt_" + tsipname + ".csv";

                OdbcConnection cn = new OdbcConnection(cnstr);
                cn.Open();

                StringBuilder sbSql = new StringBuilder("SELECT ", 1000);

                sbSql.Append("s.interferer, ");
                sbSql.Append("s.intcall1, s.intcall2, s.viccall1, s.viccall2, ");
                sbSql.Append("s.intname1, s.intname2, s.vicname1, s.vicname2, ");
                sbSql.Append("s.intoper, s.vicoper, s.intoper2, s.vicoper2, ");
                sbSql.Append("s.intlatit, s.intlongit, s.intgrnd, ");
                sbSql.Append("a.intaht, ");
                sbSql.Append("s.viclatit, s.viclongit, s.vicgrnd, ");
                sbSql.Append("a.vicaht, ");
                sbSql.Append("s.report, s.caseno, s.subcases, ");
                sbSql.Append("s.int1int2dist, s.vic1vic2dist, s.int1vic1dist, ");
                sbSql.Append("s.intoffax, s.vicoffax, s.processed as sprocessed, ");
                sbSql.Append("a.intbndcde, a.intanum, a.vicbndcde, a.vicanum, ");
                sbSql.Append("a.intacode, a.vicacode, a.report as areport, a.subcaseno, ");
                sbSql.Append("a.adiscctxh, a.adiscctxv, a.adisccrxh, a.adisccrxv, ");
                sbSql.Append("a.adiscxtxh, a.adiscxtxv, a.adiscxrxh, a.adiscxrxv, ");
                sbSql.Append("a.intause, a.vicause, a.intgain, a.vicgain, ");
                sbSql.Append("a.intaxref, a.intamodel, a.vicaxref, a.vicamodel, ");
                sbSql.Append("a.processed as aprocessed, ");
                sbSql.Append("c.intchid, c.vicchid, c.intpolar, c.vicpolar, ");
                sbSql.Append("c.inttraftx, c.victrafrx, c.intstattx, c.vicstatrx, ");
                sbSql.Append("c.inteqpttx, c.viceqptrx, c.intfreqtx, c.vicfreqrx, ");
                sbSql.Append("c.intpwrtx, c.vicpwrrx, c.intafsltx, c.vicafslrx, ");
                sbSql.Append("c.rxant, c.txant, c.ctxinttraftx, c.ctxvictrafrx, ");
                sbSql.Append("c.ctxeqpt, c.calctype, c.report as creport, ");
                sbSql.Append("c.totantdisc, c.tiltdisc, c.freqsep, c.reqdcalc, ");
                sbSql.Append("c.patloss, c.calcico, c.calcixp, c.resti, ");
                sbSql.Append("c.pathloss80, c.calcico80, c.calcixp80, c.reqd80, c.resti80, ");
                sbSql.Append("c.pathloss99, c.calcico99, c.calcixp99, c.reqd99, c.resti99, ");
                sbSql.Append("c.processed as cprocessed");
                sbSql.Append(" FROM " + chantable + " c, " + antetable + " a, " + sitetable + " s ");
                sbSql.Append(" WHERE a.interferer=c.interferer");
                sbSql.Append(" and a.intcall1=c.intcall1 and a.intcall2=c.intcall2");
                sbSql.Append(" and a.viccall1=c.viccall1 and a.viccall2=c.viccall2");
                sbSql.Append(" and a.intbndcde=c.intbndcde and a.intanum=c.intanum");
                sbSql.Append(" and a.vicbndcde=c.vicbndcde and a.vicanum=c.vicanum");
                sbSql.Append(" and s.interferer=c.interferer");
                sbSql.Append(" and s.intcall1=c.intcall1 and s.intcall2=c.intcall2");
                sbSql.Append(" and s.viccall1=c.viccall1 and s.viccall2=c.viccall2");
                sbSql.Append(" and s.caseno > 0");

                string strSql = sbSql.ToString();
                OdbcCommand select3 = new OdbcCommand(strSql);
                select3.Connection = cn;
                OdbcDataReader dr3 = null;
                try
                {
                    try
                    {
                        dr3 = select3.ExecuteReader();
                    }
                    catch (Exception e3)
                    {
                        result.ok = false;
                        result.error = SqlError(strSql, e3);
                        return result;
                    }

                    if (dr3.HasRows)
                    {
                        writeheader(tsiprepname);
                        try
                        {
                            while (dr3.Read())
                            {
                                wl = new StringBuilder("", 1000);

                                string interferer = DBUtils.GetDBString(dr3, 0);
                                string intcall1 = DBUtils.GetDBString(dr3, 1);
                                string intcall2 = DBUtils.GetDBString(dr3, 2);
                                string viccall2 = DBUtils.GetDBString(dr3, 4);
                                string bndcde = DBUtils.GetDBString(dr3, 30);
                                string intanum = DBUtils.GetDBInt16(dr3, 31);
                                string vicanum = DBUtils.GetDBInt16(dr3, 33);
                                string intacode = DBUtils.GetDBString(dr3, 34);
                                string vicacode = DBUtils.GetDBString(dr3, 35);
                                string chid = DBUtils.GetDBString(dr3, 55);

                                wl.Append(DBUtils.GetDBString(dr3, 0) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 1) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 2) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 3) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 4) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 5) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 6) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 7) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 8) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 9) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 10) + ",");

                                wl.Append(DBUtils.GetDBString(dr3, 11) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 12) + ",");
                                wl.Append(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr3, 13)) + ",");
                                wl.Append(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr3, 14)) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 15, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 16, 1) + ",");

                                switch (interferer)
                                {
                                    case "E":
                                        if (!get_antepos_mt(intcall2, bndcde, intanum))
                                        {
                                            result.ok = false;
                                            result.error = sqlError;
                                            result.files.AddRange(files);
                                            return result;
                                        }
                                        break;
                                    case "P":
                                        if (!get_antepos_ft(pdfname, intcall2, bndcde, intanum))
                                        {
                                            result.ok = false;
                                            result.error = sqlError;
                                            result.files.AddRange(files);
                                            return result;
                                        }
                                        break;
                                    default:
                                        break;
                                }

                                wl.Append(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr3, 17)) + ",");
                                wl.Append(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr3, 18)) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 19, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 20, 1) + ",");

                                switch (interferer)
                                {
                                    case "P":
                                        if (!get_antepos_mt(viccall2, bndcde, vicanum))
                                        {
                                            result.ok = false;
                                            result.error = sqlError;
                                            result.files.AddRange(files);
                                            return result;
                                        }
                                        break;
                                    case "E":
                                        if (!get_antepos_ft(pdfname, viccall2, bndcde, vicanum))
                                        {
                                            result.ok = false;
                                            result.error = sqlError;
                                            result.files.AddRange(files);
                                            return result;
                                        }
                                        break;
                                    default:
                                        break;
                                }

                                wl.Append(DBUtils.GetDBInt16(dr3, 21) + ",");
                                wl.Append(DBUtils.GetDBInt32(dr3, 22) + ",");

                                wl.Append(DBUtils.GetDBInt32(dr3, 23) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 24, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 25, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 26, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 27, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 28, 2) + ",");
                                wl.Append(DBUtils.GetDBInt32(dr3, 29) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 30) + ",");
                                wl.Append(DBUtils.GetDBInt16(dr3, 31) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 32) + ",");

                                wl.Append(DBUtils.GetDBInt16(dr3, 33) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 34) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 35) + ",");
                                wl.Append(DBUtils.GetDBInt16(dr3, 36) + ",");
                                wl.Append(DBUtils.GetDBInt32(dr3, 37) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 38, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 39, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 40, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 41, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 42, 2) + ",");

                                wl.Append(DBUtils.GetDBDouble(dr3, 43, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 44, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 45, 2) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 46) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 47) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 48, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 49, 2) + ",");

                                if (!get_antexrefmodel_mt(intacode, vicacode))
                                {
                                    result.ok = false;
                                    result.error = sqlError;
                                    result.files.AddRange(files);
                                    return result;
                                }

                                wl.Append(DBUtils.GetDBInt32(dr3, 54) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 55) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 56) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 57) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 58) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 59) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 60) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 61) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 62) + ",");

                                wl.Append(DBUtils.GetDBString(dr3, 63) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 64) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 65, 5) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 66, 5) + ",");

                                switch (interferer)
                                {
                                    case "P":
                                        if (!get_chanfreq_ft(pdfname, intcall1, intcall2, bndcde, chid, "r"))
                                        {
                                            result.ok = false;
                                            result.error = sqlError;
                                            result.files.AddRange(files);
                                            return result;
                                        }
                                        break;
                                    case "E":
                                        if (!get_chanfreq_mt(intcall1, intcall2, bndcde, chid, "r"))
                                        {
                                            result.ok = false;
                                            result.error = sqlError;
                                            result.files.AddRange(files);
                                            return result;
                                        }
                                        break;
                                    default:
                                        break;
                                }

                                switch (interferer)
                                {
                                    case "P":
                                        if (!get_chanfreq_ft(pdfname, intcall1, intcall2, bndcde, chid, "t"))
                                        {
                                            result.ok = false;
                                            result.error = sqlError;
                                            result.files.AddRange(files);
                                            return result;
                                        }
                                        break;
                                    case "E":
                                        if (!get_chanfreq_mt(intcall1, intcall2, bndcde, chid, "t"))
                                        {
                                            result.ok = false;
                                            result.error = sqlError;
                                            result.files.AddRange(files);
                                            return result;
                                        }
                                        break;
                                    default:
                                        break;
                                }

                                wl.Append(DBUtils.GetDBDouble(dr3, 67, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 68, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 69, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 70, 1) + ",");

                                wl.Append(DBUtils.GetDBInt16(dr3, 71) + ",");
                                wl.Append(DBUtils.GetDBInt16(dr3, 72) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 73) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 74) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 75) + ",");
                                wl.Append(DBUtils.GetDBString(dr3, 76) + ",");
                                wl.Append(DBUtils.GetDBInt16(dr3, 77) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 78, 2) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 79, 2) + ",");

                                wl.Append(DBUtils.GetDBDouble(dr3, 80, 3) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 81, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 82, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 83, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 84, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 85, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 86, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 87, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 88, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 89, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 90, 1) + ",");

                                wl.Append(DBUtils.GetDBDouble(dr3, 91, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 92, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 93, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 94, 1) + ",");
                                wl.Append(DBUtils.GetDBDouble(dr3, 95, 1) + ",");
                                wl.Append(DBUtils.GetDBInt32(dr3, 96));

                                swout.WriteLine(wl.ToString());
                            }
                        }
                        finally
                        {
                            if (swout != null)
                            {
                                swout.Close();
                                swout = null;
                            }
                        }
                    }
                    else
                    {
                        result.ok = false;
                        result.error = "The selected run was empty";
                        return result;
                    }
                }
                finally
                {
                    if (swout != null)
                    {
                        swout.Close();
                        swout = null;
                    }
                    if (dr3 != null)
                        dr3.Close();
                    cn.Close();
                }

                if (!string.IsNullOrEmpty(sqlError))
                {
                    result.ok = false;
                    result.error = sqlError;
                    result.files.AddRange(files);
                    return result;
                }
                if (files.Count == 0)
                {
                    result.ok = false;
                    result.error = "The selected run was empty";
                    return result;
                }
                result.ok = true;
                result.files.AddRange(files);
                result.message = "Created " + files[0];
                return result;
            }

            private bool get_antepos_ft(string pdfnameArg, string incall, string inbndcde, string inanum)
            {
                string siteTable = schema + ".ft_" + pdfnameArg + "_site";
                string anteTable = schema + ".ft_" + pdfnameArg + "_ante";

                string strSql = "SELECT latit, longit, grnd FROM " + siteTable +
                    " WHERE call1 = '" + incall + "'";

                OdbcConnection cn1 = new OdbcConnection(cnstr);
                cn1.Open();
                OdbcCommand select1 = new OdbcCommand(strSql);
                select1.Connection = cn1;
                OdbcDataReader dr1 = null;
                try
                {
                    dr1 = select1.ExecuteReader();
                }
                catch (Exception e1)
                {
                    cn1.Close();
                    sqlError = SqlError(strSql, e1);
                    return false;
                }

                if (dr1.HasRows)
                {
                    dr1.Read();
                    wl.Append(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr1, 0)) + ",");
                    wl.Append(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr1, 1)) + ",");
                    wl.Append(DBUtils.GetDBFloat(dr1, 2, 1) + ",");
                }
                else
                {
                    // W1-2: keep CSV column alignment when site lookup misses.
                    wl.Append(",,,");
                }
                dr1.Close();

                strSql = "SELECT aht FROM " + anteTable +
                    " WHERE call1 = '" + incall + "'" +
                    " AND bndcde = '" + inbndcde + "'" +
                    " AND anum = " + inanum;

                select1 = new OdbcCommand(strSql);
                select1.Connection = cn1;
                try
                {
                    dr1 = select1.ExecuteReader();
                }
                catch (Exception e1)
                {
                    cn1.Close();
                    sqlError = SqlError(strSql, e1);
                    return false;
                }

                if (dr1.HasRows)
                {
                    dr1.Read();
                    wl.Append(DBUtils.GetDBFloat(dr1, 0, 1) + ",");
                }
                else
                {
                    wl.Append(",");
                }
                dr1.Close();
                cn1.Close();
                return true;
            }

            private bool get_antepos_mt(string incall, string inbndcde, string inanum)
            {
                string strSql = "SELECT latit, longit, grnd FROM main.mt_site " +
                    " WHERE call1 = '" + incall + "'";

                OdbcConnection cn2 = new OdbcConnection(cnstr);
                cn2.Open();
                OdbcCommand select2 = new OdbcCommand(strSql);
                select2.Connection = cn2;
                OdbcDataReader dr2 = null;
                try
                {
                    dr2 = select2.ExecuteReader();
                }
                catch (Exception e2)
                {
                    cn2.Close();
                    sqlError = SqlError(strSql, e2);
                    return false;
                }

                if (dr2.HasRows)
                {
                    dr2.Read();
                    wl.Append(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr2, 0)) + ",");
                    wl.Append(LongLatUtils.decdeg(DBUtils.GetDBInt32(dr2, 1)) + ",");
                    wl.Append(DBUtils.GetDBFloat(dr2, 2, 1) + ",");
                }
                else
                {
                    // W1-2: keep CSV column alignment when site lookup misses.
                    wl.Append(",,,");
                }
                dr2.Close();

                strSql = "SELECT aht FROM main.mt_ante " +
                    " WHERE call1 = '" + incall + "'" +
                    " AND bndcde = '" + inbndcde + "'" +
                    " AND anum = " + inanum;

                select2 = new OdbcCommand(strSql);
                select2.Connection = cn2;
                try
                {
                    dr2 = select2.ExecuteReader();
                }
                catch (Exception e2)
                {
                    cn2.Close();
                    sqlError = SqlError(strSql, e2);
                    return false;
                }

                if (dr2.HasRows)
                {
                    dr2.Read();
                    wl.Append(DBUtils.GetDBFloat(dr2, 0, 1) + ",");
                }
                else
                {
                    wl.Append(",");
                }
                dr2.Close();
                cn2.Close();
                return true;
            }

            private bool get_antexrefmodel_mt(string intacode, string vicacode)
            {
                string strSql = "SELECT axref, amodel FROM main.sd_ante " +
                    " WHERE acode = '" + intacode + "'";

                OdbcConnection cn2 = new OdbcConnection(cnstr);
                cn2.Open();
                OdbcCommand select2 = new OdbcCommand(strSql);
                select2.Connection = cn2;
                OdbcDataReader dr2 = null;
                try
                {
                    dr2 = select2.ExecuteReader();
                }
                catch (Exception e2)
                {
                    cn2.Close();
                    sqlError = SqlError(strSql, e2);
                    return false;
                }

                if (dr2.HasRows)
                {
                    dr2.Read();
                    wl.Append(DBUtils.GetDBString(dr2, 0) + ",");
                    wl.Append(DBUtils.GetDBString(dr2, 1) + ",");
                }
                dr2.Close();

                strSql = "SELECT axref, amodel FROM main.sd_ante " +
                    " WHERE acode = '" + vicacode + "'";

                select2 = new OdbcCommand(strSql);
                select2.Connection = cn2;
                try
                {
                    dr2 = select2.ExecuteReader();
                }
                catch (Exception e2)
                {
                    cn2.Close();
                    sqlError = SqlError(strSql, e2);
                    return false;
                }

                if (dr2.HasRows)
                {
                    dr2.Read();
                    wl.Append(DBUtils.GetDBString(dr2, 0) + ",");
                    wl.Append(DBUtils.GetDBString(dr2, 1) + ",");
                }
                dr2.Close();
                cn2.Close();
                return true;
            }

            private bool get_chanfreq_ft(string pdfnameArg, string incall1, string incall2, string inbndcde, string inchid, string txrx)
            {
                string chanTable = schema + ".ft_" + pdfnameArg + "_chan";
                string strSql = "SELECT freqtx, freqrx FROM " + chanTable +
                    " WHERE call1 = '" + incall1 + "'" +
                    " AND call2 = '" + incall2 + "'" +
                    " AND bndcde = '" + inbndcde + "'" +
                    " AND chid = '" + inchid + "'";

                OdbcConnection cn1 = new OdbcConnection(cnstr);
                cn1.Open();
                OdbcCommand select1 = new OdbcCommand(strSql);
                select1.Connection = cn1;
                OdbcDataReader dr1 = null;
                try
                {
                    dr1 = select1.ExecuteReader();
                }
                catch (Exception e1)
                {
                    cn1.Close();
                    sqlError = SqlError(strSql, e1);
                    return false;
                }

                if (dr1.HasRows)
                {
                    dr1.Read();
                    if (txrx == "t")
                        wl.Append(DBUtils.GetDBDouble(dr1, 0, 5) + ",");
                    else
                        wl.Append(DBUtils.GetDBDouble(dr1, 1, 5) + ",");
                }
                dr1.Close();
                cn1.Close();
                return true;
            }

            private bool get_chanfreq_mt(string incall1, string incall2, string inbndcde, string inchid, string txrx)
            {
                string strSql = "SELECT freqtx, freqrx FROM main.mt_chan " +
                    " WHERE call1 = '" + incall1 + "'" +
                    " AND call2 = '" + incall2 + "'" +
                    " AND bndcde = '" + inbndcde + "'" +
                    " AND chid = '" + inchid + "'";

                OdbcConnection cn2 = new OdbcConnection(cnstr);
                cn2.Open();
                OdbcCommand select2 = new OdbcCommand(strSql);
                select2.Connection = cn2;
                OdbcDataReader dr2 = null;
                try
                {
                    dr2 = select2.ExecuteReader();
                }
                catch (Exception e2)
                {
                    cn2.Close();
                    sqlError = SqlError(strSql, e2);
                    return false;
                }

                if (dr2.HasRows)
                {
                    dr2.Read();
                    if (txrx == "t")
                        wl.Append(DBUtils.GetDBDouble(dr2, 0, 5) + ",");
                    else
                        wl.Append(DBUtils.GetDBDouble(dr2, 1, 5) + ",");
                }
                dr2.Close();
                cn2.Close();
                return true;
            }

            private void writeheader(string inname)
            {
                string tsipcsv = userDir + inname;
                swout = new StreamWriter(tsipcsv, false);
                files.Add(inname);

                swout.WriteLine("interferer,intcall1,intcall2,viccall1,viccall2," +
                    "intname1,intname2,vicname1,vicname2,intoper,vicoper," +
                    "intoper2,vicoper2,intlatit,intlongit,intgrnd,intahttx," +
                    "intlatitrx,intlongitrx,intgrndrx,intahtrx," +
                    "viclatit,viclongit,vicgrnd,vicahtrx," +
                    "viclatittx,viclongittx,vicgrndtx,vicahttx," +
                    "sreport,caseno,subcases," +
                    "int1int2dist,vic1vic2dist,int1vic1dist,intoffax,vicoffax,sprocessed," +
                    "intbndcde,intanum,vicbndcde,vicanum,intacode,vicacode,areport," +
                    "subcaseno," +
                    "adiscctxh,adiscctxv,adisccrxh,adisccrxv," +
                    "adiscxtxh,adiscxtxv,adiscxrxh,adiscxrxv," +
                    "intause,vicause,intgain,vicgain," +
                    "intaxref,intamodel,vicaxref,vicamodel," +
                    "aprocessed," +
                    "intchid,vicchid,intpolar,vicpolar," +
                    "inttraftx,victrafrx,intstattx,vicstatrx," +
                    "inteqpttx,viceqptrx,intfreqtx,vicfreqrx," +
                    "intfreqtxr,vicfreqrxr," +
                    "intpwrtx,vicpwrrx,intafsltx,vicafslrx," +
                    "rxant,txant,ctxinttraftx,ctxvictrafrx," +
                    "ctxeqpt,calctype,creport," +
                    "totantdisc,tiltdisc,freqsep,reqdcalc," +
                    "patloss,calcico,calcixp,resti," +
                    "pathloss80,calcico80,calcixp80,reqd80,resti80," +
                    "pathloss99,calcico99,calcixp99,reqd99,resti99," +
                    "cprocessed");
            }
        }
    }
}
