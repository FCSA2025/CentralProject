// RemIcsReWrite — TSIP ASMX helpers (same-origin, credentials included).
var RemicsTsipApi = (function () {
  function micsRoot() {
    if (window.RemIcsApi && RemIcsApi.micsRoot) return RemIcsApi.micsRoot();
    var pathname = window.location.pathname || '';
    var idx = pathname.toLowerCase().indexOf('/mics/');
    if (idx >= 0) {
      return window.location.protocol + '//' + window.location.host + pathname.substring(0, idx + 6);
    }
    return window.location.origin + '/mics/';
  }

  function looksLikeLoginHtml(text) {
    if (window.RemIcsApi && RemIcsApi.looksLikeLoginHtml) return RemIcsApi.looksLikeLoginHtml(text);
    return /^\s*<(!DOCTYPE|html)/i.test(text) || /Tlogin\.aspx/i.test(text);
  }

  var loginExpiredMsg = (window.RemIcsApi && RemIcsApi.loginExpiredMsg) ||
    'Session expired — log off and sign in again via RemIcsReWrite/login.aspx, then retry batch TSIP.';

  function parseAshxJson(resp, text) {
    if (looksLikeLoginHtml(text) || resp.status === 401) {
      if (window.RemIcsApi && RemIcsApi.redirectToLogin) RemIcsApi.redirectToLogin();
      return { ok: false, status: resp.status, error: loginExpiredMsg, expired: true };
    }
    var data;
    try { data = JSON.parse(text); } catch (e) { data = { ok: false, error: text }; }
    data.status = resp.status;
    data.ok = resp.ok && !!data.ok;
    if (window.RemIcsApi && RemIcsApi.isExpired && RemIcsApi.isExpired(data)) {
      if (RemIcsApi.redirectToLogin) RemIcsApi.redirectToLogin();
      data.ok = false;
      data.expired = true;
      data.error = loginExpiredMsg;
    }
    return data;
  }

  function callAsmx(servicePath, method, params) {
    if (window.RemIcsApi && RemIcsApi.dsAsmx && servicePath.indexOf('Ttsipmenu') === 0) {
      return RemIcsApi.dsAsmx(servicePath, method, params || {});
    }
    var url = micsRoot() + servicePath + '/' + method;
    return fetch(url, {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json; charset=utf-8' },
      body: JSON.stringify(params || {})
    }).then(function (resp) {
      return resp.text().then(function (text) {
        if (looksLikeLoginHtml(text) || resp.status === 401) {
          if (window.RemIcsApi && RemIcsApi.redirectToLogin) RemIcsApi.redirectToLogin();
          return { ok: false, status: resp.status, body: null, error: loginExpiredMsg, expired: true };
        }
        var value = text;
        try {
          var parsed = JSON.parse(text);
          if (parsed && typeof parsed.d !== 'undefined') value = parsed.d;
        } catch (e) { /* raw */ }
        var ok = resp.ok;
        var err = null;
        if (resp.status === 401) err = loginExpiredMsg;
        else if (!resp.ok) err = 'HTTP ' + resp.status;
        else if (typeof value === 'string' && value.toLowerCase().indexOf('timeout') === 0) {
          ok = false;
          err = loginExpiredMsg;
          if (window.RemIcsApi && RemIcsApi.redirectToLogin) RemIcsApi.redirectToLogin();
        } else if (typeof value === 'string' && value.indexOf('ERROR') === 0 && value.indexOf('ERRORS') !== 0) {
          ok = false;
          err = (window.RemIcsApi && RemIcsApi.friendlyAsmxError)
            ? RemIcsApi.friendlyAsmxError(value) : value;
        } else if (typeof value === 'string' && value.indexOf('ERRORSYS:') === 0) {
          ok = false;
          err = (window.RemIcsApi && RemIcsApi.friendlyAsmxError)
            ? RemIcsApi.friendlyAsmxError(value) : value;
        }
        return { ok: ok, status: resp.status, body: value, error: err };
      });
    });
  }

  return {
    micsRoot: micsRoot,
    tsipTree: function () {
      return callAsmx('Ttsipmenu/TwsTsipTree.asmx', 'tsipTree', {});
    },
    runList: function (parameter) {
      return callAsmx('Ttsipmenu/TwsTsipTree.asmx', 'runList', { parameter: parameter });
    },
    tsipValidateAll: function (tsipparmname) {
      return callAsmx('Ttsipmenu/TwsTsip.asmx', 'tsipValidateAll', { tsipparmname: tsipparmname });
    },
    tsipRun: function (parmfile) {
      return callAsmx('Ttsipmenu/TwsTsip.asmx', 'tsipRun', { parmfile: parmfile });
    },
    tsipDelete: function (jobno) {
      return callAsmx('Ttsipmenu/TwsTsip.asmx', 'tsipDelete', { jobno: String(jobno) });
    },
    /** Classic tsipRepsTree — parms that have tsip_*.ERR in userdirs. */
    populateRepTree: function () {
      return callAsmx('Ttsipmenu/TwsTsipTree.asmx', 'populateRepTree', {});
    },
    /** Classic — ERRORS + Run-N + file types under one parm. */
    populateRepParm: function (parmid) {
      return callAsmx('Ttsipmenu/TwsTsipTree.asmx', 'populateRepParm', { parmid: parmid });
    },
    /** Copies report to .txt for browser display; returns basename (no .txt). */
    copyToTxt: function (filename) {
      return callAsmx('Ttsipmenu/TwsTsipTree.asmx', 'CopyToTxt', { filename: filename });
    },
    deleteRepFile: function (fileName) {
      return callAsmx('Ttsipmenu/TwsTsipTree.asmx', 'DeleteFile', { FileName: fileName });
    },
    deleteRepAll: function (fileName) {
      return callAsmx('Ttsipmenu/TwsTsipTree.asmx', 'DeleteAll', { FileName: fileName });
    },
    status: function (opts) {
      opts = opts || {};
      var q = opts.scope ? ('?scope=' + encodeURIComponent(opts.scope)) : '';
      return fetch(micsRoot() + 'RemIcsReWrite/tsip-status.ashx' + q, {
        credentials: 'include',
        cache: 'no-store'
      })
        .then(function (resp) {
          return resp.text().then(function (text) { return parseAshxJson(resp, text); });
        });
    },
    /** Case-count glance per run (archive num_int_cases, else CASEDET/CASESUM). */
    repsMeta: function (opts) {
      opts = opts || {};
      var q = [];
      if (opts.parm) q.push('parm=' + encodeURIComponent(opts.parm));
      if (opts.job) q.push('job=' + encodeURIComponent(String(opts.job)));
      var url = micsRoot() + 'RemIcsReWrite/tsip-reps-meta.ashx' + (q.length ? '?' + q.join('&') : '');
      return fetch(url, { credentials: 'include' }).then(function (resp) {
        return resp.text().then(function (text) { return parseAshxJson(resp, text); });
      });
    },
    /** Disk + archive merged report tree (RemIcsReWrite). mode=root|parm */
    repsTree: function (opts) {
      opts = opts || {};
      var q = ['mode=' + encodeURIComponent(opts.mode || 'root')];
      if (opts.parm) q.push('parm=' + encodeURIComponent(opts.parm));
      return fetch(micsRoot() + 'RemIcsReWrite/tsip-reps-tree.ashx?' + q.join('&'), {
        credentials: 'include',
        cache: 'no-store'
      }).then(function (resp) {
        return resp.text().then(function (text) { return parseAshxJson(resp, text); });
      });
    },
    /** Open report — disk CopyToTxt or archive lines → userdir .txt */
    repsOpen: function (opts) {
      return fetch(micsRoot() + 'RemIcsReWrite/tsip-reps-open.ashx', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json; charset=utf-8' },
        body: JSON.stringify(opts || {})
      }).then(function (resp) {
        return resp.text().then(function (text) { return parseAshxJson(resp, text); });
      });
    },
    parseValidateFailures: function (body) {
      if (!body) return [];
      return String(body).split('^').filter(Boolean).map(function (row) {
        var p = row.split(',');
        return {
          runname: p[0] || '',
          pdfname: p[1] || '',
          code: p[2] || '',
          message: (p[2] === '1')
            ? 'has been deleted'
            : 'must be re-validated'
        };
      });
    },
    /** tsipValidateAll result — empty body means ready for batch TSIP. */
    parseParmValidateState: function (body) {
      var text = (body === null || typeof body === 'undefined') ? '' : String(body);
      var failures = RemicsTsipApi.parseValidateFailures(text);
      return {
        ok: text === '',
        failures: failures,
        issueCount: failures.length
      };
    }
  };
})();
