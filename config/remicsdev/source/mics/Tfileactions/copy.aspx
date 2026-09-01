<%@ Page Language="C#" AutoEventWireup="true" CodeBehind="copy.aspx.cs" Inherits="Tfileactions.copy" %>

<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN" >
<html>
	<head>
		<title>copy</title>
		<meta name="GENERATOR" content="Microsoft Visual Studio .NET 7.1"/>
		<meta name="CODE_LANGUAGE" content="C#"/>
		<meta name="vs_defaultClientScript" content="JavaScript"/>
		<meta name="vs_targetSchema" content="http://schemas.microsoft.com/intellisense/ie5"/>
		<!-- #include File="../includeFiles/HeaderC.js" -->
		<!-- #include File="../includeFiles/TgoBack.js" -->
		<link rel="stylesheet" type="text/css" href="../styleSheets/main.css"/>
		<script type="text/javascript" src="<%=ResolveUrl("~/micsjquery.js")%>"></script>
        <script type="text/javascript" src="../RemIcsReWrite/remics-api.js"></script>
        <script type="text/javascript" src="../includeFiles/Tutils.js"></script>
        <script type="text/javascript">
        window.COPY_CFG = {
            oldName: "<%= JsOldName %>",
            newName: "<%= JsNewName %>",
            fileType: "<%= JsFileType %>",
            projectCode: "<%= JsProjectCode %>"
        };
        </script>
	</head>
	<body onkeypress="trapEnter()" class="b">
		<div id="wservice" style="behavior:url(webservice.htc)"></div>
		<form name="frmRight" id="frmRight" runat="server">
			<input type="hidden" name="sesSiteName" id="sesSiteName" runat="server"/> 
			<input type="hidden" name="sesDbName" id="sesDbName" runat="server"/>
			<input name="txtOldName" id="txtOldName" type="hidden" runat="server"/> 
			<input name="txtsType" id="txtsType" type="hidden" runat="server"/>
			<input name="txtExists" id="txtExists" type="hidden" runat="server"/> 
			<input name="txtNewName" id="txtNewName" type="hidden" runat="server"/>
			<input id="txtErrorMsg" type="hidden" name="txtErrorMsg" runat="server"/>
			<h3 align="center">
				FCSA MICS Copying File
			</h3>
			<div align="center" id="frmHeader" runat="server">
			</div>
			<table align="center" border="0" cellpadding="1" cellspacing="1" width="70%">
				<tr>
					<td nowrap="nowrap" class="o"></td>
				</tr>
				<tr>
				</tr>
			</table>
			<div align="center"><br/>
				<br/>
				<p>Click CopyTo to proceed with copying this file</p><br/>
				<p>OR</p>
				<p>Click Cancel to return to the tree without copying</p><br/>
				<p></p>
			</div>
			<br/>
			<div id="m0" style="DISPLAY:none" align="center">
				<table align="center">
					<tr>
						<td><input name="cmdCopyTo" type="button" class="bt" value="CopyTo" onclick="checkName()" accesskey="T" title="Press ALT + T to CopyTo"/></td>
						<td><input name="cmdCancel" type="button" class="bt" value="Cancel" onclick="goBack()" accesskey="C" title="Press ALT + C to Cancel"/></td>
						<td><input name="cmdHelp" type="button" class="bt" value="Help" onclick="htmlHelp()" accesskey="H" title="Press ALT + H for Help"/></td>
					</tr>
				</table>
			</div>
			<br/>
			<br/>
			<div id="m1" style="DISPLAY:none" align="center">
				<marquee scrollamount="10" direction="left" behavior="scroll" width="200" height="5">DELETING</marquee>
			</div>
			<br/>
			<div id="m2" style="DISPLAY:none" align="center">
				<marquee scrollamount="10" direction="left" behavior="scroll" width="200" height="5">COPYING</marquee>
			</div>
			<br/>
		</form>
<script type="text/javascript">
$(document).ready(function() {
	if(document.frmRight.txtErrorMsg.value != "")
	{
		alert(document.frmRight.txtErrorMsg.value);
		document.frmRight.txtErrorMsg.value = "";
		window.status="Please correct errors and click Save or click Cancel";
	}
	else 
	{
	    m0.style.display = "";
		window.status="Confirm or Cancel Copy";
	}
	parent.txtInProcess = "f";
});
function checkName() {
	parent.txtInProcess = "t";
	var exists = document.getElementById("txtExists").value;
	//alert("checkName:" + exists);
	
	if (exists == "f")
	{
		copyingFile();
	}
	else
	{
		cancelCopy();
	}
}
function copyingFile()
{//Copy
	m2.style.display = "";
	m0.style.display = "none";
	window.status= "Please Wait...Copying Data File " + document.frmRight.txtOldName.value;
	setTimeout("copyingFile1();", 1);
}
function copyingFile1()
{
	var cfg = window.COPY_CFG || {};
	var newname = cfg.newName || document.frmRight.txtNewName.value;
	var oldname = cfg.oldName || document.frmRight.txtOldName.value;
	var filetype = cfg.fileType || document.frmRight.txtsType.value;
	var projectCode = cfg.projectCode || parent.txtProjectCode;

	RemIcsApi.copyTable(oldname, newname, projectCode, { filetype: filetype })
	    .then(function (r) {
	        if (!r.ok) {
	            m2.style.display = "none";
	            parent.txtInProcess = "f";
	            alert(r.error || r.body || ('Copy failed (HTTP ' + r.status + ')'));
	            return;
	        }
	        copyTableSuccess(r.body);
	    })
	    .catch(function (ex) {
	        m2.style.display = "none";
	        parent.txtInProcess = "f";
	        alert('Copy error: ' + (ex.message || ex));
	    });
}

function copyTableSuccess(result) {
    if (result.toLowerCase().indexOf("timeout") == 0) {
        window.parent.location.href = "../relogin.aspx?reason=0&errcode=&source=ajax-copyTable";
    }

    m2.style.display = "none";
    if(result == "1")
    {
        //alert("copydone" + retobj.value);
        alert("COPY CANCELLED - SESSION HAS TIMED OUT OR DATABASE ERROR");
	    parent.txtInProcess = "f";
	    return;
    }
	else
	{
	    alert("Copy complete");
	    parent.txtName = document.frmRight.txtNewName.value;
		goBack();
	}
}			
function cancelCopy()
{
	var ans = confirm("Are you sure you want to replace all existing information in file " + document.frmRight.txtNewName.value.toUpperCase() + " ?");
	if(ans)
	{
		document.frmRight.cmdCopyTo.disabled = true;
		//if they confirmed YES
		//var pdfType = document.frmRight.txtTableType.value;
		var sType = document.frmRight.txtsType.value;
		window.status="Please Wait...Deleting File  " + document.frmRight.txtNewName.value.toUpperCase();
		m1.style.display = "";
		setTimeout("deleteold();",1);
	}
	else
	{
		//user opted to not overwrite
		 goBack();
	}
}
function deleteold()
{
	var cfg = window.COPY_CFG || {};
	var filename = cfg.newName || document.frmRight.txtNewName.value;
	var filetype = cfg.fileType || document.frmRight.txtsType.value;
	var projectCode = cfg.projectCode || parent.txtProjectCode;
	
	RemIcsApi.killTable(filename, projectCode, { filetype: filetype })
	    .then(function (r) {
	        if (!r.ok) {
	            m1.style.display = "none";
	            parent.txtInProcess = "f";
	            alert(r.error || r.body || ('Delete failed (HTTP ' + r.status + ')'));
	            return;
	        }
	        killTableSuccess(r.body);
	    });
}

function killTableSuccess(result) {
    if (result.toLowerCase().indexOf("timeout") == 0) {
        window.parent.location.href = "../relogin.aspx?reason=0&errcode=&source=ajax-killTable";
    }

    m1.style.display = "none";
    // delete complete - proceed with copy
    copyingFile();
}
</script>
</body>
</html>
