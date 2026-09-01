// RemIcsReWrite Phase 3  -  TSIP parm list + batch submit + queue poll.
(function (global) {
  var selectedParm = '';
  var pollTimer = null;
  var queuePollOpts = { scope: 'user', keepAlive: false, parm: '' };
  var selectedQueueJob = null;

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

  function goParm(parm, opts) {
    opts = opts || {};
    var parts = [];
    if (parm) parts.push('parm=' + encodeURIComponent(parm));
    if (opts.run) parts.push('run=' + encodeURIComponent(opts.run));
    if (opts.saved) parts.push('saved=1');
    var q = parts.join('&');
    if (global.RemicsApp && RemicsApp.navigate) RemicsApp.navigate('tsip-parm', q);
    else location.hash = '#/tsip-parm' + (q ? '?' + q : '');
  }

  function goBatch(parm, opts) {
    opts = opts || {};
    var parts = ['parm=' + encodeURIComponent(parm || '')];
    if (opts.autostart) parts.push('run=1');
    var q = parts.join('&');
    if (global.RemicsApp && RemicsApp.navigate) RemicsApp.navigate('tsip-batch', q);
    else location.hash = '#/tsip-batch?' + q;
  }

  function stopPoll() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  window.addEventListener('pagehide', stopPoll);
  window.addEventListener('beforeunload', stopPoll);

  function formatStatusCode(st) {
    st = (st || '').toUpperCase();
    if (st === 'W') return 'Waiting';
    if (st === 'X') return 'Running';
    if (st === 'D') return 'Deleted';
    if (st === 'F') return 'Finished';
    return st || '-';
  }

  // TQ_Finish values from TpRunTsip / TsipInitiator / TsipQ (_Configuration.Error, Constant).
  var TSIP_FINISH_CODES = {
    0: { short: 'OK', detail: 'TSIP completed successfully.', kind: 'ok' },
    1: { short: 'Command-line error', detail: 'Invalid command-line arguments.', kind: 'err' },
    2: { short: 'Fatal exception', detail: 'TpRunTsip terminated with an unhandled exception.', kind: 'err' },
    100: { short: 'Queue busy', detail: 'Could not enter the TSIP read queue.', kind: 'err' },
    387: { short: 'MICSUSER not set', detail: 'Windows environment variable MICSUSER was not set for TpRunTsip.', kind: 'err' },
    666: { short: 'Report startup failed', detail: 'TpRunTsip failed while opening report files or ODBC setup (exit 666).', kind: 'err' },
    '-1': { short: 'Run errors', detail: 'TSIP finished but one or more parameter runs reported calculation errors.', kind: 'err' },
    '-129': { short: 'Process lost', detail: 'Queue monitor reset a job whose TpRunTsip process was no longer running.', kind: 'err' },
    '-2227': { short: 'No parm records', detail: 'The TSIP parameter table has no records.', kind: 'err' },
    '-2228': { short: 'Parm table missing', detail: 'The TSIP parameter table does not exist.', kind: 'err' }
  };

  function formatFinishCode(finish, status, active) {
    if (active || status === 'W' || status === 'X') {
      return { text: '-', title: '', kind: 'pending' };
    }
    if (finish === null || typeof finish === 'undefined') {
      return { text: '-', title: '', kind: 'none' };
    }
    var n = Number(finish);
    if (isNaN(n)) {
      return { text: String(finish), title: '', kind: 'unknown' };
    }
    var known = TSIP_FINISH_CODES[String(n)] || TSIP_FINISH_CODES[n];
    if (known) {
      return {
        text: known.short + ' (' + n + ')',
        title: known.detail,
        kind: known.kind || (n === 0 ? 'ok' : 'err')
      };
    }
    return { text: String(n), title: 'TSIP finish code ' + n, kind: 'unknown' };
  }

  function startQueuePoll(opts) {
    opts = opts || {};
    queuePollOpts = {
      scope: opts.scope || 'user',
      keepAlive: opts.keepAlive !== false,
      parm: opts.parm || ''
    };
    stopPoll();
    refreshQueue();
    pollTimer = setInterval(function () {
      refreshQueue().then(function (data) {
        if (queuePollOpts.keepAlive) return;
        if (!data || !data.ok || !data.jobs) return;
        var active = data.jobs.some(function (j) {
          if (!j.active) return false;
          if (queuePollOpts.parm) return j.parm === queuePollOpts.parm;
          return true;
        });
        if (!active) stopPoll();
      });
    }, 5000);
  }

  function setQueueRefreshNote(text) {
    var note = $('tsip-queue-refresh-note');
    if (note) note.textContent = text || '';
  }

  var selectedRun = '';
  var selectedEnv = '';
  var runDirty = { active: false, snapshot: '', hash: '' };

  function runSnapshot() {
    var Form = global.RemicsTsipRunForm;
    if (!Form) return '';
    return JSON.stringify({ fields: Form.fieldMap(), reports: Form.reportFlags() });
  }

  function markRunClean() {
    runDirty.active = !!$('tsip-run-heading');
    runDirty.snapshot = runDirty.active ? runSnapshot() : '';
    runDirty.hash = location.hash || '';
  }

  function isRunDirty() {
    if (!runDirty.active) return false;
    if (!$('tsip-run-heading')) {
      runDirty.active = false;
      return false;
    }
    return runSnapshot() !== runDirty.snapshot;
  }

  function canLeave() {
    if (!isRunDirty()) {
      runDirty.active = false;
      return true;
    }
    if (!window.confirm('You have unsaved changes. Leave without saving?')) {
      if (runDirty.hash && location.hash !== runDirty.hash) {
        try { history.replaceState(null, '', runDirty.hash); } catch (e) { location.hash = runDirty.hash; }
      }
      return false;
    }
    runDirty.active = false;
    return true;
  }

  function goRun(action, parm, runname) {
    var q = 'action=' + encodeURIComponent(action || 'new') +
      '&parm=' + encodeURIComponent(parm || '');
    if (runname) q += '&runname=' + encodeURIComponent(runname);
    if (global.RemicsApp && RemicsApp.navigate) RemicsApp.navigate('tsip-run', q);
    else location.hash = '#/tsip-run?' + q;
  }

  function projectCode() {
    var sel = $('project-select');
    if (sel && sel.value) return sel.value;
    var s = (global.RemicsApp && RemicsApp.getSession && RemicsApp.getSession()) || {};
    return s.project || (global.REMICS_SHELL && REMICS_SHELL.project) || '';
  }

  function isBrokenParmError(r) {
    var s = ((r && (r.error || r.body)) || '').toString();
    return /42S22|Invalid column name|protype|runname/i.test(s);
  }

  function brokenParmMsg(name) {
    return (name || 'This file') + ' is not a usable TSIP parameter table (it is missing run columns). Delete it and create a new file.';
  }

  function emptyParmMsg(name) {
    return (name || 'This parameter file') + ' has no runs yet. Use Add run, save the run, then click Run all runs in file.';
  }

  function updateWorkflowStep(step) {
    var strip = $('tsip-workflow-strip');
    if (!strip) return;
    strip.querySelectorAll('.tsip-workflow-step').forEach(function (el) {
      var n = parseInt(el.getAttribute('data-step'), 10);
      if (n === step) el.classList.add('tsip-workflow-active');
      else el.classList.remove('tsip-workflow-active');
    });
  }

  function updateBatchHint(text) {
    var hint = $('tsip-batch-hint');
    if (hint) hint.textContent = text || '';
  }

  function updateEmptyTreeState(showEmpty) {
    var panel = $('tsip-tree-empty');
    var treeEl = $('tsip-parm-tree');
    var legend = document.querySelector('.tsip-badge-legend');
    show(panel, showEmpty);
    if (treeEl) treeEl.hidden = showEmpty;
    if (legend) legend.hidden = showEmpty;
  }

  function promptCreateParm(onCreated) {
    var name = window.prompt('New TSIP parameter file name (1-16 A-Za-z0-9_):', '');
    if (!name) return;
    name = name.trim();
    if (!/^[A-Za-z0-9_]{1,16}$/.test(name)) {
      alert('Invalid name.');
      return;
    }
    var status = $('tsip-parm-status');
    if (status) status.textContent = 'Creating ' + name + '...';
    RemicsTsipApi.tsipTree().then(function (tr) {
      if (treeHasParm(tr.body, name)) {
        selectedParm = name;
        selectedRun = '';
        selectedEnv = '';
        if (status) status.textContent = 'Parameter file ' + name + ' already exists. Add a run, then Run all runs in file.';
        if (typeof onCreated === 'function') onCreated(name);
        return null;
      }
      return RemIcsApi.createTable(name, projectCode(), { filetype: 'TsipParm' }).then(function (r) {
        return RemicsTsipApi.tsipTree().then(function (after) {
          var created = treeHasParm(after.body, name) || (r && (r.ok || r.exists));
          if (!created && !r.ok) {
            if (status) status.textContent = createParmFailedMsg(r, name);
            return;
          }
          selectedParm = name;
          selectedRun = '';
          selectedEnv = '';
          if (status) status.textContent = 'Created ' + name + '. Add the first run, then Run all runs in file.';
          goRun('new', name, '');
        });
      });
    }).catch(function (ex) {
      if (status) status.textContent = 'Could not create the parameter file: ' + (ex.message || ex);
    });
  }

  function mountParm() {
    var tree = $('tsip-parm-tree');
    var status = $('tsip-parm-status');
    if (!tree || !window.RemicsTsipApi) return;

    stopPoll();
    selectedParm = '';
    selectedRun = '';
    selectedEnv = '';
    var parmValidateMap = {};
    status.textContent = 'Loading TSIP parameters...';
    tree.innerHTML = '';

    function parmValidateInfo(name) {
      return parmValidateMap[name] || { ok: null, failures: [], issueCount: 0 };
    }

    function formatValidateStatusSummary(items) {
      var ready = items.filter(function (x) { return x.valid; }).length;
      var empty = items.filter(function (x) { return x.empty; }).length;
      var broken = items.filter(function (x) { return x.broken; }).length;
      var notReady = items.length - ready - empty - broken;
      var parts = [];
      if (ready) parts.push(ready + ' ready for batch');
      if (empty) parts.push(empty + ' need a run first');
      if (notReady) parts.push(notReady + ' need validation');
      if (broken) parts.push(broken + ' invalid and should be deleted');
      if (!broken && !empty) parts.push('validated files listed first');
      return parts.join(' · ');
    }

    /** May execute TSIP: usable file with at least one saved run (Ready badge optional). */
    function canRunParm(name) {
      var v = parmValidateInfo(name);
      return !!name && !v.broken && !v.empty;
    }

    function updateSelectionUI() {
      var selNone = $('tsip-selection-none');
      var selEmpty = $('tsip-selection-empty');
      var selDetail = $('tsip-selection-detail-panel');
      var selEmptyName = $('tsip-selection-empty-name');
      var kindEl = selDetail && selDetail.querySelector('.tsip-parm-selection-kind');
      var labelEl = selDetail && selDetail.querySelector('.tsip-parm-selection-label');
      var detailEl = selDetail && selDetail.querySelector('.tsip-parm-selection-detail');

      show(selNone, !selectedParm);
      show(selEmpty, false);
      show(selDetail, false);

      if (!selectedParm) {
        updateWorkflowStep(1);
        updateBatchHint('Select or create a parameter file to begin.');
      } else {
        var v = parmValidateInfo(selectedParm);
        if (v.empty && !v.broken && !selectedRun) {
          show(selEmpty, true);
          if (selEmptyName) selEmptyName.textContent = selectedParm;
          updateWorkflowStep(2);
          updateBatchHint('Add and save at least one run to enable batch TSIP.');
        } else if (selDetail && labelEl && detailEl) {
          show(selDetail, true);
          if (!selectedRun) {
            if (kindEl) kindEl.textContent = 'Parameter file';
            labelEl.textContent = selectedParm;
            if (v.broken) {
              detailEl.textContent = brokenParmMsg(selectedParm);
              updateWorkflowStep(2);
            } else if (v.ok === true) {
              detailEl.textContent = 'Click Run all runs in file to execute every saved run.';
              updateWorkflowStep(3);
            } else if (v.ok === false) {
              detailEl.textContent = 'Has runs — batch TSIP is allowed. Note: ' +
                v.issueCount + ' run(s) reference missing or unvalidated PDFs (engine may fail).';
              updateWorkflowStep(3);
            } else {
              detailEl.textContent = 'Has runs — click Run all runs in file to execute.';
              updateWorkflowStep(3);
            }
          } else {
            if (kindEl) kindEl.textContent = 'Run definition';
            labelEl.textContent = selectedRun;
            detailEl.textContent = 'In ' + selectedParm +
              (selectedEnv ? ' · environment ' + selectedEnv : '') +
              '. Batch TSIP runs all runs in the file (not just this one).';
            updateWorkflowStep(v.empty ? 2 : 3);
          }
          if (canRunParm(selectedParm)) {
            updateBatchHint('');
          } else if (v.broken) {
            updateBatchHint('This file is not usable — delete and create a new parameter file.');
          } else if (v.empty) {
            updateBatchHint('Add and save at least one run to enable batch TSIP.');
          }
        }
      }

      var broken = !!(selectedParm && parmValidateInfo(selectedParm).broken);
      var runOk = canRunParm(selectedParm);
      setBtnEnabled('cmdTsipBatch', runOk);
      var batchBtn = $('cmdTsipBatch');
      if (batchBtn) {
        if (!selectedParm) {
          batchBtn.title = 'Select a parameter file first.';
        } else if (broken) {
          batchBtn.title = brokenParmMsg(selectedParm);
        } else if (parmValidateInfo(selectedParm).empty) {
          batchBtn.title = 'Add and save a run first, then Run all runs in file.';
        } else {
          batchBtn.title = 'Queue batch TSIP for all runs in ' + selectedParm + '.';
        }
      }
      setBtnEnabled('cmdTsipNewRun', !!selectedParm && !broken);
      setBtnEnabled('cmdTsipDelParm', !!selectedParm);
      setBtnEnabled('cmdTsipEditRun', !!selectedParm && !!selectedRun);
      setBtnEnabled('cmdTsipDupRun', !!selectedParm && !!selectedRun);
      setBtnEnabled('cmdTsipDelRun', !!selectedParm && !!selectedRun);

      if (global.RemicsApp && RemicsApp.setActiveFile) {
        RemicsApp.setActiveFile('TSIPPARM', selectedParm || '');
      }
    }

    function setBtnEnabled(id, on) {
      var b = $(id);
      if (b) b.disabled = !on;
    }

    function selectNode(el, meta) {
      tree.querySelectorAll('.reps-node.selected').forEach(function (n) { n.classList.remove('selected'); });
      if (el) el.classList.add('selected');
      selectedParm = meta && meta.parm ? meta.parm : '';
      selectedRun = meta && meta.run ? meta.run : '';
      selectedEnv = meta && meta.env ? meta.env : '';
      updateSelectionUI();
    }

    function addBadge(row, kind) {
      var badge = document.createElement('span');
      badge.className = 'reps-badge reps-badge-' + kind;
      badge.textContent = kind === 'parm' ? 'File' : 'Run';
      row.appendChild(badge);
    }

    function expandParm(parmLi, parm, twist, opts) {
      opts = opts || {};
      var childUl = parmLi.querySelector(':scope > ul.reps-children');
      if (childUl && childUl.getAttribute('data-loaded') === '1' && !opts.forceReload) {
        childUl.hidden = !childUl.hidden;
        twist.textContent = childUl.hidden ? '+' : '−';
        if (!childUl.hidden && opts.selectRun) selectLoadedRun(childUl, parm, opts.selectRun);
        return;
      }
      if (parmValidateInfo(parm).broken) {
        status.textContent = brokenParmMsg(parm);
        twist.textContent = '+';
        return;
      }
      twist.textContent = '...';
      RemicsTsipApi.runList(parm).then(function (r) {
        if (!r.ok) {
          twist.textContent = '+';
          status.textContent = isBrokenParmError(r)
            ? brokenParmMsg(parm)
            : 'Could not load runs for ' + parm + '.';
          return;
        }
        if (!childUl) {
          childUl = document.createElement('ul');
          childUl.className = 'reps-children';
          parmLi.appendChild(childUl);
        }
        childUl.innerHTML = '';
        childUl.hidden = false;
        childUl.setAttribute('data-loaded', '1');
        twist.textContent = '−';
        var body = (r.body || '').toString();
        if (!body || body === 'NONE') {
          var empty = document.createElement('li');
          var emptyRow = document.createElement('div');
          emptyRow.className = 'reps-node reps-leaf reps-empty';
          emptyRow.innerHTML = '<span class="reps-twist">·</span><span class="reps-label">(no runs yet)</span>';
          empty.appendChild(emptyRow);
          childUl.appendChild(empty);
          return;
        }
        body.split(':').forEach(function (token) {
          if (!token) return;
          var parts = token.split('.');
          var run = parts.length >= 3 ? parts[2] : token;
          var env = parts.length >= 4 ? parts[3] : '';
          var rli = document.createElement('li');
          var rrow = document.createElement('div');
          rrow.className = 'reps-node reps-leaf';
          rrow.innerHTML = '<span class="reps-twist">·</span><span class="reps-label"></span>';
          rrow.querySelector('.reps-label').textContent = run + (env ? ' (' + env + ')' : '');
          addBadge(rrow, 'run');
          var meta = { kind: 'run', parm: parm, run: run, env: env };
          rrow.setAttribute('data-run', run);
          rrow.addEventListener('click', function (ev) {
            ev.stopPropagation();
            selectNode(rrow, meta);
          });
          rrow.addEventListener('dblclick', function (ev) {
            ev.preventDefault();
            ev.stopPropagation();
            selectNode(rrow, meta);
            goRun('edit', parm, run);
          });
          rli.appendChild(rrow);
          childUl.appendChild(rli);
        });
        if (opts.selectRun) selectLoadedRun(childUl, parm, opts.selectRun);
      });
    }

    function selectLoadedRun(childUl, parm, runName) {
      if (!childUl || !runName) return;
      var want = String(runName).toLowerCase();
      var rows = childUl.querySelectorAll('.reps-node.reps-leaf[data-run]');
      for (var i = 0; i < rows.length; i++) {
        if (String(rows[i].getAttribute('data-run') || '').toLowerCase() === want) {
          selectNode(rows[i], {
            kind: 'run',
            parm: parm,
            run: rows[i].getAttribute('data-run'),
            env: ''
          });
          try { rows[i].scrollIntoView({ block: 'nearest' }); } catch (e) { /* ignore */ }
          return;
        }
      }
    }

    function focusParmFromRoute() {
      var route = parseRoute();
      var focusParm = (route.params.parm || '').trim();
      var focusRun = (route.params.run || '').trim();
      var saved = route.params.saved === '1';
      if (!focusParm) return;
      var nodes = tree.querySelectorAll('.reps-node.reps-parm');
      var targetRow = null;
      var targetLi = null;
      for (var i = 0; i < nodes.length; i++) {
        var lab = nodes[i].querySelector('.reps-label');
        if (lab && lab.textContent === focusParm) {
          targetRow = nodes[i];
          targetLi = nodes[i].parentNode;
          break;
        }
      }
      if (!targetRow || !targetLi) return;
      selectNode(targetRow, { kind: 'parm', parm: focusParm });
      var twist = targetRow.querySelector('.reps-twist');
      expandParm(targetLi, focusParm, twist, { forceReload: true, selectRun: focusRun || null });
      if (saved) {
        var runnable = canRunParm(focusParm);
        status.textContent = runnable
          ? ('Step 3: Run saved under ' + focusParm +
            (focusRun ? ' ("' + focusRun + '")' : '') +
            '. Run all runs in file is now enabled.')
          : ('Saved run' + (focusRun ? ' "' + focusRun + '"' : '') +
            ' under ' + focusParm + '. ' +
            (parmValidateInfo(focusParm).empty
              ? 'If the run does not appear, click Refresh, then Add run.'
              : 'Select this file and click Run all runs in file.'));
      }
    }

    function addValidateBadge(row, validateInfo) {
      var badge = document.createElement('span');
      if (validateInfo.empty) {
        badge.className = 'reps-badge reps-badge-invalid';
        badge.textContent = 'No runs';
        badge.title = emptyParmMsg(validateInfo.name);
      } else if (validateInfo.ok === true) {
        badge.className = 'reps-badge reps-badge-valid';
        badge.textContent = 'Ready';
        badge.title = 'All runs reference validated TS/ES PDFs  -  OK for batch TSIP';
      } else if (validateInfo.broken) {
        badge.className = 'reps-badge reps-badge-invalid';
        badge.textContent = 'Invalid';
        badge.title = brokenParmMsg(validateInfo.name);
      } else if (validateInfo.ok === false) {
        badge.className = 'reps-badge reps-badge-invalid';
        badge.textContent = validateInfo.issueCount === 1 ? '1 issue' : (validateInfo.issueCount + ' issues');
        badge.title = 'Some runs reference missing or unvalidated PDFs  -  batch TSIP will fail until fixed';
      } else {
        badge.className = 'reps-badge reps-badge-invalid';
        badge.textContent = 'Unknown';
        badge.title = 'Validation status could not be determined';
      }
      row.appendChild(badge);
    }

    function renderParmNode(name, validateInfo) {
      var li = document.createElement('li');
      var row = document.createElement('div');
      row.className = 'reps-node reps-parm' + (validateInfo.ok === true ? ' reps-parm-ready' : ' reps-parm-not-ready');
      var twist = document.createElement('span');
      twist.className = 'reps-twist';
      twist.textContent = '+';
      twist.title = 'Expand runs';
      var label = document.createElement('span');
      label.className = 'reps-label';
      label.textContent = name;
      row.appendChild(twist);
      row.appendChild(label);
      addBadge(row, 'parm');
      addValidateBadge(row, validateInfo);
      if (validateInfo.broken) {
        var brokenNote = document.createElement('span');
        brokenNote.className = 'reps-validate-note';
        brokenNote.textContent = 'not a usable parameter file';
        brokenNote.title = brokenParmMsg(name);
        row.appendChild(brokenNote);
      } else if (validateInfo.empty) {
        var emptyNote = document.createElement('span');
        emptyNote.className = 'reps-validate-note';
        emptyNote.textContent = 'Add run, Save, then Run all runs in file';
        emptyNote.title = emptyParmMsg(name);
        row.appendChild(emptyNote);
      } else if (validateInfo.ok === false && validateInfo.issueCount) {
        var note = document.createElement('span');
        note.className = 'reps-validate-note';
        note.textContent = validateInfo.issueCount + ' run(s) not validated';
        note.title = validateInfo.failures.map(function (f) {
          return f.runname + ': ' + f.pdfname + ' ' + f.message;
        }).join('\n');
        row.appendChild(note);
      }
      twist.addEventListener('click', function (ev) {
        ev.stopPropagation();
        selectNode(row, { kind: 'parm', parm: name });
        expandParm(li, name, twist);
      });
      row.addEventListener('click', function (ev) {
        if (ev.target === twist) return;
        ev.stopPropagation();
        selectNode(row, { kind: 'parm', parm: name });
      });
      row.addEventListener('dblclick', function (ev) {
        ev.preventDefault();
        ev.stopPropagation();
        selectNode(row, { kind: 'parm', parm: name });
        if (validateInfo.broken) {
          status.textContent = brokenParmMsg(name);
          return;
        }
        if (validateInfo.empty) {
          status.textContent = emptyParmMsg(name);
          goRun('new', name, '');
          return;
        }
        goBatch(name, { autostart: true });
      });
      li.appendChild(row);
      return li;
    }

    function load() {
      status.textContent = 'Loading TSIP parameters...';
      tree.innerHTML = '';
      selectedParm = '';
      selectedRun = '';
      selectedEnv = '';
      parmValidateMap = {};
      updateEmptyTreeState(false);
      updateSelectionUI();
      RemIcsApi.filesList('TsipParm').then(function (r) {
        if (!r.ok) {
          status.textContent = (r && r.expired)
            ? ((window.RemIcsApi && RemIcsApi.loginExpiredMsg) || 'Session expired  -  please log in again.')
            : 'Could not load TSIP parameter files.';
          if (r && r.expired && window.RemIcsApi && RemIcsApi.redirectToLogin) RemIcsApi.redirectToLogin();
          return;
        }
        var listed = (r.files || []).map(function (f) {
          return {
            name: f.name,
            usable: f.usable !== false,
            runCount: typeof f.runCount === 'number' ? f.runCount : null
          };
        });
        if (!listed.length) {
          updateEmptyTreeState(true);
          status.textContent = 'No TSIP parameter files yet — create one to get started.';
          return;
        }
        updateEmptyTreeState(false);
        status.textContent = 'Checking validation for ' + listed.length + ' parameter file' +
          (listed.length === 1 ? '' : 's') + '...';
        return Promise.all(listed.map(function (file) {
          var state = {
            name: file.name, apiOk: false, failures: [], issueCount: 0, ok: null,
            empty: false, runCount: file.runCount
          };
          if (!file.usable) {
            state.broken = true;
            state.error = brokenParmMsg(file.name);
            parmValidateMap[file.name] = state;
            return Promise.resolve(state);
          }
          if (file.runCount === 0) {
            state.empty = true;
            state.error = emptyParmMsg(file.name);
            parmValidateMap[file.name] = state;
            return Promise.resolve(state);
          }
          return RemicsTsipApi.tsipValidateAll(file.name).then(function (vr) {
            state.apiOk = !!vr.ok;
            if (!vr.ok) {
              state.broken = isBrokenParmError(vr);
              state.error = state.broken ? brokenParmMsg(file.name) : (vr.error || vr.body || 'validate failed');
              parmValidateMap[file.name] = state;
              return state;
            }
            var parsed = RemicsTsipApi.parseParmValidateState(vr.body);
            // Empty validate body used to mean "ready" — but that is also what an empty table returns.
            if (file.runCount == null) {
              return RemicsTsipApi.runList(file.name).then(function (rl) {
                var body = (rl && rl.body != null) ? String(rl.body) : '';
                var hasRuns = !!body && body !== 'NONE' && body.indexOf('ERROR') !== 0;
                if (!hasRuns) {
                  state.empty = true;
                  state.error = emptyParmMsg(file.name);
                } else {
                  state.ok = parsed.ok;
                  state.failures = parsed.failures;
                  state.issueCount = parsed.issueCount;
                }
                parmValidateMap[file.name] = state;
                return state;
              });
            }
            state.ok = parsed.ok;
            state.failures = parsed.failures;
            state.issueCount = parsed.issueCount;
            parmValidateMap[file.name] = state;
            return state;
          });
        })).then(function (items) {
          items.sort(function (a, b) {
            var ar = a.broken ? 4 : (a.empty ? 3 : (a.ok === true ? 0 : (a.ok === false ? 1 : 2)));
            var br = b.broken ? 4 : (b.empty ? 3 : (b.ok === true ? 0 : (b.ok === false ? 1 : 2)));
            if (ar !== br) return ar - br;
            return a.name.localeCompare(b.name, undefined, { sensitivity: 'base' });
          });
          tree.innerHTML = '';
          items.forEach(function (item) {
            tree.appendChild(renderParmNode(item.name, item));
          });
          var checkErrors = items.filter(function (x) { return !x.broken && !x.empty && x.ok == null; }).length;
          status.textContent = formatValidateStatusSummary(items.map(function (x) {
            return { valid: x.ok === true, broken: !!x.broken, empty: !!x.empty };
          })) +
            (checkErrors ? (' · ' + checkErrors + ' could not be checked') : '');
          focusParmFromRoute();
        });
      }).catch(function (ex) {
        status.textContent = 'Could not load TSIP parameter files.';
      });
    }

    $('cmdTsipRefresh').onclick = load;
    $('cmdTsipBatch').onclick = function () {
      if (!selectedParm) return;
      if (parmValidateInfo(selectedParm).broken) {
        status.textContent = brokenParmMsg(selectedParm);
        return;
      }
      if (parmValidateInfo(selectedParm).empty) {
        status.textContent = emptyParmMsg(selectedParm);
        goRun('new', selectedParm, '');
        return;
      }
      goBatch(selectedParm, { autostart: true });
    };
    function wireCreateParm() {
      promptCreateParm(function () { load(); });
    }
    ['cmdTsipCreateParm', 'cmdTsipCtaCreate', 'cmdTsipCtaCreate2'].forEach(function (id) {
      var btn = $(id);
      if (btn) btn.onclick = wireCreateParm;
    });
    var ctaAdd = $('cmdTsipCtaAddRun');
    if (ctaAdd) {
      ctaAdd.onclick = function () {
        if (!selectedParm) return;
        goRun('new', selectedParm, '');
      };
    }
    if ($('cmdTsipDelParm')) {
      $('cmdTsipDelParm').onclick = function () {
        if (!selectedParm) return;
        if (!window.confirm('Delete the TSIP parameter file ' + selectedParm.toUpperCase() +
            ' and all of its runs? This cannot be undone.')) return;
        status.textContent = 'Deleting ' + selectedParm + '...';
        RemIcsApi.killTable(selectedParm, projectCode(), { filetype: 'TsipParm' }).then(function (r) {
          if (!r.ok) {
            if (r.reconciled) load();
            var msg = apiErr(r, 'Delete failed');
            status.textContent = msg;
            alert(msg);
            return;
          }
          selectedParm = '';
          selectedRun = '';
          selectedEnv = '';
          status.textContent = 'Deleted parameter file.';
          load();
        });
      };
    }
    if ($('cmdTsipNewRun')) {
      $('cmdTsipNewRun').onclick = function () {
        if (!selectedParm) return;
        if (parmValidateInfo(selectedParm).broken) {
          status.textContent = brokenParmMsg(selectedParm);
          return;
        }
        goRun('new', selectedParm, '');
      };
    }
    if ($('cmdTsipEditRun')) {
      $('cmdTsipEditRun').onclick = function () {
        if (!selectedParm || !selectedRun) return;
        goRun('edit', selectedParm, selectedRun);
      };
    }
    if ($('cmdTsipDupRun')) {
      $('cmdTsipDupRun').onclick = function () {
        if (!selectedParm || !selectedRun) return;
        goRun('dup', selectedParm, selectedRun);
      };
    }
    if ($('cmdTsipDelRun')) {
      $('cmdTsipDelRun').onclick = function () {
        if (!selectedParm || !selectedRun) return;
        if (!window.confirm('Delete run ' + selectedRun + ' from ' + selectedParm + '?')) return;
        RemIcsApi.tsipRun('delete', { parm: selectedParm, runname: selectedRun }).then(function (r) {
          if (!r.ok) { alert(apiErr(r, 'Delete failed')); return; }
          selectedRun = '';
          selectedEnv = '';
          load();
        });
      };
    }
    if ($('cmdTsipParmHelp')) {
      $('cmdTsipParmHelp').onclick = function () {
        micsHelp('micshelp/tsipParmTree.aspx');
      };
    }

    updateSelectionUI();
    load();
  }

  function mountRun() {
    var route = parseRoute();
    var action = (route.params.action || 'new').toLowerCase();
    var parm = (route.params.parm || '').trim();
    var runname = (route.params.runname || '').trim();
    var status = $('tsip-run-status');
    var origRun = runname;
    var Form = global.RemicsTsipRunForm;
    var Val = global.RemicsTsipValidation;
    if (!parm) {
      if (status) status.textContent = 'Missing parm.';
      return;
    }
    if (!Form || !Val) {
      if (status) status.textContent = 'TSIP form modules not loaded.';
      return;
    }
    $('tsip-run-parm').textContent = parm;
    $('tsip-run-heading').textContent =
      action === 'edit' ? 'FCSA TSIP Edit Run' :
      action === 'dup' ? 'FCSA TSIP Duplicate Run' : 'FCSA TSIP New Run';

    var stepBanner = $('tsip-run-step-banner');
    var stepParm = $('tsip-run-step-parm');
    if (stepBanner) {
      var showBanner = action === 'new';
      show(stepBanner, showBanner);
      if (stepParm) stepParm.textContent = parm;
    }

    Form.mount({ action: action });
    if (window.RemIcsApi && RemIcsApi.wireEnterAsTab) {
      RemIcsApi.wireEnterAsTab($('view-host') || document.body);
      RemIcsApi.firstFocus($('view-host'), ['tr-runname', 'tr-proname', 'tr-envname']);
    }

    if ($('tsip-run-help')) {
      $('tsip-run-help').onclick = function () {
        micsHelp('micshelp/tsipRun.aspx');
      };
    }

    function leaveRunWithoutSave() {
      if (Form && Form.beginLeaveForm) Form.beginLeaveForm();
      runDirty.active = false;
      goParm();
      setTimeout(function () {
        if (Form && Form.endLeaveForm) Form.endLeaveForm();
      }, 0);
    }

    function bindLeave(id) {
      var el = $(id);
      if (!el) return;
      el.onmousedown = function () {
        if (Form && Form.beginLeaveForm) Form.beginLeaveForm();
      };
      el.onclick = function (ev) {
        if (ev && ev.preventDefault) ev.preventDefault();
        leaveRunWithoutSave();
      };
    }

    bindLeave('tsip-run-back');
    bindLeave('tsip-run-cancel');
    $('tsip-run-save').onclick = function () {
      var fields = Form.fieldMap();
      var rpt = Form.reportFlags();
      fields.parm = parm;
      if (action === 'edit') fields.origRunname = origRun;
      var v = Val.validate(fields, rpt);
      if (!v.ok) {
        alert(v.errors.join('\n'));
        if (status) status.textContent = 'Validation failed.';
        return;
      }
      var payload = v.fields;
      payload.parm = parm;
      if (action === 'edit') payload.origRunname = origRun;
      var act = action === 'edit' ? 'save' : 'new';
      if (status) status.textContent = 'Saving...';
      RemIcsApi.tsipRun(act, payload).then(function (r) {
        if (!r.ok) {
          if (status) status.textContent = apiErr(r, 'Save failed');
          alert(apiErr(r, 'Save failed'));
          return;
        }
        markRunClean();
        runDirty.active = false;
        goParm(parm, { run: payload.runname || fields.runname, saved: true });
      });
    };

    if (action === 'edit' || action === 'dup') {
      if (status) status.textContent = 'Loading run...';
      RemIcsApi.tsipRun('get', { parm: parm, runname: runname }).then(function (r) {
        if (!r.ok) {
          if (status) status.textContent = apiErr(r, 'Load failed');
          return;
        }
        Form.fillRecord(r.record, action);
        if (action === 'dup' && $('tr-runname')) {
          $('tr-runname').value = '';
          $('tr-runname').focus();
        }
        if (status) status.textContent = '';
        markRunClean();
      });
    } else {
      Form.initNewDefaults();
      markRunClean();
    }
  }

  function friendlyApiError(err) {
    if (window.RemIcsApi && RemIcsApi.friendlyAsmxError) {
      return RemIcsApi.friendlyAsmxError(err || 'Unable to load queue.');
    }
    if (!err) return 'Unable to load queue.';
    var s = String(err);
    if (/Tlogin\.aspx|<!DOCTYPE/i.test(s)) {
      return 'Session expired  -  log off and sign in again via RemIcsReWrite/login.aspx.';
    }
    if (s.length > 180) return s.substring(0, 180) + '...';
    return s;
  }

  function apiErr(r, fallback) {
    if (window.RemIcsApi && RemIcsApi.apiErr) return RemIcsApi.apiErr(r, fallback);
    return (r && (r.error || r.body)) || fallback || 'Request failed.';
  }

  function parmNamesFromTree(body) {
    var text = (body == null) ? '' : String(body);
    if (!text || text === 'NONE' || text.indexOf('ERROR') === 0 || text.indexOf('timeout') === 0) return [];
    return text.split(':').map(function (n) { return n.trim(); }).filter(Boolean);
  }

  function treeHasParm(body, name) {
    var want = (name || '').toLowerCase();
    return parmNamesFromTree(body).some(function (n) { return n.toLowerCase() === want; });
  }

  function createParmFailedMsg(r, name) {
    var raw = ((r && (r.body || r.error)) || '').toString();
    if (/Copying tables failed|already an object|Invalid return code/i.test(raw)) {
      return 'Could not create ' + name + '. That name may already be in use — pick a different name, or Refresh to use the existing file.';
    }
    if (/Unspecified error running CopyTable/i.test(raw)) {
      return 'CopyTable finished but the web job log could not be updated. Refresh the list — the file may already be there.';
    }
    return apiErr(r, 'createTable failed');
  }

  function parseTsipDeleteResult(r, jobno) {
    var body = (r && r.body != null) ? String(r.body) : '';
    var job = String(jobno);
    if (body.indexOf('OK:0') === 0) {
      return { ok: true, message: 'TSIP batch job ' + job + ' submission cancelled.' };
    }
    if (body.indexOf('OK:1') === 0) {
      return { ok: false, message: 'TSIP batch job ' + job + ' was not found in the queue. Deletion cancelled.' };
    }
    if (body.indexOf('OK:2') === 0) {
      return { ok: false, message: 'TSIP batch job ' + job + ' does not belong to you. Deletion cancelled.' };
    }
    if (body.indexOf('OK:3') === 0) {
      return { ok: false, message: 'TSIP batch job ' + job + ' has already started. Only jobs that have not started can be cancelled this way.' };
    }
    if (body.indexOf('ERROR:123') === 0) {
      return { ok: false, message: 'The job queue is busy. Try again in a moment.' };
    }
    if (body.indexOf('ERROR:10') === 0 || body.indexOf('ERROR:125') === 0) {
      return { ok: false, message: 'Could not update the job queue. Job not deleted.' };
    }
    return { ok: false, message: apiErr(r, 'System error deleting TSIP batch job. Job not deleted.') };
  }

  function deleteQueueJob(jobno) {
    var job = String(jobno || '').trim();
    if (!job) return;
    if (!window.confirm('Cancel submission of waiting TSIP batch job ' + job + '?')) return;
    RemicsTsipApi.tsipDelete(job).then(function (r) {
      var parsed = parseTsipDeleteResult(r, job);
      alert(parsed.message);
      if (parsed.ok) selectedQueueJob = null;
      refreshQueue();
    }).catch(function (ex) {
      alert('Cancel error: ' + (ex.message || ex));
    });
  }

  function sessionUser() {
    return (session().user || '').toLowerCase();
  }

  function isOwnQueueJob(j) {
    var me = sessionUser();
    if (!j) return false;
    var id = (j.micsid || '').toLowerCase();
    if (id) return !!me && id === me;
    return (queuePollOpts.scope || 'user') === 'user';
  }

  function updateCancelJobButton() {
    var btn = $('cmdTsipCancelJob');
    if (!btn) return;
    btn.disabled = !selectedQueueJob || !selectedQueueJob.own || selectedQueueJob.status !== 'W';
  }

  function cancelSelectedQueueJob() {
    if (!selectedQueueJob || !selectedQueueJob.own) {
      alert('Select a job that belongs to you first.');
      return;
    }
    if (selectedQueueJob.status !== 'W') {
      alert('Only jobs that have not started can be cancelled this way.');
      return;
    }
    deleteQueueJob(selectedQueueJob.job);
  }

  function renderQueue(data, metaByJob, showUser) {
    var tbody = $('tsip-queue-body');
    if (!tbody) return;
    tbody.innerHTML = '';
    var colCount = showUser ? 8 : 7;
    if (!data || !data.ok) {
      var tr = document.createElement('tr');
      var td = document.createElement('td');
      td.colSpan = colCount;
      td.textContent = friendlyApiError(data && data.error);
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }
    var jobs = data.jobs || [];
    if (!jobs.length) {
      var tr0 = document.createElement('tr');
      var td0 = document.createElement('td');
      td0.colSpan = colCount;
      td0.textContent = showUser ? '(no active or recently finished jobs)' : '(no jobs for this user)';
      tr0.appendChild(td0);
      tbody.appendChild(tr0);
      return;
    }
    metaByJob = metaByJob || {};
    jobs = jobs.slice().sort(function (a, b) {
      var da = a.timeIn || '';
      var db = b.timeIn || '';
      if (da !== db) return da < db ? 1 : -1;
      return (Number(b.job) || 0) - (Number(a.job) || 0);
    });
    jobs.forEach(function (j) {
      var g = metaByJob[String(j.job)];
      var tr = document.createElement('tr');
      var ownJob = isOwnQueueJob(j);
      var classes = [];
      if (j.active) classes.push('tsip-queue-active-row');
      else if (j.status === 'F') classes.push('tsip-queue-finished-row');
      if (ownJob) classes.push('tsip-queue-own');
      if (selectedQueueJob && String(selectedQueueJob.job) === String(j.job) && ownJob) {
        classes.push('tsip-queue-selected');
        selectedQueueJob = { job: j.job, status: j.status, own: true };
      }
      tr.className = classes.join(' ');
      tr.setAttribute('data-job', String(j.job));
      if (ownJob) {
        tr.title = 'Click to select this job';
        tr.addEventListener('click', function () {
          selectedQueueJob = { job: j.job, status: j.status, own: true };
          tbody.querySelectorAll('tr').forEach(function (row) {
            row.classList.remove('tsip-queue-selected');
          });
          tr.classList.add('tsip-queue-selected');
          updateCancelJobButton();
        });
      }
      var finishInfo = formatFinishCode(j.finish, j.status, j.active);
      var cols = [
        String(j.job),
        formatStatusCode(j.status),
        finishInfo,
        j.parm || '',
        j.active ? 'yes' : 'no',
        j.timeIn || '',
        (g && g.glance) ? g.glance : ''
      ];
      if (showUser) cols.splice(4, 0, j.micsid || '');
      cols.forEach(function (val, idx) {
        var td = document.createElement('td');
        if (idx === 2 && val && typeof val === 'object') {
          td.textContent = val.text;
          if (val.title) td.title = val.title;
          if (val.kind === 'ok') td.className = 'tsip-finish-ok';
          else if (val.kind === 'err') td.className = 'tsip-finish-err';
        } else {
          td.textContent = val;
        }
        tr.appendChild(td);
      });
      tbody.appendChild(tr);
    });
    if (selectedQueueJob) {
      var stillThere = jobs.some(function (j) {
        return String(j.job) === String(selectedQueueJob.job) && isOwnQueueJob(j);
      });
      if (!stillThere) selectedQueueJob = null;
    }
    updateCancelJobButton();
  }

  function updateBatchTime() {
    var el = $('tsip-batch-time');
    if (el) el.textContent = new Date().toLocaleString();
  }

  function micsHelp(path) {
    var root = (window.RemIcsApi && RemIcsApi.micsRoot) ? RemIcsApi.micsRoot() : '/mics/';
    window.open(root + path, 'WndHelp', 'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=720,height=520');
  }

  function refreshQueue() {
    updateBatchTime();
    var scope = queuePollOpts.scope || 'user';
    var showUser = scope === 'all' || scope === 'active';
    var userHead = $('tsip-queue-user-head');
    if (userHead) userHead.hidden = !showUser;
    return RemicsTsipApi.status({ scope: scope }).then(function (data) {
      if (!data || !data.ok) {
        renderQueue(data, null, showUser);
        setQueueRefreshNote('Queue refresh failed  -  click Refresh Queue or wait for retry.');
        return data;
      }
      return RemicsTsipApi.repsMeta({}).then(function (meta) {
        var byJob = {};
        if (meta && meta.ok && meta.runs) {
          meta.runs.forEach(function (row) {
            if (row.queueJobId != null) byJob[String(row.queueJobId)] = row;
          });
        }
        renderQueue(data, byJob, showUser);
        var activeCount = (data.jobs || []).filter(function (j) { return j.active; }).length;
        var finishedCount = (data.jobs || []).filter(function (j) { return !j.active && j.status === 'F'; }).length;
        var note = 'Auto-refresh every 5 seconds  -  last updated ' + new Date().toLocaleTimeString();
        if (activeCount) note += '  -  ' + activeCount + ' active job(s)';
        if (finishedCount) note += '  -  ' + finishedCount + ' finished in last 24h';
        setQueueRefreshNote(note);
        return data;
      }).catch(function () {
        renderQueue(data, null, showUser);
        setQueueRefreshNote('Auto-refresh every 5 seconds  -  last updated ' + new Date().toLocaleTimeString());
        return data;
      });
    });
  }

  function wireBatchButtons(monitorOnly, deleteMode) {
    var cancel = $('cmdTsipCancel');
    var ret = $('cmdTsipReturn');
    var closeBtn = $('cmdTsipClose');
    var poll = $('cmdTsipPoll');
    var help = $('cmdTsipHelp');
    if (cancel) cancel.onclick = function () { stopPoll(); goParm(); };
    if (ret) ret.onclick = function () { stopPoll(); goParm(); };
    if (closeBtn) closeBtn.onclick = function () { stopPoll(); goParm(); };
    if (poll) poll.onclick = function () { refreshQueue(); };
    var cancelJob = $('cmdTsipCancelJob');
    if (cancelJob) cancelJob.onclick = cancelSelectedQueueJob;
    if (help) {
      help.onclick = function () {
        var page = deleteMode ? 'micshelp/tsipDelete.aspx'
          : monitorOnly ? 'micshelp/tsipMonitor.aspx'
          : 'micshelp/tsipBatch.aspx';
        micsHelp(page);
      };
    }
  }

  function mountBatch() {
    selectedQueueJob = null;
    var route = parseRoute();
    var parm = (route.params.parm || '').trim();
    var monitorOnly = route.params.monitor === '1' || !parm;
    var deleteMode = route.params.delete === '1';
    var nameEl = $('tsip-batch-name');
    var heading = $('tsip-batch-heading');
    if (nameEl) nameEl.textContent = parm || '';
    if (heading) {
      heading.textContent = deleteMode ? 'FCSA MICS Delete TSIP Job'
        : monitorOnly ? 'FCSA MICS Monitor TSIP'
        : 'FCSA MICS Run TSIP';
    }

    stopPoll();
    wireBatchButtons(monitorOnly, deleteMode);
    show($('tsip-b2'), true);

    if (monitorOnly) {
      show($('tsip-b0'), false);
      show($('tsip-b1'), false);
      if ($('tsip-batch-note')) show($('tsip-batch-note'), false);
      var msg = $('tsip-batch-msg');
      if (msg) {
        msg.textContent = deleteMode
          ? 'Select a job that belongs to you, then Cancel submission. Only jobs that have not started can be cancelled this way.'
          : 'Active TSIP jobs and jobs finished in the last 24 hours (all users). ' +
            'Select a job that belongs to you, then Cancel submission. Only jobs that have not started can be cancelled this way.';
      }
      startQueuePoll({ scope: 'all', keepAlive: true });
      return;
    }

    show($('tsip-b0'), true);
    show($('tsip-b1'), false);
    if ($('tsip-batch-note')) show($('tsip-batch-note'), true);
    var batchMsg = $('tsip-batch-msg');
    if (batchMsg) batchMsg.textContent = '';
    startQueuePoll({ scope: 'user', keepAlive: true, parm: parm });

    var runBtn = $('cmdRunTsip');
    if (!runBtn) return;
    var wantAutostart = route.params.run === '1';

    function rejectEmptyParm() {
      var msg = $('tsip-batch-msg');
      if (msg) msg.textContent = emptyParmMsg(parm);
      alert(emptyParmMsg(parm));
      goRun('new', parm, '');
    }

    function startTsipJob() {
      var btn = runBtn;
      btn.disabled = true;
      show($('tsip-b0'), false);
      show($('tsip-b1'), true);
      var msg = $('tsip-batch-msg');

      RemicsTsipApi.runList(parm).then(function (rl) {
        if (!rl || !rl.ok) {
          show($('tsip-b1'), false);
          show($('tsip-b0'), true);
          btn.disabled = false;
          alert((rl && (rl.error || rl.body)) || 'Could not check runs for this parameter file.');
          return null;
        }
        var runsBody = (rl.body == null) ? '' : String(rl.body);
        if (!runsBody || runsBody === 'NONE' || runsBody.indexOf('ERROR') === 0) {
          show($('tsip-b1'), false);
          show($('tsip-b0'), true);
          btn.disabled = true;
          rejectEmptyParm();
          return null;
        }
        return RemicsTsipApi.tsipValidateAll(parm);
      }).then(function (v) {
        if (!v) return null;
        if (!v.ok) {
          show($('tsip-b1'), false);
          show($('tsip-b0'), true);
          btn.disabled = false;
          alert(v.error || v.body || 'Validate failed');
          return null;
        }
        var body = (v.body === null || typeof v.body === 'undefined') ? '' : String(v.body);
        if (body !== '') {
          var fails = RemicsTsipApi.parseValidateFailures(body);
          fails.forEach(function (f) {
            alert('Run Number: ' + f.runname + ' File: ' + f.pdfname + ' ' + f.message);
          });
          alert('TSIP submission cancelled');
          show($('tsip-b1'), false);
          show($('tsip-b0'), true);
          btn.disabled = false;
          return null;
        }
        return RemicsTsipApi.tsipRun(parm);
      }).then(function (r) {
        if (!r) return;
        show($('tsip-b1'), false);
        show($('tsip-b0'), true);
        btn.disabled = false;
        var text = (r.body || '').toString();
        if (text.indexOf('OK:0') === 0) {
          if (msg) {
            msg.innerHTML = '<b>TSIP submitted for parameter file ' + parm + '</b><br>' +
              'Calculations run in the background. Watch the queue below ' +
              '(completion email is suppressed on CloudMics 2022).<br>' +
              '<a href="#/tsip-reps">Retrieve TSIP Reports</a> when the job finishes.';
          }
        } else if (text.indexOf('OK:2') === 0) {
          if (msg) msg.textContent = 'Cancelled  -  already in queue (OK:2).';
        } else {
          if (msg) msg.textContent = 'FAILED: ' + (r.error || text);
        }
        startQueuePoll({ scope: 'user', keepAlive: true, parm: parm });
      }).catch(function (ex) {
        show($('tsip-b1'), false);
        show($('tsip-b0'), true);
        btn.disabled = false;
        alert('TSIP error: ' + (ex.message || ex));
      });
    }

    RemicsTsipApi.runList(parm).then(function (rl) {
      var body = (rl && rl.ok && rl.body != null) ? String(rl.body) : '';
      var hasRuns = !!body && body !== 'NONE' && body.indexOf('ERROR') !== 0;
      if (!hasRuns) {
        runBtn.disabled = true;
        var pre = $('tsip-batch-msg');
        if (pre) pre.textContent = emptyParmMsg(parm) + ' Run TSIP is disabled until a run exists.';
        return;
      }
      if (wantAutostart) {
        startTsipJob();
      }
    });

    runBtn.onclick = startTsipJob;
  }

  function session() {
    if (global.RemicsApp && RemicsApp.getSession) return RemicsApp.getSession() || {};
    return global.REMICS_SHELL || {};
  }

  function reportTxtUrl(baseName) {
    var s = session();
    var schema = (s.schema || (global.REMICS_SHELL && REMICS_SHELL.schema) || '').toLowerCase();
    var user = (s.user || (global.REMICS_SHELL && REMICS_SHELL.user) || '').toLowerCase();
    var root = (window.RemIcsApi && RemIcsApi.micsRoot) ? RemIcsApi.micsRoot() : RemicsTsipApi.micsRoot();
    return root + 'userdirs/' + schema + '/' + user + '/' + baseName + '.txt';
  }

  function openCopiedReport(baseName) {
    var name = (baseName || '').toString();
    if (name.indexOf('ERROR') === 0) {
      alert(friendlyApiError(name));
      return;
    }
    window.open(
      reportTxtUrl(name),
      'WndTSIP',
      'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,status=yes'
    );
  }

  function setActiveRep(parm) {
    if (global.RemicsApp && RemicsApp.setActiveFile) {
      RemicsApp.setActiveFile('TSIPREP', parm || '');
    }
  }

  function mountReps() {
    var tree = $('tsip-reps-tree');
    var status = $('tsip-reps-status');
    var glanceEl = $('tsip-reps-glance');
    if (!tree || !window.RemicsTsipApi) return;

    var selected = null; // { kind:'p'|'e'|'r'|'f', parm, run?, filetype?, fileName?, glance?, glanceKind? }
    var metaByRun = {}; // key parm\trun -> meta row

    function metaKey(parm, run) {
      return (parm || '') + '\t' + (run || '');
    }

    function setGlanceBanner(meta) {
      if (!glanceEl) return;
      if (!meta || !meta.glance) {
        glanceEl.hidden = true;
        glanceEl.textContent = '';
        glanceEl.className = 'classic-glance';
        return;
      }
      var label = meta.parm && meta.run
        ? (meta.parm + ' / ' + meta.run + '  -  ' + meta.glance)
        : meta.glance;
      glanceEl.hidden = false;
      glanceEl.textContent = label;
      glanceEl.className = 'classic-glance ' + (meta.glanceKind || 'unknown');
    }

    function selectNode(el, meta) {
      tree.querySelectorAll('.reps-node.selected').forEach(function (n) {
        n.classList.remove('selected');
      });
      if (el) el.classList.add('selected');
      selected = meta;
      setActiveRep(meta && meta.parm ? meta.parm : '');
      if (meta && meta.run) {
        var row = metaByRun[metaKey(meta.parm, meta.run)];
        setGlanceBanner(row || { parm: meta.parm, run: meta.run, glance: meta.glance, glanceKind: meta.glanceKind });
      } else if (meta && meta.kind === 'p') {
        setGlanceBanner(null);
      } else {
        setGlanceBanner(meta && meta.glance ? meta : null);
      }
    }

    function displaySelected() {
      if (!selected) {
        alert('Select a report file (or ERRORS) first.');
        return;
      }
      var fileName = '';
      var openOpts = { parm: selected.parm };
      if (selected.kind === 'e') {
        fileName = 'tsip_' + selected.parm + '.ERR';
        openOpts.fileType = 'ERR';
      } else if (selected.kind === 'f') {
        fileName = 'tsip_' + selected.parm + '_' + selected.run + '.' + selected.filetype;
        openOpts.run = selected.run;
        openOpts.fileType = selected.filetype;
        if (selected.runId != null) openOpts.runId = selected.runId;
      } else {
        alert('Double-click or select a report type under a run (or ERRORS).');
        return;
      }
      status.textContent = 'Opening ' + fileName + '...';
      RemicsTsipApi.repsOpen(openOpts).then(function (r) {
        if (!r.ok) {
          status.textContent = apiErr(r, 'Open failed');
          alert(status.textContent);
          return;
        }
        status.textContent = 'Opened ' + fileName + (r.source === 'archive' ? ' (from archive)' : '');
        openCopiedReport(r.baseName || fileName);
      }).catch(function (ex) {
        status.textContent = 'Error: ' + (ex.message || ex);
      });
    }

    function deleteSelected() {
      if (!selected) {
        alert('Select a parameter or report file to delete.');
        return;
      }
      if (selected.kind === 'f' && selected.source === 'archive') {
        alert('This report is loaded from the web archive (not on disk). ' +
          'Deleting removes only userdir copies; use Display Results without delete, or re-run batch TSIP to refresh disk files.');
        return;
      }
      if (selected.kind === 'p') {
        if (selected.archive && !selected.disk) {
          alert('These reports are loaded from the web archive (not on disk). ' +
            'Deleting removes only userdir copies; the archive set would still appear after refresh.');
          return;
        }
        if (!confirm('Delete all on-disk output from parameter file ' + selected.parm + '?')) return;
        RemicsTsipApi.deleteRepAll('tsip_' + selected.parm).then(function (r) {
          if (!r.ok) alert(apiErr(r, 'Delete failed'));
          loadRoot();
        });
        return;
      }
      if (selected.kind === 'e') {
        var errName = 'tsip_' + selected.parm + '.ERR';
        if (!confirm('Delete ' + errName + '?')) return;
        RemicsTsipApi.deleteRepFile(errName).then(function (r) {
          if (!r.ok) alert(apiErr(r, 'Delete failed'));
          loadRoot();
        });
        return;
      }
      if (selected.kind === 'f') {
        var fn = 'tsip_' + selected.parm + '_' + selected.run + '.' + selected.filetype;
        if (!confirm('Delete ' + fn + '?')) return;
        RemicsTsipApi.deleteRepFile(fn).then(function (r) {
          if (!r.ok) alert(apiErr(r, 'Delete failed'));
          loadRoot();
        });
        return;
      }
      alert('Select a parameter (all reports) or a single report file.');
    }

    function addFileNode(parentUl, file) {
      var li = document.createElement('li');
      var row = document.createElement('div');
      row.className = 'reps-node reps-leaf';
      row.innerHTML = '<span class="reps-twist">·</span><span></span>';
      var label = file.text || file.label || file.filetype || file.type;
      row.lastChild.textContent = label;
      if (file.source === 'archive') {
        var tag = document.createElement('span');
        tag.className = 'reps-archive-tag';
        tag.textContent = 'archive';
        tag.title = 'Report restored from web.tsip_run_report_line';
        row.appendChild(tag);
      }
      row.title = 'tsip_' + file.parm + '_' + file.run + '.' + (file.filetype || file.type);
      var meta = {
        kind: 'f',
        parm: file.parm,
        run: file.run,
        filetype: file.filetype || file.type,
        runId: file.runId != null ? file.runId : null,
        source: file.source || 'disk'
      };
      row.addEventListener('click', function (ev) {
        ev.stopPropagation();
        selectNode(row, meta);
      });
      row.addEventListener('dblclick', function (ev) {
        ev.preventDefault();
        ev.stopPropagation();
        selectNode(row, meta);
        displaySelected();
      });
      li.appendChild(row);
      parentUl.appendChild(li);
    }

    function expandParm(parmLi, parm, twist) {
      var childUl = parmLi.querySelector(':scope > ul.reps-children');
      if (childUl && childUl.getAttribute('data-loaded') === '1') {
        var hide = !childUl.hidden;
        childUl.hidden = hide;
        twist.textContent = hide ? '+' : '−';
        return;
      }
      twist.textContent = '...';
      Promise.all([
        RemicsTsipApi.repsTree({ mode: 'parm', parm: parm }),
        RemicsTsipApi.repsMeta({ parm: parm }).catch(function () { return { ok: false, runs: [] }; })
      ]).then(function (results) {
        var treeData = results[0];
        var meta = results[1];
        if (!treeData || !treeData.ok) {
          status.textContent = (treeData && treeData.error) || 'Could not load reports for ' + parm;
          twist.textContent = '+';
          return;
        }
        if (meta && meta.ok && meta.runs) {
          meta.runs.forEach(function (row) {
            metaByRun[metaKey(row.parm, row.run)] = row;
          });
        }
        if (!childUl) {
          childUl = document.createElement('ul');
          childUl.className = 'reps-children';
          parmLi.appendChild(childUl);
        }
        childUl.innerHTML = '';
        childUl.hidden = false;
        childUl.setAttribute('data-loaded', '1');
        twist.textContent = '−';

        if (treeData.hasErrors) {
          var eli = document.createElement('li');
          var erow = document.createElement('div');
          erow.className = 'reps-node reps-leaf';
          erow.innerHTML = '<span class="reps-twist">·</span><span></span>';
          erow.lastChild.textContent = 'ERRORS';
          var emeta = { kind: 'e', parm: parm };
          erow.addEventListener('click', function (ev) {
            ev.stopPropagation();
            selectNode(erow, emeta);
          });
          erow.addEventListener('dblclick', function (ev) {
            ev.preventDefault();
            ev.stopPropagation();
            selectNode(erow, emeta);
            displaySelected();
          });
          eli.appendChild(erow);
          childUl.appendChild(eli);
        }

        (treeData.runs || []).forEach(function (run) {
          var rli = document.createElement('li');
          var rrow = document.createElement('div');
          rrow.className = 'reps-node';
          var rtwist = document.createElement('span');
          rtwist.className = 'reps-twist';
          rtwist.textContent = run.files && run.files.length ? '−' : '·';
          var rlabel = document.createElement('span');
          rlabel.textContent = run.label || ('Run-' + run.run);
          rrow.appendChild(rtwist);
          rrow.appendChild(rlabel);
          var info = metaByRun[metaKey(parm, run.run)];
          if (info && info.glance) {
            var gtag = document.createElement('span');
            gtag.className = 'reps-glance-tag ' + (info.glanceKind || 'unknown');
            gtag.textContent = '(' + info.glance + ')';
            rrow.appendChild(gtag);
          }
          rrow.addEventListener('click', function (ev) {
            ev.stopPropagation();
            selectNode(rrow, {
              kind: 'r',
              parm: parm,
              run: run.run,
              glance: info && info.glance,
              glanceKind: info && info.glanceKind
            });
            var ful = rli.querySelector(':scope > ul.reps-children');
            if (ful) {
              ful.hidden = !ful.hidden;
              rtwist.textContent = ful.hidden ? '+' : '−';
            }
          });
          rli.appendChild(rrow);
          if (run.files && run.files.length) {
            var ful = document.createElement('ul');
            ful.className = 'reps-children';
            run.files.forEach(function (f) {
              addFileNode(ful, {
                parm: parm,
                run: run.run,
                filetype: f.type,
                text: f.label || f.type,
                source: f.source,
                runId: f.runId != null ? f.runId : run.runId
              });
            });
            rli.appendChild(ful);
          }
          childUl.appendChild(rli);
        });

        if (!treeData.hasErrors && !(treeData.runs && treeData.runs.length)) {
          var empty = document.createElement('li');
          empty.innerHTML = '<div class="reps-node reps-leaf"><span class="reps-twist">·</span><span>(no report files)</span></div>';
          childUl.appendChild(empty);
        }
        status.textContent = 'Reports for ' + parm + ' loaded.';
      }).catch(function (ex) {
        twist.textContent = '+';
        status.textContent = 'Error: ' + (ex.message || ex);
      });
    }

    function loadRoot() {
      selected = null;
      metaByRun = {};
      setGlanceBanner(null);
      status.textContent = 'Loading TSIP Report Files...';
      tree.innerHTML = '';
      RemicsTsipApi.repsTree({ mode: 'root' }).then(function (data) {
        if (!data || !data.ok) {
          status.textContent = (data && data.error) || 'Could not load TSIP reports';
          return;
        }
        var parms = data.parms || [];
        if (!parms.length) {
          var who = data.user || session().user || 'this account';
          var dir = data.userDir || 'userdirs';
          status.textContent =
            'No TSIP reports for ' + who + '. Run batch TSIP and wait for the job to finish, ' +
            'then refresh. Reports are stored under ' + dir + ' (tsip_<parm>.ERR) or in the web archive.';
          return;
        }
        status.textContent = parms.length + ' parameter report set(s)  -  click to expand';
        parms.forEach(function (row) {
          var parm = row.parm || row;
          if (typeof parm !== 'string') parm = String(parm);
          var li = document.createElement('li');
          var rowEl = document.createElement('div');
          rowEl.className = 'reps-node';
          var twist = document.createElement('span');
          twist.className = 'reps-twist';
          twist.textContent = '+';
          var label = document.createElement('span');
          label.textContent = parm;
          rowEl.appendChild(twist);
          rowEl.appendChild(label);
          if (row.archive && !row.disk) {
            var atag = document.createElement('span');
            atag.className = 'reps-archive-tag';
            atag.textContent = 'archive only';
            atag.title = 'On-disk reports were removed; runs load from web.tsip_run_report_line';
            rowEl.appendChild(atag);
          }
          rowEl.addEventListener('click', function (ev) {
            ev.stopPropagation();
            selectNode(rowEl, {
              kind: 'p',
              parm: parm,
              archive: !!row.archive,
              disk: !!row.disk
            });
            expandParm(li, parm, twist);
          });
          li.appendChild(rowEl);
          tree.appendChild(li);
        });
      }).catch(function (ex) {
        status.textContent = 'Error: ' + (ex.message || ex);
      });
    }

    $('cmdRepsRefresh').onclick = loadRoot;
    $('cmdRepsOpen').onclick = displaySelected;
    $('cmdRepsDelete').onclick = deleteSelected;
    loadRoot();
  }

  global.RemicsTsip = {
    mountParm: mountParm,
    mountBatch: mountBatch,
    mountReps: mountReps,
    mountRun: mountRun,
    canLeave: canLeave
  };
})(window);
