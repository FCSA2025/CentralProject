<%@ Page language="c#" Codebehind="luTsipSiteCodesCrit.aspx.cs" AutoEventWireup="True" Inherits="lookuptsip.luTsipSiteCodesCrit" %>
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN" > 

<html>
  <head>
    <title>TSIP Call Signs</title>
    <meta name="GENERATOR" content="Microsoft Visual Studio .NET 7.1"/>
    <meta name="CODE_LANGUAGE" content="C#"/>
    <meta name="vs_defaultClientScript" content="JavaScript"/>
    <meta name="vs_targetSchema" content="http://schemas.microsoft.com/intellisense/ie5"/>
    <script type="text/javascript" src="<%=ResolveUrl("~/micsjquery.js")%>"></script>
    <script type="text/javascript" src="https://code.jquery.com/ui/1.12.1/jquery-ui.js"></script>
    <link rel="stylesheet" href="//code.jquery.com/ui/1.12.1/themes/base/jquery-ui.css"/>
    <link rel="styleSheet" type="text/css" href="../styleSheets/main.css"/>
    <!-- #include File="../includeFiles/HeaderC.js" -->
    <!-- #include File="../lookuptsip/lookuptsip.js" -->
    <script type="text/javascript" src="../RemIcsReWrite/js/remics-tsip-lookup-bridge.js?v=2026081215"></script>
  </head>
  <script type="text/javascript">
        function load() { }
        function getCodes() {
            var text1 = "";
            var text2 = "";
            var type = document.frmRight.txtPdfType.value;
            var eftype = document.frmRight.txtefType.value;
            var efname = document.frmRight.txtefName.value;
            var senvSite = document.frmRight.txtCallCode.value;

            if (type == "T") {
                if (senvSite == "CALL SIGN") {
                    if (document.frmRight.txtCallSignCrit.value == "" && document.frmRight.txtSiteNameCrit.value == "") {
                        alert("You have to provide search criteria " + "\n" +
                            " either for Call Sign or Site Name");
                        document.frmRight.txtCallSignCrit.focus();
                        return;
                    }
                    else {
                        if (document.frmRight.txtCallSignCrit.value != "") {
                            text1 = document.frmRight.txtCallSignCrit.value;
                        }
                        if (document.frmRight.txtSiteNameCrit.value != "") {
                            text2 = document.frmRight.txtSiteNameCrit.value;
                        }
                        if (eftype.indexOf("MDB_ES") >= 0) type = "E";
                        if (eftype.indexOf("PDF_TS") >= 0) type = "FT";
                        if (eftype.indexOf("PDF_ES") >= 0) type = "FE";
                        if (eftype.indexOf("INTRA") >= 0) type = "FT";
                    }
                    var text = type + "^" + efname + "^CALL+SIGN^" + text1.toUpperCase() + "^" + text2.toUpperCase();
                    TsipCodes(text);
                }
            }
            else {
                if (senvSite == "CALL SIGN") {
                    if (document.frmRight.txtCallSignCrit.value == "" && document.frmRight.txtSiteNameCrit.value == "") {
                        alert("You have to provide search criteria " + "\n" +
                            " either for Call Sign or Site Name");
                        document.frmRight.txtCallSignCrit.focus();
                        return;
                    }
                    else {
                        if (document.frmRight.txtCallSignCrit.value != "") {
                            text1 = document.frmRight.txtCallSignCrit.value;
                        }
                        if (document.frmRight.txtSiteNameCrit.value != "") {
                            text2 = document.frmRight.txtSiteNameCrit.value;
                        }
                    }
                    type = "T";
                    if (eftype.indexOf("PDF_TS") >= 0) type = "FT";
                    var text = type + "^" + efname + "^CALL+SIGN^" + text1.toUpperCase() + "^" + text2.toUpperCase();
                    TsipCodes(text);
                }
            }
        }
        function TsipCodes(text) {
            var field1 = "caseCodes";
            window.status = "Loading Tsip Site Codes Lookup";
            var lookupurl = "../lookuptsip/luTsipSiteCodes.aspx?text=" + text;
            LookupDialog1(lookupurl, field1, 30 * 16, 25 * 16, "Select a call sign");
        }
  </script>
  <body class="lu" onload="load()">
    <form name="frmRight" id="frmRight" method="post" runat="server">
      <input type="hidden" name="sesSiteName" id="sesSiteName" runat="server"/>
      <input type="hidden" name="txtErrorMsg" id="txtErrorMsg" runat="server"/>
      <input type="hidden" name="txtDisplayCnt" id="txtDisplayCnt" runat="server"/> 
      <input type="hidden" name="txtType" id="txtType" runat="server"/>
      <input type="hidden" name="txtUser" id="txtUser" runat="server"/>
      <input type="hidden" name="txtPdfType" id="txtPdfType" runat="server"/> 
      <input type="hidden" name="txtefType" id="txtefType" runat="server"/>
      <input type="hidden" name="txtefName" id="txtefName" runat="server"/> 
      <input type="hidden" name="txtCallCode" id="txtCallCode" runat="server"/>
      <h5 align="center">TSIP Call Signs</h5>
      <div id="callsign">
        <table style="WIDTH: 350px; HEIGHT: 30px">
          <tr>
            <td class="p">Call Sign Criteria:</td>
            <td class="p"><input type="text" name="txtCallSignCrit"/></td>
            <td class="p">Site Name Criteria:</td>
            <td class="p"><input type="text" name="txtSiteNameCrit"/></td>
          </tr>
        </table>
      </div>
      <br/>
      <div align="center">
        <input type="button" name="cmdCallCodes" value="Search for Codes" onclick="getCodes()"/>
      </div>
      <div id="aspxdialog" style="display:none"></div>  
    </form>
  </body>
</html>
