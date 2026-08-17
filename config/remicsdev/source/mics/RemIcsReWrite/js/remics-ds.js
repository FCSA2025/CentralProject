// RemIcsReWrite Phase 6.5 — Data Search TS / ES (IP-2 classic checkbox criteria).
(function (global) {
  var tsState = { sites: [], links: [], remotes: [], owhere: '' };
  var esState = { sites: [], owhere: '' };

  function $(id) { return document.getElementById(id); }
  function show(el, on) {
    if (!el) return;
    el.hidden = !on;
    el.style.display = on ? '' : 'none';
  }
  function micsRoot() {
    return (global.RemIcsApi && RemIcsApi.micsRoot) ? RemIcsApi.micsRoot() : '/mics/';
  }
  function openHelp(path) {
    window.open(micsRoot() + path, 'WndHelp', 'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
  }
  function clearCritDiv(div) {
    if (!div) return;
    div.querySelectorAll('input,select,textarea').forEach(function (el) {
      if (el.type === 'checkbox' || el.type === 'button') return;
      el.value = '';
    });
  }

  /** Classic dsTS/dsES checkbox → criteria panel binding. */
  function bindDsCriteria(prefix, fieldKeys, opts) {
    opts = opts || {};
    var latKeys = opts.latKeys || ['sstrlatit', 'sstrlongit'];
    var radiusKey = opts.radiusKey || 'sradius';

    function setChecked(id, on) {
      var el = $(prefix + '-chk-' + id);
      if (el) el.checked = !!on;
    }
    function syncField(key) {
      var chk = $(prefix + '-chk-' + key);
      var div = $(prefix + '-crit-' + key);
      if (!chk || !div) return;
      show(div, chk.checked);
      if (!chk.checked) clearCritDiv(div);
    }
    function onLatLongChange(fromKey) {
      if (latKeys.indexOf(fromKey) < 0) return;
      var anyLat = latKeys.some(function (k) {
        var c = $(prefix + '-chk-' + k);
        return c && c.checked;
      });
      if (anyLat) {
        setChecked(radiusKey, false);
        syncField(radiusKey);
        latKeys.forEach(function (k) {
          if (k !== fromKey) setChecked(k, false);
        });
        latKeys.forEach(syncField);
      }
    }
    function onRadiusChange() {
      var rad = $(prefix + '-chk-' + radiusKey);
      if (rad && rad.checked) {
        latKeys.forEach(function (k) {
          setChecked(k, false);
          syncField(k);
        });
      }
    }

    fieldKeys.forEach(function (key) {
      var chk = $(prefix + '-chk-' + key);
      if (!chk) return;
      chk.onchange = function () {
        if (key === radiusKey) onRadiusChange();
        else if (latKeys.indexOf(key) >= 0) onLatLongChange(key);
        syncField(key);
      };
      syncField(key);
    });
  }

  function valIfChecked(prefix, chkKey, inputId, apiKey, body) {
    var chk = $(prefix + '-chk-' + chkKey);
    if (!chk || !chk.checked) return;
    var el = $(inputId);
    if (!el) return;
    var v = (el.value || '').trim();
    if (v) body[apiKey || chkKey.replace(/^[sca]/, '')] = el.value;
  }

  function collectTsBody() {
    var body = {};
    valIfChecked('dsts', 'scall1', 'dsts-call1', 'call1', body);
    valIfChecked('dsts', 'sname', 'dsts-name', 'name', body);
    valIfChecked('dsts', 'soper', 'dsts-oper', 'oper', body);
    valIfChecked('dsts', 'sprov', 'dsts-prov', 'prov', body);
    valIfChecked('dsts', 'sstats', 'dsts-stats', 'stats', body);
    valIfChecked('dsts', 'sreg', 'dsts-reg', 'reg', body);
    valIfChecked('dsts', 'sgrnd', 'dsts-grnd', 'grnd', body);
    valIfChecked('dsts', 'acall2', 'dsts-call2', 'call2', body);
    valIfChecked('dsts', 'abndcde', 'dsts-bndcde', 'bndcde', body);
    valIfChecked('dsts', 'aanum', 'dsts-anum', 'anum', body);
    valIfChecked('dsts', 'aacode', 'dsts-acode', 'acode', body);
    valIfChecked('dsts', 'cchid', 'dsts-chid', 'chid', body);
    valIfChecked('dsts', 'cfreqtx', 'dsts-freqtx', 'freqtx', body);
    valIfChecked('dsts', 'cfreqrx', 'dsts-freqrx', 'freqrx', body);

    var radChk = $('dsts-chk-sradius');
    if (radChk && radChk.checked) {
      var rlat = ($('dsts-rlat').value || '').trim();
      var rlong = ($('dsts-rlong').value || '').trim();
      var rrad = ($('dsts-rradius').value || '').trim();
      if (rlat && rlong && rrad) body.radiusinfo = rlat + '^' + rlong + '^' + rrad;
    } else {
      valIfChecked('dsts', 'sstrlatit', 'dsts-strlatit', 'strlatit', body);
      valIfChecked('dsts', 'sstrlongit', 'dsts-strlongit', 'strlongit', body);
    }
    return body;
  }

  function collectEsBody() {
    var body = {};
    valIfChecked('dses', 'slocation', 'dses-location', 'location', body);
    valIfChecked('dses', 'sname', 'dses-name', 'name', body);
    valIfChecked('dses', 'soper', 'dses-oper', 'oper', body);
    valIfChecked('dses', 'sprov', 'dses-prov', 'prov', body);
    valIfChecked('dses', 'sstats', 'dses-stats', 'stats', body);
    valIfChecked('dses', 'sgrnd', 'dses-grnd', 'grnd', body);
    valIfChecked('dses', 'scall1', 'dses-call1', 'call1', body);
    valIfChecked('dses', 'cchid', 'dses-chid', 'chid', body);

    var radChk = $('dses-chk-sradius');
    if (radChk && radChk.checked) {
      var rlat = ($('dses-rlat').value || '').trim();
      var rlong = ($('dses-rlong').value || '').trim();
      var rrad = ($('dses-rradius').value || '').trim();
      if (rlat && rlong && rrad) body.radiusinfo = rlat + '^' + rlong + '^' + rrad;
    } else {
      valIfChecked('dses', 'sstrlatit', 'dses-strlatit', 'strlatit', body);
      valIfChecked('dses', 'sstrlongit', 'dses-strlongit', 'strlongit', body);
    }
    return body;
  }

  function dsStoreKey(prefix) {
    return 'remics-ds-crit-' + prefix;
  }

  function saveDsCriteria(prefix, fieldKeys) {
    var data = { checks: {}, values: {} };
    fieldKeys.forEach(function (key) {
      var chk = $(prefix + '-chk-' + key);
      data.checks[key] = !!(chk && chk.checked);
      var div = $(prefix + '-crit-' + key);
      if (!div) return;
      div.querySelectorAll('input,select,textarea').forEach(function (el) {
        if (el.type === 'checkbox' || el.type === 'button' || !el.id) return;
        data.values[el.id] = el.value;
      });
    });
    if (window.RemIcsApi && RemIcsApi.sessionSetJson) RemIcsApi.sessionSetJson(dsStoreKey(prefix), data);
  }

  function restoreDsCriteria(prefix, fieldKeys) {
    var data = (window.RemIcsApi && RemIcsApi.sessionGetJson) ? RemIcsApi.sessionGetJson(dsStoreKey(prefix)) : null;
    if (!data || !data.checks) return;
    fieldKeys.forEach(function (key) {
      var chk = $(prefix + '-chk-' + key);
      if (chk) chk.checked = !!data.checks[key];
    });
    Object.keys(data.values || {}).forEach(function (id) {
      var el = $(id);
      if (el) el.value = data.values[id];
    });
  }

  function resetDsCriteria(prefix, fieldKeys) {
    fieldKeys.forEach(function (key) {
      var chk = $(prefix + '-chk-' + key);
      if (chk) chk.checked = false;
      var div = $(prefix + '-crit-' + key);
      show(div, false);
      clearCritDiv(div);
    });
  }

  function updateSqlPreview(prefix, r) {
    var showSql = $(prefix + '-showsql');
    var pre = $(prefix + '-sql-preview');
    if (!pre) return;
    var on = showSql && showSql.checked;
    show(pre, on);
    if (!on || !r) return;
    pre.textContent = 'owhere: ' + (r.owhere || '') + '\nkwhere: ' + (r.kwhere || '');
  }

  function projectCode() {
    var sel = $('project-select');
    if (sel && sel.value) return sel.value;
    var s = (global.RemicsApp && RemicsApp.getSession && RemicsApp.getSession()) || {};
    return s.project || (global.REMICS_SHELL && REMICS_SHELL.project) || '';
  }
  function rewriteRoot() {
    return (global.RemIcsApi && RemIcsApi.micsRoot)
      ? RemIcsApi.micsRoot() + 'RemIcsReWrite/'
      : '/mics/RemIcsReWrite/';
  }

  /* ---------- TS ---------- */

  function mountTs() {
    var status = $('ds-ts-status');
    function setStatus(m) { if (status) status.textContent = m || ''; }
    var tsFields = ['scall1', 'sname', 'soper', 'sprov', 'sstats', 'sreg', 'sgrnd', 'sstrlatit', 'sstrlongit', 'sradius',
      'acall2', 'abndcde', 'aanum', 'aacode', 'cchid', 'cfreqtx', 'cfreqrx'];
    restoreDsCriteria('dsts', tsFields);
    bindDsCriteria('dsts', tsFields, { latKeys: ['sstrlatit', 'sstrlongit'], radiusKey: 'sradius' });
    if (window.RemIcsApi && RemIcsApi.wireEnterAsTab) {
      RemIcsApi.wireEnterAsTab($('ds-ts-criteria'));
    }

    var fldDesc = $('dsts-flddesc');
    if (fldDesc) fldDesc.onclick = function () { openHelp('micshelp/separatefiles/dsTSFields.aspx'); };
    var helpBtn = $('dsts-help');
    if (helpBtn) helpBtn.onclick = function () { openHelp('micshelp/separatefiles/dsRules.aspx'); };
    var showSql = $('dsts-showsql');
    if (showSql) showSql.onchange = function () { updateSqlPreview('dsts', null); };

    $('dsts-clear').onclick = function () {
      resetDsCriteria('dsts', tsFields);
      if (window.RemIcsApi && RemIcsApi.sessionSet) RemIcsApi.sessionSet(dsStoreKey('dsts'), '');
      setStatus('');
      updateSqlPreview('dsts', null);
    };

    $('dsts-search').onclick = function () {
      setStatus('Searching…');
      saveDsCriteria('dsts', tsFields);
      var body = collectTsBody();

      RemIcsApi.dsSearch('searchTs', body).then(function (r) {
        if (!r.ok) { setStatus(r.error || 'Search failed'); return; }
        tsState.sites = r.sites || [];
        tsState.links = r.links || [];
        tsState.remotes = r.remotes || [];
        tsState.owhere = r.owhere || '';
        renderTsResults(r);
        show($('ds-ts-criteria'), false);
        show($('ds-ts-results'), true);
        show($('ds-ts-save'), false);
        updateSqlPreview('dsts', r);
        var msg = r.siteCount + ' site(s), ' + r.linkCount + ' link(s), ' + r.remoteCount + ' OE';
        if (r.capped) msg += ' — capped at ' + r.maxRecs;
        setStatus(msg);
      });
    };

    $('dsts-backcrit').onclick = function () {
      show($('ds-ts-results'), false);
      show($('ds-ts-save'), false);
      show($('ds-ts-criteria'), true);
    };
    $('dsts-checkall').onclick = function () {
      document.querySelectorAll('#dsts-table input[data-kind=site]').forEach(function (c) { c.checked = true; });
    };
    $('dsts-checknone').onclick = function () {
      document.querySelectorAll('#dsts-table input[type=checkbox]').forEach(function (c) { c.checked = false; });
    };
    $('dsts-save').onclick = function () {
      populatePdfSelect('dsts-exist', 'TS').then(function () {
        show($('ds-ts-save'), true);
      });
    };
    $('dsts-save-cancel').onclick = function () { show($('ds-ts-save'), false); };
    $('dsts-save-go').onclick = function () { saveTs(setStatus); };
  }

  function renderTsResults(r) {
    var tbody = $('dsts-table').querySelector('tbody');
    tbody.innerHTML = '';
    var linkByCall = {};
    (r.links || []).forEach(function (l) {
      if (!linkByCall[l.call1]) linkByCall[l.call1] = [];
      linkByCall[l.call1].push(l);
    });

    (r.sites || []).forEach(function (s) {
      var tr = document.createElement('tr');
      tr.innerHTML =
        '<td><input type="checkbox" data-kind="site" data-key="' + escAttr(s.call1) + '"></td>' +
        '<td>' + escHtml(s.call1) + '</td>' +
        '<td>' + escHtml(s.name) + '</td><td>' + escHtml(s.oper) + '</td>' +
        '<td>' + escHtml(s.prov) + '</td>' +
        '<td>' + escHtml(s.strlatit) + '</td><td>' + escHtml(s.strlongit) + '</td>' +
        '<td>' + escHtml(s.grnd) + '</td>' +
        '<td><input type="button" class="bt" value="Detail" data-call1="' + escAttr(s.call1) + '"></td>';
      tbody.appendChild(tr);
      var det = tr.querySelector('input[type=button]');
      if (det) {
        det.addEventListener('click', function () {
          RemIcsApi.dsSearch('detailTs', { call1: s.call1 }).then(function (d) {
            if (!d.ok) { $('dsts-detail').textContent = d.error || ''; return; }
            $('dsts-detail').textContent = s.call1 + ': ' + (d.antes || []).length + ' ante(s), ' +
              (d.chans || []).length + ' chan(s)';
          });
        });
      }

      var links = linkByCall[s.call1] || [];
      if (links.length) {
        var trH = document.createElement('tr');
        trH.innerHTML =
          '<td></td><td class="o">Link To:</td><td class="o">Remote Call</td><td class="o">Band</td>' +
          '<td></td><td></td><td></td><td class="o">Save O/E</td><td></td>';
        tbody.appendChild(trH);
      }
      links.forEach(function (l) {
        var trL = document.createElement('tr');
        var lkey = l.call1 + ',' + l.call2 + ',' + l.bndcde;
        var rkey = l.call2 + ',' + l.call1 + ',' + l.bndcde;
        trL.innerHTML =
          '<td><input type="checkbox" data-kind="link" data-key="' + escAttr(lkey) + '"></td>' +
          '<td></td>' +
          '<td>' + escHtml(l.call2) + '</td>' +
          '<td>' + escHtml(l.bndcde) + '</td>' +
          '<td></td><td></td><td></td>' +
          '<td><input type="checkbox" data-kind="oe" data-key="' + escAttr(rkey) + '"></td>' +
          '<td><input type="button" class="bt" value="Show O/E"></td>';
        tbody.appendChild(trL);
        var showOe = trL.querySelector('input[value="Show O/E"]');
        if (showOe) {
          showOe.addEventListener('click', function () {
            $('dsts-detail').textContent = 'O/E ' + l.call1 + ' ↔ ' + l.call2 + ' / ' + l.bndcde;
          });
        }
      });
    });
  }

  function collectTsKeys() {
    var sites = [], siteChk = '', links = [], linkChk = '', remotes = [], remChk = '';
    document.querySelectorAll('#dsts-table input[data-kind=site]').forEach(function (c) {
      sites.push(c.getAttribute('data-key') + '}}');
      siteChk += c.checked ? '1' : '0';
    });
    document.querySelectorAll('#dsts-table input[data-kind=link]').forEach(function (c) {
      links.push(c.getAttribute('data-key') + '}}');
      linkChk += c.checked ? '1' : '0';
    });
    document.querySelectorAll('#dsts-table input[data-kind=oe]').forEach(function (c) {
      remotes.push(c.getAttribute('data-key') + '}}');
      remChk += c.checked ? '1' : '0';
    });
    return {
      inkeyss: sites.join(','),
      checkss: siteChk,
      inkeysLocal: links.join(','),
      checksLocal: linkChk,
      inkeysRemote: remotes.join(','),
      checksRemote: remChk,
      any: siteChk.indexOf('1') >= 0 || linkChk.indexOf('1') >= 0 || remChk.indexOf('1') >= 0
    };
  }

  function saveTs(setStatus) {
    var keys = collectTsKeys();
    if (!keys.any) { alert('Select at least one site, link, or OE.'); return; }
    var mode = (document.querySelector('input[name=dsts-save-mode]:checked') || {}).value || 'new';
    var pdfname = mode === 'new' ? ($('dsts-newname').value || '').trim() : ($('dsts-exist').value || '').trim();
    if (!/^[A-Za-z0-9_]{1,16}$/.test(pdfname)) {
      alert('Enter a valid PDF name (1–16 A-Za-z0-9_).');
      return;
    }
    var dupMode = $('dsts-dup').value;
    var pc = projectCode();
    setStatus('Saving… clearing culls');

    var chain = Promise.resolve();
    if (mode === 'new') {
      chain = RemIcsApi.createTable(pdfname, pc, { filetype: 'TS' }).then(function (r) {
        if (!r.ok) throw new Error(r.error || r.body || 'createTable failed');
      });
    }

    chain
      .then(function () { return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'ClearCulls', { start: '1' }); })
      .then(function () {
        if (keys.inkeyss || keys.inkeysLocal) {
          return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'SaveKeysLocal', {
            inkeyss: keys.inkeyss,
            checkss: keys.checkss,
            inkeys: keys.inkeysLocal,
            checks: keys.checksLocal,
            type: 'LOCA'
          });
        }
      })
      .then(function () {
        if (keys.inkeysRemote) {
          return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'SaveKeysRemote', {
            inkeys: keys.inkeysRemote,
            checks: keys.checksRemote,
            type: 'REMO'
          });
        }
      })
      .then(function () { return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'InsertCullSites', {}); })
      .then(function () {
        var ow = (tsState.owhere || '').replace(/</g, '^');
        return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'InsertCullAntesLink', { owhere: ow })
          .then(function () { return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'InsertCullAntesOE', { owhere: ow }); })
          .then(function () { return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'InsertCullChansLink', { owhere: ow }); })
          .then(function () { return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'InsertCullChansOE', { owhere: ow }); });
      })
      .then(function () { return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'CheckDupSites', { name: pdfname }); })
      .then(function (dup) {
        var n = parseInt((dup && dup.body) || '0', 10) || 0;
        if (n > 0 && dupMode === 'over') {
          return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'DeletePDFSites', { name: pdfname });
        }
        if (n > 0 && dupMode === 'keep') {
          return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'DeleteCullSites', { name: pdfname });
        }
      })
      .then(function () { return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'InsertPDFSites', { name: pdfname }); })
      .then(function () { return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'CheckDupAntes', { name: pdfname }); })
      .then(function (dup) {
        var n = parseInt((dup && dup.body) || '0', 10) || 0;
        if (n > 0 && dupMode === 'over') return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'DeletePDFAntes', { name: pdfname });
        if (n > 0 && dupMode === 'keep') return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'DeleteCullAntes', { name: pdfname });
      })
      .then(function () { return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'InsertPDFAntes', { name: pdfname }); })
      .then(function () { return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'CheckDupChans', { name: pdfname }); })
      .then(function (dup) {
        var n = parseInt((dup && dup.body) || '0', 10) || 0;
        if (n > 0 && dupMode === 'over') return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'DeletePDFChans', { name: pdfname });
        if (n > 0 && dupMode === 'keep') return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'DeleteCullChans', { name: pdfname });
      })
      .then(function () { return RemIcsApi.dsAsmx('Tdsts/TwsdsTS.asmx', 'InsertPDFChans', { name: pdfname }); })
      .then(function () {
        return RemIcsApi.dsAsmx('Ttsmenu/TwsTStree.asmx', 'updateValidTS', {
          projectCode: pc,
          pdfname: pdfname
        });
      })
      .then(function () {
        setStatus('Save complete — ' + pdfname);
        alert('Save complete');
        show($('ds-ts-save'), false);
        if (global.RemicsApp && RemicsApp.navigate) RemicsApp.navigate('ts-tree');
      })
      .catch(function (ex) {
        setStatus(ex.message || String(ex));
        alert('Save failed: ' + (ex.message || ex));
      });
  }

  /* ---------- ES ---------- */

  function mountEs() {
    var status = $('ds-es-status');
    function setStatus(m) { if (status) status.textContent = m || ''; }
    var esFields = ['slocation', 'sname', 'soper', 'sprov', 'sstats', 'sgrnd', 'scall1', 'sstrlatit', 'sstrlongit', 'sradius', 'cchid'];
    restoreDsCriteria('dses', esFields);
    bindDsCriteria('dses', esFields, { latKeys: ['sstrlatit', 'sstrlongit'], radiusKey: 'sradius' });
    if (window.RemIcsApi && RemIcsApi.wireEnterAsTab) {
      RemIcsApi.wireEnterAsTab($('ds-es-criteria'));
    }

    var fldDesc = $('dses-flddesc');
    if (fldDesc) fldDesc.onclick = function () { openHelp('micshelp/separatefiles/dsESFields.aspx'); };
    var helpBtn = $('dses-help');
    if (helpBtn) helpBtn.onclick = function () { openHelp('micshelp/separatefiles/dsRules.aspx'); };
    var showSql = $('dses-showsql');
    if (showSql) showSql.onchange = function () { updateSqlPreview('dses', null); };

    $('dses-clear').onclick = function () {
      resetDsCriteria('dses', esFields);
      if (window.RemIcsApi && RemIcsApi.sessionSet) RemIcsApi.sessionSet(dsStoreKey('dses'), '');
      setStatus('');
      updateSqlPreview('dses', null);
    };

    $('dses-search').onclick = function () {
      setStatus('Searching…');
      saveDsCriteria('dses', esFields);
      var body = collectEsBody();

      RemIcsApi.dsSearch('searchEs', body).then(function (r) {
        if (!r.ok) { setStatus(r.error || 'Search failed'); return; }
        esState.sites = r.sites || [];
        esState.owhere = r.owhere || '';
        var tbody = $('dses-table').querySelector('tbody');
        tbody.innerHTML = '';
        (r.sites || []).forEach(function (s) {
          var tr = document.createElement('tr');
          tr.innerHTML =
            '<td><input type="checkbox" data-kind="site" data-key="' + escAttr(s.location) + '"></td>' +
            '<td>' + escHtml(s.location) + '</td>' +
            '<td>' + escHtml(s.name) + '</td><td>' + escHtml(s.oper) + '</td>' +
            '<td>' + escHtml(s.prov) + '</td>' +
            '<td>' + escHtml(s.strlatit) + '</td><td>' + escHtml(s.strlongit) + '</td>' +
            '<td>' + escHtml(s.grnd) + '</td>' +
            '<td><input type="button" class="bt" value="Detail"></td>';
          tbody.appendChild(tr);
          var det = tr.querySelector('input[type=button]');
          if (det) {
            det.addEventListener('click', function () {
              RemIcsApi.dsSearch('detailEs', { location: s.location }).then(function (d) {
                if (!d.ok) { $('dses-detail').textContent = d.error || ''; return; }
                $('dses-detail').textContent = s.location + ': ' + (d.antes || []).length + ' ante(s), ' +
                  (d.chans || []).length + ' chan(s)';
              });
            });
          }
        });
        show($('ds-es-criteria'), false);
        show($('ds-es-results'), true);
        show($('ds-es-save'), false);
        updateSqlPreview('dses', r);
        var msg = r.siteCount + ' site(s)';
        if (r.capped) msg += ' — capped at ' + r.maxRecs;
        setStatus(msg);
      });
    };

    $('dses-backcrit').onclick = function () {
      show($('ds-es-results'), false);
      show($('ds-es-save'), false);
      show($('ds-es-criteria'), true);
    };
    $('dses-checkall').onclick = function () {
      document.querySelectorAll('#dses-table input[type=checkbox]').forEach(function (c) { c.checked = true; });
    };
    $('dses-checknone').onclick = function () {
      document.querySelectorAll('#dses-table input[type=checkbox]').forEach(function (c) { c.checked = false; });
    };
    $('dses-save').onclick = function () {
      populatePdfSelect('dses-exist', 'ES').then(function () { show($('ds-es-save'), true); });
    };
    $('dses-save-cancel').onclick = function () { show($('ds-es-save'), false); };
    $('dses-save-go').onclick = function () { saveEs(setStatus); };
  }

  function saveEs(setStatus) {
    var keys = [], chk = '';
    document.querySelectorAll('#dses-table input[data-kind=site]').forEach(function (c) {
      keys.push(c.getAttribute('data-key'));
      chk += c.checked ? '1' : '0';
    });
    if (chk.indexOf('1') < 0) { alert('Select at least one site.'); return; }
    var mode = (document.querySelector('input[name=dses-save-mode]:checked') || {}).value || 'new';
    var pdfname = mode === 'new' ? ($('dses-newname').value || '').trim() : ($('dses-exist').value || '').trim();
    if (!/^[A-Za-z0-9_]{1,16}$/.test(pdfname)) {
      alert('Enter a valid PDF name (1–16 A-Za-z0-9_).');
      return;
    }
    var dupMode = $('dses-dup').value;
    var pc = projectCode();
    var keylist = keys.join(',');
    setStatus('Saving…');

    var chain = Promise.resolve();
    if (mode === 'new') {
      chain = RemIcsApi.createTable(pdfname, pc, { filetype: 'ES' }).then(function (r) {
        if (!r.ok) throw new Error(r.error || r.body || 'createTable failed');
      });
    }

    chain
      .then(function () { return RemIcsApi.dsAsmx('Tdses/TwsdsES.asmx', 'ClearCulls', { start: '1' }); })
      .then(function () { return RemIcsApi.dsAsmx('Tdses/TwsdsES.asmx', 'StoreKeys', { keylist: keylist }); })
      .then(function () {
        // StoreKeys may store all; re-filter via checks — classic ES uses checkbox parallel on list.
        // For rewrite: store only checked keys.
        var checked = [];
        keys.forEach(function (k, i) { if (chk.charAt(i) === '1') checked.push(k); });
        return RemIcsApi.dsAsmx('Tdses/TwsdsES.asmx', 'ClearCulls', { start: '1' })
          .then(function () {
            return RemIcsApi.dsAsmx('Tdses/TwsdsES.asmx', 'StoreKeys', { keylist: checked.join(',') });
          });
      })
      .then(function () {
        var ow = (esState.owhere || '').replace(/</g, '^');
        return RemIcsApi.dsAsmx('Tdses/TwsdsES.asmx', 'InsertCullAntes', { owhere: ow })
          .then(function () { return RemIcsApi.dsAsmx('Tdses/TwsdsES.asmx', 'InsertCullChans', { owhere: ow }); });
      })
      .then(function () { return RemIcsApi.dsAsmx('Tdses/TwsdsES.asmx', 'CheckDupSites', { name: pdfname }); })
      .then(function (dup) {
        var n = parseInt((dup && dup.body) || '0', 10) || 0;
        if (n > 0 && dupMode === 'over') return RemIcsApi.dsAsmx('Tdses/TwsdsES.asmx', 'DeletePDFSites', { name: pdfname });
        if (n > 0 && dupMode === 'keep') return RemIcsApi.dsAsmx('Tdses/TwsdsES.asmx', 'DeleteCullSites', { name: pdfname });
      })
      .then(function () { return RemIcsApi.dsAsmx('Tdses/TwsdsES.asmx', 'InsertPDFSites', { name: pdfname }); })
      .then(function () { return RemIcsApi.dsAsmx('Tdses/TwsdsES.asmx', 'CheckDupAntes', { name: pdfname }); })
      .then(function (dup) {
        var n = parseInt((dup && dup.body) || '0', 10) || 0;
        if (n > 0 && dupMode === 'over') return RemIcsApi.dsAsmx('Tdses/TwsdsES.asmx', 'DeletePDFAntes', { name: pdfname });
        if (n > 0 && dupMode === 'keep') return RemIcsApi.dsAsmx('Tdses/TwsdsES.asmx', 'DeleteCullAntes', { name: pdfname });
      })
      .then(function () { return RemIcsApi.dsAsmx('Tdses/TwsdsES.asmx', 'InsertPDFAntes', { name: pdfname }); })
      .then(function () { return RemIcsApi.dsAsmx('Tdses/TwsdsES.asmx', 'CheckDupChans', { name: pdfname }); })
      .then(function (dup) {
        var n = parseInt((dup && dup.body) || '0', 10) || 0;
        if (n > 0 && dupMode === 'over') return RemIcsApi.dsAsmx('Tdses/TwsdsES.asmx', 'DeletePDFChans', { name: pdfname });
        if (n > 0 && dupMode === 'keep') return RemIcsApi.dsAsmx('Tdses/TwsdsES.asmx', 'DeleteCullChans', { name: pdfname });
      })
      .then(function () { return RemIcsApi.dsAsmx('Tdses/TwsdsES.asmx', 'InsertPDFChans', { name: pdfname }); })
      .then(function () {
        // ES invalidate if available
        return RemIcsApi.dsAsmx('Tesmenu/TwsESTree.asmx', 'updateValidES', {
          projectCode: pc,
          pdfname: pdfname
        }).catch(function () { return { ok: true }; });
      })
      .then(function () {
        setStatus('Save complete — ' + pdfname);
        alert('Save complete');
        show($('ds-es-save'), false);
        if (global.RemicsApp && RemicsApp.navigate) RemicsApp.navigate('es-tree');
      })
      .catch(function (ex) {
        setStatus(ex.message || String(ex));
        alert('Save failed: ' + (ex.message || ex));
      });
  }

  function populatePdfSelect(selectId, filetype) {
    var sel = $(selectId);
    if (!sel) return Promise.resolve();
    return RemIcsApi.filesList(filetype).then(function (data) {
      if (!data.ok) return;
      sel.innerHTML = '';
      (data.files || []).forEach(function (f) {
        var opt = document.createElement('option');
        opt.value = f.name;
        opt.textContent = f.name;
        sel.appendChild(opt);
      });
    });
  }

  function escHtml(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
  function escAttr(s) {
    return String(s == null ? '' : s).replace(/"/g, '&quot;');
  }

  global.RemicsDs = { mountTs: mountTs, mountEs: mountEs };
})(window);
