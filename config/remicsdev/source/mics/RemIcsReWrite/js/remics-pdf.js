// RemIcsReWrite Phase 6.5  -  Title / Site / Ante / Chan (+ ES Azimuth) edit.
(function (global) {
  var state = {
    name: '', filetype: 'TS', siteIsNew: false, anteIsNew: false, chanIsNew: false, azimIsNew: false,
    siteRec: null, anteRec: null, chanRec: null, azimRec: null,
    dirtyKind: '', formSnapshot: '', extraOrig: null
  };

  // Suppress blur validation while opening ? lookups (avoid alert+refocus loops).
  var suppressBlurValidation = false;
  function beginLeaveForm() { suppressBlurValidation = true; }
  function endLeaveForm() { suppressBlurValidation = false; }

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
  function failStatus(ex) {
    status((ex && ex.message) || String(ex || 'Request failed'));
  }
  function goTree() {
    var v = state.filetype === 'ES' ? 'es-tree' : 'ts-tree';
    if (global.RemicsApp && RemicsApp.navigate) RemicsApp.navigate(v);
    else location.hash = '#/' + v;
  }

  function treeKeyForSaved(kind, rec) {
    var name = state.name;
    if (!name || !rec) return '';
    function U(v) { return String(v == null ? '' : v).trim().toUpperCase(); }
    if (kind === 'site') {
      return 'd.' + name + '.' + U(state.filetype === 'ES' ? rec.location : rec.call1);
    }
    if (kind === 'ante') {
      if (state.filetype === 'ES') {
        return 'a.' + name + '.' + U(rec.location) + '.' + U(rec.call1);
      }
      return 'a.' + name + '.' + U(rec.call1) + '.' + U(rec.call2) + '.' + U(rec.bndcde) + '.' + U(rec.anum);
    }
    if (kind === 'chan') {
      if (state.filetype === 'ES') {
        return 'h.' + name + '.' + U(rec.location) + '.' + U(rec.call1) + '.' + U(rec.chid);
      }
      return 'c.' + name + '.' + U(rec.call1) + '.' + U(rec.call2) + '.' + U(rec.bndcde) + '.' + U(rec.chid);
    }
    if (kind === 'azim') {
      return 'm.' + name + '.' + U(rec.location) + '.' + U(rec.call1);
    }
    if (kind === 'link') {
      return 'k.' + name + '.' + U(rec.call1) + '.' + U(rec.call2) + '.' + U(rec.bndcde);
    }
    return '';
  }

  function notifyTreeRefresh(kind, rec) {
    var key = (kind && rec) ? treeKeyForSaved(kind, rec) : '';
    if (global.RemicsTs && typeof RemicsTs.reloadTree === 'function') {
      RemicsTs.reloadTree(key, state.filetype);
    }
  }

  function filterStoreKey() {
    return 'remics-pdf-filter-' + state.filetype + '-' + String(state.name || '').toLowerCase();
  }

  function readFilters() {
    try {
      return JSON.parse(sessionStorage.getItem(filterStoreKey()) || '{}') || {};
    } catch (e) {
      return {};
    }
  }

  function writeFilters(patch) {
    var cur = readFilters();
    Object.keys(patch || {}).forEach(function (k) { cur[k] = patch[k]; });
    try { sessionStorage.setItem(filterStoreKey(), JSON.stringify(cur)); } catch (e) { /* ignore */ }
  }

  function snapshotForm(kind) {
    if (kind === 'title') {
      return JSON.stringify({
        namef: ($('titl-namef') && $('titl-namef').value) || '',
        source: ($('titl-source') && $('titl-source').value) || '',
        descr: ($('titl-descr') && $('titl-descr').value) || ''
      });
    }
    if (kind === 'chng') {
      return JSON.stringify({
        old: ($('chng-old') && $('chng-old').value) || '',
        neu: ($('chng-new') && $('chng-new').value) || '',
        name: ($('chng-name') && $('chng-name').value) || ''
      });
    }
    if (kind === 'cloc') {
      return JSON.stringify({
        old: ($('cloc-old') && $('cloc-old').value) || '',
        neu: ($('cloc-new') && $('cloc-new').value) || '',
        name: ($('cloc-name') && $('cloc-name').value) || ''
      });
    }
    if (kind === 'ccal') {
      return JSON.stringify({
        old: ($('ccal-old') && $('ccal-old').value) || '',
        neu: ($('ccal-new') && $('ccal-new').value) || ''
      });
    }
    return JSON.stringify(collectFields(kind + '-fields'));
  }

  function markClean(kind) {
    state.dirtyKind = kind || '';
    state.formSnapshot = kind ? snapshotForm(kind) : '';
  }

  function isDirty() {
    if (!state.dirtyKind) return false;
    if (state.dirtyKind === 'title') {
      if (!$('titl-namef')) return false;
      return snapshotForm('title') !== state.formSnapshot;
    }
    var form = $(state.dirtyKind + '-form');
    if (!form || form.hidden) return false;
    return snapshotForm(state.dirtyKind) !== state.formSnapshot;
  }

  function confirmLeave() {
    if (!isDirty()) return true;
    return window.confirm('You have unsaved changes. Leave without saving?');
  }

  function canLeave() {
    if (!confirmLeave()) {
      var q = 'name=' + encodeURIComponent(state.name) + '&filetype=' + encodeURIComponent(state.filetype);
      var keep = '#/pdf-edit?' + q;
      if (location.hash !== keep) {
        try { history.replaceState(null, '', keep); } catch (e) { location.hash = keep; }
      }
      return false;
    }
    markClean('');
    return true;
  }

  function goTreeSafe() {
    if (!confirmLeave()) return;
    markClean('');
    var key = ((parseRoute().params.key || '').trim());
    if (key && global.RemicsTs && typeof RemicsTs.rememberReveal === 'function') {
      RemicsTs.rememberReveal(key, state.filetype);
    }
    goTree();
  }

  function closeEntityForm(kind) {
    if (!confirmLeave()) return false;
    show($(kind + '-form'), false);
    markClean('');
    return true;
  }

  function firstFocusField(kind) {
    var ids = [];
    if (kind === 'site') ids = state.filetype === 'ES' ? ['fld-location', 'fld-name'] : ['fld-call1', 'fld-name'];
    else if (kind === 'ante') ids = state.filetype === 'ES' ? ['fld-call1', 'fld-location', 'fld-txband'] : ['fld-anum', 'fld-acode', 'fld-call1'];
    else if (kind === 'chan') ids = ['fld-chid', 'fld-call1', 'fld-location'];
    else if (kind === 'azim') ids = ['fld-azim', 'fld-elev', 'fld-call1'];
    else if (kind === 'title') ids = ['titl-namef', 'titl-source'];
    else if (kind === 'chng') ids = ['chng-old', 'chng-name', 'chng-new'];
    else if (kind === 'cloc') ids = ['cloc-old', 'cloc-new'];
    else if (kind === 'ccal') ids = ['ccal-old', 'ccal-new'];
    for (var i = 0; i < ids.length; i++) {
      var el = $(ids[i]);
      if (el && !el.readOnly && !el.disabled && el.type !== 'hidden') {
        try { el.focus(); if (el.select) el.select(); } catch (e) { /* ignore */ }
        return;
      }
    }
  }

  function wireEnterAsTab(container) {
    if (!container || container._enterWired) return;
    container._enterWired = true;
    container.addEventListener('keydown', function (ev) {
      if (ev.key !== 'Enter' && ev.keyCode !== 13) return;
      var t = ev.target;
      if (!t) return;
      var tag = (t.tagName || '').toUpperCase();
      var type = (t.type || '').toLowerCase();
      if (tag === 'TEXTAREA' || tag === 'BUTTON' || type === 'button' || type === 'submit') return;
      ev.preventDefault();
      var nodes = container.querySelectorAll('input, select, textarea');
      var focusable = [];
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        var elType = (el.type || '').toLowerCase();
        if (el.disabled || el.readOnly || el.tabIndex === -1) continue;
        if (elType === 'hidden' || elType === 'button' || elType === 'submit') continue;
        if (!el.offsetParent) continue;
        focusable.push(el);
      }
      var idx = focusable.indexOf(t);
      if (idx >= 0 && idx < focusable.length - 1) focusable[idx + 1].focus();
    });
  }

  function keyFieldsFor(kind) {
    if (kind === 'site') return state.filetype === 'ES' ? ['location'] : ['call1'];
    if (kind === 'ante') return state.filetype === 'ES' ? ['call1'] : ['anum'];
    if (kind === 'chan') return ['chid'];
    if (kind === 'azim') return ['azim'];
    return [];
  }

  function afterFormReady(kind, doFocus) {
    wireEnterAsTab($(kind + '-form'));
    wireFieldChecks(kind);
    if (kind === 'site') wireSiteSaveValidation();
    if (kind === 'ante') afterAnteRender();
    if (kind === 'chan') afterChanRender();
    markClean(kind);
    if (doFocus) firstFocusField(kind);
  }

  function strtrim(s) {
    return String(s == null ? '' : s).replace(/^\s+|\s+$/g, '');
  }

  function isAllDigits(s) {
    if (!s) return false;
    for (var i = 0; i < s.length; i++) {
      var c = s.charCodeAt(i);
      if (c < 48 || c > 57) return false;
    }
    return true;
  }

  function isNegInt(s) {
    if (!s) return false;
    for (var i = 0; i < s.length; i++) {
      var c = s.charCodeAt(i);
      if (c < 48 || c > 57) {
        if (i !== 0 || s.charAt(i) !== '-') return false;
      }
    }
    return true;
  }

  function formatFloat(s, places) {
    var minus = false;
    var raw = String(s || '');
    if (raw.charAt(0) === '-') {
      minus = true;
      raw = raw.substr(1);
    }
    var dec = false;
    for (var i = 0; i < raw.length; i++) {
      var c = raw.charCodeAt(i);
      if (c < 48 || c > 57) {
        if (raw.charAt(i) === '.' && !dec) dec = true;
        else return null;
      }
    }
    var n = parseFloat(raw);
    if (isNaN(n)) return null;
    var out = n.toFixed(places);
    return minus ? ('-' + out) : out;
  }

  function leavingToButton(ev) {
    var n = ev && ev.relatedTarget;
    if (!n) return false;
    if (n.getAttribute && (n.getAttribute('data-lookup') || n.id && String(n.id).indexOf('-lookup') >= 0)) {
      return true;
    }
    var tag = (n.tagName || '').toUpperCase();
    var type = (n.type || '').toLowerCase();
    return tag === 'BUTTON' || type === 'button' || type === 'submit';
  }

  function fieldFail(fld, msg, noFocus) {
    if (suppressBlurValidation) return;
    alert(msg);
    fld.value = '';
    if (!noFocus) {
      setTimeout(function () { try { fld.focus(); } catch (e) { /* ignore */ } }, 0);
    }
  }

  function icheck(fld, low, high, noFocus) {
    if (suppressBlurValidation) return true;
    fld.value = strtrim(fld.value);
    if (!fld.value) return true;
    var ok = low < 0 ? isNegInt(fld.value) : isAllDigits(fld.value);
    if (!ok) {
      fieldFail(fld, 'You have entered an invalid character', noFocus);
      return false;
    }
    var n = Number(fld.value);
    if (n < low || n > high) {
      fieldFail(fld, 'You must enter a numeric value between ' + low + ' and ' + high + '.', noFocus);
      return false;
    }
    return true;
  }

  function ichecklz2(fld, low, high, noFocus) {
    if (!icheck(fld, low, high, noFocus)) return false;
    if (fld.value && fld.value.length === 1) fld.value = '0' + fld.value;
    return true;
  }

  function fcheck(fld, low, high, places, required, noFocus) {
    if (suppressBlurValidation) return true;
    if (!fld.value) {
      if (required && !noFocus) alert('Warning - a value is required before validation');
      return !required;
    }
    var chk = formatFloat(fld.value, places);
    if (chk == null) {
      fieldFail(fld, 'You have entered an invalid character in a numeric field.', noFocus);
      return false;
    }
    var n = Number(chk);
    if (n < low || n > high) {
      fieldFail(fld, 'You must enter a numeric value between ' +
        low.toFixed(places) + ' and ' + high.toFixed(places) + '.', noFocus);
      return false;
    }
    fld.value = chk;
    return true;
  }

  function checkMonth(fldmm, flddd, fldyy, noFocus) {
    var mm = String(fldmm.value || '').toUpperCase();
    if (!mm || mm === 'MMM') return true;
    var names = ['', 'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    var nums = ['', '01', '02', '03', '04', '05', '06', '07', '08', '09', '10', '11', '12'];
    var intMonth = '';
    var i;
    for (i = 1; i < 13; i++) {
      if (mm === String(i) || mm === names[i]) {
        intMonth = nums[i];
        fldmm.value = names[i];
        break;
      }
    }
    if (!intMonth) {
      fieldFail(fldmm, 'You have not entered a valid month.', noFocus);
      return false;
    }
    var dd = flddd.value;
    if (!dd) return true;
    var day = parseInt(dd, 10);
    var valid = true;
    if (intMonth === '02') {
      if (day > 29) valid = false;
      if (day === 29) {
        valid = false;
        var yy = parseInt(fldyy.value, 10);
        for (i = 1976; i < 2051; i += 4) {
          if (yy === i) valid = true;
        }
      }
    } else if (intMonth === '04' || intMonth === '06' || intMonth === '09' || intMonth === '11') {
      if (day > 30) valid = false;
    }
    if (!valid) {
      fieldFail(flddd, 'Invalid date', noFocus);
      return false;
    }
    return true;
  }

  function checkDateParts(noFocus) {
    var dd = $('fld-sDay');
    var mm = $('fld-sMonth');
    var yy = $('fld-sYear');
    if (!dd || !mm || !yy) return;
    dd.value = strtrim(dd.value);
    mm.value = strtrim(mm.value);
    yy.value = strtrim(yy.value);
    var flag = 0;
    if (dd.value) flag += 1;
    if (mm.value) flag += 2;
    if (yy.value) flag += 4;
    if (flag & 1) ichecklz2(dd, 1, 31, noFocus);
    if (flag & 4) icheck(yy, 1975, 2050, noFocus);
    if (flag & 2) checkMonth(mm, dd, yy, noFocus);
  }

  function applyOffAzim(fld, noFocus) {
    var call1 = ($('fld-call1') && $('fld-call1').value) || '';
    if (call1.charAt(0) === '%') {
      fld.value = 'P';
      if (global.RemicsPdfFields && RemicsPdfFields.applyAnteLocks) {
        RemicsPdfFields.applyAnteLocks({ call1: call1 });
      }
      return;
    }
    var v = String(fld.value || '').toUpperCase();
    if (!v) v = 'N';
    if (v !== 'Y' && v !== 'N') {
      fieldFail(fld, 'You may only enter Y or N', noFocus);
      fld.value = 'N';
      v = 'N';
    } else {
      fld.value = v;
    }
    ['tazmth', 'telvtn', 'tgain'].forEach(function (k) {
      var el = $('fld-' + k);
      if (!el) return;
      if (v !== 'Y') el.value = '';
      el.readOnly = v !== 'Y';
      el.tabIndex = v === 'Y' ? 0 : -1;
      el.className = v === 'Y' ? 'im' : 'iro';
    });
  }

  function fieldCheckRules(schema) {
    var rules = {};
    function i(key, low, high) { rules[key] = { i: [low, high] }; }
    function f(key, low, high, places, required) { rules[key] = { f: [low, high, places, !!required] }; }
    function extra(key, name) { rules[key] = rules[key] || {}; rules[key].extra = name; }
    if (schema === 'SITE_TS' || schema === 'SITE_ES') {
      i('latDD', -89, 89); extra('latDD', 'latDir');
      i('latMM', 0, 59); i('latSS', 0, 59); i('lat00', 0, 99); extra('lat00', 'lat00');
      i('longDD', -179, 179); extra('longDD', 'longDir');
      i('longMM', 0, 59); i('longSS', 0, 59); i('long00', 0, 99); extra('long00', 'long00');
      f('grnd', 0, 6200, 1, false);
      rules.sDay = { date: true }; rules.sMonth = { date: true }; rules.sYear = { date: true };
    }
    if (schema === 'SITE_TS') {
      i('notwr', 1, 9);
      rules.icaccount = { up: true };
    }
    if (schema === 'SITE_ES') i('rain', 1, 9);
    if (schema === 'ANTE_TS') {
      i('atwrno', 1, 9); i('anum', 1, 99);
      f('aht', 0, 1000, 1, false);
      rules.offazm = { extra: 'offAzim' };
      f('tazmth', 0, 360, 2, true);
      f('telvtn', -89.99, 89.99, 2, true);
      f('tgain', 0, 99.9, 1, true);
      f('kvalue', 0, 9.99, 2, false);
      f('obsloss', 0, 99.9, 1, false);
      rules.licence = { up: true };
      f('txcompl', -99.9, 99.9, 1, false); f('rxcompl', -99.9, 99.9, 1, false);
      f('txfdlnlh', 0, 999.9, 1, false); f('rxfdlnlh', 0, 999.9, 1, false);
      f('txfdlnlv', 0, 999.9, 1, false); f('rxfdlnlv', 0, 999.9, 1, false);
      f('txpadpam', -99.9, 99.9, 1, false); f('rxpadlna', -99.9, 99.9, 1, false);
      rules.sDay = { date: true }; rules.sMonth = { date: true }; rules.sYear = { date: true };
    }
    if (schema === 'ANTE_ES') {
      f('aht', 0, 1000, 1, false);
      i('antref', 0, 999999);
      f('g_t', -99, 99.9, 1, false); f('lnat', 0, 999.9, 1, false);
      f('satlong', 0, 180, 2, false); rules.satlongs = { extra: 'satlongs' };
      f('sarc1', -180, 180, 2, false); f('sarc2', 0, 90, 2, false);
      f('afslt', 0, 99.9, 1, false); f('afslr', 0, 99.9, 1, false);
      f('txpre', 0, 9999.99, 2, false); f('rxpre', 0, 9999.99, 2, false);
      f('txtro', 0, 9999.99, 2, false); f('rxtro', 0, 9999.99, 2, false);
      rules.licence = { up: true };
    }
    if (schema === 'CHAN_TS') {
      i('vh', 1, 4); i('hl', 1, 6);
      f('esint', -999.9, -0.1, 1, false); f('tsint', -999.9, -0.1, 1, false);
      f('freqtx', 0, 99999999.99, 2, false);
      i('antnumbtx1', 1, 99); i('antnumbtx2', 1, 99);
      i('antnumbrx1', 1, 99); i('antnumbrx2', 1, 99); i('antnumbrx3', 1, 99);
      f('afsltx1', 0, 99.9, 1, false); f('afsltx2', 0, 99.9, 1, false);
      f('afslrx1', 0, 99.9, 1, false); f('afslrx2', 0, 99.9, 1, false); f('afslrx3', 0, 99.9, 1, false);
      f('pwrtx', -999.9, 999.9, 1, false); f('atpccde', 0, 99.9, 1, false);
      i('hopnumb', 0, 99); i('stnnumb', 1, 99);
      rules.sDay = { date: true }; rules.sMonth = { date: true }; rules.sYear = { date: true };
    }
    if (schema === 'CHAN_ES') {
      f('i20', -999.9, 0, 1, false); f('ip01', -999.9, 0, 1, false); f('it01', -999.9, 0, 1, false);
      f('maxtxpower', -99.9, 99.9, 1, false); f('p4khz', 0, 50, 1, false);
      f('freqtx', 0, 99999999.99, 2, false); f('freqrx', 0, 99999999.99, 2, false);
      f('pwrtx', -99.9, 99.9, 2, false); f('pwrrx', -999.9, 0, 2, false);
    }
    if (schema === 'AZIM_ES') {
      f('azim', 0, 360, 2, false); f('elev', -90, 90, 2, false);
      f('dist', 0, 999.99, 2, false); f('loss', 0, 999.99, 2, false);
    }
    return rules;
  }

  function runFieldExtra(fld, name, noFocus) {
    if (name === 'latDir') {
      var latDir = $('fld-latDir');
      if (latDir) latDir.value = String(fld.value || '').charAt(0) === '-' ? 'S' : 'N';
      return;
    }
    if (name === 'longDir') {
      var longDir = $('fld-longDir');
      if (longDir) longDir.value = String(fld.value || '').charAt(0) === '-' ? 'E' : 'W';
      return;
    }
    if (name === 'lat00' || name === 'long00') {
      var pfx = name === 'lat00' ? 'lat' : 'long';
      var label = name === 'lat00' ? 'Latitude' : 'Longitude';
      var parts = [
        { el: $('fld-' + pfx + 'DD'), msg: 'You must enter the ' + label + ' Degrees' },
        { el: $('fld-' + pfx + 'MM'), msg: 'You must enter the ' + label + ' Minutes' },
        { el: $('fld-' + pfx + 'SS'), msg: 'You must enter the ' + label + ' Seconds' },
        { el: fld, msg: 'You must enter the ' + label + ' Decimal Seconds' }
      ];
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].el && !strtrim(parts[i].el.value)) {
          alert(parts[i].msg);
          if (!noFocus) {
            var focusEl = parts[i].el;
            setTimeout(function () { try { focusEl.focus(); } catch (e) { /* ignore */ } }, 0);
          }
          return;
        }
      }
      return;
    }
    if (name === 'satlongs') {
      var sense = String(fld.value || '').toUpperCase();
      if (sense && sense !== 'W' && sense !== 'E') {
        fieldFail(fld, 'You have entered an invalid character in Satellite Longitude Sense field. Valid values are W or E. ', noFocus);
      } else {
        fld.value = sense;
      }
      return;
    }
    if (name === 'offAzim') applyOffAzim(fld, noFocus);
  }

  function runFieldCheck(fld, rule, ev) {
    if (!fld || !rule || fld.readOnly || suppressBlurValidation) return;
    var noFocus = leavingToButton(ev);
    if (rule.up) fld.value = String(fld.value || '').toUpperCase();
    if (rule.date) {
      checkDateParts(noFocus);
      return;
    }
    if (rule.i) icheck(fld, rule.i[0], rule.i[1], noFocus);
    if (rule.f) fcheck(fld, rule.f[0], rule.f[1], rule.f[2], rule.f[3], noFocus);
    if (rule.extra) runFieldExtra(fld, rule.extra, noFocus);
  }

  function wireFieldChecks(kind) {
    var schema = kind === 'site'
      ? (state.filetype === 'ES' ? 'SITE_ES' : 'SITE_TS')
      : kind === 'ante'
        ? (state.filetype === 'ES' ? 'ANTE_ES' : 'ANTE_TS')
        : kind === 'chan'
          ? (state.filetype === 'ES' ? 'CHAN_ES' : 'CHAN_TS')
          : kind === 'azim' ? 'AZIM_ES' : '';
    var rules = fieldCheckRules(schema);
    Object.keys(rules).forEach(function (key) {
      var el = $('fld-' + key);
      if (!el || el.readOnly || el._rangeWired) return;
      el._rangeWired = true;
      el.addEventListener('blur', function (ev) { runFieldCheck(el, rules[key], ev); });
    });
  }

  function syncListFindVisible(listId, findId) {
    var list = $(listId);
    var find = $(findId);
    var row = $(findId + '-row') || (find && find.parentNode);
    var n = list ? list.querySelectorAll('li').length : 0;
    show(list, n > 0);
    show(row, n > 1);
    if (n < 2 && find) find.value = '';
  }

  function applyListFind(listId, findId) {
    var list = $(listId);
    var find = $(findId);
    if (!list) return;
    var q = find ? String(find.value || '').toLowerCase().replace(/^\s+|\s+$/g, '') : '';
    var items = list.querySelectorAll('li');
    for (var i = 0; i < items.length; i++) {
      var t = (items[i].textContent || '').toLowerCase();
      items[i].style.display = (!q || t.indexOf(q) >= 0) ? '' : 'none';
    }
    syncListFindVisible(listId, findId);
  }

  function wireListFind(listId, findId) {
    var find = $(findId);
    if (!find || find._findWired) return;
    find._findWired = true;
    find.addEventListener('input', function () { applyListFind(listId, findId); });
  }

  function beginDuplicate(kind) {
    var rec = collectFields(kind + '-fields');
    keyFieldsFor(kind).forEach(function (k) { rec[k] = ''; });
    ['mDay', 'mMonth', 'mYear'].forEach(function (k) { rec[k] = ''; });
    rec.cmd = 'A';
    if (kind === 'site') {
      state.siteIsNew = true;
      state.siteRec = rec;
      renderFields('site-fields', state.filetype === 'ES' ? SITE_ES : SITE_TS, rec, []);
      setEntityHeading('pdf-site-heading', 'FCSA MICS Terrestrial Site', 'FCSA MICS Earth Station Site');
      show($('site-form'), true);
      afterFormReady('site', true);
    } else if (kind === 'ante') {
      state.anteIsNew = true;
      state.anteRec = rec;
      renderFields('ante-fields', state.filetype === 'ES' ? ANTE_ES : ANTE_TS, rec, anteReadonlyKeysForNew(rec));
      setEntityHeading('pdf-ante-heading', 'FCSA MICS Terrestrial Antenna', 'FCSA MICS Earth Station Antenna');
      show($('ante-form'), true);
      afterFormReady('ante', true);
    } else if (kind === 'chan') {
      state.chanIsNew = true;
      state.chanRec = rec;
      renderFields('chan-fields', state.filetype === 'ES' ? CHAN_ES : CHAN_TS, rec, chanReadonlyKeysForNew(rec));
      setEntityHeading('pdf-chan-heading', 'FCSA MICS Terrestrial Channel', 'FCSA MICS Earth Station Channel');
      show($('chan-form'), true);
      afterFormReady('chan', true);
    } else if (kind === 'azim') {
      state.azimIsNew = true;
      state.azimRec = rec;
      renderFields('azim-fields', AZIM_ES, rec, azimReadonlyKeysForNew(rec));
      show($('azim-form'), true);
      afterFormReady('azim', true);
    }
    status('Duplicate  -  change the key fields and Save');
  }

  function suggestNextTsAnum(call1, call2, bndcde) {
    call1 = String(call1 || '').trim();
    call2 = String(call2 || '').trim();
    bndcde = String(bndcde || '').trim();
    if (!call1 || !call2 || !bndcde) return Promise.resolve('');
    return RemIcsApi.pdfEdit('antesList', {
      name: state.name, filetype: 'TS', siteKey: call1
    }).then(function (r) {
      var used = {};
      ((r && r.antes) || []).forEach(function (a) {
        if (a.call1 === call1 && a.call2 === call2 && a.bndcde === bndcde) {
          var n = parseInt(a.anum, 10);
          if (!isNaN(n)) used[n] = true;
        }
      });
      for (var i = 1; i <= 99; i++) {
        if (!used[i]) return String(i);
      }
      return '';
    }).catch(function () { return ''; });
  }

  function contextForNew(kind, rec) {
    rec = rec || {};
    if (kind === 'ante') {
      return state.filetype === 'ES'
        ? { location: rec.location || ($('ante-site-filter') && $('ante-site-filter').value) || '' }
        : { call1: rec.call1 || '', call2: rec.call2 || '', bndcde: rec.bndcde || '' };
    }
    if (kind === 'chan') {
      return state.filetype === 'ES'
        ? { location: rec.location || '', call1: rec.call1 || '' }
        : { call1: rec.call1 || '', call2: rec.call2 || '', bndcde: rec.bndcde || '' };
    }
    if (kind === 'azim') {
      return { location: rec.location || '', call1: rec.call1 || '' };
    }
    return {};
  }

  function addOption(sel, value, label) {
    var opt = document.createElement('option');
    opt.value = value;
    opt.textContent = label;
    sel.appendChild(opt);
  }

  function selectedHop(which) {
    var sel = $(which + '-link-select');
    if (!sel || !sel.value || sel.value === '__new__') return null;
    var p = sel.value.split('|');
    return { call1: p[0] || '', call2: p[1] || '', bndcde: p[2] || '' };
  }

  function newHopKeys(which) {
    return {
      call1: (($(which + '-site-select') && $(which + '-site-select').value) || '').trim().toUpperCase(),
      call2: (($(which + '-remote') && $(which + '-remote').value) || '').trim().toUpperCase(),
      bndcde: (($(which + '-band') && $(which + '-band').value) || '').trim().toUpperCase()
    };
  }

  function hopKeysForNew(which) {
    var hop = selectedHop(which);
    if (hop) return hop;
    var sel = $(which + '-link-select');
    if (sel && sel.value === '__new__') return newHopKeys(which);
    return {};
  }

  function hopSiteKey(which) {
    var hop = selectedHop(which);
    if (hop) return hop.call1;
    var sel = $(which + '-link-select');
    if (sel && sel.value === '__new__') return newHopKeys(which).call1;
    return '';
  }

  // U2-2: idle list copy — count alone left Edit path undiscoverable.
  function listIdleStatus(n, noun) {
    if (!n) return '0 ' + noun + '(s)';
    if (n === 1) return '1 ' + noun + ' — click to edit';
    return n + ' ' + noun + '(s) — click a row to edit';
  }

  function loadHopSelect(which) {
    var sel = $(which + '-link-select');
    var siteSel = $(which + '-site-select');
    if (!sel || state.filetype !== 'TS') return Promise.resolve();
    var filters = readFilters();
    var prev = sel.value || filters.tsHop || '';
    // Only prefer first hop when the user has never chosen a hop filter for this file.
    var hopChosen = Object.prototype.hasOwnProperty.call(filters, 'tsHop') || !!sel.value;
    return Promise.all([
      RemIcsApi.pdfEdit('sitesList', { name: state.name, filetype: 'TS' }),
      RemIcsApi.pdfExtra('linksites', { name: state.name, filetype: 'TS' })
    ]).then(function (results) {
      var r0 = results[0] || {};
      var r1 = results[1] || {};
      if (!r0.ok || !r1.ok) {
        status((!r0.ok ? (r0.error || 'sitesList failed') : (r1.error || 'linksites failed')));
        return;
      }
      var sites = r0.sites || [];
      var links = r1.links || [];
      sel.innerHTML = '';
      addOption(sel, '', '(all hops)');
      addOption(sel, '__new__', '(new hop...)');
      links.forEach(function (l) {
        var val = (l.call1 || '') + '|' + (l.call2 || '') + '|' + (l.bndcde || '');
        addOption(sel, val, (l.call1 || '') + ' → ' + (l.call2 || '') + ' / ' + (l.bndcde || ''));
      });
      if (prev) {
        sel.value = prev;
      } else if (!hopChosen && links.length) {
        var l0 = links[0];
        sel.value = (l0.call1 || '') + '|' + (l0.call2 || '') + '|' + (l0.bndcde || '');
      }
      writeFilters({ tsHop: sel.value || '' });
      if (siteSel) {
        siteSel.innerHTML = '';
        addOption(siteSel, '', '(local site)');
        sites.forEach(function (s) {
          addOption(siteSel, s.key || '', (s.key || '') + (s.name ? '  -  ' + s.name : ''));
        });
      }
      show($(which + '-new-hop'), sel.value === '__new__');
    }).catch(function (ex) { failStatus(ex); });
  }

  var SITE_TS = ['cmd', 'call1', 'name', 'prov', 'oper', 'grnd', 'stats', 'notwr', 'icaccount', 'nots', 'snumb', 'spoint', 'reg', 'loc',
    'latDD', 'latMM', 'latSS', 'lat00', 'latDir', 'longDD', 'longMM', 'longSS', 'long00', 'longDir',
    'mDay', 'mMonth', 'mYear', 'sDay', 'sMonth', 'sYear'];
  var SITE_ES = ['cmd', 'location', 'name', 'prov', 'oper', 'grnd', 'stats', 'radio', 'rain', 'reg', 'nots', 'oprtyp',
    'latDD', 'latMM', 'latSS', 'lat00', 'latDir', 'longDD', 'longMM', 'longSS', 'long00', 'longDir',
    'mDay', 'mMonth', 'mYear', 'sDay', 'sMonth', 'sYear'];
  var ANTE_TS = ['cmd', 'call1', 'call2', 'bndcde', 'anum', 'ause', 'acode', 'aht', 'azmth', 'elvtn', 'dist', 'offazm',
    'tazmth', 'telvtn', 'tgain', 'atwrno', 'nota', 'licence', 'kvalue', 'obsloss', 'txcompl', 'rxcompl', 'apoint',
    'txfdlnth', 'txfdlnlh', 'txfdlntv', 'txfdlnlv', 'rxfdlnth', 'rxfdlnlh', 'rxfdlntv', 'rxfdlnlv', 'txpadpam', 'rxpadlna',
    'mDay', 'mMonth', 'mYear', 'sDay', 'sMonth', 'sYear'];
  var ANTE_ES = ['cmd', 'location', 'call1', 'txband', 'rxband', 'acodetx', 'acoderx', 'g_t', 'lnat', 'aht',
    'afslt', 'afslr', 'txhgmax', 'rxhgmax', 'satlongit', 'satlong', 'satlongs', 'az', 'el', 'sarc1', 'sarc2',
    'rxpre', 'txpre', 'rxtro', 'txtro', 'licence', 'satname', 'stata', 'nota', 'op2', 'antref', 'orbit',
    'mDay', 'mMonth', 'mYear'];
  var CHAN_TS = ['cmd', 'call1', 'call2', 'bndcde', 'chid', 'splan', 'hl', 'vh', 'esint', 'tsint',
    'freqtx', 'poltx', 'antnumbtx1', 'antnumbtx2', 'eqpttx', 'eqptutx', 'pwrtx', 'atpccde', 'afsltx1', 'afsltx2',
    'traftx', 'srvctx', 'stattx', 'freqrx', 'polrx', 'antnumbrx1', 'antnumbrx2', 'antnumbrx3', 'eqptrx', 'eqpturx',
    'afslrx1', 'afslrx2', 'afslrx3', 'pwrrx1', 'pwrrx2', 'pwrrx3', 'trafrx', 'srvcrx', 'statrx',
    'routnumb', 'stnnumb', 'hopnumb', 'notetx', 'noterx', 'notegnl', 'cpoint', 'feetx', 'feerx',
    'tx_Authorization', 'rx_Authorization', 'mDay', 'mMonth', 'mYear', 'sDay', 'sMonth', 'sYear'];
  var CHAN_ES = ['cmd', 'location', 'call1', 'chid', 'freqtx', 'poltx', 'maxtxpower', 'pwrtx', 'p4khz',
    'eqpttx', 'traftx', 'stattx', 'feetx', 'freqrx', 'polrx', 'pwrrx', 'eqptrx', 'trafrx', 'statrx',
    'i20', 'it01', 'ip01', 'feerx', 'notc', 'srvctx', 'srvcrx', 'mDay', 'mMonth', 'mYear'];
  var AZIM_ES = ['cmd', 'location', 'call1', 'azim', 'elev', 'dist', 'loss', 'mDay', 'mMonth', 'mYear'];

  function renderFields(tableId, fields, rec, readonlyKeys) {
    if (global.RemicsPdfFields) {
      var schema = tableId.indexOf('site') >= 0
        ? (state.filetype === 'ES' ? 'SITE_ES' : 'SITE_TS')
        : tableId.indexOf('ante') >= 0
          ? (state.filetype === 'ES' ? 'ANTE_ES' : 'ANTE_TS')
          : tableId.indexOf('chan') >= 0
            ? (state.filetype === 'ES' ? 'CHAN_ES' : 'CHAN_TS')
            : tableId.indexOf('azim') >= 0
              ? 'AZIM_ES'
              : null;
      if (schema) {
        RemicsPdfFields.render(tableId, schema, rec, readonlyKeys);
        bindFieldHints(tableId);
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
        inp.setAttribute('aria-readonly', 'true');
        inp.title = 'Filled by MICS — not editable';
      }
      td2.appendChild(inp);
      tr.appendChild(td1);
      tr.appendChild(td2);
      table.appendChild(tr);
    });
    bindFieldHints(tableId);
  }

  function bindFieldHints(tableId) {
    if (!window.RemicsHints) return;
    var kind = tableId.indexOf('azim') >= 0 ? 'azim'
      : tableId.indexOf('site') >= 0 ? 'site'
      : tableId.indexOf('ante') >= 0 ? 'ante'
      : tableId.indexOf('chan') >= 0 ? 'chan'
      : null;
    if (!kind) return;
    var table = $(tableId);
    var root = (table && table.parentNode) || table;
    var hintId = kind === 'site' ? 'site-field-hint'
      : kind === 'ante' ? 'ante-field-hint'
      : kind === 'azim' ? 'azim-field-hint'
      : 'chan-field-hint';
    RemicsHints.bindForm(root, kind, hintId);
  }

  function collectFields(tableId) {
    if (global.RemicsPdfFields && (tableId === 'site-fields' || tableId === 'ante-fields' || tableId === 'chan-fields' || tableId === 'azim-fields')) {
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
    status('Loading links...');
    Promise.all([
      RemIcsApi.pdfExtra('linksites', { name: state.name, filetype: 'TS' }),
      RemIcsApi.pdfEdit('sitesList', { name: state.name, filetype: 'TS' })
    ]).then(function (results) {
      var r = results[0] || {};
      if (!r.ok) { status(r.error || 'Failed'); return; }
      var list = $('links-list');
      list.innerHTML = '';
      (r.links || []).forEach(function (l) {
        var li = document.createElement('li');
        li.textContent = l.call1 + ' ↔ ' + l.call2 + ' / ' + l.bndcde;
        list.appendChild(li);
      });
      applyListFind('links-list', 'links-find');
      var localSel = $('links-local');
      if (localSel) {
        var prev = localSel.value;
        localSel.innerHTML = '';
        addOption(localSel, '', '(local site)');
        ((results[1] && results[1].sites) || []).forEach(function (s) {
          addOption(localSel, s.key || '', (s.key || '') + (s.name ? '  -  ' + s.name : ''));
        });
        if (prev) localSel.value = prev;
      }
      status((r.links || []).length + ' hop(s). Pick a local site, enter remote + band, then New Link.');
      showPanel('links');
      if (window.RemicsHints) RemicsHints.bindForm($('pdf-panel-links'), 'links', 'links-field-hint');
    }).catch(function (ex) { failStatus(ex); });
  }

  function addPdfLink() {
    var call1 = (($('links-local') && $('links-local').value) || '').trim().toUpperCase();
    var remote = (($('links-remote') && $('links-remote').value) || '').trim().toUpperCase();
    var band = (($('links-band') && $('links-band').value) || '').trim().toUpperCase();
    if (!call1) { alert('Select a local site.'); return; }
    if (!remote) { alert('You must enter a Remote Call Sign.'); return; }
    if (!band) { alert('You must enter a Band Code.'); return; }
    var linkKey = 'k.' + state.name + '.' + call1 + '.' + remote + '.' + band;
    RemIcsApi.verifyTsLinkSite(linkKey).then(function (r) {
      if (!r.ok) {
        alert((window.RemIcsApi && RemIcsApi.apiErr) ? RemIcsApi.apiErr(r, 'verifySite failed') : (r.error || 'verifySite failed'));
        return;
      }
      var parts = String(r.body || '').split('.');
      if (parts.length === 5) {
        var msg = 'You must add a Site Record for the Call Sign ' + (parts[3] || remote) +
          '. Would you like to add a site with this call sign?';
        if (window.confirm(msg)) {
          openSite(parts[3] || remote, true);
        }
        return;
      }
      status('Link ' + call1 + ' → ' + remote + ' / ' + band + ' verified.');
      notifyTreeRefresh('link', { call1: call1, call2: remote, bndcde: band });
      loadLinks();
    }).catch(function (ex) { failStatus(ex); });
  }

  function extraCfg(kind) {
    if (kind === 'chng') {
      return {
        kind: 'chng', filetype: 'TS', list: 'chnglist', save: 'chngsave', del: 'chngdelete',
        findId: 'chng-find', listId: 'chng-list',
        fields: ['chng-old', 'chng-new', 'chng-name'],
        fill: function (row) {
          $('chng-old').value = row.oldcall1 || '';
          $('chng-new').value = row.newcall1 || '';
          $('chng-name').value = row.name || '';
        },
        origOf: function (row) { return { oldcall1: row.oldcall1, newcall1: row.newcall1 }; },
        label: function (row) {
          return row.oldcall1 + ' → ' + row.newcall1 + (row.name ? ' (' + row.name + ')' : '');
        },
        payload: function () {
          return {
            oldcall1: $('chng-old').value, newcall1: $('chng-new').value, sitename: $('chng-name').value,
            origoldcall1: (state.extraOrig && state.extraOrig.oldcall1) || ''
          };
        },
        delPayload: function (row) { return { oldcall1: row.oldcall1, newcall1: row.newcall1 }; },
        required: function () {
          return !!(($('chng-old').value || '').trim() && ($('chng-new').value || '').trim() && ($('chng-name').value || '').trim());
        },
        requiredMsg: 'Current call sign, new call sign, and name are required.',
        clearKey: function () { $('chng-old').value = ''; }
      };
    }
    if (kind === 'cloc') {
      return {
        kind: 'cloc', filetype: 'ES', list: 'cloclist', save: 'clocsave', del: 'clocdelete',
        findId: 'cloc-find', listId: 'cloc-list',
        fields: ['cloc-old', 'cloc-new', 'cloc-name'],
        fill: function (row) {
          $('cloc-old').value = row.oldlocation || '';
          $('cloc-new').value = row.newlocation || '';
          $('cloc-name').value = row.name || '';
        },
        origOf: function (row) { return { oldlocation: row.oldlocation, newlocation: row.newlocation }; },
        label: function (row) {
          return row.oldlocation + ' → ' + row.newlocation + (row.name ? ' (' + row.name + ')' : '');
        },
        payload: function () {
          return {
            oldlocation: $('cloc-old').value, newlocation: $('cloc-new').value, sitename: $('cloc-name').value,
            origoldlocation: (state.extraOrig && state.extraOrig.oldlocation) || ''
          };
        },
        delPayload: function (row) { return { oldlocation: row.oldlocation, newlocation: row.newlocation }; },
        required: function () { return !!(($('cloc-old').value || '').trim() && ($('cloc-new').value || '').trim()); },
        requiredMsg: 'Old location and new location are required.',
        clearKey: function () { $('cloc-old').value = ''; }
      };
    }
    return {
      kind: 'ccal', filetype: 'ES', list: 'ccallist', save: 'ccalsave', del: 'ccaldelete',
      findId: 'ccal-find', listId: 'ccal-list',
      fields: ['ccal-old', 'ccal-new'],
      fill: function (row) {
        $('ccal-old').value = row.oldcallsign || '';
        $('ccal-new').value = row.newcallsign || '';
      },
      origOf: function (row) { return { oldcallsign: row.oldcallsign, newcallsign: row.newcallsign }; },
      label: function (row) { return row.oldcallsign + ' → ' + row.newcallsign; },
      payload: function () {
        return {
          oldcallsign: $('ccal-old').value, newcallsign: $('ccal-new').value,
          origoldcallsign: (state.extraOrig && state.extraOrig.oldcallsign) || ''
        };
      },
      delPayload: function (row) { return { oldcallsign: row.oldcallsign, newcallsign: row.newcallsign }; },
      required: function () { return !!(($('ccal-old').value || '').trim() && ($('ccal-new').value || '').trim()); },
      requiredMsg: 'Old call sign and new call sign are required.',
      clearKey: function () { $('ccal-old').value = ''; }
    };
  }

  function fillChngNameFromSite() {
    var call1 = ($('chng-old') && $('chng-old').value || '').trim().toUpperCase();
    var nameEl = $('chng-name');
    if (!call1 || !nameEl || (nameEl.value || '').trim()) return;
    RemIcsApi.pdfEdit('sitesList', { name: state.name, filetype: 'TS' }).then(function (r) {
      if (!r.ok || (nameEl.value || '').trim()) return;
      var sites = r.sites || [];
      for (var i = 0; i < sites.length; i++) {
        if (String(sites[i].key || '').toUpperCase() === call1 && sites[i].name) {
          nameEl.value = String(sites[i].name).toUpperCase();
          return;
        }
      }
    });
  }

  function wireExtraToUp(kind) {
    extraCfg(kind).fields.forEach(function (id) {
      var el = $(id);
      if (!el || el._upWired) return;
      el._upWired = true;
      el.addEventListener('blur', function () {
        el.value = String(el.value || '').trim().toUpperCase();
        if (kind === 'chng' && id === 'chng-old') fillChngNameFromSite();
      });
    });
  }

  function clearExtraForm(kind, doFocus) {
    var cfg = extraCfg(kind);
    cfg.fields.forEach(function (id) { if ($(id)) $(id).value = ''; });
    state.extraOrig = null;
    markClean(kind);
    if (doFocus) firstFocusField(kind);
  }

  function editExtraRow(kind, row) {
    if (!confirmLeave()) return;
    var cfg = extraCfg(kind);
    cfg.fill(row);
    state.extraOrig = cfg.origOf(row);
    markClean(kind);
    firstFocusField(kind);
  }

  function loadExtra(kind) {
    var cfg = extraCfg(kind);
    RemIcsApi.pdfExtra(cfg.list, { name: state.name, filetype: cfg.filetype }).then(function (r) {
      if (!r.ok) { status(r.error || 'Failed'); return; }
      var list = $(cfg.listId);
      list.innerHTML = '';
      (r.rows || []).forEach(function (row) {
        var li = document.createElement('li');
        var a = document.createElement('a');
        a.href = '#';
        a.textContent = cfg.label(row);
        a.addEventListener('click', function (ev) {
          ev.preventDefault();
          editExtraRow(kind, row);
        });
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'bt';
        btn.textContent = 'Del';
        btn.onclick = function () {
          if (!window.confirm('Delete this change record?')) return;
          var body = cfg.delPayload(row);
          body.name = state.name;
          body.filetype = cfg.filetype;
          RemIcsApi.pdfExtra(cfg.del, body).then(function (r) {
            if (!r || !r.ok) {
              var msg = (r && r.error) || 'Delete failed';
              status(msg);
              alert(msg);
              return;
            }
            loadExtra(kind);
          }).catch(function (ex) {
            failStatus(ex);
            alert((ex && ex.message) || String(ex || 'Delete failed'));
          });
        };
        li.appendChild(a);
        li.appendChild(document.createTextNode(' '));
        li.appendChild(btn);
        list.appendChild(li);
      });
      applyListFind(cfg.listId, cfg.findId);
      status((r.rows || []).length + ' change(s)');
      showPanel(kind);
      wireEnterAsTab($(kind + '-form'));
      if (window.RemicsHints) RemicsHints.bindForm($(kind + '-form'), kind, kind + '-field-hint');
      wireExtraToUp(kind);
      if (kind === 'chng') fillChngNameFromSite();
      if (!state.dirtyKind) markClean(kind);
    }).catch(function (ex) { failStatus(ex); });
  }

  function saveExtra(kind, thenNew) {
    var cfg = extraCfg(kind);
    cfg.fields.forEach(function (id) {
      if ($(id)) $(id).value = String($(id).value || '').trim().toUpperCase();
    });
    if (!cfg.required()) { alert(cfg.requiredMsg); firstFocusField(kind); return; }
    var body = cfg.payload();
    body.name = state.name;
    body.filetype = cfg.filetype;
    RemIcsApi.pdfExtra(cfg.save, body).then(function (r) {
      status(r.ok ? 'Saved.' : (r.error || 'Failed'));
      if (!r.ok) return;
      markClean('');
      if (thenNew) {
        clearExtraForm(kind, true);
        loadExtra(kind);
      } else {
        state.extraOrig = null;
        loadExtra(kind);
      }
    }).catch(function (ex) { failStatus(ex); });
  }

  function loadChng() { loadExtra('chng'); }
  function loadCloc() { loadExtra('cloc'); }
  function loadCcal() { loadExtra('ccal'); }

  function loadTitle() {
    status('Loading title...');
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
      wireEnterAsTab($('pdf-panel-title'));
      if (window.RemicsHints) RemicsHints.bindForm($('pdf-panel-title'), 'title', 'title-field-hint');
      markClean('title');
    }).catch(function (ex) { failStatus(ex); });
  }

  function loadSites(keepForm) {
    if (!keepForm) {
      status('Loading sites...');
      show($('site-form'), false);
    }
    RemIcsApi.pdfEdit('sitesList', { name: state.name, filetype: state.filetype }).then(function (r) {
      if (!r.ok) { status(r.error || 'sitesList failed'); return; }
      var list = $('site-list');
      list.innerHTML = '';
      (r.sites || []).forEach(function (s) {
        var li = document.createElement('li');
        var a = document.createElement('a');
        a.href = '#';
        a.textContent = s.key + (s.name ? '  -  ' + s.name : '');
        a.addEventListener('click', function (ev) {
          ev.preventDefault();
          if (!confirmLeave()) return;
          openSite(s.key, false);
        });
        li.appendChild(a);
        list.appendChild(li);
      });
      applyListFind('site-list', 'site-find');
      if (!keepForm) status(listIdleStatus((r.sites || []).length, 'site'));
      showPanel('sites');
    }).catch(function (ex) { failStatus(ex); });
  }

  function setEntityHeading(id, tsText, esText) {
    var el = $(id);
    if (el) el.textContent = state.filetype === 'ES' ? esText : tsText;
  }

  var SITE_LAT_FIELDS = ['latDD', 'latMM', 'latSS', 'lat00', 'latDir'];

  function siteKeyFieldId() {
    return state.filetype === 'ES' ? 'fld-location' : 'fld-call1';
  }

  function siteHasKey() {
    var el = $(siteKeyFieldId());
    return !!(el && String(el.value || '').trim());
  }

  function siteHasLatitude() {
    return SITE_LAT_FIELDS.some(function (k) {
      var el = $('fld-' + k);
      return !!(el && String(el.value || '').trim());
    });
  }

  function updateSiteSaveState() {
    var on = siteHasKey() && siteHasLatitude();
    if ($('site-save')) $('site-save').disabled = !on;
    if ($('site-save-new')) $('site-save-new').disabled = !on;
  }

  function wireSiteSaveValidation() {
    var ids = [siteKeyFieldId()].concat(SITE_LAT_FIELDS.map(function (k) { return 'fld-' + k; }));
    ids.forEach(function (id) {
      var el = $(id);
      if (!el || el._remicsSaveWired) return;
      el._remicsSaveWired = true;
      el.addEventListener('input', updateSiteSaveState);
      el.addEventListener('change', updateSiteSaveState);
    });
    updateSiteSaveState();
  }

  function titleSourceOperator() {
    var el = $('titl-source');
    var fromDom = el ? String(el.value || '').trim() : '';
    if (fromDom) return Promise.resolve(fromDom);
    return RemIcsApi.pdfEdit('titleGet', { name: state.name, filetype: state.filetype }).then(function (r) {
      if (r && r.ok && r.record && r.record.source) return String(r.record.source).trim();
      return '';
    }).catch(function () { return ''; });
  }

  function openSite(key, isNew, asDup) {
    state.siteIsNew = !!isNew;
    var fields = state.filetype === 'ES' ? SITE_ES : SITE_TS;
    if (isNew) {
      var blank = {};
      fields.forEach(function (f) { blank[f] = ''; });
      blank.cmd = 'A';
      if (state.filetype === 'ES') blank.location = '';
      else blank.call1 = key || '';
      function showNewSite(rec) {
        state.siteRec = rec;
        renderFields('site-fields', fields, rec, []);
        setEntityHeading('pdf-site-heading', 'FCSA MICS Terrestrial Site', 'FCSA MICS Earth Station Site');
        showPanel('sites');
        show($('site-form'), true);
        status('New site');
        afterFormReady('site', true);
      }
      titleSourceOperator().then(function (oper) {
        if (oper) blank.oper = oper;
        showNewSite(blank);
      });
      return;
    }
    showPanel('sites');
    RemIcsApi.pdfEdit('siteGet', { name: state.name, filetype: state.filetype, key: key }).then(function (r) {
      if (!r.ok) { status(r.error || 'siteGet failed'); return; }
      state.siteRec = r.record || {};
      renderFields('site-fields', fields, state.siteRec, state.filetype === 'ES' ? ['location'] : ['call1']);
      setEntityHeading('pdf-site-heading', 'FCSA MICS Terrestrial Site', 'FCSA MICS Earth Station Site');
      showPanel('sites');
      show($('site-form'), true);
      if (asDup) beginDuplicate('site');
      else afterFormReady('site', false);
    }).catch(function (ex) { failStatus(ex); });
  }

  function loadAntes(keepForm) {
    var hop = selectedHop('ante');
    var siteKey = state.filetype === 'ES'
      ? (($('ante-site-filter') && $('ante-site-filter').value) || '')
      : hopSiteKey('ante');
    if (!keepForm) {
      status('Loading antennas...');
      show($('ante-form'), false);
    }
    RemIcsApi.pdfEdit('antesList', { name: state.name, filetype: state.filetype, siteKey: siteKey }).then(function (r) {
      if (!r.ok) { status(r.error || 'antesList failed'); return; }
      var rows = r.antes || [];
      if (hop) {
        rows = rows.filter(function (a) {
          return a.call1 === hop.call1 && a.call2 === hop.call2 && a.bndcde === hop.bndcde;
        });
      }
      var list = $('ante-list');
      list.innerHTML = '';
      rows.forEach(function (a) {
        var li = document.createElement('li');
        var link = document.createElement('a');
        link.href = '#';
        link.textContent = a.key;
        link.addEventListener('click', function (ev) {
          ev.preventDefault();
          if (!confirmLeave()) return;
          openAnte(a, false);
        });
        li.appendChild(link);
        list.appendChild(li);
      });
      applyListFind('ante-list', 'ante-find');
      if (!keepForm) status(listIdleStatus(rows.length, 'antenna'));
      showPanel('antes');
    }).catch(function (ex) { failStatus(ex); });
  }

  function openAnte(row, isNew, asDup) {
    state.anteIsNew = !!isNew;
    row = row || {};
    var fields = state.filetype === 'ES' ? ANTE_ES : ANTE_TS;
    if (isNew) {
      var blank = {};
      fields.forEach(function (f) { blank[f] = ''; });
      if (state.filetype === 'ES') {
        blank.location = row.location || ($('ante-site-filter') && $('ante-site-filter').value.trim()) || '';
        blank.cmd = 'A';
      } else {
        var hop = hopKeysForNew('ante');
        blank.call1 = row.call1 || hop.call1 || '';
        blank.call2 = row.call2 || hop.call2 || '';
        blank.bndcde = row.bndcde || hop.bndcde || '';
        blank.cmd = 'A';
        blank.offazm = 'N';
      }
      function showNewAnte(rec) {
        state.anteRec = rec;
        renderFields('ante-fields', fields, rec, anteReadonlyKeysForNew(rec));
        setEntityHeading('pdf-ante-heading', 'FCSA MICS Terrestrial Antenna', 'FCSA MICS Earth Station Antenna');
        showPanel('antes');
        show($('ante-form'), true);
        status('New antenna');
        afterFormReady('ante', true);
      }
      if (state.filetype === 'TS' && !blank.anum && blank.call1 && blank.call2 && blank.bndcde) {
        suggestNextTsAnum(blank.call1, blank.call2, blank.bndcde).then(function (next) {
          if (next) blank.anum = next;
          showNewAnte(blank);
        });
      } else {
        showNewAnte(blank);
      }
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
    showPanel('antes');
    if (state.filetype === 'ES' && row.location) {
      writeFilters({ esSite: row.location });
      if ($('ante-site-filter')) $('ante-site-filter').value = row.location;
    } else if (state.filetype === 'TS' && row.call1) {
      writeFilters({ tsHop: (row.call1 || '') + '|' + (row.call2 || '') + '|' + (row.bndcde || '') });
      loadHopSelect('ante').then(function () { loadAntes(true); });
    }
    RemIcsApi.pdfEdit('anteGet', params).then(function (r) {
      if (!r.ok) { status(r.error || 'anteGet failed'); return; }
      state.anteRec = r.record || {};
      renderFields('ante-fields', fields, state.anteRec, state.filetype === 'ES' ? ['location', 'call1'] : ['call1', 'call2', 'bndcde', 'anum']);
      setEntityHeading('pdf-ante-heading', 'FCSA MICS Terrestrial Antenna', 'FCSA MICS Earth Station Antenna');
      showPanel('antes');
      show($('ante-form'), true);
      if (asDup) beginDuplicate('ante');
      else afterFormReady('ante', false);
    }).catch(function (ex) { failStatus(ex); });
  }

  function loadChans(keepForm) {
    var hop = selectedHop('chan');
    var siteKey = state.filetype === 'ES'
      ? (($('chan-site-filter') && $('chan-site-filter').value) || '')
      : hopSiteKey('chan');
    if (!keepForm) {
      status('Loading channels...');
      show($('chan-form'), false);
    }
    RemIcsApi.pdfEdit('chansList', { name: state.name, filetype: state.filetype, siteKey: siteKey }).then(function (r) {
      if (!r.ok) { status(r.error || 'chansList failed'); return; }
      var rows = r.chans || [];
      if (hop) {
        rows = rows.filter(function (c) {
          return c.call1 === hop.call1 && c.call2 === hop.call2 && c.bndcde === hop.bndcde;
        });
      }
      var list = $('chan-list');
      list.innerHTML = '';
      rows.forEach(function (c) {
        var li = document.createElement('li');
        var link = document.createElement('a');
        link.href = '#';
        link.textContent = c.key;
        link.addEventListener('click', function (ev) {
          ev.preventDefault();
          if (!confirmLeave()) return;
          openChan(c, false);
        });
        li.appendChild(link);
        list.appendChild(li);
      });
      applyListFind('chan-list', 'chan-find');
      if (!keepForm) status(listIdleStatus(rows.length, 'channel'));
      showPanel('chans');
    }).catch(function (ex) { failStatus(ex); });
  }

  function fillChanSiteGlance() {
    if (state.filetype !== 'TS') return;
    var c1 = ($('fld-call1') && $('fld-call1').value) || '';
    var c2 = ($('fld-call2') && $('fld-call2').value) || '';
    RemIcsApi.pdfEdit('sitesList', { name: state.name, filetype: 'TS' }).then(function (r) {
      var sites = (r && r.sites) || [];
      function find(key) {
        key = String(key || '').toUpperCase();
        for (var i = 0; i < sites.length; i++) {
          if (String(sites[i].key || '').toUpperCase() === key) return sites[i];
        }
        return null;
      }
      function apply(prefix, site) {
        var n = $('chan-' + prefix + '-name');
        var p = $('chan-' + prefix + '-prov');
        var o = $('chan-' + prefix + '-oper');
        if (n) n.value = site ? (site.name || '') : '';
        if (p) p.value = site ? (site.prov || '') : '';
        if (o) o.value = site ? (site.oper || '') : '';
      }
      apply('local', find(c1));
      apply('remote', find(c2));
    }).catch(function (ex) { failStatus(ex); });
  }

  function asmxBody(r) {
    var body = r && r.body != null ? String(r.body) : '';
    return body.replace(/^"+|"+$/g, '').trim();
  }

  function setVal(id, v) {
    var el = $(id);
    if (el) el.value = v || '';
  }

  function fillEsSiteGlance() {
    if (state.filetype !== 'ES') return;
    var loc = (($('fld-location') && $('fld-location').value) || '').trim().toUpperCase();
    setVal('es-glance-location', loc);
    RemIcsApi.pdfEdit('sitesList', { name: state.name, filetype: 'ES' }).then(function (r) {
      var sites = (r && r.sites) || [];
      var site = null;
      for (var i = 0; i < sites.length; i++) {
        if (String(sites[i].key || '').toUpperCase() === loc) {
          site = sites[i];
          break;
        }
      }
      setVal('es-glance-name', site ? site.name : '');
      setVal('es-glance-prov', site ? site.prov : '');
      setVal('es-glance-oper', site ? site.oper : '');
    }).catch(function (ex) { failStatus(ex); });
  }

  function fillEsAnteGlance() {
    if (state.filetype !== 'ES') return;
    var loc = (($('fld-location') && $('fld-location').value) || '').trim();
    var call1 = (($('fld-call1') && $('fld-call1').value) || '').trim();
    setVal('es-ante-call1', call1);
    if (!loc || !call1) {
      setVal('es-ante-txband', '');
      setVal('es-ante-rxband', '');
      setVal('es-ante-acodetx', '');
      setVal('es-ante-acoderx', '');
      return;
    }
    RemIcsApi.pdfEdit('anteGet', { name: state.name, filetype: 'ES', location: loc, call1: call1 }).then(function (r) {
      var rec = (r && r.ok && r.record) ? r.record : {};
      setVal('es-ante-txband', rec.txband);
      setVal('es-ante-rxband', rec.rxband);
      setVal('es-ante-acodetx', rec.acodetx);
      setVal('es-ante-acoderx', rec.acoderx);
    }).catch(function (ex) { failStatus(ex); });
  }

  function ensureTsSite(call) {
    call = String(call || '').trim().toUpperCase();
    if (!call) return;
    RemIcsApi.dsAsmx('Ttsmenu/TwsTStree.asmx', 'chkSite', { pdfname: state.name, call1: call }).then(function (r) {
      if (asmxBody(r) !== 'f') return;
      if (!window.confirm('No site record found in the database or in the current file for:\n' + call +
          '\nDo you want to add it?')) return;
      alert('You must edit this site record later to enter required information');
      RemIcsApi.dsAsmx('Ttsmenu/TwsTStree.asmx', 'addSite', { pdfname: state.name, call1: call }).then(function (r2) {
        var ok = asmxBody(r2);
        if (!r2.ok || ok.indexOf('ERROR') === 0) {
          alert('Error adding new site');
          return;
        }
        notifyTreeRefresh('site', { call1: call });
        fillChanSiteGlance();
      }).catch(function (ex) { failStatus(ex); });
    }).catch(function (ex) { failStatus(ex); });
  }

  function ensureEsSite(location) {
    location = String(location || '').trim().toUpperCase();
    if (!location) return;
    RemIcsApi.dsAsmx('Tesmenu/TwsESTree.asmx', 'chkSite', { pdfname: state.name, location: location }).then(function (r) {
      if (asmxBody(r) !== 'f') {
        fillEsSiteGlance();
        return;
      }
      if (!window.confirm('No site record found in the database or in the current file for:\n' + location +
          '\nDo you want to add it?')) {
        setVal('fld-location', '');
        fillEsSiteGlance();
        return;
      }
      alert('You must edit this site record later to enter required information');
      RemIcsApi.dsAsmx('Tesmenu/TwsESTree.asmx', 'addSite', { pdfname: state.name, location: location }).then(function (r2) {
        var ok = asmxBody(r2);
        if (!r2.ok || ok.indexOf('ERROR') === 0) {
          alert('Error adding new site');
          return;
        }
        notifyTreeRefresh('site', { location: location });
        fillEsSiteGlance();
        loadEsSiteSelect('ante-site-filter');
        loadEsSiteSelect('chan-site-filter');
        loadEsSiteSelect('azim-site-filter');
      }).catch(function (ex) { failStatus(ex); });
    }).catch(function (ex) { failStatus(ex); });
  }

  function ensureEsAntenna(location, call1) {
    location = String(location || '').trim().toUpperCase();
    call1 = String(call1 || '').trim().toUpperCase();
    if (!location || !call1) return;
    RemIcsApi.dsAsmx('Tesmenu/TwsESTree.asmx', 'chkAntenna', {
      pdfname: state.name, location: location, call1: call1
    }).then(function (r) {
      if (asmxBody(r) !== 'f') {
        fillEsAnteGlance();
        return;
      }
      alert('No antenna record found in the database or in the current file for:\n' +
        location + '-' + call1 + '\nYou must add the antenna before adding this channel');
      setVal('fld-call1', '');
      fillEsAnteGlance();
    }).catch(function (ex) { failStatus(ex); });
  }

  function wireChanSiteGlance() {
    ['fld-call1', 'fld-call2'].forEach(function (id) {
      var el = $(id);
      if (!el || el._chanGlanceWired) return;
      el._chanGlanceWired = true;
      el.addEventListener('change', fillChanSiteGlance);
      el.addEventListener('blur', function () {
        fillChanSiteGlance();
        if (state.chanIsNew && state.filetype === 'TS') ensureTsSite(el.value);
      });
    });
  }

  function wireEsLocationCall() {
    var loc = $('fld-location');
    if (loc && !loc._esGlanceWired) {
      loc._esGlanceWired = true;
      loc.addEventListener('change', function () {
        loc.value = String(loc.value || '').toUpperCase();
        fillEsSiteGlance();
        if (state.filetype === 'ES' && (state.anteIsNew || state.chanIsNew)) ensureEsSite(loc.value);
        if (state.chanIsNew) fillEsAnteGlance();
      });
    }
    var c1 = $('fld-call1');
    if (c1 && !c1._esGlanceWired) {
      c1._esGlanceWired = true;
      c1.addEventListener('change', function () {
        c1.value = String(c1.value || '').toUpperCase();
        if (state.chanIsNew && state.filetype === 'ES') {
          ensureEsAntenna(($('fld-location') && $('fld-location').value) || '', c1.value);
        } else {
          fillEsAnteGlance();
        }
      });
    }
  }

  function afterAnteRender() {
    if (state.filetype !== 'ES') return;
    fillEsSiteGlance();
    wireEsLocationCall();
  }

  function afterChanRender() {
    if (state.filetype === 'ES') {
      fillEsSiteGlance();
      fillEsAnteGlance();
      wireEsLocationCall();
      return;
    }
    fillChanSiteGlance();
    wireChanSiteGlance();
  }

  function loadEsSiteSelect(filterId) {
    var sel = $(filterId);
    if (!sel || state.filetype !== 'ES') return Promise.resolve();
    var filters = readFilters();
    var prev = sel.value || filters.esSite || '';
    // U2-2: prefer first site until the user has chosen a filter for this file.
    var siteChosen = Object.prototype.hasOwnProperty.call(filters, 'esSite') || !!sel.value;
    return RemIcsApi.pdfEdit('sitesList', { name: state.name, filetype: 'ES' }).then(function (r) {
      if (!r || !r.ok) {
        status((r && r.error) || 'sitesList failed');
        return;
      }
      var sites = (r && r.sites) || [];
      sel.innerHTML = '';
      addOption(sel, '', '(all sites)');
      sites.forEach(function (s) {
        addOption(sel, s.key || '', (s.key || '') + (s.name ? '  -  ' + s.name : ''));
      });
      if (prev) {
        sel.value = prev;
      } else if (!siteChosen && sites.length) {
        sel.value = sites[0].key || '';
      }
      writeFilters({ esSite: sel.value || '' });
    }).catch(function (ex) { failStatus(ex); });
  }

  function openChan(row, isNew, asDup) {
    state.chanIsNew = !!isNew;
    row = row || {};
    var fields = state.filetype === 'ES' ? CHAN_ES : CHAN_TS;
    if (isNew) {
      var blank = {};
      fields.forEach(function (f) { blank[f] = ''; });
      if (state.filetype === 'ES') {
        blank.location = row.location || ($('chan-site-filter') && $('chan-site-filter').value.trim()) || '';
        blank.call1 = row.call1 || '';
        blank.cmd = 'A';
      } else {
        var hop = hopKeysForNew('chan');
        blank.call1 = row.call1 || hop.call1 || '';
        blank.call2 = row.call2 || hop.call2 || '';
        blank.bndcde = row.bndcde || hop.bndcde || '';
        blank.cmd = 'A';
        blank.atpccde = '0.0';
      }
      state.chanRec = blank;
      renderFields('chan-fields', fields, blank, chanReadonlyKeysForNew(blank));
      setEntityHeading('pdf-chan-heading', 'FCSA MICS Terrestrial Channel', 'FCSA MICS Earth Station Channel');
      showPanel('chans');
      show($('chan-form'), true);
      status('New channel');
      afterFormReady('chan', true);
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
    showPanel('chans');
    if (state.filetype === 'ES' && row.location) {
      writeFilters({ esSite: row.location });
      if ($('chan-site-filter')) $('chan-site-filter').value = row.location;
    } else if (state.filetype === 'TS' && row.call1) {
      writeFilters({ tsHop: (row.call1 || '') + '|' + (row.call2 || '') + '|' + (row.bndcde || '') });
      loadHopSelect('chan').then(function () { loadChans(true); });
    }
    RemIcsApi.pdfEdit('chanGet', params).then(function (r) {
      if (!r.ok) { status(r.error || 'chanGet failed'); return; }
      state.chanRec = r.record || {};
      renderFields('chan-fields', fields, state.chanRec, state.filetype === 'ES' ? ['location', 'call1', 'chid'] : ['call1', 'call2', 'bndcde', 'chid']);
      setEntityHeading('pdf-chan-heading', 'FCSA MICS Terrestrial Channel', 'FCSA MICS Earth Station Channel');
      showPanel('chans');
      show($('chan-form'), true);
      if (asDup) beginDuplicate('chan');
      else afterFormReady('chan', false);
    }).catch(function (ex) { failStatus(ex); });
  }

  function loadAzims(keepForm) {
    if (!keepForm) {
      status('Loading azimuths...');
      show($('azim-form'), false);
    }
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
          if (!confirmLeave()) return;
          openAzim(a, false);
        });
        li.appendChild(link);
        list.appendChild(li);
      });
      applyListFind('azim-list', 'azim-find');
      if (!keepForm) status(listIdleStatus((r.azims || []).length, 'azimuth'));
      showPanel('azims');
    }).catch(function (ex) { failStatus(ex); });
  }

  function openAzim(row, isNew, asDup) {
    state.azimIsNew = !!isNew;
    row = row || {};
    if (isNew) {
      var blank = {};
      AZIM_ES.forEach(function (f) { blank[f] = ''; });
      blank.location = row.location || ($('azim-site-filter') && $('azim-site-filter').value.trim()) || '';
      blank.call1 = row.call1 || ($('azim-call1-filter') && $('azim-call1-filter').value.trim()) || '';
      blank.cmd = 'A';
      state.azimRec = blank;
      renderFields('azim-fields', AZIM_ES, blank, azimReadonlyKeysForNew(blank));
      showPanel('azims');
      show($('azim-form'), true);
      status('New azimuth');
      afterFormReady('azim', true);
      return;
    }
    showPanel('azims');
    if (row.location) {
      writeFilters({ esSite: row.location, azimCall1: row.call1 || '' });
      if ($('azim-site-filter')) $('azim-site-filter').value = row.location;
      if ($('azim-call1-filter') && row.call1) $('azim-call1-filter').value = row.call1;
    }
    RemIcsApi.pdfEdit('azimGet', {
      name: state.name, filetype: 'ES',
      location: row.location, call1: row.call1, azim: row.azim
    }).then(function (r) {
      if (!r.ok) { status(r.error || 'azimGet failed'); return; }
      state.azimRec = r.record || {};
      renderFields('azim-fields', AZIM_ES, state.azimRec, ['location', 'call1', 'azim']);
      showPanel('azims');
      show($('azim-form'), true);
      if (asDup) beginDuplicate('azim');
      else afterFormReady('azim', false);
    }).catch(function (ex) { failStatus(ex); });
  }

  function splitTreeKey(value) {
    return (value || '').split('.');
  }

  function anteDefaultsFromTreeKey(value) {
    var parts = splitTreeKey(value);
    if (!parts.length) return {};
    var p = parts[0];
    if (state.filetype === 'ES') {
      if (p === 's') return { location: parts[2] || '' };
      return {};
    }
    if (p === 'b' || p === 'a') {
      return { call1: parts[2] || '', call2: parts[3] || '', bndcde: parts[4] || '' };
    }
    return {};
  }

  function anteReadonlyKeysForNew(defaults) {
    defaults = defaults || {};
    if (state.filetype === 'ES') {
      return defaults.location ? ['location'] : [];
    }
    var ro = [];
    if (defaults.call1) ro.push('call1');
    if (defaults.call2) ro.push('call2');
    if (defaults.bndcde) ro.push('bndcde');
    return ro;
  }

  function chanDefaultsFromTreeKey(value) {
    var parts = splitTreeKey(value);
    if (!parts.length) return {};
    var p = parts[0];
    if (state.filetype === 'ES') {
      if (p === 'n') return { location: parts[2] || '', call1: parts[3] || '' };
      return {};
    }
    if (p === 'h' || p === 'c') {
      return { call1: parts[2] || '', call2: parts[3] || '', bndcde: parts[4] || '' };
    }
    return {};
  }

  function chanReadonlyKeysForNew(defaults) {
    defaults = defaults || {};
    if (state.filetype === 'ES') {
      var roEs = [];
      if (defaults.location) roEs.push('location');
      if (defaults.call1) roEs.push('call1');
      return roEs;
    }
    var ro = [];
    if (defaults.call1) ro.push('call1');
    if (defaults.call2) ro.push('call2');
    if (defaults.bndcde) ro.push('bndcde');
    return ro;
  }

  function azimDefaultsFromTreeKey(value) {
    var parts = splitTreeKey(value);
    if (!parts.length) return {};
    var p = parts[0];
    if (p === 'm' || p === 'n') {
      return { location: parts[2] || '', call1: parts[3] || '' };
    }
    return {};
  }

  function azimReadonlyKeysForNew(defaults) {
    defaults = defaults || {};
    var ro = [];
    if (defaults.location) ro.push('location');
    if (defaults.call1) ro.push('call1');
    return ro;
  }

  function openNewExtraPanel(panel) {
    showPanel(panel);
    if (panel === 'chng' || panel === 'cloc' || panel === 'ccal') {
      loadExtra(panel);
      clearExtraForm(panel, true);
    }
  }

  function openFromTreeKey(value, panel, asDup) {
    var parts = splitTreeKey(value);
    var p = parts[0];
    if (panel === 'title' || p === 't') {
      loadTitle();
      return;
    }
    if (panel === 'sites' || p === 'd') {
      openSite(parts[2] || '', false, asDup);
      return;
    }
    if (panel === 'antes' || p === 'a') {
      if (state.filetype === 'ES') {
        openAnte({ location: parts[2] || '', call1: parts[3] || '' }, false, asDup);
      } else {
        openAnte({
          call1: parts[2] || '',
          call2: parts[3] || '',
          bndcde: parts[4] || '',
          anum: parts[5] || ''
        }, false, asDup);
      }
      return;
    }
    if (panel === 'chans' || p === 'h' || p === 'c') {
      if (state.filetype === 'ES') {
        openChan({ location: parts[2] || '', call1: parts[3] || '', chid: parts[4] || '' }, false, asDup);
      } else {
        openChan({
          call1: parts[2] || '',
          call2: parts[3] || '',
          bndcde: parts[4] || '',
          chid: parts[5] || ''
        }, false, asDup);
      }
      return;
    }
    if (panel === 'azims' || p === 'm') {
      openAzim({ location: parts[2] || '', call1: parts[3] || '', azim: parts[4] || '' }, false, asDup);
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
    show($('ante-ts-hop'), state.filetype === 'TS');
    show($('ante-es-filter'), state.filetype === 'ES');
    show($('chan-ts-hop'), state.filetype === 'TS');
    show($('chan-es-filter'), state.filetype === 'ES');
    wireListFind('site-list', 'site-find');
    wireListFind('ante-list', 'ante-find');
    wireListFind('chan-list', 'chan-find');
    wireListFind('azim-list', 'azim-find');
    wireListFind('links-list', 'links-find');
    if (state.filetype === 'ES') {
      loadEsSiteSelect('ante-site-filter');
      loadEsSiteSelect('chan-site-filter');
      loadEsSiteSelect('azim-site-filter');
      if ($('azim-call1-filter') && readFilters().azimCall1) {
        $('azim-call1-filter').value = readFilters().azimCall1;
      }
    }

    $('pdf-edit-back').onclick = goTreeSafe;
    if ($('titl-cancel')) $('titl-cancel').onclick = goTreeSafe;
    if ($('titl-source-lookup')) {
      $('titl-source-lookup').onclick = function () {
        if (global.RemicsLookup) {
          RemicsLookup.open('Operator', 'titl-source', { mandatory: true });
        }
      };
    }
    document.querySelectorAll('#pdf-panel-nav [data-panel]').forEach(function (btn) {
      btn.onclick = function () {
        if (!confirmLeave()) return;
        markClean('');
        var p = btn.getAttribute('data-panel');
        if (p === 'title') loadTitle();
        else if (p === 'sites') loadSites();
        else if (p === 'antes') {
          if (state.filetype === 'ES') loadEsSiteSelect('ante-site-filter').then(loadAntes);
          else loadHopSelect('ante').then(loadAntes);
        } else if (p === 'chans') {
          if (state.filetype === 'ES') loadEsSiteSelect('chan-site-filter').then(loadChans);
          else loadHopSelect('chan').then(loadChans);
        } else if (p === 'azims') loadEsSiteSelect('azim-site-filter').then(loadAzims);
        else if (p === 'links') loadLinks();
        else if (p === 'chng') loadChng();
        else if (p === 'cloc') loadCloc();
        else if (p === 'ccal') loadCcal();
      };
    });

    if ($('links-refresh')) $('links-refresh').onclick = loadLinks;
    if ($('links-add')) $('links-add').onclick = addPdfLink;
    if ($('links-help')) {
      $('links-help').onclick = function () {
        window.open(RemIcsApi.micsRoot() + 'micshelp/separatefiles/tsLink.aspx', 'WndHelp',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
      };
    }
    if ($('pdf-edit-back-links')) $('pdf-edit-back-links').onclick = goTreeSafe;
    if ($('chng-refresh')) $('chng-refresh').onclick = function () { if (confirmLeave()) { markClean(''); loadChng(); } };
    if ($('chng-save')) $('chng-save').onclick = function () { saveExtra('chng', false); };
    if ($('chng-save-new')) $('chng-save-new').onclick = function () { saveExtra('chng', true); };
    if ($('chng-dup')) $('chng-dup').onclick = function () {
      if (!confirmLeave()) return;
      extraCfg('chng').clearKey();
      state.extraOrig = null;
      markClean('chng');
      firstFocusField('chng');
    };
    if ($('chng-btn-new')) $('chng-btn-new').onclick = function () {
      if (!confirmLeave()) return;
      clearExtraForm('chng', true);
    };
    wireListFind('chng-list', 'chng-find');
    if ($('chng-help')) {
      $('chng-help').onclick = function () {
        window.open(RemIcsApi.micsRoot() + 'micshelp/separatefiles/tsChangeofCallSign.aspx', 'WndHelp',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
      };
    }
    if ($('pdf-edit-back-chng')) $('pdf-edit-back-chng').onclick = goTreeSafe;
    if ($('cloc-refresh')) $('cloc-refresh').onclick = function () { if (confirmLeave()) { markClean(''); loadCloc(); } };
    if ($('cloc-save')) $('cloc-save').onclick = function () { saveExtra('cloc', false); };
    if ($('cloc-save-new')) $('cloc-save-new').onclick = function () { saveExtra('cloc', true); };
    if ($('cloc-dup')) $('cloc-dup').onclick = function () {
      if (!confirmLeave()) return;
      extraCfg('cloc').clearKey();
      state.extraOrig = null;
      markClean('cloc');
      firstFocusField('cloc');
    };
    if ($('cloc-btn-new')) $('cloc-btn-new').onclick = function () {
      if (!confirmLeave()) return;
      clearExtraForm('cloc', true);
    };
    wireListFind('cloc-list', 'cloc-find');
    if ($('cloc-help')) {
      $('cloc-help').onclick = function () {
        window.open(RemIcsApi.micsRoot() + 'micshelp/separatefiles/esChangeofLocation.aspx', 'WndHelp',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
      };
    }
    if ($('pdf-edit-back-cloc')) $('pdf-edit-back-cloc').onclick = goTreeSafe;
    if ($('ccal-refresh')) $('ccal-refresh').onclick = function () { if (confirmLeave()) { markClean(''); loadCcal(); } };
    if ($('ccal-save')) $('ccal-save').onclick = function () { saveExtra('ccal', false); };
    if ($('ccal-save-new')) $('ccal-save-new').onclick = function () { saveExtra('ccal', true); };
    if ($('ccal-dup')) $('ccal-dup').onclick = function () {
      if (!confirmLeave()) return;
      extraCfg('ccal').clearKey();
      state.extraOrig = null;
      markClean('ccal');
      firstFocusField('ccal');
    };
    if ($('ccal-btn-new')) $('ccal-btn-new').onclick = function () {
      if (!confirmLeave()) return;
      clearExtraForm('ccal', true);
    };
    wireListFind('ccal-list', 'ccal-find');
    if ($('ccal-help')) {
      $('ccal-help').onclick = function () {
        window.open(RemIcsApi.micsRoot() + 'micshelp/separatefiles/esChangeofCallSign.aspx', 'WndHelp',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
      };
    }
    if ($('pdf-edit-back-ccal')) $('pdf-edit-back-ccal').onclick = goTreeSafe;

    $('titl-save').onclick = function () {
      RemIcsApi.pdfEdit('titleSave', {
        name: state.name,
        filetype: state.filetype,
        namef: $('titl-namef').value,
        source: $('titl-source').value,
        descr: $('titl-descr').value
      }).then(function (r) {
        status(r.ok ? 'Title saved (validated reset).' : (r.error || 'Save failed'));
        if (r.ok) {
          loadTitle();
          if (window.RemicsHints) RemicsHints.setNext('title', { filetype: state.filetype });
        }
      }).catch(function (ex) { failStatus(ex); });
    };

    $('site-new').onclick = function () {
      if (!confirmLeave()) return;
      openSite('', true);
    };
    $('site-refresh').onclick = function () {
      if (!confirmLeave()) return;
      markClean('');
      loadSites();
    };
    $('site-cancel').onclick = function () { closeEntityForm('site'); };
    function saveSite(thenNew) {
      if ($('site-save') && $('site-save').disabled) return;
      var rec = collectFields('site-fields');
      if (state.siteIsNew && state.filetype === 'TS' && !(rec.call1 || '').trim()) {
        alert('Call Sign Local is required for a new site.');
        var callEl = $('fld-call1');
        if (callEl) callEl.focus();
        return;
      }
      if (state.siteIsNew && state.filetype === 'ES' && !(rec.location || '').trim()) {
        alert('Location Code is required for a new site.');
        var locEl = $('fld-location');
        if (locEl) locEl.focus();
        return;
      }
      if (!(rec.cmd || '').trim()) rec.cmd = 'A';
      RemIcsApi.pdfEdit(state.siteIsNew ? 'siteNew' : 'siteSave', {
        name: state.name, filetype: state.filetype, record: JSON.stringify(rec)
      }).then(function (r) {
        if (r.ok || r.partialOk) {
          status('Site saved.');
          markClean('');
          notifyTreeRefresh('site', rec);
          var siteCount = ($('site-list') && $('site-list').querySelectorAll('li').length) || 0;
          if (state.siteIsNew) siteCount += 1;
          if (window.RemicsHints) RemicsHints.setNext('site', { filetype: state.filetype, siteCount: siteCount });
          if (thenNew) {
            loadSites(true);
            openSite('', true);
          } else {
            loadSites(true);
            openSite((state.filetype === 'ES' ? rec.location : rec.call1) || '', false);
          }
        } else {
          status(r.error || 'Save failed');
        }
      }).catch(function (ex) { failStatus(ex); });
    }
    $('site-save').onclick = function () { saveSite(false); };
    if ($('site-save-new')) $('site-save-new').onclick = function () { saveSite(true); };
    if ($('site-dup')) $('site-dup').onclick = function () { beginDuplicate('site'); };

    function startNewAnte() {
      if (!confirmLeave()) return;
      if (state.filetype === 'ES') {
        openAnte({ location: ($('ante-site-filter') && $('ante-site-filter').value.trim()) || '' }, true);
      } else {
        openAnte(hopKeysForNew('ante'), true);
      }
    }
    if ($('ante-refresh')) $('ante-refresh').onclick = function () {
      if (!confirmLeave()) return;
      markClean('');
      loadAntes();
    };
    if ($('ante-refresh-es')) $('ante-refresh-es').onclick = function () {
      if (!confirmLeave()) return;
      markClean('');
      loadAntes();
    };
    if ($('ante-new')) $('ante-new').onclick = startNewAnte;
    if ($('ante-new-es')) $('ante-new-es').onclick = startNewAnte;
    if ($('ante-site-filter')) {
      $('ante-site-filter').onchange = function () {
        writeFilters({ esSite: this.value || '' });
        loadAntes();
      };
    }
    if ($('ante-link-select')) {
      $('ante-link-select').onchange = function () {
        writeFilters({ tsHop: this.value || '' });
        show($('ante-new-hop'), $('ante-link-select').value === '__new__');
        loadAntes();
      };
    }
    $('ante-cancel').onclick = function () { closeEntityForm('ante'); };
    if ($('ante-dup')) $('ante-dup').onclick = function () { beginDuplicate('ante'); };
    function saveAnte(thenNew) {
      var rec = collectFields('ante-fields');
      if (state.anteIsNew) {
        if (state.filetype === 'TS') {
          if (!(rec.call1 || '').trim()) {
            alert('Call Sign Local is required.');
            var c1 = $('fld-call1');
            if (c1) c1.focus();
            return;
          }
          if (!(rec.call2 || '').trim()) {
            alert('Call Sign Remote is required.');
            var c2 = $('fld-call2');
            if (c2) c2.focus();
            return;
          }
          if (!(rec.bndcde || '').trim()) {
            alert('Band Code is required.');
            var bd = $('fld-bndcde');
            if (bd) bd.focus();
            return;
          }
          if (!(rec.anum || '').trim()) {
            alert('Antenna No is required.');
            var an = $('fld-anum');
            if (an) an.focus();
            return;
          }
          var anum = parseInt(rec.anum, 10);
          if (isNaN(anum) || anum < 1 || anum > 99) {
            alert('Antenna No must be between 1 and 99.');
            return;
          }
          if (!(rec.acode || '').trim()) {
            alert('Antenna Code is required. Use Find... to search by manufacturer, model, or description.');
            var ac = $('fld-acode');
            if (ac) ac.focus();
            return;
          }
          if (rec.aht) {
            var ht = parseFloat(rec.aht);
            if (isNaN(ht) || ht < 0 || ht > 1000) {
              alert('Height must be between 0 and 1000 m.');
              return;
            }
          }
        } else {
          if (!(rec.location || '').trim()) {
            alert('Location Code is required.');
            var loc = $('fld-location');
            if (loc) loc.focus();
            return;
          }
          if (!(rec.call1 || '').trim()) {
            alert('You must enter a Call Sign to continue');
            var esC1 = $('fld-call1');
            if (esC1) esC1.focus();
            return;
          }
          if (!(rec.txband || '').trim() && !(rec.rxband || '').trim()) {
            alert('You must enter a TX or RX Band to continue');
            var tb = $('fld-txband');
            if (tb) tb.focus();
            return;
          }
          if ((rec.txband || '').trim() && !(rec.acodetx || '').trim()) {
            alert('You must enter a TX Antenna Code to continue');
            var txc = $('fld-acodetx');
            if (txc) txc.focus();
            return;
          }
          if ((rec.rxband || '').trim() && !(rec.acoderx || '').trim()) {
            alert('You must enter an RX Antenna Code to continue');
            var rxc = $('fld-acoderx');
            if (rxc) rxc.focus();
            return;
          }
          if (rec.aht) {
            var esHt = parseFloat(rec.aht);
            if (isNaN(esHt) || esHt < 0 || esHt > 1000) {
              alert('Antenna Height must be between 0 and 1000 m.');
              return;
            }
          }
        }
      }
      if (!(rec.cmd || '').trim()) rec.cmd = 'A';
      if (state.filetype === 'TS' && !(rec.acode || '').trim()) {
        alert('Antenna Code is required. Use Find... to search by manufacturer, model, or description.');
        var acNeed = $('fld-acode');
        if (acNeed) acNeed.focus();
        return;
      }
      RemIcsApi.pdfEdit(state.anteIsNew ? 'anteNew' : 'anteSave', {
        name: state.name, filetype: state.filetype, record: JSON.stringify(rec)
      }).then(function (r) {
        status(r.ok ? 'Antenna saved.' : (r.error || 'Save failed'));
        if (r.ok) {
          markClean('');
          if (window.RemicsHints) RemicsHints.setNext('ante', { filetype: state.filetype });
          notifyTreeRefresh('ante', rec);
          if (thenNew) {
            loadHopSelect('ante').then(function () { loadAntes(true); });
            openAnte(contextForNew('ante', rec), true);
          } else {
            loadHopSelect('ante').then(function () { loadAntes(true); });
            openAnte(rec, false);
          }
        }
      }).catch(function (ex) { failStatus(ex); });
    }
    $('ante-save').onclick = function () { saveAnte(false); };
    if ($('ante-save-new')) $('ante-save-new').onclick = function () { saveAnte(true); };

    function startNewChan() {
      if (!confirmLeave()) return;
      if (state.filetype === 'ES') {
        openChan({ location: ($('chan-site-filter') && $('chan-site-filter').value.trim()) || '' }, true);
      } else {
        openChan(hopKeysForNew('chan'), true);
      }
    }
    if ($('chan-refresh')) $('chan-refresh').onclick = function () {
      if (!confirmLeave()) return;
      markClean('');
      loadChans();
    };
    if ($('chan-refresh-es')) $('chan-refresh-es').onclick = function () {
      if (!confirmLeave()) return;
      markClean('');
      loadChans();
    };
    if ($('chan-new')) $('chan-new').onclick = startNewChan;
    if ($('chan-new-es')) $('chan-new-es').onclick = startNewChan;
    if ($('chan-site-filter')) {
      $('chan-site-filter').onchange = function () {
        writeFilters({ esSite: this.value || '' });
        loadChans();
      };
    }
    if ($('chan-link-select')) {
      $('chan-link-select').onchange = function () {
        writeFilters({ tsHop: this.value || '' });
        show($('chan-new-hop'), $('chan-link-select').value === '__new__');
        loadChans();
      };
    }
    $('chan-cancel').onclick = function () { closeEntityForm('chan'); };
    if ($('chan-dup')) $('chan-dup').onclick = function () { beginDuplicate('chan'); };
    function openClassicHelp(tsNew, tsEdit, esNew, esEdit, isNew) {
      var page = state.filetype === 'ES' ? (isNew ? esNew : esEdit) : (isNew ? tsNew : tsEdit);
      window.open(RemIcsApi.micsRoot() + 'micshelp/' + page, 'WndHelp',
        'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
    }
    if ($('titl-help')) {
      $('titl-help').onclick = function () {
        openClassicHelp('tsTitle.aspx', 'tsTitle.aspx', 'esTitle.aspx', 'esTitle.aspx', false);
      };
    }
    if ($('site-help')) {
      $('site-help').onclick = function () {
        openClassicHelp('tsSiteNew.aspx', 'tsSite.aspx', 'esSiteNew.aspx', 'esSite.aspx', state.siteIsNew);
      };
    }
    if ($('ante-help')) {
      $('ante-help').onclick = function () {
        openClassicHelp('tsAnteNew.aspx', 'tsAnte.aspx', 'esAnteNew.aspx', 'esAnte.aspx', state.anteIsNew);
      };
    }
    if ($('chan-help')) {
      $('chan-help').onclick = function () {
        openClassicHelp('tsChanNew.aspx', 'tsChan.aspx', 'esChanNew.aspx', 'esChan.aspx', state.chanIsNew);
      };
    }
    function saveChan(thenNew) {
      var rec = collectFields('chan-fields');
      if (state.chanIsNew) {
        if (state.filetype === 'TS') {
          if (!(rec.call1 || '').trim()) {
            alert('Call Sign Local is required.');
            return;
          }
          if (!(rec.call2 || '').trim()) {
            alert('Call Sign Remote is required.');
            return;
          }
          if (!(rec.bndcde || '').trim()) {
            alert('Band Code is required.');
            return;
          }
          if (!(rec.chid || '').trim()) {
            alert('Channel ID is required.');
            return;
          }
        } else {
          if (!(rec.location || '').trim()) {
            alert('Location Code is required.');
            return;
          }
          if (!(rec.call1 || '').trim()) {
            alert('Call Sign is required.');
            return;
          }
          if (!(rec.chid || '').trim()) {
            alert('You must enter a channel id to continue');
            return;
          }
        }
      }
      if (!(rec.cmd || '').trim()) rec.cmd = 'A';
      RemIcsApi.pdfEdit(state.chanIsNew ? 'chanNew' : 'chanSave', {
        name: state.name, filetype: state.filetype, record: JSON.stringify(rec)
      }).then(function (r) {
        status(r.ok ? 'Channel saved.' : (r.error || 'Save failed'));
        if (r.ok) {
          markClean('');
          if (window.RemicsHints) RemicsHints.setNext('chan', { filetype: state.filetype });
          notifyTreeRefresh('chan', rec);
          if (thenNew) {
            loadHopSelect('chan').then(function () { loadChans(true); });
            openChan(contextForNew('chan', rec), true);
          } else {
            loadHopSelect('chan').then(function () { loadChans(true); });
            openChan(rec, false);
          }
        }
      }).catch(function (ex) { failStatus(ex); });
    }
    $('chan-save').onclick = function () { saveChan(false); };
    if ($('chan-save-new')) $('chan-save-new').onclick = function () { saveChan(true); };

    if ($('azim-site-filter')) {
      $('azim-site-filter').onchange = function () {
        writeFilters({ esSite: this.value || '' });
        loadAzims();
      };
    }
    if ($('azim-call1-filter')) {
      $('azim-call1-filter').onchange = function () {
        writeFilters({ azimCall1: this.value || '' });
      };
    }
    if ($('azim-refresh')) {
      $('azim-refresh').onclick = function () {
        if (!confirmLeave()) return;
        markClean('');
        loadAzims();
      };
      $('azim-new').onclick = function () {
        if (!confirmLeave()) return;
        openAzim({
          location: ($('azim-site-filter') && $('azim-site-filter').value.trim()) || '',
          call1: ($('azim-call1-filter') && $('azim-call1-filter').value.trim()) || ''
        }, true);
      };
      $('azim-cancel').onclick = function () { closeEntityForm('azim'); };
      if ($('azim-dup')) $('azim-dup').onclick = function () { beginDuplicate('azim'); };
      function saveAzim(thenNew) {
        var rec = collectFields('azim-fields');
        if (state.azimIsNew) {
          if (!(rec.location || '').trim()) {
            alert('Location is required.');
            return;
          }
          if (!(rec.call1 || '').trim()) {
            alert('Call Sign is required.');
            return;
          }
          if (!(rec.azim || '').trim()) {
            alert('Azimuth is required.');
            return;
          }
          var az = parseFloat(rec.azim);
          if (isNaN(az) || az < 0 || az > 360) {
            alert('Azimuth must be between 0 and 360.');
            return;
          }
          if (rec.elev) {
            var elv = parseFloat(rec.elev);
            if (isNaN(elv) || elv < -90 || elv > 90) {
              alert('Elevation must be between -90 and 90.');
              return;
            }
          }
        }
        if (!(rec.cmd || '').trim()) rec.cmd = 'A';
        RemIcsApi.pdfEdit(state.azimIsNew ? 'azimNew' : 'azimSave', {
          name: state.name, filetype: 'ES', record: JSON.stringify(rec)
        }).then(function (r) {
          status(r.ok ? 'Azimuth saved.' : (r.error || 'Save failed'));
          if (r.ok) {
            markClean('');
            notifyTreeRefresh('azim', rec);
            if (thenNew) {
              loadAzims(true);
              openAzim(contextForNew('azim', rec), true);
            } else {
              loadAzims(true);
              openAzim(rec, false);
            }
          }
        }).catch(function (ex) { failStatus(ex); });
      }
      $('azim-save').onclick = function () { saveAzim(false); };
      if ($('azim-save-new')) $('azim-save-new').onclick = function () { saveAzim(true); };
    }
    if ($('azim-help')) {
      $('azim-help').onclick = function () {
        openClassicHelp('esAzimuthNew.aspx', 'esAzimuth.aspx', 'esAzimuthNew.aspx', 'esAzimuth.aspx', state.azimIsNew);
      };
    }
    if ($('pdf-edit-back-azims')) $('pdf-edit-back-azims').onclick = goTreeSafe;

    var startPanel = (route.params.panel || 'title').toLowerCase();
    var treeKey = (route.params.key || '').trim();
    var asDup = route.params.dup === '1';
    if (asDup && treeKey) {
      openFromTreeKey(treeKey, startPanel, true);
    } else if (route.params.new === '1' && startPanel === 'sites') {
      var siteParts = splitTreeKey(treeKey);
      var presetCall = (siteParts[0] === 'w' && siteParts[2]) ? siteParts[2] : '';
      openSite(presetCall, true);
    } else if (route.params.new === '1' && startPanel === 'antes') {
      var anteDef = anteDefaultsFromTreeKey(treeKey);
      openAnte(anteDef, true);
      if (state.filetype === 'ES') {
        loadEsSiteSelect('ante-site-filter').then(function () {
          if ($('ante-site-filter') && anteDef.location) $('ante-site-filter').value = anteDef.location;
        });
      } else {
        loadHopSelect('ante').then(function () {
          var sel = $('ante-link-select');
          if (sel && anteDef.call1) {
            sel.value = (anteDef.call1 || '') + '|' + (anteDef.call2 || '') + '|' + (anteDef.bndcde || '');
          }
        });
      }
    } else if (route.params.new === '1' && startPanel === 'chans') {
      var chanDef = chanDefaultsFromTreeKey(treeKey);
      openChan(chanDef, true);
      if (state.filetype === 'ES') {
        loadEsSiteSelect('chan-site-filter').then(function () {
          if ($('chan-site-filter') && chanDef.location) $('chan-site-filter').value = chanDef.location;
        });
      } else {
        loadHopSelect('chan').then(function () {
          var sel = $('chan-link-select');
          if (sel && chanDef.call1) {
            sel.value = (chanDef.call1 || '') + '|' + (chanDef.call2 || '') + '|' + (chanDef.bndcde || '');
          }
        });
      }
    } else if (route.params.new === '1' && startPanel === 'azims') {
      var azimDef = azimDefaultsFromTreeKey(treeKey);
      openAzim(azimDef, true);
      loadEsSiteSelect('azim-site-filter').then(function () {
        if ($('azim-site-filter') && azimDef.location) $('azim-site-filter').value = azimDef.location;
        if ($('azim-call1-filter') && azimDef.call1) $('azim-call1-filter').value = azimDef.call1;
      });
    } else if (route.params.new === '1' && (startPanel === 'cloc' || startPanel === 'ccal' || startPanel === 'chng')) {
      openNewExtraPanel(startPanel);
    } else if (treeKey) {
      openFromTreeKey(treeKey, startPanel);
    } else if (startPanel === 'sites') loadSites();
    else if (startPanel === 'antes') {
      if (state.filetype === 'ES') loadEsSiteSelect('ante-site-filter').then(loadAntes);
      else loadHopSelect('ante').then(loadAntes);
    } else if (startPanel === 'chans') {
      if (state.filetype === 'ES') loadEsSiteSelect('chan-site-filter').then(loadChans);
      else loadHopSelect('chan').then(loadChans);
    } else if (startPanel === 'chng') loadChng();
    else if (startPanel === 'cloc') loadCloc();
    else if (startPanel === 'ccal') loadCcal();
    else if (startPanel === 'azims') loadEsSiteSelect('azim-site-filter').then(loadAzims);
    else loadTitle();
  }

  global.RemicsPdf = {
    mount: mount, canLeave: canLeave, confirmLeave: confirmLeave,
    fcheck: fcheck, icheck: icheck, beginLeaveForm: beginLeaveForm, endLeaveForm: endLeaveForm
  };
})(window);
