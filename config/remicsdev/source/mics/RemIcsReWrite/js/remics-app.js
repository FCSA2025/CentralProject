// RemIcsReWrite shell — routing, project bar, error banner, diagnostics.
(function () {
  var apiLog = [];
  var MAX_LOG = 10;
  var lastSession = null;
  var diagOpen = false;
  var activeFile = { fileType: '', fileName: '' };

  function $(id) { return document.getElementById(id); }

  function rewriteRoot() {
    if (window.RemIcsApi && RemIcsApi.micsRoot) {
      return RemIcsApi.micsRoot() + 'RemIcsReWrite/';
    }
    return '/mics/RemIcsReWrite/';
  }

  function parseHash() {
    var hash = (location.hash || '').replace(/^#\/?/, '');
    var q = hash.indexOf('?');
    var view = q >= 0 ? hash.substring(0, q) : hash;
    var query = q >= 0 ? hash.substring(q + 1) : '';
    return { view: view || 'welcome', query: query };
  }

  function isDiagOpen() {
    var drawer = $('diag-drawer');
    return drawer && !drawer.hidden;
  }

  function pushLog(entry) {
    apiLog.unshift(entry);
    if (apiLog.length > MAX_LOG) apiLog.length = MAX_LOG;
    if (isDiagOpen()) renderDiag();
  }

  function showError(title, detail) {
    var el = $('error-banner');
    if (!el) return;
    var text = title;
    if (detail) text += '\n' + (typeof detail === 'string' ? detail : JSON.stringify(detail, null, 2));
    el.innerHTML = '';
    var msg = document.createElement('span');
    msg.textContent = text;
    el.appendChild(msg);
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'remics-error-dismiss';
    btn.setAttribute('aria-label', 'Dismiss error');
    btn.textContent = '\u00d7';
    btn.addEventListener('click', clearError);
    el.appendChild(btn);
    el.hidden = false;
  }

  function clearError() {
    var el = $('error-banner');
    if (el) { el.innerHTML = ''; el.hidden = true; }
  }

  function fetchJson(url, options) {
    options = options || {};
    var silent = options.silent === true;
    var started = new Date().toISOString();
    var fetchOpts = { credentials: 'include' };
    if (options.method) fetchOpts.method = options.method;
    if (options.headers) fetchOpts.headers = options.headers;
    if (options.body) fetchOpts.body = options.body;

    return fetch(url, fetchOpts)
      .then(function (resp) {
        return resp.text().then(function (text) {
          var data = null;
          try { data = JSON.parse(text); } catch (e) { data = { raw: text }; }
          if (!silent) {
            pushLog({
              time: started,
              url: url,
              method: options.method || 'GET',
              status: resp.status,
              body: data
            });
          }
          if (!resp.ok && !silent) {
            showError('HTTP ' + resp.status + ' — ' + url, data);
          }
          return { ok: resp.ok, status: resp.status, data: data };
        });
      })
      .catch(function (err) {
        if (!silent) {
          pushLog({ time: started, url: url, error: err.message || String(err) });
          showError('Network error — ' + url, err.message || String(err));
        }
        throw err;
      });
  }

  function loadSession(silent) {
    return fetchJson(rewriteRoot() + 'session.ashx', { silent: silent === true }).then(function (r) {
      lastSession = r.data;
      if (r.data && r.data.user) {
        var badge = $('user-badge');
        if (badge) {
          badge.textContent = r.data.user + ' / ' + (r.data.schema || '') + ' / ' + (r.data.project || '');
        }
      }
      if (window.RemicsNav && RemicsNav.updateHeader) RemicsNav.updateHeader();
      return r.data;
    });
  }

  function loadProjects() {
    return fetchJson(rewriteRoot() + 'projects.ashx').then(function (r) {
      var sel = $('project-select');
      if (!sel || !r.data || !r.data.projects) return r.data;
      sel.innerHTML = '';
      r.data.projects.forEach(function (p) {
        var opt = document.createElement('option');
        opt.value = p.pcode;
        opt.textContent = p.pcode;
        if (p.pcode === r.data.current) opt.selected = true;
        sel.appendChild(opt);
      });
      return r.data;
    });
  }

  function setProject(pcode) {
    var body = new URLSearchParams();
    body.set('pcode', pcode);
    return fetchJson(rewriteRoot() + 'projects.ashx', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString()
    }).then(function (r) {
      if (lastSession) lastSession.project = pcode;
      return r;
    });
  }

  function setActiveFile(fileType, fileName) {
    activeFile.fileType = fileType || '';
    activeFile.fileName = fileName || '';
    var typeEl = $('active-type');
    var fileEl = $('active-file');
    if (typeEl) typeEl.value = activeFile.fileType;
    if (fileEl) fileEl.value = activeFile.fileName;
  }

  function mountCurrentView(view) {
    if (window.RemicsTs) {
      if (view === 'ts-tree') RemicsTs.mountTree('TS');
      else if (view === 'ts-file') RemicsTs.mountFile('TS');
      else if (view === 'es-tree') RemicsTs.mountTree('ES');
      else if (view === 'es-file') RemicsTs.mountFile('ES');
    }
    if (window.RemicsTsip) {
      if (view === 'tsip-parm') RemicsTsip.mountParm();
      else if (view === 'tsip-batch') RemicsTsip.mountBatch();
      else if (view === 'tsip-reps') RemicsTsip.mountReps();
      else if (view === 'tsip-run') RemicsTsip.mountRun();
    }
    if (window.RemicsPdf && view === 'pdf-edit') RemicsPdf.mount();
    if (window.RemicsDs) {
      if (view === 'ds-ts') RemicsDs.mountTs();
      else if (view === 'ds-es') RemicsDs.mountEs();
    }
    if (window.RemicsP675) {
      if (view === 'tsip-casedet') RemicsP675.mountCasedet();
      else if (view === 'file-open') RemicsP675.mountFileOpen();
      else if (view === 'sdf-tree') RemicsP675.mountSdfTree();
      else if (view === 'ds-sdf') RemicsP675.mountDsSdf();
      else if (view === 'fee-calc') RemicsP675.mountFeeCalc();
      else if (view === 'bulk-print') RemicsP675.mountBulkPrint();
      else if (view === 'aux-eng') RemicsP675.mountAuxEng();
      else if (view === 'tsip-post') RemicsP675.mountTsipPost();
      else if (view === 'radio-catalogue') RemicsP675.mountCatalogue();
      else if (view === 'info-files') RemicsP675.mountInfoFiles();
      else if (view === 'ds-report') RemicsP675.mountDsReport();
      else if (view === 'change-password') RemicsP675.mountChangePassword();
      else if (view === 'pwd-recovery-setup') RemicsP675.mountPwdRecoverySetup();
    }
  }

  function loadView(name) {
    var host = $('view-host');
    if (!host) return;
    var view = (name || 'welcome').split('?')[0];
    // Classic popup shortcuts — no shell HTML; mount opens the page then navigates away.
    if (view === 'radio-catalogue' || view === 'info-files' || view === 'ds-report'
        || view === 'pwd-recovery-setup' || view === 'tsip-post') {
      clearError();
      mountCurrentView(view);
      return;
    }
    var file = 'views/' + view + '.html';
    fetch(rewriteRoot() + file, { credentials: 'include' })
      .then(function (resp) {
        if (!resp.ok) throw new Error('View not found: ' + file);
        return resp.text();
      })
      .then(function (html) {
        // Strip inline scripts — innerHTML does not execute them; mount via RemicsTs instead.
        host.innerHTML = html.replace(/<script[\s\S]*?<\/script>/gi, '');
        clearError();
        mountCurrentView(view);
      })
      .catch(function (err) {
        host.innerHTML = '<p class="b">That screen is not available yet. Use <strong>TS Data Files</strong> or <strong>ES Data Files</strong> in the left nav.</p>';
        showError('View load failed', err.message);
      });
  }

  function navigate(view, query) {
    var hash = '#/' + view + (query ? '?' + query : '');
    if (location.hash === hash) {
      loadView(view);
      if (window.RemicsNav && RemicsNav.highlightRoute) {
        RemicsNav.highlightRoute(view, query || '');
      }
      return;
    }
    location.hash = hash;
  }

  function renderDiag() {
    var body = $('diag-body');
    if (!body) return;
    body.textContent = JSON.stringify({
      session: lastSession,
      activeFile: activeFile,
      apiLog: apiLog
    }, null, 2);
  }

  function setDiagOpen(open) {
    diagOpen = open;
    var drawer = $('diag-drawer');
    var backdrop = $('diag-backdrop');
    if (drawer) drawer.hidden = !open;
    if (backdrop) backdrop.hidden = !open;
    if (open) loadSession(true).then(renderDiag);
  }

  function initDiag() {
    $('diag-toggle').addEventListener('click', function () {
      setDiagOpen(!isDiagOpen());
    });
    $('diag-close').addEventListener('click', function () { setDiagOpen(false); });
    var backdrop = $('diag-backdrop');
    if (backdrop) {
      backdrop.addEventListener('click', function () { setDiagOpen(false); });
    }
    document.addEventListener('keydown', function (ev) {
      if (ev.key === 'Escape' && isDiagOpen()) setDiagOpen(false);
    });
    $('diag-copy').addEventListener('click', function () {
      var text = $('diag-body').textContent;
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text);
      }
    });
  }

  function initProjectSelect() {
    var sel = $('project-select');
    if (!sel) return;
    sel.addEventListener('change', function () {
      setProject(sel.value).catch(function () { /* error banner */ });
    });
  }

  function routeFromHash() {
    var parsed = parseHash();
    loadView(parsed.view);
    if (window.RemicsNav && RemicsNav.highlightRoute) {
      RemicsNav.highlightRoute(parsed.view, parsed.query);
    }
  }

  function init() {
    initDiag();
    initProjectSelect();
    if (window.RemicsNav) {
      if (RemicsNav.updateHeader) RemicsNav.updateHeader();
      RemicsNav.render($('remics-nav'), function (view, query) {
        navigate(view, query || '');
      });
    }
    window.addEventListener('hashchange', routeFromHash);
    loadProjects();
    loadSession(true);
    routeFromHash();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  window.RemicsApp = {
    showError: showError,
    clearError: clearError,
    loadView: loadView,
    navigate: navigate,
    loadSession: loadSession,
    getSession: function () { return lastSession; },
    setActiveFile: setActiveFile,
    getActiveFile: function () { return { fileType: activeFile.fileType, fileName: activeFile.fileName }; },
    getApiLog: function () { return apiLog.slice(); },
    state: activeFile
  };
})();
