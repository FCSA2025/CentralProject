<%@ Page Language="C#" AutoEventWireup="true" CodeBehind="login.aspx.cs" Inherits="mics.RemIcsReWrite_login" %>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Login — CloudMics 2022</title>
  <link href="../styleSheets/login.css" type="text/css" rel="stylesheet">
  <link rel="icon" href="../favicon.ico" type="image/x-icon">
</head>
<body onload="if (window.top !== window.self) { window.top.location = window.location; }">
  <table align="center">
    <tr>
      <td><img hspace="12" src="../images/Image4.gif" alt="" width="241" height="260"></td>
      <td class="o">
        <h1>Frequency<br>Coordination<br>System<br>Association</h1>
      </td>
    </tr>
  </table>
  <br><br>
  <table align="center">
    <tr>
      <td class="o" colspan="2" align="center"><h1>CloudMics 2022 Login</h1></td>
    </tr>
    <tr><td colspan="2">&nbsp;</td></tr>
    <tr>
      <td colspan="2" align="center">
        <%= ErrorHtml %>
        <p id="loggedout-msg" class="info" hidden>Session closed. Please log in again.</p>
        <form method="post" action="login.aspx">
          <table>
            <tr>
              <td class="o">Mics ID:</td>
              <td><input type="text" name="user" value="<%= UserNameValue %>" autocomplete="username"></td>
            </tr>
            <tr>
              <td class="o">Password:</td>
              <td><input type="password" name="password" autocomplete="current-password"></td>
            </tr>
            <tr>
              <td></td>
              <td><input type="submit" value="Log In"></td>
            </tr>
          </table>
        </form>
        <br>
        <div align="center">
          <a href="#" onclick="forgot(); return false;">Forgot your password?</a>
        </div>
        <p><a href="/admin/">Back to FCSA Testing</a></p>
      </td>
    </tr>
  </table>
  <script type="text/javascript">
  if (/[?&]loggedout=1(?:&|$)/.test(location.search)) {
    var el = document.getElementById('loggedout-msg');
    if (el) {
      el.hidden = false;
      var reason = (location.search.match(/[?&]reason=([^&]+)/) || [])[1] || '';
      if (reason === '0') el.textContent = 'Your session timed out. Please log in again.';
      else if (reason === '2') el.textContent = 'Your session was closed due to a system error. Please log in again.';
      else if (reason === '3') el.textContent = 'Unable to connect to the database. Please log in again.';
      else el.textContent = 'Session closed. Please log in again.';
    }
  }
  function forgot() {
    var fusername = document.getElementsByName('user')[0];
    if (!fusername || fusername.value === '') {
      alert('You must enter a Mics ID');
      return;
    }
    var url = 'pwd-reset.aspx?id=' + encodeURIComponent(fusername.value);
    window.open(url, 'wReset', 'status=no,top=200,left=200,width=800,height=280,scrollbars=yes');
  }
  </script>
</body>
</html>
