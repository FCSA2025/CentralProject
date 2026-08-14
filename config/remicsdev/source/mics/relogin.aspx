<%@ Page language="c#" Codebehind="relogin.aspx.cs" AutoEventWireup="True" Inherits="mics.relogin" %>
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN" >
<html>
	<head>
		<title>relogin</title>
		<meta content="Microsoft Visual Studio .NET 7.1" name="GENERATOR"/>
		<meta content="C#" name="CODE_LANGUAGE"/>
		<meta content="JavaScript" name="vs_defaultClientScript"/>
		<meta content="http://schemas.microsoft.com/intellisense/ie5" name="vs_targetSchema"/>
       	</head>
		<script type="text/javascript">
<!--
    function exitsite() {
        var reason = document.getElementById("txtReason").value || "0";
        var loginUrl = window.location.protocol + "//" + window.location.host +
            "/mics/RemIcsReWrite/login.aspx?loggedout=1&reason=" + encodeURIComponent(reason);

        // RemIcsReWrite: silent redirect — no alert popups (classic frames still land on login).
        if (window.top && window.top !== window.self) {
            window.top.location.replace(loginUrl);
        } else {
            window.location.replace(loginUrl);
        }
    }
//-->
        </script>

	<body class="b" onload="exitsite()">
    <form id="frmRight" name="frmRight" method="post" runat="server">
        <input id="txtReason" type="hidden" name="txtReason" runat="server" />
        <input id="txtError" type="hidden" name="txtError" runat="server" />
        <input id="txtSource" type="hidden" name="txtSource" runat="server" />
        <input id="txtTarget" type="hidden" name="txtTarget" runat="server" />
        <input id="txtLogin" type="hidden" name="txtLogin" runat="server" />
        <input id="sesSiteName" type="hidden" name="sesSiteName" runat="server" />
    </form>

	</body>
</html>
