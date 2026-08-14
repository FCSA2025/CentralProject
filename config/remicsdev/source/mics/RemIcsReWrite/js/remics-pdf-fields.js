// Classic PDF edit field layouts (IP-1 parity with tsSite / tsAnte / tsChan).
(function (global) {
  function openLookup(lookupType, inputId, mandatoryPrefix, inputId2) {
    if (global.RemicsLookup) {
      RemicsLookup.open(lookupType, inputId, {
        mandatory: !!mandatoryPrefix,
        fld2: inputId2 || null
      });
    }
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

  function linkedId(linkedFieldKey) {
    if (!linkedFieldKey) return null;
    if (linkedFieldKey.indexOf('fld-') === 0 || linkedFieldKey.indexOf('chan-') === 0) return linkedFieldKey;
    return 'fld-' + linkedFieldKey;
  }

  function mkLookupBtn(lookupType, fieldKey, btnLabel, linkedFieldKey, twoField) {
    var btn = document.createElement('input');
    btn.type = 'button';
    btn.className = 'bt';
    btn.value = btnLabel || '?';
    btn.tabIndex = -1;
    btn.onclick = function () {
      if (global.RemicsLookup) {
        RemicsLookup.open(lookupType, 'fld-' + fieldKey, {
          mandatory: btnLabel === '??',
          fld2: linkedId(linkedFieldKey),
          twoField: !!twoField
        });
      } else {
        openLookup(lookupType, 'fld-' + fieldKey, btnLabel === '??', linkedId(linkedFieldKey));
      }
    };
    return btn;
  }

  function mkDisplay(id, size) {
    var inp = document.createElement('input');
    inp.id = id;
    inp.className = 'iro';
    inp.readOnly = true;
    inp.tabIndex = -1;
    if (size) inp.size = size;
    return inp;
  }

  function mkText(s) {
    return document.createTextNode(s);
  }

  function mkFindAnteBtn(fieldKey) {
    var btn = document.createElement('input');
    btn.type = 'button';
    btn.className = 'bt';
    btn.value = 'Find…';
    btn.title = 'Search by manufacturer, model, description, or code (SDF + main)';
    btn.tabIndex = -1;
    btn.onclick = function () { openAnteFinder(fieldKey); };
    return btn;
  }

  function mkHidden(key, rec) {
    var inp = mkInput(key, rec, true, 'iro', 1, 1);
    inp.type = 'hidden';
    return inp;
  }

  function addRow(table, cells) {
    var tr = document.createElement('tr');
    cells.forEach(function (c) {
      if (!c) return;
      var td = document.createElement('td');
      if (c.className) td.className = c.className;
      if (c.colspan) td.colSpan = c.colspan;
      if (c.label) td.textContent = c.label;
      if (c.html) td.innerHTML = c.html;
      if (c.el) td.appendChild(c.el);
      if (c.nodes) c.nodes.forEach(function (n) { td.appendChild(n); });
      tr.appendChild(td);
    });
    table.appendChild(tr);
  }

  function dateParts(table, rec, sRo, labelS, labelM) {
    addRow(table, [
      { className: 'o', label: labelS || 'Service Date' },
      { className: 'by', nodes: [
        mkInput('sDay', rec, sRo, 'im', 2, 2),
        document.createTextNode('-'),
        mkInput('sMonth', rec, sRo, 'im', 4, 3),
        document.createTextNode('-'),
        mkInput('sYear', rec, sRo, 'im', 6, 4)
      ] },
      { className: 'tdro', label: labelM || 'Modify Date' },
      { className: 'by', nodes: [
        mkInput('mDay', rec, true, 'iro', 2, 2),
        mkInput('mMonth', rec, true, 'iro', 4, 3),
        mkInput('mYear', rec, true, 'iro', 6, 4)
      ] }
    ]);
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
    parts.forEach(function (p) {
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
        { className: 'by', el: mkInput('call1', rec, ro('call1'), ro('call1') ? 'irok' : 'im', 12, 9) },
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
        { className: 'by', nodes: [mkInput('nots', rec, ro('nots'), 'im', 8, 4), mkLookupBtn('NotesOper', 'nots', '?', 'oper')] },
        { className: 'o', label: 'Site Number' },
        { className: 'by', el: mkInput('snumb', rec, ro('snumb'), 'im', 8, 4) }
      ]);
      addRow(table, [
        { className: 'o', label: 'Pointer' },
        { className: 'by', el: mkInput('spoint', rec, ro('spoint'), 'im', 8, 4) },
        { className: 'o', label: '' },
        { className: 'by', label: '' }
      ]);
      dateParts(table, rec, ro('sDay'));
    },
    SITE_ES: function (table, rec, roKeys) {
      roKeys = roKeys || [];
      function ro(k) { return roKeys.indexOf(k) >= 0; }
      addRow(table, [
        { className: 'tdro', label: 'MDB Operation' },
        { className: 'by', el: mkInput('cmd', rec, true, 'iro', 4, 1) },
        { className: 'm', label: '' },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'rok', label: 'Location Code' },
        { className: 'by', el: mkInput('location', rec, ro('location'), ro('location') ? 'irok' : 'ik', 12, 10) },
        { className: 'm', label: 'Name' },
        { className: 'by', el: mkInput('name', rec, ro('name'), 'im', 20, 16) }
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
        { className: 'by', el: mkInput('grnd', rec, ro('grnd'), 'im', 8, 6) },
        { className: 'm', label: 'Site Status' },
        { className: 'by', nodes: [mkInput('stats', rec, ro('stats'), 'im', 4, 1), mkLookupBtn('SiteStatus', 'stats', '?')] }
      ]);
      addRow(table, [
        { className: 'm', label: 'Radio' },
        { className: 'by', nodes: [mkInput('radio', rec, ro('radio'), 'im', 4, 2), mkLookupBtn('Radio', 'radio', '?')] },
        { className: 'm', label: 'Rain' },
        { className: 'by', nodes: [mkInput('rain', rec, ro('rain'), 'im', 4, 1), mkLookupBtn('Rain', 'rain', '?')] }
      ]);
      addRow(table, [
        { className: 'o', label: 'Region' },
        { className: 'by', el: mkInput('reg', rec, ro('reg'), 'im', 4, 2) },
        { className: 'o', label: 'Notes' },
        { className: 'by', nodes: [mkInput('nots', rec, ro('nots'), 'im', 8, 4), mkLookupBtn('NotesOper', 'nots', '?', 'oper')] }
      ]);
      dateParts(table, rec, ro('sDay'));
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
        { className: 'rok', label: 'Local' },
        { className: 'by', el: mkInput('call1', rec, ro('call1'), ro('call1') ? 'irok' : 'im', 12, 9) },
        { className: 'rok', label: 'Remote' },
        { className: 'by', el: mkInput('call2', rec, ro('call2'), ro('call2') ? 'irok' : 'im', 12, 9) }
      ]);
      addRow(table, [
        { className: 'rok', label: 'Antenna No' },
        { className: 'by', el: mkInput('anum', rec, ro('anum'), ro('anum') ? 'irok' : 'im', 4, 2) },
        { className: 'rok', label: 'Band Code' },
        { className: 'by', nodes: [
          mkInput('bndcde', rec, ro('bndcde'), ro('bndcde') ? 'irok' : 'im', 6, 4),
          mkLookupBtn('BandCode', 'bndcde', '?')
        ] }
      ]);
      addRow(table, [
        { className: 'o', label: 'Tower No' },
        { className: 'by', nodes: [
          mkInput('atwrno', rec, ro('atwrno'), 'im', 6, 4),
          mkLookupBtn('TowerNumber', 'atwrno', '?', 'call1')
        ] },
        { className: 'm', label: 'Antenna Code' },
        { className: 'by', nodes: [
          mkInput('acode', rec, ro('acode'), 'im', 14, 12),
          mkFindAnteBtn('acode'),
          mkLookupBtn('AnteCode', 'acode', '?')
        ] }
      ]);
      var glance = document.createElement('span');
      glance.id = 'ante-sdf-glance';
      glance.className = 'classic-hint';
      glance.textContent = 'Use Find… to search manufacturer / model / description.';
      addRow(table, [
        { className: 'tdro', label: 'SDF Antenna' },
        { className: 'by', el: glance, colspan: 3 }
      ]);
      addRow(table, [
        { className: 'm', label: 'Use' },
        { className: 'by', nodes: [mkInput('ause', rec, ro('ause'), 'im', 6, 3), mkLookupBtn('AnteUse', 'ause', '?')] },
        { className: 'm', label: 'Height (m)' },
        { className: 'by', el: mkInput('aht', rec, ro('aht'), 'im', 10, 7) }
      ]);
      addRow(table, [
        { className: 'tdro', label: 'Azimuth' },
        { className: 'by', el: mkInput('azmth', rec, true, 'iro', 10, 8) },
        { className: 'tdro', label: 'Elevation' },
        { className: 'by', el: mkInput('elvtn', rec, true, 'iro', 10, 8) }
      ]);
      addRow(table, [
        { className: 'tdro', label: 'Distance' },
        { className: 'by', el: mkInput('dist', rec, true, 'iro', 10, 8) },
        { className: 'o', label: 'Off Azimuth' },
        { className: 'by', el: mkInput('offazm', rec, ro('offazm'), 'im', 4, 1) }
      ]);
      addRow(table, [
        { className: 'o', label: 'True Azimuth' },
        { className: 'by', el: mkInput('tazmth', rec, ro('tazmth'), 'im', 10, 6) },
        { className: 'o', label: 'True Elevation' },
        { className: 'by', el: mkInput('telvtn', rec, ro('telvtn'), 'im', 10, 6) }
      ]);
      addRow(table, [
        { className: 'o', label: 'True Gain' },
        { className: 'by', el: mkInput('tgain', rec, ro('tgain'), 'im', 8, 4) },
        { className: 'o', label: 'K Value' },
        { className: 'by', el: mkInput('kvalue', rec, ro('kvalue'), 'im', 8, 4) }
      ]);
      addRow(table, [
        { className: 'o', label: 'Obstruction Loss' },
        { className: 'by', el: mkInput('obsloss', rec, ro('obsloss'), 'im', 8, 6) },
        { className: 'o', label: 'Notes' },
        { className: 'by', nodes: [mkInput('nota', rec, ro('nota'), 'im', 8, 4), mkLookupBtn('NotesCall1', 'nota', '?', 'call1')] }
      ]);
      addRow(table, [
        { className: 'o', label: 'Pointer' },
        { className: 'by', el: mkInput('apoint', rec, ro('apoint'), 'im', 8, 4) },
        { className: 'o', label: 'Licence' },
        { className: 'by', el: mkInput('licence', rec, ro('licence'), 'im', 16, 13) }
      ]);
      addRow(table, [
        { className: 'o', label: 'Tx Component Loss' },
        { className: 'by', el: mkInput('txcompl', rec, ro('txcompl'), 'im', 8, 5) },
        { className: 'o', label: 'Rx Component Loss' },
        { className: 'by', el: mkInput('rxcompl', rec, ro('rxcompl'), 'im', 8, 5) }
      ]);
      addRow(table, [
        { className: 'o', label: 'Tx Feed H Type' },
        { className: 'by', el: mkInput('txfdlnth', rec, ro('txfdlnth'), 'im', 6, 2) },
        { className: 'o', label: 'Rx Feed H Type' },
        { className: 'by', el: mkInput('rxfdlnth', rec, ro('rxfdlnth'), 'im', 6, 2) }
      ]);
      addRow(table, [
        { className: 'o', label: 'Tx Feed H Length' },
        { className: 'by', el: mkInput('txfdlnlh', rec, ro('txfdlnlh'), 'im', 8, 5) },
        { className: 'o', label: 'Rx Feed H Length' },
        { className: 'by', el: mkInput('rxfdlnlh', rec, ro('rxfdlnlh'), 'im', 8, 5) }
      ]);
      addRow(table, [
        { className: 'o', label: 'Tx Feed V Type' },
        { className: 'by', el: mkInput('txfdlntv', rec, ro('txfdlntv'), 'im', 6, 2) },
        { className: 'o', label: 'Rx Feed V Type' },
        { className: 'by', el: mkInput('rxfdlntv', rec, ro('rxfdlntv'), 'im', 6, 2) }
      ]);
      addRow(table, [
        { className: 'o', label: 'Tx Feed V Length' },
        { className: 'by', el: mkInput('txfdlnlv', rec, ro('txfdlnlv'), 'im', 8, 5) },
        { className: 'o', label: 'Rx Feed V Length' },
        { className: 'by', el: mkInput('rxfdlnlv', rec, ro('rxfdlnlv'), 'im', 8, 5) }
      ]);
      addRow(table, [
        { className: 'o', label: 'Tx Pad/Amp' },
        { className: 'by', el: mkInput('txpadpam', rec, ro('txpadpam'), 'im', 8, 5) },
        { className: 'o', label: 'Rx Pad/LNA' },
        { className: 'by', el: mkInput('rxpadlna', rec, ro('rxpadlna'), 'im', 8, 5) }
      ]);
      dateParts(table, rec, ro('sDay'));
    },
    ANTE_ES: function (table, rec, roKeys) {
      roKeys = roKeys || [];
      function ro(k) { return roKeys.indexOf(k) >= 0; }
      table.className += ' classic-chan-form';
      addRow(table, [
        { className: 'rok', label: 'Site' },
        { className: 'by', nodes: [
          mkDisplay('es-glance-location', 12),
          mkDisplay('es-glance-name', 20),
          mkDisplay('es-glance-prov', 3),
          mkDisplay('es-glance-oper', 8)
        ], colspan: 3 }
      ]);
      addRow(table, [
        { className: 'tdro', label: 'MDB Operation' },
        { className: 'by', el: mkInput('cmd', rec, true, 'iro', 4, 1) },
        { className: 'm', label: '' },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'rok', label: 'Location Code' },
        { className: 'by', el: mkInput('location', rec, ro('location'), ro('location') ? 'irok' : 'ik', 14, 10) },
        { className: 'rok', label: 'Call Sign' },
        { className: 'by', el: mkInput('call1', rec, ro('call1'), ro('call1') ? 'irok' : 'ik', 12, 9) }
      ]);
      addRow(table, [
        { className: 'o', label: 'Licence' },
        { className: 'by', el: mkInput('licence', rec, ro('licence'), 'im', 16, 13) },
        { className: 'm', label: '' },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'm', label: 'Antenna Height' },
        { className: 'by', el: mkInput('aht', rec, ro('aht'), 'im', 10, 6) },
        { className: 'tdro', label: 'Azimuth' },
        { className: 'by', el: mkInput('az', rec, true, 'iro', 10, 8) }
      ]);
      addRow(table, [
        { className: 'tdro', label: 'Elevation Angle' },
        { className: 'by', el: mkInput('el', rec, true, 'iro', 10, 8) },
        { className: 'o', label: 'Antenna Reference' },
        { className: 'by', el: mkInput('antref', rec, ro('antref'), 'im', 8, 6) }
      ]);
      addRow(table, [
        { className: 'o', label: 'Gain/Temperature' },
        { className: 'by', el: mkInput('g_t', rec, ro('g_t'), 'im', 8, 5) },
        { className: 'o', label: 'Noise Temperature' },
        { className: 'by', el: mkInput('lnat', rec, ro('lnat'), 'im', 8, 5) }
      ]);
      addRow(table, [
        { className: 'm', label: 'Satellite Oper.' },
        { className: 'by', nodes: [mkInput('op2', rec, ro('op2'), 'im', 4, 2), mkLookupBtn('SatOper', 'op2', '?')] },
        { className: 'o', label: 'Orbit' },
        { className: 'by', nodes: [mkInput('orbit', rec, ro('orbit'), 'im', 4, 2), mkLookupBtn('Orbit', 'orbit', '?')] }
      ]);
      addRow(table, [
        { className: 'o', label: 'Satellite Name' },
        { className: 'by', el: mkInput('satname', rec, ro('satname'), 'im', 18, 16) },
        { className: 'm', label: 'Satellite Longitude' },
        { className: 'by', nodes: [
          mkInput('satlong', rec, ro('satlong'), 'im', 8, 6),
          mkInput('satlongs', rec, ro('satlongs'), 'im', 3, 2)
        ] }
      ]);
      addRow(table, [
        { className: 'm', label: 'Arc Orbit Center' },
        { className: 'by', el: mkInput('sarc1', rec, ro('sarc1'), 'im', 10, 6) },
        { className: 'm', label: 'Arc Half Width' },
        { className: 'by', el: mkInput('sarc2', rec, ro('sarc2'), 'im', 8, 5) }
      ]);
      addRow(table, [
        { className: 'o', label: 'Notes' },
        { className: 'by', nodes: [mkInput('nota', rec, ro('nota'), 'im', 8, 4), mkLookupBtn('NotesLocation', 'nota', '?', 'location')] },
        { className: 'm', label: '' },
        { className: 'by', el: mkHidden('satlongit', rec) }
      ]);
      addRow(table, [
        { className: 'by', label: '' },
        { className: 'b', label: 'TRANSMIT' },
        { className: 'b', label: 'RECEIVE' },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'm', label: 'Antenna Feed System Loss' },
        { className: 'by', el: mkInput('afslt', rec, ro('afslt'), 'im', 8, 4) },
        { className: 'by', el: mkInput('afslr', rec, ro('afslr'), 'im', 8, 4) },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'm', label: 'Band' },
        { className: 'by', nodes: [mkInput('txband', rec, ro('txband'), 'im', 8, 4), mkLookupBtn('BandCode', 'txband', '?')] },
        { className: 'by', nodes: [mkInput('rxband', rec, ro('rxband'), 'im', 8, 4), mkLookupBtn('BandCode', 'rxband', '?')] },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'm', label: 'Antenna Code' },
        { className: 'by', nodes: [
          mkInput('acodetx', rec, ro('acodetx'), 'im', 14, 12),
          mkFindAnteBtn('acodetx'),
          mkLookupBtn('AnteCode', 'acodetx', '??')
        ] },
        { className: 'by', nodes: [
          mkInput('acoderx', rec, ro('acoderx'), 'im', 14, 12),
          mkFindAnteBtn('acoderx'),
          mkLookupBtn('AnteCode', 'acoderx', '??')
        ] },
        { className: 'by', label: '' }
      ]);
      var glanceTx = document.createElement('span');
      glanceTx.id = 'ante-sdf-glance-tx';
      glanceTx.className = 'classic-hint';
      glanceTx.textContent = 'Find… TX code';
      var glanceRx = document.createElement('span');
      glanceRx.id = 'ante-sdf-glance-rx';
      glanceRx.className = 'classic-hint';
      glanceRx.textContent = 'Find… RX code';
      addRow(table, [
        { className: 'tdro', label: 'SDF Antenna' },
        { className: 'by', el: glanceTx },
        { className: 'by', el: glanceRx },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'tdro', label: 'Maximum Antenna Gain' },
        { className: 'by', el: mkInput('txhgmax', rec, true, 'iro', 8, 6) },
        { className: 'by', el: mkInput('rxhgmax', rec, true, 'iro', 8, 6) },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'm', label: 'Precipitation Scatter Distance' },
        { className: 'by', el: mkInput('txpre', rec, ro('txpre'), 'im', 10, 7) },
        { className: 'by', el: mkInput('rxpre', rec, ro('rxpre'), 'im', 10, 7) },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'm', label: 'Tropospheric Scatter Distance' },
        { className: 'by', el: mkInput('txtro', rec, ro('txtro'), 'im', 10, 7) },
        { className: 'by', el: mkInput('rxtro', rec, ro('rxtro'), 'im', 10, 7) },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'm', label: 'Status' },
        { className: 'by', nodes: [mkInput('stata', rec, ro('stata'), 'im', 4, 1), mkLookupBtn('SiteStatus', 'stata', '?')], colspan: 3 }
      ]);
      addRow(table, [
        { className: 'tdro', label: 'Modify Date' },
        { className: 'by', nodes: [
          mkInput('mDay', rec, true, 'iro', 2, 2),
          mkInput('mMonth', rec, true, 'iro', 4, 3),
          mkInput('mYear', rec, true, 'iro', 6, 4)
        ], colspan: 3 }
      ]);
    },
    CHAN_TS: function (table, rec, roKeys) {
      roKeys = roKeys || [];
      function ro(k) { return roKeys.indexOf(k) >= 0; }
      table.className += ' classic-chan-form';
      addRow(table, [
        { className: 'rok', label: 'Local' },
        { className: 'by', nodes: [
          mkInput('call1', rec, ro('call1'), ro('call1') ? 'irok' : 'im', 10, 9),
          mkDisplay('chan-local-name', 22),
          mkDisplay('chan-local-prov', 3),
          mkDisplay('chan-local-oper', 8)
        ], colspan: 3 }
      ]);
      addRow(table, [
        { className: 'rok', label: 'Remote' },
        { className: 'by', nodes: [
          mkInput('call2', rec, ro('call2'), ro('call2') ? 'irok' : 'im', 10, 9),
          mkDisplay('chan-remote-name', 22),
          mkDisplay('chan-remote-prov', 3),
          mkDisplay('chan-remote-oper', 8)
        ], colspan: 3 }
      ]);
      addRow(table, [
        { className: 'm', label: 'MDB Operation' },
        { className: 'by', nodes: [mkInput('cmd', rec, ro('cmd')), mkLookupBtn('MdbOperation', 'cmd', '?')] },
        { className: 'rok', label: 'Band Code' },
        { className: 'by', nodes: [
          mkInput('bndcde', rec, ro('bndcde'), ro('bndcde') ? 'irok' : 'im', 6, 4),
          mkLookupBtn('BandCode', 'bndcde', '?')
        ] }
      ]);
      addRow(table, [
        { className: 'rok', label: 'Channel ID' },
        { className: 'by', el: mkInput('chid', rec, ro('chid'), ro('chid') ? 'irok' : 'im', 8, 4) },
        { className: 'o', label: 'Frequency Plan' },
        { className: 'by', nodes: [mkInput('splan', rec, ro('splan'), 'im', 8, 4), mkLookupBtn('Plan', 'splan', '?', 'bndcde')] }
      ]);
      addRow(table, [
        { className: 'o', label: 'Polarization (VH)' },
        { className: 'by', nodes: [mkInput('vh', rec, ro('vh'), 'im', 4, 2), mkLookupBtn('Polarization', 'vh', '?')] },
        { className: 'o', label: 'HiLo' },
        { className: 'by', nodes: [mkInput('hl', rec, ro('hl'), 'im', 6, 2), mkLookupBtn('HiLo', 'hl', '?')] }
      ]);
      addRow(table, [
        { className: 'o', label: 'Cumul. Interfer. ES' },
        { className: 'by', el: mkInput('esint', rec, ro('esint'), 'im', 8, 6) },
        { className: 'o', label: 'Cumul. Interfer. TS' },
        { className: 'by', el: mkInput('tsint', rec, ro('tsint'), 'im', 8, 6) }
      ]);
      addRow(table, [
        { className: 'b', label: '' },
        { className: 'b', label: 'TRANSMIT' },
        { className: 'b', label: '' },
        { className: 'b', label: 'RECEIVE' }
      ]);
      addRow(table, [
        { className: 'm', label: 'Frequency' },
        { className: 'by', el: mkInput('freqtx', rec, ro('freqtx'), 'im', 14, 11) },
        { className: 'tdro', label: 'Frequency' },
        { className: 'by', el: mkInput('freqrx', rec, true, 'iro', 14, 11) }
      ]);
      addRow(table, [
        { className: 'm', label: 'Polarization' },
        { className: 'by', nodes: [mkInput('poltx', rec, ro('poltx'), 'im', 4, 1), mkLookupBtn('PolCode', 'poltx', '?')] },
        { className: 'tdro', label: 'Polarization' },
        { className: 'by', el: mkInput('polrx', rec, true, 'iro', 4, 1) }
      ]);
      addRow(table, [
        { className: 'm', label: 'Antenna No Main/Stx' },
        { className: 'by', nodes: [
          mkInput('antnumbtx1', rec, ro('antnumbtx1'), 'im', 4, 2),
          mkText(' / '),
          mkInput('antnumbtx2', rec, ro('antnumbtx2'), 'im', 4, 2)
        ] },
        { className: 'm', label: 'Antenna No Main/Dv1/Dv2' },
        { className: 'by', nodes: [
          mkInput('antnumbrx1', rec, ro('antnumbrx1'), 'im', 4, 2),
          mkText(' / '),
          mkInput('antnumbrx2', rec, ro('antnumbrx2'), 'im', 4, 2),
          mkText(' / '),
          mkInput('antnumbrx3', rec, ro('antnumbrx3'), 'im', 4, 2)
        ] }
      ]);
      addRow(table, [
        { className: 'm', label: 'Antenna FSL Main/Stx' },
        { className: 'by', nodes: [
          mkInput('afsltx1', rec, ro('afsltx1'), 'im', 6, 4),
          mkText(' / '),
          mkInput('afsltx2', rec, ro('afsltx2'), 'im', 6, 4)
        ] },
        { className: 'm', label: 'Antenna FSL Main/Dv1/Dv2' },
        { className: 'by', nodes: [
          mkInput('afslrx1', rec, ro('afslrx1'), 'im', 6, 4),
          mkText(' / '),
          mkInput('afslrx2', rec, ro('afslrx2'), 'im', 6, 4),
          mkText(' / '),
          mkInput('afslrx3', rec, ro('afslrx3'), 'im', 6, 4)
        ] }
      ]);
      addRow(table, [
        { className: 'm', label: 'Coord. Power / ATPC' },
        { className: 'by', nodes: [
          mkInput('pwrtx', rec, ro('pwrtx'), 'im', 8, 6),
          mkText(' / '),
          mkInput('atpccde', rec, ro('atpccde'), 'im', 6, 4)
        ] },
        { className: 'tdro', label: 'Rx Power Main/Dv1/Dv2' },
        { className: 'by', nodes: [
          mkInput('pwrrx1', rec, true, 'iro', 6, 6),
          mkText(' / '),
          mkInput('pwrrx2', rec, true, 'iro', 6, 6),
          mkText(' / '),
          mkInput('pwrrx3', rec, true, 'iro', 6, 6)
        ] }
      ]);
      addRow(table, [
        { className: 'm', label: 'Eqpt / Use / Fee' },
        { className: 'by', nodes: [
          mkInput('eqpttx', rec, ro('eqpttx'), 'im', 10, 8),
          mkLookupBtn('EqptTraf', 'eqpttx', '??', 'traftx', true),
          mkInput('eqptutx', rec, ro('eqptutx'), 'im', 3, 1),
          mkLookupBtn('EqptUseTx', 'eqptutx', '?'),
          mkInput('feetx', rec, ro('feetx'), 'im', 4, 2),
          mkLookupBtn('FeeCode', 'feetx', '?')
        ] },
        { className: 'm', label: 'Eqpt / Use / Fee' },
        { className: 'by', nodes: [
          mkInput('eqptrx', rec, ro('eqptrx'), 'im', 10, 8),
          mkLookupBtn('EqptTraf', 'eqptrx', '??', 'trafrx', true),
          mkInput('eqpturx', rec, ro('eqpturx'), 'im', 3, 1),
          mkLookupBtn('EqptUseRx', 'eqpturx', '?'),
          mkInput('feerx', rec, ro('feerx'), 'im', 4, 2),
          mkLookupBtn('FeeCode', 'feerx', '?')
        ] }
      ]);
      addRow(table, [
        { className: 'm', label: 'Traffic / Status' },
        { className: 'by', nodes: [
          mkInput('traftx', rec, ro('traftx'), 'im', 8, 6),
          mkLookupBtn('TrafficCode', 'traftx', '?'),
          mkInput('stattx', rec, ro('stattx'), 'im', 3, 1),
          mkLookupBtn('SiteStatus', 'stattx', '?')
        ] },
        { className: 'm', label: 'Traffic / Status' },
        { className: 'by', nodes: [
          mkInput('trafrx', rec, ro('trafrx'), 'im', 8, 6),
          mkLookupBtn('TrafficCode', 'trafrx', '?'),
          mkInput('statrx', rec, true, 'iro', 3, 1)
        ] }
      ]);
      addRow(table, [
        { className: 'tdro', label: 'Authorization' },
        { className: 'by', el: mkInput('tx_Authorization', rec, true, 'iro', 14, 16) },
        { className: 'tdro', label: 'Authorization' },
        { className: 'by', el: mkInput('rx_Authorization', rec, true, 'iro', 14, 16) }
      ]);
      addRow(table, [
        { className: 'o', label: 'Service / Notes' },
        { className: 'by', nodes: [
          mkInput('srvctx', rec, ro('srvctx'), 'im', 8, 6),
          mkInput('notetx', rec, ro('notetx'), 'im', 6, 4),
          mkLookupBtn('NotesOper', 'notetx', '?', 'chan-local-oper')
        ] },
        { className: 'o', label: 'Service / Notes' },
        { className: 'by', nodes: [
          mkInput('srvcrx', rec, true, 'iro', 8, 6),
          mkInput('noterx', rec, ro('noterx'), 'im', 6, 4),
          mkLookupBtn('NotesOper', 'noterx', '?', 'chan-remote-oper')
        ] }
      ]);
      addRow(table, [
        { className: 'o', label: 'Hop Number' },
        { className: 'by', el: mkInput('hopnumb', rec, ro('hopnumb'), 'im', 4, 2) },
        { className: 'o', label: 'Route Code' },
        { className: 'by', nodes: [mkInput('routnumb', rec, ro('routnumb'), 'im', 10, 8), mkLookupBtn('RoutOper', 'routnumb', '?', 'chan-local-oper')] }
      ]);
      addRow(table, [
        { className: 'o', label: 'Station Number' },
        { className: 'by', el: mkInput('stnnumb', rec, ro('stnnumb'), 'im', 4, 2) },
        { className: 'o', label: 'Notes General' },
        { className: 'by', nodes: [mkInput('notegnl', rec, ro('notegnl'), 'im', 8, 4), mkLookupBtn('NotesOper', 'notegnl', '?', 'chan-local-oper')] }
      ]);
      addRow(table, [
        { className: 'o', label: 'Pointer' },
        { className: 'by', el: mkInput('cpoint', rec, ro('cpoint'), 'im', 8, 4) },
        { className: 'tdro', label: 'Modify Date' },
        { className: 'by', nodes: [
          mkInput('mDay', rec, true, 'iro', 2, 2),
          mkText('-'),
          mkInput('mMonth', rec, true, 'iro', 4, 3),
          mkText('-'),
          mkInput('mYear', rec, true, 'iro', 6, 4)
        ] }
      ]);
      addRow(table, [
        { className: 'o', label: 'Service Date' },
        { className: 'by', nodes: [
          mkInput('sDay', rec, ro('sDay'), 'im', 2, 2),
          mkText('-'),
          mkInput('sMonth', rec, ro('sMonth'), 'im', 4, 3),
          mkText('-'),
          mkInput('sYear', rec, ro('sYear'), 'im', 6, 4)
        ] },
        { className: 'o', label: '' },
        { className: 'by', label: '' }
      ]);
    },
    CHAN_ES: function (table, rec, roKeys) {
      roKeys = roKeys || [];
      function ro(k) { return roKeys.indexOf(k) >= 0; }
      table.className += ' classic-chan-form';
      addRow(table, [
        { className: 'rok', label: 'Site' },
        { className: 'by', nodes: [
          mkDisplay('es-glance-location', 12),
          mkDisplay('es-glance-name', 18),
          mkDisplay('es-glance-prov', 3),
          mkDisplay('es-glance-oper', 8)
        ], colspan: 3 }
      ]);
      addRow(table, [
        { className: 'rok', label: 'Antenna' },
        { className: 'by', nodes: [
          mkDisplay('es-ante-call1', 12),
          mkDisplay('es-ante-txband', 6),
          mkDisplay('es-ante-rxband', 6),
          mkDisplay('es-ante-acodetx', 14),
          mkDisplay('es-ante-acoderx', 14)
        ], colspan: 3 }
      ]);
      addRow(table, [
        { className: 'tdro', label: 'MDB Operation' },
        { className: 'by', el: mkInput('cmd', rec, true, 'iro', 4, 1) },
        { className: 'm', label: '' },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'rok', label: 'Location Code' },
        { className: 'by', el: mkInput('location', rec, ro('location'), ro('location') ? 'irok' : 'ik', 14, 10) },
        { className: 'rok', label: 'Call Sign' },
        { className: 'by', el: mkInput('call1', rec, ro('call1'), ro('call1') ? 'irok' : 'ik', 12, 9) }
      ]);
      addRow(table, [
        { className: 'rok', label: 'Channel Id' },
        { className: 'by', el: mkInput('chid', rec, ro('chid'), ro('chid') ? 'irok' : 'ik', 8, 4) },
        { className: 'm', label: '' },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'm', label: 'LT Interference Obj.' },
        { className: 'by', el: mkInput('i20', rec, ro('i20'), 'im', 8, 6) },
        { className: 'm', label: 'ST Prec. Interference Obj.' },
        { className: 'by', el: mkInput('ip01', rec, ro('ip01'), 'im', 8, 6) }
      ]);
      addRow(table, [
        { className: 'm', label: 'Maximum Transmit Power' },
        { className: 'by', el: mkInput('maxtxpower', rec, ro('maxtxpower'), 'im', 8, 6) },
        { className: 'm', label: 'ST Trop. Interference Obj.' },
        { className: 'by', el: mkInput('it01', rec, ro('it01'), 'im', 8, 6) }
      ]);
      addRow(table, [
        { className: 'm', label: 'Energy Dispersal' },
        { className: 'by', el: mkInput('p4khz', rec, ro('p4khz'), 'im', 6, 4) },
        { className: 'o', label: 'Notes' },
        { className: 'by', nodes: [mkInput('notc', rec, ro('notc'), 'im', 8, 4), mkLookupBtn('NotesLocation', 'notc', '?', 'location')] }
      ]);
      addRow(table, [
        { className: 'by', label: '' },
        { className: 'b', label: 'TRANSMIT' },
        { className: 'b', label: 'RECEIVE' },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'm', label: 'Frequency' },
        { className: 'by', el: mkInput('freqtx', rec, ro('freqtx'), 'im', 14, 11) },
        { className: 'by', el: mkInput('freqrx', rec, ro('freqrx'), 'im', 14, 11) },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'm', label: 'Polarization' },
        { className: 'by', nodes: [mkInput('poltx', rec, ro('poltx'), 'im', 3, 1), mkLookupBtn('PolCode', 'poltx', '?')] },
        { className: 'by', nodes: [mkInput('polrx', rec, ro('polrx'), 'im', 3, 1), mkLookupBtn('PolCode', 'polrx', '?')] },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'm', label: 'Equipment' },
        { className: 'by', nodes: [mkInput('eqpttx', rec, ro('eqpttx'), 'im', 10, 8), mkLookupBtn('EqptTraf', 'eqpttx', '??', 'traftx', true)] },
        { className: 'by', nodes: [mkInput('eqptrx', rec, ro('eqptrx'), 'im', 10, 8), mkLookupBtn('EqptTraf', 'eqptrx', '??', 'trafrx', true)] },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'm', label: 'Default/Normal Power' },
        { className: 'by', el: mkInput('pwrtx', rec, ro('pwrtx'), 'im', 8, 6) },
        { className: 'by', el: mkInput('pwrrx', rec, ro('pwrrx'), 'im', 8, 7) },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'm', label: 'Traffic Code' },
        { className: 'by', nodes: [mkInput('traftx', rec, ro('traftx'), 'im', 8, 6), mkLookupBtn('TrafficCode', 'traftx', '?')] },
        { className: 'by', nodes: [mkInput('trafrx', rec, ro('trafrx'), 'im', 8, 6), mkLookupBtn('TrafficCode', 'trafrx', '?')] },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'm', label: 'Status' },
        { className: 'by', nodes: [mkInput('stattx', rec, ro('stattx'), 'im', 3, 1), mkLookupBtn('SiteStatus', 'stattx', '?')] },
        { className: 'by', nodes: [mkInput('statrx', rec, ro('statrx'), 'im', 3, 1), mkLookupBtn('SiteStatus', 'statrx', '?')] },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'm', label: 'Fee Code' },
        { className: 'by', nodes: [mkInput('feetx', rec, ro('feetx'), 'im', 4, 2), mkLookupBtn('FeeCode', 'feetx', '?')] },
        { className: 'by', nodes: [mkInput('feerx', rec, ro('feerx'), 'im', 4, 2), mkLookupBtn('FeeCode', 'feerx', '?')] },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'o', label: 'Service Code' },
        { className: 'by', el: mkInput('srvctx', rec, ro('srvctx'), 'im', 8, 6) },
        { className: 'by', el: mkInput('srvcrx', rec, ro('srvcrx'), 'im', 8, 6) },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'tdro', label: 'Modify Date' },
        { className: 'by', nodes: [
          mkInput('mDay', rec, true, 'iro', 2, 2),
          mkInput('mMonth', rec, true, 'iro', 4, 3),
          mkInput('mYear', rec, true, 'iro', 6, 4)
        ], colspan: 3 }
      ]);
    },
    AZIM_ES: function (table, rec, roKeys) {
      roKeys = roKeys || [];
      function ro(k) { return roKeys.indexOf(k) >= 0; }
      addRow(table, [
        { className: 'tdro', label: 'Cmd' },
        { className: 'by', el: mkInput('cmd', rec, true, 'iro', 4, 1) },
        { className: 'm', label: '' },
        { className: 'by', label: '' }
      ]);
      addRow(table, [
        { className: 'rok', label: 'Location' },
        { className: 'by', el: mkInput('location', rec, ro('location'), ro('location') ? 'irok' : 'im', 14, 10) },
        { className: 'rok', label: 'Call Sign' },
        { className: 'by', el: mkInput('call1', rec, ro('call1'), ro('call1') ? 'irok' : 'im', 12, 9) }
      ]);
      addRow(table, [
        { className: 'rok', label: 'Azimuth' },
        { className: 'by', el: mkInput('azim', rec, ro('azim'), ro('azim') ? 'irok' : 'ik', 10, 8) },
        { className: 'm', label: 'Elevation' },
        { className: 'by', el: mkInput('elev', rec, ro('elev'), 'im', 10, 8) }
      ]);
      addRow(table, [
        { className: 'm', label: 'Distance' },
        { className: 'by', el: mkInput('dist', rec, ro('dist'), 'im', 10, 8) },
        { className: 'o', label: 'Loss' },
        { className: 'by', el: mkInput('loss', rec, ro('loss'), 'im', 10, 8) }
      ]);
      addRow(table, [
        { className: 'tdro', label: 'Modify Date' },
        { className: 'by', nodes: [
          mkInput('mDay', rec, true, 'iro', 2, 2),
          mkInput('mMonth', rec, true, 'iro', 4, 3),
          mkInput('mYear', rec, true, 'iro', 6, 4)
        ], colspan: 3 }
      ]);
    }
  };

  function setGlance(row, elId) {
    var el = document.getElementById(elId || 'ante-sdf-glance');
    if (!el) return;
    if (!row) {
      el.textContent = 'No SDF match for this code.';
      return;
    }
    var bits = [];
    if (row.amodel) bits.push(row.amodel);
    if (row.amanu) bits.push(row.amanu);
    if (row.adesc) bits.push(row.adesc);
    if (row.again) bits.push('gain ' + row.again);
    if (row.source) bits.push('(' + row.source + ')');
    el.textContent = bits.length ? bits.join(' · ') : (row.acode || '');
  }

  function glanceIdForField(fieldKey) {
    if (fieldKey === 'acodetx') return 'ante-sdf-glance-tx';
    if (fieldKey === 'acoderx') return 'ante-sdf-glance-rx';
    return 'ante-sdf-glance';
  }

  function gainFieldForCode(fieldKey) {
    if (fieldKey === 'acodetx') return 'txhgmax';
    if (fieldKey === 'acoderx') return 'rxhgmax';
    return '';
  }

  function setGainField(gainField, value) {
    if (!gainField || value == null || value === '') return;
    var g = document.getElementById('fld-' + gainField);
    if (g) g.value = value;
  }

  function refreshAnteGlance(acode, elId, gainField, overwriteGain) {
    acode = (acode || '').trim();
    var el = document.getElementById(elId || 'ante-sdf-glance');
    if (!el) return;
    if (!acode) {
      el.textContent = 'Use Find… to search manufacturer / model / description.';
      return;
    }
    if (!global.RemIcsApi || !RemIcsApi.anteLookup) return;
    RemIcsApi.anteLookup('', acode).then(function (r) {
      if (!r.ok || !r.rows || !r.rows.length) {
        setGlance(null, elId);
        return;
      }
      setGlance(r.rows[0], elId);
      if (overwriteGain) setGainField(gainField, r.rows[0].again);
    }).catch(function () { setGlance(null, elId); });
  }

  function applyAnteLocks(rec) {
    rec = rec || {};
    var call1 = '';
    var c1 = document.getElementById('fld-call1');
    if (c1) call1 = String(c1.value || rec.call1 || '');
    else call1 = String(rec.call1 || '');
    if (call1.charAt(0) === '%') {
      ['offazm', 'tazmth', 'telvtn', 'tgain'].forEach(function (k) {
        var el = document.getElementById('fld-' + k);
        if (!el) return;
        if (k === 'offazm') el.value = 'P';
        el.readOnly = true;
        el.tabIndex = -1;
        el.className = 'iro';
      });
    }
    var ac = document.getElementById('fld-acode');
    if (ac && !ac._glanceWired) {
      ac._glanceWired = true;
      ac.addEventListener('change', function () { refreshAnteGlance(ac.value); });
      ac.addEventListener('blur', function () { refreshAnteGlance(ac.value); });
    }
    refreshAnteGlance((ac && ac.value) || rec.acode || '');
  }

  function applyEsAnteCodes(rec) {
    rec = rec || {};
    function wire(key) {
      var el = document.getElementById('fld-' + key);
      var glanceId = glanceIdForField(key);
      var gainField = gainFieldForCode(key);
      if (el && !el._glanceWired) {
        el._glanceWired = true;
        el.addEventListener('change', function () { refreshAnteGlance(el.value, glanceId, gainField, true); });
        el.addEventListener('blur', function () { refreshAnteGlance(el.value, glanceId, gainField, true); });
      }
      refreshAnteGlance((el && el.value) || rec[key] || '', glanceId, gainField, false);
    }
    wire('acodetx');
    wire('acoderx');
  }

  function ensureFinder() {
    var wrap = document.getElementById('ante-finder');
    if (wrap) return wrap;
    wrap = document.createElement('div');
    wrap.id = 'ante-finder';
    wrap.className = 'remics-ante-finder';
    wrap.hidden = true;
    wrap.innerHTML =
      '<div class="remics-ante-finder-box" role="dialog" aria-labelledby="ante-finder-title">' +
      '<h3 id="ante-finder-title">Find antenna</h3>' +
      '<p class="classic-hint">Search manufacturer, model, description, or code. Searches your SDF antenna files and main.sd_ante.</p>' +
      '<p><input id="ante-finder-q" class="im" size="36" placeholder="e.g. Andrew, HP8, parabolic">' +
      ' <button type="button" class="bt" id="ante-finder-go">Search</button>' +
      ' <button type="button" class="bt" id="ante-finder-close">Cancel</button></p>' +
      '<div id="ante-finder-status" class="classic-status"></div>' +
      '<div class="remics-ante-finder-scroll"><table class="classic-form classic-form-wide" id="ante-finder-table">' +
      '<thead><tr><th>Model</th><th>Manufact</th><th>Description</th><th>Gain</th><th>Code</th><th>Source</th></tr></thead>' +
      '<tbody></tbody></table></div></div>';
    document.body.appendChild(wrap);
    return wrap;
  }

  var finderFieldKey = 'acode';

  function pickAnteRow(row) {
    var el = document.getElementById('fld-' + finderFieldKey);
    if (el) {
      el.value = row.acode || '';
      try {
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      } catch (e) { /* ignore */ }
    }
    setGlance(row, glanceIdForField(finderFieldKey));
    setGainField(gainFieldForCode(finderFieldKey), row.again);
    var wrap = document.getElementById('ante-finder');
    if (wrap) wrap.hidden = true;
  }

  function runAnteSearch() {
    var qEl = document.getElementById('ante-finder-q');
    var st = document.getElementById('ante-finder-status');
    var tbody = document.querySelector('#ante-finder-table tbody');
    if (!tbody || !global.RemIcsApi || !RemIcsApi.anteLookup) return;
    var q = qEl ? qEl.value.trim() : '';
    if (st) st.textContent = 'Searching…';
    tbody.innerHTML = '';
    RemIcsApi.anteLookup(q, '').then(function (r) {
      if (!r.ok) {
        if (st) st.textContent = r.error || 'Search failed';
        return;
      }
      var rows = r.rows || [];
      if (st) st.textContent = rows.length ? (rows.length + ' match(es). Click a row to select.') : 'No matches.';
      rows.forEach(function (row) {
        var tr = document.createElement('tr');
        [row.amodel, row.amanu, row.adesc, row.again, row.acode, row.source].forEach(function (v) {
          var td = document.createElement('td');
          td.textContent = v || '';
          tr.appendChild(td);
        });
        tr.addEventListener('click', function () { pickAnteRow(row); });
        tbody.appendChild(tr);
      });
    }).catch(function (ex) {
      if (st) st.textContent = ex.message || String(ex);
    });
  }

  function openAnteFinder(fieldKey) {
    finderFieldKey = fieldKey || 'acode';
    var wrap = ensureFinder();
    wrap.hidden = false;
    var qEl = document.getElementById('ante-finder-q');
    var ac = document.getElementById('fld-' + finderFieldKey);
    if (qEl) {
      qEl.value = ac ? (ac.value || '') : '';
      qEl.focus();
      qEl.select();
    }
    var go = document.getElementById('ante-finder-go');
    var close = document.getElementById('ante-finder-close');
    if (go) go.onclick = runAnteSearch;
    if (close) close.onclick = function () { wrap.hidden = true; };
    if (qEl && !qEl._enterWired) {
      qEl._enterWired = true;
      qEl.addEventListener('keydown', function (ev) {
        if (ev.key === 'Enter') {
          ev.preventDefault();
          runAnteSearch();
        }
      });
    }
    wrap.onclick = function (ev) {
      if (ev.target === wrap) wrap.hidden = true;
    };
    runAnteSearch();
  }

  function render(tableId, schemaName, rec, roKeys) {
    var table = document.getElementById(tableId);
    if (!table) return;
    table.innerHTML = '';
    table.className = 'classic-form classic-form-wide';
    var fn = SCHEMAS[schemaName];
    if (fn) fn(table, rec || {}, roKeys || []);
    if (schemaName === 'ANTE_TS') applyAnteLocks(rec || {});
    if (schemaName === 'ANTE_ES') applyEsAnteCodes(rec || {});
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

  global.RemicsPdfFields = {
    render: render,
    collect: collect,
    openLookup: openLookup,
    openAnteFinder: openAnteFinder,
    applyAnteLocks: applyAnteLocks,
    applyEsAnteCodes: applyEsAnteCodes,
    refreshAnteGlance: refreshAnteGlance
  };
})(window);
