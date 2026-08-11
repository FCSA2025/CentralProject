// RemIcsReWrite Phase 6.75 — CASEDET, File Open, SDF, DS-SDF, Fee, Bulk Print, Aux Eng.
(function (global) {
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
  var casedetSel = null;
  function mountCasedet() {
    var status = $('casedet-status');
    var list = $('casedet-list');
    if (!list) return;
    function load() {
      casedetSel = null;
      status.textContent = 'Loading…';
      list.innerHTML = '';
      RemIcsApi.casedet('list', { mode: $('casedet-mode').value }).then(function (r) {
        if (!r.ok) { status.textContent = r.error || 'Failed'; return; }
        var runs = r.runs || [];
        status.textContent = runs.length + ' run(s)';
        runs.forEach(function (row) {
          var li = document.createElement('li');
          var a = document.createElement('a');
          a.href = '#';
          a.textContent = row.label;
          a.addEventListener('click', function (ev) {
            ev.preventDefault();
            list.querySelectorAll('a').forEach(function (n) { n.classList.remove('selected'); });
            a.classList.add('selected');
            casedetSel = row;
          });
          li.appendChild(a);
          list.appendChild(li);
        });
      });
    }
    function openGen(kind, reptype) {
      if (!casedetSel) { alert('Select a run.'); return; }
      RemIcsApi.casedet('url', {
        mode: $('casedet-mode').value,
        kind: kind,
        parm: casedetSel.parm,
        run: casedetSel.run,
        reptype: reptype || 'G'
      }).then(function (r) {
        if (!r.ok) { alert(r.error || 'URL failed'); return; }
        var qs = (r.url || '').split('?')[1] || '';
        var abs = micsRoot() + 'Ttsipmenu/' + r.page + (qs ? '?' + qs : '');
        window.open(abs, 'WndCaseDet', 'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes');
        status.textContent = 'Opened ' + r.page + ' for ' + r.tsip;
      });
    }
    $('casedet-refresh').onclick = load;
    $('casedet-mode').onchange = load;
    $('casedet-csv').onclick = function () { openGen('csv'); };
    $('casedet-kml-g').onclick = function () { openGen('kml', 'G'); };
    $('casedet-kml-c').onclick = function () { openGen('kml', 'C'); };
    load();
  }

  /* ---- File Open ---- */
  function mountFileOpen() {
    var status = $('file-open-status');
    function loadList() {
      var type = $('fo-type').value;
      status.textContent = 'Loading…';
      var p;
      if (type === 'TS' || type === 'ES') {
        p = fetch(rewriteRoot() + 'files.ashx?filetype=' + encodeURIComponent(type), { credentials: 'include' })
          .then(function (r) { return r.json(); });
      } else if (type === 'TsipParm') {
        p = RemicsTsipApi.tsipTree().then(function (r) {
          var names = (r.body || '').toString().split(':').filter(Boolean);
          return { ok: r.ok, files: names.map(function (n) { return { name: n }; }) };
        });
      } else {
        p = RemIcsApi.sdfFiles(type);
      }
      p.then(function (data) {
        if (!data.ok) { status.textContent = data.error || 'Failed'; return; }
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
    Ctx: { title: 'SDF CTX Search and Extract', fields: [
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

    function sdfFileActions(node) {
      var name = node.sdf || node.text;
      return [
        { label: 'Validate', action: function () {
          RemIcsApi.valFile(name, projectCode(), { filetype: type }).then(function (r) {
            status.textContent = r.ok ? 'Validate OK' : (r.error || r.body || 'Validate failed');
          });
        }},
        { label: 'Export', action: function () {
          RemIcsApi.exportTable(name, projectCode(), { filetype: type }).then(function (r) {
            status.textContent = r.ok ? 'Export OK' : (r.error || r.body || 'Export failed');
          });
        }},
        { label: 'Delete file', action: function () {
          if (!window.confirm('Delete SDF file ' + name + '?')) return;
          RemIcsApi.killTable(name, projectCode(), { filetype: type }).then(function (r) {
            if (!r.ok) { alert(r.error || r.body || 'Delete failed'); return; }
            load();
          });
        }},
        { label: 'Copy', action: function () {
          var newName = window.prompt('Copy ' + name + ' as:', name + '_2');
          if (!newName) return;
          RemIcsApi.copyTable(name, newName.trim(), projectCode(), { filetype: type }).then(function (r) {
            status.textContent = r.ok ? 'Copied' : (r.error || r.body || 'Copy failed');
            if (r.ok) load();
          });
        }}
      ];
    }

    function load() {
      type = $('sdf-type').value;
      if (longEl) longEl.textContent = sdfTypeLong(type);
      if (!window.RemicsSdfTree) {
        if (status) status.textContent = 'SDF tree module not loaded.';
        return;
      }
      treeMount = new RemicsSdfTree.TreeMount('sdf-tree-host', type, {
        onSelect: function (node) {
          if (status && node.value && node.value.indexOf('d^') === 0) {
            status.textContent = node.text + ' (' + node.key + ')';
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
            showMenu(ev, [{ label: 'Delete record', action: function () {
              if (!window.confirm('Delete ' + node.text + '?')) return;
              RemIcsApi.sdfTreeCall(delFn, { key: node.value }).then(function (r) {
                var body = (r.body || '').toString();
                if (!r.ok || body.indexOf('ERROR') === 0 || body.toLowerCase().indexOf('timeout') === 0) {
                  alert(r.error || body || 'Delete failed');
                  return;
                }
                load();
              }).catch(function (ex) {
                alert('Delete error: ' + (ex.message || ex));
              });
            }}], node);
          }
        }
      });
      if (status) status.textContent = 'Loading…';
      treeMount.loadRoot().then(function () {
        if (status) status.textContent = 'Right-click for actions · expand files for records';
      });
    }

    $('sdf-type').onchange = load;
    $('sdf-refresh').onclick = load;
    if ($('sdf-help')) {
      $('sdf-help').onclick = function () {
        window.open(micsRoot() + 'micshelp/separatefiles/sdf' + $('sdf-type').value + '.aspx', 'WndHelp',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
      };
    }
    $('sdf-create').onclick = function () {
      var name = window.prompt('New SDF ' + $('sdf-type').value + ' name (1–16 A-Za-z0-9_):', '');
      if (!name) return;
      name = name.trim();
      if (!/^[A-Za-z0-9_]{1,16}$/.test(name)) { alert('Invalid name.'); return; }
      RemIcsApi.createTable(name, projectCode(), { filetype: $('sdf-type').value }).then(function (r) {
        if (!r.ok) { alert(r.error || r.body || 'create failed'); return; }
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
      alert('Enter a valid SDF name (1–16 A-Za-z0-9_).');
      return;
    }
    var dupMode = $('dssdf-dup').value;
    var pc = projectCode();
    var keylist = keys.join(',');
    setStatus('Saving…');

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
      setStatus('Save complete — ' + sdfname);
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
    if (typeSel) typeSel.value = type;
    renderDsSdfCriteria(type);

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
      setStatus('Searching…');
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
    if ($('dssdf-report')) {
      $('dssdf-report').onclick = function () {
        alert('This function is not currently supported.');
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
    }

    function load() {
      staging = [];
      renderStaging();
      status.textContent = 'Loading…';
      fetch(rewriteRoot() + 'files.ashx?filetype=' + encodeURIComponent(ft()), { credentials: 'include' })
        .then(function (r) { return r.json(); })
        .then(function (data) {
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
      };
    }
    if ($('bp-checknone')) {
      $('bp-checknone').onclick = function () {
        document.querySelectorAll('#bp-list input[type=checkbox]').forEach(function (c) { c.checked = false; });
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

    $('bp-open-tree').onclick = function () {
      var page = ft() === 'ES' ? 'ESPrintTree.aspx' : 'TSPrintTree.aspx';
      var key = staging[0] ? 't.' + staging[0] : '';
      var checked = [];
      document.querySelectorAll('#bp-list input:checked').forEach(function (c) {
        checked.push(c.getAttribute('data-name'));
      });
      if (!key && checked[0]) key = 't.' + checked[0];
      window.open(micsRoot() + 'Tbulkprint/' + page + (key ? '?key=' + encodeURIComponent(key) : ''),
        'WndPrint', 'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes');
    };
    load();
  }

  /* ---- TSIP Post Analysis (classic TnavigationLeft postTsip subtree) ---- */
  var POST_TSIP_TOOLS = {
    ohl: { page: 'auxengmenu/AUXOHLoss1.aspx', title: 'Over Horizon Loss' },
    terrain: { page: 'auxengmenu/AUXTerrain1.aspx', title: 'Terrain Profile' },
    nad27: { external: 'http://webapp.geod.nrcan.gc.ca/geod/tools-outils/ntv2.php?locale=en', title: 'NAD27-WGS84 Conversion' },
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
    var cfg = POST_TSIP_TOOLS[tool];
    if (cfg && cfg.external) {
      window.open(cfg.external, 'WndNRCAN',
        'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes');
    } else if (cfg && cfg.page) {
      openClassicPage(cfg.page, cfg.title);
    }
    if (global.RemicsApp) RemicsApp.navigate('welcome');
  }

  /* ---- Aux Eng ---- */
  var AUX_TOOLS = [
    { id: 'distance', label: 'Distance and Bearing', page: null },
    { id: 'passive', label: 'Passive Calculations', page: 'AUXpassive1.aspx' },
    { id: 'pattern', label: 'Pattern', page: 'AUXpattern1.aspx' },
    { id: 'pcs', label: 'PCS Coordination', page: 'AUXpcscoord1.aspx' },
    { id: 'sat', label: 'Satellite Bearings', page: 'AUXSataze1.aspx' },
    { id: 'sep', label: 'Separation Angles', page: 'AUXSepang1.aspx' },
    { id: 'coord', label: 'Coordination Checks', page: 'AUXCoordChk1.aspx' },
    { id: 'orbit', label: 'Orbit Intersection', page: 'AUXorbit.aspx' },
    { id: 'ohl', label: 'Over Horizon Losses', page: 'AUXOHLoss1.aspx' },
    { id: 'terrain', label: 'Terrain Profile', page: 'AUXTerrain1.aspx' },
    { id: 'area', label: 'Area Coordination', page: 'AUXAreaCoord1.aspx' },
    { id: 'pfd', label: 'Power Flux Density Contours', page: 'AUXpfdc1.aspx' },
    { id: 'genctx', label: 'CTX Curve Generation', page: 'AUXgenctx1.aspx' },
    { id: 'hilo', label: 'HiLo band check', page: 'AUXHilo1.aspx' },
    { id: 'nad27', label: 'NAD27–WGS84 (NRCAN)', page: 'external' }
  ];

  function mountAuxEng() {
    var route = parseRoute();
    var tool = route.params.tool || 'menu';
    var list = $('aux-tool-list');
    list.innerHTML = '';
    AUX_TOOLS.forEach(function (t) {
      var li = document.createElement('li');
      var a = document.createElement('a');
      a.href = '#';
      a.textContent = t.label;
      a.onclick = function (ev) {
        ev.preventDefault();
        if (t.id === 'distance') {
          show($('aux-distance'), true);
          show($('aux-links'), false);
          $('aux-title').textContent = 'FCSA Distance and Bearing Calculation';
        } else if (t.page === 'external') {
          window.open('http://webapp.geod.nrcan.gc.ca/geod/tools-outils/ntv2.php?locale=en', 'WndNRCAN');
        } else {
          window.open(micsRoot() + 'auxengmenu/' + t.page, 'WndAux',
            'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes');
        }
      };
      li.appendChild(a);
      list.appendChild(li);
    });
    show($('aux-distance'), tool === 'distance');
    show($('aux-links'), tool !== 'distance');
    if (tool === 'distance') $('aux-title').textContent = 'FCSA Distance and Bearing Calculation';
    if (tool && tool !== 'menu' && tool !== 'distance') {
      var pick = null;
      AUX_TOOLS.forEach(function (t) { if (t.id === tool) pick = t; });
      if (pick) {
        if (pick.page === 'external') {
          window.open('http://webapp.geod.nrcan.gc.ca/geod/tools-outils/ntv2.php?locale=en', 'WndNRCAN');
        } else if (pick.page) {
          window.open(micsRoot() + 'auxengmenu/' + pick.page, 'WndAux',
            'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes');
        }
      }
    }

    if ($('d-help')) {
      $('d-help').onclick = function () {
        window.open(micsRoot() + 'micshelp/disthelp.aspx', 'WndHelp',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=520,height=420');
      };
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
        if (status) status.textContent = 'Updating…';
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

  function mountPwdRecoverySetup() {
    window.open(micsRoot() + 'Maintenance/pwdqa.aspx', 'WndPref',
      'status=no,top=200,left=200,width=800,height=250,resizable=yes');
    if (global.RemicsApp) RemicsApp.navigate('welcome');
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
    mountPwdRecoverySetup: mountPwdRecoverySetup
  };
})(window);
