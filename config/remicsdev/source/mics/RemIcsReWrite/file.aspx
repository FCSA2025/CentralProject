<%@ Page Language="C#" AutoEventWireup="true" CodeBehind="file.aspx.cs" Inherits="mics.RemIcsReWrite_file" %>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>RemIcsReWrite — TS File</title>
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 2rem; background: #f4f6fb; color: #1a1a2e; }
    h1 { color: #0c1566; }
    .meta, .diag, .actions, .result { background: #fff; border: 1px solid #dde2ef; border-radius: 8px; padding: 1rem; margin: 1rem 0; }
    .diag dt, .result dt { font-weight: 600; margin-top: 0.35rem; }
    .diag dd, .result dd { margin: 0.1rem 0 0 0; font-family: Consolas, monospace; font-size: 0.9rem; }
    button { margin: 0.25rem 0.5rem 0.25rem 0; padding: 0.55rem 1rem; font: inherit; font-weight: 600; background: #121f91; color: #fff; border: 0; border-radius: 4px; cursor: pointer; }
    button.secondary { background: transparent; color: #121f91; border: 1px solid #121f91; }
    button:disabled { opacity: 0.6; cursor: wait; }
    .toolbar a { margin-right: 1rem; color: #121f91; }
    input[type=file] { font: inherit; }
    label.chk { font-weight: normal; margin-right: 1rem; }
    .report-link { margin-top: 0.75rem; }
    .error { color: #b71c1c; }
    pre { white-space: pre-wrap; word-break: break-word; margin: 0; }
  </style>
</head>
<body>
  <h1>RemIcsReWrite — TS File</h1>
  <div class="toolbar">
    <a href="index.aspx?harness=1">Back to list</a>
    <a href="shell.aspx">Shell</a>
    <a href="../logoff.aspx?reason=1">Log off</a>
    <a href="/admin/">FCSA Testing</a>
  </div>
  <%= MetaHtml %>
  <%= DiagHtml %>

  <div class="actions">
    <h2 id="file-heading">Actions</h2>
    <p>
      <button type="button" id="btn-delete">Delete (killTable)</button>
      <button type="button" id="btn-print" class="secondary">Print / Export</button>
      <button type="button" id="btn-validate" class="secondary">Validate (valFile)</button>
    </p>
    <p class="validate-opts">
      <label class="chk"><input type="checkbox" id="chk-hilo"> Skip HiLo band check (-m:-1)</label>
      <label class="chk"><input type="checkbox" id="chk-verbose"> Verbose ftValidate (-v)</label>
    </p>
    <p>
      <label for="import-file">Import .txt into this table name:</label><br>
      <input type="file" id="import-file" accept=".txt,text/plain">
      <button type="button" id="btn-import" class="secondary">Upload &amp; Import</button>
    </p>
    <p id="action-status" aria-live="polite"></p>
  </div>

  <div class="result" id="result-panel" hidden>
    <h3>Last response</h3>
    <dl>
      <dt>HTTP status</dt><dd id="res-status">—</dd>
      <dt>Body</dt><dd><pre id="res-body">—</pre></dd>
    </dl>
    <p class="report-link" id="report-link-row" hidden>
      <a id="report-open" href="#" target="_blank" rel="noopener">Open validation report (.txt)</a>
    </p>
  </div>

  <script>
    window.REMICS_REWRITE = {
      fileName: "<%= JsFileName %>",
      projectCode: "<%= JsProjectCode %>",
      reportUrl: "<%= JsReportUrl %>"
    };
  </script>
  <script src="remics-api.js"></script>
  <script>
  (function () {
    var cfg = window.REMICS_REWRITE;
    var statusEl = document.getElementById('action-status');
    var panel = document.getElementById('result-panel');
    var resStatus = document.getElementById('res-status');
    var resBody = document.getElementById('res-body');
    var reportLinkRow = document.getElementById('report-link-row');
    var reportOpen = document.getElementById('report-open');
    document.getElementById('file-heading').textContent = 'Actions — ' + cfg.fileName;

    function setBusy(busy) {
      document.getElementById('btn-delete').disabled = busy;
      document.getElementById('btn-print').disabled = busy;
      document.getElementById('btn-validate').disabled = busy;
      document.getElementById('btn-import').disabled = busy;
    }

    function showResult(result, opts) {
      opts = opts || {};
      panel.hidden = false;
      resStatus.textContent = result.status + (result.ok ? ' OK' : '');
      resBody.textContent = result.body || result.error || '';
      statusEl.textContent = result.ok ? (opts.successMessage || 'Done.') : ('Failed: ' + (result.error || result.body || result.status));
      if (opts.reportUrl && result.ok) {
        reportOpen.href = opts.reportUrl;
        reportLinkRow.hidden = false;
      } else {
        reportLinkRow.hidden = true;
      }
    }

    function finish(result, opts) {
      setBusy(false);
      showResult(result, opts || {});
    }

    function fail(err, label) {
      finish({
        ok: false,
        status: 0,
        body: '',
        error: (label || 'Request failed') + ': ' + (err && err.message ? err.message : String(err || 'unknown'))
      });
    }

    document.getElementById('btn-delete').addEventListener('click', function () {
      if (!confirm('Delete TS table ' + cfg.fileName + '?')) return;
      setBusy(true);
      statusEl.textContent = 'Deleting…';
      RemIcsApi.killTable(cfg.fileName, cfg.projectCode).then(finish).catch(function (e) { fail(e, 'Delete'); });
    });

    document.getElementById('btn-print').addEventListener('click', function () {
      setBusy(true);
      statusEl.textContent = 'Exporting…';
      RemIcsApi.exportTable(cfg.fileName, cfg.projectCode).then(finish).catch(function (e) { fail(e, 'Export'); });
    });

    document.getElementById('btn-validate').addEventListener('click', function () {
      setBusy(true);
      reportLinkRow.hidden = true;
      statusEl.textContent = 'Validating (ftValidate)…';
      var options = {
        hilorep: document.getElementById('chk-hilo').checked ? '1' : '0',
        verbose: document.getElementById('chk-verbose').checked ? '1' : '0'
      };
      RemIcsApi.valFile(cfg.fileName, cfg.projectCode, options).then(function (r) {
        if (!r.ok) {
          finish(r);
          return;
        }
        statusEl.textContent = 'Loading report…';
        return RemIcsApi.fetchReport(cfg.reportUrl).then(function (report) {
          if (report.ok && report.body) {
            r.body = 'valFile returned: ' + r.body + '\n\n--- Report preview ---\n' + report.body;
          } else if (report.error) {
            r.body = 'valFile returned: ' + r.body + '\n\n(Report fetch failed: ' + report.error + ')';
          }
          var cancelled = report.body && /Validate cancelled/i.test(report.body);
          finish(r, {
            successMessage: cancelled ? 'Validate finished with errors (cancelled). See report.' : 'Validate complete.',
            reportUrl: cfg.reportUrl
          });
        });
      }).catch(function (e) { fail(e, 'Validate'); });
    });

    document.getElementById('btn-import').addEventListener('click', function () {
      var input = document.getElementById('import-file');
      if (!input.files || !input.files.length) {
        alert('Choose a .txt file first.');
        return;
      }
      setBusy(true);
      statusEl.textContent = 'Uploading…';
      RemIcsApi.uploadTxt(cfg.fileName, input.files[0]).then(function (uploadRes) {
        if (!uploadRes.ok) {
          finish(uploadRes);
          return;
        }
        statusEl.textContent = 'Importing…';
        return RemIcsApi.importTable(cfg.fileName, cfg.projectCode).then(finish);
      }).catch(function (e) { fail(e, 'Import'); });
    });
  })();
  </script>
</body>
</html>
