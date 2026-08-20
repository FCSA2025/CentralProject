// RemIcsReWrite  -  optional extra help for new users (classic table/hint style).
(function (global) {
  var CACHE = 'remics-extra-help';
  var loaded = false;
  var on = true;
  var syncBound = false;

  var HINTS = {
    title: {
      namef: "This file's name in MICS (1-16 letters, digits, underscore).",
      source: 'Operator / company code that owns this file. Use ?? to look it up.',
      descr: 'Your notes for this file. Not sent as licence data.',
      validated: 'Y after a clean Validate. N if the file has not passed or was edited since.'
    },
    site: {
      cmd: 'SDB action for this record. Must be A, B, D, N, or U. Use ? for the code list.',
      call1: 'Licensed call sign of this site. This is the site ID in the tree.',
      location: 'Earth-station location code. This is the site ID in the ES tree.',
      name: 'Common name or place-name for the site.',
      prov: 'Province or state (2 letters). Use ? to look it up.',
      oper: 'Operator code for the licensee. Use ?? to look it up.',
      latDD: 'Site latitude in WGS84 (degrees, minutes, seconds, hemisphere).',
      latMM: 'Site latitude minutes (WGS84).',
      latSS: 'Site latitude seconds (WGS84).',
      latDir: 'N or S.',
      longDD: 'Site longitude in WGS84 (degrees, minutes, seconds, hemisphere).',
      longMM: 'Site longitude minutes (WGS84).',
      longSS: 'Site longitude seconds (WGS84).',
      longDir: 'E or W.',
      grnd: 'Ground elevation at the site, in metres above sea level.',
      stats: 'Site status code (proposed, licensed, etc.). Use ? for codes.',
      notwr: 'How many towers are at this site.',
      icaccount: 'ISED / IC account number, if you have one.',
      reg: 'Registration or file reference used by your company.',
      loc: 'Optional location text or code.',
      nots: "Note number from the operator's SDF notes. Use ? after Operator is filled.",
      snumb: 'Your internal site number.',
      spoint: 'Pointer to a related record, if used.',
      radio: 'Radio climate code used in ES path calculations.',
      rain: 'Rain region code used in ES path calculations.',
      sDay: 'Service / in-service date (day-month-year). Leave blank if not yet in service.'
    },
    ante: {
      cmd: 'SDB action for this antenna record. Must be A, B, D, N, or U.',
      call1: 'Local site call sign. Must match a site already in this file.',
      call2: 'Far-end (remote) site call sign for this hop.',
      location: 'Earth-station location code this antenna belongs to.',
      anum: 'Antenna number at the local site (1, 2, ...).',
      bndcde: 'Frequency band code (for example 6G, 11G). Use ? to look it up.',
      atwrno: 'Which tower this antenna is on. Use ? after the local call sign is filled.',
      acode: 'Antenna model code from your SDF (or main). Use Find... if you do not know the code.',
      acodetx: 'Transmit antenna model code. Use Find... to search by manufacturer or model.',
      acoderx: 'Receive antenna model code. Use Find... to search by manufacturer or model.',
      ause: 'How the antenna is used (TX, RX, both). Use ? for codes.',
      aht: 'Centre-line height of the antenna above ground, in metres.',
      azmth: 'Calculated azimuth toward the far end. Filled after both sites exist.',
      elvtn: 'Calculated elevation angle toward the far end.',
      dist: 'Path distance. Calculated from the two site coordinates.',
      az: 'Calculated azimuth toward the satellite.',
      el: 'Calculated elevation angle toward the satellite.',
      offazm: 'Offset from the calculated azimuth, if the dish is not aimed exactly on path.',
      tazmth: 'Surveyed / true azimuth, if different from the calculated value.',
      telvtn: 'Surveyed / true elevation, if different from the calculated value.',
      tgain: 'True (installed) antenna gain, if you override the SDF value.',
      kvalue: 'Effective-earth-radius factor used on this hop.',
      obsloss: 'Extra obstruction loss on the path, in dB.',
      nota: 'Antenna note number. Use ? after the site key is filled.',
      licence: 'Licence or authorization number for this antenna.',
      txband: 'Transmit frequency band code.',
      rxband: 'Receive frequency band code.',
      op2: 'Satellite operator code. Use ? to look it up.',
      orbit: 'Orbit type code. Use ? for codes.',
      satname: 'Satellite name as you want it shown.',
      satlong: 'Satellite orbital longitude (degrees).',
      satlongs: 'E or W for satellite longitude.',
      txcompl: 'Transmit-side component loss (filters, etc.), in dB.',
      rxcompl: 'Receive-side component loss, in dB.'
    },
    chan: {
      cmd: 'SDB action for this channel. Must be A, B, D, N, or U. Use ? for the code list.',
      call1: 'Local site call sign. Must match a site already in this file.',
      call2: 'Far-end (remote) site call sign for this hop.',
      location: 'Earth-station location code this channel belongs to.',
      bndcde: 'Frequency band code for this hop. Use ? to look it up.',
      chid: 'Channel ID on this hop or antenna (unique in the file).',
      splan: 'Frequency / spectrum plan code. Use ? after Band is filled.',
      vh: 'Vertical / horizontal polarization pair. Use ? for codes.',
      hl: 'High or low side of the band pair. Use ? for codes. Receive frequency is calculated from this.',
      esint: 'Cumulative earth-station interference, if you have a value.',
      tsint: 'Cumulative terrestrial interference, if you have a value.',
      freqtx: 'Transmit frequency in MHz. Receive frequency is calculated on TS when HiLo is set.',
      freqrx: 'Receive frequency in MHz. On TS this is calculated from transmit frequency and HiLo.',
      poltx: 'Transmit polarization code. Use ? for the list.',
      polrx: 'Receive polarization. On TS this is filled from the transmit polarity.',
      antnumbtx1: 'Main transmit antenna number at the local site (must exist on this hop).',
      antnumbtx2: 'Standby transmit antenna number, if used.',
      antnumbrx1: 'Main receive antenna number at the local site.',
      antnumbrx2: 'First diversity receive antenna number, if used.',
      antnumbrx3: 'Second diversity receive antenna number, if used.',
      afsltx1: 'Free-space loss to the main transmit antenna, in dB.',
      afsltx2: 'Free-space loss to the standby transmit antenna, in dB.',
      afslrx1: 'Free-space loss to the main receive antenna, in dB.',
      afslrx2: 'Free-space loss to the first diversity receive antenna, in dB.',
      afslrx3: 'Free-space loss to the second diversity receive antenna, in dB.',
      pwrtx: 'Coordinated / default transmit power, in dBW.',
      atpccde: 'ATPC (automatic transmit power control) code, if used.',
      pwrrx: 'Receive power, in dBW.',
      pwrrx1: 'Calculated receive power on the main antenna.',
      pwrrx2: 'Calculated receive power on diversity 1.',
      pwrrx3: 'Calculated receive power on diversity 2.',
      eqpttx: 'Transmit equipment code from your SDF (or main). Use ?? to search.',
      eqptrx: 'Receive equipment code from your SDF (or main). Use ?? to search.',
      eqptutx: 'How the transmit equipment is used. Use ? for codes.',
      eqpturx: 'How the receive equipment is used. Use ? for codes.',
      feetx: 'Transmit licence-fee code. Use ? for the list.',
      feerx: 'Receive licence-fee code. Use ? for the list.',
      traftx: 'Transmit traffic / capacity code. Use ? for the list.',
      trafrx: 'Receive traffic / capacity code. Use ? for the list.',
      stattx: 'Transmit channel status (proposed, licensed, etc.). Use ? for codes.',
      statrx: 'Receive channel status. On TS this often follows the transmit status.',
      hopnumb: 'Your hop number on the route, if you use one.',
      routnumb: 'Route code from your SDF Routes file. Use ? after Operator is known.',
      stnnumb: 'Your station number on the route, if you use one.',
      notetx: 'Transmit note number. Use ? after the local operator is filled.',
      noterx: 'Receive note number. Use ? after the remote operator is filled.',
      notegnl: 'General note number for this channel.',
      notc: 'Note number for this ES channel. Use ? after Location is filled.',
      srvctx: 'Transmit service code, if used.',
      srvcrx: 'Receive service code, if used.',
      cpoint: 'Pointer to a related record, if used.',
      maxtxpower: 'Maximum transmit power for this ES channel, in dBW.',
      p4khz: 'Energy dispersal / power in 4 kHz, if required.',
      i20: 'Long-term interference objective.',
      ip01: 'Short-term precipitation interference objective.',
      it01: 'Short-term tropospheric interference objective.'
    },
    azim: {
      cmd: 'SDB action for this azimuth record. Filled when you save (usually A).',
      location: 'Earth-station location code this azimuth belongs to.',
      call1: 'Call sign at this location. Must match a site already in this file.',
      azim: 'Azimuth toward the far point, in degrees (0-360).',
      elev: 'Elevation angle toward the far point, in degrees.',
      dist: 'Path distance to the far point.',
      loss: 'Optional extra path loss, in dB.',
      mDay: 'Last modify date (day). Filled when you save.',
      mMonth: 'Last modify date (month). Filled when you save.',
      mYear: 'Last modify date (year). Filled when you save.'
    },
    chng: {
      old: 'Current licensed call sign. This is the key of the change record.',
      new: 'Replacement call sign. After the change, sites and hops in this file should use this sign.',
      name: 'Station / site name for this change (optional).'
    },
    cloc: {
      old: 'Current location code. This is the key of the change record.',
      new: 'Replacement location code for this earth station.',
      name: 'Station / site name for this change (optional).'
    },
    ccal: {
      old: 'Current licensed call sign at this earth station.',
      new: 'Replacement call sign.'
    },
    pwdqa: {
      fixedQ: 'Pick one of the three standard questions. Forgot password will show this text.',
      fixedA: 'Your answer to the standard question. It is stored as a one-way hash; you must re-enter it if you change setup.',
      userQ: 'A question only you would know. Forgot password will show this text.',
      userA: 'Your answer to your own question. Both answers are required to reset a forgotten password.'
    },
    links: {
      local: 'Local site call sign. Must already exist in this file.',
      remote: 'Far-end site call sign. Add that Site first if it is not in the file yet.',
      band: 'Frequency band code for this hop (for example 6G, 11G).',
      find: 'Filter the hop list by call sign or band.'
    }
  };

  function cookieGet() {
    try {
      var parts = document.cookie.split(';');
      for (var i = 0; i < parts.length; i++) {
        var p = parts[i].replace(/^\s+/, '');
        if (p.indexOf('PrefExtraHelp=') === 0) {
          return p.substring('PrefExtraHelp='.length) !== '0';
        }
      }
    } catch (e) { /* ignore */ }
    return null;
  }

  function cacheGet() {
    var cookie = cookieGet();
    if (cookie != null) return cookie;
    try {
      var v = sessionStorage.getItem(CACHE);
      if (v === '0') return false;
      if (v === '1') return true;
    } catch (e) { /* ignore */ }
    return null;
  }

  function syncFromCookie() {
    var cookie = cookieGet();
    if (cookie == null) return;
    if (loaded && on === cookie) return;
    cacheSet(cookie);
    apply(document);
  }

  function bindSync() {
    if (syncBound) return;
    syncBound = true;
    window.addEventListener('focus', syncFromCookie);
    window.addEventListener('pageshow', syncFromCookie);
    document.addEventListener('visibilitychange', function () {
      if (!document.hidden) syncFromCookie();
    });
  }

  function cacheSet(value) {
    on = !!value;
    loaded = true;
    try { sessionStorage.setItem(CACHE, on ? '1' : '0'); } catch (e) { /* ignore */ }
  }

  function isOn() {
    if (loaded) return on;
    var cached = cacheGet();
    if (cached != null) {
      on = cached;
      loaded = true;
      return on;
    }
    return true;
  }

  function apply(root) {
    var scope = root || document;
    var show = isOn();
    var nodes = scope.querySelectorAll('.remics-extra-help');
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].hidden = !show;
      nodes[i].style.display = show ? '' : 'none';
    }
  }

  function set(value, persist) {
    cacheSet(value);
    apply(document);
    if (persist === false) return Promise.resolve({ ok: true, extraHelp: on });
    if (!global.RemIcsApi || !RemIcsApi.extraHelpSet) return Promise.resolve({ ok: true, extraHelp: on });
    return RemIcsApi.extraHelpSet(on);
  }

  function load() {
    bindSync();
    var cached = cacheGet();
    cacheSet(cached == null ? true : cached);
    apply(document);
    return Promise.resolve(on);
  }

  function hintFor(kind, key) {
    var map = HINTS[kind] || {};
    if (map[key]) return map[key];
    if (key && key.indexOf('lat') === 0) return map.latDD || '';
    if (key && key.indexOf('long') === 0) return map.longDD || '';
    return '';
  }

  function bindForm(root, kind, hintId) {
    if (!root) return;
    var hintEl = hintId ? document.getElementById(hintId) : root.querySelector('.remics-field-hint');
    function fieldKey(el) {
      return (el.getAttribute('data-field') || el.id || '').replace(/^(fld-|titl-|chng-|cloc-|ccal-|links-)/, '');
    }
    function showHint(el) {
      if (!isOn() || !hintEl) return;
      var text = hintFor(kind, fieldKey(el));
      hintEl.textContent = text || 'Click a field for a short explanation. Use Help for the full manual page.';
    }
    var inputs = root.querySelectorAll('input, textarea, select');
    for (var i = 0; i < inputs.length; i++) {
      var el = inputs[i];
      var text = hintFor(kind, fieldKey(el));
      if (text && !el.title) el.title = text;
    }
    if (root.getAttribute('data-hints-bound') !== kind) {
      root.setAttribute('data-hints-bound', kind);
      root.addEventListener('focusin', function (ev) {
        var t = ev.target;
        if (!t || !t.tagName) return;
        var tag = String(t.tagName).toLowerCase();
        if (tag !== 'input' && tag !== 'textarea' && tag !== 'select') return;
        showHint(t);
      });
    }
    if (hintEl && isOn() && !hintEl.textContent) {
      hintEl.textContent = 'Click a field for a short explanation. Use Help for the full manual page.';
    }
    apply(root);
  }

  var VALIDATE_FAILS = [
    { key: 'Missing far-end site', fix: 'Add the other Site first. A hop is local call sign + remote call sign + band.' },
    { key: 'Unknown antenna / equipment code', fix: 'Codes come from your SDF files (or main). Use Find...  -  do not type a manufacturer name.' },
    { key: 'NAD27 vs WGS84', fix: 'All latitudes and longitudes in this file must be WGS84. Convert NAD27 before pasting.' },
    { key: 'Required (green) field blank', fix: 'Green labels are required. Fill them before Validate. Command must be A, B, D, N, or U.' },
    { key: 'Local / remote call-sign mismatch', fix: 'Use the same two call signs on both ends of the hop.' }
  ];

  var NEXT = {
    title: 'Next: open Sites and add the first site (call sign or location, coordinates, operator).',
    siteTsOne: 'Next: add the far-end site, then an Antenna on that hop (local + remote + band).',
    siteTsMore: 'Next: add an Antenna on a hop (local call sign + remote call sign + band).',
    siteEs: 'Next: add an Antenna on this site.',
    anteTs: 'Next: add a Channel on this hop.',
    anteEs: 'Next: add a Channel on this site.',
    chan: 'Next: Validate the file. It must finish with no errors before PCN or Database Update.'
  };

  function nextText(kind, ctx) {
    ctx = ctx || {};
    if (kind === 'title') return NEXT.title;
    if (kind === 'site') {
      if (ctx.filetype === 'ES') return NEXT.siteEs;
      return (ctx.siteCount || 0) < 2 ? NEXT.siteTsOne : NEXT.siteTsMore;
    }
    if (kind === 'ante') return ctx.filetype === 'ES' ? NEXT.anteEs : NEXT.anteTs;
    if (kind === 'chan') return NEXT.chan;
    return '';
  }

  function setNext(kind, ctx) {
    var el = document.getElementById('pdf-next-step');
    if (!el) return;
    var text = isOn() ? nextText(kind, ctx) : '';
    el.textContent = text;
    el.hidden = !text;
    el.style.display = text ? '' : 'none';
  }

  function fillWelcomeValidateFails() {
    var table = document.getElementById('welcome-validate-fails');
    fillValidateErrors(table && (table.tBodies[0] || table));
  }

  function fillValidateErrors(tbody) {
    if (!tbody) return;
    tbody.innerHTML = '';
    for (var i = 0; i < VALIDATE_FAILS.length; i++) {
      var tr = document.createElement('tr');
      var td0 = document.createElement('td');
      td0.className = 'o';
      td0.textContent = VALIDATE_FAILS[i].key;
      var td1 = document.createElement('td');
      td1.textContent = VALIDATE_FAILS[i].fix;
      tr.appendChild(td0);
      tr.appendChild(td1);
      tbody.appendChild(tr);
    }
  }

  function setValidateHelp(hasErrors, opts) {
    opts = opts || {};
    var hint = document.getElementById('val-extra-hint');
    var table = document.getElementById('val-error-help');
    var showHelp = isOn();
    if (hint) {
      if (!showHelp) {
        hint.textContent = '';
        hint.style.display = 'none';
      } else if (opts.reportFailed) {
        hint.textContent = 'The report file was missing or could not be read. PCN and DbUpdate stay closed until you can open Display Results.';
        hint.style.display = '';
      } else if (hasErrors) {
        hint.textContent = 'Open Display Results, fix the errors on Edit, then Validate again. PCN and DbUpdate need a clean file.';
        hint.style.display = '';
      } else if (opts.warnings) {
        var n = opts.warnings;
        hint.textContent = 'No errors (' + n + ' warning' + (n === 1 ? '' : 's') + '). PCN and DbUpdate can proceed. Open Display Results to review warnings.';
        hint.style.display = '';
      } else {
        hint.textContent = 'File is clean. Use Edit to change records, PCN to notify operators, or DbUpdate to send to FCSA.';
        hint.style.display = '';
      }
    }
    if (table) {
      var showTable = showHelp && !!hasErrors && !opts.reportFailed;
      if (showTable) fillValidateErrors(table.tBodies[0] || table);
      table.hidden = !showTable;
      table.style.display = showTable ? '' : 'none';
    }
  }

  global.RemicsHints = {
    isOn: isOn,
    set: set,
    load: load,
    apply: apply,
    hintFor: hintFor,
    bindForm: bindForm,
    setNext: setNext,
    setValidateHelp: setValidateHelp,
    fillWelcomeValidateFails: fillWelcomeValidateFails
  };
})(window);
