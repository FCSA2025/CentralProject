// RemIcsReWrite  -  SDF record edit (classic Tsdfmenu sdf*).
(function (global) {
  var state = {
    type: 'Ante', name: '', key: '', origKey: '', isNew: false, isDup: false,
    formSnapshot: '', hash: '', loaded: null, children: [], interpolated: false,
    childKind: '', childIsNew: false, childKey: '', childLoaded: null
  };

  function $(id) { return document.getElementById(id); }

  function show(el, on) {
    if (!el) return;
    el.hidden = !on;
    el.style.display = on ? '' : 'none';
  }

  function openInterpLog(body) {
    var shell = window.REMICS_SHELL || {};
    var schema = shell.schema || '';
    var user = shell.user || '';
    var root = (window.RemIcsApi && RemIcsApi.micsRoot) ? RemIcsApi.micsRoot() : '/mics/';
    var name = String(body || '').replace(/^\s+|\s+$/g, '');
    var file = 'errors.txt';
    if (name && !/^ERROR/i.test(name) && !/\s/.test(name) && name.length < 80) {
      file = name;
    }
    window.open(root + 'userdirs/' + schema + '/' + user + '/' + file, 'WndExport',
      'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes');
  }

  function parseRoute() {
    var hash = (location.hash || '').replace(/^#\/?/, '');
    var parts = hash.split('?');
    var params = {};
    if (parts[1]) {
      parts[1].split('&').forEach(function (pair) {
        var kv = pair.split('=');
        params[decodeURIComponent(kv[0] || '')] = decodeURIComponent((kv[1] || '').replace(/\+/g, ' '));
      });
    }
    return { view: parts[0] || '', params: params };
  }

  function status(msg) {
    var el = $('sdf-edit-status');
    if (el) el.textContent = msg || '';
  }

  function val(id) {
    var el = $(id);
    return el ? (el.value || '') : '';
  }

  function setVal(id, v) {
    var el = $(id);
    if (el) el.value = v == null ? '' : String(v);
  }

  function types() { return global.RemicsSdfTypes; }

  function isHeader() { return state.type === 'Ante' || state.type === 'Band'; }

  function spec() { return types() ? types().spec(state.type) : null; }

  function childKind() {
    if (state.type === 'Ante') return 'antd';
    var s = spec();
    return (s && s.child) || '';
  }

  function esc(s, allowNbsp) {
    if (allowNbsp && (s === '&nbsp;' || s === '')) return '&nbsp;';
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function apiErr(r, fb) {
    return (global.RemIcsApi && RemIcsApi.apiErr) ? RemIcsApi.apiErr(r, fb) : ((r && r.error) || fb || 'Request failed.');
  }

  function blurAttr(rule) {
    if (!rule) return '';
    var p = String(rule).split(',');
    if (p[0] === 'f') {
      return ' onblur="if(window.RemicsPdf)RemicsPdf.fcheck(this,' + p[1] + ',' + p[2] + ',' + p[3] + ',false)"';
    }
    if (p[0] === 'i') {
      return ' onblur="if(window.RemicsPdf)RemicsPdf.icheck(this,' + p[1] + ',' + p[2] + ')"';
    }
    return '';
  }

  function setKeyEditable(inputId, labelId, editable, keyClass) {
    var el = $(inputId);
    var lab = $(labelId);
    if (!el) return;
    el.readOnly = !editable;
    el.tabIndex = editable ? 0 : -1;
    el.className = editable ? (keyClass || 'ik') : 'irok';
    if (lab) lab.className = editable ? 'k' : 'rok';
  }

  function setCmdEditable(inputId, lookupId, labelId, editable) {
    var el = $(inputId);
    var look = $(lookupId);
    var lab = $(labelId);
    if (!el) return;
    el.readOnly = !editable;
    el.tabIndex = editable ? 0 : -1;
    el.className = editable ? 'im' : 'iro';
    if (look) show(look, editable);
    if (lab) lab.className = editable ? 'm' : 'tdro';
  }

  function fieldId(name, prefix) { return (prefix || 'sdf-d-') + name; }

  function renderFields(host, rows, rec, prefix, isNew) {
    if (!host) return;
    rec = rec || {};
    var html = '<table align="center">';
    rows.forEach(function (row) {
      html += '<tr>';
      row.forEach(function (fld) {
        var id = fieldId(fld.name, prefix);
        var labClass = fld.ro ? 'tdro' : (fld.key ? 'rok' : (fld.opt ? 'o' : 'm'));
        var span = fld.colspan ? ' colspan="' + fld.colspan + '"' : '';
        html += '<td class="' + labClass + '" id="' + id + '-label">' + fld.label + '</td>';
        html += '<td class="by"' + span + '>';
        if (fld.radio) {
          fld.radio.forEach(function (opt) {
            html += opt[1] + ' <input type="radio" name="' + id + '" value="' + opt[0] + '"' +
              (String(rec[fld.name] || '') === opt[0] ? ' checked' : '') + '> ';
          });
        } else if (fld.date3) {
          var p = fld.date3;
          html += '<input id="' + fieldId(p + 'Day', prefix) + '" class="im" maxlength="2" size="2" value="' + esc(rec[p + 'Day']) + '">-' +
            '<input id="' + fieldId(p + 'Month', prefix) + '" class="im" maxlength="3" size="4" value="' + esc(rec[p + 'Month']) + '">-' +
            '<input id="' + fieldId(p + 'Year', prefix) + '" class="im" maxlength="4" size="4" value="' + esc(rec[p + 'Year']) + '">';
        } else if (fld.textarea) {
          html += '<textarea id="' + id + '" class="im" rows="' + (fld.rows || 3) + '" cols="' + (fld.cols || 22) + '"' +
            (fld.max ? ' maxlength="' + fld.max + '"' : '') + '>' + esc(rec[fld.name]) + '</textarea>';
        } else {
          var cls = fld.ro ? 'iro' : (fld.key ? 'irok' : (fld.opt ? '' : 'im'));
          var ro = fld.ro || (fld.key && !isNew && !fld.cmd) ? ' readonly tabindex="-1"' : '';
          if (fld.cmd && isNew) { cls = 'iro'; ro = ' readonly tabindex="-1"'; }
          if (fld.key && isNew) cls = 'ik';
          html += '<input id="' + id + '" class="' + cls + '" type="text"' +
            (fld.max ? ' maxlength="' + fld.max + '"' : '') +
            (fld.size ? ' size="' + fld.size + '"' : '') +
            ro + blurAttr(fld.blur) + ' value="' + esc(rec[fld.name]) + '">';
          if (fld.lookup) {
            html += ' <input class="bt" type="button" value="' + (fld.lookupM ? '??' : '?') +
              '" tabindex="-1" data-lookup="' + fld.lookup + '" data-field="' + id + '"' +
              (fld.lookupM ? ' data-lookup-m="1"' : '') + ' id="' + id + '-lookup">';
          }
        }
        html += '</td>';
      });
      html += '</tr>';
    });
    html += '<tr><td class="tdro">Modify Date</td><td class="by" colspan="3">' +
      '<input id="' + fieldId('mDay', prefix) + '" class="iro" readonly tabindex="-1" maxlength="2" size="2" value="' + esc(rec.mDay) + '"> ' +
      '<input id="' + fieldId('mMonth', prefix) + '" class="iro" readonly tabindex="-1" maxlength="3" size="4" value="' + esc(rec.mMonth) + '"> ' +
      '<input id="' + fieldId('mYear', prefix) + '" class="iro" readonly tabindex="-1" maxlength="4" size="4" value="' + esc(rec.mYear) + '">' +
      '</td></tr></table>';
    host.innerHTML = html;
  }

  function collectFields(rows, prefix) {
    var out = {};
    (rows || []).forEach(function (row) {
      row.forEach(function (fld) {
        if (fld.radio) {
          var radios = document.getElementsByName(fieldId(fld.name, prefix));
          out[fld.name] = '';
          Array.prototype.forEach.call(radios, function (r) { if (r.checked) out[fld.name] = r.value; });
        } else if (fld.date3) {
          var p = fld.date3;
          out[p + 'Day'] = val(fieldId(p + 'Day', prefix));
          out[p + 'Month'] = val(fieldId(p + 'Month', prefix));
          out[p + 'Year'] = val(fieldId(p + 'Year', prefix));
        } else {
          out[fld.name] = val(fieldId(fld.name, prefix));
        }
      });
    });
    return out;
  }

  function snapshotForm() {
    if (state.type === 'Band') {
      return JSON.stringify({
        cmd: val('sdf-b-cmd'), bndcde: val('sdf-bndcde'),
        blo: val('sdf-blo'), bmidf: val('sdf-bmidf'),
        bhi: val('sdf-bhi'), badj: val('sdf-badj')
      });
    }
    if (state.type === 'Ante') {
      return JSON.stringify({
        cmd: val('sdf-cmd'), acode: val('sdf-acode'),
        axtype: val('sdf-axtype'), again: val('sdf-again'),
        axref: val('sdf-axref'), abw: val('sdf-abw'),
        arms: val('sdf-arms'), aband: val('sdf-aband'),
        amanu: val('sdf-amanu'), apattern: val('sdf-apattern'),
        amodel: val('sdf-amodel'), adesc: val('sdf-adesc'),
        antype: val('sdf-antype'), aftbr: val('sdf-aftbr'),
        lofreq: val('sdf-lofreq'), hifreq: val('sdf-hifreq'),
        bandcodes: val('sdf-bandcodes'), ax0: val('sdf-ax0')
      });
    }
    var s = spec();
    return JSON.stringify(s ? collectFields(s.rows, 'sdf-d-') : {});
  }

  function markClean() { state.formSnapshot = snapshotForm(); }

  function isDirty() {
    if (!$('sdf-edit-heading')) return false;
    return snapshotForm() !== state.formSnapshot;
  }

  function confirmLeave() {
    if (!isDirty()) return true;
    return window.confirm('You have unsaved changes. Leave without saving?');
  }

  function keepHash() {
    if (state.hash && location.hash !== state.hash) {
      try { history.replaceState(null, '', state.hash); } catch (e) { location.hash = state.hash; }
    }
  }

  function canLeave() {
    if (!confirmLeave()) {
      keepHash();
      return false;
    }
    state.formSnapshot = '';
    return true;
  }

  function goTree() {
    var q = 'type=' + encodeURIComponent(state.type);
    if (state.name) q += '&name=' + encodeURIComponent(state.name);
    if (global.RemicsApp && RemicsApp.navigate) RemicsApp.navigate('sdf-tree', q);
    else location.hash = '#/sdf-tree?' + q;
  }

  function goTreeSafe() {
    if (!confirmLeave()) return;
    state.formSnapshot = '';
    goTree();
  }

  function goEdit(opts) {
    var q = 'type=' + encodeURIComponent(opts.type || state.type) +
      '&name=' + encodeURIComponent(opts.name || state.name);
    if (opts.key) q += '&key=' + encodeURIComponent(opts.key);
    if (opts.isNew) q += '&new=1';
    if (opts.isDup) q += '&dup=1';
    markClean();
    if (global.RemicsApp && RemicsApp.navigate) RemicsApp.navigate('sdf-edit', q);
    else location.hash = '#/sdf-edit?' + q;
  }

  function collectAnte() {
    return {
      name: state.name,
      acode: val('sdf-acode').trim().toUpperCase(),
      cmd: val('sdf-cmd'),
      axtype: val('sdf-axtype'),
      again: val('sdf-again'),
      axref: val('sdf-axref'),
      abw: val('sdf-abw'),
      arms: val('sdf-arms'),
      aband: val('sdf-aband'),
      amanu: val('sdf-amanu'),
      apattern: val('sdf-apattern'),
      amodel: val('sdf-amodel'),
      adesc: val('sdf-adesc'),
      antype: val('sdf-antype'),
      aftbr: val('sdf-aftbr'),
      lofreq: val('sdf-lofreq'),
      hifreq: val('sdf-hifreq'),
      bandcodes: val('sdf-bandcodes'),
      ax0: val('sdf-ax0'),
      anip: val('sdf-anip'),
      origAcode: state.isDup ? state.origKey : ''
    };
  }

  function collectBand() {
    return {
      name: state.name,
      bndcde: val('sdf-bndcde').trim().toUpperCase(),
      cmd: val('sdf-b-cmd'),
      blo: val('sdf-blo'),
      bmidf: val('sdf-bmidf'),
      bhi: val('sdf-bhi'),
      badj: val('sdf-badj')
    };
  }

  function collectDyn() {
    var s = spec();
    var fields = s ? collectFields(s.rows, 'sdf-d-') : {};
    fields.name = state.name;
    fields.type = state.type;
    fields.key = state.key;
    if (state.isDup) fields.origKey = state.origKey;
    (s && s.keys || []).forEach(function (k) {
      if (fields[k]) fields[k] = String(fields[k]).trim().toUpperCase();
    });
    return fields;
  }

  function fillAnte(rec) {
    rec = rec || {};
    setVal('sdf-cmd', rec.cmd || (state.isNew ? 'A' : ''));
    setVal('sdf-acode', rec.acode || '');
    setVal('sdf-axtype', rec.axtype);
    setVal('sdf-again', rec.again);
    setVal('sdf-axref', rec.axref);
    setVal('sdf-abw', rec.abw);
    setVal('sdf-arms', rec.arms);
    setVal('sdf-aband', rec.aband);
    setVal('sdf-amanu', rec.amanu);
    setVal('sdf-apattern', rec.apattern);
    setVal('sdf-amodel', rec.amodel);
    setVal('sdf-adesc', rec.adesc);
    setVal('sdf-antype', rec.antype);
    setVal('sdf-aftbr', rec.aftbr);
    setVal('sdf-lofreq', rec.lofreq);
    setVal('sdf-hifreq', rec.hifreq);
    setVal('sdf-bandcodes', rec.bandcodes);
    setVal('sdf-ax0', rec.ax0);
    setVal('sdf-anip', rec.anip);
    setVal('sdf-mDay', rec.mDay);
    setVal('sdf-mMonth', rec.mMonth);
    setVal('sdf-mYear', rec.mYear);
  }

  function fillBand(rec) {
    rec = rec || {};
    setVal('sdf-b-cmd', rec.cmd || (state.isNew ? 'A' : ''));
    setVal('sdf-bndcde', rec.bndcde || '');
    setVal('sdf-bandbitpos', rec.bandbitpos);
    setVal('sdf-blo', rec.blo);
    setVal('sdf-bmidf', rec.bmidf);
    setVal('sdf-bhi', rec.bhi);
    setVal('sdf-badj', rec.badj);
    setVal('sdf-b-mDay', rec.mDay);
    setVal('sdf-b-mMonth', rec.mMonth);
    setVal('sdf-b-mYear', rec.mYear);
  }

  function fillDyn(rec) {
    var s = spec();
    if (!s) return;
    if (state.isNew && !(rec && rec.cmd)) rec = Object.assign({ cmd: 'A' }, rec || {});
    renderFields($('sdf-panel-dyn'), s.rows, rec, 'sdf-d-', state.isNew);
    applyDynMode();
  }

  function applyDynMode() {
    var s = spec();
    if (!s) return;
    s.rows.forEach(function (row) {
      row.forEach(function (fld) {
        if (fld.cmd) setCmdEditable(fieldId(fld.name), fieldId(fld.name) + '-lookup', fieldId(fld.name) + '-label', !state.isNew);
        else if (fld.key) setKeyEditable(fieldId(fld.name), fieldId(fld.name) + '-label', state.isNew, 'ik');
      });
    });
  }

  function renderChildren(rows, kind) {
    var host = kind === 'antd' ? $('sdf-discr-host') : $('sdf-child-host');
    var btns = kind === 'antd' ? $('sdf-ante-child-btns') : $('sdf-child-btns');
    if (btns) show(btns, !state.isNew);
    if (kind === 'antd') {
      var newBtn = $('sdf-discr-new');
      if (newBtn) newBtn.value = 'New Discrimination';
    } else {
      var s = spec();
      var nb = $('sdf-child-new');
      if (nb) nb.value = (s && s.childNew) || 'New';
    }
    if (!host) return;
    host.innerHTML = '';
    var cspec = types() && types().childSpec(kind);
    if (state.isNew) return;
    if (!rows || !rows.length) {
      host.innerHTML = '<p class="classic-hint">No ' + ((cspec && cspec.title) || 'child') + ' records.</p>';
      return;
    }
    var html = '<table align="center" bordercolor="navy" cellspacing="0" cellpadding="2" border="2"><tr>';
    (cspec && cspec.cols || []).forEach(function (c) {
      html += '<td class="h">&nbsp;' + esc(c.label) + '&nbsp;</td>';
    });
    html += '<td class="h">&nbsp;</td><td class="h">&nbsp;</td></tr>';
    rows.forEach(function (r) {
      html += '<tr>';
      (cspec && cspec.cols || []).forEach(function (c) {
        html += '<td class="az">' + esc(r[c.name] || '&nbsp;', true) + '</td>';
      });
      var ck = r[(cspec && cspec.key) || ''] || '';
      html += '<td class="h"><input class="bt" type="button" value="Edit" data-child-edit="' + esc(ck) + '"></td>';
      html += '<td class="h"><input class="bt" type="button" value="Delete" data-child-del="' + esc(ck) + '"></td></tr>';
    });
    html += '</table>';
    host.innerHTML = html;
    host.querySelectorAll('[data-child-edit]').forEach(function (btn) {
      btn.onclick = function () { openChild(false, btn.getAttribute('data-child-edit')); };
    });
    host.querySelectorAll('[data-child-del]').forEach(function (btn) {
      btn.onclick = function () { deleteChild(btn.getAttribute('data-child-del')); };
    });
  }

  function interpolatedFrom(rows) {
    return (rows || []).some(function (r) {
      return r.interpstat && r.interpstat !== '0';
    });
  }

  function guardInterp() {
    if (state.type === 'Ante' && state.interpolated) {
      alert('Some discrimination values have been interpolated.\nYou must run Undo Interpolate before you can add, change or delete any values.');
      return false;
    }
    return true;
  }

  function openChild(isNew, childKey) {
    if (!guardInterp() && !isNew) return;
    if (isNew && !guardInterp()) return;
    var kind = childKind();
    var cspec = types() && types().childSpec(kind);
    if (!cspec) return;
    state.childKind = kind;
    state.childIsNew = !!isNew;
    state.childKey = childKey || '';
    show($('sdf-child-form'), true);
    $('sdf-child-heading').textContent = (isNew ? 'New ' : '') + cspec.title;
    if (isNew) {
      renderFields($('sdf-child-fields'), cspec.rows, { cmd: 'A' }, 'sdf-c-', true);
      bindChildForm();
      return;
    }
    status('Loading...');
    RemIcsApi.sdfEdit('childGet', {
      type: state.type, name: state.name, key: state.key, childKey: childKey
    }).then(function (r) {
      status('');
      if (!r || !r.ok) { alert(apiErr(r, 'Load failed')); return; }
      state.childLoaded = r.record || {};
      renderFields($('sdf-child-fields'), cspec.rows, r.record, 'sdf-c-', false);
      bindChildForm();
    }).catch(function (ex) {
      status('');
      alert(ex.message || String(ex));
    });
  }

  function bindChildForm() {
    if (window.RemicsLookup && RemicsLookup.bindDataLookupButtons) {
      RemicsLookup.bindDataLookupButtons($('sdf-child-form'));
    }
    if (window.RemIcsApi && RemIcsApi.wireEnterAsTab) {
      RemIcsApi.wireEnterAsTab($('sdf-child-form'));
    }
  }

  function saveChild() {
    var kind = state.childKind || childKind();
    var cspec = types() && types().childSpec(kind);
    if (!cspec) return;
    var fields = collectFields(cspec.rows, 'sdf-c-');
    fields.type = state.type;
    fields.name = state.name;
    fields.key = state.key;
    fields.childKey = state.childIsNew ? (fields[cspec.key] || '') : state.childKey;
    if (state.childIsNew && !fields.childKey) {
      alert(cspec.keyMsg);
      return;
    }
    status('Saving...');
    RemIcsApi.sdfEdit(state.childIsNew ? 'childNew' : 'childSave', fields).then(function (r) {
      status('');
      if (!r || !r.ok) { alert(apiErr(r, 'Save failed')); return; }
      show($('sdf-child-form'), false);
      reloadRecord();
    }).catch(function (ex) {
      status('');
      alert(ex.message || String(ex));
    });
  }

  function deleteChild(childKey) {
    if (!guardInterp()) return;
    if (!window.confirm('Delete this ' + ((types() && types().childSpec(childKind()) || {}).title || 'record') + '?')) return;
    RemIcsApi.sdfEdit('childDelete', {
      type: state.type, name: state.name, key: state.key, childKey: childKey
    }).then(function (r) {
      if (!r || !r.ok) { alert(apiErr(r, 'Delete failed')); return; }
      reloadRecord();
    }).catch(function (ex) {
      alert(ex.message || String(ex));
    });
  }

  function runInterp(method) {
    if (state.isNew) return;
    if (method === 'interpolate' && state.interpolated) {
      alert('Some discrimination values have been interpolated.\nYou must run Undo Interpolate before you can run Interpolate again.');
      return;
    }
    if (method === 'uninterpolate' && !state.interpolated) {
      alert('No discrimination values have been interpolated.\nUndo Interpolate cancelled.');
      return;
    }
    var acode = val('sdf-acode') || state.key;
    status(method === 'interpolate' ? 'Interpolating...' : 'Undo Interpolate...');
    RemIcsApi.dsAsmx('Tfileactions/TwsTabUtil.asmx', method, { args: state.name + ' ' + acode }).then(function (r) {
      var body = (r && r.body != null) ? String(r.body) : '';
      if (r && r.ok && (body === 'OK' || body.indexOf('OK') === 0)) {
        status('');
        reloadRecord();
        return;
      }
      status('');
      var label = method === 'interpolate' ? 'Interpolate' : 'Undo Interpolate';
      var detail = String(body || '').replace(/^ERROR:\s*/i, '').replace(/^\s+|\s+$/g, '');
      alert(label + ' failed' + (detail && detail !== 'OK' ? ':\n' + detail : '.') + '\nOpening the interpolate log.');
      openInterpLog(body);
    }).catch(function (ex) {
      status('');
      alert(ex.message || String(ex));
    });
  }

  function save(after) {
    var fields, action, keyField, s;
    if (state.type === 'Band') {
      fields = collectBand();
      if (state.isNew && !fields.bndcde) {
        alert('You must enter a Band Code to continue');
        return Promise.resolve(false);
      }
      action = state.isNew ? 'bandNew' : 'bandSave';
      keyField = 'bndcde';
    } else if (state.type === 'Ante') {
      fields = collectAnte();
      if (state.isNew && !fields.acode) {
        alert('You must enter an antenna code to continue');
        return Promise.resolve(false);
      }
      action = state.isNew ? 'anteNew' : 'anteSave';
      keyField = 'acode';
    } else {
      s = spec();
      fields = collectDyn();
      if (state.isNew && s) {
        var missing = (s.keys || []).some(function (k) { return !fields[k]; });
        if (missing) {
          alert(s.keyMsg);
          return Promise.resolve(false);
        }
      }
      action = state.isNew ? 'recNew' : 'recSave';
      keyField = (s && s.keys && s.keys.length === 1) ? s.keys[0] : '';
    }
    status('Saving...');
    return RemIcsApi.sdfEdit(action, fields).then(function (r) {
      if (!r || !r.ok) {
        status('');
        alert(apiErr(r, 'Save failed'));
        return false;
      }
      var savedKey = r.key || (keyField ? fields[keyField] : ((s && s.keys || []).map(function (k) { return fields[k]; }).join('^')));
      state.key = savedKey;
      markClean();
      status('Saved');
      if (after === 'new') {
        goEdit({ type: state.type, name: state.name, isNew: true });
        return true;
      }
      if (after === 'dup') {
        goEdit({ type: state.type, name: state.name, key: savedKey, isDup: true });
        return true;
      }
      if (after === 'edit' || state.isDup) {
        goEdit({ type: state.type, name: state.name, key: savedKey });
        return true;
      }
      goTree();
      return true;
    }).catch(function (ex) {
      status('');
      alert(ex.message || String(ex));
      return false;
    });
  }

  function applyMode() {
    var isAnte = state.type === 'Ante';
    var isBand = state.type === 'Band';
    show($('sdf-panel-ante'), isAnte);
    show($('sdf-panel-band'), isBand);
    show($('sdf-panel-dyn'), !isAnte && !isBand);
    show($('sdf-dup'), !state.isNew);
    show($('sdf-ante-child-btns'), isAnte && !state.isNew);
    show($('sdf-child-btns'), !isAnte && !isBand && !!childKind() && !state.isNew);
    show($('sdf-child-form'), false);
    if (isAnte) {
      setCmdEditable('sdf-cmd', 'sdf-cmd-lookup', 'sdf-cmd-label', !state.isNew);
      setKeyEditable('sdf-acode', 'sdf-acode-label', state.isNew, 'ik');
    } else if (isBand) {
      setCmdEditable('sdf-b-cmd', 'sdf-b-cmd-lookup', 'sdf-b-cmd-label', !state.isNew);
      setKeyEditable('sdf-bndcde', 'sdf-bndcde-label', state.isNew, 'ik');
      show($('sdf-bndcde-lookup'), state.isNew);
    }
  }

  function headingText() {
    var kind = types() ? types().kindName(state.type) : state.type;
    if (state.isDup) return 'Duplicate FCSA MICS ' + kind + ' Subsidiary Data Entry';
    if (state.isNew) return 'New FCSA MICS ' + kind + ' Subsidiary Data Entry';
    return state.type === 'Band'
      ? 'FCSA MICS Band Subsidiary Data Entry Form'
      : 'FCSA MICS ' + kind + ' Subsidiary Data Entry';
  }

  function firstFocus() {
    var ids;
    if (state.type === 'Band') ids = state.isNew ? ['sdf-bndcde', 'sdf-blo'] : ['sdf-b-cmd', 'sdf-blo'];
    else if (state.type === 'Ante') ids = state.isNew ? ['sdf-acode', 'sdf-axtype'] : ['sdf-cmd', 'sdf-axtype'];
    else {
      var s = spec();
      ids = [];
      if (s) {
        s.rows.forEach(function (row) {
          row.forEach(function (fld) {
            if (fld.date3) ids.push(fieldId(fld.date3 + 'Day'));
            else ids.push(fieldId(fld.name));
          });
        });
      }
    }
    if (global.RemIcsApi && RemIcsApi.firstFocus) {
      RemIcsApi.firstFocus($('view-host'), ids);
      return;
    }
    for (var i = 0; i < ids.length; i++) {
      var el = $(ids[i]);
      if (el && !el.readOnly && !el.disabled) {
        try { el.focus(); if (el.select) el.select(); } catch (e) { /* ignore */ }
        return;
      }
    }
  }

  function openHelp() {
    var page = 'sdf' + state.type + '.aspx';
    var root = (global.RemIcsApi && RemIcsApi.micsRoot) ? RemIcsApi.micsRoot() : '/mics/';
    window.open(root + 'micshelp/separatefiles/' + page, 'WndHelp',
      'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
  }

  function applyRecord(r) {
    state.loaded = r.record || {};
    state.children = r.discr || r.children || [];
    state.interpolated = !!r.interpolated || interpolatedFrom(state.children);
    if (state.type === 'Band') {
      fillBand(r.record);
      if (state.isNew) {
        setVal('sdf-b-cmd', 'A');
        setVal('sdf-b-mDay', '');
        setVal('sdf-b-mMonth', '');
        setVal('sdf-b-mYear', '');
      }
    } else if (state.type === 'Ante') {
      fillAnte(r.record);
      renderChildren(state.children, 'antd');
      if (state.isNew) {
        setVal('sdf-cmd', 'A');
        setVal('sdf-mDay', '');
        setVal('sdf-mMonth', '');
        setVal('sdf-mYear', '');
      }
    } else {
      fillDyn(r.record);
      if (childKind()) renderChildren(state.children, childKind());
    }
    markClean();
    status('');
    firstFocus();
  }

  function reloadRecord() {
    if (state.isNew && !state.isDup) {
      if (state.type === 'Band') fillBand({ cmd: 'A' });
      else if (state.type === 'Ante') fillAnte({ cmd: 'A' });
      else fillDyn({ cmd: 'A' });
      renderChildren([], childKind() || 'antd');
      markClean();
      firstFocus();
      return;
    }
    var action = state.type === 'Band' ? 'bandGet' : (state.type === 'Ante' ? 'anteGet' : 'recGet');
    var fields = { name: state.name, key: state.key };
    if (action === 'recGet') fields.type = state.type;
    status('Loading...');
    RemIcsApi.sdfEdit(action, fields).then(function (r) {
      if (!r || !r.ok) {
        status('');
        alert(apiErr(r, 'Load failed'));
        return;
      }
      applyRecord(r);
    }).catch(function (ex) {
      status('');
      alert(ex.message || String(ex));
    });
  }

  function loadRecord() { reloadRecord(); }

  function persistLast() {
    if (!window.RemIcsApi || !RemIcsApi.sessionSet) return;
    RemIcsApi.sessionSet('remics-last-sdf-type', state.type);
    RemIcsApi.sessionSet('remics-last-sdf-name', state.name);
    if (state.key && !state.isNew) RemIcsApi.sessionSet('remics-last-sdf-key', state.key);
  }

  function mount() {
    var route = parseRoute();
    var p = route.params || {};
    var t = (p.type || 'Ante').trim();
    state.type = t;
    state.name = (p.name || '').trim();
    state.key = (p.key || '').trim();
    state.isNew = p['new'] === '1' || p['new'] === 'true';
    state.isDup = p.dup === '1' || p.dup === 'true';
    if (state.isDup) state.isNew = true;
    state.origKey = state.key;
    state.hash = location.hash || '';
    state.loaded = null;
    state.children = [];
    state.interpolated = false;

    if (!state.name) {
      status('Missing SDF file name.');
      return;
    }
    if (!state.isNew && !state.key) {
      status('Missing record key.');
      return;
    }
    if (!isHeader() && !spec()) {
      status('Unknown SDF type: ' + state.type);
      return;
    }

    persistLast();
    $('sdf-edit-heading').textContent = headingText();
    $('sdf-edit-meta').textContent = state.type + ' file ' + state.name +
      (state.key && !state.isNew ? '  -  ' + state.key : (state.isDup ? '  -  from ' + state.origKey : ''));

    applyMode();
    if (!isHeader()) fillDyn(state.isNew && !state.isDup ? { cmd: 'A' } : {});
    if (window.RemicsLookup && RemicsLookup.bindDataLookupButtons) {
      RemicsLookup.bindDataLookupButtons($('view-host') || document);
    }
    if (window.RemIcsApi && RemIcsApi.wireEnterAsTab) {
      RemIcsApi.wireEnterAsTab($('view-host') || document.body);
    }

    $('sdf-save').onclick = function () { save(state.isDup ? 'edit' : 'tree'); };
    $('sdf-save-new').onclick = function () { save('new'); };
    $('sdf-dup').onclick = function () {
      if (!isDirty()) {
        goEdit({ type: state.type, name: state.name, key: state.key, isDup: true });
        return;
      }
      save('dup');
    };
    $('sdf-reset').onclick = function () {
      if (state.loaded) applyRecord({ record: state.loaded, discr: state.children, children: state.children, interpolated: state.interpolated });
      else if (state.isNew && !state.isDup) reloadRecord();
      markClean();
      status('');
    };
    $('sdf-cancel').onclick = goTreeSafe;
    $('sdf-help').onclick = openHelp;
    if ($('sdf-discr-new')) $('sdf-discr-new').onclick = function () { openChild(true); };
    if ($('sdf-child-new')) $('sdf-child-new').onclick = function () { openChild(true); };
    if ($('sdf-child-save')) $('sdf-child-save').onclick = saveChild;
    if ($('sdf-child-cancel')) $('sdf-child-cancel').onclick = function () { show($('sdf-child-form'), false); };
    if ($('sdf-interp')) $('sdf-interp').onclick = function () { runInterp('interpolate'); };
    if ($('sdf-uninterp')) $('sdf-uninterp').onclick = function () { runInterp('uninterpolate'); };

    loadRecord();
  }

  global.RemicsSdfEdit = { mount: mount, canLeave: canLeave };
})(window);
