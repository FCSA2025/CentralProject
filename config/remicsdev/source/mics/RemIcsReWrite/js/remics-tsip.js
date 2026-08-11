// RemIcsReWrite Phase 3 — TSIP parm list + batch submit + queue poll.
(function (global) {
  var selectedParm = '';
  var pollTimer = null;
  var queuePollOpts = { scope: 'user', keepAlive: false, parm: '' };

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

  function goParm() {
    if (global.RemicsApp && RemicsApp.navigate) RemicsApp.navigate('tsip-parm');
    else location.hash = '#/tsip-parm';
  }

  function goBatch(parm) {
    var q = 'parm=' + encodeURIComponent(parm || '');
    if (global.RemicsApp && RemicsApp.navigate) RemicsApp.navigate('tsip-batch', q);
    else location.hash = '#/tsip-batch?' + q;
  }

  function stopPoll() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  function formatStatusCode(st) {
    st = (st || '').toUpperCase();
    if (st === 'W') return 'Waiting';
    if (st === 'X') return 'Running';
    if (st === 'D') return 'Deleted';
    if (st === 'F') return 'Finished';
    return st || '-';
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

  function mountParm() {
    var tree = $('tsip-parm-tree');
    var status = $('tsip-parm-status');
    if (!tree || !window.RemicsTsipApi) return;

    stopPoll();
    selectedParm = '';
    selectedRun = '';
    selectedEnv = '';
    status.textContent = 'Loading TSIP parameters…';
    tree.innerHTML = '';

    function setBtnEnabled(id, on) {
      var b = $(id);
      if (b) b.disabled = !on;
    }

    function updateSelectionUI() {
      var selBox = $('tsip-parm-selection');
      var kindEl = selBox && selBox.querySelector('.tsip-parm-selection-kind');
      var labelEl = selBox && selBox.querySelector('.tsip-parm-selection-label');
      var detailEl = selBox && selBox.querySelector('.tsip-parm-selection-detail');
      if (!selBox || !labelEl || !detailEl) return;

      if (!selectedParm) {
        selBox.classList.add('tsip-parm-selection-empty');
        if (kindEl) kindEl.textContent = 'Selection';
        labelEl.textContent = 'Nothing selected';
        detailEl.textContent = 'Click a parameter file, or expand one and click a run.';
      } else if (!selectedRun) {
        selBox.classList.remove('tsip-parm-selection-empty');
        if (kindEl) kindEl.textContent = 'Parameter file';
        labelEl.textContent = selectedParm;
        detailEl.textContent = 'Expand to view runs, run batch TSIP, or create a new run.';
      } else {
        selBox.classList.remove('tsip-parm-selection-empty');
        if (kindEl) kindEl.textContent = 'Run';
        labelEl.textContent = selectedRun;
        detailEl.textContent = 'In ' + selectedParm +
          (selectedEnv ? ' · environment ' + selectedEnv : '') +
          '. Edit, duplicate, delete, or double-click to open.';
      }

      setBtnEnabled('cmdTsipBatch', !!selectedParm);
      setBtnEnabled('cmdTsipNewRun', !!selectedParm);
      setBtnEnabled('cmdTsipEditRun', !!selectedParm && !!selectedRun);
      setBtnEnabled('cmdTsipDupRun', !!selectedParm && !!selectedRun);
      setBtnEnabled('cmdTsipDelRun', !!selectedParm && !!selectedRun);

      if (global.RemicsApp && RemicsApp.setActiveFile) {
        RemicsApp.setActiveFile('TSIPPARM', selectedParm || '');
      }
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

    function expandParm(parmLi, parm, twist) {
      var childUl = parmLi.querySelector(':scope > ul.reps-children');
      if (childUl && childUl.getAttribute('data-loaded') === '1') {
        childUl.hidden = !childUl.hidden;
        twist.textContent = childUl.hidden ? '+' : '−';
        return;
      }
      twist.textContent = '…';
      RemicsTsipApi.runList(parm).then(function (r) {
        if (!r.ok) {
          status.textContent = r.error || r.body || 'runList failed';
          twist.textContent = '+';
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
      });
    }

    function load() {
      status.textContent = 'Loading TSIP parameters…';
      tree.innerHTML = '';
      selectedParm = '';
      selectedRun = '';
      selectedEnv = '';
      updateSelectionUI();
      RemicsTsipApi.tsipTree().then(function (r) {
        if (!r.ok) {
          status.textContent = r.error || r.body || 'tsipTree failed';
          return;
        }
        var body = (r.body || '').toString();
        if (body.indexOf('timeout') === 0) {
          status.textContent = 'Session timeout — log in again.';
          return;
        }
        if (body.indexOf('ERROR') === 0) {
          status.textContent = body;
          return;
        }
        if (body === 'NONE') {
          status.textContent = 'No TSIP parameter files (tp_*_parm) in this schema. Create one to get started.';
          return;
        }
        var parms = body.split(':').filter(Boolean);
        status.textContent = parms.length + ' parameter file' + (parms.length === 1 ? '' : 's') + ' found';
        parms.forEach(function (name) {
          var li = document.createElement('li');
          var row = document.createElement('div');
          row.className = 'reps-node reps-parm';
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
            goBatch(name);
          });
          li.appendChild(row);
          tree.appendChild(li);
        });
      }).catch(function (ex) {
        status.textContent = 'Error: ' + (ex.message || ex);
      });
    }

    $('cmdTsipRefresh').onclick = load;
    $('cmdTsipBatch').onclick = function () {
      if (!selectedParm) return;
      goBatch(selectedParm);
    };
    if ($('cmdTsipCreateParm')) {
      $('cmdTsipCreateParm').onclick = function () {
        var name = window.prompt('New TSIP parameter file name (1–16 A-Za-z0-9_):', '');
        if (!name) return;
        name = name.trim();
        if (!/^[A-Za-z0-9_]{1,16}$/.test(name)) {
          alert('Invalid name.');
          return;
        }
        status.textContent = 'Creating ' + name + '…';
        RemIcsApi.createTable(name, projectCode(), { filetype: 'TsipParm' }).then(function (r) {
          if (!r.ok) {
            status.textContent = r.error || r.body || 'createTable failed';
            return;
          }
          status.textContent = 'Created ' + name;
          load();
        });
      };
    }
    if ($('cmdTsipNewRun')) {
      $('cmdTsipNewRun').onclick = function () {
        if (!selectedParm) return;
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
          if (!r.ok) { alert(r.error || 'Delete failed'); return; }
          selectedRun = '';
          selectedEnv = '';
          load();
        });
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

    Form.mount({ action: action });

    if ($('tsip-run-help')) {
      $('tsip-run-help').onclick = function () {
        micsHelp('micshelp/tsipRun.aspx');
      };
    }

    $('tsip-run-back').onclick = goParm;
    $('tsip-run-cancel').onclick = goParm;
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
      if (status) status.textContent = 'Saving…';
      RemIcsApi.tsipRun(act, payload).then(function (r) {
        if (!r.ok) {
          if (status) status.textContent = r.error || 'Save failed';
          alert(r.error || 'Save failed');
          return;
        }
        goParm();
      });
    };

    if (action === 'edit' || action === 'dup') {
      if (status) status.textContent = 'Loading run…';
      RemIcsApi.tsipRun('get', { parm: parm, runname: runname }).then(function (r) {
        if (!r.ok) {
          if (status) status.textContent = r.error || 'Load failed';
          return;
        }
        Form.fillRecord(r.record, action);
        if (action === 'dup' && $('tr-runname')) {
          $('tr-runname').value = '';
          $('tr-runname').focus();
        }
        if (status) status.textContent = '';
      });
    } else {
      Form.initNewDefaults();
    }
  }

  function renderQueue(data, metaByJob, showUser) {
    var tbody = $('tsip-queue-body');
    if (!tbody) return;
    tbody.innerHTML = '';
    if (!data || !data.ok) {
      var tr = document.createElement('tr');
      var td = document.createElement('td');
      td.colSpan = showUser ? 8 : 7;
      td.textContent = (data && data.error) || 'Unable to load queue.';
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }
    var jobs = data.jobs || [];
    if (!jobs.length) {
      var tr0 = document.createElement('tr');
      var td0 = document.createElement('td');
      td0.colSpan = showUser ? 8 : 7;
      td0.textContent = showUser ? '(no active jobs in queue)' : '(no jobs for this user)';
      tr0.appendChild(td0);
      tbody.appendChild(tr0);
      return;
    }
    metaByJob = metaByJob || {};
    jobs.forEach(function (j) {
      var g = metaByJob[String(j.job)];
      var tr = document.createElement('tr');
      if (j.active) tr.className = 'tsip-queue-active-row';
      var cols = [
        String(j.job),
        formatStatusCode(j.status),
        j.finish === null || typeof j.finish === 'undefined' ? '-' : String(j.finish),
        j.parm || '',
        j.active ? 'yes' : 'no',
        j.timeIn || '',
        (g && g.glance) ? g.glance : ''
      ];
      if (showUser) cols.splice(4, 0, j.micsid || '');
      cols.forEach(function (val) {
        var td = document.createElement('td');
        td.textContent = val;
        tr.appendChild(td);
      });
      tbody.appendChild(tr);
    });
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
        setQueueRefreshNote('Queue refresh failed — click Refresh Queue or wait for retry.');
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
        setQueueRefreshNote(
          'Auto-refresh every 5 seconds — last updated ' + new Date().toLocaleTimeString() +
          (activeCount ? (' — ' + activeCount + ' active job(s)') : '')
        );
        return data;
      }).catch(function () {
        renderQueue(data, null, showUser);
        setQueueRefreshNote('Auto-refresh every 5 seconds — last updated ' + new Date().toLocaleTimeString());
        return data;
      });
    });
  }

  function wireBatchButtons(monitorOnly) {
    var cancel = $('cmdTsipCancel');
    var ret = $('cmdTsipReturn');
    var closeBtn = $('cmdTsipClose');
    var poll = $('cmdTsipPoll');
    var help = $('cmdTsipHelp');
    if (cancel) cancel.onclick = function () { stopPoll(); goParm(); };
    if (ret) ret.onclick = function () { stopPoll(); goParm(); };
    if (closeBtn) closeBtn.onclick = function () { stopPoll(); goParm(); };
    if (poll) poll.onclick = function () { refreshQueue(); };
    if (help) {
      help.onclick = function () {
        micsHelp(monitorOnly ? 'micshelp/tsipMonitor.aspx' : 'micshelp/tsipBatch.aspx');
      };
    }
  }

  function mountBatch() {
    var route = parseRoute();
    var parm = (route.params.parm || '').trim();
    var monitorOnly = route.params.monitor === '1' || !parm;
    var nameEl = $('tsip-batch-name');
    var heading = $('tsip-batch-heading');
    if (nameEl) nameEl.textContent = parm || '';
    if (heading) {
      heading.textContent = monitorOnly ? 'FCSA MICS Monitor TSIP' : 'FCSA MICS Batch TSIP Parameter';
    }

    stopPoll();
    wireBatchButtons(monitorOnly);
    show($('tsip-b2'), true);

    if (monitorOnly) {
      show($('tsip-b0'), false);
      show($('tsip-b1'), false);
      if ($('tsip-batch-note')) show($('tsip-batch-note'), false);
      var msg = $('tsip-batch-msg');
      if (msg) msg.textContent = 'All active TSIP jobs (same view as classic Monitor TSIP).';
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
    runBtn.onclick = function () {
      var btn = runBtn;
      btn.disabled = true;
      show($('tsip-b0'), false);
      show($('tsip-b1'), true);
      var msg = $('tsip-batch-msg');

      RemicsTsipApi.tsipValidateAll(parm).then(function (v) {
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
          alert('Tsip submission cancelled');
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
            msg.innerHTML = '<b>Batch submission for parameter file ' + parm + ' completed</b><br>' +
              'Calculations run in the background. Watch the queue below ' +
              '(completion email is suppressed on CloudMics 2022).<br>' +
              '<a href="#/tsip-reps">Retrieve TSIP Batch Reports</a> when the job finishes.';
          }
          alert('Batch submission for parameter file ' + parm + ' completed');
        } else if (text.indexOf('OK:2') === 0) {
          if (msg) msg.textContent = 'Cancelled — already in queue (OK:2).';
          alert('Batch submission for parameter file ' + parm + ' cancelled. Already in queue');
        } else {
          if (msg) msg.textContent = 'FAILED: ' + (r.error || text);
          alert('Batch submission for parameter file ' + parm + ' FAILED!!\n ERROR: ' + (r.error || text));
        }
        startQueuePoll({ scope: 'user', keepAlive: true, parm: parm });
      }).catch(function (ex) {
        show($('tsip-b1'), false);
        show($('tsip-b0'), true);
        btn.disabled = false;
        alert('TSIP error: ' + (ex.message || ex));
      });
    };
  }

  function session() {
    if (global.RemicsApp && RemicsApp.getSession) return RemicsApp.getSession() || {};
    return global.REMICS_SHELL || {};
  }

  function reportTxtUrl(baseName) {
    var s = session();
    var schema = s.schema || (global.REMICS_SHELL && REMICS_SHELL.schema) || '';
    var user = s.user || (global.REMICS_SHELL && REMICS_SHELL.user) || '';
    var root = (window.RemIcsApi && RemIcsApi.micsRoot) ? RemIcsApi.micsRoot() : RemicsTsipApi.micsRoot();
    return root + 'userdirs/' + schema + '/' + user + '/' + baseName + '.txt';
  }

  function openCopiedReport(baseName) {
    var name = (baseName || '').toString();
    if (name.indexOf('ERROR') === 0) {
      alert(name);
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

  /** Parse populateRepParm: e^parm*ERRORS/ r^parm^run*Run-run/ f^parm^run^type*type/ */
  function parseRepParm(body, parm) {
    var errors = null;
    var runs = {};
    var runOrder = [];
    String(body || '').split('/').forEach(function (token) {
      if (!token) return;
      var star = token.indexOf('*');
      if (star < 0) return;
      var key = token.substring(0, star);
      var text = token.substring(star + 1);
      var parts = key.split('^');
      var kind = parts[0];
      if (kind === 'e') {
        errors = { key: key, text: text || 'ERRORS', parm: parts[1] || parm };
      } else if (kind === 'r') {
        var run = parts[2] || text;
        if (!runs[run]) {
          runs[run] = { key: key, run: run, text: text || ('Run-' + run), files: [] };
          runOrder.push(run);
        }
      } else if (kind === 'f') {
        var r = parts[2];
        var ft = parts[3] || text;
        if (!runs[r]) {
          runs[r] = { key: 'r^' + parm + '^' + r, run: r, text: 'Run-' + r, files: [] };
          runOrder.push(r);
        }
        runs[r].files.push({ key: key, text: text || ft, parm: parts[1] || parm, run: r, filetype: ft });
      }
    });
    return {
      errors: errors,
      runs: runOrder.map(function (r) { return runs[r]; })
    };
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
        ? (meta.parm + ' / ' + meta.run + ' — ' + meta.glance)
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
      if (selected.kind === 'e') {
        fileName = 'tsip_' + selected.parm + '.ERR';
      } else if (selected.kind === 'f') {
        fileName = 'tsip_' + selected.parm + '_' + selected.run + '.' + selected.filetype;
      } else {
        alert('Double-click or select a report type under a run (or ERRORS).');
        return;
      }
      status.textContent = 'Opening ' + fileName + '…';
      RemicsTsipApi.copyToTxt(fileName).then(function (r) {
        if (!r.ok) {
          status.textContent = r.error || r.body || 'CopyToTxt failed';
          alert(status.textContent);
          return;
        }
        status.textContent = 'Opened ' + fileName;
        openCopiedReport(r.body || fileName);
      }).catch(function (ex) {
        status.textContent = 'Error: ' + (ex.message || ex);
      });
    }

    function deleteSelected() {
      if (!selected) {
        alert('Select a parameter or report file to delete.');
        return;
      }
      if (selected.kind === 'p') {
        if (!confirm('Delete all output from parameter file ' + selected.parm + '?')) return;
        RemicsTsipApi.deleteRepAll('tsip_' + selected.parm).then(function (r) {
          if (!r.ok) alert(r.error || r.body || 'Delete failed');
          loadRoot();
        });
        return;
      }
      if (selected.kind === 'e') {
        var errName = 'tsip_' + selected.parm + '.ERR';
        if (!confirm('Delete ' + errName + '?')) return;
        RemicsTsipApi.deleteRepFile(errName).then(function (r) {
          if (!r.ok) alert(r.error || r.body || 'Delete failed');
          loadRoot();
        });
        return;
      }
      if (selected.kind === 'f') {
        var fn = 'tsip_' + selected.parm + '_' + selected.run + '.' + selected.filetype;
        if (!confirm('Delete ' + fn + '?')) return;
        RemicsTsipApi.deleteRepFile(fn).then(function (r) {
          if (!r.ok) alert(r.error || r.body || 'Delete failed');
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
      row.lastChild.textContent = file.text;
      row.title = 'tsip_' + file.parm + '_' + file.run + '.' + file.filetype;
      var meta = {
        kind: 'f',
        parm: file.parm,
        run: file.run,
        filetype: file.filetype
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
      twist.textContent = '…';
      Promise.all([
        RemicsTsipApi.populateRepParm(parm),
        RemicsTsipApi.repsMeta({ parm: parm }).catch(function () { return { ok: false, runs: [] }; })
      ]).then(function (results) {
        var r = results[0];
        var meta = results[1];
        if (!r.ok) {
          status.textContent = r.error || r.body || 'populateRepParm failed';
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

        var parsed = parseRepParm(r.body, parm);
        if (parsed.errors) {
          var eli = document.createElement('li');
          var erow = document.createElement('div');
          erow.className = 'reps-node reps-leaf';
          erow.innerHTML = '<span class="reps-twist">·</span><span></span>';
          erow.lastChild.textContent = parsed.errors.text;
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
        parsed.runs.forEach(function (run) {
          var rli = document.createElement('li');
          var rrow = document.createElement('div');
          rrow.className = 'reps-node';
          var rtwist = document.createElement('span');
          rtwist.className = 'reps-twist';
          rtwist.textContent = run.files.length ? '−' : '·';
          var rlabel = document.createElement('span');
          rlabel.textContent = run.text;
          rrow.appendChild(rtwist);
          rrow.appendChild(rlabel);
          var info = metaByRun[metaKey(parm, run.run)];
          if (info && info.glance) {
            var tag = document.createElement('span');
            tag.className = 'reps-glance-tag ' + (info.glanceKind || 'unknown');
            tag.textContent = '(' + info.glance + ')';
            rrow.appendChild(tag);
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
          if (run.files.length) {
            var ful = document.createElement('ul');
            ful.className = 'reps-children';
            run.files.forEach(function (f) { addFileNode(ful, f); });
            rli.appendChild(ful);
          }
          childUl.appendChild(rli);
        });
        if (!parsed.errors && !parsed.runs.length) {
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
      status.textContent = 'Loading TSIP Report Files…';
      tree.innerHTML = '';
      RemicsTsipApi.populateRepTree().then(function (r) {
        if (!r.ok) {
          status.textContent = r.error || r.body || 'populateRepTree failed';
          return;
        }
        var body = (r.body || '').toString();
        if (body === 'NONE' || !body) {
          status.textContent = 'No TSIP report sets (need tsip_<parm>.ERR in userdirs).';
          return;
        }
        var parms = body.split(':').filter(Boolean);
        status.textContent = parms.length + ' parameter report set(s) — click to expand';
        parms.forEach(function (parm) {
          var li = document.createElement('li');
          var row = document.createElement('div');
          row.className = 'reps-node';
          var twist = document.createElement('span');
          twist.className = 'reps-twist';
          twist.textContent = '+';
          var label = document.createElement('span');
          label.textContent = parm;
          row.appendChild(twist);
          row.appendChild(label);
          row.addEventListener('click', function (ev) {
            ev.stopPropagation();
            selectNode(row, { kind: 'p', parm: parm });
            expandParm(li, parm, twist);
          });
          li.appendChild(row);
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
    mountRun: mountRun
  };
})(window);
