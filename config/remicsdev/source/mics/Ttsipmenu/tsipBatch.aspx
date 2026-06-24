<%@ Page language="c#" Codebehind="tsipBatch.aspx.cs" AutoEventWireup="True" Inherits="Ttsipmenu.tsipBatch" %>
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN" >
<html>
	<head>
		<title>tsipBatch</title>
		<meta name="GENERATOR" content="Microsoft Visual Studio .NET 7.1"/>
		<meta name="CODE_LANGUAGE" content="C#"/>
		<meta name="vs_defaultClientScript" content="JavaScript"/>
		<meta name="vs_targetSchema" content="http://schemas.microsoft.com/intellisense/ie5"/>
		<link rel="stylesheet" type="text/css" href="../styleSheets/main.css"/>
		<!-- #include File="../includeFiles/HeaderC.js" -->
		<!-- #include File ="../includeFiles/TgoBack.js"-->
	</head>

<script type="text/javascript" src="<%=ResolveUrl("~/micsjquery.js")%>"></script>
<script type="text/javascript" src="../includeFiles/Tutils.js"></script>
<script type="text/javascript">
<!--
function pageLoad()
{
	if(document.frmRight.txtErrorMsg.value != "")
	{
		alert(document.frmRight.txtErrorMsg.value);
		document.frmRight.txtErrorMsg.value = "";
		window.status="Please correct errors and click Save or click Cancel";
	}
	else
	{
		window.status="Confirm or Cancel TSIP Batch Submission";
    }
    m0.style.display = "";
}
	function batchcheck() {
        var parameter = new String(document.frmRight.txtParameter.value);
        document.frmRight.cmdRunTsip.disabled = true;

        window.status = "Please Wait... Submitting Batch TSIP for " + document.frmRight.txtParameter.value;
        wsUrl = document.frmRight.sesSiteName.value + "Ttsipmenu/TwsTsip.asmx/tsipValidateAll";
		params = "{'tsipparmname':'" + parameter + "'}";
        callajaxchrome(wsUrl, params).then(function (data, status, req) {
            var response = jQuery.parseJSON(req.responseText);
            batchcheckdone(response.d);
        });
	}
	function batchcheckdone(retval) {
		if (retval == "") {
			batch();
		}
		else {
			errorlines = retval.split("^");	// split retval into separate lines on '^'
			for (i = 0; i < errorlines.length; i++) {
				// split each line into fields
				lineparts = errorlines[i].split(",");
				str = "Run Number: " + lineparts[0] + " File: " + lineparts[1]; 
				if (lineparts[2] == 1) {
                    str = str + " has been deleted";
				}
				else {
                    str = str + " must be re-validated";
				}
				alert(str);
			}
			alert("Tsip submission cancelled"); 
        }
    }
function batch() 
{
	var parameter = new String(document.frmRight.txtParameter.value);
	document.frmRight.cmdRunTsip.disabled = true;

	window.status = "Please Wait... Submitting Batch TSIP for " +  document.frmRight.txtParameter.value;
	wsUrl = document.frmRight.sesSiteName.value + "Ttsipmenu/TwsTsip.asmx/tsipRun";
	params = "{'parmfile':'" + parameter + "'}";
	callajaxchrome(wsUrl, params).then(function (data, status, req) {
        var response = jQuery.parseJSON(req.responseText);
        batchDone(response.d);
	});
}
function batchDone(response) 
{
	var parameter = new String(document.frmRight.txtParameter.value);
	if (response.indexOf("OK:0") == 0)
	{
		window.status = "Batch submission for parameter file " + parameter + " queued; results will be emailed when complete.";
	}
	else if (response.indexOf("OK:2") == 0) {
	    alert("Batch submission for parameter file " + parameter + " cancelled. Already in queue");
	}
	//else if (response.indexOf("OK:125") == 0) {
	//    alert("Batch submission for parameter file " + parameter + " failed accessing stored procedure");
	//}
	else
	{
	    alert("Batch submission for parameter file " + parameter + " FAILED!!\n ERROR: " + response);
	}
	goBack();
}
	
//-->
</script>
	<body onkeypress="trapEnter()" class="b">
		<h3 align="center">
			FCSA MICS Batch TSIP Parameter
		</h3>
		<div align="center" id="nameHeader" runat="server"></div>
		<form id="frmRight" name="frmRight" method="post">
			<input type="hidden" name="sesSiteName" id="sesSiteName" runat="server"/> <input type="hidden" name="txtParameter" id="txtParameter" runat="server"/>
			<input type="hidden" name="txtErrorMsg" id="txtErrorMsg" runat="server"/>
			<br/>
			<br/>
			<div id="m0">
				<table align="center">
					<tr>
						<td>
							<input type="button" name="cmdRunTsip" class="bt" value="Batch TSIP" onclick="batchcheck()"
								accesskey="B" title="Press ALT + B to Batch TSIP"/>
						</td>
						<td>
							<input type="button" name="cmdBack" class="bt" value="Cancel" onclick="goBack()" accesskey="C"
								title="Press ALT + C to Cancel"/>
						</td>
						<td>
							<input type="button" class="bt" name="cmdHelp" value="Help" onclick="htmlHelp()" accesskey="H"
								title="Press ALT + H for Help"/>
						</td>
					</tr>
				</table>
			</div>
		<br/>
		<table align="center" width="70%" cellpadding="1">
			<tr>
				<td width="20%" valign="top">
					<font color="red">Important Note:</font></td>
				<td width="50%">
					<font color="red">All <b>TSIP Run Name</b>'s in a parameter file are executed each 
						time the <b>Batch TSIP</b> button is clicked.</font>
				</td>
			</tr>
		</table>
		</form>
	</body>
</html>
