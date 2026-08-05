// RemIcsReWrite Phase 6.5 — Title / Site / Ante / Chan (+ ES Azimuth) edit.
(function (global) {
  var state = { name: '', filetype: 'TS', siteIsNew: false, anteIsNew: false, chanIsNew: false, azimIsNew: false, siteRec: null, anteRec: null, chanRec: null, azimRec: null };

  function $(id) { return document.getElementById(id); }
  function show(el, on) {
    if (!el) return;
    el.hidden = !on;
    el.style.display = on ? '' : 'none';
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
  function status(msg) {
    var el = $('pdf-edit-status');
    if (el) el.textContent = msg || '';
  }
  function goTree() {
    var v = state.filetype === 'ES' ? 'es-tree' : 'ts-tree';
    if (global.RemicsApp && RemicsApp.navigate) RemicsApp.navigate(v);
    else location.hash = '#/' + v;
  }

  var SITE_TS = ['cmd', 'call1', 'name', 'prov', 'oper', 'grnd', 'stats', 'notwr', 'icaccount', 'nots', 'snumb', 'spoint', 'reg', 'loc',
    'latDD', 'latMM', 'latSS', 'lat00', 'latDir', 'longDD', 'longMM', 'longSS', 'long00', 'longDir',
    'mDay', 'mMonth', 'mYear', 'sDay', 'sMonth', 'sYear'];
  var SITE_ES = ['cmd', 'location', 'name', 'prov', 'oper', 'grnd', 'stats', 'radio', 'rain', 'reg', 'nots', 'oprtyp',
    'latDD', 'latMM', 'latSS', 'lat00', 'latDir', 'longDD', 'longMM', 'longSS', 'long00', 'longDir',
    'mDay', 'mMonth', 'mYear', 'sDay', 'sMonth', 'sYear'];
  var ANTE_TS = ['cmd', 'call1', 'call2', 'bndcde', 'anum', 'ause', 'acode', 'aht', 'azmth', 'elvtn', 'dist', 'offazm',
    'tazmth', 'telvtn', 'tgain', 'atwrno', 'nota', 'licence'];
  var ANTE_ES = ['cmd', 'location', 'call1', 'ause', 'acode', 'aht', 'azmth', 'elvtn', 'nota'];
  var CHAN_TS = ['cmd', 'call1', 'call2', 'bndcde', 'chid', 'splan', 'hl', 'vh', 'freqtx', 'poltx', 'eqpttx', 'pwrtx',
    'freqrx', 'polrx', 'eqptrx', 'stattx', 'statrx', 'notegnl'];
  var CHAN_ES = ['cmd', 'location', 'call1', 'chid', 'freqtx', 'freqrx', 'poltx', 'polrx', 'eqpttx', 'eqptrx', 'pwrtx'];
  var AZIM_ES = ['cmd', 'location', 'call1', 'azim', 'elvtn', 'aht', 'acode', 'nota'];

  function renderFields(tableId, fields, rec, readonlyKeys) {
    if (global.RemicsPdfFields) {
      var schema = tableId.indexOf('site') >= 0
        ? (state.filetype === 'ES' ? 'SITE_ES' : 'SITE_TS')
        : tableId.indexOf('ante') >= 0
          ? (state.filetype === 'ES' ? 'ANTE_ES' : 'ANTE_TS')
          : tableId.indexOf('chan') >= 0
            ? (state.filetype === 'ES' ? 'CHAN_ES' : 'CHAN_TS')
            : null;
      if (schema) {
        RemicsPdfFields.render(tableId, schema, rec, readonlyKeys);
        return;
      }
    }
    var table = $(tableId);
    if (!table) return;
    table.innerHTML = '';
    readonlyKeys = readonlyKeys || [];
    fields.forEach(function (f) {
      var tr = document.createElement('tr');
      var td1 = document.createElement('td');
      td1.className = 'o';
      td1.textContent = f;
      var td2 = document.createElement('td');
      var inp = document.createElement('input');
      inp.id = 'fld-' + f;
      inp.setAttribute('data-field', f);
      inp.size = f.length > 8 ? 24 : 12;
      inp.value = (rec && rec[f] != null) ? String(rec[f]) : '';
      if (readonlyKeys.indexOf(f) >= 0) {
        inp.readOnly = true;
        inp.className = 'iro';
      }
      td2.appendChild(inp);
      tr.appendChild(td1);
      tr.appendChild(td2);
      table.appendChild(tr);
    });
  }

  function collectFields(tableId) {
    if (global.RemicsPdfFields && (tableId === 'site-fields' || tableId === 'ante-fields' || tableId === 'chan-fields')) {
      return RemicsPdfFields.collect(tableId);
    }
    var table = $(tableId);
    var rec = {};
    if (!table) return rec;
    table.querySelectorAll('input[data-field]').forEach(function (inp) {
      rec[inp.getAttribute('data-field')] = inp.value;
    });
    return rec;
  }

  function showPanel(name) {
    ['title', 'sites', 'antes', 'chans', 'azims', 'links', 'chng', 'cloc', 'ccal'].forEach(function (p) {
      show($('pdf-panel-' + p), p === name);
    });
  }

  function loadLinks() {
    status('Loading links…');
    RemIcsApi.pdfExtra('linksites', { name: state.name, filetype: 'TS' }).then(function (r) {
      if (!r.ok) { status(r.error || 'Failed'); return; }
      var list = $('links-list');
      list.innerHTML = '';
      (r.links || []).forEach(function (l) {
        var li = document.createElement('li');
        li.textContent = l.call1 + ' ↔ ' + l.call2 + ' / ' + l.bndcde;
        list.appendChild(li);
      });
      status((r.links || []).length + ' link key(s). ' + (r.note || ''));
      showPanel('links');
    });
  }

  function loadChng() {
    RemIcsApi.pdfExtra('chnglist', { name: state.name, filetype: 'TS' }).then(function (r) {
      if (!r.ok) { status(r.error || 'Failed'); return; }
      var list = $('chng-list');
      list.innerHTML = '';
      (r.rows || []).forEach(function (row) {
        var li = document.createElement('li');
        li.textContent = row.oldcall1 + ' → ' + row.newcall1 + (row.name ? ' (' + row.name + ')' : '');
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'bt';
        btn.textContent = 'Del';
        btn.onclick = function () {
          RemIcsApi.pdfExtra('chngdelete', {
            name: state.name, filetype: 'TS', oldcall1: row.oldcall1, newcall1: row.newcall1
          }).then(function () { loadChng(); });
        };
        li.appendChild(document.createTextNode(' '));
        li.appendChild(btn);
        list.appendChild(li);
      });
      status((r.rows || []).length + ' change(s)');
      showPanel('chng');
    });
  }

  function loadCloc() {
    RemIcsApi.pdfExtra('cloclist', { name: state.name, filetype: 'ES' }).then(function (r) {
      if (!r.ok) { status(r.error || 'Failed'); return; }
      var list = $('cloc-list');
      list.innerHTML = '';
      (r.rows || []).forEach(function (row) {
        var li = document.createElement('li');
        li.textContent = row.oldlocation + ' → ' + row.newlocation;
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'bt';
        btn.textContent = 'Del';
        btn.onclick = function () {
          RemIcsApi.pdfExtra('clocdelete', {
            name: state.name, filetype: 'ES', oldlocation: row.oldlocation, newlocation: row.newlocation
          }).then(function () { loadCloc(); });
        };
        li.appendChild(document.createTextNode(' '));
        li.appendChild(btn);
        list.appendChild(li);
      });
      showPanel('cloc');
    });
  }

  function loadCcal() {
    RemIcsApi.pdfExtra('ccallist', { name: state.name, filetype: 'ES' }).then(function (r) {
      if (!r.ok) { status(r.error || 'Failed'); return; }
      var list = $('ccal-list');
      list.innerHTML = '';
      (r.rows || []).forEach(function (row) {
        var li = document.createElement('li');
        li.textContent = row.oldcallsign + ' → ' + row.newcallsign;
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'bt';
        btn.textContent = 'Del';
        btn.onclick = function () {
          RemIcsApi.pdfExtra('ccaldelete', {
            name: state.name, filetype: 'ES', oldcallsign: row.oldcallsign, newcallsign: row.newcallsign
          }).then(function () { loadCcal(); });
        };
        li.appendChild(document.createTextNode(' '));
        li.appendChild(btn);
        list.appendChild(li);
      });
      showPanel('ccal');
    });
  }

  function loadTitle() {
    status('Loading title…');
    RemIcsApi.pdfEdit('titleGet', { name: state.name, filetype: state.filetype }).then(function (r) {
      if (!r.ok) { status(r.error || 'titleGet failed'); return; }
      var rec = r.record || {};
      $('titl-namef').value = rec.namef || state.name || '';
      $('titl-source').value = rec.source || '';
      $('titl-descr').value = rec.descr || '';
      $('titl-validated').value = rec.validated || '';
      if ($('titl-mDay')) $('titl-mDay').value = rec.mDay || '';
      if ($('titl-mMonth')) $('titl-mMonth').value = rec.mMonth || '';
      if ($('titl-mYear')) $('titl-mYear').value = rec.mYear || '';
      var th = $('pdf-title-heading');
      if (th) {
        th.textContent = state.filetype === 'ES'
          ? 'FCSA MICS Earth Station Title Record'
          : 'FCSA MICS Terrestrial Title Record';
      }
      status('');
      showPanel('title');
    });
  }

  function loadSites() {
    status('Loading sites…');
    show($('site-form'), false);
    RemIcsApi.pdfEdit('sitesList', { name: state.name, filetype: state.filetype }).then(function (r) {
      if (!r.ok) { status(r.error || 'sitesList failed'); return; }
      var list = $('site-list');
      list.innerHTML = '';
      (r.sites || []).forEach(function (s) {
        var li = document.createElement('li');
        var a = document.createElement('a');
        a.href = '#';
        a.textContent = s.key + (s.name ? ' — ' + s.name : '');
        a.addEventListener('click', function (ev) {
          ev.preventDefault();
          openSite(s.key, false);
        });
        li.appendChild(a);
        list.appendChild(li);
      });
      status((r.sites || []).length + ' site(s)');
      showPanel('sites');
    });
  }

  function setEntityHeading(id, tsText, esText) {
    var el = $(id);
    if (el) el.textContent = state.filetype === 'ES' ? esText : tsText;
  }

  function openSite(key, isNew) {
    state.siteIsNew = !!isNew;
    var fields = state.filetype === 'ES' ? SITE_ES : SITE_TS;
    if (isNew) {
      var blank = {};
      fields.forEach(function (f) { blank[f] = ''; });
      if (state.filetype === 'ES') blank.location = '';
      else blank.call1 = '';
      state.siteRec = blank;
      renderFields('site-fields', fields, blank, []);
      setEntityHeading('pdf-site-heading', 'FCSA MICS Terrestrial Site', 'FCSA MICS Earth Station Site');
      show($('site-form'), true);
      return;
    }
    RemIcsApi.pdfEdit('siteGet', { name: state.name, filetype: state.filetype, key: key }).then(function (r) {
      if (!r.ok) { status(r.error || 'siteGet failed'); return; }
      state.siteRec = r.record || {};
      renderFields('site-fields', fields, state.siteRec, state.filetype === 'ES' ? ['location'] : ['call1']);
      setEntityHeading('pdf-site-heading', 'FCSA MICS Terrestrial Site', 'FCSA MICS Earth Station Site');
      show($('site-form'), true);
    });
  }

  function loadAntes() {
    var siteKey = ($('ante-site-filter') && $('ante-site-filter').value) || '';
    status('Loading antennas…');
    show($('ante-form'), false);
    RemIcsApi.pdfEdit('antesList', { name: state.name, filetype: state.filetype, siteKey: siteKey }).then(function (r) {
      if (!r.ok) { status(r.error || 'antesList failed'); return; }
      var list = $('ante-list');
      list.innerHTML = '';
      (r.antes || []).forEach(function (a) {
        var li = document.createElement('li');
        var link = document.createElement('a');
        link.href = '#';
        link.textContent = a.key;
        link.addEventListener('click', function (ev) {
          ev.preventDefault();
          openAnte(a, false);
        });
        li.appendChild(link);
        list.appendChild(li);
      });
      status((r.antes || []).length + ' antenna(s)');
      showPanel('antes');
    });
  }

  function openAnte(row, isNew) {
    state.anteIsNew = !!isNew;
    var fields = state.filetype === 'ES' ? ANTE_ES : ANTE_TS;
    if (isNew) {
      var blank = {};
      fields.forEach(function (f) { blank[f] = ''; });
      state.anteRec = blank;
      renderFields('ante-fields', fields, blank, []);
      setEntityHeading('pdf-ante-heading', 'FCSA MICS Terrestrial Antenna', 'FCSA MICS Earth Station Antenna');
      show($('ante-form'), true);
      return;
    }
    var params = { name: state.name, filetype: state.filetype };
    if (state.filetype === 'ES') {
      params.location = row.location;
      params.call1 = row.call1;
    } else {
      params.call1 = row.call1;
      params.call2 = row.call2;
      params.bndcde = row.bndcde;
      params.anum = row.anum;
    }
    RemIcsApi.pdfEdit('anteGet', params).then(function (r) {
      if (!r.ok) { status(r.error || 'anteGet failed'); return; }
      state.anteRec = r.record || {};
      renderFields('ante-fields', fields, state.anteRec, state.filetype === 'ES' ? ['location', 'call1'] : ['call1', 'call2', 'bndcde', 'anum']);
      setEntityHeading('pdf-ante-heading', 'FCSA MICS Terrestrial Antenna', 'FCSA MICS Earth Station Antenna');
      show($('ante-form'), true);
    });
  }

  function loadChans() {
    var siteKey = ($('chan-site-filter') && $('chan-site-filter').value) || '';
    status('Loading channels…');
    show($('chan-form'), false);
    RemIcsApi.pdfEdit('chansList', { name: state.name, filetype: state.filetype, siteKey: siteKey }).then(function (r) {
      if (!r.ok) { status(r.error || 'chansList failed'); return; }
      var list = $('chan-list');
      list.innerHTML = '';
      (r.chans || []).forEach(function (c) {
        var li = document.createElement('li');
        var link = document.createElement('a');
        link.href = '#';
        link.textContent = c.key;
        link.addEventListener('click', function (ev) {
          ev.preventDefault();
          openChan(c, false);
        });
        li.appendChild(link);
        list.appendChild(li);
      });
      status((r.chans || []).length + ' channel(s)');
      showPanel('chans');
    });
  }

  function openChan(row, isNew) {
    state.chanIsNew = !!isNew;
    var fields = state.filetype === 'ES' ? CHAN_ES : CHAN_TS;
    if (isNew) {
      var blank = {};
      fields.forEach(function (f) { blank[f] = ''; });
      state.chanRec = blank;
      renderFields('chan-fields', fields, blank, []);
      setEntityHeading('pdf-chan-heading', 'FCSA MICS Terrestrial Channel', 'FCSA MICS Earth Station Channel');
      show($('chan-form'), true);
      return;
    }
    var params = { name: state.name, filetype: state.filetype };
    if (state.filetype === 'ES') {
      params.location = row.location;
      params.call1 = row.call1;
      params.chid = row.chid;
    } else {
      params.call1 = row.call1;
      params.call2 = row.call2;
      params.bndcde = row.bndcde;
      params.chid = row.chid;
    }
    RemIcsApi.pdfEdit('chanGet', params).then(function (r) {
      if (!r.ok) { status(r.error || 'chanGet failed'); return; }
      state.chanRec = r.record || {};
      renderFields('chan-fields', fields, state.chanRec, state.filetype === 'ES' ? ['location', 'call1', 'chid'] : ['call1', 'call2', 'bndcde', 'chid']);
      setEntityHeading('pdf-chan-heading', 'FCSA MICS Terrestrial Channel', 'FCSA MICS Earth Station Channel');
      show($('chan-form'), true);
    });
  }

  function loadAzims() {
    status('Loading azimuths…');
    show($('azim-form'), false);
    RemIcsApi.pdfEdit('azimsList', {
      name: state.name,
      filetype: 'ES',
      siteKey: ($('azim-site-filter') && $('azim-site-filter').value) || '',
      call1: ($('azim-call1-filter') && $('azim-call1-filter').value) || ''
    }).then(function (r) {
      if (!r.ok) { status(r.error || 'azimsList failed'); return; }
      var list = $('azim-list');
      list.innerHTML = '';
      (r.azims || []).forEach(function (a) {
        var li = document.createElement('li');
        var link = document.createElement('a');
        link.href = '#';
        link.textContent = a.key;
        link.addEventListener('click', function (ev) {
          ev.preventDefault();
          openAzim(a, false);
        });
        li.appendChild(link);
        list.appendChild(li);
      });
      status((r.azims || []).length + ' azimuth(s)');
      showPanel('azims');
    });
  }

  function openAzim(row, isNew) {
    state.azimIsNew = !!isNew;
    if (isNew) {
      var blank = {};
      AZIM_ES.forEach(function (f) { blank[f] = ''; });
      state.azimRec = blank;
      renderFields('azim-fields', AZIM_ES, blank, []);
      show($('azim-form'), true);
      return;
    }
    RemIcsApi.pdfEdit('azimGet', {
      name: state.name, filetype: 'ES',
      location: row.location, call1: row.call1, azim: row.azim
    }).then(function (r) {
      if (!r.ok) { status(r.error || 'azimGet failed'); return; }
      state.azimRec = r.record || {};
      renderFields('azim-fields', AZIM_ES, state.azimRec, ['location', 'call1', 'azim']);
      show($('azim-form'), true);
    });
  }

  function splitTreeKey(value) {
    return (value || '').split('.');
  }

  function openFromTreeKey(value, panel) {
    var parts = splitTreeKey(value);
    var p = parts[0];
    if (panel === 'title' || p === 't') {
      loadTitle();
      return;
    }
    if (panel === 'sites' || p === 'd') {
      openSite(parts[2] || '', false);
      return;
    }
    if (panel === 'antes' || p === 'a') {
      if (state.filetype === 'ES') {
        openAnte({ location: parts[2] || '', call1: parts[3] || '' }, false);
      } else {
        openAnte({
          call1: parts[2] || '',
          call2: parts[3] || '',
          bndcde: parts[4] || '',
          anum: parts[5] || ''
        }, false);
      }
      return;
    }
    if (panel === 'chans' || p === 'h' || p === 'c') {
      if (state.filetype === 'ES') {
        openChan({ location: parts[2] || '', call1: parts[3] || '', chid: parts[4] || '' }, false);
      } else {
        openChan({
          call1: parts[2] || '',
          call2: parts[3] || '',
          bndcde: parts[4] || '',
          chid: parts[5] || ''
        }, false);
      }
      return;
    }
    if (panel === 'chng' || (p === 'g' && state.filetype === 'TS')) {
      if ($('chng-old')) $('chng-old').value = parts[2] || '';
      if ($('chng-new')) $('chng-new').value = parts[3] || '';
      loadChng();
      return;
    }
    if (panel === 'cloc' || p === 'q') {
      if ($('cloc-old')) $('cloc-old').value = parts[2] || '';
      if ($('cloc-new')) $('cloc-new').value = parts[3] || '';
      loadCloc();
      return;
    }
    if (panel === 'ccal' || (p === 'g' && state.filetype === 'ES')) {
      if ($('ccal-old')) $('ccal-old').value = parts[2] || '';
      if ($('ccal-new')) $('ccal-new').value = parts[3] || '';
      loadCcal();
      return;
    }
    loadTitle();
  }

  function mount() {
    var route = parseRoute();
    state.name = (route.params.name || '').trim();
    state.filetype = (route.params.filetype || 'TS').toUpperCase() === 'ES' ? 'ES' : 'TS';
    if (!state.name) {
      status('Missing file name.');
      return;
    }
    if (global.RemicsApp && RemicsApp.setActiveFile) RemicsApp.setActiveFile(state.filetype, state.name);
    $('pdf-edit-heading').textContent = 'Edit ' + state.filetype + ' Contents';
    $('pdf-edit-meta').textContent = state.name + ' ';
    show($('pdf-btn-azims'), state.filetype === 'ES');
    show($('pdf-btn-links'), state.filetype === 'TS');
    show($('pdf-btn-chng'), state.filetype === 'TS');
    show($('pdf-btn-cloc'), state.filetype === 'ES');
    show($('pdf-btn-ccal'), state.filetype === 'ES');

    $('pdf-edit-back').onclick = goTree;
    if ($('titl-cancel')) $('titl-cancel').onclick = goTree;
    if ($('titl-source-lookup')) {
      $('titl-source-lookup').onclick = function () {
        window.open(
          RemIcsApi.micsRoot() + 'lookupscrns/lookup1.aspx?type=Operator&fld=titl-source',
          'WndLookup',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=520,height=420'
        );
      };
    }
    document.querySelectorAll('#pdf-panel-nav [data-panel]').forEach(function (btn) {
      btn.onclick = function () {
        var p = btn.getAttribute('data-panel');
        if (p === 'title') loadTitle();
        else if (p === 'sites') loadSites();
        else if (p === 'antes') loadAntes();
        else if (p === 'chans') loadChans();
        else if (p === 'azims') loadAzims();
        else if (p === 'links') loadLinks();
        else if (p === 'chng') loadChng();
        else if (p === 'cloc') loadCloc();
        else if (p === 'ccal') loadCcal();
      };
    });

    if ($('links-refresh')) $('links-refresh').onclick = loadLinks;
    if ($('links-help')) {
      $('links-help').onclick = function () {
        window.open(RemIcsApi.micsRoot() + 'micshelp/separatefiles/tsLink.aspx', 'WndHelp',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
      };
    }
    if ($('pdf-edit-back-links')) $('pdf-edit-back-links').onclick = goTree;
    if ($('chng-refresh')) $('chng-refresh').onclick = loadChng;
    if ($('chng-save')) {
      $('chng-save').onclick = function () {
        RemIcsApi.pdfExtra('chngsave', {
          name: state.name, filetype: 'TS',
          oldcall1: $('chng-old').value,
          newcall1: $('chng-new').value,
          sitename: $('chng-name').value
        }).then(function (r) {
          status(r.ok ? 'Saved.' : (r.error || 'Failed'));
          if (r.ok) loadChng();
        });
      };
    }
    if ($('chng-help')) {
      $('chng-help').onclick = function () {
        window.open(RemIcsApi.micsRoot() + 'micshelp/separatefiles/tsChangeofCallSign.aspx', 'WndHelp',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
      };
    }
    if ($('pdf-edit-back-chng')) $('pdf-edit-back-chng').onclick = goTree;
    if ($('cloc-refresh')) $('cloc-refresh').onclick = loadCloc;
    if ($('cloc-save')) {
      $('cloc-save').onclick = function () {
        RemIcsApi.pdfExtra('clocsave', {
          name: state.name, filetype: 'ES',
          oldlocation: $('cloc-old').value,
          newlocation: $('cloc-new').value,
          sitename: $('cloc-name').value
        }).then(function (r) {
          status(r.ok ? 'Saved.' : (r.error || 'Failed'));
          if (r.ok) loadCloc();
        });
      };
    }
    if ($('cloc-help')) {
      $('cloc-help').onclick = function () {
        window.open(RemIcsApi.micsRoot() + 'micshelp/separatefiles/esChangeofLocation.aspx', 'WndHelp',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
      };
    }
    if ($('pdf-edit-back-cloc')) $('pdf-edit-back-cloc').onclick = goTree;
    if ($('ccal-refresh')) $('ccal-refresh').onclick = loadCcal;
    if ($('ccal-save')) {
      $('ccal-save').onclick = function () {
        RemIcsApi.pdfExtra('ccalsave', {
          name: state.name, filetype: 'ES',
          oldcallsign: $('ccal-old').value,
          newcallsign: $('ccal-new').value
        }).then(function (r) {
          status(r.ok ? 'Saved.' : (r.error || 'Failed'));
          if (r.ok) loadCcal();
        });
      };
    }
    if ($('ccal-help')) {
      $('ccal-help').onclick = function () {
        window.open(RemIcsApi.micsRoot() + 'micshelp/separatefiles/esChangeofCallSign.aspx', 'WndHelp',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
      };
    }
    if ($('pdf-edit-back-ccal')) $('pdf-edit-back-ccal').onclick = goTree;

    $('titl-save').onclick = function () {
      RemIcsApi.pdfEdit('titleSave', {
        name: state.name,
        filetype: state.filetype,
        namef: $('titl-namef').value,
        source: $('titl-source').value,
        descr: $('titl-descr').value
      }).then(function (r) {
        status(r.ok ? 'Title saved (validated reset).' : (r.error || 'Save failed'));
        if (r.ok) loadTitle();
      });
    };

    $('site-new').onclick = function () { openSite('', true); };
    $('site-refresh').onclick = loadSites;
    $('site-cancel').onclick = function () { show($('site-form'), false); };
    $('site-save').onclick = function () {
      var rec = collectFields('site-fields');
      RemIcsApi.pdfEdit(state.siteIsNew ? 'siteNew' : 'siteSave', {
        name: state.name, filetype: state.filetype, record: JSON.stringify(rec)
      }).then(function (r) {
        status(r.ok ? 'Site saved.' : (r.error || 'Save failed'));
        if (r.ok) loadSites();
      });
    };

    $('ante-refresh').onclick = loadAntes;
    $('ante-new').onclick = function () { openAnte({}, true); };
    $('ante-cancel').onclick = function () { show($('ante-form'), false); };
    $('ante-save').onclick = function () {
      var rec = collectFields('ante-fields');
      RemIcsApi.pdfEdit(state.anteIsNew ? 'anteNew' : 'anteSave', {
        name: state.name, filetype: state.filetype, record: JSON.stringify(rec)
      }).then(function (r) {
        status(r.ok ? 'Antenna saved.' : (r.error || 'Save failed'));
        if (r.ok) loadAntes();
      });
    };

    $('chan-refresh').onclick = loadChans;
    $('chan-new').onclick = function () { openChan({}, true); };
    $('chan-cancel').onclick = function () { show($('chan-form'), false); };
    $('chan-save').onclick = function () {
      var rec = collectFields('chan-fields');
      RemIcsApi.pdfEdit(state.chanIsNew ? 'chanNew' : 'chanSave', {
        name: state.name, filetype: state.filetype, record: JSON.stringify(rec)
      }).then(function (r) {
        status(r.ok ? 'Channel saved.' : (r.error || 'Save failed'));
        if (r.ok) loadChans();
      });
    };

    if ($('azim-refresh')) {
      $('azim-refresh').onclick = loadAzims;
      $('azim-new').onclick = function () { openAzim({}, true); };
      $('azim-cancel').onclick = function () { show($('azim-form'), false); };
      $('azim-save').onclick = function () {
        var rec = collectFields('azim-fields');
        RemIcsApi.pdfEdit(state.azimIsNew ? 'azimNew' : 'azimSave', {
          name: state.name, filetype: 'ES', record: JSON.stringify(rec)
        }).then(function (r) {
          status(r.ok ? 'Azimuth saved.' : (r.error || 'Save failed'));
          if (r.ok) loadAzims();
        });
      };
    }
    if ($('azim-help')) {
      $('azim-help').onclick = function () {
        window.open(RemIcsApi.micsRoot() + 'micshelp/separatefiles/esAzimuth.aspx', 'WndHelp',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
      };
    }
    if ($('pdf-edit-back-azims')) $('pdf-edit-back-azims').onclick = goTree;

    var startPanel = (route.params.panel || 'title').toLowerCase();
    var treeKey = (route.params.key || '').trim();
    if (treeKey) {
      openFromTreeKey(treeKey, startPanel);
    } else if (startPanel === 'sites') loadSites();
    else if (startPanel === 'antes') loadAntes();
    else if (startPanel === 'chans') loadChans();
    else if (startPanel === 'chng') loadChng();
    else if (startPanel === 'cloc') loadCloc();
    else loadTitle();
  }

  global.RemicsPdf = { mount: mount };
})(window);
