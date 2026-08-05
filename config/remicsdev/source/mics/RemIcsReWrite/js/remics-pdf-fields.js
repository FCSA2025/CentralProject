// Classic PDF edit field layouts (IP-1 parity with tsSite / tsAnte / tsChan).
(function (global) {
  function openLookup(lookupType, inputId, btnStyle) {
    var url = RemIcsApi.micsRoot() + 'lookupscrns/lookup1.aspx?type=' +
      encodeURIComponent(lookupType) + '&fld=' + encodeURIComponent(inputId);
    window.open(url, 'WndLookup', 'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=520,height=420');
  }

  function mkInput(key, rec, ro, cls, size, max) {
    var inp = document.createElement('input');
    inp.id = 'fld-' + key;
    inp.setAttribute('data-field', key);
    inp.className = cls || 'im';
    if (size) inp.size = size;
    if (max) inp.maxLength = max;
    inp.value = (rec && rec[key] != null) ? String(rec[key]) : '';
    if (ro) {
      inp.readOnly = true;
      inp.tabIndex = -1;
      inp.className = cls || 'iro';
    }
    return inp;
  }

  function mkLookupBtn(lookupType, fieldKey, btnLabel) {
    var btn = document.createElement('input');
    btn.type = 'button';
    btn.className = 'bt';
    btn.value = btnLabel || '?';
    btn.tabIndex = -1;
    btn.onclick = function () { openLookup(lookupType, 'fld-' + fieldKey); };
    return btn;
  }

  function addRow(table, cells) {
    var tr = document.createElement('tr');
    cells.forEach(function (c) {
      if (!c) return;
      var td = document.createElement('td');
      if (c.className) td.className = c.className;
      if (c.colspan) td.colSpan = c.colspan;
      if (c.label) td.textContent = c.label;
      if (c.el) td.appendChild(c.el);
      if (c.nodes) c.nodes.forEach(function (n) { td.appendChild(n); });
      tr.appendChild(td);
    });
    table.appendChild(tr);
  }

  function renderDmsRow(table, prefix, label, rec, ro) {
    var keys = [prefix + 'DD', prefix + 'MM', prefix + 'SS', prefix + '00', prefix + 'Dir'];
    var cls = ro ? 'iro' : 'im';
    var parts = keys.map(function (k, i) {
      var inp = mkInput(k, rec, ro, cls, i === 0 ? 4 : 2, i === 4 ? 1 : 2);
      var sep = document.createTextNode(i < 3 ? '-' : (i === 3 ? '.' : ''));
      return { inp: inp, sep: sep };
    });
    var tdVal = document.createElement('td');
    tdVal.className = 'by';
    parts.forEach(function (p, i) {
      tdVal.appendChild(p.inp);
      if (p.sep.textContent) tdVal.appendChild(p.sep);
    });
    addRow(table, [
      { className: 'm', label: label },
      { el: tdVal, colspan: 3 }
    ]);
  }

  var SCHEMAS = {
    SITE_TS: function (table, rec, roKeys) {
      roKeys = roKeys || [];
      function ro(k) { return roKeys.indexOf(k) >= 0; }
      addRow(table, [
        { className: 'm', label: 'MDB Operation' },
        { className: 'by', nodes: [mkInput('cmd', rec, ro('cmd')), mkLookupBtn('MdbOperation', 'cmd', '?')] },
        { className: 'm', label: '' },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'rok', label: 'Call Sign Local' },
        { className: 'by', el: mkInput('call1', rec, true, 'irok', 12, 9) },
        { className: 'm', label: '' },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'm', label: 'Name' },
        { className: 'by', el: mkInput('name', rec, ro('name'), 'im', 45, 32), colspan: 3 }
      ]);
      addRow(table, [
        { className: 'm', label: 'Province' },
        { className: 'by', nodes: [mkInput('prov', rec, ro('prov'), 'im', 4, 2), mkLookupBtn('Province', 'prov', '?')] },
        { className: 'm', label: 'Operator' },
        { className: 'by', nodes: [mkInput('oper', rec, ro('oper'), 'im', 10, 6), mkLookupBtn('Operator', 'oper', '??')] }
      ]);
      renderDmsRow(table, 'lat', 'Latitude (WGS84)', rec, false);
      renderDmsRow(table, 'long', 'Longitude (WGS84)', rec, false);
      addRow(table, [
        { className: 'm', label: 'Ground Height' },
        { className: 'by', el: mkInput('grnd', rec, ro('grnd'), 'im', 10, 7) },
        { className: 'm', label: 'Site Status' },
        { className: 'by', nodes: [mkInput('stats', rec, ro('stats'), 'im', 4, 1), mkLookupBtn('SiteStatus', 'stats', '?')] }
      ]);
      addRow(table, [
        { className: 'o', label: 'No. of Towers' },
        { className: 'by', el: mkInput('notwr', rec, ro('notwr'), 'im', 4, 1) },
        { className: 'o', label: 'IC Account' },
        { className: 'by', el: mkInput('icaccount', rec, ro('icaccount'), 'im', 14, 12) }
      ]);
      addRow(table, [
        { className: 'o', label: 'Registration' },
        { className: 'by', el: mkInput('reg', rec, ro('reg'), 'im', 12, 10) },
        { className: 'o', label: 'Location' },
        { className: 'by', el: mkInput('loc', rec, ro('loc'), 'im', 12, 10) }
      ]);
      addRow(table, [
        { className: 'o', label: 'Notes' },
        { className: 'by', el: mkInput('nots', rec, ro('nots'), 'im', 40, 32), colspan: 3 }
      ]);
      addRow(table, [
        { className: 'o', label: 'Service Date' },
        { className: 'by', nodes: [
          mkInput('sDay', rec, ro('sDay'), 'im', 2, 2),
          document.createTextNode('-'),
          mkInput('sMonth', rec, ro('sMonth'), 'im', 4, 3),
          document.createTextNode('-'),
          mkInput('sYear', rec, ro('sYear'), 'im', 6, 4)
        ] },
        { className: 'tdro', label: 'Modify Date' },
        { className: 'by', nodes: [
          mkInput('mDay', rec, true, 'iro', 2, 2),
          mkInput('mMonth', rec, true, 'iro', 4, 3),
          mkInput('mYear', rec, true, 'iro', 6, 4)
        ] }
      ]);
    },
    SITE_ES: function (table, rec, roKeys) {
      roKeys = roKeys || [];
      function ro(k) { return roKeys.indexOf(k) >= 0; }
      addRow(table, [
        { className: 'rok', label: 'Location' },
        { className: 'by', el: mkInput('location', rec, ro('location'), 'im', 16, 12) },
        { className: 'm', label: '' },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'm', label: 'Name' },
        { className: 'by', el: mkInput('name', rec, ro('name'), 'im', 45, 32), colspan: 3 }
      ]);
      addRow(table, [
        { className: 'm', label: 'Province' },
        { className: 'by', nodes: [mkInput('prov', rec, ro('prov'), 'im', 4, 2), mkLookupBtn('Province', 'prov', '?')] },
        { className: 'm', label: 'Operator' },
        { className: 'by', nodes: [mkInput('oper', rec, ro('oper'), 'im', 10, 6), mkLookupBtn('Operator', 'oper', '??')] }
      ]);
      renderDmsRow(table, 'lat', 'Latitude (WGS84)', rec, false);
      renderDmsRow(table, 'long', 'Longitude (WGS84)', rec, false);
      addRow(table, [
        { className: 'm', label: 'Ground Height' },
        { className: 'by', el: mkInput('grnd', rec, ro('grnd'), 'im', 10, 7) },
        { className: 'm', label: 'Site Status' },
        { className: 'by', nodes: [mkInput('stats', rec, ro('stats'), 'im', 4, 1), mkLookupBtn('SiteStatus', 'stats', '?')] }
      ]);
    },
    ANTE_TS: function (table, rec, roKeys) {
      roKeys = roKeys || [];
      function ro(k) { return roKeys.indexOf(k) >= 0; }
      addRow(table, [
        { className: 'm', label: 'MDB Operation' },
        { className: 'by', nodes: [mkInput('cmd', rec, ro('cmd')), mkLookupBtn('MdbOperation', 'cmd', '?')] },
        { className: 'm', label: '' },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'rok', label: 'Antenna No' },
        { className: 'by', el: mkInput('anum', rec, true, 'irok', 4, 2) },
        { className: 'o', label: 'Tower No' },
        { className: 'by', nodes: [mkInput('atwrno', rec, ro('atwrno'), 'im', 6, 4), mkLookupBtn('TowerNumber', 'atwrno', '?')] }
      ]);
      addRow(table, [
        { className: 'rok', label: 'Band Code' },
        { className: 'by', el: mkInput('bndcde', rec, true, 'irok', 6, 4) },
        { className: 'm', label: 'Antenna Code' },
        { className: 'by', nodes: [mkInput('acode', rec, ro('acode'), 'im', 14, 12), mkLookupBtn('AnteCode', 'acode', '??')] }
      ]);
      addRow(table, [
        { className: 'm', label: 'Height (m)' },
        { className: 'by', el: mkInput('aht', rec, ro('aht'), 'im', 10, 8) },
        { className: 'm', label: 'Azimuth' },
        { className: 'by', el: mkInput('azmth', rec, ro('azmth'), 'im', 10, 8) }
      ]);
      addRow(table, [
        { className: 'm', label: 'Elevation' },
        { className: 'by', el: mkInput('elvtn', rec, ro('elvtn'), 'im', 10, 8) },
        { className: 'm', label: 'Use' },
        { className: 'by', el: mkInput('ause', rec, ro('ause'), 'im', 6, 4) }
      ]);
    },
    ANTE_ES: function (table, rec, roKeys) {
      roKeys = roKeys || [];
      function ro(k) { return roKeys.indexOf(k) >= 0; }
      addRow(table, [
        { className: 'rok', label: 'Location' },
        { className: 'by', el: mkInput('location', rec, true, 'irok', 14, 12) },
        { className: 'rok', label: 'Call1' },
        { className: 'by', el: mkInput('call1', rec, true, 'irok', 12, 9) }
      ]);
      addRow(table, [
        { className: 'm', label: 'Antenna Code' },
        { className: 'by', nodes: [mkInput('acode', rec, ro('acode'), 'im', 14, 12), mkLookupBtn('AnteCode', 'acode', '??')] },
        { className: 'm', label: 'Height (m)' },
        { className: 'by', el: mkInput('aht', rec, ro('aht'), 'im', 10, 8) }
      ]);
      addRow(table, [
        { className: 'm', label: 'Azimuth' },
        { className: 'by', el: mkInput('azmth', rec, ro('azmth'), 'im', 10, 8) },
        { className: 'm', label: 'Elevation' },
        { className: 'by', el: mkInput('elvtn', rec, ro('elvtn'), 'im', 10, 8) }
      ]);
    },
    CHAN_TS: function (table, rec, roKeys) {
      roKeys = roKeys || [];
      function ro(k) { return roKeys.indexOf(k) >= 0; }
      addRow(table, [
        { className: 'rok', label: 'Channel ID' },
        { className: 'by', el: mkInput('chid', rec, ro('chid'), 'im', 8, 4) },
        { className: 'm', label: 'Spectrum Plan' },
        { className: 'by', el: mkInput('splan', rec, ro('splan'), 'im', 10, 8) }
      ]);
      addRow(table, [
        { className: 'm', label: 'Tx Frequency' },
        { className: 'by', el: mkInput('freqtx', rec, ro('freqtx'), 'im', 14, 12) },
        { className: 'm', label: 'Rx Frequency' },
        { className: 'by', el: mkInput('freqrx', rec, ro('freqrx'), 'im', 14, 12) }
      ]);
      addRow(table, [
        { className: 'm', label: 'Tx Polarization' },
        { className: 'by', el: mkInput('poltx', rec, ro('poltx'), 'im', 6, 4) },
        { className: 'm', label: 'Rx Polarization' },
        { className: 'by', el: mkInput('polrx', rec, ro('polrx'), 'im', 6, 4) }
      ]);
    },
    CHAN_ES: function (table, rec, roKeys) {
      roKeys = roKeys || [];
      function ro(k) { return roKeys.indexOf(k) >= 0; }
      addRow(table, [
        { className: 'rok', label: 'Location' },
        { className: 'by', el: mkInput('location', rec, true, 'irok', 14, 12) },
        { className: 'rok', label: 'Channel ID' },
        { className: 'by', el: mkInput('chid', rec, ro('chid'), 'im', 8, 4) }
      ]);
      addRow(table, [
        { className: 'm', label: 'Tx Frequency' },
        { className: 'by', el: mkInput('freqtx', rec, ro('freqtx'), 'im', 14, 12) },
        { className: 'm', label: 'Rx Frequency' },
        { className: 'by', el: mkInput('freqrx', rec, ro('freqrx'), 'im', 14, 12) }
      ]);
    }
  };

  function render(tableId, schemaName, rec, roKeys) {
    var table = document.getElementById(tableId);
    if (!table) return;
    table.innerHTML = '';
    table.className = 'classic-form classic-form-wide';
    var fn = SCHEMAS[schemaName];
    if (fn) fn(table, rec || {}, roKeys || []);
  }

  function collect(tableId) {
    var table = document.getElementById(tableId);
    var rec = {};
    if (!table) return rec;
    table.querySelectorAll('input[data-field]').forEach(function (inp) {
      rec[inp.getAttribute('data-field')] = inp.value;
    });
    return rec;
  }

  global.RemicsPdfFields = { render: render, collect: collect, openLookup: openLookup };
})(window);
