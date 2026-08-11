// RemIcsReWrite Phase 1/4 — classic TS/ES tree + file wizards.
// Reports: never rewrite batch output; open the same userdirs/{schema}/{user}/{name}.txt as classic.
// Always pass filetype TS|ES on ASMX (ES → feValidate / fePrint / feImport).
(function (global) {
  var currentFt = 'TS'; // TS | ES

  function $(id) { return document.getElementById(id); }

  function rewriteRoot() {
    return (global.RemIcsApi && RemIcsApi.micsRoot)
      ? RemIcsApi.micsRoot() + 'RemIcsReWrite/'
      : '/mics/RemIcsReWrite/';
  }

  function session() {
    return (global.RemicsApp && RemicsApp.getSession && RemicsApp.getSession()) || {};
  }

  function projectCode() {
    var sel = $('project-select');
    if (sel && sel.value) return sel.value;
    var s = session();
    return s.project || (global.REMICS_SHELL && REMICS_SHELL.project) || '';
  }

  function ft() {
    return currentFt === 'ES' ? 'ES' : 'TS';
  }

  function ftOpts(extra) {
    var o = { filetype: ft() };
    if (extra) {
      Object.keys(extra).forEach(function (k) { o[k] = extra[k]; });
    }
    return o;
  }

  function treePrefix() {
    return ft() === 'ES' ? 'es' : 'ts';
  }

  function treeView() {
    return ft() === 'ES' ? 'es-tree' : 'ts-tree';
  }

  function isValidMicsFileName(name) {
    return /^[A-Za-z0-9_]{1,16}$/.test(name || '');
  }

  /** Basename of uploaded .txt without extension; sanitized for MICS table name rules. */
  function micsNameFromUploadFile(file) {
    if (!file || !file.name) return '';
    var base = String(file.name).replace(/^.*[\\/]/, '').replace(/\.txt$/i, '');
    base = base.replace(/[^A-Za-z0-9_]/g, '_').replace(/_+/g, '_').replace(/^_|_$/g, '');
    if (base.length > 16) base = base.substring(0, 16);
    return base;
  }

  function resolveImportName(nameField, fileInput, routeName) {
    var name = (nameField && nameField.value ? nameField.value : '').trim();
    if (name) return name;
    if (routeName) return routeName.trim();
    if (fileInput && fileInput.files && fileInput.files.length) {
      return micsNameFromUploadFile(fileInput.files[0]);
    }
    return '';
  }

  function fileView() {
    return ft() === 'ES' ? 'es-file' : 'ts-file';
  }

  function reportUrl(fileName) {
    var s = session();
    var schema = s.schema || (global.REMICS_SHELL && REMICS_SHELL.schema) || '';
    var user = s.user || (global.REMICS_SHELL && REMICS_SHELL.user) || '';
    return RemIcsApi.micsRoot() + 'userdirs/' + schema + '/' + user + '/' + fileName + '.txt';
  }

  function openReportWindow(fileNameOrTxt, winName) {
    var name = fileNameOrTxt || '';
    if (name.indexOf('FILENAME:') === 0) name = name.substring(9);
    if (/\.txt$/i.test(name)) name = name.replace(/\.txt$/i, '');
    var url = reportUrl(name);
    window.open(url, winName || 'WndValid', 'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,status=yes');
  }

  function setActiveFile(fileName) {
    var type = ft();
    if (global.RemicsApp && RemicsApp.setActiveFile) {
      RemicsApp.setActiveFile(type, fileName || '');
    }
    var typeEl = $('active-type');
    var fileEl = $('active-file');
    if (typeEl) typeEl.value = fileName ? type : '';
    if (fileEl) fileEl.value = fileName || '';
  }

  function goTree() {
    var v = treeView();
    if (global.RemicsApp && RemicsApp.navigate) RemicsApp.navigate(v);
    else location.hash = '#/' + v;
  }

  function goFile(action, fileName) {
    var q = 'action=' + encodeURIComponent(action || 'validate');
    if (fileName) q += '&name=' + encodeURIComponent(fileName);
    var v = fileView();
    if (global.RemicsApp && RemicsApp.navigate) RemicsApp.navigate(v, q);
    else location.hash = '#/' + v + '?' + q;
  }

  function show(el, on) {
    if (!el) return;
    el.hidden = !on;
    el.style.display = on ? '' : 'none';
  }

  function parseRoute() {
    var hash = (location.hash || '').replace(/^#\/?/, '');
    var parts = hash.split('?');
    var view = parts[0] || '';
    var params = {};
    if (parts[1]) {
      parts[1].split('&').forEach(function (pair) {
        var kv = pair.split('=');
        params[decodeURIComponent(kv[0] || '')] = decodeURIComponent(kv[1] || '');
      });
    }
    return { view: view, params: params };
  }

  function detectFileType(preferred) {
    if (preferred === 'ES' || preferred === 'TS') return preferred;
    var route = parseRoute();
    if (route.params.filetype === 'ES' || route.params.filetype === 'TS') {
      return route.params.filetype;
    }
    if ((route.view || '').indexOf('es-') === 0) return 'ES';
    return 'TS';
  }

  function parseValidationSummary(text) {
    if (!text) return null;
    var total = text.match(/There were a total of\s+(\d+)\s+errors?\s+and\s+(\d+)\s+warnings?/i);
    if (total) {
      return { errors: parseInt(total[1], 10), warnings: parseInt(total[2], 10) };
    }
    return null;
  }

  /* ---------- Tree ---------- */

  function classicPopup(path) {
    var url = RemIcsApi.micsRoot() + path;
    window.open(url, 'WndClassic', 'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,status=yes,width=900,height=700');
  }

  function navigatePdfEdit(fileName, extraQuery) {
    var q = 'name=' + encodeURIComponent(fileName) + '&filetype=' + encodeURIComponent(ft());
    if (extraQuery) q += '&' + extraQuery;
    if (global.RemicsApp && RemicsApp.navigate) RemicsApp.navigate('pdf-edit', q);
    else location.hash = '#/pdf-edit?' + q;
  }

  function panelForTreeNode(nodeType, filetype) {
    if (nodeType === 't') return 'title';
    if (nodeType === 'd') return 'sites';
    if (nodeType === 'a') return 'antes';
    if (nodeType === 'c' || nodeType === 'h') return 'chans';
    if (nodeType === 'q') return 'cloc';
    if (nodeType === 'g') return filetype === 'ES' ? 'ccal' : 'chng';
    return 'title';
  }

  function reloadTree() {
    var pfx = treePrefix();
    var tree = global.__remicsTreeInstance && global.__remicsTreeInstance[pfx];
    if (tree) tree.load();
    else goTree();
  }

  function deleteTreeNode(ctx) {
    var value = ctx.value || '';
    var nodeType = value.charAt(0);
    var nodeText = (ctx.nodeText || value).replace(/\s+/g, ' ').trim();
    var pc = projectCode();
    var isEs = ft() === 'ES';
    var servicePath = isEs ? 'Tesmenu/TwsESTree.asmx' : 'Ttsmenu/TwsTStree.asmx';
    var cfg = null;

    if (!isEs) {
      if (nodeType === 'g') {
        cfg = { method: 'delete_ts_chng', key: value, msg: 'Change of Call Sign ' + nodeText };
      } else if (nodeType === 's') {
        cfg = { method: 'delete_ts_site', key: value, msg: 'site ' + nodeText + ' and all antennas and channels below it' };
      } else if (nodeType === 'k') {
        cfg = { method: 'delete_ts_link', key: value, msg: 'link ' + nodeText + ' and all antennas and channels below it' };
      } else if (nodeType === 'a') {
        cfg = { method: 'delete_ts_ante', key: value, msg: 'antenna ' + nodeText };
      } else if (nodeType === 'c') {
        cfg = { method: 'delete_ts_chan', key: value, msg: 'channel ' + nodeText };
      }
    } else {
      if (nodeType === 'q') {
        cfg = { method: 'delete_es_cloc', key: value, msg: 'Change of Location ' + nodeText };
      } else if (nodeType === 'g') {
        cfg = { method: 'delete_es_ccal', key: value, msg: 'Change of Call Sign ' + nodeText };
      } else if (nodeType === 's') {
        cfg = { method: 'delete_es_site', key: 'd' + value.substring(1), msg: 'site ' + nodeText + ' and all antennas, channels, and azimuths below it' };
      } else if (nodeType === 'n') {
        cfg = { method: 'delete_es_ante', key: value, msg: 'antenna ' + nodeText + ' and all channels and azimuths below it' };
      } else if (nodeType === 'h') {
        cfg = { method: 'delete_es_chan', key: value, msg: 'channel ' + nodeText };
      }
    }

    if (!cfg) {
      alert('This selection may not be deleted.');
      return;
    }

    if (!window.confirm('Are you sure you want to delete the ' + cfg.msg + '?')) {
      return;
    }

    RemIcsApi.dsAsmx(servicePath, cfg.method, { project: pc, key: cfg.key }).then(function (r) {
      var body = (r.body != null ? String(r.body) : '');
      if (!r.ok || body.indexOf('ERROR') === 0 || body.toLowerCase().indexOf('timeout') === 0) {
        alert(r.error || body || 'Delete failed');
        return;
      }
      reloadTree();
    }).catch(function (ex) {
      alert('Delete error: ' + (ex.message || ex));
    });
  }

  function handleTreeAction(action, ctx) {
    var fileName = ctx.fileName || '';
    var value = ctx.value || '';
    var nodeType = value.charAt(0);

    if (action === 'help') {
      classicPopup('micshelp/tsTreeHelp.aspx');
      return;
    }
    if (action === 'create') {
      var name = window.prompt('New ' + ft() + ' file name (1–16 letters, digits, underscore):', '');
      if (!name) return;
      name = name.trim();
      if (!/^[A-Za-z0-9_]{1,16}$/.test(name)) {
        alert('Invalid name. Use 1–16 characters: A–Z, a–z, 0–9, _.');
        return;
      }
      RemIcsApi.createTable(name, projectCode(), ftOpts()).then(function (r) {
        if (!r.ok) { alert(r.error || r.body || 'createTable failed'); return; }
        navigatePdfEdit(name);
      });
      return;
    }
    if (action === 'import') {
      goFile('import', '');
      return;
    }
    if (action === 'validate') {
      goFile('validate', fileName);
      return;
    }
    if (action === 'export') goFile('export', fileName);
    else if (action === 'delete') goFile('delete', fileName);
    else if (action === 'copy') goFile('copy', fileName);
    else if (action === 'dbupdate') goFile('dbupdate', fileName);
    else if (action === 'pcn') goFile('pcn', fileName);
    else if (action === 'kml' && ft() === 'TS') {
      classicPopup('Ttsmenu/tsPdfKml.aspx?kmlName=' + encodeURIComponent(fileName) + '&reptype=V');
    }
    else if (action === 'edit-node') {
      var panel = panelForTreeNode(nodeType, ft());
      navigatePdfEdit(fileName, 'panel=' + panel + '&key=' + encodeURIComponent(value));
    }
    else if (action === 'new-site') {
      classicPopup((ft() === 'ES' ? 'Tesmenu/esSiteNew.aspx' : 'Ttsmenu/tsSiteNew.aspx') + '?key=' + encodeURIComponent(value));
    }
    else if (action === 'new-link') {
      classicPopup('Ttsmenu/tsLinkNew.aspx?key=' + encodeURIComponent(value));
    }
    else if (action === 'new-ante') {
      classicPopup((ft() === 'ES' ? 'Tesmenu/esAnteNew.aspx' : 'Ttsmenu/tsAnteNew.aspx') + '?key=' + encodeURIComponent(value));
    }
    else if (action === 'new-chan') {
      classicPopup((ft() === 'ES' ? 'Tesmenu/esChanNew.aspx' : 'Ttsmenu/tsChanNew.aspx') + '?key=' + encodeURIComponent(value));
    }
    else if (action === 'new-chng') {
      classicPopup((ft() === 'ES' ? 'Tesmenu/esChangeofCallSignNew.aspx' : 'Ttsmenu/tsChangeofCallSignNew.aspx') + '?key=' + encodeURIComponent(value));
    }
    else if (action === 'new-cloc') {
      classicPopup('Tesmenu/esChangeofLocationNew.aspx?key=' + encodeURIComponent(value));
    }
    else if (action === 'delete-node') {
      deleteTreeNode(ctx);
    }
  }

  function mountTree(preferredFt) {
    currentFt = detectFileType(preferredFt);
    var pfx = treePrefix();
    var container = $(pfx + '-data-tree');
    var status = $(pfx + '-tree-status');
    if (!container) return;

    setActiveFile('');

    if (!global.__remicsTreeInstance) global.__remicsTreeInstance = {};
    var tree = new RemicsDataTree(container, {
      filetype: ft(),
      rootLabel: ft() === 'ES' ? 'ES Data Tree' : 'TS Data Tree',
      onSelectFile: function (name) { setActiveFile(name); },
      onStatus: function (msg) { if (status) status.textContent = msg || ''; },
      onAction: handleTreeAction
    });
    global.__remicsTreeInstance[pfx] = tree;

    var refresh = $(pfx + '-refresh');
    if (refresh) refresh.onclick = function () { tree.load(); };

    tree.load();
  }

  /* ---------- File wizards ---------- */

  function mountFile(preferredFt) {
    currentFt = detectFileType(preferredFt);
    var route = parseRoute();
    var action = (route.params.action || 'validate').toLowerCase();
    var fileName = (route.params.name || '').trim();
    var title = $('pdf-file-title') || $('ts-file-title');
    var nameEl = $('pdf-file-name') || $('ts-file-name');

    setActiveFile(fileName);

    ['panel-validate', 'panel-export', 'panel-import', 'panel-delete', 'panel-copy', 'panel-dbupdate', 'panel-pcn'].forEach(function (id) {
      show($(id), false);
    });

    var titles = {
      validate: 'FCSA MICS Validating File',
      export: 'FCSA MICS Exporting File',
      import: 'FCSA MICS Import Local File',
      delete: 'FCSA MICS Delete File',
      copy: 'FCSA MICS Copy File',
      dbupdate: 'FCSA MICS Database Updating Files',
      pcn: 'FCSA MICS PCN Coordination'
    };
    if (title) title.textContent = titles[action] || 'FCSA MICS File';
    if (nameEl) {
      nameEl.innerHTML = fileName ? '<h4 align="center">' + fileName.replace(/</g, '&lt;') + '</h4>' : '';
    }

    if (action === 'validate') mountValidate(fileName);
    else if (action === 'export') mountExport(fileName);
    else if (action === 'import') mountImport(fileName);
    else if (action === 'delete') mountDelete(fileName);
    else if (action === 'copy') mountCopy(fileName);
    else if (action === 'dbupdate') mountDbUpdate(fileName);
    else if (action === 'pcn') mountPcn(fileName);
    else goTree();
  }

  function mountValidate(fileName) {
    show($('panel-validate'), true);
    show($('val-m0'), true);
    show($('val-m1'), false);
    show($('val-m2'), false);
    show($('val-m3'), false);
    var cleanfile = fileName + '.txt';

    // TS-only options (absent on ES view)
    var hilo = $('chkHilo');
    var verbose = $('chkVerbose');

    $('cmdValCancel').onclick = goTree;
    $('cmdValReturn').onclick = goTree;
    $('cmdDisplay').onclick = function () { openReportWindow(cleanfile, 'WndValid'); show($('val-m2'), false); show($('val-m3'), true); };

    $('cmdValidate').onclick = function () {
      show($('val-m0'), false);
      show($('val-m1'), true);
      var options = ftOpts({
        hilorep: (hilo && hilo.checked) ? '1' : '0',
        verbose: (verbose && verbose.checked) ? '1' : '0'
      });
      RemIcsApi.valFile(fileName, projectCode(), options).then(function (r) {
        show($('val-m1'), false);
        if (!r.ok) {
          alert(r.error || r.body || ('Validate failed (HTTP ' + r.status + ')'));
          show($('val-m0'), true);
          return;
        }
        cleanfile = (r.body || (fileName + '.txt')).replace(/^FILENAME:/, '');
        if (!/\.txt$/i.test(cleanfile)) cleanfile = cleanfile + '.txt';
        var base = cleanfile.replace(/\.txt$/i, '');
        RemIcsApi.fetchReport(reportUrl(base)).then(function (report) {
          var summary = $('valSummary');
          if (summary) {
            var counts = parseValidationSummary(report.body || '');
            if (counts) {
              summary.innerHTML = 'Errors: <b>' + counts.errors + '</b> &nbsp;&nbsp; Warnings: <b>' + counts.warnings + '</b>';
            } else if (report.body && /error|cancelled/i.test(report.body)) {
              summary.textContent = 'Errors were detected. Use Display Results to view the report.';
            } else {
              summary.textContent = '';
            }
            summary.style.display = summary.textContent ? '' : 'none';
          }
          show($('val-m2'), true);
        });
      }).catch(function (ex) {
        show($('val-m1'), false);
        show($('val-m0'), true);
        alert('Validate error: ' + (ex.message || ex));
      });
    };
  }

  function mountExport(fileName) {
    show($('panel-export'), true);
    show($('exp-m0'), true);
    show($('exp-m1'), false);
    show($('exp-m2'), false);
    show($('exp-m3'), false);
    var cleanfile = fileName + '.txt';

    $('cmdExpCancel').onclick = goTree;
    $('cmdExpReturn').onclick = goTree;

    $('cmdExport').onclick = function () {
      show($('exp-m0'), false);
      show($('exp-m1'), true);
      $('cmdExport').disabled = true;
      RemIcsApi.exportTable(fileName, projectCode(), ftOpts()).then(function (r) {
        show($('exp-m1'), false);
        $('cmdExport').disabled = false;
        if (!r.ok) {
          alert(r.error || r.body || ('Export failed (HTTP ' + r.status + ')'));
          show($('exp-m0'), true);
          return;
        }
        var body = r.body || '';
        if (body.indexOf('FILENAME') === 0) {
          cleanfile = body.substring(9);
          show($('exp-m2'), true);
          setTimeout(function () {
            openReportWindow(cleanfile, 'WndExport');
            show($('exp-m2'), false);
            show($('exp-m3'), true);
          }, 1000);
        } else {
          alert(body || 'Unexpected export response');
          goTree();
        }
      }).catch(function (ex) {
        show($('exp-m1'), false);
        show($('exp-m0'), true);
        $('cmdExport').disabled = false;
        alert('Export error: ' + (ex.message || ex));
      });
    };
  }

  function mountImport(fileName) {
    show($('panel-import'), true);
    show($('imp-m0'), true);
    show($('imp-m1'), false);
    show($('imp-m2'), false);
    show($('imp-m3'), false);
    if ($('imp-name')) $('imp-name').value = fileName || '';

    var fileInput = $('imp-file');
    if (fileInput) {
      fileInput.onchange = function () {
        var nameField = $('imp-name');
        if (!nameField || (nameField.value || '').trim() || fileName) return;
        if (!fileInput.files || !fileInput.files.length) return;
        var derived = micsNameFromUploadFile(fileInput.files[0]);
        if (derived) nameField.value = derived;
      };
    }

    $('cmdImpCancel').onclick = goTree;
    $('cmdImpReturn').onclick = goTree;
    $('cmdImpDisplay').onclick = function () {
      openReportWindow(($('imp-name').value || fileName || '').trim(), 'WndImport');
    };

    $('cmdImport').onclick = function () {
      var nameField = $('imp-name');
      var input = $('imp-file');
      var name = resolveImportName(nameField, input, fileName);
      if (name && nameField && !(nameField.value || '').trim()) {
        nameField.value = name;
      }
      if (!isValidMicsFileName(name)) {
        alert('Enter a valid Mics File Name (1-16 letters, digits, underscore), or choose a .txt file whose name can be used.');
        return;
      }
      if (!input.files || !input.files.length) {
        alert('Choose a .txt file first.');
        return;
      }
      show($('imp-m0'), false);
      show($('imp-m1'), true);
      RemIcsApi.uploadTxt(name, input.files[0]).then(function (up) {
        if (!up.ok) {
          show($('imp-m1'), false);
          show($('imp-m0'), true);
          alert(up.error || 'Upload failed');
          return null;
        }
        show($('imp-m1'), false);
        show($('imp-m2'), true);
        return RemIcsApi.importTable(name, projectCode(), ftOpts());
      }).then(function (r) {
        if (!r) return;
        show($('imp-m2'), false);
        if (!r.ok) {
          show($('imp-m0'), true);
          alert(r.error || r.body || 'Import failed');
          return;
        }
        setActiveFile(name);
        show($('imp-m3'), true);
      }).catch(function (ex) {
        show($('imp-m1'), false);
        show($('imp-m2'), false);
        show($('imp-m0'), true);
        alert('Import error: ' + (ex.message || ex));
      });
    };
  }

  function mountDelete(fileName) {
    show($('panel-delete'), true);
    show($('del-m0'), true);
    show($('del-m1'), false);
    show($('del-m2'), false);
    if ($('del-name')) $('del-name').textContent = fileName;

    $('cmdDelCancel').onclick = goTree;
    $('cmdDelReturn').onclick = goTree;

    $('cmdDelete').onclick = function () {
      if (!confirm('Delete ' + ft() + ' table ' + fileName + '?')) return;
      show($('del-m0'), false);
      show($('del-m1'), true);
      RemIcsApi.killTable(fileName, projectCode(), ftOpts()).then(function (r) {
        show($('del-m1'), false);
        if (!r.ok) {
          alert(r.error || r.body || 'Delete failed');
          show($('del-m0'), true);
          return;
        }
        setActiveFile('');
        show($('del-m2'), true);
      }).catch(function (ex) {
        show($('del-m1'), false);
        show($('del-m0'), true);
        alert('Delete error: ' + (ex.message || ex));
      });
    };
  }

  function mountDbUpdate(fileName) {
    show($('panel-dbupdate'), true);
    show($('dbu-m0'), false);
    show($('dbu-m1'), false);
    show($('dbu-m2'), false);
    var gateEl = $('dbu-gate');
    if (gateEl) gateEl.textContent = 'Checking validation status…';

    $('cmdDbuCancel').onclick = goTree;
    $('cmdDbuReturn').onclick = goTree;
    var dbuHelp = $('cmdDbuHelp');
    if (dbuHelp) dbuHelp.onclick = function () { classicPopup('micshelp/DbUpdate.aspx'); };
    $('cmdDbuDisplay').onclick = function () { openReportWindow(fileName, 'WndUpdate'); };

    RemIcsApi.dbUpdateGate(fileName, ftOpts()).then(function (gate) {
      if (!gate.ok) {
        alert(gate.error || 'Unable to check validation status.');
        goTree();
        return;
      }
      if (!gate.allowTransfer) {
        alert(gate.errortext || 'This file cannot be transferred for update.');
        goTree();
        return;
      }
      if (gateEl) gateEl.textContent = '';
      show($('dbu-m0'), true);
      var warn = $('dbu-warn');
      if (warn) warn.textContent = gate.errortext || '';
      var btn = $('cmdUpdateF');
      if (btn) btn.disabled = false;

      btn.onclick = function () {
        btn.disabled = true;
        show($('dbu-m0'), false);
        show($('dbu-m1'), true);
        RemIcsApi.exportForUpdate(fileName, projectCode(), ftOpts({ userFcsa: 'F' })).then(function (r) {
          show($('dbu-m1'), false);
          var body = (r.body || '').toString();
          var exportOk = r.ok && (body === 'OK' || body.indexOf('OK') === 0);
          if (!exportOk) {
            var disp = $('cmdDbuDisplay');
            if (disp) disp.hidden = false;
            var msg = $('dbu-done-msg');
            if (msg) msg.textContent = r.error || body || 'Export for update failed.';
            show($('dbu-m2'), true);
            setTimeout(function () { openReportWindow(fileName, 'WndUpdate'); }, 1000);
            return;
          }
          return RemIcsApi.dbUpdateNotify(fileName, ftOpts({ userFcsa: 'F' })).then(function (n) {
            var msg = $('dbu-done-msg');
            var text = (n && n.message) || 'Transfer for database update complete.';
            if (n && !n.ok) {
              alert(n.error || 'Notify failed after export.');
              if (msg) msg.textContent = n.error || text;
            } else {
              alert(text);
              if (msg) msg.textContent = text;
              if (n && n.emailSent === false) {
                if (msg) msg.textContent = text + ' (email may not have been delivered — see extractlogs)';
              }
            }
            var disp = $('cmdDbuDisplay');
            if (disp) disp.hidden = true;
            show($('dbu-m2'), true);
          });
        }).catch(function (ex) {
          show($('dbu-m1'), false);
          show($('dbu-m0'), true);
          btn.disabled = false;
          alert('Database update error: ' + (ex.message || ex));
        });
      };
    }).catch(function (ex) {
      alert('Database update gate error: ' + (ex.message || ex));
      goTree();
    });
  }

  function mountPcn(fileName) {
    show($('panel-pcn'), true);
    show($('pcn-m0'), false);
    show($('pcn-m1'), false);
    show($('pcn-m2'), false);
    show($('pcn-m3'), false);

    var state = {
      logserial: '',
      tmpdir: '',
      senderEmail: '',
      cDist: 200,
      includeOwn: true
    };

    var gateMsg = $('pcn-gate-msg');
    var distRow = $('pcn-dist-row');
    var cdistEl = $('pcn-cdist');
    var kmlRow = $('pcn-kml-row');

    $('cmdPcnCancel0').onclick = goTree;
    $('cmdPcnCancel2').onclick = goTree;
    $('cmdPcnReturn').onclick = goTree;
    var pcnHelp = $('cmdPcnHelp');
    if (pcnHelp) {
      pcnHelp.onclick = function () {
        classicPopup(ft() === 'ES' ? 'micshelp/PcnES.aspx' : 'micshelp/PcnTS.aspx');
      };
    }

    function showCompose(ops) {
      state.tmpdir = ops.tmpdir || '';
      state.senderEmail = ops.senderEmail || '';
      var box = $('pcn-oper-box');
      if (box) {
        if (!ops.operators || !ops.operators.length) {
          box.textContent = ops.message || 'No operators.';
        } else {
          box.innerHTML = '<b>Affected Operators</b><br>' + ops.operators.map(function (o) {
            return (o.oper || '') + ' — ' + (o.name || o.ultrixid || '');
          }).join('<br>');
        }
      }
      var sel = $('pcn-emails');
      if (sel) {
        sel.innerHTML = '';
        (ops.emails || []).forEach(function (e) {
          var opt = document.createElement('option');
          opt.value = e.email;
          opt.textContent = e.display || e.email;
          opt.selected = true;
          sel.appendChild(opt);
        });
      }
      if (kmlRow) show(kmlRow, ft() === 'TS');
      show($('pcn-m1'), false);
      show($('pcn-m2'), true);
    }

    function loadOperators(includeOwn) {
      state.includeOwn = includeOwn !== false;
      return RemIcsApi.pcnOperators(fileName, state.logserial, {
        filetype: ft(),
        includeOwn: state.includeOwn
      }).then(function (ops) {
        if (!ops.ok) {
          alert(ops.error || 'Unable to load operators.');
          show($('pcn-m1'), false);
          show($('pcn-m0'), true);
          return;
        }
        if (ops.empty) {
          alert(ops.message || 'No companies within distance.');
          goTree();
          return;
        }
        if (ops.ownCompanyAffected && ops.otherMicsInCompany > 0 && includeOwn !== false) {
          var yn = confirm(
            'Your company is also within the coordination distance.\n' +
            'Include other MICS users in your company on the PCN email list?'
          );
          if (!yn) return loadOperators(false);
        }
        showCompose(ops);
      });
    }

    RemIcsApi.pcnGate(fileName, ftOpts()).then(function (gate) {
      if (!gate.ok && gate.error) {
        alert(gate.error);
        goTree();
        return;
      }
      if (!gate.allow) {
        alert(gate.skipReason || 'This file cannot be used for PCN Coordination.');
        goTree();
        return;
      }
      state.cDist = gate.cDist != null ? gate.cDist : 200;
      if (cdistEl) cdistEl.value = String(state.cDist);
      if (distRow) show(distRow, !!gate.distanceEditable);
      if (gateMsg) {
        gateMsg.textContent = ft() === 'ES'
          ? ('ES coordination distance from antenna scatter: ' + state.cDist + ' km')
          : 'Enter coordination distance, then Find Operators.';
      }
      show($('pcn-m0'), true);
    }).catch(function (ex) {
      alert('PCN gate error: ' + (ex.message || ex));
      goTree();
    });

    $('cmdPcnFind').onclick = function () {
      var d = parseFloat(cdistEl && cdistEl.value ? cdistEl.value : state.cDist);
      if (!(d > 0)) {
        alert('Enter a positive coordination distance.');
        return;
      }
      state.cDist = d;
      show($('pcn-m0'), false);
      show($('pcn-m1'), true);
      RemIcsApi.pcnScan(fileName, projectCode(), ftOpts({ cDist: d })).then(function (r) {
        if (!r.ok) {
          show($('pcn-m1'), false);
          if (r.errorReportFile) {
            alert(r.error || 'pcnscan errors — opening report.');
            openReportWindow(r.errorReportFile, 'WndPcnErr');
          } else {
            alert(r.error || 'pcnscan failed');
          }
          show($('pcn-m0'), true);
          return;
        }
        state.logserial = r.logserial || '';
        return loadOperators(true);
      }).catch(function (ex) {
        show($('pcn-m1'), false);
        show($('pcn-m0'), true);
        alert('PCN scan error: ' + (ex.message || ex));
      });
    };

    $('cmdPcnAttach').onclick = function () {
      var input = $('pcn-attach-file');
      if (!state.tmpdir) {
        alert('Find Operators first.');
        return;
      }
      if (!input.files || !input.files.length) {
        alert('Choose a file to attach.');
        return;
      }
      RemIcsApi.pcnAttach(state.tmpdir, input.files[0]).then(function (r) {
        var st = $('pcn-attach-status');
        if (st) st.textContent = r.ok ? ('Attached ' + (r.fileName || '')) : (r.error || 'Attach failed');
      });
    };

    $('cmdPcnSend').onclick = function () {
      var sel = $('pcn-emails');
      var to = [];
      if (sel) {
        Array.prototype.forEach.call(sel.options, function (opt) {
          if (opt.selected) to.push(opt.value);
        });
      }
      var kml = $('pcn-kml');
      var btn = $('cmdPcnSend');
      btn.disabled = true;
      show($('pcn-m2'), false);
      show($('pcn-m1'), true);

      RemIcsApi.exportTable(fileName, projectCode(), ftOpts()).then(function (ex) {
        if (!ex.ok) {
          throw new Error(ex.error || ex.body || 'exportTable failed');
        }
        return RemIcsApi.pcnSend(fileName, {
          filetype: ft(),
          tmpdir: state.tmpdir,
          notes: ($('pcn-notes') && $('pcn-notes').value) || '',
          cc: ($('pcn-cc') && $('pcn-cc').value) || '',
          senderEmail: state.senderEmail,
          toEmails: to.join(';'),
          attachKml: !!(kml && kml.checked && ft() === 'TS')
        });
      }).then(function (r) {
        show($('pcn-m1'), false);
        btn.disabled = false;
        var msg = $('pcn-done-msg');
        if (!r.ok) {
          if (msg) msg.textContent = r.error || 'PCN send failed';
          alert(r.error || 'PCN send failed');
          show($('pcn-m2'), true);
          return;
        }
        if (msg) msg.textContent = r.message || 'PCN notification processed.';
        alert(r.message || 'PCN complete');
        show($('pcn-m3'), true);
      }).catch(function (ex) {
        show($('pcn-m1'), false);
        show($('pcn-m2'), true);
        btn.disabled = false;
        alert('PCN send error: ' + (ex.message || ex));
      });
    };
  }

  function mountCopy(fileName) {
    show($('panel-copy'), true);
    show($('cpy-m0'), true);
    show($('cpy-m1'), false);
    show($('cpy-m2'), false);
    if ($('cpy-from')) $('cpy-from').textContent = fileName;

    $('cmdCpyCancel').onclick = goTree;
    $('cmdCpyReturn').onclick = goTree;

    $('cmdCopy').onclick = function () {
      var newName = ($('cpy-name').value || '').trim();
      if (!/^[A-Za-z0-9_]{1,16}$/.test(newName)) {
        alert('Enter a valid new file name (1-16 letters, digits, underscore).');
        return;
      }
      show($('cpy-m0'), false);
      show($('cpy-m1'), true);
      RemIcsApi.copyTable(fileName, newName, projectCode(), ftOpts()).then(function (r) {
        show($('cpy-m1'), false);
        if (!r.ok) {
          alert(r.error || r.body || 'Copy failed');
          show($('cpy-m0'), true);
          return;
        }
        setActiveFile(newName);
        show($('cpy-m2'), true);
      }).catch(function (ex) {
        show($('cpy-m1'), false);
        show($('cpy-m0'), true);
        alert('Copy error: ' + (ex.message || ex));
      });
    };
  }

  global.RemicsTs = {
    mountTree: mountTree,
    mountFile: mountFile,
    reportUrl: reportUrl,
    openReportWindow: openReportWindow,
    getFileType: ft
  };
})(window);
