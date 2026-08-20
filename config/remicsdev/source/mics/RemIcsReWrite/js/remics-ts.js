// RemIcsReWrite Phase 1/4  -  classic TS/ES tree + file wizards.
// Reports: never rewrite batch output; open the same userdirs/{schema}/{user}/{name}.txt as classic.
// Always pass filetype TS|ES on ASMX (ES → feValidate / fePrint / feImport).
(function (global) {
  var currentFt = 'TS'; // TS | ES

  function $(id) { return document.getElementById(id); }

  function apiAlert(r, fallback) {
    if (r && ((r.expired) || (window.RemIcsApi && RemIcsApi.isExpired && RemIcsApi.isExpired(r)))) return;
    if (typeof r === 'string' && window.RemIcsApi && RemIcsApi.isExpired && RemIcsApi.isExpired(r)) return;
    alert((window.RemIcsApi && RemIcsApi.apiErr) ? RemIcsApi.apiErr(r, fallback) : ((r && r.error) || r || fallback));
  }

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
    if (fileName && window.RemIcsApi && RemIcsApi.rememberLastFile) {
      RemIcsApi.rememberLastFile(type, fileName);
    }
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
    if (nodeType === 's' || nodeType === 'd') return 'sites';
    if (nodeType === 'n' || nodeType === 'a') return 'antes';
    if (nodeType === 'm') return 'azims';
    if (nodeType === 'c' || nodeType === 'h') return 'chans';
    if (nodeType === 'q') return 'cloc';
    if (nodeType === 'g') return filetype === 'ES' ? 'ccal' : 'chng';
    return 'title';
  }

  function recordKeyForFolder(value) {
    var p = (value || '').charAt(0);
    if (p === 's') return 'd' + String(value).substring(1);
    if (p === 'n') return 'a' + String(value).substring(1);
    return value;
  }

  function revealStoreKey(filetype) {
    return 'remics-tree-reveal-' + ((filetype || ft()) === 'ES' ? 'ES' : 'TS');
  }

  function rememberReveal(value, filetype) {
    if (!value) return;
    try { sessionStorage.setItem(revealStoreKey(filetype), value); } catch (e) {}
  }

  function persistTreeFileSelection(name) {
    if (!name) return;
    var fileVal = 'e.' + name;
    try { sessionStorage.setItem('remics-tree-selected-' + ft(), fileVal); } catch (e) {}
    rememberReveal(fileVal, ft());
  }

  function selectFileInTree(name, statusMsg) {
    persistTreeFileSelection(name);
    setActiveFile(name);
    var fileVal = 'e.' + name;
    var tree = activeTree();
    if (!treeIsLive(tree)) {
      goTree();
      return;
    }
    var expanded = tree.getExpandedValues();
    tree.load().then(function () {
      syncTreeFindVisible(tree);
      return tree.restoreExpanded(expanded);
    }).then(function () {
      consumeReveal(ft());
      var li = tree.findNodeLi(fileVal);
      if (li) tree.selectLi(li);
      else if (tree.reveal) return tree.reveal(fileVal);
    }).then(function () {
      if (statusMsg && tree && tree.onStatus) tree.onStatus(statusMsg);
    });
  }

  function consumeReveal(filetype) {
    try {
      var k = revealStoreKey(filetype);
      var v = sessionStorage.getItem(k) || '';
      if (v) sessionStorage.removeItem(k);
      return v;
    } catch (e) {
      return '';
    }
  }

  function treeIsLive(tree) {
    return !!(tree && tree.container && document.body.contains(tree.container));
  }

  function applyPendingReveal(tree) {
    if (!tree || !tree.reveal) return;
    var target = consumeReveal(ft());
    if (target) tree.reveal(target);
  }

  function syncTreeFindVisible(tree) {
    var pfx = treePrefix();
    var row = $(pfx + '-tree-find-row');
    if (!row) return;
    var n = 0;
    if (tree && tree.container) {
      n = tree.container.querySelectorAll('li.classic-tree-node[data-value^="e."]').length;
    }
    show(row, n > 0);
  }

  function reloadTree(revealValue, filetype) {
    if (filetype === 'ES' || filetype === 'TS') currentFt = filetype;
    if (revealValue) rememberReveal(revealValue, ft());
    var tree = activeTree();
    if (!treeIsLive(tree)) return;
    tree.load().then(function () {
      syncTreeFindVisible(tree);
      applyPendingReveal(tree);
    });
  }

  function activeTree() {
    var pfx = treePrefix();
    return global.__remicsTreeInstance && global.__remicsTreeInstance[pfx];
  }

  function finishAddTsLink(verified, pdfName, siteKey) {
    var linkparts = (verified || '').split('.');
    if (linkparts.length === 5) {
      var remote = (linkparts[3] || '').toUpperCase();
      var msg = 'You must add a Site Record for the Call Sign ' + remote + '. Would you like to add a site with this call sign?';
      if (window.confirm(msg)) {
        navigatePdfEdit(pdfName, 'panel=sites&new=1&key=' + encodeURIComponent('w.' + pdfName + '.' + remote));
      }
      return;
    }
    if (linkparts.length < 6) {
      alert('Unexpected response from verifySite.');
      return;
    }
    var tree = activeTree();
    if (!tree) return;
    var linkText = '<b>Link To(' + linkparts[3] + ', ' + linkparts[5] + ')' + linkparts[4] + '</b>';
    var linkKey = 'k.' + linkparts[1] + '.' + linkparts[2] + '.' + linkparts[3] + '.' + linkparts[4];
    var baseKey = linkparts[1] + '.' + linkparts[2] + '.' + linkparts[3] + '.' + linkparts[4];
    tree.appendChildNode(siteKey, { Value: linkKey, Text: linkText, ExpandMode: 1 });
    tree.appendChildNode(linkKey, { Value: 'b.' + baseKey, Text: '<b>Antennas</b>', ExpandMode: 1 });
    tree.appendChildNode(linkKey, { Value: 'h.' + baseKey, Text: '<b>Channels</b>', ExpandMode: 1 });
    var linkLi = tree.findNodeLi(linkKey);
    if (linkLi) {
      linkLi.querySelector(':scope > .classic-tree-row').classList.add('classic-tree-selected');
      linkLi.scrollIntoView({ block: 'nearest' });
    }
  }

  function addTsLink(siteKey) {
    var parts = (siteKey || '').split('.');
    if (parts[0] !== 's' || parts.length < 3) {
      alert('Select a site node to add a link.');
      return;
    }
    var pdfName = parts[1];
    var call1 = (parts[2] || '').toUpperCase();
    var remote = prompt('Remote Call Sign');
    if (remote == null) return;
    remote = remote.trim().toUpperCase();
    if (!remote) {
      alert('You must enter a Remote Call Sign.');
      return;
    }
    var band = prompt('Link Band Code');
    if (band == null) return;
    band = band.trim().toUpperCase();
    if (!band) {
      alert('You must enter a Band Code.');
      return;
    }
    var linkKey = 'k.' + pdfName + '.' + call1 + '.' + remote + '.' + band;
    var tree = activeTree();
    if (tree && tree.findNodeLi(linkKey)) {
      alert('A link already exists for ' + call1 + '-' + remote + '-' + band);
      return;
    }
    RemIcsApi.verifyTsLinkSite(linkKey).then(function (r) {
      if (!r.ok) {
        apiAlert(r, 'verifySite failed');
        return;
      }
      finishAddTsLink(r.body, pdfName, siteKey);
    });
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

    RemIcsApi.dsAsmx(servicePath, cfg.method, { project: pc, key: cfg.key }).then(function (r) {
      var body = (r.body != null ? String(r.body) : '');
      if (!r.ok || body.indexOf('ERROR') === 0 || body.toLowerCase().indexOf('timeout') === 0) {
        apiAlert(r, 'Delete failed');
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
      classicPopup(ft() === 'ES' ? 'micshelp/esTree.aspx' : 'micshelp/tsTree.aspx');
      return;
    }
    if (action === 'create') {
      var name = window.prompt('New ' + ft() + ' file name (1-16 letters, digits, underscore):', '');
      if (!name) return;
      name = name.trim();
      if (!/^[A-Za-z0-9_]{1,16}$/.test(name)) {
        alert('Invalid name. Use 1-16 characters: A-Z, a-z, 0-9, _.');
        return;
      }
      RemIcsApi.createTable(name, projectCode(), ftOpts()).then(function (r) {
        if (!r.ok) { apiAlert(r, 'createTable failed'); return; }
        selectFileInTree(name, 'Created ' + name + '. Right-click the file for Edit Contents, or expand Sites for New Site.');
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
    else if (action === 'edit-contents') {
      navigatePdfEdit(fileName);
    }
    else if (action === 'edit-node') {
      value = recordKeyForFolder(value);
      nodeType = value.charAt(0);
      var panel = panelForTreeNode(nodeType, ft());
      navigatePdfEdit(fileName, 'panel=' + panel + '&key=' + encodeURIComponent(value));
    }
    else if (action === 'dup-node') {
      value = recordKeyForFolder(value);
      nodeType = value.charAt(0);
      var dupPanel = panelForTreeNode(nodeType, ft());
      navigatePdfEdit(fileName, 'panel=' + dupPanel + '&dup=1&key=' + encodeURIComponent(value));
    }
    else if (action === 'new-site') {
      navigatePdfEdit(fileName, 'panel=sites&new=1');
    }
    else if (action === 'new-link') {
      addTsLink(value);
    }
    else if (action === 'new-ante') {
      navigatePdfEdit(fileName, 'panel=antes&new=1&key=' + encodeURIComponent(value));
    }
    else if (action === 'new-chan') {
      navigatePdfEdit(fileName, 'panel=chans&new=1&key=' + encodeURIComponent(value));
    }
    else if (action === 'new-azim') {
      navigatePdfEdit(fileName, 'panel=azims&new=1&key=' + encodeURIComponent(value));
    }
    else if (action === 'new-chng') {
      var chngPanel = ft() === 'ES' ? 'ccal' : 'chng';
      navigatePdfEdit(fileName, 'panel=' + chngPanel + '&new=1&key=' + encodeURIComponent(value));
    }
    else if (action === 'new-cloc') {
      navigatePdfEdit(fileName, 'panel=cloc&new=1&key=' + encodeURIComponent(value));
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

    var pendingName = '';
    try {
      var peekReveal = sessionStorage.getItem(revealStoreKey(ft())) || '';
      var peekSel = sessionStorage.getItem('remics-tree-selected-' + ft()) || '';
      var peekVal = peekReveal || peekSel;
      if (peekVal && peekVal.charAt(0) === 'e' && peekVal.indexOf('.') > 0) {
        pendingName = peekVal.substring(2);
      }
    } catch (e) { /* ignore */ }
    setActiveFile(pendingName);

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
    if (refresh) refresh.onclick = function () {
      var expanded = tree.getExpandedValues();
      var selected = tree.getSelectedValue();
      tree.persistExpanded();
      tree.load().then(function () {
        syncTreeFindVisible(tree);
        return tree.restoreExpanded(expanded);
      }).then(function () {
        applyPendingReveal(tree);
        if (selected) {
          var li = tree.findNodeLi(selected);
          if (li) tree.selectLi(li);
        }
      });
    };

    var find = $(pfx + '-tree-find');
    var findGo = $(pfx + '-tree-find-go');
    var findKey = 'remics-tree-find-' + ft();
    if (find) {
      try {
        var savedFind = sessionStorage.getItem(findKey);
        if (savedFind) find.value = savedFind;
      } catch (e) { /* ignore */ }
    }
    function runFind() {
      if (!find) return;
      try { sessionStorage.setItem(findKey, find.value || ''); } catch (e) { /* ignore */ }
      tree.findQuery(find.value);
    }
    if (find) {
      find.addEventListener('keydown', function (ev) {
        if (ev.key === 'Enter' || ev.keyCode === 13) {
          ev.preventDefault();
          runFind();
        }
      });
      find.addEventListener('change', function () {
        try { sessionStorage.setItem(findKey, find.value || ''); } catch (e) { /* ignore */ }
      });
    }
    if (findGo) findGo.onclick = runFind;

    tree.load().then(function () {
      syncTreeFindVisible(tree);
      return tree.restoreExpanded();
    }).then(function () {
      var pending = consumeReveal(ft());
      if (pending) {
        var pendingLi = tree.findNodeLi(pending);
        if (pendingLi) {
          tree.selectLi(pendingLi);
          return;
        }
        if (tree.reveal) return tree.reveal(pending);
      }
      try {
        var sel = sessionStorage.getItem('remics-tree-selected-' + ft());
        if (sel && tree.findNodeLi(sel)) tree.selectLi(tree.findNodeLi(sel));
      } catch (e) { /* ignore */ }
    });
  }

  /* ---------- File wizards ---------- */

  function mountFile(preferredFt) {
    currentFt = detectFileType(preferredFt);
    var route = parseRoute();
    var action = (route.params.action || 'validate').toLowerCase();
    var fileName = (route.params.name || '').trim();
    if (!fileName && window.RemIcsApi && RemIcsApi.lastFile) {
      fileName = RemIcsApi.lastFile(ft()) || '';
    }
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

    var fileRoot = $('ts-file-root') || $('es-file-root') || document.getElementById('view-host');
    if (window.RemIcsApi && RemIcsApi.wireEnterAsTab && fileRoot) {
      RemIcsApi.wireEnterAsTab(fileRoot);
      RemIcsApi.firstFocus(fileRoot, ['imp-name', 'cpy-name', 'pcn-dist']);
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
    var autoStartEs = (ft() === 'ES' && !!fileName);
    show($('panel-validate'), true);
    show($('val-m0'), !autoStartEs);
    show($('val-m1'), autoStartEs);
    show($('val-m2'), false);
    show($('val-m3'), false);
    var cleanfile = fileName + '.txt';

    // TS-only options (absent on ES view)
    var hilo = $('chkHilo');
    var verbose = $('chkVerbose');

    $('cmdValCancel').onclick = goTree;
    $('cmdValReturn').onclick = goTree;
    $('cmdDisplay').onclick = function () { openReportWindow(cleanfile, 'WndValid'); show($('val-m2'), false); show($('val-m3'), true); };
    function goAfterValidate(action) {
      var q = 'name=' + encodeURIComponent(fileName);
      if (action === 'edit') {
        if (global.RemicsApp && RemicsApp.navigate) RemicsApp.navigate('pdf-edit', q + '&filetype=' + encodeURIComponent(ft()));
        else location.hash = '#/pdf-edit?' + q + '&filetype=' + encodeURIComponent(ft());
        return;
      }
      var view = ft() === 'ES' ? 'es-file' : 'ts-file';
      if (global.RemicsApp && RemicsApp.navigate) RemicsApp.navigate(view, 'action=' + action + '&' + q);
      else location.hash = '#/' + view + '?action=' + action + '&' + q;
    }
    function bindValNext(id, action) {
      var el = $(id);
      if (el) el.onclick = function () { goAfterValidate(action); };
    }
    function setValProceedEnabled(on) {
      ['cmdValPcn', 'cmdValPcn2', 'cmdValDbu', 'cmdValDbu2'].forEach(function (id) {
        var el = $(id);
        if (el) el.disabled = !on;
      });
    }
    bindValNext('cmdValEdit', 'edit');
    bindValNext('cmdValEdit2', 'edit');
    bindValNext('cmdValPcn', 'pcn');
    bindValNext('cmdValPcn2', 'pcn');
    bindValNext('cmdValDbu', 'dbupdate');
    bindValNext('cmdValDbu2', 'dbupdate');
    setValProceedEnabled(false);

    function startValidate() {
      if (!fileName) {
        alert('No file selected.');
        return;
      }
      show($('val-m0'), false);
      show($('val-m1'), true);
      var options = ftOpts({
        hilorep: (hilo && hilo.checked) ? '1' : '0',
        verbose: (verbose && verbose.checked) ? '1' : '0'
      });
      RemIcsApi.valFile(fileName, projectCode(), options).then(function (r) {
        show($('val-m1'), false);
        if (!r.ok) {
          apiAlert(r, 'Validate failed');
          show($('val-m0'), true);
          return;
        }
        cleanfile = (r.body || (fileName + '.txt')).replace(/^FILENAME:/, '');
        if (!/\.txt$/i.test(cleanfile)) cleanfile = cleanfile + '.txt';
        var base = cleanfile.replace(/\.txt$/i, '');
        RemIcsApi.fetchReport(reportUrl(base)).then(function (report) {
          var summary = $('valSummary');
          if (!report || !report.ok) {
            if (summary) {
              summary.textContent = 'Validation finished but the report could not be opened. Use Display Results, or Validate again.';
              summary.style.display = '';
            }
            if (window.RemicsHints && RemicsHints.setValidateHelp) {
              RemicsHints.setValidateHelp(true, { reportFailed: true });
            } else {
              var failHint = $('val-extra-hint');
              if (failHint) {
                failHint.textContent = 'The report file was missing or could not be read. PCN and DbUpdate stay closed until you can open Display Results.';
                failHint.style.display = '';
              }
            }
            setValProceedEnabled(false);
            show($('val-m2'), true);
            return;
          }
          var counts = parseValidationSummary(report.body || '');
          if (summary) {
            if (counts) {
              summary.innerHTML = 'Errors: <b>' + counts.errors + '</b> &nbsp;&nbsp; Warnings: <b>' + counts.warnings + '</b>';
              if (window.RemIcsApi && RemIcsApi.sessionSetJson) {
                RemIcsApi.sessionSetJson('remics-last-validate', {
                  filetype: ft(), name: fileName,
                  errors: counts.errors, warnings: counts.warnings,
                  when: new Date().toLocaleString()
                });
              }
            } else if (report.body && /error|cancelled/i.test(report.body)) {
              summary.textContent = 'Errors were detected. Use Display Results to view the report.';
            } else {
              summary.textContent = '';
            }
            summary.style.display = summary.textContent ? '' : 'none';
          }
          var hasErrors = (counts && counts.errors > 0) ||
            (!counts && report.body && /error|cancelled/i.test(report.body));
          if (window.RemicsHints && RemicsHints.setValidateHelp) {
            RemicsHints.setValidateHelp(hasErrors, (!hasErrors && counts && counts.warnings)
              ? { warnings: counts.warnings } : null);
          } else {
            var hint = $('val-extra-hint');
            if (hint) {
              hint.textContent = hasErrors
                ? 'Open Display Results, fix the errors on Edit, then Validate again. PCN and DbUpdate need a clean file.'
                : 'File is clean. Use Edit to change records, PCN to notify operators, or DbUpdate to send to FCSA.';
              hint.style.display = '';
            }
          }
          setValProceedEnabled(!hasErrors);
          show($('val-m2'), true);
        });
      }).catch(function (ex) {
        show($('val-m1'), false);
        show($('val-m0'), true);
        alert('Validate error: ' + (ex.message || ex));
      });
    }
    var cmdVal = $('cmdValidate');
    if (cmdVal) cmdVal.onclick = startValidate;
    // ES has no HiLo / Verbose options  -  begin immediately (TS still waits on those checkboxes).
    if (autoStartEs) startValidate();
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
          apiAlert(r, 'Export failed');
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

  function titleTableName(name) {
    return (ft() === 'ES' ? 'fe_' : 'ft_') + name + '_titl';
  }

  function showMissingImportKeys(up) {
    var kind = ft() === 'TS' ? 'call1(s)' : 'location(s)';
    if (up.missingAnte) {
      alert('The following ' + kind + ' occur in your antenna records, but there is no corresponding site in your file:\n ' + up.missingAnte);
    }
    if (up.missingAzim) {
      alert('The following ' + kind + ' occur in your azimuth records, but there is no corresponding site in your file:\n ' + up.missingAzim);
    }
    if (up.missingChan) {
      alert('The following ' + kind + ' occur in your channel records, but there is no corresponding site in your file:\n ' + up.missingChan);
    }
    alert('Your import was cancelled. Please edit the file and try again');
  }

  function confirmOverwriteIfExists(name) {
    return RemIcsApi.tableExists(titleTableName(name)).then(function (r) {
      if (!r.ok) {
        apiAlert(r, 'Duplicate check failed');
        return false;
      }
      var body = String(r.body != null ? r.body : '0').replace(/^\s+|\s+$/g, '');
      if (/^timeout/i.test(body)) {
        apiAlert(r, 'Duplicate check failed');
        return false;
      }
      if (body === '0' || body === '') return true;
      var ans = window.confirm('There is already a Data File name ' + name + '.\n  Do you wish to overwrite this file?');
      if (!ans) {
        alert('Import Cancelled.  Please change the name of the Mics File Name to continue.');
        return false;
      }
      return RemIcsApi.killTable(name, projectCode(), ftOpts()).then(function (k) {
        if (!k.ok) {
          apiAlert(k, 'Delete existing file failed');
          return false;
        }
        return true;
      });
    });
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

    function resetImportForm() {
      show($('imp-m1'), false);
      show($('imp-m2'), false);
      show($('imp-m0'), true);
    }

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
      confirmOverwriteIfExists(name).then(function (go) {
        if (!go) {
          resetImportForm();
          return null;
        }
        return RemIcsApi.uploadTxt(name, input.files[0], { filetype: ft() });
      }).then(function (up) {
        if (!up) return null;
        if (!up.ok) {
          resetImportForm();
          if (up.code === 'MISSING') showMissingImportKeys(up);
          else alert(up.error || 'Upload failed');
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
          apiAlert(r, 'Import failed');
          return;
        }
        setActiveFile(name);
        persistTreeFileSelection(name);
        show($('imp-m3'), true);
      }).catch(function (ex) {
        resetImportForm();
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
      show($('del-m0'), false);
      show($('del-m1'), true);
      RemIcsApi.killTable(fileName, projectCode(), ftOpts()).then(function (r) {
        show($('del-m1'), false);
        if (!r.ok) {
          apiAlert(r, 'Delete failed');
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
    var esOnScreen = (ft() === 'ES');
    show($('panel-dbupdate'), true);
    show($('dbu-m0'), false);
    show($('dbu-m1'), false);
    show($('dbu-m2'), false);
    var gateEl = $('dbu-gate');
    if (gateEl) gateEl.textContent = 'Checking validation status...';

    function showDbuDone(text, showDisplay) {
      var msg = $('dbu-done-msg');
      if (msg) msg.textContent = text || '';
      var disp = $('cmdDbuDisplay');
      if (disp) disp.hidden = !showDisplay;
      if (gateEl) gateEl.textContent = '';
      show($('dbu-m0'), false);
      show($('dbu-m1'), false);
      show($('dbu-m2'), true);
    }

    $('cmdDbuCancel').onclick = goTree;
    $('cmdDbuReturn').onclick = goTree;
    var dbuHelp = $('cmdDbuHelp');
    if (dbuHelp) dbuHelp.onclick = function () { classicPopup('micshelp/DbUpdate.aspx'); };
    $('cmdDbuDisplay').onclick = function () { openReportWindow(fileName, 'WndUpdate'); };

    RemIcsApi.dbUpdateGate(fileName, ftOpts()).then(function (gate) {
      if (!gate.ok) {
        var gerr = gate.error || 'Unable to check validation status.';
        if (esOnScreen) { showDbuDone(gerr); return; }
        alert(gerr);
        goTree();
        return;
      }
      if (!gate.allowTransfer) {
        var blocked = gate.errortext || 'This file cannot be transferred for update.';
        if (esOnScreen) { showDbuDone(blocked); return; }
        alert(blocked);
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
            showDbuDone(r.error || body || 'Export for update failed.', true);
            setTimeout(function () { openReportWindow(fileName, 'WndUpdate'); }, 1000);
            return;
          }
          return RemIcsApi.dbUpdateNotify(fileName, ftOpts({ userFcsa: 'F' })).then(function (n) {
            var text = (n && n.message) || 'Transfer for database update complete.';
            if (n && !n.ok) text = n.error || 'Notify failed after export.';
            else if (n && n.emailSent === false) {
              text = text + ' (email may not have been delivered  -  see extractlogs)';
            }
            if (!esOnScreen) alert(text);
            showDbuDone(text, false);
          });
        }).catch(function (ex) {
          var xerr = 'Database update error: ' + (ex.message || ex);
          if (esOnScreen) { showDbuDone(xerr); return; }
          show($('dbu-m1'), false);
          show($('dbu-m0'), true);
          btn.disabled = false;
          alert(xerr);
        });
      };
    }).catch(function (ex) {
      var xerr = 'Database update gate error: ' + (ex.message || ex);
      if (esOnScreen) { showDbuDone(xerr); return; }
      alert(xerr);
      goTree();
    });
  }

  function mountPcn(fileName) {
    show($('panel-pcn'), true);
    show($('pcn-m0'), false);
    show($('pcn-m1'), false);
    show($('pcn-m-empty'), false);
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

    function pcnHelpOpen() {
      classicPopup(ft() === 'ES' ? 'micshelp/PcnES.aspx' : 'micshelp/PcnTS.aspx');
    }
    function pcnDiscardThen(next) {
      if (state.tmpdir && window.RemIcsApi && RemIcsApi.pcnDiscard) {
        RemIcsApi.pcnDiscard(state.tmpdir).catch(function () { /* ignore */ }).then(next);
        return;
      }
      next();
    }
    function pcnCancel() {
      pcnDiscardThen(goTree);
    }
    $('cmdPcnCancel0').onclick = pcnCancel;
    $('cmdPcnCancel2').onclick = pcnCancel;
    $('cmdPcnReturn').onclick = goTree;
    var pcnHelp = $('cmdPcnHelp');
    if (pcnHelp) pcnHelp.onclick = pcnHelpOpen;
    var pcnHelp2 = $('cmdPcnHelp2');
    if (pcnHelp2) pcnHelp2.onclick = pcnHelpOpen;
    var emptyBack = $('cmdPcnEmptyBack');
    if (emptyBack) emptyBack.onclick = pcnCancel;
    var delEmail = $('cmdPcnDelEmail');
    if (delEmail) {
      delEmail.onclick = function () {
        var sel = $('pcn-emails');
        if (!sel) return;
        for (var i = sel.options.length - 1; i >= 0; i--) {
          if (sel.options[i].selected) sel.remove(i);
        }
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
          var html = '<table align="center" border="1" cellspacing="0" cellpadding="2">' +
            '<tr><td class="h">&nbsp;Operator&nbsp;</td><td class="h">&nbsp;Name&nbsp;</td></tr>';
          ops.operators.forEach(function (o) {
            html += '<tr><td class="az">' + String(o.oper || '').replace(/</g, '&lt;') +
              '</td><td class="az">' + String(o.name || o.ultrixid || '').replace(/</g, '&lt;') +
              '</td></tr>';
          });
          html += '</table>';
          box.innerHTML = html;
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
      var miss = $('pcn-missing-email');
      if (miss) {
        var n = (ops.missingEmails || []).length;
        if (n) {
          miss.textContent = 'FCSA was notified that ' + n +
            ' user(s) have no email and will not receive this PCN. You were copied.';
          miss.hidden = false;
        } else {
          miss.textContent = '';
          miss.hidden = true;
        }
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
          var emptyMsg = $('pcn-empty-msg');
          if (emptyMsg) emptyMsg.textContent = ops.message || 'No companies within the coordination distance.';
          show($('pcn-m1'), false);
          show($('pcn-m-empty'), true);
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
      var mq = $('pcn-marquee');
      if (mq) mq.textContent = 'SCANNING';
      RemIcsApi.pcnScan(fileName, projectCode(), ftOpts({ cDist: d })).then(function (r) {
        if (!r.ok) {
          show($('pcn-m1'), false);
          if (r.errorReportFile) {
            apiAlert(r, 'pcnscan errors  -  opening report.');
            openReportWindow(r.errorReportFile, 'WndPcnErr');
          } else {
            apiAlert(r, 'pcnscan failed');
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
          to.push(opt.value);
        });
      }
      if (!to.length) {
        alert('There are no remaining recipients. Add or keep at least one email address.');
        return;
      }
      var kml = $('pcn-kml');
      var btn = $('cmdPcnSend');
      btn.disabled = true;
      show($('pcn-m2'), false);
      show($('pcn-m1'), true);
      var mqSend = $('pcn-marquee');
      if (mqSend) mqSend.textContent = 'EXPORTING';

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
          apiAlert(r, 'PCN send failed');
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
          apiAlert(r, 'Copy failed');
          show($('cpy-m0'), true);
          return;
        }
        setActiveFile(newName);
        persistTreeFileSelection(newName);
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
    getFileType: ft,
    reloadTree: reloadTree,
    addTsLink: addTsLink
  };
})(window);
