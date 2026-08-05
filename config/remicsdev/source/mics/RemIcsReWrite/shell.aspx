<%@ Page Language="C#" AutoEventWireup="true" CodeBehind="shell.aspx.cs" Inherits="mics.RemIcsReWrite_shell" %>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MICS — RemIcsReWrite</title>
  <link rel="icon" href="../favicon.ico" type="image/x-icon">
  <link href="../styleSheets/main.css" type="text/css" rel="stylesheet">
  <link href="assets/remics-shell.css" type="text/css" rel="stylesheet">
</head>
<body class="remics-shell">
  <header class="remics-topbar">
    <div class="remics-brand">
      <img src="../images/Image4.gif" alt="" width="48" height="52">
      <span class="remics-title">Frequency Coordination System Association</span>
    </div>
    <div class="remics-topbar-meta">
      <label class="remics-project-label" for="project-select">Project Code</label>
      <select id="project-select" class="remics-project-select" aria-label="Project code"></select>
      <label class="remics-project-label" for="active-type">Active File</label>
      <input type="text" id="active-type" class="iro remics-active-type" readonly size="4" value="">
      <input type="text" id="active-file" class="iro remics-active-file" readonly size="16" value="">
      <span id="user-badge" class="remics-user-badge"></span>
      <a href="../logoff.aspx?reason=1" class="remics-link">Log off</a>
      <a href="/admin/" class="remics-link">FCSA Testing</a>
    </div>
  </header>
  <div class="remics-layout">
    <div class="remics-nav-panel">
      <div class="remics-nav-header">
        <span id="nav-login-name" class="remics-nav-login"></span>
        <span id="nav-db-name" class="remics-nav-db"></span>
        <a href="../logoff.aspx?reason=1" class="remics-nav-logoff">Log Off</a>
      </div>
      <nav class="remics-nav" id="remics-nav" aria-label="Main navigation"></nav>
    </div>
    <main class="remics-main" id="remics-main">
  <div id="error-banner" class="remics-error-banner" hidden role="alert"></div>
      <div id="view-host" class="remics-view-host"></div>
    </main>
  </div>
  <div class="remics-diag-backdrop" id="diag-backdrop" hidden></div>
  <aside class="remics-diag-drawer" id="diag-drawer" hidden>
    <header class="remics-diag-header">
      <strong>Diagnostics</strong>
      <button type="button" id="diag-close" class="remics-btn-secondary">Close</button>
      <button type="button" id="diag-copy" class="remics-btn-secondary">Copy</button>
    </header>
    <pre id="diag-body" class="remics-diag-body"></pre>
  </aside>
  <button type="button" id="diag-toggle" class="remics-diag-toggle" title="Session &amp; API diagnostics">Diag</button>
  <script>
    window.REMICS_SHELL = {
      user: "<%= JsUser %>",
      schema: "<%= JsSchema %>",
      project: "<%= JsProject %>"
    };
  </script>
  <script src="remics-api.js"></script>
  <script src="js/remics-tsip-api.js"></script>
  <script src="js/remics-tsip-validation.js"></script>
  <script src="js/distsubs.js"></script>
  <script src="js/remics-nav-data.js"></script>
  <script src="js/remics-nav.js"></script>
  <script src="js/remics-tree.js"></script>
  <script src="js/remics-sdf-tree.js"></script>
  <script src="js/remics-ts.js"></script>
  <script src="js/remics-tsip.js"></script>
  <script src="js/remics-pdf-fields.js"></script>
  <script src="js/remics-pdf.js"></script>
  <script src="js/remics-ds.js"></script>
  <script src="js/remics-phase675.js"></script>
  <script src="js/remics-app.js"></script>
</body>
</html>
