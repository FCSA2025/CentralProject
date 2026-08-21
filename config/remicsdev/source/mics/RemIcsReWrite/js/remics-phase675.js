// RemIcsReWrite Phase 6.75  -  CASEDET, File Open, SDF, DS-SDF, Fee, Bulk Print, Aux Eng.
(function (global) {
  function apiErr(r, fb) {
    return (global.RemIcsApi && RemIcsApi.apiErr) ? RemIcsApi.apiErr(r, fb) : ((r && (r.error || r.body)) || fb || 'Request failed.');
  }
  function $(id) { return document.getElementById(id); }
  function show(el, on) {
    if (!el) return;
    el.hidden = !on;
    el.style.display = on ? '' : 'none';
  }
  function rewriteRoot() {
    return (global.RemIcsApi && RemIcsApi.micsRoot)
      ? RemIcsApi.micsRoot() + 'RemIcsReWrite/'
      : '/mics/RemIcsReWrite/';
  }
  function micsRoot() {
    return (global.RemIcsApi && RemIcsApi.micsRoot) ? RemIcsApi.micsRoot() : '/mics/';
  }
  function parseRoute() {
    var hash = (location.hash || '').replace(/^#\/?/, '');
    var parts = hash.split('?');
    var params = {};
    if (parts[1]) {
      parts[1].split('&').forEach(function (pair) {
        var kv = pair.split('=');
        params[decodeURIComponent(kv[0] || '')] = decodeURIComponent(kv[1] || '');
      });
    }
    return { view: parts[0] || '', params: params };
  }
  function projectCode() {
    var sel = $('project-select');
    if (sel && sel.value) return sel.value;
    var s = (global.RemicsApp && RemicsApp.getSession && RemicsApp.getSession()) || {};
    return s.project || (global.REMICS_SHELL && REMICS_SHELL.project) || '';
  }

  /* ---- CASEDET ---- */
  var CASEDET_TITLES = {
    'TSES-csv': 'TSIP TS-ES CSV Report',
    'TSTS-csv': 'TSIP TS-TS CSV Report',
    'TSES-kml': 'TSIP TS-ES KML Report',
    'TSTS-kml': 'TSIP TS-TS KML Report'
  };
  var CASEDET_HELP = {
    'TSES-csv': 'micshelp/CASEDETTSESsel.aspx',
    'TSTS-csv': 'micshelp/CASEDETTSTSsel.aspx',
    'TSES-kml': 'micshelp/CASEDETTSESkmlsel.aspx',
    'TSTS-kml': 'micshelp/CASEDETTSTSkmlsel.aspx'
  };
  function mountCasedet() {
    var status = $('casedet-status');
    var sel = $('casedet-runs');
    var route = parseRoute();
    var lockedMode = (route.params.mode || '').toUpperCase();
    var lockedKind = (route.params.kind || '').toLowerCase();
    if (lockedMode !== 'TSTS') lockedMode = lockedMode === 'TSES' ? 'TSES' : '';
    if (lockedKind !== 'kml' && lockedKind !== 'csv') lockedKind = '';
    if ($('casedet-mode') && lockedMode) $('casedet-mode').value = lockedMode;
    if ($('casedet-mode-row')) show($('casedet-mode-row'), !lockedMode);
    function mode() {
      return ($('casedet-mode') && $('casedet-mode').value) || lockedMode || 'TSES';
    }
    function kind() { return lockedKind || 'csv'; }
    function key() { return mode() + '-' + kind(); }
    function setStatus(msg) { if (status) status.textContent = msg || ''; }
    if ($('casedet-title')) {
      $('casedet-title').textContent = CASEDET_TITLES[key()] || 'TSIP CASEDET Extract';
    }
    if ($('casedet-hint')) {
      $('casedet-hint').textContent = kind() === 'kml'
        ? 'Select a run, then Global (one combined file) or Case (one file per case). KML files are e-mailed.'
        : 'Select a TSIP run to build the CSV. Download buttons appear when a report is created.';
    }
    function selected() {
      if (!sel || sel.selectedIndex < 0) return null;
      var opt = sel.options[sel.selectedIndex];
      if (!opt || !opt.value) return null;
      var parts = opt.value.split('^');
      return { parm: parts[0] || '', run: parts[1] || '', label: opt.textContent };
    }
    function showDownloads(files) {
      var host = $('casedet-downloads');
      if (!host) return;
      host.innerHTML = '';
      if (!files || !files.length) { show(host, false); return; }
      files.forEach(function (name) {
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'bt';
        btn.textContent = name.indexOf('et_') === 0 ? 'Download ES-TS Report'
          : (name.indexOf('te_') === 0 ? 'Download TS-ES Report' : 'Download ' + name);
        btn.onclick = function () {
          window.open(micsRoot() + 'RemIcsReWrite/casedet.ashx?action=download&file=' +
            encodeURIComponent(name), 'WndCaseDetDl',
            'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,status=yes');
        };
        host.appendChild(btn);
        host.appendChild(document.createElement('br'));
      });
      show(host, true);
    }
    function generate(reptype) {
      var row = selected();
      if (!row) { alert('Select a TSIP run.'); return; }
      setStatus('Generating...');
      show($('casedet-downloads'), false);
      RemIcsApi.casedet('generate', {
        mode: mode(),
        kind: kind(),
        parm: row.parm,
        run: row.run,
        reptype: reptype || 'G'
      }).then(function (r) {
        if (!r || !r.ok) {
          setStatus('');
          alert((r && r.error) || 'Generate failed');
          return;
        }
        if (kind() === 'kml') {
          setStatus(r.message || '');
          if (r.message) { /* keep */ }
          return;
        }
        var files = r.files || [];
        if (!files.length) {
          setStatus('');
          alert(r.error || r.message || 'No reports were created');
          return;
        }
        setStatus((r.message || 'CSV created') + (files.length ? ': ' + files.join(', ') : ''));
        showDownloads(files);
        if (mode() === 'TSTS' && files[0]) {
          window.open(micsRoot() + 'RemIcsReWrite/casedet.ashx?action=download&file=' +
            encodeURIComponent(files[0]), 'WndCaseDetDl',
            'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,status=yes');
        }
      }).catch(function (ex) {
        setStatus('');
        alert(ex.message || String(ex));
      });
    }
    function load() {
      if (!sel) return;
      sel.innerHTML = '';
      show($('casedet-kml-choice'), false);
      show($('casedet-downloads'), false);
      setStatus('Loading...');
      RemIcsApi.casedet('list', { mode: mode() }).then(function (r) {
        if (!r.ok) { setStatus(r.error || 'Failed'); return; }
        var runs = r.runs || [];
        if (!runs.length) {
          setStatus('There were no TSIP tables found.');
          return;
        }
        runs.forEach(function (row) {
          var opt = document.createElement('option');
          opt.value = row.parm + '^' + row.run;
          opt.textContent = row.label;
          sel.appendChild(opt);
        });
        sel.selectedIndex = -1;
        setStatus('');
      });
    }
    if (sel) {
      sel.onchange = function () {
        if (kind() === 'kml') {
          show($('casedet-kml-choice'), !!selected());
          return;
        }
        generate();
      };
    }
    if ($('casedet-mode')) $('casedet-mode').onchange = load;
    if ($('casedet-kml-g')) $('casedet-kml-g').onclick = function () { generate('G'); };
    if ($('casedet-kml-c')) $('casedet-kml-c').onclick = function () { generate('C'); };
    if ($('casedet-help')) {
      $('casedet-help').onclick = function () {
        window.open(micsRoot() + (CASEDET_HELP[key()] || 'micshelp/CASEDETTSESsel.aspx'), 'WndHelp',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
      };
    }
    if (window.RemicsHints && RemicsHints.bindForm) {
      RemicsHints.bindForm($('view-host'), 'casedet', null);
    }
    load();
  }

  /* ---- File Open ---- */
  function mountFileOpen() {
    var status = $('file-open-status');
    if (window.RemIcsApi && RemIcsApi.sessionGet) {
      var lastType = RemIcsApi.sessionGet('remics-last-fileopen-type');
      var lastName = RemIcsApi.sessionGet('remics-last-fileopen-name');
      if (lastType && $('fo-type')) $('fo-type').value = lastType;
      if (lastName && $('fo-name')) $('fo-name').value = lastName;
    }
    if (window.RemIcsApi && RemIcsApi.wireEnterAsTab) {
      RemIcsApi.wireEnterAsTab($('view-host') || document.body);
      RemIcsApi.firstFocus($('view-host'), ['fo-name']);
    }
    function loadList() {
      var type = $('fo-type').value;
      status.textContent = 'Loading...';
      var p;
      if (type === 'TS' || type === 'ES') {
        p = RemIcsApi.filesList(type);
      } else if (type === 'TsipParm') {
        p = RemicsTsipApi.tsipTree().then(function (r) {
          var names = (r.body || '').toString().split(':').filter(Boolean);
          return { ok: r.ok, files: names.map(function (n) { return { name: n }; }) };
        });
      } else {
        p = RemIcsApi.sdfFiles(type);
      }
      p.then(function (data) {
        if (!data.ok) {
          status.textContent = (RemIcsApi.friendlyAsmxError && data.error)
            ? RemIcsApi.friendlyAsmxError(data.error) : (data.error || 'Failed');
          return;
        }
        var files = data.files || [];
        var ul = $('fo-files');
        var dl = $('fo-list');
        ul.innerHTML = '';
        dl.innerHTML = '';
        files.forEach(function (f) {
          var n = f.name || f;
          var opt = document.createElement('option');
          opt.value = n;
          dl.appendChild(opt);
          var li = document.createElement('li');
          var a = document.createElement('a');
          a.href = '#';
          a.textContent = n;
          a.onclick = function (ev) {
            ev.preventDefault();
            $('fo-name').value = n;
          };
          li.appendChild(a);
          ul.appendChild(li);
        });
        status.textContent = files.length + ' file(s)';
      });
    }
    $('fo-type').onchange = loadList;
    $('fo-refresh').onclick = loadList;
    $('fo-open').onclick = function () {
      var type = $('fo-type').value;
      var name = ($('fo-name').value || '').trim();
      if (!name) { alert('Enter or select a name.'); return; }
      if (window.RemIcsApi && RemIcsApi.sessionSet) {
        RemIcsApi.sessionSet('remics-last-fileopen-type', type);
        RemIcsApi.sessionSet('remics-last-fileopen-name', name);
      }
      if (type === 'TS') {
        if (global.RemicsApp) RemicsApp.setActiveFile('TS', name);
        RemicsApp.navigate('pdf-edit', 'name=' + encodeURIComponent(name) + '&filetype=TS');
      } else if (type === 'ES') {
        if (global.RemicsApp) RemicsApp.setActiveFile('ES', name);
        RemicsApp.navigate('pdf-edit', 'name=' + encodeURIComponent(name) + '&filetype=ES');
      } else if (type === 'TsipParm') {
        RemicsApp.navigate('tsip-parm');
      } else {
        RemicsApp.navigate('sdf-tree', 'type=' + encodeURIComponent(type) + '&name=' + encodeURIComponent(name));
      }
    };
    loadList();
  }

  /* ---- SDF tree ---- */
  var SDF_TYPE_LONG = {
    Ante: 'Antenna', Band: 'Band', Ctx: 'CTX', Eqpt: 'Equipment', Oper: 'Operator',
    Plan: 'Spectrum Plan', Rout: 'Route', Note: 'Note', Towr: 'Tower', Town: 'Town', Traf: 'Traffic'
  };

  var SDF_SEARCH = {
    Ante: { title: 'SDF Antenna Search and Extract', fields: [
      { col: 'acode', label: 'Antenna Code' }, { col: 'amanu', label: 'Manufacturer' },
      { col: 'adesc', label: 'Description' }, { col: 'again', label: 'Antenna Gain' }
    ]},
    Band: { title: 'SDF Band Search and Extract', fields: [
      { col: 'bndcde', label: 'Band Code' }, { col: 'blo', label: 'Low Frequency' },
      { col: 'bmidf', label: 'Mid Frequency' }, { col: 'bhi', label: 'High Frequency' },
      { col: 'badj', label: 'Adjacent Band' }
    ]},
    Ctx: { title: 'SDF CTX Pattern Search and Extract', fields: [
      { col: 'tfcr', label: 'TFCR' }, { col: 'tfci', label: 'TFCI' },
      { col: 'rxeqp', label: 'Rx Equipment' }, { col: 'ctxdesc', label: 'Description' }
    ]},
    Eqpt: { title: 'SDF Equipment Search and Extract', fields: [
      { col: 'ecode', label: 'Equipment Code' }, { col: 'emanu', label: 'Manufacturer' },
      { col: 'emodel', label: 'Model' }, { col: 'edesc', label: 'Description' }
    ]},
    Oper: { title: 'SDF Operator Search and Extract', fields: [
      { col: 'oper', label: 'Operator Code' }, { col: 'nameop', label: 'Operator Name' },
      { col: 'city', label: 'City' }, { col: 'prstat', label: 'Province/State' }
    ]},
    Plan: { title: 'SDF Spectrum Plan Search and Extract', fields: [
      { col: 'sband', label: 'Spectrum Band' }, { col: 'splan', label: 'Spectrum Plan' }
    ]},
    Rout: { title: 'SDF Route Search and Extract', fields: [
      { col: 'rtname', label: 'Route Name' }, { col: 'rcomp', label: 'Route Component' },
      { col: 'routnumb', label: 'Route Number' }
    ]},
    Note: { title: 'SDF Note Search and Extract', fields: [
      { col: 'oper', label: 'Operator Code' }, { col: 'nonum', label: 'Note Number' },
      { col: 'note', label: 'Note Text' }
    ]},
    Towr: { title: 'SDF Tower Search and Extract', fields: [
      { col: 'twcode', label: 'Tower Code' }, { col: 'twdesc', label: 'Description' }
    ]},
    Town: { title: 'SDF Town Search and Extract', fields: [
      { col: 'call1', label: 'Call Sign' }, { col: 'atwrno', label: 'Tower No' },
      { col: 'oper', label: 'Operator Code' }
    ]},
    Traf: { title: 'SDF Traffic Search and Extract', fields: [
      { col: 'trafcode', label: 'Traffic Code' }, { col: 'ecode', label: 'Equipment Code' },
      { col: 'trdesc', label: 'Description' }
    ]}
  };

  function sdfTypeLong(type) {
    return SDF_TYPE_LONG[type] || type;
  }

  function mountSdfTree() {
    var route = parseRoute();
    var type = route.params.type || $('sdf-type').value || 'Ante';
    if (!route.params.type && window.RemIcsApi && RemIcsApi.sessionGet) {
      type = RemIcsApi.sessionGet('remics-last-sdf-type') || type;
    }
    $('sdf-type').value = type;
    var longEl = $('sdf-type-long');
    if (longEl) longEl.textContent = sdfTypeLong(type);
    var status = $('sdf-tree-status');
    var host = $('sdf-tree-host');
    var treeMount = null;
    var ctxMenu = null;

    function hideMenu() {
      if (ctxMenu) ctxMenu.hidden = true;
    }

    function showMenu(ev, items, node) {
      hideMenu();
      if (!items.length) return;
      if (!ctxMenu) {
        ctxMenu = document.createElement('div');
        ctxMenu.className = 'classic-tree-context';
        document.body.appendChild(ctxMenu);
      }
      ctxMenu.innerHTML = '';
      items.forEach(function (it) {
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'classic-tree-context-item';
        btn.textContent = it.label;
        btn.onclick = function (e) {
          e.stopPropagation();
          hideMenu();
          it.action(node);
        };
        ctxMenu.appendChild(btn);
      });
      ctxMenu.hidden = false;
      ctxMenu.style.left = ev.pageX + 'px';
      ctxMenu.style.top = ev.pageY + 'px';
    }

    function goSdfEdit(sdfType, sdfName, key, flags) {
      flags = flags || {};
      if (!canEditType(sdfType)) {
        alert('Unknown SDF type.');
        return;
      }
      var q = 'type=' + encodeURIComponent(sdfType) + '&name=' + encodeURIComponent(sdfName);
      if (key) q += '&key=' + encodeURIComponent(key);
      if (flags.isNew) q += '&new=1';
      if (flags.isDup) q += '&dup=1';
      if (window.RemIcsApi && RemIcsApi.sessionSet) {
        RemIcsApi.sessionSet('remics-last-sdf-type', sdfType);
        RemIcsApi.sessionSet('remics-last-sdf-name', sdfName);
        if (key) RemIcsApi.sessionSet('remics-last-sdf-key', key);
      }
      if (global.RemicsApp) RemicsApp.navigate('sdf-edit', q);
      else location.hash = '#/sdf-edit?' + q;
    }

    function canEditType(t) {
      return t === 'Ante' || t === 'Band' || t === 'Eqpt' || t === 'Oper' || t === 'Note'
        || t === 'Traf' || t === 'Rout' || t === 'Towr' || t === 'Town' || t === 'Ctx' || t === 'Plan';
    }

    function sdfFileActions(node) {
      var name = node.sdf || node.text;
      var items = [];
      if (canEditType(type)) {
        items.push({ label: 'New record', action: function () { goSdfEdit(type, name, '', { isNew: true }); }});
      }
      items.push(
        { label: 'Validate', action: function () {
          RemIcsApi.valFile(name, projectCode(), { filetype: type }).then(function (r) {
            status.textContent = r.ok ? 'Validate OK' : apiErr(r, 'Validate failed');
          });
        }},
        { label: 'Export', action: function () {
          RemIcsApi.exportTable(name, projectCode(), { filetype: type }).then(function (r) {
            status.textContent = r.ok ? 'Export OK' : apiErr(r, 'Export failed');
          });
        }},
        { label: 'Delete file', action: function () {
          if (!window.confirm('Delete SDF file ' + name + '?')) return;
          RemIcsApi.killTable(name, projectCode(), { filetype: type }).then(function (r) {
            if (!r.ok) { alert(apiErr(r, 'Delete failed')); return; }
            load();
          });
        }},
        { label: 'Copy', action: function () {
          var newName = window.prompt('Copy ' + name + ' as:', name + '_2');
          if (!newName) return;
          RemIcsApi.copyTable(name, newName.trim(), projectCode(), { filetype: type }).then(function (r) {
            status.textContent = r.ok ? 'Copied' : apiErr(r, 'Copy failed');
            if (r.ok) load();
          });
        }}
      );
      return items;
    }

    function load() {
      type = $('sdf-type').value;
      if (longEl) longEl.textContent = sdfTypeLong(type);
      if (!window.RemicsSdfTree) {
        if (status) status.textContent = 'SDF tree module not loaded.';
        return;
      }
      treeMount = new RemicsSdfTree.TreeMount('sdf-tree-host', type, {
        onStatus: function (msg) { if (status) status.textContent = msg || ''; },
        onSelect: function (node) {
          if (status && node.value && node.value.indexOf('d^') === 0) {
            status.textContent = node.text + ' (' + node.key + ')';
          }
        },
        onActivate: function (node) {
          var val = node.value || '';
          if (val.indexOf('d^') === 0 && canEditType(type) && node.sdf && node.key) {
            goSdfEdit(type, node.sdf, node.key);
          }
        },
        onContext: function (ev, node) {
          var val = node.value || '';
          if (val === 'HELP') {
            showMenu(ev, [{ label: 'Open help', action: function () {
              window.open(micsRoot() + 'micshelp/separatefiles/sdf' + type + '.aspx', 'WndHelp',
                'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
            }}], node);
          } else if (val === 'n.new') {
            showMenu(ev, [{ label: 'Create new file', action: function () { $('sdf-create').click(); }}], node);
          } else if (val.indexOf('e^') === 0) {
            showMenu(ev, sdfFileActions(node), node);
          } else if (val.indexOf('d^') === 0) {
            var delFn = (treeMount && treeMount.cfg && treeMount.cfg.deleteFn) || 'delete_ante';
            var recItems = [];
            if (canEditType(type) && node.sdf && node.key) {
              recItems.push({ label: 'Edit', action: function () { goSdfEdit(type, node.sdf, node.key); }});
              recItems.push({ label: 'Duplicate', action: function () { goSdfEdit(type, node.sdf, node.key, { isDup: true }); }});
            }
            recItems.push({ label: 'Delete record', action: function () {
              if (!window.confirm('Delete ' + node.text + '?')) return;
              RemIcsApi.sdfTreeCall(delFn, { key: node.value }).then(function (r) {
                var body = (r.body || '').toString();
                if (!r.ok || body.indexOf('ERROR') === 0 || body.toLowerCase().indexOf('timeout') === 0) {
                  alert(apiErr(r, 'Delete failed'));
                  return;
                }
                load();
              }).catch(function (ex) {
                alert('Delete error: ' + (ex.message || ex));
              });
            }});
            showMenu(ev, recItems, node);
          }
        }
      });
      if (status) status.textContent = 'Loading...';
      treeMount.loadRoot().then(function () {
        var findRow = $('sdf-tree-find-row');
        var fileCount = 0;
        if (treeMount.roots) {
          treeMount.roots.forEach(function (n) { if (n && n.sdf) fileCount++; });
        }
        show(findRow, fileCount > 0);
        var want = route.params.name || (window.RemIcsApi && RemIcsApi.sessionGet && RemIcsApi.sessionGet('remics-last-sdf-name')) || '';
        if (want && treeMount.roots) {
          var fileNode = null;
          treeMount.roots.forEach(function (n) {
            if (n.sdf && n.sdf.toUpperCase() === want.toUpperCase()) fileNode = n;
          });
          if (fileNode) return treeMount.expand(fileNode);
        }
      }).then(function () {
        if (status) status.textContent = canEditType(type)
          ? 'Right-click for actions · double-click a record to edit'
          : 'Right-click for actions · expand files for records';
      });
    }

    $('sdf-type').onchange = function () {
      if (window.RemIcsApi && RemIcsApi.sessionSet) {
        RemIcsApi.sessionSet('remics-last-sdf-type', $('sdf-type').value);
      }
      load();
    };
    var find = $('sdf-tree-find');
    var findGo = $('sdf-tree-find-go');
    var findKey = 'remics-tree-find-SDF';
    if (find) {
      try {
        var savedFind = sessionStorage.getItem(findKey);
        if (savedFind) find.value = savedFind;
      } catch (e) { /* ignore */ }
    }
    function runSdfFind() {
      if (!find || !treeMount || !treeMount.findQuery) return;
      try { sessionStorage.setItem(findKey, find.value || ''); } catch (e) { /* ignore */ }
      treeMount.findQuery(find.value).then(function () {
        if (status && treeMount.handlers && !status.textContent) { /* keep tree status */ }
      });
    }
    if (find) {
      find.addEventListener('keydown', function (ev) {
        if (ev.key === 'Enter' || ev.keyCode === 13) {
          ev.preventDefault();
          runSdfFind();
        }
      });
    }
    if (findGo) findGo.onclick = runSdfFind;
    $('sdf-refresh').onclick = load;
    if ($('sdf-help')) {
      $('sdf-help').onclick = function () {
        window.open(micsRoot() + 'micshelp/separatefiles/sdf' + $('sdf-type').value + '.aspx', 'WndHelp',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
      };
    }
    $('sdf-create').onclick = function () {
      var name = window.prompt('New SDF ' + $('sdf-type').value + ' name (1-16 A-Za-z0-9_):', '');
      if (!name) return;
      name = name.trim();
      if (!/^[A-Za-z0-9_]{1,16}$/.test(name)) { alert('Invalid name.'); return; }
      RemIcsApi.createTable(name, projectCode(), { filetype: $('sdf-type').value }).then(function (r) {
        if (!r.ok) { alert(apiErr(r, 'create failed')); return; }
        load();
      });
    };
    document.addEventListener('click', hideMenu);
    load();
  }

  var SDF_SAVE = {
    Ante: { insert: 'InsertAnte', checkDup: 'AppendDupAnte', deleteDup: 'DeleteAnte', subcount: 60 },
    Band: { insert: 'InsertBand', checkDup: 'AppendDupBand', deleteDup: 'DeleteBand', subcount: 60 },
    Ctx: { insert: 'InsertCtx', checkDup: 'AppendDupCtx', deleteDup: 'DeleteCtx', subcount: 60, insert2: 'InsertCtxd', deleteDup2: 'DeleteCtxd' },
    Eqpt: { insert: 'InsertEqpt', checkDup: 'AppendDupEqpt', deleteDup: 'DeleteEqpt', subcount: 60 },
    Oper: { insert: 'InsertOper', checkDup: 'AppendDupOper', deleteDup: 'DeleteOper', subcount: 60 },
    Plan: { insert: 'InsertPlan', checkDup: 'AppendDupPlan', deleteDup: 'DeletePlan', subcount: 60, insert2: 'InsertPlnd', deleteDup2: 'DeletePlnd' },
    Rout: { insert: 'InsertRout', checkDup: 'AppendDupRout', deleteDup: 'DeleteRout', subcount: 60 },
    Note: { insert: 'InsertNote', checkDup: 'AppendDupNote', deleteDup: 'DeleteNote', subcount: 60 },
    Towr: { insert: 'InsertTowr', checkDup: 'AppendDupTowr', deleteDup: 'DeleteTowr', subcount: 60 },
    Town: { insert: 'InsertTown', checkDup: 'AppendDupTown', deleteDup: 'DeleteTown', subcount: 60 },
    Traf: { insert: 'InsertTraf', checkDup: 'AppendDupTraf', deleteDup: 'DeleteTraf', subcount: 60 }
  };

  var dsSdfState = { keyCol: 'acode', rows: [], type: 'Ante' };

  function chunkKeyList(keys, subcount) {
    var chunks = [];
    var batch = [];
    keys.forEach(function (k, i) {
      batch.push(k);
      if (batch.length >= subcount) {
        chunks.push(batch.join(','));
        batch = [];
      }
    });
    if (batch.length) chunks.push(batch.join(','));
    return chunks;
  }

  function populateSdfSelect(type) {
    return RemIcsApi.sdfFiles(type).then(function (data) {
      var sel = $('dssdf-exist');
      if (!sel) return;
      sel.innerHTML = '';
      (data.files || []).forEach(function (f) {
        var opt = document.createElement('option');
        opt.value = f.name;
        opt.textContent = f.name;
        sel.appendChild(opt);
      });
    });
  }

  function saveDsSdf(setStatus) {
    var cfg = SDF_SAVE[dsSdfState.type] || SDF_SAVE.Ante;
    var keys = [];
    document.querySelectorAll('#dssdf-table input[data-kind=row]').forEach(function (c) {
      if (c.checked) keys.push(c.getAttribute('data-key'));
    });
    if (!keys.length) { alert('Select at least one row to save.'); return; }
    var mode = (document.querySelector('input[name=dssdf-save-mode]:checked') || {}).value || 'new';
    var sdfname = mode === 'new' ? ($('dssdf-newname').value || '').trim() : ($('dssdf-exist').value || '').trim();
    if (!/^[A-Za-z0-9_]{1,16}$/.test(sdfname)) {
      alert('Enter a valid SDF name (1-16 A-Za-z0-9_).');
      return;
    }
    var dupMode = $('dssdf-dup').value;
    var pc = projectCode();
    var keylist = keys.join(',');
    setStatus('Saving...');

    var chain = Promise.resolve();
    if (mode === 'new') {
      chain = RemIcsApi.createTable(sdfname, pc, { filetype: dsSdfState.type }).then(function (r) {
        if (!r.ok) throw new Error(r.error || r.body || 'createTable failed');
      });
    }

    chain.then(function () {
      return RemIcsApi.dsAsmx('Tdssdf/TwsdsSDF.asmx', cfg.checkDup, { name: sdfname, keylist: keylist });
    }).then(function (dup) {
      var duplists = (dup && dup.body) ? String(dup.body).trim() : '';
      if (duplists && dupMode === 'over') {
        return chunkKeyList(duplists.split(',').filter(Boolean), cfg.subcount).reduce(function (p, chunk) {
          return p.then(function () {
            return RemIcsApi.dsAsmx('Tdssdf/TwsdsSDF.asmx', cfg.deleteDup, { name: sdfname, keylist: chunk })
              .then(function () {
                if (cfg.deleteDup2) {
                  return RemIcsApi.dsAsmx('Tdssdf/TwsdsSDF.asmx', cfg.deleteDup2, { name: sdfname, keylist: chunk });
                }
              });
          });
        }, Promise.resolve());
      }
      if (duplists && dupMode === 'keep') {
        var dupSet = ',' + duplists + ',';
        keys = keys.filter(function (k) { return dupSet.indexOf(',' + k + ',') < 0; });
        keylist = keys.join(',');
      }
    }).then(function () {
      if (!keys.length) {
        setStatus('Save complete (no new keys).');
        alert('Save complete');
        show($('ds-sdf-save'), false);
        return;
      }
      return chunkKeyList(keys, cfg.subcount).reduce(function (p, chunk) {
        return p.then(function () {
          return RemIcsApi.dsAsmx('Tdssdf/TwsdsSDF.asmx', cfg.insert, { name: sdfname, keylist: chunk })
            .then(function () {
              if (cfg.insert2) {
                return RemIcsApi.dsAsmx('Tdssdf/TwsdsSDF.asmx', cfg.insert2, { name: sdfname, keylist: chunk });
              }
            });
        });
      }, Promise.resolve());
    }).then(function () {
      setStatus('Save complete  -  ' + sdfname);
      alert('Save complete');
      show($('ds-sdf-save'), false);
      if (global.RemicsApp) RemicsApp.navigate('sdf-tree', 'type=' + encodeURIComponent(dsSdfState.type));
    }).catch(function (ex) {
      setStatus(ex.message || String(ex));
      alert('Save failed: ' + (ex.message || ex));
    });
  }

  /* ---- DS SDF ---- */
  function renderDsSdfCriteria(type) {
    var cfg = SDF_SEARCH[type] || SDF_SEARCH.Ante;
    var title = $('dssdf-title');
    if (title) title.textContent = cfg.title;
    var table = $('dssdf-fields');
    if (!table) return;
    table.innerHTML = '';
    var row = null;
    cfg.fields.forEach(function (f, i) {
      if (i % 2 === 0) {
        row = document.createElement('tr');
        table.appendChild(row);
      }
      var tdL = document.createElement('td');
      tdL.className = 'o';
      tdL.textContent = f.label;
      var tdR = document.createElement('td');
      tdR.className = 'by';
      var inp = document.createElement('input');
      inp.id = 'dssdf-f-' + f.col;
      inp.className = 'im';
      inp.size = 16;
      inp.maxLength = 100;
      inp.setAttribute('data-col', f.col);
      tdR.appendChild(inp);
      row.appendChild(tdL);
      row.appendChild(tdR);
      if (cfg.fields.length % 2 === 1 && i === cfg.fields.length - 1) {
        row.appendChild(document.createElement('td'));
        row.appendChild(document.createElement('td'));
      }
    });
  }

  function mountDsSdf() {
    var status = $('ds-sdf-status');
    var route = parseRoute();
    var typeSel = $('dssdf-type');
    var type = (route.params.type || (typeSel && typeSel.value) || 'Ante').trim();
    if (!route.params.type && window.RemIcsApi && RemIcsApi.sessionGet) {
      type = RemIcsApi.sessionGet('remics-last-dssdf-type') || type;
    }
    if (typeSel) typeSel.value = type;
    renderDsSdfCriteria(type);
    if (window.RemIcsApi && RemIcsApi.wireEnterAsTab) {
      RemIcsApi.wireEnterAsTab($('ds-sdf-criteria') || $('view-host'));
    }

    if (route.params.type && $('dssdf-type-row')) {
      show($('dssdf-type-row'), false);
    }

    function setStatus(m) { if (status) status.textContent = m || ''; }

    function collectBody() {
      var t = typeSel ? typeSel.value : type;
      var body = { type: t };
      var cfg = SDF_SEARCH[t] || SDF_SEARCH.Ante;
      cfg.fields.forEach(function (f) {
        var el = $('dssdf-f-' + f.col);
        if (el && el.value.trim()) body[f.col] = el.value.trim();
      });
      return body;
    }

    if (typeSel) {
      typeSel.onchange = function () {
        if (window.RemIcsApi && RemIcsApi.sessionSet) {
          RemIcsApi.sessionSet('remics-last-dssdf-type', typeSel.value);
        }
        renderDsSdfCriteria(typeSel.value);
        setStatus('');
        show($('ds-sdf-results'), false);
        show($('ds-sdf-criteria'), true);
      };
    }

    if ($('dssdf-clear')) {
      $('dssdf-clear').onclick = function () {
        var cfg = SDF_SEARCH[typeSel ? typeSel.value : type] || SDF_SEARCH.Ante;
        cfg.fields.forEach(function (f) {
          var el = $('dssdf-f-' + f.col);
          if (el) el.value = '';
        });
        setStatus('');
        var pre = $('dssdf-sql-preview');
        if (pre) pre.textContent = '';
      };
    }

    if ($('dssdf-help')) {
      $('dssdf-help').onclick = function () {
        var t = typeSel ? typeSel.value : type;
        window.open(micsRoot() + 'micshelp/separatefiles/ds' + t + '.aspx', 'WndHelp',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
      };
    }

    if ($('dssdf-showsql')) {
      $('dssdf-showsql').onchange = function () {
        show($('dssdf-sql-preview'), $('dssdf-showsql').checked);
      };
    }

    $('dssdf-backcrit').onclick = function () {
      show($('ds-sdf-results'), false);
      show($('ds-sdf-criteria'), true);
    };

    $('dssdf-search').onclick = function () {
      setStatus('Searching...');
      var body = collectBody();
      RemIcsApi.dsSdf('search', body).then(function (r) {
        if (!r.ok) { setStatus(r.error || 'Failed'); return; }
        dsSdfState.type = r.type || type;
        dsSdfState.keyCol = r.keyCol || 'acode';
        dsSdfState.rows = r.rows || [];
        var head = $('dssdf-head');
        var tbody = $('dssdf-table').querySelector('tbody');
        head.innerHTML = '';
        tbody.innerHTML = '';
        var thSave = document.createElement('th');
        thSave.className = 'o';
        thSave.textContent = 'Save';
        head.appendChild(thSave);
        (r.columns || []).forEach(function (c) {
          var th = document.createElement('th');
          th.className = 'o';
          th.textContent = c;
          head.appendChild(th);
        });
        (r.rows || []).forEach(function (row) {
          var tr = document.createElement('tr');
          var tdChk = document.createElement('td');
          var key = row[dsSdfState.keyCol] || '';
          tdChk.innerHTML = '<input type="checkbox" data-kind="row" data-key="' + String(key).replace(/"/g, '&quot;') + '">';
          tr.appendChild(tdChk);
          (r.columns || []).forEach(function (c) {
            var td = document.createElement('td');
            td.textContent = row[c] || '';
            tr.appendChild(td);
          });
          tbody.appendChild(tr);
        });
        setStatus(r.count + ' row(s)');
        if ($('dssdf-showsql') && $('dssdf-showsql').checked) {
          var pre = $('dssdf-sql-preview');
          if (pre) pre.textContent = 'type=' + r.type + ' keyCol=' + (r.keyCol || '');
          show(pre, true);
        }
        show($('ds-sdf-criteria'), false);
        show($('ds-sdf-results'), true);
        show($('ds-sdf-save'), false);
      });
    };

    if ($('dssdf-checkall')) {
      $('dssdf-checkall').onclick = function () {
        document.querySelectorAll('#dssdf-table input[data-kind=row]').forEach(function (c) { c.checked = true; });
      };
    }
    if ($('dssdf-checknone')) {
      $('dssdf-checknone').onclick = function () {
        document.querySelectorAll('#dssdf-table input[data-kind=row]').forEach(function (c) { c.checked = false; });
      };
    }
    if ($('dssdf-save')) {
      $('dssdf-save').onclick = function () {
        populateSdfSelect(typeSel ? typeSel.value : type).then(function () {
          show($('ds-sdf-save'), true);
        });
      };
    }
    if ($('dssdf-save-cancel')) {
      $('dssdf-save-cancel').onclick = function () { show($('ds-sdf-save'), false); };
    }
    if ($('dssdf-save-go')) {
      $('dssdf-save-go').onclick = function () { saveDsSdf(setStatus); };
    }
  }

  /* ---- Fee ---- */
  function mountFeeCalc() {
    function openFee(next, title) {
      var url = micsRoot() + 'reports/tsFeeParm.aspx?Next=' + encodeURIComponent(next) +
        '&T=' + encodeURIComponent(title);
      window.open(url, 'WndFee', 'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes');
    }
    $('fee-ts-det').onclick = function () { openFee('tsDetRep.aspx', 'TS Fee Calculation Detail Report'); };
    $('fee-ts-sum').onclick = function () { openFee('tsSumRep.aspx', 'TS Fee Calculation Summary Report'); };
    $('fee-es-det').onclick = function () { openFee('esDetRep.aspx', 'ES Fee Calculation Detail Report'); };
    $('fee-es-sum').onclick = function () { openFee('esSumRep.aspx', 'ES Fee Calculation Summary Report'); };
    $('fee-eqpt').onclick = function () {
      window.open(micsRoot() + 'reports/EqptFeesReport.aspx', 'WndFee', 'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes');
    };
  }

  /* ---- Bulk print ---- */
  function mountBulkPrint() {
    var status = $('bp-status');
    var route = parseRoute();
    var staging = [];

    function ft() {
      var el = document.querySelector('input[name=bp-ft]:checked');
      return el ? el.value : 'TS';
    }
    if (route.params.filetype) {
      var want = route.params.filetype.toUpperCase();
      document.querySelectorAll('input[name=bp-ft]').forEach(function (r) {
        r.checked = r.value === want;
      });
    }

    var emailedKey = '';

    function selectedNames() {
      if (staging.length) return staging.slice();
      var names = [];
      document.querySelectorAll('#bp-list input:checked').forEach(function (c) {
        var name = c.getAttribute('data-name');
        if (name) names.push(name);
      });
      return names;
    }

    function selectionKey() {
      return ft() + ':' + selectedNames().join(',');
    }

    function syncEmailButton() {
      var btn = $('bp-email');
      var note = $('bp-email-note');
      if (!btn) return;
      if (selectionKey() !== emailedKey) {
        btn.disabled = false;
        show(note, false);
      }
    }

    function renderStaging() {
      var ul = $('bp-staging');
      if (!ul) return;
      ul.innerHTML = '';
      staging.forEach(function (name, idx) {
        var li = document.createElement('li');
        li.className = idx === 0 ? 'selected' : '';
        li.textContent = name;
        li.onclick = function () {
          ul.querySelectorAll('li').forEach(function (n) { n.classList.remove('selected'); });
          li.classList.add('selected');
        };
        ul.appendChild(li);
      });
      syncEmailButton();
    }

    function load() {
      staging = [];
      emailedKey = '';
      renderStaging();
      status.textContent = 'Loading...';
      RemIcsApi.filesList(ft()).then(function (data) {
        if (!data.ok) {
          status.textContent = (RemIcsApi.friendlyAsmxError && data.error)
            ? RemIcsApi.friendlyAsmxError(data.error) : (data.error || 'Load failed');
          return;
        }
        var ul = $('bp-list');
        ul.innerHTML = '';
        (data.files || []).forEach(function (f) {
          var li = document.createElement('li');
          li.innerHTML = '<label><input type="checkbox" data-name="' + f.name + '"> ' + f.name + '</label>';
          ul.appendChild(li);
        });
        status.textContent = (data.files || []).length + ' file(s)';
      });
    }

    $('bp-refresh').onclick = load;
    document.querySelectorAll('input[name=bp-ft]').forEach(function (r) { r.onchange = load; });

    if ($('bp-checkall')) {
      $('bp-checkall').onclick = function () {
        document.querySelectorAll('#bp-list input[type=checkbox]').forEach(function (c) { c.checked = true; });
        syncEmailButton();
      };
    }
    if ($('bp-checknone')) {
      $('bp-checknone').onclick = function () {
        document.querySelectorAll('#bp-list input[type=checkbox]').forEach(function (c) { c.checked = false; });
        syncEmailButton();
      };
    }
    if ($('bp-add')) {
      $('bp-add').onclick = function () {
        document.querySelectorAll('#bp-list input:checked').forEach(function (c) {
          var name = c.getAttribute('data-name');
          if (name && staging.indexOf(name) < 0) staging.push(name);
          c.checked = false;
        });
        renderStaging();
      };
    }
    if ($('bp-remove')) {
      $('bp-remove').onclick = function () {
        var ul = $('bp-staging');
        var sel = ul && ul.querySelector('li.selected');
        if (!sel) return;
        staging = staging.filter(function (n) { return n !== sel.textContent; });
        renderStaging();
      };
    }
    if ($('bp-up')) {
      $('bp-up').onclick = function () {
        var ul = $('bp-staging');
        var sel = ul && ul.querySelector('li.selected');
        if (!sel) return;
        var idx = staging.indexOf(sel.textContent);
        if (idx <= 0) return;
        var tmp = staging[idx - 1];
        staging[idx - 1] = staging[idx];
        staging[idx] = tmp;
        renderStaging();
        ul.children[idx - 1].classList.add('selected');
      };
    }
    if ($('bp-down')) {
      $('bp-down').onclick = function () {
        var ul = $('bp-staging');
        var sel = ul && ul.querySelector('li.selected');
        if (!sel) return;
        var idx = staging.indexOf(sel.textContent);
        if (idx < 0 || idx >= staging.length - 1) return;
        var tmp = staging[idx + 1];
        staging[idx + 1] = staging[idx];
        staging[idx] = tmp;
        renderStaging();
        ul.children[idx + 1].classList.add('selected');
      };
    }

    if ($('bp-list')) {
      $('bp-list').addEventListener('change', syncEmailButton);
    }

    if ($('bp-email')) {
      $('bp-email').onclick = function () {
        var names = selectedNames();
        var btn = $('bp-email');
        var note = $('bp-email-note');
        if (!names.length) {
          if (status) status.textContent = 'Stage or check at least one file, then click Email me.';
          return;
        }
        btn.disabled = true;
        show(note, true);
        if (status) status.textContent = 'Printing files to your directory and queueing email...';
        RemIcsApi.printEmail(names, ft(), projectCode()).then(function (data) {
          if (!data.ok) {
            btn.disabled = false;
            show(note, false);
            if (status) status.textContent = data.error || 'Email request failed.';
            return;
          }
          emailedKey = selectionKey();
          var dest = data.email ? (' to ' + data.email) : '';
          if (status) status.textContent = 'Email queued' + dest + '. Delivery can take up to 20 minutes.';
        }).catch(function (ex) {
          btn.disabled = false;
          show(note, false);
          if (status) status.textContent = ex.message || String(ex);
        });
      };
    }

    if ($('bp-open-tree')) $('bp-open-tree').onclick = function () {
      var page = ft() === 'ES' ? 'ESPrintTree.aspx' : 'TSPrintTree.aspx';
      var key = staging[0] ? 't.' + staging[0] : '';
      var checked = [];
      document.querySelectorAll('#bp-list input:checked').forEach(function (c) {
        checked.push(c.getAttribute('data-name'));
      });
      if (!key && checked[0]) key = 't.' + checked[0];
      if (status) status.textContent = 'Opening print tree... wait in that window until the file list loads.';
      window.open(micsRoot() + 'Tbulkprint/' + page + (key ? '?key=' + encodeURIComponent(key) : ''),
        'WndPrintTree', 'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes');
    };
    load();
  }

  /* ---- TSIP Post Analysis (classic TnavigationLeft postTsip subtree) ---- */
  var NRCAN_NTV2_URL = 'https://webapp.csrs-scrs.nrcan-rncan.gc.ca/geod/tools-outils/ntv2.php?locale=en';
  var POST_TSIP_TOOLS = {
    ohl: { page: 'auxengmenu/AUXOHLoss1.aspx', title: 'Over Horizon Loss' },
    terrain: { page: 'auxengmenu/AUXTerrain1.aspx', title: 'Terrain Profile' },
    nad27: { external: NRCAN_NTV2_URL, title: 'NAD27-WGS84 Conversion' },
    antennaRpe: { page: 'Tdssdf/dsAnte.aspx?type=PA', title: 'Antenna RPE' },
    ctx: { page: 'Tdssdf/dsCtx.aspx?type=PA', title: 'CTX File' },
    tsesCsv: { page: 'Ttsipmenu/CASEDETTSESsel.aspx', title: 'TSIP TS-ES CSV Report' },
    tstsCsv: { page: 'Ttsipmenu/CASEDETTSTSsel.aspx', title: 'TSIP TS-TS CSV Report' },
    tsesKml: { page: 'Ttsipmenu/CASEDETTSESkmlsel.aspx', title: 'TSIP TS-ES KML Report' },
    tstsKml: { page: 'Ttsipmenu/CASEDETTSTSkmlsel.aspx', title: 'TSIP TS-TS KML Report' },
    genctx: { page: 'auxengmenu/AUXgenctx1.aspx', title: 'Generate CTX Curves' }
  };

  function openClassicPage(page, title) {
    window.open(micsRoot() + page, 'WndPostTsip',
      'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes');
  }

  function mountTsipPost() {
    var tool = parseRoute().params.tool || '';
    if (tool === 'genctx') {
      if (global.RemicsApp) RemicsApp.navigate('aux-eng', 'tool=genctx');
      else location.hash = '#/aux-eng?tool=genctx';
      return;
    }
    if (tool === 'ohl') {
      if (global.RemicsApp) RemicsApp.navigate('aux-eng', 'tool=ohl');
      else location.hash = '#/aux-eng?tool=ohl';
      return;
    }
    if (tool === 'terrain') {
      if (global.RemicsApp) RemicsApp.navigate('aux-eng', 'tool=terrain');
      else location.hash = '#/aux-eng?tool=terrain';
      return;
    }
    if (tool === 'nad27') {
      if (global.RemicsApp) RemicsApp.navigate('aux-eng', 'tool=nad27');
      else location.hash = '#/aux-eng?tool=nad27';
      return;
    }
    if (tool === 'antennaRpe') {
      if (global.RemicsApp) RemicsApp.navigate('ds-sdf', 'type=Ante');
      else location.hash = '#/ds-sdf?type=Ante';
      return;
    }
    if (tool === 'ctx') {
      if (global.RemicsApp) RemicsApp.navigate('ds-sdf', 'type=Ctx');
      else location.hash = '#/ds-sdf?type=Ctx';
      return;
    }
    var casedetMap = {
      tsesCsv: 'mode=TSES&kind=csv',
      tstsCsv: 'mode=TSTS&kind=csv',
      tsesKml: 'mode=TSES&kind=kml',
      tstsKml: 'mode=TSTS&kind=kml'
    };
    if (casedetMap[tool]) {
      if (global.RemicsApp) RemicsApp.navigate('tsip-casedet', casedetMap[tool]);
      else location.hash = '#/tsip-casedet?' + casedetMap[tool];
      return;
    }
    var cfg = POST_TSIP_TOOLS[tool];
    if (cfg && cfg.external) {
      window.open(cfg.external, 'WndNRCAN',
        'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes');
    }
    if (global.RemicsApp) RemicsApp.navigate('welcome');
  }

  /* ---- Aux Eng ---- */
  var AUX_LIVE = {
    distance: true, genctx: true, sep: true, pattern: true, coord: true, pcs: true, hilo: true, nad27: true, sat: true, orbit: true, ohl: true, terrain: true, pfd: true, passive: true
  };
  var AUX_TITLES = {
    distance: 'FCSA Distance and Bearing Calculation',
    genctx: 'Generate a CTX curve',
    sep: 'Earth Station Separation Angle',
    pattern: 'Passive Antenna Pattern Generator',
    coord: 'Coordination Zone Check',
    pcs: 'PCS Coordination',
    hilo: 'Check Band High-Low Frequency distribution',
    nad27: 'NAD27-WGS84 Conversion',
    sat: 'Satellite Azimuth and Elevation',
    orbit: 'Geostationary Orbit Intersection',
    ohl: 'Over Horizon Loss',
    terrain: 'Terrain Profiling',
    pfd: 'PFD or Coverage Contours',
    passive: 'Passive Calculation Entry'
  };
  var ctxState = { serial: '', vicParm: '', intParm: '', rows: [] };

  function auxOpenHelp(page) {
    window.open(micsRoot() + page, 'WndHelp',
      'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=520,height=420');
  }

  function setAuxStatus(msg, isError) {
    var el = $('aux-status');
    if (!el) return;
    el.innerHTML = '';
    el.style.color = isError ? '#a00000' : '';
    el.style.fontStyle = isError ? 'italic' : '';
    el.textContent = msg || '';
  }

  function showAuxPane(id) {
    ['aux-menu', 'aux-stub', 'aux-distance', 'aux-genctx',
      'aux-sep', 'aux-pattern', 'aux-passive', 'aux-coord', 'aux-pcs', 'aux-hilo', 'aux-sat', 'aux-orbit', 'aux-ohl', 'aux-terrain', 'aux-pfd', 'aux-nad27'].forEach(function (pane) {
      show($(pane), pane === id);
    });
  }

  function auxGoWelcome() {
    if (global.RemicsApp) RemicsApp.navigate('welcome');
    else location.hash = '#/welcome';
  }

  function axPasPat(width, incAng, freq, gain) {
    var discTable = [13.5, 17.9, 20.8, 23.0, 24.8, 26.2,
      27.4, 28.5, 29.5, 30.4, 31.2, 31.9,
      32.5, 33.2, 33.7, 34.3, 34.8, 35.3,
      35.7, 36.2, 36.6, 37.0, 37.4, 37.7,
      38.1, 38.4, 38.7, 39.0, 39.3, 39.6,
      39.9, 40.2, 40.4, 40.7, 40.9, 41.2,
      41.4, 41.7, 41.9, 42.1];
    var i, greater90 = false, discGtDiscrMax = false;
    var varA, efwlog, freqLog, varAFreq, discrim, discrMax, holdVar1, holdVar2, temp;
    var patt1 = new Array(40);
    var patt2 = new Array(40);
    var beamWth, x;
    function log10(v) { return Math.log(v) / Math.log(10.0); }
    varA = width * Math.cos(incAng * 0.008726646);
    if (varA <= 0) varA = 1.0e-10;
    efwlog = log10(varA);
    freqLog = log10(freq);
    varAFreq = varA * freq;
    discrim = (20 * efwlog) + (20 * freqLog) - 39.5995;
    discrMax = (discrim < (gain / 2)) ? discrim : gain / 2;
    holdVar1 = 134.83607 / varAFreq;
    holdVar2 = 450 / varAFreq;
    if (Math.floor(Math.abs(holdVar2)) > 1) {
      throw new Error('Area or Frequency too small for pattern');
    }
    beamWth = (360 / Math.PI) * Math.asin(holdVar1);
    var RTOD = 180.0 / Math.PI;
    for (i = 0; i < 40; i++) {
      temp = 2 * (i + 1);
      x = Math.asin((temp + 1.0) * 150 / varAFreq);
      patt1[i] = RTOD * x;
      if (patt1[i] > 90.0) { greater90 = true; break; }
      discrim = discTable[i];
      if (discrim > discrMax) { discGtDiscrMax = true; break; }
      patt2[i] = discrim;
    }
    if (!greater90 && !discGtDiscrMax) {
      patt1[i] = 2.5 * (discrMax - discrim) + patt1[i - 1];
      patt2[i] = discrMax;
      i++;
    }
    if (discGtDiscrMax) { patt2[i] = discrMax; i++; }
    if (greater90) { patt1[i] = 90.0; patt2[i] = discrMax; i++; }
    patt1[i] = 180.0;
    patt2[i] = discrMax;
    return [beamWth, patt1, patt2];
  }

  function fmt2(n) {
    var v = Number(n);
    if (isNaN(v)) return '';
    return v.toFixed(2);
  }

  function plotCtxCurve(host, rows) {
    if (!host) return;
    host.innerHTML = '';
    if (!rows || !rows.length) return;
    var w = 640, h = 360, padL = 56, padR = 16, padT = 28, padB = 44;
    var i, minX = rows[0].sep, maxX = rows[0].sep, minY = rows[0].req, maxY = rows[0].req;
    for (i = 1; i < rows.length; i++) {
      if (rows[i].sep < minX) minX = rows[i].sep;
      if (rows[i].sep > maxX) maxX = rows[i].sep;
      if (rows[i].req < minY) minY = rows[i].req;
      if (rows[i].req > maxY) maxY = rows[i].req;
    }
    if (maxX === minX) maxX = minX + 1;
    if (maxY === minY) { minY -= 1; maxY += 1; }
    function xOf(v) { return padL + ((v - minX) / (maxX - minX)) * (w - padL - padR); }
    function yOf(v) { return padT + (1 - (v - minY) / (maxY - minY)) * (h - padT - padB); }
    var pts = rows.map(function (r) { return xOf(r.sep).toFixed(1) + ',' + yOf(r.req).toFixed(1); }).join(' ');
    var label = (rows[0].req >= 0) ? 'Required C/I' : 'Max Interference';
    var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + h + '" viewBox="0 0 ' + w + ' ' + h + '">';
    svg += '<rect x="0" y="0" width="' + w + '" height="' + h + '" fill="#fff" stroke="#000"/>';
    svg += '<line x1="' + padL + '" y1="' + padT + '" x2="' + padL + '" y2="' + (h - padB) + '" stroke="#000"/>';
    svg += '<line x1="' + padL + '" y1="' + (h - padB) + '" x2="' + (w - padR) + '" y2="' + (h - padB) + '" stroke="#000"/>';
    svg += '<polyline fill="none" stroke="#003399" stroke-width="1.5" points="' + pts + '"/>';
    svg += '<text x="' + (w / 2) + '" y="18" text-anchor="middle" font-size="12" font-family="Arial">' + label + '</text>';
    svg += '<text x="' + (w / 2) + '" y="' + (h - 12) + '" text-anchor="middle" font-size="11" font-family="Arial">Frequency Separation (MHz)</text>';
    svg += '<text x="14" y="' + (h / 2) + '" text-anchor="middle" font-size="11" font-family="Arial" transform="rotate(-90 14 ' + (h / 2) + ')">dB</text>';
    svg += '<text x="' + padL + '" y="' + (h - 28) + '" text-anchor="middle" font-size="10" font-family="Arial">' + fmt2(minX) + '</text>';
    svg += '<text x="' + (w - padR) + '" y="' + (h - 28) + '" text-anchor="end" font-size="10" font-family="Arial">' + fmt2(maxX) + '</text>';
    svg += '<text x="' + (padL - 6) + '" y="' + (h - padB) + '" text-anchor="end" font-size="10" font-family="Arial">' + fmt2(minY) + '</text>';
    svg += '<text x="' + (padL - 6) + '" y="' + (padT + 10) + '" text-anchor="end" font-size="10" font-family="Arial">' + fmt2(maxY) + '</text>';
    svg += '</svg>';
    host.innerHTML = svg;
  }

  function fillCtxTable(rows) {
    var tb = $('ctx-table') && $('ctx-table').tBodies[0];
    if (!tb) return;
    tb.innerHTML = '';
    (rows || []).forEach(function (r) {
      var tr = document.createElement('tr');
      var c1 = document.createElement('td');
      c1.align = 'right';
      c1.textContent = Number(r.sep).toFixed(2);
      var c2 = document.createElement('td');
      c2.align = 'right';
      c2.textContent = Number(r.req).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
      tr.appendChild(c1);
      tr.appendChild(c2);
      tb.appendChild(tr);
    });
  }

  function fillPairTable(tableId, rows, note) {
    var tb = $(tableId) && $(tableId).tBodies[0];
    if (!tb) return;
    tb.innerHTML = '';
    if (note && (!rows || !rows.length)) {
      var trn = document.createElement('tr');
      var tdn = document.createElement('td');
      tdn.colSpan = 2;
      tdn.align = 'center';
      var b = document.createElement('b');
      b.textContent = note;
      tdn.appendChild(b);
      trn.appendChild(tdn);
      tb.appendChild(trn);
      return;
    }
    (rows || []).forEach(function (r) {
      var tr = document.createElement('tr');
      var c1 = document.createElement('td');
      c1.align = 'right';
      c1.textContent = Number(r.fs).toLocaleString(undefined, { minimumFractionDigits: 3, maximumFractionDigits: 3 });
      var c2 = document.createElement('td');
      c2.align = 'right';
      c2.textContent = Number(r.value).toLocaleString(undefined, { minimumFractionDigits: 1, maximumFractionDigits: 1 });
      tr.appendChild(c1);
      tr.appendChild(c2);
      tb.appendChild(tr);
    });
  }

  function downloadText(fileName, text, mime) {
    var blob = new Blob([text], { type: mime || 'text/csv' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = fileName || 'download.csv';
    document.body.appendChild(a);
    a.click();
    setTimeout(function () {
      URL.revokeObjectURL(a.href);
      a.remove();
    }, 500);
  }

  function mountGenCtx() {
    ctxState = { serial: '', vicParm: '', intParm: '', rows: [] };
    if ($('ctx-save')) $('ctx-save').disabled = true;
    if ($('ctx-fs')) $('ctx-fs').disabled = true;
    show($('ctx-result'), false);
    show($('ctx-plot'), false);
    show($('ctx-spectra'), false);
    setCtxStatus('');
    if ($('ctx-message')) $('ctx-message').innerHTML = '';

    function setCtxStatus(msg, isError) {
      var el = $('aux-status');
      if (!el) return;
      el.innerHTML = '';
      el.style.color = isError ? '#a00000' : '';
      el.style.fontStyle = isError ? 'italic' : '';
      el.textContent = msg || '';
    }

    function bindLookup(btnId, type, fieldId, fld2) {
      if (!$(btnId) || !global.RemicsLookup) return;
      $(btnId).onclick = function () {
        var text = ($(fieldId) ? $(fieldId).value : '').trim();
        if (!text) {
          setCtxStatus('Type the first character(s) of the code in that field, then click ??.', true);
          if ($(fieldId)) $(fieldId).focus();
          return;
        }
        setCtxStatus('');
        RemicsLookup.open(type, fieldId, {
          mandatory: true,
          fld2: fld2 || '',
          twoField: !!fld2,
          text: text
        });
      };
    }
    bindLookup('ctx-vic-eqpt-lookup', 'EqptTraf', 'ctx-vic-eqpt', 'ctx-vic-traf');
    bindLookup('ctx-int-eqpt-lookup', 'EqptTraf', 'ctx-int-eqpt', 'ctx-int-traf');
    bindLookup('ctx-vic-traf-lookup', 'TrafCode', 'ctx-vic-traf');
    bindLookup('ctx-int-traf-lookup', 'TrafCode', 'ctx-int-traf');

    var LAST_EQPT_TRAF = 'remicsCtxLastEqptTraf';
    function lastEqptTrafMap() {
      try { return JSON.parse(sessionStorage.getItem(LAST_EQPT_TRAF) || '{}') || {}; }
      catch (e) { return {}; }
    }
    function rememberEqptTraf(eqpt, traf) {
      eqpt = (eqpt || '').trim().toUpperCase();
      traf = (traf || '').trim().toUpperCase();
      if (!eqpt || !traf) return;
      var map = lastEqptTrafMap();
      map[eqpt] = traf;
      try { sessionStorage.setItem(LAST_EQPT_TRAF, JSON.stringify(map)); } catch (e) { /* ignore */ }
    }
    function lookupEqptTraf(eqpt) {
      eqpt = (eqpt || '').trim().toUpperCase();
      if (!eqpt) return Promise.resolve('');
      var remembered = lastEqptTrafMap()[eqpt] || '';
      if (!global.RemIcsApi || typeof RemIcsApi.genctxEqptTraf !== 'function') {
        return Promise.resolve(remembered);
      }
      return RemIcsApi.genctxEqptTraf(eqpt).then(function (r) {
        if (r && r.ok && r.traf) return String(r.traf).trim().toUpperCase();
        return remembered;
      }).catch(function () { return remembered; });
    }
    function fillTrafFromEqpt(eqptId, trafId) {
      var eqEl = $(eqptId);
      var trEl = $(trafId);
      if (!eqEl || !trEl) return Promise.resolve('');
      var code = (eqEl.value || '').trim().toUpperCase();
      if (code && eqEl.value !== code) eqEl.value = code;
      if (!code) return Promise.resolve((trEl.value || '').trim());
      return lookupEqptTraf(code).then(function (traf) {
        if ((eqEl.value || '').trim().toUpperCase() !== code) return (trEl.value || '').trim();
        if (traf) trEl.value = traf;
        return (trEl.value || '').trim();
      });
    }
    function bindEqptTrafAutofill(eqptId, trafId) {
      var eqEl = $(eqptId);
      if (!eqEl) return;
      var timer = null;
      function run() { fillTrafFromEqpt(eqptId, trafId); }
      eqEl.addEventListener('change', run);
      eqEl.addEventListener('blur', run);
      eqEl.addEventListener('input', function () {
        clearTimeout(timer);
        timer = setTimeout(run, 350);
      });
    }
    bindEqptTrafAutofill('ctx-vic-eqpt', 'ctx-vic-traf');
    bindEqptTrafAutofill('ctx-int-eqpt', 'ctx-int-traf');

    if ($('ctx-add-freq-btn')) {
      $('ctx-add-freq-btn').onclick = function () {
        var raw = ($('ctx-add-freq').value || '').trim();
        var d = parseFloat(raw);
        if (isNaN(d)) {
          setCtxStatus('Enter the frequency in MegaHertz.', true);
          return;
        }
        if (d < 0 || d > 5000) {
          setCtxStatus('Frequency must be between 0 and 5000 MHz.', true);
          return;
        }
        var ta = $('ctx-freqs');
        ta.value = ta.value ? (ta.value.replace(/\s+$/, '') + '\n' + d.toFixed(3)) : d.toFixed(3);
        $('ctx-add-freq').value = '';
        setCtxStatus('');
      };
    }

    if ($('ctx-go')) {
      $('ctx-go').onclick = function () {
        $('ctx-go').disabled = true;
        Promise.all([
          fillTrafFromEqpt('ctx-vic-eqpt', 'ctx-vic-traf'),
          fillTrafFromEqpt('ctx-int-eqpt', 'ctx-int-traf')
        ]).then(function () {
          var vicE = ($('ctx-vic-eqpt').value || '').trim();
          var vicT = ($('ctx-vic-traf').value || '').trim();
          var intE = ($('ctx-int-eqpt').value || '').trim();
          var intT = ($('ctx-int-traf').value || '').trim();
          if (!vicE || !vicT || !intE || !intT) {
            $('ctx-go').disabled = false;
            setCtxStatus('The four green fields are required: Victim and Interferor Equipment and Traffic.', true);
            return;
          }
          setCtxStatus('Generating...');
          show($('ctx-result'), false);
          show($('ctx-plot'), false);
          show($('ctx-spectra'), false);
          RemIcsApi.genctxGenerate({
            vicEquip: vicE,
            vicTraf: vicT,
            intEquip: intE,
            intTraf: intT,
            esVictim: $('ctx-es') && $('ctx-es').checked,
            freqs: $('ctx-freqs') ? $('ctx-freqs').value : ''
          }).then(function (r) {
            $('ctx-go').disabled = false;
            if (!r.ok) {
              setCtxStatus(r.noResults ? (r.error || 'No results found.') : apiErr(r, 'Generate failed'), true);
              if ($('ctx-save')) $('ctx-save').disabled = true;
              if ($('ctx-fs')) $('ctx-fs').disabled = true;
              return;
            }
            rememberEqptTraf(vicE, vicT);
            rememberEqptTraf(intE, intT);
            ctxState.serial = r.serial || '';
            ctxState.vicParm = r.vicParm || '';
            ctxState.intParm = r.intParm || '';
            ctxState.rows = r.rows || [];
            var msg = 'The victim cross reference is, Equipment: <b>' + (r.vicEquip || '') +
              '</b>, Traffic: <b>' + (r.vicTraf || '') +
              '</b><br>The Interferor cross reference is, Equipment: <b>' + (r.intEquip || '') +
              '</b>, Traffic: <b>' + (r.intTraf || '') + '</b>';
            if ($('ctx-message')) $('ctx-message').innerHTML = msg;
            fillCtxTable(ctxState.rows);
            show($('ctx-result'), true);
            show($('ctx-plot'), false);
            show($('ctx-spectra'), false);
            var hasRows = ctxState.rows.length > 0;
            if ($('ctx-save')) $('ctx-save').disabled = !hasRows;
            if ($('ctx-fs')) $('ctx-fs').disabled = false;
            if (!hasRows || r.noResults) {
              setCtxStatus('No results found for those equipment and traffic codes.', true);
            } else {
              setCtxStatus('');
            }
          }).catch(function (ex) {
            $('ctx-go').disabled = false;
            setCtxStatus(ex.message || String(ex), true);
          });
        }).catch(function (ex) {
          $('ctx-go').disabled = false;
          setCtxStatus(ex.message || String(ex), true);
        });
      };
    }

    if ($('ctx-save')) {
      $('ctx-save').onclick = function () {
        if (!ctxState.serial) return;
        RemIcsApi.genctxSave(ctxState.serial).then(function (r) {
          if (!r.ok) { setCtxStatus(apiErr(r, 'Save failed'), true); return; }
          downloadText(r.fileName || (ctxState.serial + '.csv'), r.csv || '', 'text/csv');
          setCtxStatus('Saved ' + (r.fileName || 'curve.csv'));
        });
      };
    }

    if ($('ctx-plot-btn')) {
      $('ctx-plot-btn').onclick = function () {
        if (!ctxState.rows.length) {
          setCtxStatus('No results found to plot.', true);
          return;
        }
        show($('ctx-plot'), true);
        plotCtxCurve($('ctx-plot'), ctxState.rows);
      };
    }

    if ($('ctx-fs')) {
      $('ctx-fs').onclick = function () {
        RemIcsApi.genctxSpectra({
          vicEquip: $('ctx-vic-eqpt').value,
          vicTraf: $('ctx-vic-traf').value,
          intEquip: $('ctx-int-eqpt').value,
          intTraf: $('ctx-int-traf').value,
          vicParm: ctxState.vicParm,
          intParm: ctxState.intParm
        }).then(function (r) {
          if (!r.ok) { setCtxStatus(apiErr(r, 'Spectra failed'), true); return; }
          if ($('ctx-filter-title')) $('ctx-filter-title').textContent = r.filterTitle || 'Filter Attenuation';
          if ($('ctx-power-title')) $('ctx-power-title').textContent = r.powerTitle || 'Power Spectrum';
          fillPairTable('ctx-filter-table', r.filter, r.filterNote);
          fillPairTable('ctx-power-table', r.power, r.powerNote);
          show($('ctx-spectra'), true);
          setCtxStatus('');
        });
      };
    }

    if ($('ctx-cancel')) {
      $('ctx-cancel').onclick = function () {
        if (global.RemicsApp) RemicsApp.navigate('welcome');
      };
    }
    if ($('ctx-help')) {
      $('ctx-help').onclick = function () {
        auxOpenHelp('micshelp/AUXgenctx1.aspx');
      };
    }
  }

  function mountSep() {
    setAuxStatus('');
    if ($('sep-ang')) $('sep-ang').innerHTML = '';
    function readNum(id) {
      var v = ($(id) ? $(id).value : '').trim();
      if (v === '') return null;
      var n = parseFloat(v);
      return isNaN(n) ? null : n;
    }
    if ($('sep-calc')) {
      $('sep-calc').onclick = function () {
        var satAz = readNum('sep-sat-az');
        var satEl = readNum('sep-sat-el');
        var terrAz = readNum('sep-terr-az');
        var terrEl = readNum('sep-terr-el');
        if (satAz == null || satEl == null || terrAz == null || terrEl == null) {
          setAuxStatus('You must fill in all the fields.', true);
          return;
        }
        var DEG_TO_RAD = Math.PI / 180.0;
        var azimAng1Rad = satAz * DEG_TO_RAD;
        var elevAng1Rad = satEl * DEG_TO_RAD;
        var azimAng2Rad = terrAz * DEG_TO_RAD;
        var elevAng2Rad = terrEl * DEG_TO_RAD;
        var varW = Math.cos(azimAng2Rad - azimAng1Rad) * Math.cos(elevAng2Rad) *
          Math.cos(elevAng1Rad) + Math.sin(elevAng2Rad) * Math.sin(elevAng1Rad);
        var varX = 1 - (varW * varW);
        var varY = (varX <= 0) ? -Math.sqrt(-varX) : Math.sqrt(varX);
        var varZ = (varW === 0) ? 0 : varY / varW;
        var intersectAng = Math.atan(varZ) / DEG_TO_RAD;
        if (intersectAng < 0) intersectAng += 180;
        if ($('sep-ang')) $('sep-ang').innerHTML = '<b>' + intersectAng.toFixed(2) + '</b>';
        setAuxStatus('');
      };
    }
    if ($('sep-reset')) {
      $('sep-reset').onclick = function () {
        ['sep-sat-az', 'sep-sat-el', 'sep-terr-az', 'sep-terr-el'].forEach(function (id) {
          if ($(id)) $(id).value = '';
        });
        if ($('sep-ang')) $('sep-ang').innerHTML = '';
        setAuxStatus('');
      };
    }
    if ($('sep-cancel')) $('sep-cancel').onclick = auxGoWelcome;
    if ($('sep-help')) {
      $('sep-help').onclick = function () { auxOpenHelp('micshelp/AUXSepang1.aspx'); };
    }
  }

  function mountPattern() {
    setAuxStatus('');
    function fillPatTable(patt1, patt2) {
      var tb = $('pat-body');
      if (!tb) return;
      tb.innerHTML = '';
      var i;
      for (i = 0; typeof patt1[i] === 'number'; i++) {
        var tr = document.createElement('tr');
        var c1 = document.createElement('td');
        c1.textContent = patt1[i].toFixed(1);
        var c2 = document.createElement('td');
        c2.textContent = (typeof patt2[i] === 'number' ? patt2[i] : 0).toFixed(1);
        tr.appendChild(c1);
        tr.appendChild(c2);
        tb.appendChild(tr);
      }
    }
    if ($('pat-calc')) {
      $('pat-calc').onclick = function () {
        var nWidth = parseFloat(($('pat-width').value || '').trim());
        var nIncAng = parseFloat(($('pat-inc').value || '').trim());
        var nFreq = parseFloat(($('pat-freq').value || '').trim());
        var nGain = parseFloat(($('pat-gain').value || '').trim());
        if (isNaN(nWidth) || isNaN(nIncAng) || isNaN(nFreq) || isNaN(nGain) ||
            !$('pat-width').value.trim() || !$('pat-inc').value.trim() ||
            !$('pat-freq').value.trim() || !$('pat-gain').value.trim()) {
          setAuxStatus('You must enter all of the Width, the Included angle, the Frequency and the Gain.', true);
          if ($('pat-width')) $('pat-width').focus();
          return;
        }
        try {
          var aResult = axPasPat(nWidth, nIncAng, nFreq, nGain);
          if ($('pat-beam')) $('pat-beam').textContent = String(Math.round(aResult[0] * 100) / 100);
          fillPatTable(aResult[1], aResult[2]);
          setAuxStatus('');
        } catch (e) {
          setAuxStatus('Pattern calculation error: ' + (e.message || e), true);
        }
      };
    }
    if ($('pat-report')) {
      $('pat-report').onclick = function () {
        var beam = ($('pat-beam') && $('pat-beam').textContent) || '';
        var tb = $('pat-body');
        if (!beam || !tb || !tb.rows.length) {
          setAuxStatus('Calculate a pattern first.', true);
          return;
        }
        var html = '<html><head><title>Passive Pattern Calculation Report</title></head><body><pre>';
        html += 'Passive Pattern Calculation Report\n';
        html += 'Run at ' + new Date().toLocaleString() + '\n\n';
        html += 'Passive Named: ' + (($('pat-name') && $('pat-name').value) || '') + '\n';
        html += '        Width: ' + (($('pat-width') && $('pat-width').value) || '') + '\n';
        html += '        Angle: ' + (($('pat-inc') && $('pat-inc').value) || '') + '\n';
        html += '    Frequency: ' + (($('pat-freq') && $('pat-freq').value) || '') + '\n';
        html += '         Gain: ' + (($('pat-gain') && $('pat-gain').value) || '') + '\n';
        html += '   Beam width: ' + beam + '\n\n';
        html += 'Off-axis Angle    Discrimination\n';
        for (var i = 0; i < tb.rows.length; i++) {
          html += tb.rows[i].cells[0].textContent + '    ' + tb.rows[i].cells[1].textContent + '\n';
        }
        html += '\nTo save, save as Web page HTML only.\n</pre></body></html>';
        downloadText('passive-pattern.html', html, 'text/html');
      };
    }
    if ($('pat-reset')) {
      $('pat-reset').onclick = function () {
        ['pat-name', 'pat-width', 'pat-inc', 'pat-freq', 'pat-gain'].forEach(function (id) {
          if ($(id)) $(id).value = '';
        });
        if ($('pat-beam')) $('pat-beam').textContent = '';
        if ($('pat-body')) $('pat-body').innerHTML = '';
        setAuxStatus('');
      };
    }
    if ($('pat-cancel')) $('pat-cancel').onclick = auxGoWelcome;
    if ($('pat-help')) {
      $('pat-help').onclick = function () { auxOpenHelp('micshelp/AUXpattern1.aspx'); };
    }
  }

  function fillSelect(sel, files, emptyLabel, headerLabel) {
    if (!sel) return;
    sel.innerHTML = '';
    var opt0 = document.createElement('option');
    opt0.value = '';
    opt0.textContent = (files && files.length) ? headerLabel : emptyLabel;
    sel.appendChild(opt0);
    (files || []).forEach(function (f) {
      var o = document.createElement('option');
      o.value = f.name;
      o.textContent = f.name;
      sel.appendChild(o);
    });
  }

  function mountCoord() {
    setAuxStatus('');
    show($('coord-table'), false);
    var tsSel = $('coord-ts');
    var esSel = $('coord-es');
    RemIcsApi.filesList('TS').then(function (r) {
      fillSelect(tsSel, (r && r.ok && r.files) || [], '-- No TS Data Files --', 'TS Data Files');
    });
    RemIcsApi.filesList('ES').then(function (r) {
      fillSelect(esSel, (r && r.ok && r.files) || [], '-- No ES Data Files --', 'ES Data Files');
    });
    if (tsSel) tsSel.onchange = function () { if (esSel && tsSel.selectedIndex > 0) esSel.selectedIndex = 0; };
    if (esSel) esSel.onchange = function () { if (tsSel && esSel.selectedIndex > 0) tsSel.selectedIndex = 0; };
    if ($('coord-display')) {
      $('coord-display').onclick = function () {
        var tsOn = tsSel && tsSel.selectedIndex > 0;
        var esOn = esSel && esSel.selectedIndex > 0;
        if (tsOn && esOn) {
          setAuxStatus('Only one of the TS or ES pdfs may be chosen', true);
          return;
        }
        if (!tsOn && !esOn) {
          setAuxStatus('Must chose one of the TS or ES pdfs', true);
          return;
        }
        var filetype = tsOn ? 'TS' : 'ES';
        var name = tsOn ? tsSel.value : esSel.value;
        setAuxStatus('Checking...');
        RemIcsApi.auxCoordCheck(filetype, name).then(function (r) {
          if (!r.ok) { setAuxStatus(apiErr(r, 'Check failed'), true); return; }
          var tb = $('coord-table') && $('coord-table').tBodies[0];
          if (tb) tb.innerHTML = '';
          if (r.empty) {
            show($('coord-table'), false);
            setAuxStatus(r.message || 'There are no sites in this file.', true);
            return;
          }
          (r.rows || []).forEach(function (row) {
            var tr = document.createElement('tr');
            [row.call, row.name, row.lat, row.lng].forEach(function (v) {
              var td = document.createElement('td');
              td.textContent = v || '';
              tr.appendChild(td);
            });
            var td = document.createElement('td');
            td.innerHTML = row.requiresCoord
              ? "<span style='color:red'>Yes</span>"
              : "<span style='color:green'>No</span>";
            tr.appendChild(td);
            if (tb) tb.appendChild(tr);
          });
          show($('coord-table'), true);
          setAuxStatus('');
        }).catch(function (ex) { setAuxStatus(ex.message || String(ex), true); });
      };
    }
    if ($('coord-reset')) {
      $('coord-reset').onclick = function () {
        if (tsSel) tsSel.selectedIndex = 0;
        if (esSel) esSel.selectedIndex = 0;
        show($('coord-table'), false);
        setAuxStatus('');
      };
    }
    if ($('coord-cancel')) $('coord-cancel').onclick = auxGoWelcome;
    if ($('coord-help')) {
      $('coord-help').onclick = function () { auxOpenHelp('micshelp/AUXCoordChk1.aspx'); };
    }
  }

  function pcsParseLl(cLat, nMax, cSenses) {
    var pattern = /^(\d{1,3})-(\d{1,2})(-[\d\.]{0,5})?([NnSsEeWw]?)$/i;
    try {
      if (pattern.exec(cLat) == null) return 'No Match';
      var dDeg = parseInt(RegExp.$1, 10);
      var dMin = parseInt(RegExp.$2, 10);
      var dSec = parseFloat(String(RegExp.$3 || '').replace(/^-/, ''));
      var dSense = RegExp.$4;
      if (isNaN(dSec)) dSec = 0;
      if (isNaN(dMin)) dMin = 0;
      if (isNaN(dDeg)) dDeg = 0;
      if (!dSense) dSense = 'N';
      else {
        dSense = dSense.toUpperCase();
        if (cSenses.indexOf(dSense) === -1) {
          throw new Error('Sense must be ' + cSenses.charAt(0) + ' or ' + cSenses.charAt(1));
        }
      }
      if (dSec >= 60) throw new Error('60 seconds or more.');
      if (dMin >= 60) throw new Error('60 minutes or more.');
      if (dDeg > nMax) throw new Error('More than ' + nMax + ' degrees.');
      var retval = dDeg + (dMin / 60) + (dSec / 3600);
      if (dSense === 'S' || dSense === 'E') retval = -retval;
      return retval;
    } catch (e) {
      return 'Error: ' + (e.message || e);
    }
  }

  function pcsDisplayLl(dDegrees, nLat0Lng1) {
    var cSense;
    if (dDegrees >= 0) cSense = (nLat0Lng1 === 0) ? 'N' : 'W';
    else { cSense = (nLat0Lng1 === 0) ? 'S' : 'E'; dDegrees = -dDegrees; }
    var dDeg = Math.floor(dDegrees);
    dDegrees = (dDegrees - dDeg) * 60;
    var dMin = Math.floor(dDegrees);
    var dSec = (dDegrees - dMin) * 60;
    if (dSec > 59.99) { dSec = 0; dMin++; }
    if (dMin > 59) { dMin = 0; dDeg++; }
    var cSec = dSec.toFixed(2);
    if (cSec.length < 5) cSec = '0' + cSec;
    return dDeg + '-' + Math.floor(dMin / 10) + ((dMin % 10) + '-') + cSec + cSense;
  }

  function pcsRayend(dInLat, dInLng, dDist, dAz) {
    function toRadians(x) { return x * (Math.PI / 180); }
    function toDegrees(x) { return x * (180 / Math.PI); }
    function SIND(x) { return Math.sin(toRadians(x)); }
    function COSD(x) { return Math.cos(toRadians(x)); }
    function TAND(x) { return Math.tan(toRadians(x)); }
    function ATAND(x) { return toDegrees(Math.atan(x)); }
    var dOutLat, dOutLng;
    var bL = 90 - dInLat;
    var cL = (dDist / 6374.82) * (180 / Math.PI);
    var c1 = (bL - cL) / 2;
    var c2 = (bL + cL) / 2;
    var ah = dAz;
    if (ah === 0) {
      dOutLng = dInLng;
      dOutLat = dInLat + cL;
    } else if (dAz === 180) {
      dOutLng = dInLng;
      dOutLat = dInLat - cL;
    } else {
      var c3 = 1 / TAND(ah / 2);
      var u1 = (COSD(c1) / COSD(c2)) * c3;
      var u2 = (SIND(c1) / SIND(c2)) * c3;
      var v1 = ATAND(u1);
      var v2 = ATAND(u2);
      var bh = v1 + v2;
      var ch = v1 - v2;
      var u3 = (SIND((bh + ch) / 2) / SIND((bh - ch) / 2)) * TAND(c1);
      var aL = 2 * ATAND(u3);
      dOutLat = 90 - aL;
      dOutLng = dInLng - ch;
    }
    return [dOutLat, dOutLng];
  }

  function mountPcs() {
    setAuxStatus('');
    var cCalcType = '';
    var latEl = $('pcs-lat');
    var lngEl = $('pcs-lng');
    function setDeg(el, nMax, senses, label) {
      if (!el) return;
      el.onchange = el.onblur = function () {
        if (!el.value.trim()) { el.degrees = undefined; return; }
        var d = pcsParseLl(el.value.trim(), nMax, senses);
        if (typeof d !== 'number') {
          setAuxStatus(label + ' is not valid: ' + d, true);
          el.value = '';
          el.degrees = undefined;
          el.focus();
        } else {
          el.degrees = d;
          setAuxStatus('');
        }
      };
    }
    setDeg(latEl, 90, 'NS', 'Latitude');
    setDeg(lngEl, 180, 'EW', 'Longitude');
    function setPcsFields(azOn, rngOn, stepOn) {
      if ($('pcs-az')) { $('pcs-az').value = ''; $('pcs-az').disabled = !azOn; }
      if ($('pcs-rng')) { $('pcs-rng').value = ''; $('pcs-rng').disabled = !rngOn; }
      if ($('pcs-step')) { $('pcs-step').value = ''; $('pcs-step').disabled = !stepOn; }
    }
    function choose(type) {
      cCalcType = type;
      show($('pcs-fs-omni'), type === 'OMNI');
      show($('pcs-fs-sect'), type === 'SECT');
      show($('pcs-fs-mult'), type === 'MULT');
      if (type === 'OMNI') setPcsFields(false, false, false);
      else if (type === 'SECT') setPcsFields(true, true, false);
      else setPcsFields(true, true, true);
    }
    if ($('pcs-omni')) $('pcs-omni').onclick = function () { choose('OMNI'); };
    if ($('pcs-sect')) $('pcs-sect').onclick = function () { choose('SECT'); };
    if ($('pcs-mult')) $('pcs-mult').onclick = function () { choose('MULT'); };
    if ($('pcs-calc')) {
      $('pcs-calc').onclick = function () {
        var dInLat = latEl && latEl.degrees;
        var dInLng = lngEl && lngEl.degrees;
        var dRadius = parseFloat(($('pcs-radius') && $('pcs-radius').value) || '');
        if (dInLat == null || dInLng == null) {
          setAuxStatus('Need Latitude and Longitude', true);
          if (latEl) latEl.focus();
          return;
        }
        if (isNaN(dRadius)) {
          setAuxStatus('Need Radius', true);
          if ($('pcs-radius')) $('pcs-radius').focus();
          return;
        }
        if (!cCalcType) {
          setAuxStatus("Type: '' is not supported. Select a Base Station Type.", true);
          return;
        }
        var aEnd;
        if (cCalcType === 'OMNI') {
          aEnd = pcsRayend(dInLat, dInLng, dRadius, 0);
          if ($('pcs-n-lat')) $('pcs-n-lat').textContent = pcsDisplayLl(aEnd[0], 0);
          if ($('pcs-n-lng')) $('pcs-n-lng').textContent = pcsDisplayLl(aEnd[1], 1);
          aEnd = pcsRayend(dInLat, dInLng, dRadius, 90);
          if ($('pcs-e-lat')) $('pcs-e-lat').textContent = pcsDisplayLl(aEnd[0], 0);
          if ($('pcs-e-lng')) $('pcs-e-lng').textContent = pcsDisplayLl(aEnd[1], 1);
          aEnd = pcsRayend(dInLat, dInLng, dRadius, 180);
          if ($('pcs-s-lat')) $('pcs-s-lat').textContent = pcsDisplayLl(aEnd[0], 0);
          if ($('pcs-s-lng')) $('pcs-s-lng').textContent = pcsDisplayLl(aEnd[1], 1);
          aEnd = pcsRayend(dInLat, dInLng, dRadius, 270);
          if ($('pcs-w-lat')) $('pcs-w-lat').textContent = pcsDisplayLl(aEnd[0], 0);
          if ($('pcs-w-lng')) $('pcs-w-lng').textContent = pcsDisplayLl(aEnd[1], 1);
          setAuxStatus('');
          return;
        }
        var dCentreAz = parseFloat(($('pcs-az') && $('pcs-az').value) || '');
        var dRange = parseFloat(($('pcs-rng') && $('pcs-rng').value) || '');
        if (cCalcType === 'SECT') {
          if (isNaN(dCentreAz) || isNaN(dRange)) {
            setAuxStatus('Need centre azimuth and range', true);
            return;
          }
          aEnd = pcsRayend(dInLat, dInLng, dRadius, dCentreAz);
          if ($('pcs-c-az')) $('pcs-c-az').textContent = dCentreAz.toFixed(1);
          if ($('pcs-c-lat')) $('pcs-c-lat').textContent = pcsDisplayLl(aEnd[0], 0);
          if ($('pcs-c-lng')) $('pcs-c-lng').textContent = pcsDisplayLl(aEnd[1], 1);
          var dAz = dCentreAz - (dRange / 2);
          aEnd = pcsRayend(dInLat, dInLng, dRadius, dAz);
          if ($('pcs-min-az')) $('pcs-min-az').textContent = dAz.toFixed(1);
          if ($('pcs-min-lat')) $('pcs-min-lat').textContent = pcsDisplayLl(aEnd[0], 0);
          if ($('pcs-min-lng')) $('pcs-min-lng').textContent = pcsDisplayLl(aEnd[1], 1);
          dAz = dCentreAz + (dRange / 2);
          aEnd = pcsRayend(dInLat, dInLng, dRadius, dAz);
          if ($('pcs-max-az')) $('pcs-max-az').textContent = dAz.toFixed(1);
          if ($('pcs-max-lat')) $('pcs-max-lat').textContent = pcsDisplayLl(aEnd[0], 0);
          if ($('pcs-max-lng')) $('pcs-max-lng').textContent = pcsDisplayLl(aEnd[1], 1);
          setAuxStatus('');
          return;
        }
        var dStep = parseFloat(($('pcs-step') && $('pcs-step').value) || '');
        if (isNaN(dCentreAz) || isNaN(dRange) || isNaN(dStep)) {
          setAuxStatus('Need proper Centre, Range and Step', true);
          return;
        }
        if (dStep <= 0) {
          setAuxStatus('Step must be positive.', true);
          return;
        }
        var tb = $('pcs-multi') && $('pcs-multi').tBodies[0];
        if (tb) tb.innerHTML = '';
        var dAz2 = dCentreAz - (dRange / 2);
        var dEndAz = dCentreAz + (dRange / 2);
        var nNum = 0;
        function addRow(n, az) {
          var end = pcsRayend(dInLat, dInLng, dRadius, az);
          if (!tb) return;
          var tr = document.createElement('tr');
          [n, az.toFixed(2), pcsDisplayLl(end[0], 0), pcsDisplayLl(end[1], 1)].forEach(function (v) {
            var td = document.createElement('td');
            td.textContent = v;
            tr.appendChild(td);
          });
          tb.appendChild(tr);
        }
        while (dAz2 < dEndAz) {
          addRow(nNum++, dAz2);
          dAz2 += dStep;
        }
        addRow(nNum, dEndAz);
        setAuxStatus('');
      };
    }
    if ($('pcs-save')) {
      $('pcs-save').onclick = function () {
        var host = $('aux-pcs');
        if (!host) return;
        downloadText('pcs-coordination.html',
          '<html><head><title>PCS Coordination</title></head><body>' + host.innerHTML + '</body></html>',
          'text/html');
      };
    }
    if ($('pcs-cancel')) $('pcs-cancel').onclick = auxGoWelcome;
    if ($('pcs-help')) {
      $('pcs-help').onclick = function () { auxOpenHelp('micshelp/AUXpcscoord1.aspx'); };
    }
  }

  function mountHilo() {
    setAuxStatus('');
    show($('hilo-report'), false);
    if ($('hilo-report')) $('hilo-report').innerHTML = '';
    var sel = $('hilo-files');
    RemIcsApi.filesList('TS').then(function (r) {
      if (!sel) return;
      sel.innerHTML = '';
      var files = (r && r.ok && r.files) || [];
      if (!files.length) {
        var o = document.createElement('option');
        o.value = '';
        o.textContent = 'no proposed files';
        sel.appendChild(o);
        return;
      }
      files.forEach(function (f) {
        var opt = document.createElement('option');
        opt.value = f.name;
        opt.textContent = f.name;
        sel.appendChild(opt);
      });
    });
    if ($('hilo-check')) {
      $('hilo-check').onclick = function () {
        if (!sel || sel.selectedIndex < 0 || !sel.value) {
          setAuxStatus('You must select one of the proposed files.', true);
          return;
        }
        setAuxStatus('Checking...');
        show($('hilo-report'), false);
        RemIcsApi.auxHiloCheck(sel.value, ($('hilo-dist') && $('hilo-dist').value) || '5').then(function (r) {
          if (!r.ok) { setAuxStatus(apiErr(r, 'Check failed'), true); return; }
          if (r.note) setAuxStatus(r.note, true);
          else setAuxStatus('');
          if ($('hilo-report')) {
            $('hilo-report').innerHTML = r.html || '';
            show($('hilo-report'), true);
          }
        }).catch(function (ex) { setAuxStatus(ex.message || String(ex), true); });
      };
    }
    if ($('hilo-cancel')) $('hilo-cancel').onclick = auxGoWelcome;
    if ($('hilo-help')) {
      $('hilo-help').onclick = function () { auxOpenHelp('micshelp/AUXHilo1.aspx'); };
    }
  }

  function openNad27() {
    window.open(NRCAN_NTV2_URL, 'WndNRCAN',
      'toolbar=no,menubar=yes,scrollbars=yes,location=yes,resizable=yes,status=yes');
  }

  function mountNad27() {
    setAuxStatus('');
    openNad27();
    if ($('nad27-open')) $('nad27-open').onclick = openNad27;
    if ($('nad27-cancel')) $('nad27-cancel').onclick = auxGoWelcome;
  }

  function satFilled() {
    var n = 0;
    var i;
    for (i = 0; i < arguments.length; i++) {
      var el = $(arguments[i]);
      if (el && String(el.value || '').trim()) n++;
    }
    return n;
  }

  function mountSat() {
    setAuxStatus('');
    show($('sat-form'), true);
    show($('sat-result'), false);
    function val(id) { return ($(id) && $(id).value) ? $(id).value.trim() : ''; }
    function setOut(id, v) { if ($(id)) $(id).textContent = v == null ? '' : String(v); }
    if ($('sat-call')) {
      $('sat-call').onblur = function () {
        if (satFilled('sat-call')) {
          ['sat-lat', 'sat-lng', 'sat-utmn', 'sat-utme', 'sat-utmz'].forEach(function (id) {
            if ($(id)) $(id).value = '';
          });
        }
      };
      $('sat-call').oninput = function () {
        this.value = this.value.toUpperCase();
      };
    }
    function clearCallUtm() {
      if ($('sat-call')) $('sat-call').value = '';
      ['sat-utmn', 'sat-utme', 'sat-utmz'].forEach(function (id) { if ($(id)) $(id).value = ''; });
    }
    function clearCallLl() {
      if ($('sat-call')) $('sat-call').value = '';
      ['sat-lat', 'sat-lng'].forEach(function (id) { if ($(id)) $(id).value = ''; });
    }
    if ($('sat-lat')) $('sat-lat').onblur = function () { if (satFilled('sat-lat', 'sat-lng')) clearCallUtm(); };
    if ($('sat-lng')) $('sat-lng').onblur = function () { if (satFilled('sat-lat', 'sat-lng')) clearCallUtm(); };
    ['sat-utmn', 'sat-utme', 'sat-utmz'].forEach(function (id) {
      if ($(id)) $(id).onblur = function () {
        if (satFilled('sat-utmn', 'sat-utme', 'sat-utmz')) clearCallLl();
      };
    });
    if ($('sat-next')) {
      $('sat-next').onclick = function () {
        if (satFilled('sat-call')) {
          if (satFilled('sat-antht', 'sat-name', 'sat-satlng', 'sat-refract') < 4) {
            setAuxStatus('You must enter Antenna Height, Satellite Name, Longitude, and Refraction Index.', true);
            if ($('sat-antht')) $('sat-antht').focus();
            return;
          }
        } else if (satFilled('sat-lat', 'sat-lng')) {
          if (satFilled('sat-lat', 'sat-lng') < 2) {
            setAuxStatus('You must enter both Latitude and Longitude.', true);
            if ($('sat-lat')) $('sat-lat').focus();
            return;
          }
          if (satFilled('sat-grnd', 'sat-antht', 'sat-name', 'sat-satlng', 'sat-refract') < 5) {
            setAuxStatus('You must enter Altitude, Antenna Height, Satellite Name, Longitude, and Refraction Index.', true);
            if ($('sat-grnd')) $('sat-grnd').focus();
            return;
          }
        } else if (satFilled('sat-utmn', 'sat-utme', 'sat-utmz')) {
          if (satFilled('sat-utmn', 'sat-utme', 'sat-utmz') < 3) {
            setAuxStatus('You must enter all the UTM coordinates.', true);
            if ($('sat-utmn')) $('sat-utmn').focus();
            return;
          }
          if (satFilled('sat-grnd', 'sat-antht', 'sat-name', 'sat-satlng', 'sat-refract') < 5) {
            setAuxStatus('You must enter Altitude, Antenna Height, Satellite Name, Longitude, and Refraction Index.', true);
            if ($('sat-grnd')) $('sat-grnd').focus();
            return;
          }
        } else {
          setAuxStatus('You must enter a call sign or coordinates.', true);
          if ($('sat-call')) $('sat-call').focus();
          return;
        }
        setAuxStatus('Calculating...');
        RemIcsApi.auxSataze({
          call: val('sat-call'),
          lat: val('sat-lat'),
          lng: val('sat-lng'),
          utmNorth: val('sat-utmn'),
          utmEast: val('sat-utme'),
          utmZone: val('sat-utmz'),
          grnd: val('sat-grnd'),
          antHt: val('sat-antht'),
          satName: val('sat-name'),
          satLng: val('sat-satlng'),
          refract: val('sat-refract') || '330'
        }).then(function (r) {
          if (!r.ok) { setAuxStatus(apiErr(r, 'Satellite bearing failed'), true); return; }
          setOut('sat-out-call', r.call);
          setOut('sat-out-site', r.siteName);
          setOut('sat-out-lat84', r.lat84);
          setOut('sat-out-lng84', r.lng84);
          setOut('sat-out-grnd', r.grnd);
          setOut('sat-out-utmn', r.utmNorth);
          setOut('sat-out-utme', r.utmEast);
          setOut('sat-out-utmz', r.utmZone);
          setOut('sat-out-antht', r.antHt);
          setOut('sat-out-name', r.satName);
          setOut('sat-out-satlng', r.satLng);
          setOut('sat-out-refract', r.refract);
          setOut('sat-out-az', r.azimuth);
          setOut('sat-out-el', r.elevation);
          setOut('sat-out-rel', r.refElevation);
          show($('sat-form'), false);
          show($('sat-result'), true);
          setAuxStatus('');
        }).catch(function (ex) { setAuxStatus(ex.message || String(ex), true); });
      };
    }
    if ($('sat-reset')) {
      $('sat-reset').onclick = function () {
        ['sat-call', 'sat-lat', 'sat-lng', 'sat-utmn', 'sat-utme', 'sat-utmz',
          'sat-grnd', 'sat-antht', 'sat-name', 'sat-satlng'].forEach(function (id) {
          if ($(id)) $(id).value = '';
        });
        if ($('sat-refract')) $('sat-refract').value = '330';
        setAuxStatus('');
        if ($('sat-call')) $('sat-call').focus();
      };
    }
    if ($('sat-cancel')) $('sat-cancel').onclick = auxGoWelcome;
    if ($('sat-result-cancel')) $('sat-result-cancel').onclick = auxGoWelcome;
    if ($('sat-back')) {
      $('sat-back').onclick = function () {
        show($('sat-result'), false);
        show($('sat-form'), true);
        setAuxStatus('');
      };
    }
    if ($('sat-help')) {
      $('sat-help').onclick = function () { auxOpenHelp('micshelp/AUXSataze1.aspx'); };
    }
    if ($('sat-result-help')) {
      $('sat-result-help').onclick = function () { auxOpenHelp('micshelp/AUXSataze2.aspx'); };
    }
    if ($('sat-call')) $('sat-call').focus();
  }

  var orbitState = { a: null, b: null };

  function orbitShowStep(step) {
    show($('orbit-site-a'), step === 'a');
    show($('orbit-site-b'), step === 'b');
    show($('orbit-options'), step === 'opt');
    show($('orbit-result'), step === 'res');
    if ($('orbit-heading')) {
      $('orbit-heading').textContent = step === 'a'
        ? 'Geostationary Orbit Intersection - Site A'
        : 'Geostationary Orbit Intersection';
      show($('orbit-heading'), step === 'a' || step === 'b');
    }
  }

  function orbitVal(pfx) {
    return {
      call: (($(pfx + '-call') && $(pfx + '-call').value) || '').trim(),
      lat: (($(pfx + '-lat') && $(pfx + '-lat').value) || '').trim(),
      lng: (($(pfx + '-lng') && $(pfx + '-lng').value) || '').trim(),
      utmNorth: (($(pfx + '-utmn') && $(pfx + '-utmn').value) || '').trim(),
      utmEast: (($(pfx + '-utme') && $(pfx + '-utme').value) || '').trim(),
      utmZone: (($(pfx + '-utmz') && $(pfx + '-utmz').value) || '').trim(),
      alt: (($(pfx + '-alt') && $(pfx + '-alt').value) || '').trim(),
      antHt: (($(pfx + '-antht') && $(pfx + '-antht').value) || '').trim()
    };
  }

  function orbitApplySite(pfx, r) {
    if ($(pfx + '-call')) $(pfx + '-call').value = r.call || '';
    if ($(pfx + '-sitename')) $(pfx + '-sitename').textContent = r.siteName || '';
    if ($(pfx + '-lat')) $(pfx + '-lat').value = r.lat84 || '';
    if ($(pfx + '-lng')) $(pfx + '-lng').value = r.lng84 || '';
    if ($(pfx + '-utmn')) $(pfx + '-utmn').value = r.utmNorth || '';
    if ($(pfx + '-utme')) $(pfx + '-utme').value = r.utmEast || '';
    if ($(pfx + '-utmz')) $(pfx + '-utmz').value = r.utmZone || '';
    if ($(pfx + '-alt')) $(pfx + '-alt').value = r.alt || '';
    if ($(pfx + '-antht')) $(pfx + '-antht').value = r.antHt || '';
    ['call', 'lat', 'lng', 'utmn', 'utme', 'utmz', 'alt', 'antht'].forEach(function (k) {
      var el = $(pfx + '-' + k);
      if (el) el.disabled = true;
    });
  }

  function orbitEnableSite(pfx, on) {
    ['call', 'lat', 'lng', 'utmn', 'utme', 'utmz', 'alt', 'antht'].forEach(function (k) {
      var el = $(pfx + '-' + k);
      if (el) el.disabled = !on;
    });
  }

  function orbitDistText(a, b) {
    try {
      if (typeof dist !== 'function' || typeof pcsParseLl !== 'function') return null;
      var lat1 = pcsParseLl(a.lat84, 90, 'NS');
      var lng1 = pcsParseLl(a.lng84, 180, 'WE');
      var lat2 = pcsParseLl(b.lat84, 90, 'NS');
      var lng2 = pcsParseLl(b.lng84, 180, 'WE');
      if (typeof lat1 !== 'number' || typeof lng1 !== 'number' ||
          typeof lat2 !== 'number' || typeof lng2 !== 'number') return null;
      var o = dist(lat1, lng1, lat2, lng2);
      return {
        km: Number(o.DistanceKm).toFixed(2),
        ab: Number(o.Bearing12).toFixed(1),
        ba: Number(o.Bearing21).toFixed(1)
      };
    } catch (ex) {
      return null;
    }
  }

  function mountOrbit() {
    setAuxStatus('');
    orbitState = { a: null, b: null };
    ['orb-a', 'orb-b'].forEach(function (pfx) {
      ['call', 'lat', 'lng', 'utmn', 'utme', 'utmz', 'alt', 'antht'].forEach(function (k) {
        var el = $(pfx + '-' + k);
        if (el) { el.value = ''; el.disabled = false; }
      });
      if ($(pfx + '-sitename')) $(pfx + '-sitename').textContent = '';
    });
    if ($('orb-trueaz')) { $('orb-trueaz').checked = false; $('orb-trueaz').disabled = false; }
    if ($('orb-trueaz-val')) { $('orb-trueaz-val').value = ''; $('orb-trueaz-val').disabled = false; }
    if ($('orb-trueel-val')) { $('orb-trueel-val').value = ''; $('orb-trueel-val').disabled = false; }
    orbitShowStep('a');
    if ($('orb-a-next')) {
      $('orb-a-next').onclick = function () {
        setAuxStatus('Looking up site A...');
        RemIcsApi.auxOrbitCoords(orbitVal('orb-a')).then(function (r) {
          if (!r.ok) { setAuxStatus(apiErr(r, 'Site A failed'), true); return; }
          orbitState.a = r;
          orbitApplySite('orb-a', r);
          orbitShowStep('b');
          setAuxStatus('');
          if ($('orb-b-call')) $('orb-b-call').focus();
        }).catch(function (ex) { setAuxStatus(ex.message || String(ex), true); });
      };
    }
    if ($('orb-b-next')) {
      $('orb-b-next').onclick = function () {
        setAuxStatus('Looking up site B...');
        RemIcsApi.auxOrbitCoords(orbitVal('orb-b')).then(function (r) {
          if (!r.ok) { setAuxStatus(apiErr(r, 'Site B failed'), true); return; }
          orbitState.b = r;
          orbitApplySite('orb-b', r);
          if ($('orb-trueaz') && !$('orb-trueaz').checked) {
            $('orb-trueaz').disabled = true;
            if ($('orb-trueaz-val')) $('orb-trueaz-val').disabled = true;
            if ($('orb-trueel-val')) $('orb-trueel-val').disabled = true;
          }
          var d = orbitDistText(orbitState.a, orbitState.b);
          if ($('orb-opt-dist')) $('orb-opt-dist').textContent = d ? d.km : '';
          if ($('orb-opt-ab')) $('orb-opt-ab').textContent = d ? d.ab : '';
          if ($('orb-opt-ba')) $('orb-opt-ba').textContent = d ? d.ba : '';
          orbitShowStep('opt');
          setAuxStatus('');
        }).catch(function (ex) { setAuxStatus(ex.message || String(ex), true); });
      };
    }
    if ($('orb-b-back')) {
      $('orb-b-back').onclick = function () {
        orbitEnableSite('orb-a', true);
        orbitShowStep('a');
        setAuxStatus('');
      };
    }
    if ($('orb-opt-back')) {
      $('orb-opt-back').onclick = function () {
        orbitEnableSite('orb-b', true);
        if ($('orb-trueaz')) $('orb-trueaz').disabled = false;
        if ($('orb-trueaz-val')) $('orb-trueaz-val').disabled = false;
        if ($('orb-trueel-val')) $('orb-trueel-val').disabled = false;
        orbitShowStep('b');
        setAuxStatus('');
      };
    }
    if ($('orb-run')) {
      $('orb-run').onclick = function () {
        var a = orbitState.a || {};
        var b = orbitState.b || {};
        setAuxStatus('Running...');
        RemIcsApi.auxOrbitRun({
          call1: a.call, lat1: a.lat84, lng1: a.lng84, alt1: a.alt, antHt1: a.antHt,
          call2: b.call, lat2: b.lat84, lng2: b.lng84, alt2: b.alt, antHt2: b.antHt,
          trueAz: ($('orb-trueaz') && $('orb-trueaz').checked) ? '1' : '',
          trueAzVal: (($('orb-trueaz-val') && $('orb-trueaz-val').value) || '').trim(),
          trueElVal: (($('orb-trueel-val') && $('orb-trueel-val').value) || '').trim()
        }).then(function (r) {
          if (!r.ok) { setAuxStatus(apiErr(r, 'Orbit run failed'), true); return; }
          function setT(id, v) { if ($(id)) $(id).textContent = v == null ? '' : String(v); }
          setT('orb-r-call1', r.call1); setT('orb-r-call2', r.call2);
          setT('orb-r-lat1', r.lat1); setT('orb-r-lat2', r.lat2);
          setT('orb-r-lng1', r.lng1); setT('orb-r-lng2', r.lng2);
          setT('orb-r-alt1', r.alt1); setT('orb-r-alt2', r.alt2);
          setT('orb-r-ant1', r.antHt1); setT('orb-r-ant2', r.antHt2);
          setT('orb-r-dist', r.dist); setT('orb-r-az', r.azim); setT('orb-r-el', r.elev);
          setT('orb-r-insl', r.insL); setT('orb-r-mas', r.minAngSep);
          setT('orb-r-e1', r.e1_10); setT('orb-r-e2', r.e10_15); setT('orb-r-e3', r.eGt15);
          setT('orb-r-caz1', r.crAzSt); setT('orb-r-caz2', r.crAzEnd);
          setT('orb-r-clng1', r.crLongFrom); setT('orb-r-clng2', r.crLongTo);
          setT('orb-r-note', r.note);
          var extra = '';
          if (r.trueAz) extra += 'True azimuth and elevation angle were used. ';
          if (r.swapped) extra += 'Sites swapped.';
          setT('orb-r-swapped', extra);
          var host = $('orb-r-sats');
          if (host) {
            host.innerHTML = '';
            if (r.sats && r.sats.length) {
              var tbl = document.createElement('table');
              tbl.width = '90%';
              tbl.innerHTML = '<tr><td><b>Norad Id</b></td><td><b>Satellite Name</b></td><td><b>Orbit</b></td><td><b>Longitude</b></td></tr>';
              r.sats.forEach(function (s) {
                var tr = document.createElement('tr');
                [s.norad, s.name, s.orbit, s.lng].forEach(function (v) {
                  var td = document.createElement('td');
                  td.textContent = v || '';
                  tr.appendChild(td);
                });
                tbl.appendChild(tr);
              });
              host.appendChild(tbl);
            } else if (r.note && r.note.indexOf('critical longitudes') >= 0) {
              host.innerHTML = '<br/>-- None found within these longitudes --<br/>';
            }
          }
          orbitShowStep('res');
          setAuxStatus('');
        }).catch(function (ex) { setAuxStatus(ex.message || String(ex), true); });
      };
    }
    if ($('orb-r-back')) {
      $('orb-r-back').onclick = function () { orbitShowStep('opt'); setAuxStatus(''); };
    }
    if ($('orb-a-cancel')) $('orb-a-cancel').onclick = auxGoWelcome;
    if ($('orb-r-cancel')) $('orb-r-cancel').onclick = auxGoWelcome;
    if ($('orb-help')) {
      $('orb-help').onclick = function () { auxOpenHelp('micshelp/AUXorbit1.aspx'); };
    }
    if ($('orb-save')) {
      $('orb-save').onclick = function () {
        var host = $('orbit-result');
        if (!host) return;
        downloadText('AUXOrbit.htm',
          '<html><head><title>Geostationary Orbit Intersection</title></head><body>' + host.innerHTML + '</body></html>',
          'text/html');
      };
    }
    if ($('orb-print')) {
      $('orb-print').onclick = function () { window.print(); };
    }
    if ($('orb-a-call')) $('orb-a-call').focus();
  }

  var ohlState = { a: null, b: null, serial: '', url: '', text: '', html: '', repType: '' };

  function ohlShowStep(step) {
    show($('ohl-site-a'), step === 'a');
    show($('ohl-site-b'), step === 'b');
    show($('ohl-options'), step === 'opt');
    show($('ohl-result'), step === 'res');
    if ($('ohl-heading')) {
      $('ohl-heading').textContent = step === 'a'
        ? 'Over Horizon Loss - Site A'
        : 'Over Horizon Loss';
      show($('ohl-heading'), step === 'a' || step === 'b');
    }
  }

  function ohlVal(pfx) {
    return {
      call: (($(pfx + '-call') && $(pfx + '-call').value) || '').trim(),
      lat: (($(pfx + '-lat') && $(pfx + '-lat').value) || '').trim(),
      lng: (($(pfx + '-lng') && $(pfx + '-lng').value) || '').trim(),
      utmNorth: (($(pfx + '-utmn') && $(pfx + '-utmn').value) || '').trim(),
      utmEast: (($(pfx + '-utme') && $(pfx + '-utme').value) || '').trim(),
      utmZone: (($(pfx + '-utmz') && $(pfx + '-utmz').value) || '').trim(),
      antHt: (($(pfx + '-antht') && $(pfx + '-antht').value) || '').trim()
    };
  }

  function ohlApplySite(pfx, r) {
    if ($(pfx + '-call')) $(pfx + '-call').value = r.call || '';
    if ($(pfx + '-sitename')) $(pfx + '-sitename').textContent = r.siteName || '';
    if ($(pfx + '-lat')) $(pfx + '-lat').value = r.lat84 || '';
    if ($(pfx + '-lng')) $(pfx + '-lng').value = r.lng84 || '';
    if ($(pfx + '-utmn')) $(pfx + '-utmn').value = r.utmNorth || '';
    if ($(pfx + '-utme')) $(pfx + '-utme').value = r.utmEast || '';
    if ($(pfx + '-utmz')) $(pfx + '-utmz').value = r.utmZone || '';
    if ($(pfx + '-antht')) $(pfx + '-antht').value = r.antHt || '';
    ['call', 'lat', 'lng', 'utmn', 'utme', 'utmz', 'antht'].forEach(function (k) {
      var el = $(pfx + '-' + k);
      if (el) el.disabled = true;
    });
  }

  function ohlEnableSite(pfx, on) {
    ['call', 'lat', 'lng', 'utmn', 'utme', 'utmz', 'antht'].forEach(function (k) {
      var el = $(pfx + '-' + k);
      if (el) el.disabled = !on;
    });
  }

  function ohlRadio(name) {
    var nodes = document.getElementsByName(name);
    var i;
    for (i = 0; i < nodes.length; i++) {
      if (nodes[i].checked) return nodes[i].value;
    }
    return '';
  }

  function mountOhl() {
    setAuxStatus('');
    ohlState = { a: null, b: null, serial: '', url: '', text: '', html: '', repType: '' };
    ['ohl-a', 'ohl-b'].forEach(function (pfx) {
      ['call', 'lat', 'lng', 'utmn', 'utme', 'utmz', 'antht'].forEach(function (k) {
        var el = $(pfx + '-' + k);
        if (el) { el.value = ''; el.disabled = false; }
      });
      if ($(pfx + '-sitename')) $(pfx + '-sitename').textContent = '';
    });
    if ($('ohl-k')) { $('ohl-k').value = '1.333333'; $('ohl-k').disabled = false; }
    if ($('ohl-freq')) { $('ohl-freq').value = ''; $('ohl-freq').disabled = false; }
    ['ohl-pol-h', 'ohl-pol-v', 'ohl-cli-0', 'ohl-cli-1', 'ohl-cli-2',
      'ohl-rep-plain', 'ohl-rep-html', 'ohl-rep-csv'].forEach(function (id) {
      if ($(id)) $(id).disabled = false;
    });
    if ($('ohl-pol-h')) $('ohl-pol-h').checked = true;
    if ($('ohl-cli-0')) $('ohl-cli-0').checked = true;
    ['ohl-rep-plain', 'ohl-rep-html', 'ohl-rep-csv'].forEach(function (id) {
      if ($(id)) $(id).checked = false;
    });
    if ($('ohl-report')) $('ohl-report').innerHTML = '';
    ohlShowStep('a');
    if ($('ohl-a-next')) {
      $('ohl-a-next').onclick = function () {
        var fields = ohlVal('ohl-a');
        setAuxStatus('Looking up site A...');
        RemIcsApi.auxOhlCoords(fields).then(function (r) {
          if (!r.ok) { setAuxStatus(apiErr(r, 'Site A failed'), true); return; }
          ohlState.a = r;
          ohlApplySite('ohl-a', r);
          ohlShowStep('b');
          setAuxStatus('');
          if ($('ohl-b-call')) $('ohl-b-call').focus();
        }).catch(function (ex) { setAuxStatus(ex.message || String(ex), true); });
      };
    }
    if ($('ohl-b-next')) {
      $('ohl-b-next').onclick = function () {
        var fields = ohlVal('ohl-b');
        fields.timeout = '60';
        setAuxStatus('Looking up site B...');
        RemIcsApi.auxOhlCoords(fields).then(function (r) {
          if (!r.ok) { setAuxStatus(apiErr(r, 'Site B failed'), true); return; }
          ohlState.b = r;
          ohlApplySite('ohl-b', r);
          var d = orbitDistText(ohlState.a, ohlState.b);
          if ($('ohl-opt-dist')) $('ohl-opt-dist').textContent = d ? d.km : '';
          if ($('ohl-opt-ab')) $('ohl-opt-ab').textContent = d ? d.ab : '';
          if ($('ohl-opt-ba')) $('ohl-opt-ba').textContent = d ? d.ba : '';
          ohlShowStep('opt');
          setAuxStatus('');
          if ($('ohl-freq')) $('ohl-freq').focus();
        }).catch(function (ex) { setAuxStatus(ex.message || String(ex), true); });
      };
    }
    if ($('ohl-b-back')) {
      $('ohl-b-back').onclick = function () {
        ohlEnableSite('ohl-a', true);
        ohlShowStep('a');
        setAuxStatus('');
      };
    }
    if ($('ohl-opt-back')) {
      $('ohl-opt-back').onclick = function () {
        ohlEnableSite('ohl-b', true);
        ohlShowStep('b');
        setAuxStatus('');
      };
    }
    if ($('ohl-run')) {
      $('ohl-run').onclick = function () {
        var a = ohlState.a || {};
        var b = ohlState.b || {};
        var k = (($('ohl-k') && $('ohl-k').value) || '').trim();
        var freq = (($('ohl-freq') && $('ohl-freq').value) || '').trim();
        var repType = ohlRadio('ohl-rep');
        if (!k) { setAuxStatus('You must enter a K value.', true); if ($('ohl-k')) $('ohl-k').focus(); return; }
        if (!freq) { setAuxStatus('You must enter a frequency.', true); if ($('ohl-freq')) $('ohl-freq').focus(); return; }
        if (!repType) { setAuxStatus('You must select at least one form of report.', true); return; }
        setAuxStatus('Running...');
        RemIcsApi.auxOhlRun({
          call1: a.call, siteName1: a.siteName, lat1: a.lat84, lng1: a.lng84, antHt1: a.antHt,
          call2: b.call, siteName2: b.siteName, lat2: b.lat84, lng2: b.lng84, antHt2: b.antHt,
          k: k, freq: freq, pol: ohlRadio('ohl-pol') || '0', climate: ohlRadio('ohl-cli') || '0',
          repType: repType
        }).then(function (r) {
          if (!r.ok) { setAuxStatus(apiErr(r, 'Over Horizon Loss failed'), true); return; }
          ohlState.serial = r.serial || '';
          ohlState.url = r.url || '';
          ohlState.text = r.text || '';
          ohlState.html = r.html || '';
          ohlState.repType = r.repType || repType;
          var host = $('ohl-report');
          if (host) {
            if (ohlState.repType === 'HTML') {
              host.style.whiteSpace = 'normal';
              host.innerHTML = ohlState.html || '';
            } else {
              host.style.whiteSpace = 'pre';
              host.textContent = ohlState.text || '';
            }
          }
          ohlShowStep('res');
          setAuxStatus('');
        }).catch(function (ex) { setAuxStatus(ex.message || String(ex), true); });
      };
    }
    if ($('ohl-r-back')) {
      $('ohl-r-back').onclick = function () { ohlShowStep('opt'); setAuxStatus(''); };
    }
    if ($('ohl-a-cancel')) $('ohl-a-cancel').onclick = auxGoWelcome;
    if ($('ohl-r-cancel')) $('ohl-r-cancel').onclick = auxGoWelcome;
    if ($('ohl-help')) {
      $('ohl-help').onclick = function () { auxOpenHelp('micshelp/AUXOHLoss.aspx'); };
    }
    if ($('ohl-open')) {
      $('ohl-open').onclick = function () {
        if (ohlState.url) window.open(ohlState.url, 'WndReport',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,status=yes');
      };
    }
    if ($('ohl-save')) {
      $('ohl-save').onclick = function () {
        var name = 'p-ohl.htm';
        var mime = 'text/html';
        var body = ohlState.html || ohlState.text || '';
        if (ohlState.repType === 'CSV') {
          name = 'p-ohl.csv';
          mime = 'text/csv';
          body = ohlState.text || '';
        } else if (ohlState.repType === 'NOHTML') {
          name = 'p-ohl.txt';
          mime = 'text/plain';
          body = ohlState.text || '';
        }
        downloadText(name, body, mime);
      };
    }
    if ($('ohl-email')) {
      $('ohl-email').onclick = function () {
        if (!ohlState.serial) {
          setAuxStatus('Run the calculation first.', true);
          return;
        }
        setAuxStatus('Queueing email...');
        RemIcsApi.auxOhlEmail(ohlState.serial).then(function (r) {
          if (!r.ok) { setAuxStatus(apiErr(r, 'Email failed'), true); return; }
          setAuxStatus(r.message || 'Email queued.');
        }).catch(function (ex) { setAuxStatus(ex.message || String(ex), true); });
      };
    }
    if ($('ohl-a-call')) $('ohl-a-call').focus();
  }

  var terState = { a: null, b: null, serial: '', url: '', text: '', html: '', repType: '' };

  function terShowStep(step) {
    show($('ter-site-a'), step === 'a');
    show($('ter-site-b'), step === 'b');
    show($('ter-options'), step === 'opt');
    show($('ter-result'), step === 'res');
    if ($('ter-heading')) {
      $('ter-heading').textContent = step === 'a'
        ? 'Terrain Profiling - Site A'
        : 'Terrain Profiling';
      show($('ter-heading'), step === 'a' || step === 'b');
    }
  }

  function terVal(pfx) {
    return {
      call: (($(pfx + '-call') && $(pfx + '-call').value) || '').trim(),
      lat: (($(pfx + '-lat') && $(pfx + '-lat').value) || '').trim(),
      lng: (($(pfx + '-lng') && $(pfx + '-lng').value) || '').trim(),
      utmNorth: (($(pfx + '-utmn') && $(pfx + '-utmn').value) || '').trim(),
      utmEast: (($(pfx + '-utme') && $(pfx + '-utme').value) || '').trim(),
      utmZone: (($(pfx + '-utmz') && $(pfx + '-utmz').value) || '').trim()
    };
  }

  function terApplySite(pfx, r) {
    if ($(pfx + '-call')) $(pfx + '-call').value = r.call || '';
    if ($(pfx + '-sitename')) $(pfx + '-sitename').textContent = r.siteName || '';
    if ($(pfx + '-lat')) $(pfx + '-lat').value = r.lat84 || '';
    if ($(pfx + '-lng')) $(pfx + '-lng').value = r.lng84 || '';
    if ($(pfx + '-utmn')) $(pfx + '-utmn').value = r.utmNorth || '';
    if ($(pfx + '-utme')) $(pfx + '-utme').value = r.utmEast || '';
    if ($(pfx + '-utmz')) $(pfx + '-utmz').value = r.utmZone || '';
    ['call', 'lat', 'lng', 'utmn', 'utme', 'utmz'].forEach(function (k) {
      var el = $(pfx + '-' + k);
      if (el) el.disabled = true;
    });
  }

  function terEnableSite(pfx, on) {
    ['call', 'lat', 'lng', 'utmn', 'utme', 'utmz'].forEach(function (k) {
      var el = $(pfx + '-' + k);
      if (el) el.disabled = !on;
    });
  }

  function mountTerrain() {
    setAuxStatus('');
    terState = { a: null, b: null, serial: '', url: '', text: '', html: '', repType: '' };
    ['ter-a', 'ter-b'].forEach(function (pfx) {
      ['call', 'lat', 'lng', 'utmn', 'utme', 'utmz'].forEach(function (k) {
        var el = $(pfx + '-' + k);
        if (el) { el.value = ''; el.disabled = false; }
      });
      if ($(pfx + '-sitename')) $(pfx + '-sitename').textContent = '';
    });
    if ($('ter-step')) { $('ter-step').value = '1.0'; $('ter-step').disabled = false; }
    if ($('ter-rep-plain')) $('ter-rep-plain').checked = true;
    if ($('ter-report')) $('ter-report').innerHTML = '';
    terShowStep('a');
    if ($('ter-a-next')) {
      $('ter-a-next').onclick = function () {
        setAuxStatus('Looking up site A...');
        RemIcsApi.auxTerrainCoords(terVal('ter-a')).then(function (r) {
          if (!r.ok) { setAuxStatus(apiErr(r, 'Site A failed'), true); return; }
          terState.a = r;
          terApplySite('ter-a', r);
          terShowStep('b');
          setAuxStatus('');
          if ($('ter-b-call')) $('ter-b-call').focus();
        }).catch(function (ex) { setAuxStatus(ex.message || String(ex), true); });
      };
    }
    if ($('ter-b-next')) {
      $('ter-b-next').onclick = function () {
        setAuxStatus('Looking up site B...');
        RemIcsApi.auxTerrainCoords(terVal('ter-b')).then(function (r) {
          if (!r.ok) { setAuxStatus(apiErr(r, 'Site B failed'), true); return; }
          terState.b = r;
          terApplySite('ter-b', r);
          var d = orbitDistText(terState.a, terState.b);
          if ($('ter-opt-dist')) $('ter-opt-dist').textContent = d ? (d.km + 'km') : '';
          if ($('ter-opt-ab')) $('ter-opt-ab').textContent = d ? d.ab : '';
          if ($('ter-opt-ba')) $('ter-opt-ba').textContent = d ? d.ba : '';
          terShowStep('opt');
          setAuxStatus('');
          if ($('ter-step')) $('ter-step').focus();
        }).catch(function (ex) { setAuxStatus(ex.message || String(ex), true); });
      };
    }
    if ($('ter-b-back')) {
      $('ter-b-back').onclick = function () {
        terEnableSite('ter-a', true);
        terShowStep('a');
        setAuxStatus('');
      };
    }
    if ($('ter-opt-back')) {
      $('ter-opt-back').onclick = function () {
        terEnableSite('ter-b', true);
        terShowStep('b');
        setAuxStatus('');
      };
    }
    if ($('ter-run')) {
      $('ter-run').onclick = function () {
        var a = terState.a || {};
        var b = terState.b || {};
        var step = (($('ter-step') && $('ter-step').value) || '').trim();
        if (!step) { setAuxStatus('You must enter a step value.', true); if ($('ter-step')) $('ter-step').focus(); return; }
        setAuxStatus('Running...');
        RemIcsApi.auxTerrainRun({
          call1: a.call, siteName1: a.siteName, lat1: a.lat84, lng1: a.lng84,
          call2: b.call, siteName2: b.siteName, lat2: b.lat84, lng2: b.lng84,
          step: step, repType: ohlRadio('ter-rep') || 'NOHTML'
        }).then(function (r) {
          if (!r.ok) { setAuxStatus(apiErr(r, 'Terrain profile failed'), true); return; }
          terState.serial = r.serial || '';
          terState.url = r.url || '';
          terState.text = r.text || '';
          terState.html = r.html || '';
          terState.repType = r.repType || 'NOHTML';
          var host = $('ter-report');
          if (host) {
            if (terState.repType === 'HTML') {
              host.style.whiteSpace = 'normal';
              host.innerHTML = terState.html || '';
            } else {
              host.style.whiteSpace = 'pre';
              host.textContent = terState.text || '';
            }
          }
          terShowStep('res');
          setAuxStatus('');
        }).catch(function (ex) { setAuxStatus(ex.message || String(ex), true); });
      };
    }
    if ($('ter-r-back')) {
      $('ter-r-back').onclick = function () { terShowStep('opt'); setAuxStatus(''); };
    }
    if ($('ter-a-cancel')) $('ter-a-cancel').onclick = auxGoWelcome;
    if ($('ter-r-cancel')) $('ter-r-cancel').onclick = auxGoWelcome;
    if ($('ter-help')) {
      $('ter-help').onclick = function () { auxOpenHelp('micshelp/AUXTerrain1.aspx'); };
    }
    if ($('ter-open')) {
      $('ter-open').onclick = function () {
        if (terState.url) window.open(terState.url, 'WndReport',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,status=yes');
      };
    }
    if ($('ter-save')) {
      $('ter-save').onclick = function () {
        var name = 'p-terrain.txt';
        var mime = 'text/plain';
        var body = terState.text || '';
        if (terState.repType === 'HTML') { name = 'p-terrain.htm'; mime = 'text/html'; body = terState.html || ''; }
        else if (terState.repType === 'CSV') { name = 'p-terrain.csv'; mime = 'text/csv'; }
        else if (terState.repType === 'PL3') { name = 'p-terrain.pl3'; }
        downloadText(name, body, mime);
      };
    }
    if ($('ter-email')) {
      $('ter-email').onclick = function () {
        if (!terState.serial) { setAuxStatus('Run the calculation first.', true); return; }
        setAuxStatus('Queueing email...');
        RemIcsApi.auxTerrainEmail(terState.serial).then(function (r) {
          if (!r.ok) { setAuxStatus(apiErr(r, 'Email failed'), true); return; }
          setAuxStatus(r.message || 'Email queued.');
        }).catch(function (ex) { setAuxStatus(ex.message || String(ex), true); });
      };
    }
    if ($('ter-a-call')) $('ter-a-call').focus();
  }

  var pfdState = { site: null };

  function pfdShowStep(step) {
    show($('pfd-site'), step === 'site');
    show($('pfd-options'), step === 'opt');
  }

  function pfdFillAnt(ant) {
    if ($('pfd-acode')) $('pfd-acode').value = ant.acode || '';
    if ($('pfd-aht')) $('pfd-aht').value = ant.aht || '';
    if ($('pfd-azim')) $('pfd-azim').value = ant.azim || '';
    if ($('pfd-txpwr')) $('pfd-txpwr').value = ant.txpwr || '';
    if ($('pfd-fsl')) $('pfd-fsl').value = ant.fsl || '';
    if ($('pfd-altr')) $('pfd-altr').focus();
  }

  function pfdRenderAnts(ants) {
    var host = $('pfd-ant-table');
    if (!host) return;
    host.innerHTML = '';
    if (!ants || !ants.length) return;
    var tbl = document.createElement('table');
    tbl.width = '95%';
    var head = document.createElement('tr');
    ['Antenna Code', 'Height', 'Azimuth', 'TX Power', 'FSL', 'Select:-'].forEach(function (t) {
      var th = document.createElement('td');
      th.innerHTML = '<b>' + t + '</b>';
      head.appendChild(th);
    });
    tbl.appendChild(head);
    ants.forEach(function (ant) {
      var tr = document.createElement('tr');
      [ant.acode, ant.aht, ant.azim, ant.txpwr, ant.fsl].forEach(function (v) {
        var td = document.createElement('td');
        td.textContent = v == null ? '' : String(v);
        tr.appendChild(td);
      });
      var tdBtn = document.createElement('td');
      var btn = document.createElement('input');
      btn.type = 'button';
      btn.className = 'bt';
      btn.value = 'Select';
      btn.onclick = function () { pfdFillAnt(ant); };
      tdBtn.appendChild(btn);
      tr.appendChild(tdBtn);
      tbl.appendChild(tr);
    });
    host.appendChild(tbl);
  }

  function mountPfd() {
    setAuxStatus('');
    pfdState = { site: null };
    ['pfd-call', 'pfd-lat', 'pfd-lng', 'pfd-alt', 'pfd-utmn', 'pfd-utme', 'pfd-utmz',
      'pfd-acode', 'pfd-aht', 'pfd-azim', 'pfd-txpwr', 'pfd-fsl', 'pfd-altr', 'pfd-bw', 'pfd-freq'].forEach(function (id) {
      if ($(id)) { $(id).value = ''; $(id).disabled = false; }
    });
    if ($('pfd-rxht')) $('pfd-rxht').value = '60.0';
    if ($('pfd-atten')) $('pfd-atten').value = '0.10';
    if ($('pfd-minpfd')) $('pfd-minpfd').value = '-114.0';
    if ($('pfd-maxpfd')) $('pfd-maxpfd').value = '-94.0';
    if ($('pfd-minrx')) $('pfd-minrx').value = '0.0';
    if ($('pfd-sitename')) $('pfd-sitename').textContent = '';
    if ($('pfd-analysis')) $('pfd-analysis').textContent = '';
    if ($('pfd-ant-table')) $('pfd-ant-table').innerHTML = '';
    if ($('pfd-submitted')) { $('pfd-submitted').textContent = ''; show($('pfd-submitted'), false); }
    if ($('pfd-ct-pfd')) { $('pfd-ct-pfd').checked = true; $('pfd-ct-pfd').disabled = false; }
    if ($('pfd-ct-cov')) $('pfd-ct-cov').disabled = false;
    if ($('pfd-ls-sph')) { $('pfd-ls-sph').checked = true; $('pfd-ls-sph').disabled = false; }
    if ($('pfd-ls-ter')) $('pfd-ls-ter').disabled = false;
    if ($('pfd-out-r')) $('pfd-out-r').checked = true;
    if ($('pfd-out-c')) $('pfd-out-c').checked = false;
    if ($('pfd-out-m')) $('pfd-out-m').checked = false;
    if ($('pfd-cli-c')) $('pfd-cli-c').checked = true;
    pfdShowStep('site');
    if ($('pfd-next')) {
      $('pfd-next').onclick = function () {
        var contour = ohlRadio('pfd-ct') || 'pfd';
        var loss = ohlRadio('pfd-ls') || 'sph';
        setAuxStatus('Looking up site...');
        RemIcsApi.auxPfdCoords({
          call: (($('pfd-call') && $('pfd-call').value) || '').trim().toUpperCase(),
          lat: (($('pfd-lat') && $('pfd-lat').value) || '').trim(),
          lng: (($('pfd-lng') && $('pfd-lng').value) || '').trim(),
          alt: (($('pfd-alt') && $('pfd-alt').value) || '').trim(),
          utmNorth: (($('pfd-utmn') && $('pfd-utmn').value) || '').trim(),
          utmEast: (($('pfd-utme') && $('pfd-utme').value) || '').trim(),
          utmZone: (($('pfd-utmz') && $('pfd-utmz').value) || '').trim(),
          contour: contour,
          loss: loss
        }).then(function (r) {
          if (!r.ok) { setAuxStatus(apiErr(r, 'Site lookup failed'), true); return; }
          pfdState.site = r;
          if ($('pfd-call')) { $('pfd-call').value = r.call || ''; $('pfd-call').disabled = true; }
          if ($('pfd-sitename')) $('pfd-sitename').textContent = r.siteName || '';
          if ($('pfd-lat')) { $('pfd-lat').value = r.lat84 || ''; $('pfd-lat').disabled = true; }
          if ($('pfd-lng')) { $('pfd-lng').value = r.lng84 || ''; $('pfd-lng').disabled = true; }
          if ($('pfd-alt')) { $('pfd-alt').value = r.alt || ''; $('pfd-alt').disabled = true; }
          if ($('pfd-utmn')) { $('pfd-utmn').value = r.utmNorth || ''; $('pfd-utmn').disabled = true; }
          if ($('pfd-utme')) { $('pfd-utme').value = r.utmEast || ''; $('pfd-utme').disabled = true; }
          if ($('pfd-utmz')) { $('pfd-utmz').value = r.utmZone || ''; $('pfd-utmz').disabled = true; }
          ['pfd-ct-pfd', 'pfd-ct-cov', 'pfd-ls-sph', 'pfd-ls-ter'].forEach(function (id) {
            if ($(id)) $(id).disabled = true;
          });
          if ($('pfd-analysis')) $('pfd-analysis').textContent = r.analysis || '';
          pfdRenderAnts(r.antennas || []);
          var isPfd = (r.contour || contour) === 'pfd';
          show($('pfd-row-pfd'), isPfd);
          show($('pfd-row-rx'), !isPfd);
          show($('pfd-row-cli'), !isPfd);
          if ($('pfd-altr') && r.alt) $('pfd-altr').value = r.alt;
          pfdShowStep('opt');
          setAuxStatus('');
          if ($('pfd-acode')) $('pfd-acode').focus();
        }).catch(function (ex) { setAuxStatus(ex.message || String(ex), true); });
      };
    }
    if ($('pfd-back')) {
      $('pfd-back').onclick = function () {
        ['pfd-call', 'pfd-lat', 'pfd-lng', 'pfd-alt', 'pfd-utmn', 'pfd-utme', 'pfd-utmz'].forEach(function (id) {
          if ($(id)) $(id).disabled = false;
        });
        ['pfd-ct-pfd', 'pfd-ct-cov', 'pfd-ls-sph', 'pfd-ls-ter'].forEach(function (id) {
          if ($(id)) $(id).disabled = false;
        });
        pfdShowStep('site');
        setAuxStatus('');
      };
    }
    if ($('pfd-run')) {
      $('pfd-run').onclick = function () {
        var s = pfdState.site || {};
        setAuxStatus('Submitting...');
        RemIcsApi.auxPfdRun({
          call: s.call, lat: s.lat84, lng: s.lng84,
          contour: s.contour || ohlRadio('pfd-ct') || 'pfd',
          loss: s.loss || ohlRadio('pfd-ls') || 'sph',
          acode: (($('pfd-acode') && $('pfd-acode').value) || '').trim().toUpperCase(),
          aht: (($('pfd-aht') && $('pfd-aht').value) || '').trim(),
          azim: (($('pfd-azim') && $('pfd-azim').value) || '').trim(),
          txpwr: (($('pfd-txpwr') && $('pfd-txpwr').value) || '').trim(),
          fsl: (($('pfd-fsl') && $('pfd-fsl').value) || '').trim(),
          altR: (($('pfd-altr') && $('pfd-altr').value) || '').trim(),
          rxht: (($('pfd-rxht') && $('pfd-rxht').value) || '').trim(),
          bandwidth: (($('pfd-bw') && $('pfd-bw').value) || '').trim(),
          freq: (($('pfd-freq') && $('pfd-freq').value) || '').trim(),
          attatten: (($('pfd-atten') && $('pfd-atten').value) || '').trim(),
          minPfd: (($('pfd-minpfd') && $('pfd-minpfd').value) || '').trim(),
          maxPfd: (($('pfd-maxpfd') && $('pfd-maxpfd').value) || '').trim(),
          minRx: (($('pfd-minrx') && $('pfd-minrx').value) || '').trim(),
          climate: ohlRadio('pfd-cli') || 'C',
          outR: ($('pfd-out-r') && $('pfd-out-r').checked) ? '1' : '',
          outC: ($('pfd-out-c') && $('pfd-out-c').checked) ? '1' : '',
          outM: ($('pfd-out-m') && $('pfd-out-m').checked) ? '1' : ''
        }).then(function (r) {
          if (!r.ok) { setAuxStatus(apiErr(r, 'Contour submit failed'), true); return; }
          if ($('pfd-submitted')) {
            $('pfd-submitted').textContent = r.message || '';
            show($('pfd-submitted'), true);
          }
          setAuxStatus('');
        }).catch(function (ex) { setAuxStatus(ex.message || String(ex), true); });
      };
    }
    if ($('pfd-cancel')) $('pfd-cancel').onclick = auxGoWelcome;
    if ($('pfd-help')) {
      $('pfd-help').onclick = function () { auxOpenHelp('micshelp/AUXpfdc1.aspx'); };
    }
    if ($('pfd-call')) $('pfd-call').focus();
  }

  var pasState = { nPass: 0, last: false };

  function pasIsLl() {
    return !!( $('pas-mode-l') && $('pas-mode-l').checked );
  }

  function pasVal(id) {
    var el = $(id);
    return el && !el.disabled ? String(el.value || '').trim() : '';
  }

  function pasMark(el, on) {
    if (!el) return;
    if (el.tagName === 'TD' || el.tagName === 'LABEL') {
      el.className = el.className.replace(/\b(m|o)\b/g, '').replace(/\s+/g, ' ').trim()
        + (on ? ' m' : ' o');
    } else if (el.tagName === 'INPUT' && el.type === 'text') {
      el.className = el.className.replace(/\bim\b/g, '').replace(/\s+/g, ' ').trim()
        + (on ? ' im' : '');
    }
  }

  function pasApplyMode() {
    var ll = pasIsLl();
    var idsLl = ['pas-lat-0', 'pas-lng-0', 'pas-alt-0', 'pas-ant-0',
      'pas-lat-5', 'pas-lng-5', 'pas-alt-5', 'pas-ant-5'];
    var idsD = ['pas-dst-0'];
    var i;
    for (i = 1; i <= 4; i++) {
      idsLl.push('pas-lat-' + i, 'pas-lng-' + i, 'pas-alt-' + i, 'pas-ant-' + i);
      idsD.push('pas-dst-' + i, 'pas-ang-' + i);
    }
    idsLl.forEach(function (id) {
      var el = $(id);
      if (el) el.disabled = !ll;
    });
    idsD.forEach(function (id) {
      var el = $(id);
      if (el) el.disabled = ll;
    });
    var labs = document.querySelectorAll('#aux-passive .pas-ll');
    for (i = 0; i < labs.length; i++) pasMark(labs[i], ll);
    labs = document.querySelectorAll('#aux-passive .pas-d');
    for (i = 0; i < labs.length; i++) pasMark(labs[i], !ll);
  }

  function pasEnsureHop(n) {
    var host = $('pas-hops');
    if (!host || $('pas-fs-' + n)) return;
    var fs = document.createElement('fieldset');
    fs.id = 'pas-fs-' + n;
    fs.hidden = true;
    var lg = document.createElement('legend');
    lg.textContent = 'Passive Number ' + n;
    fs.appendChild(lg);
    var tbl = document.createElement('table');
    tbl.className = 'classic-form';
    tbl.width = '95%';
    tbl.align = 'center';
    function row(cells) {
      var tr = document.createElement('tr');
      cells.forEach(function (c) { tr.appendChild(c); });
      tbl.appendChild(tr);
    }
    function td(text, cls) {
      var el = document.createElement('td');
      if (cls) el.className = cls;
      el.textContent = text;
      return el;
    }
    function inp(id, cls, size) {
      var el = document.createElement('input');
      el.id = id;
      el.size = size || 6;
      if (cls) el.className = cls;
      return el;
    }
    var c1 = td('Enter the Latitude, Longitude of a location:', 'pas-ll');
    var tLat = document.createElement('td'); tLat.appendChild(inp('pas-lat-' + n, 'pas-ll', 10));
    var tLng = document.createElement('td'); tLng.appendChild(inp('pas-lng-' + n, 'pas-ll', 10));
    row([c1, tLat, tLng, td('(WGS 84)')]);
    var a1 = td('Altitude of site:', 'pas-ll');
    var tAlt = document.createElement('td'); tAlt.appendChild(inp('pas-alt-' + n, 'pas-ll', 6)); tAlt.appendChild(document.createTextNode(' m.'));
    var a2 = td('Centre Line Height:', 'pas-ll');
    var tAnt = document.createElement('td'); tAnt.appendChild(inp('pas-ant-' + n, 'pas-ll', 6)); tAnt.appendChild(document.createTextNode(' m.'));
    row([a1, tAlt, a2, tAnt]);
    var d1 = td('-or- Distance to Next:', 'pas-d');
    var tDst = document.createElement('td'); tDst.appendChild(inp('pas-dst-' + n, 'pas-d', 6)); tDst.appendChild(document.createTextNode(' Km'));
    var d2 = td('Included Angle:', 'pas-d');
    var tAng = document.createElement('td'); tAng.appendChild(inp('pas-ang-' + n, 'pas-d', 6)); tAng.appendChild(document.createTextNode(' deg.'));
    row([d1, tDst, d2, tAng]);
    var w1 = td('Passive Width:', 'm');
    var tW = document.createElement('td');
    var wIn = inp('pas-wd-' + n, 'im', 6); tW.appendChild(wIn); tW.appendChild(document.createTextNode(' m.'));
    var w2 = td('Passive Height:', 'm');
    var tH = document.createElement('td');
    var hIn = inp('pas-ht-' + n, 'im', 6); tH.appendChild(hIn); tH.appendChild(document.createTextNode(' m.'));
    row([w1, tW, w2, tH]);
    fs.appendChild(tbl);
    host.appendChild(fs);
  }

  function pasShowStep() {
    var i;
    for (i = 1; i <= 4; i++) {
      pasEnsureHop(i);
      show($('pas-fs-' + i), i <= pasState.nPass);
    }
    show($('pas-fs-5'), pasState.last);
    if ($('pas-add-p')) $('pas-add-p').disabled = pasState.last || pasState.nPass >= 4;
    if ($('pas-add-a')) $('pas-add-a').disabled = pasState.last || pasState.nPass < 1;
    if ($('pas-back')) $('pas-back').disabled = pasState.nPass < 1 && !pasState.last;
    pasApplyMode();
  }

  function pasClearHop(n) {
    ['lat', 'lng', 'alt', 'ant', 'dst', 'ang', 'wd', 'ht'].forEach(function (k) {
      var el = $('pas-' + k + '-' + n);
      if (el) el.value = '';
    });
  }

  function mountPassive() {
    setAuxStatus('');
    show($('pas-result'), false);
    if ($('pas-report')) $('pas-report').textContent = '';
    pasState = { nPass: 0, last: false };
    [0, 5].forEach(function (n) {
      ['lat', 'lng', 'alt', 'ant', 'dst', 'power', 'gain', 'fsl'].forEach(function (k) {
        var el = $('pas-' + k + '-' + n);
        if (el) el.value = '';
      });
    });
    if ($('pas-freq')) $('pas-freq').value = '';
    if ($('pas-gain-0')) $('pas-gain-0').value = '';
    if ($('pas-mode-d')) $('pas-mode-d').checked = true;
    for (var i = 1; i <= 4; i++) { pasEnsureHop(i); pasClearHop(i); }
    pasShowStep();
    if ($('pas-mode-l')) $('pas-mode-l').onclick = pasApplyMode;
    if ($('pas-mode-d')) $('pas-mode-d').onclick = pasApplyMode;
    if ($('pas-add-p')) {
      $('pas-add-p').onclick = function () {
        if (pasState.nPass >= 4 || pasState.last) return;
        pasState.nPass++;
        pasShowStep();
      };
    }
    if ($('pas-add-a')) {
      $('pas-add-a').onclick = function () {
        if (pasState.nPass < 1) return;
        pasState.last = true;
        pasShowStep();
        if ($('pas-power-5')) $('pas-power-5').focus();
      };
    }
    if ($('pas-back')) {
      $('pas-back').onclick = function () {
        if (pasState.last) {
          pasState.last = false;
          pasClearHop(5);
          if ($('pas-power-5')) $('pas-power-5').value = '';
          if ($('pas-gain-5')) $('pas-gain-5').value = '';
          if ($('pas-fsl-5')) $('pas-fsl-5').value = '';
        } else if (pasState.nPass > 0) {
          pasClearHop(pasState.nPass);
          pasState.nPass--;
        }
        pasShowStep();
      };
    }
    if ($('pas-reset')) {
      $('pas-reset').onclick = function () { mountPassive(); };
    }
    if ($('pas-cancel')) $('pas-cancel').onclick = auxGoWelcome;
    if ($('pas-help')) {
      $('pas-help').onclick = function () { auxOpenHelp('micshelp/AUXpassive1.aspx'); };
    }
    if ($('pas-calc')) {
      $('pas-calc').onclick = function () {
        if (!pasState.last || pasState.nPass < 1) {
          setAuxStatus('Add at least one passive and the last active.', true);
          return;
        }
        var fields = {
          mode: pasIsLl() ? 'L' : 'D',
          nPass: String(pasState.nPass),
          freq: pasVal('pas-freq'),
          power0: pasVal('pas-power-0'),
          again0: pasVal('pas-gain-0'),
          fsl0: pasVal('pas-fsl-0'),
          power5: pasVal('pas-power-5'),
          again5: pasVal('pas-gain-5'),
          fsl5: pasVal('pas-fsl-5')
        };
        var n;
        for (n = 0; n <= 5; n++) {
          if (n >= 1 && n <= 4 && n > pasState.nPass) continue;
          if (n >= 1 && n <= 4) {
            fields['wd' + n] = pasVal('pas-wd-' + n);
            fields['ht' + n] = pasVal('pas-ht-' + n);
            fields['ang' + n] = pasVal('pas-ang-' + n);
            fields['dst' + n] = pasVal('pas-dst-' + n);
          }
          if (n === 0) fields.dst0 = pasVal('pas-dst-0');
          fields['lat' + n] = pasVal('pas-lat-' + n);
          fields['lng' + n] = pasVal('pas-lng-' + n);
          fields['alt' + n] = pasVal('pas-alt-' + n);
          fields['ant' + n] = pasVal('pas-ant-' + n);
        }
        setAuxStatus('Running...');
        RemIcsApi.auxPassive(fields).then(function (r) {
          if (!r.ok) { setAuxStatus(apiErr(r, 'Passive run failed'), true); return; }
          pasState.reportUrl = r.url || '';
          pasState.reportText = r.text || '';
          pasState.serial = r.serial || '';
          if ($('pas-report')) $('pas-report').textContent = r.text || r.note || '';
          show($('pas-result'), true);
          setAuxStatus(r.note || '');
        }).catch(function (ex) { setAuxStatus(ex.message || String(ex), true); });
      };
    }
    if ($('pas-open')) {
      $('pas-open').onclick = function () {
        if (pasState.reportUrl) window.open(pasState.reportUrl, 'WndReport',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,status=yes');
      };
    }
    if ($('pas-save')) {
      $('pas-save').onclick = function () {
        downloadText('p-passive.txt', pasState.reportText || '', 'text/plain');
      };
    }
    if ($('pas-email')) {
      $('pas-email').onclick = function () {
        if (!pasState.serial) {
          setAuxStatus('Run the calculation first.', true);
          return;
        }
        setAuxStatus('Queueing email...');
        RemIcsApi.auxPassive({ action: 'email', serial: pasState.serial }).then(function (r) {
          if (!r.ok) { setAuxStatus(apiErr(r, 'Email failed'), true); return; }
          setAuxStatus(r.message || 'Email queued.');
        }).catch(function (ex) { setAuxStatus(ex.message || String(ex), true); });
      };
    }
  }

  function setAuxPageTitle(tool) {
    var el = $('aux-title');
    if (!el) return;
    var text = AUX_TITLES[tool] || 'Auxiliary Engineering';
    var ownHeading = { sep: 1, pattern: 1, coord: 1, pcs: 1, hilo: 1, nad27: 1, sat: 1, orbit: 1, passive: 1 };
    if (ownHeading[tool]) {
      el.hidden = true;
      el.style.display = 'none';
      el.textContent = text;
      return;
    }
    var tag = tool === 'genctx' ? 'h1' : (tool === 'distance' ? 'p' : 'h3');
    if (el.tagName.toLowerCase() !== tag) {
      var neu = document.createElement(tag);
      neu.id = 'aux-title';
      neu.setAttribute('align', 'center');
      el.parentNode.replaceChild(neu, el);
      el = neu;
    }
    el.hidden = false;
    el.style.display = '';
    el.align = 'center';
    if (tag === 'p') {
      el.textContent = '';
      var b = document.createElement('b');
      b.textContent = text;
      el.appendChild(b);
    } else {
      el.textContent = text;
    }
  }

  function mountAuxEng() {
    var route = parseRoute();
    var tool = route.params.tool || 'menu';
    setAuxPageTitle(tool);
    setAuxStatus('');
    if (tool === 'distance') {
      showAuxPane('aux-distance');
    } else if (tool === 'genctx') {
      showAuxPane('aux-genctx');
      mountGenCtx();
    } else if (tool === 'sep') {
      showAuxPane('aux-sep');
      mountSep();
    } else if (tool === 'pattern') {
      showAuxPane('aux-pattern');
      mountPattern();
    } else if (tool === 'coord') {
      showAuxPane('aux-coord');
      mountCoord();
    } else if (tool === 'pcs') {
      showAuxPane('aux-pcs');
      mountPcs();
    } else if (tool === 'hilo') {
      showAuxPane('aux-hilo');
      mountHilo();
    } else if (tool === 'nad27') {
      showAuxPane('aux-nad27');
      mountNad27();
    } else if (tool === 'sat') {
      showAuxPane('aux-sat');
      mountSat();
    } else if (tool === 'orbit') {
      showAuxPane('aux-orbit');
      mountOrbit();
    } else if (tool === 'ohl') {
      showAuxPane('aux-ohl');
      mountOhl();
    } else if (tool === 'terrain') {
      showAuxPane('aux-terrain');
      mountTerrain();
    } else if (tool === 'pfd') {
      showAuxPane('aux-pfd');
      mountPfd();
    } else if (tool === 'passive') {
      showAuxPane('aux-passive');
      mountPassive();
    } else if (tool && tool !== 'menu' && !AUX_LIVE[tool]) {
      showAuxPane('aux-stub');
    } else {
      showAuxPane('aux-menu');
    }

    if ($('d-help')) {
      $('d-help').onclick = function () {
        auxOpenHelp('micshelp/disthelp.aspx');
      };
    }
    if (window.RemicsHints && RemicsHints.apply) RemicsHints.apply($('view-host') || document);
    if (window.RemIcsApi && RemIcsApi.wireEnterAsTab) {
      RemIcsApi.wireEnterAsTab($('view-host') || document.body);
    }
  }

  /* ---- Catalogue / subsid / DS report shortcuts ---- */
  function mountCatalogue() {
    window.open(micsRoot() + 'catalogue/radiocatalog.aspx', 'WndCat', 'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes');
    if (global.RemicsApp) RemicsApp.navigate('welcome');
  }
  function mountInfoFiles() {
    window.open(micsRoot() + 'catalogue/infofiles.aspx', 'WndInfo', 'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes');
    if (global.RemicsApp) RemicsApp.navigate('welcome');
  }
  function mountDsReport() {
    var ft = (parseRoute().params.filetype || 'TS').toUpperCase();
    var page = ft === 'ES' ? 'dsESReport.aspx' : 'dsTSReport.aspx';
    window.open(micsRoot() + 'reports/' + page, 'WndDsRep', 'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes');
    if (global.RemicsApp) RemicsApp.navigate(ft === 'ES' ? 'ds-es' : 'ds-ts');
  }

  /* ---- Change password (classic loginPassword look; MicsDbAuth) ---- */
  function mountChangePassword() {
    var status = $('pwd-status');
    var mid = $('pwd-micsid');
    if (mid && window.REMICS_SHELL) mid.textContent = REMICS_SHELL.user || '';

    function showMasked(on) {
      show($('pwd-form-masked'), on);
      show($('pwd-form-plain'), !on);
    }
    if ($('pwd-masked')) $('pwd-masked').onchange = function () { if (this.checked) showMasked(true); };
    if ($('pwd-unmasked')) $('pwd-unmasked').onchange = function () { if (this.checked) showMasked(false); };
    showMasked(true);

    if ($('pwd-cancel')) {
      $('pwd-cancel').onclick = function () {
        if (global.RemicsApp) RemicsApp.navigate('welcome');
      };
    }
    if ($('pwd-help')) {
      $('pwd-help').onclick = function () {
        window.open(micsRoot() + 'micshelp/loginPassword.aspx', 'WndHelp',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=520,height=420');
      };
    }
    if ($('pwd-submit')) {
      $('pwd-submit').onclick = function () {
        var masked = $('pwd-masked') && $('pwd-masked').checked;
        var oldP = masked ? ($('pwd-old-m').value || '') : ($('pwd-old').value || '');
        var n1 = masked ? ($('pwd-new1-m').value || '') : ($('pwd-new1').value || '');
        var n2 = masked ? ($('pwd-new2-m').value || '') : ($('pwd-new2').value || '');
        if (!oldP) { alert('You must enter a value for the current password'); return; }
        if (!n1) { alert('You must enter a value for the new password'); return; }
        if (n1.length < 8) { alert('New password must be 8 or more characters'); return; }
        if (!n2) { alert('You must enter a value for the repeat new password'); return; }
        if (n1 !== n2) { alert('New password and its confirmation must match'); return; }
        if (n1 === oldP) { alert('New password must be different from old password'); return; }
        if (status) status.textContent = 'Updating...';
        RemIcsApi.changePassword(oldP, n1).then(function (r) {
          if (!r || !r.ok) {
            if (status) status.textContent = (r && r.error) || 'Change failed';
            if (r && r.code === 'badold') alert('The specified Current Password is not correct');
            else alert((r && r.error) || 'Change failed');
            return;
          }
          alert('Your password was changed successfully\n\nYou will be logged into the site again.\nPlease use your new password.');
          location.href = rewriteRoot() + 'logoff.ashx';
        }).catch(function (err) {
          if (status) status.textContent = String(err);
          alert(String(err));
        });
      };
    }
  }

  function mountSesTimeout() {
    var status = $('ses-to-status');
    var mins = $('ses-to-mins');
    var extraHelp = $('ses-to-extra-help');
    function extraHelpOn() { return !!(extraHelp && extraHelp.checked); }
    function setStatus(msg) { if (status) status.textContent = msg || ''; }
    function validMins(raw, silent) {
      var n = parseInt(String(raw || '').replace(/^\s+|\s+$/g, ''), 10);
      if (!/^\d+$/.test(String(raw || '').replace(/^\s+|\s+$/g, '')) || isNaN(n)) {
        if (!silent) alert('Invalid timeout value: ' + raw);
        return null;
      }
      if (n < 60) {
        if (!silent) alert('Time must be >= 60');
        return null;
      }
      return n;
    }
    function apply(n) {
      setStatus('Saving...');
      RemIcsApi.sesTimeoutSet(n, extraHelpOn()).then(function (r) {
        if (!r || !r.ok) {
          setStatus('');
          alert((r && r.error) || 'Timeout not changed');
          return;
        }
        if (mins) mins.value = String(r.minutes);
        if (extraHelp && typeof r.extraHelp === 'boolean') extraHelp.checked = r.extraHelp;
        if (window.RemicsHints) RemicsHints.set(extraHelpOn(), false);
        setStatus(r.message || ('Session Timeout Changed to ' + r.minutes));
      }).catch(function (ex) {
        setStatus('');
        alert(ex.message || String(ex));
      });
    }
    if (mins) {
      mins.onblur = function () { validMins(mins.value, false); };
    }
    if ($('ses-to-save')) {
      $('ses-to-save').onclick = function () {
        var n = validMins(mins && mins.value, false);
        if (n == null) return;
        apply(n);
      };
    }
    if ($('ses-to-default')) {
      $('ses-to-default').onclick = function () {
        if (mins) mins.value = '60';
        apply(60);
      };
    }
    if ($('ses-to-cancel')) {
      $('ses-to-cancel').onclick = function () {
        alert('Timeout not changed');
        if (global.RemicsApp) RemicsApp.navigate('welcome');
      };
    }
    if ($('ses-to-help')) {
      $('ses-to-help').onclick = function () {
        window.open(micsRoot() + 'micshelp/sesTimeout.aspx', 'WndHelp',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
      };
    }
    setStatus('Loading...');
    RemIcsApi.sesTimeoutGet().then(function (r) {
      setStatus('');
      if (!r || !r.ok) {
        setStatus((r && r.error) || 'Unable to read timeout');
        return;
      }
      if (mins) mins.value = String(r.minutes);
      if (extraHelp) {
        extraHelp.checked = (typeof r.extraHelp === 'boolean')
          ? r.extraHelp
          : !(window.RemicsHints) || RemicsHints.isOn();
        if (window.RemicsHints) RemicsHints.set(extraHelp.checked, false);
      }
      if (window.RemIcsApi && RemIcsApi.firstFocus) RemIcsApi.firstFocus($('view-host'), ['ses-to-mins']);
      else if (mins) try { mins.focus(); mins.select(); } catch (e) { /* ignore */ }
    }).catch(function (ex) {
      setStatus(ex.message || String(ex));
    });
    if (window.RemIcsApi && RemIcsApi.wireEnterAsTab) {
      RemIcsApi.wireEnterAsTab($('view-host') || document.body);
    }
  }

  function mountContact() {
    var status = $('contact-status');
    var currentId = '';
    function setStatus(msg) { if (status) status.textContent = msg || ''; }
    function selectedId() {
      var sel = $('contact-user');
      var row = $('contact-user-row');
      if (sel && row && !row.hidden && sel.value) return sel.value;
      return currentId;
    }
    function fill(r) {
      currentId = r.micsid || '';
      if ($('contact-micsid')) $('contact-micsid').value = r.micsid || '';
      if ($('contact-ultrixid')) $('contact-ultrixid').value = r.ultrixid || '';
      if ($('contact-email')) $('contact-email').value = r.email || '';
      if ($('contact-email2')) $('contact-email2').value = r.email || '';
      if ($('contact-phone')) $('contact-phone').value = r.phone || '';
      if ($('contact-mobile')) $('contact-mobile').value = r.mobile || '';
      if ($('contact-send-pcn')) $('contact-send-pcn').checked = !!r.sendPcn;
      var lab = $('contact-send-pcn-label');
      if (lab) {
        lab.textContent = r.isSelf === false
          ? 'Send this user Prior Coordination Notices (PCN)'
          : 'Send me Prior Coordination Notices (PCN)';
      }
    }
    function loadUser(micsid) {
      setStatus('Loading...');
      RemIcsApi.contactGet(micsid).then(function (r) {
        setStatus('');
        if (!r || !r.ok) {
          setStatus((r && r.error) || 'Unable to read contact information');
          return;
        }
        fill(r);
        if (window.RemIcsApi && RemIcsApi.firstFocus) RemIcsApi.firstFocus($('view-host'), ['contact-email']);
      }).catch(function (ex) {
        setStatus(ex.message || String(ex));
      });
    }
    if ($('contact-cancel')) {
      $('contact-cancel').onclick = function () {
        if (global.RemicsApp) RemicsApp.navigate('welcome');
      };
    }
    if ($('contact-save')) {
      $('contact-save').onclick = function () {
        var email = ($('contact-email') && $('contact-email').value || '').replace(/^\s+|\s+$/g, '');
        var email2 = ($('contact-email2') && $('contact-email2').value || '').replace(/^\s+|\s+$/g, '');
        if (!email) { alert('Enter a valid email address.'); return; }
        if (email !== email2) { alert('Email and confirmation must match.'); return; }
        setStatus('Saving...');
        RemIcsApi.contactSet({
          micsid: selectedId(),
          email: email,
          emailConfirm: email2,
          phone: ($('contact-phone') && $('contact-phone').value) || '',
          mobile: ($('contact-mobile') && $('contact-mobile').value) || '',
          sendPcn: !!( $('contact-send-pcn') && $('contact-send-pcn').checked )
        }).then(function (r) {
          if (!r || !r.ok) {
            setStatus('');
            alert((r && r.error) || 'Contact not changed');
            return;
          }
          fill(r);
          setStatus(r.message || 'Contact information saved.');
        }).catch(function (ex) {
          setStatus('');
          alert(ex.message || String(ex));
        });
      };
    }
    if ($('contact-user')) {
      $('contact-user').onchange = function () { loadUser(this.value); };
    }
    setStatus('Loading...');
    RemIcsApi.contactList().then(function (list) {
      if (!list || !list.ok) {
        setStatus((list && list.error) || 'Unable to read contact information');
        return loadUser();
      }
      var row = $('contact-user-row');
      var sel = $('contact-user');
      if (list.canEditOthers && sel && (list.people || []).length) {
        sel.innerHTML = '';
        (list.people || []).forEach(function (p) {
          var opt = document.createElement('option');
          opt.value = p.micsid;
          opt.textContent = p.display || p.micsid;
          if (p.isSelf) opt.selected = true;
          sel.appendChild(opt);
        });
        if (row) {
          row.hidden = false;
          row.style.display = '';
        }
      } else if (row) {
        row.hidden = true;
        row.style.display = 'none';
      }
      loadUser(sel && sel.value);
    }).catch(function (ex) {
      setStatus(ex.message || String(ex));
    });
    if (window.RemIcsApi && RemIcsApi.wireEnterAsTab) {
      RemIcsApi.wireEnterAsTab($('view-host') || document.body);
    }
  }

  function mountPwdRecoverySetup() {
    var status = $('pwdqa-status');
    var intro = $('pwdqa-intro');
    var form = $('pwdqa-form');
    function setStatus(msg) { if (status) status.textContent = msg || ''; }
    function showForm(on) {
      show(intro, !on);
      show(form, on);
    }
    function clearFields() {
      if ($('pwdqa-fixed-q')) $('pwdqa-fixed-q').selectedIndex = 0;
      if ($('pwdqa-fixed-a')) $('pwdqa-fixed-a').value = '';
      if ($('pwdqa-user-q')) $('pwdqa-user-q').value = '';
      if ($('pwdqa-user-a')) $('pwdqa-user-a').value = '';
    }
    if ($('pwdqa-proceed')) {
      $('pwdqa-proceed').onclick = function () {
        setStatus('');
        showForm(true);
        if (window.RemIcsApi && RemIcsApi.firstFocus) RemIcsApi.firstFocus($('view-host'), ['pwdqa-fixed-q']);
      };
    }
    function goBack() {
      if (global.RemicsApp) RemicsApp.navigate('welcome');
    }
    if ($('pwdqa-close-intro')) $('pwdqa-close-intro').onclick = goBack;
    if ($('pwdqa-cancel')) $('pwdqa-cancel').onclick = goBack;
    if ($('pwdqa-reset')) $('pwdqa-reset').onclick = function () { clearFields(); setStatus(''); };
    if ($('pwdqa-help')) {
      $('pwdqa-help').onclick = function () {
        window.open(micsRoot() + 'micshelp/pwdqa.aspx', 'WndHelp',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
      };
    }
    if ($('pwdqa-submit')) {
      $('pwdqa-submit').onclick = function () {
        var fq = ($('pwdqa-fixed-q') && $('pwdqa-fixed-q').value) || '';
        var fa = ($('pwdqa-fixed-a') && $('pwdqa-fixed-a').value) || '';
        var uq = ($('pwdqa-user-q') && $('pwdqa-user-q').value) || '';
        var ua = ($('pwdqa-user-a') && $('pwdqa-user-a').value) || '';
        if (!fa || !uq || !ua) {
          alert('All four fields must have a value');
          return;
        }
        setStatus('Saving...');
        RemIcsApi.pwdRecoverySetup({
          fixedQuestion: fq,
          fixedAnswer: fa,
          userQuestion: uq,
          userAnswer: ua
        }).then(function (r) {
          if (!r || !r.ok) {
            setStatus('');
            alert((r && r.error) || 'Save failed');
            return;
          }
          setStatus(r.message || 'Information saved and E-mail sent');
        }).catch(function (ex) {
          setStatus('');
          alert(ex.message || String(ex));
        });
      };
    }
    showForm(false);
    if (window.RemicsHints && RemicsHints.bindForm) {
      RemicsHints.bindForm($('view-host'), 'pwdqa', null);
    }
    if (window.RemIcsApi && RemIcsApi.wireEnterAsTab) {
      RemIcsApi.wireEnterAsTab($('view-host') || document.body);
    }
  }

  global.RemicsP675 = {
    mountCasedet: mountCasedet,
    mountFileOpen: mountFileOpen,
    mountSdfTree: mountSdfTree,
    mountDsSdf: mountDsSdf,
    mountFeeCalc: mountFeeCalc,
    mountBulkPrint: mountBulkPrint,
    mountAuxEng: mountAuxEng,
    mountTsipPost: mountTsipPost,
    mountCatalogue: mountCatalogue,
    mountInfoFiles: mountInfoFiles,
    mountDsReport: mountDsReport,
    mountChangePassword: mountChangePassword,
    mountPwdRecoverySetup: mountPwdRecoverySetup,
    mountSesTimeout: mountSesTimeout,
    mountContact: mountContact
  };
})(window);
