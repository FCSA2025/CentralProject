// RemIcsReWrite — same-origin fetch helpers for TwsTabUtil.asmx (no jQuery/Telerik).
var RemIcsApi = (function () {
  var loginExpiredMsg = 'Session expired — please log in again.';
  var _loginRedirecting = false;

  function looksLikeLoginHtml(text) {
    return /^\s*<(!DOCTYPE|html)/i.test(text || '') ||
      /Tlogin\.aspx|relogin\.aspx|RemIcsReWrite\/login\.aspx/i.test(text || '');
  }

  function isSessionExpiredText(value) {
    if (value == null || value === '') return false;
    var s = String(value);
    if (looksLikeLoginHtml(s)) return true;
    if (/^timeout\b/i.test(s)) return true;
    if (/session\s+(not initialized|expired|timeout|timed\s*out)/i.test(s)) return true;
    if (/please log in again/i.test(s)) return true;
    if (/\b(unauthenticated|not authenticated)\b/i.test(s)) return true;
    if (/ERRORSYS:\s*timeout/i.test(s)) return true;
    return false;
  }

  function isOnLoginPage() {
    return /\/login\.aspx/i.test(window.location.pathname || '');
  }

  function loginUrl() {
    return micsRoot() + 'RemIcsReWrite/login.aspx?loggedout=1&reason=0';
  }

  function redirectToLogin() {
    if (_loginRedirecting || isOnLoginPage()) return;
    _loginRedirecting = true;
    var url = loginUrl();
    setTimeout(function () {
      try { window.location.replace(url); } catch (e) { window.location.href = url; }
    }, 10);
  }

  function isExpired(r) {
    if (_loginRedirecting) return true;
    if (r == null) return false;
    if (typeof r === 'string') return isSessionExpiredText(r);
    if (r.expired) return true;
    if (r.status === 401) return true;
    if (isSessionExpiredText(r.error) || isSessionExpiredText(r.message)) return true;
    var body = r.body;
    if (typeof body === 'string' && body.length < 80 && isSessionExpiredText(body)) return true;
    return false;
  }

  function applyExpired(result, status) {
    if (!result) return result;
    var st = status != null ? status : result.status;
    if (st === 401 || isExpired(result)) {
      result.ok = false;
      result.expired = true;
      result.error = loginExpiredMsg;
      redirectToLogin();
    }
    return result;
  }

  function friendlyAsmxError(value) {
    if (value == null || value === '') return 'Request failed.';
    var s = String(value);
    if (isSessionExpiredText(s)) return loginExpiredMsg;
    if (/^ERRORSYS:/i.test(s)) {
      return 'Server error: ' + s.replace(/^ERRORSYS:\s*/i, '');
    }
    if (/^ERROR/i.test(s) && s.indexOf('ERRORS') !== 0) {
      if (s.length > 160) return s.substring(0, 160) + '…';
      return s;
    }
    return s;
  }

  /** Prefer r.error, else r.body, with friendlyAsmxError applied. */
  function apiErr(r, fallback) {
    if (isExpired(r)) return loginExpiredMsg;
    if (!r) return fallback || 'Request failed.';
    var v = r.error;
    if (v == null || v === '') v = r.body;
    if (v == null || v === '') return fallback || 'Request failed.';
    return friendlyAsmxError(v);
  }

  function micsRoot() {
    var pathname = window.location.pathname || '';
    var idx = pathname.toLowerCase().indexOf('/mics/');
    if (idx >= 0) {
      return window.location.protocol + '//' + window.location.host + pathname.substring(0, idx + 6);
    }
    return window.location.origin + '/mics/';
  }

  function asmxUrl(method) {
    return micsRoot() + 'Tfileactions/TwsTabUtil.asmx/' + method;
  }

  function uploadUrl() {
    return micsRoot() + 'RemIcsReWrite/upload.ashx';
  }

  function cookieDiag() {
    var name = '.ADAuthCookie';
    var has = document.cookie.split(';').some(function (c) {
      return c.trim().indexOf(name + '=') === 0;
    });
    return { cookieName: name, documentCookieHasAuth: has, host: window.location.hostname };
  }

  function classifyAsmxValue(resp, value) {
    var ok = resp.ok;
    var err = null;
    if (looksLikeLoginHtml(typeof value === 'string' ? value : '')) {
      ok = false;
      err = loginExpiredMsg;
    } else if (resp.status === 401) {
      ok = false;
      err = loginExpiredMsg;
    } else if (!resp.ok) {
      err = 'HTTP ' + resp.status;
    } else if (typeof value === 'string' && value.toLowerCase().indexOf('timeout') === 0) {
      ok = false;
      err = loginExpiredMsg;
    } else if (typeof value === 'string' && value.indexOf('ERROR') === 0 && value.indexOf('ERRORS') !== 0) {
      ok = false;
      err = friendlyAsmxError(value);
    } else if (typeof value === 'string' && value.indexOf('ERRORSYS:') === 0) {
      ok = false;
      err = friendlyAsmxError(value);
    } else if (typeof value === 'string' && value.indexOf('OK') === 0) {
      ok = true;
    }
    return { ok: ok, error: err };
  }

  function callAsmx(method, params) {
    var body = JSON.stringify(params);
    return fetch(asmxUrl(method), {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json; charset=utf-8' },
      body: body
    }).then(function (resp) {
      return resp.text().then(function (text) {
        if (looksLikeLoginHtml(text)) {
          return applyExpired({
            ok: false,
            status: resp.status,
            body: null,
            error: loginExpiredMsg,
            diag: cookieDiag()
          }, 401);
        }
        var parsed = null;
        var value = text;
        try {
          parsed = JSON.parse(text);
          if (parsed && typeof parsed.d !== 'undefined') value = parsed.d;
        } catch (e) { /* raw text */ }

        var cls = classifyAsmxValue(resp, value);
        return applyExpired({
          ok: cls.ok,
          status: resp.status,
          body: typeof value === 'string' ? value : JSON.stringify(value),
          error: cls.error,
          diag: cookieDiag()
        }, resp.status);
      });
    }).catch(function (ex) {
      return { ok: false, status: 0, body: '', error: ex.message || String(ex), diag: cookieDiag() };
    });
  }

  function extractLeadingJson(text) {
    var t = (text || '').trim();
    if (!t || t.charAt(0) !== '{') return null;
    var depth = 0;
    var inStr = false;
    var esc = false;
    for (var i = 0; i < t.length; i++) {
      var c = t.charAt(i);
      if (inStr) {
        if (esc) esc = false;
        else if (c === '\\') esc = true;
        else if (c === '"') inStr = false;
        continue;
      }
      if (c === '"') { inStr = true; continue; }
      if (c === '{') depth++;
      else if (c === '}') {
        depth--;
        if (depth === 0) {
          try { return JSON.parse(t.substring(0, i + 1)); } catch (e) { return null; }
        }
      }
    }
    return null;
  }

  function parseJsonResponse(resp) {
    return resp.text().then(function (text) {
      if (looksLikeLoginHtml(text)) {
        return applyExpired({
          ok: false,
          status: resp.status,
          error: loginExpiredMsg,
          diag: cookieDiag()
        }, 401);
      }
      var data = extractLeadingJson(text);
      var trailingHtml = false;
      if (!data) {
        try { data = JSON.parse(text); } catch (e) {
          if (/Global Page Error/i.test(text)) {
            data = { ok: false, error: 'Unexpected server error after request completed.' };
          } else {
            data = { ok: false, error: friendlyAsmxError(text) };
          }
        }
      } else if (text.length > (JSON.stringify(data).length + 2)) {
        trailingHtml = /Global Page Error|<h2>/i.test(text);
      }
      data.status = resp.status;
      data.ok = resp.ok && !!data.ok;
      if (!data.ok && data.error) data.error = friendlyAsmxError(data.error);
      if (trailingHtml && data.ok) data.partialOk = true;
      data.diag = cookieDiag();
      return applyExpired(data, resp.status);
    });
  }

  function callAsmxPath(servicePath, method, params) {
    var url = micsRoot() + servicePath + '/' + method;
    return fetch(url, {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json; charset=utf-8' },
      body: JSON.stringify(params)
    }).then(function (resp) {
      return resp.text().then(function (text) {
        if (looksLikeLoginHtml(text)) {
          applyExpired({ ok: false, status: 401, body: null, error: loginExpiredMsg }, 401);
          return { ok: false, status: resp.status, body: null, error: loginExpiredMsg, expired: true, diag: cookieDiag() };
        }
        var value = text;
        try {
          var parsed = JSON.parse(text);
          if (parsed && typeof parsed.d !== 'undefined') value = parsed.d;
        } catch (e) { /* raw */ }
        var cls = classifyAsmxValue(resp, value);
        var out = applyExpired({
          ok: cls.ok,
          status: resp.status,
          body: value,
          error: cls.error,
          diag: cookieDiag()
        }, resp.status);
        if (!out.ok && out.error && !out.expired) {
          var ex = new Error(out.error);
          ex.body = value;
          throw ex;
        }
        return out;
      });
    });
  }

  return {
    micsRoot: micsRoot,
    cookieDiag: cookieDiag,
    looksLikeLoginHtml: looksLikeLoginHtml,
    friendlyAsmxError: friendlyAsmxError,
    loginExpiredMsg: loginExpiredMsg,
    isExpired: isExpired,
    redirectToLogin: redirectToLogin,
    apiErr: apiErr,
    sessionCheck: function () {
      return fetch(micsRoot() + 'RemIcsReWrite/session.ashx', {
        credentials: 'include',
        cache: 'no-store'
      }).then(parseJsonResponse);
    },
    sesTimeoutGet: function () {
      return fetch(micsRoot() + 'RemIcsReWrite/session.ashx?action=timeoutget', {
        credentials: 'include',
        cache: 'no-store'
      }).then(parseJsonResponse);
    },
    sesTimeoutSet: function (minutes) {
      var body = new URLSearchParams();
      body.set('action', 'timeoutset');
      body.set('minutes', String(minutes));
      return fetch(micsRoot() + 'RemIcsReWrite/session.ashx', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString()
      }).then(parseJsonResponse);
    },
    filesList: function (filetype) {
      return fetch(micsRoot() + 'RemIcsReWrite/files.ashx?filetype=' + encodeURIComponent(filetype || 'TS'), {
        credentials: 'include',
        cache: 'no-store'
      }).then(parseJsonResponse);
    },
    killTable: function (filename, projectCode, options) {
      options = options || {};
      return callAsmx('killTable', {
        filename: filename,
        filetype: options.filetype || 'TS',
        projectCode: projectCode
      });
    },
    createTable: function (filename, projectCode, options) {
      options = options || {};
      return callAsmx('createTable', {
        filename: filename,
        filetype: options.filetype || 'TS',
        projectCode: projectCode
      });
    },
    exportTable: function (filename, projectCode, options) {
      options = options || {};
      return callAsmx('exportTable', {
        filename: filename,
        filetype: options.filetype || 'TS',
        projectCode: projectCode
      });
    },
    importTable: function (filename, projectCode, options) {
      options = options || {};
      return callAsmx('importTable', {
        filename: filename,
        filetype: options.filetype || 'TS',
        projectCode: projectCode
      });
    },
    tableExists: function (filename) {
      return callAsmx('tableexists', { filename: filename });
    },
    copyTable: function (oldname, newname, projectCode, options) {
      options = options || {};
      return callAsmx('copyTable', {
        oldname: oldname,
        newname: newname,
        filetype: options.filetype || 'TS',
        projectCode: projectCode
      });
    },
    userUpdate: function (filename, options) {
      options = options || {};
      return callAsmx('userUpdate', {
        filename: filename,
        filetype: options.filetype || 'TS'
      });
    },
    exportForUpdate: function (filename, projectCode, options) {
      options = options || {};
      return callAsmx('exportForUpdate', {
        filename: filename,
        filetype: options.filetype || 'TS',
        UserFcsa: options.userFcsa || 'F',
        projectCode: projectCode
      });
    },
    dbUpdateGate: function (filename, options) {
      options = options || {};
      var ft = options.filetype || 'TS';
      var url = micsRoot() + 'RemIcsReWrite/dbupdate.ashx?name=' +
        encodeURIComponent(filename) + '&filetype=' + encodeURIComponent(ft);
      return fetch(url, { method: 'GET', credentials: 'include' })
        .then(function (resp) {
          return resp.text().then(function (text) {
            if (looksLikeLoginHtml(text)) {
              return applyExpired({ ok: false, status: resp.status, error: loginExpiredMsg, diag: cookieDiag() }, 401);
            }
            var data;
            try { data = JSON.parse(text); } catch (e) { data = { ok: false, error: friendlyAsmxError(text) }; }
            data.status = resp.status;
            data.ok = resp.ok && !!data.ok;
            if (!data.ok && !data.error) data.error = 'HTTP ' + resp.status;
            data.diag = cookieDiag();
            return applyExpired(data, resp.status);
          });
        });
    },
    dbUpdateNotify: function (filename, options) {
      options = options || {};
      var body = new URLSearchParams();
      body.set('name', filename);
      body.set('filetype', options.filetype || 'TS');
      body.set('userFcsa', options.userFcsa || 'F');
      return fetch(micsRoot() + 'RemIcsReWrite/dbupdate.ashx', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString()
      }).then(function (resp) {
        return resp.text().then(function (text) {
          if (looksLikeLoginHtml(text)) {
            return applyExpired({ ok: false, status: resp.status, error: loginExpiredMsg, diag: cookieDiag() }, 401);
          }
          var data;
          try { data = JSON.parse(text); } catch (e) { data = { ok: false, error: friendlyAsmxError(text) }; }
          data.status = resp.status;
          data.ok = resp.ok && !!data.ok;
          data.diag = cookieDiag();
          return applyExpired(data, resp.status);
        });
      });
    },
    valFile: function (filename, projectCode, options) {
      options = options || {};
      return callAsmx('valFile', {
        filename: filename,
        filetype: options.filetype || 'TS',
        projectCode: projectCode,
        hilorep: options.hilorep || '0',
        verbose: options.verbose || '0'
      });
    },
    fetchReport: function (reportUrl) {
      return fetch(reportUrl, { method: 'GET', credentials: 'include' })
        .then(function (resp) {
          return resp.text().then(function (text) {
            if (looksLikeLoginHtml(text)) {
              return applyExpired({ ok: false, status: resp.status, body: text, error: loginExpiredMsg }, 401);
            }
            return applyExpired({
              ok: resp.ok,
              status: resp.status,
              body: text,
              error: resp.ok ? null : ('HTTP ' + resp.status)
            }, resp.status);
          });
        })
        .catch(function (ex) {
          return { ok: false, status: 0, body: '', error: ex.message || String(ex) };
        });
    },
    uploadTxt: function (targetName, file) {
      var fd = new FormData();
      fd.append('name', targetName);
      fd.append('file', file);
      return fetch(uploadUrl(), { method: 'POST', credentials: 'include', body: fd })
        .then(function (resp) {
          return resp.text().then(function (text) {
            var data;
            var looksLikeLogin = /^\s*<(!DOCTYPE|html)/i.test(text) || /Tlogin\.aspx/i.test(text);
            try { data = JSON.parse(text); } catch (e) {
              data = {
                ok: false,
                error: looksLikeLogin
                  ? 'Upload bounced to login (session/auth lost for upload.ashx). Log off, sign in again via RemIcsReWrite/login.aspx, then retry.'
                  : text
              };
            }
            data.status = resp.status;
            if (!resp.ok && !data.error) data.error = 'HTTP ' + resp.status;
            if (looksLikeLogin) data.ok = false;
            else data.ok = resp.ok && !!data.ok;
            data.diag = cookieDiag();
            return applyExpired(data, resp.status);
          });
        });
    },
    pcnUrl: function () {
      return micsRoot() + 'RemIcsReWrite/pcn.ashx';
    },
    pcnGate: function (filename, options) {
      options = options || {};
      var ft = options.filetype || 'TS';
      var url = micsRoot() + 'RemIcsReWrite/pcn.ashx?action=gate&name=' +
        encodeURIComponent(filename) + '&filetype=' + encodeURIComponent(ft);
      return fetch(url, { credentials: 'include' }).then(parseJsonResponse);
    },
    pcnScan: function (filename, projectCode, options) {
      options = options || {};
      var body = new URLSearchParams();
      body.set('action', 'scan');
      body.set('name', filename);
      body.set('filetype', options.filetype || 'TS');
      body.set('cDist', String(options.cDist != null ? options.cDist : 200));
      body.set('projectCode', projectCode || '');
      return fetch(micsRoot() + 'RemIcsReWrite/pcn.ashx', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString()
      }).then(parseJsonResponse);
    },
    pcnOperators: function (filename, logserial, options) {
      options = options || {};
      var q = 'action=operators&name=' + encodeURIComponent(filename) +
        '&filetype=' + encodeURIComponent(options.filetype || 'TS') +
        '&logserial=' + encodeURIComponent(logserial) +
        '&includeOwn=' + (options.includeOwn === false ? '0' : '1');
      return fetch(micsRoot() + 'RemIcsReWrite/pcn.ashx?' + q, { credentials: 'include' })
        .then(parseJsonResponse);
    },
    pcnAttach: function (tmpdir, file) {
      var fd = new FormData();
      fd.append('action', 'attach');
      fd.append('tmpdir', tmpdir);
      fd.append('file', file);
      return fetch(micsRoot() + 'RemIcsReWrite/pcn.ashx', {
        method: 'POST',
        credentials: 'include',
        body: fd
      }).then(parseJsonResponse);
    },
    pcnDiscard: function (tmpdir) {
      var body = new URLSearchParams();
      body.set('action', 'discard');
      body.set('tmpdir', tmpdir || '');
      return fetch(micsRoot() + 'RemIcsReWrite/pcn.ashx', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString()
      }).then(parseJsonResponse);
    },
    pcnSend: function (filename, options) {
      options = options || {};
      var body = new URLSearchParams();
      body.set('action', 'send');
      body.set('name', filename);
      body.set('filetype', options.filetype || 'TS');
      body.set('tmpdir', options.tmpdir || '');
      body.set('notes', options.notes || '');
      body.set('cc', options.cc || '');
      body.set('senderEmail', options.senderEmail || '');
      body.set('toEmails', options.toEmails || '');
      body.set('attachKml', options.attachKml ? '1' : '0');
      return fetch(micsRoot() + 'RemIcsReWrite/pcn.ashx', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString()
      }).then(parseJsonResponse);
    },
    pdfEdit: function (action, fields) {
      fields = fields || {};
      var body = new URLSearchParams();
      body.set('action', action);
      Object.keys(fields).forEach(function (k) {
        if (fields[k] != null) body.set(k, fields[k]);
      });
      return fetch(micsRoot() + 'RemIcsReWrite/pdf-edit.ashx', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString()
      }).then(parseJsonResponse);
    },
    sdfEdit: function (action, fields) {
      fields = fields || {};
      var body = new URLSearchParams();
      body.set('action', action);
      Object.keys(fields).forEach(function (k) {
        if (fields[k] != null) body.set(k, fields[k]);
      });
      return fetch(micsRoot() + 'RemIcsReWrite/sdf-edit.ashx', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString()
      }).then(parseJsonResponse);
    },
    tsipValidate: function (type, pdfname) {
      return callAsmxPath('Ttsipmenu/TwsTsip.asmx', 'tsipValidate', {
        type: type,
        pdfname: pdfname
      });
    },
    tsipRun: function (action, fields) {
      fields = fields || {};
      var body = new URLSearchParams();
      body.set('action', action);
      Object.keys(fields).forEach(function (k) {
        if (fields[k] != null) body.set(k, fields[k]);
      });
      return fetch(micsRoot() + 'RemIcsReWrite/tsip-run.ashx', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString()
      }).then(parseJsonResponse);
    },
    dsSearch: function (action, fields) {
      fields = fields || {};
      var body = new URLSearchParams();
      body.set('action', action);
      Object.keys(fields).forEach(function (k) {
        if (fields[k] != null && fields[k] !== '') body.set(k, fields[k]);
      });
      return fetch(micsRoot() + 'RemIcsReWrite/ds-search.ashx', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString()
      }).then(parseJsonResponse);
    },
    dsAsmx: function (servicePath, method, params) {
      return callAsmxPath(servicePath, method, params || {});
    },
    casedet: function (action, fields) {
      fields = fields || {};
      var body = new URLSearchParams();
      body.set('action', action);
      Object.keys(fields).forEach(function (k) {
        if (fields[k] != null) body.set(k, fields[k]);
      });
      return fetch(micsRoot() + 'RemIcsReWrite/casedet.ashx', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString()
      }).then(parseJsonResponse);
    },
    pdfExtra: function (action, fields) {
      fields = fields || {};
      var body = new URLSearchParams();
      body.set('action', action);
      Object.keys(fields).forEach(function (k) {
        if (fields[k] != null) body.set(k, fields[k]);
      });
      return fetch(micsRoot() + 'RemIcsReWrite/pdf-extra.ashx', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString()
      }).then(parseJsonResponse);
    },
    sdfFiles: function (type) {
      return fetch(micsRoot() + 'RemIcsReWrite/sdf-files.ashx?type=' + encodeURIComponent(type || 'Ante'), {
        credentials: 'include'
      }).then(parseJsonResponse);
    },
    anteLookup: function (q, acode) {
      var body = new URLSearchParams();
      if (q) body.set('q', q);
      if (acode) body.set('acode', acode);
      return fetch(micsRoot() + 'RemIcsReWrite/ante-lookup.ashx', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString()
      }).then(parseJsonResponse);
    },
    dsSdf: function (action, fields) {
      fields = fields || {};
      var body = new URLSearchParams();
      body.set('action', action);
      Object.keys(fields).forEach(function (k) {
        if (fields[k] != null && fields[k] !== '') body.set(k, fields[k]);
      });
      return fetch(micsRoot() + 'RemIcsReWrite/ds-sdf.ashx', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString()
      }).then(parseJsonResponse);
    },
    changePassword: function (oldPassword, newPassword) {
      var body = new URLSearchParams();
      body.set('action', 'change');
      body.set('oldPassword', oldPassword || '');
      body.set('newPassword', newPassword || '');
      return fetch(micsRoot() + 'RemIcsReWrite/password.ashx', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString()
      }).then(parseJsonResponse);
    },
    treeExpand: function (filetype, nodeValue, nodeText) {
      var ft = (filetype || 'TS').toUpperCase();
      var path = ft === 'ES' ? 'Tesmenu/TwsESTree.asmx' : 'Ttsmenu/TwsTStree.asmx';
      var rootText = ft === 'ES' ? 'ES Data Tree' : 'TS Data Tree';
      return callAsmxPath(path, 'expandNode', {
        node: { Value: nodeValue || 'root', Text: nodeText || rootText },
        context: {}
      }).then(function (r) {
        var nodes = r.body;
        if (typeof nodes === 'string') {
          try { nodes = JSON.parse(nodes); } catch (e) { nodes = []; }
        }
        if (!Array.isArray(nodes)) nodes = nodes ? [nodes] : [];
        return { ok: r.ok, nodes: nodes, error: r.error };
      }).catch(function (ex) {
        return { ok: false, nodes: [], error: ex.message || String(ex) };
      });
    },
    verifyTsLinkSite: function (linkKey) {
      return callAsmxPath('Ttsmenu/TwsTStree.asmx', 'verifySite', { key: linkKey }).then(function (r) {
        return { ok: r.ok, body: r.body, error: r.error };
      }).catch(function (ex) {
        return { ok: false, body: '', error: ex.message || String(ex) };
      });
    },
    sdfTreeCall: function (method, params) {
      return callAsmxPath('Tsdfmenu/TwsSDFTree.asmx', method, params || {});
    },
    sessionGet: function (key) {
      try { return sessionStorage.getItem(key) || ''; } catch (e) { return ''; }
    },
    sessionSet: function (key, value) {
      try {
        if (value == null || value === '') sessionStorage.removeItem(key);
        else sessionStorage.setItem(key, String(value));
      } catch (e) { /* ignore */ }
    },
    sessionGetJson: function (key) {
      try {
        var raw = sessionStorage.getItem(key);
        return raw ? JSON.parse(raw) : null;
      } catch (e) { return null; }
    },
    sessionSetJson: function (key, obj) {
      try { sessionStorage.setItem(key, JSON.stringify(obj)); } catch (e) { /* ignore */ }
    },
    lastFileKey: function (filetype) {
      return 'remics-last-file-' + ((filetype || 'TS') === 'ES' ? 'ES' : 'TS');
    },
    rememberLastFile: function (filetype, name) {
      if (!name) return;
      RemIcsApi.sessionSet(RemIcsApi.lastFileKey(filetype), name);
    },
    lastFile: function (filetype) {
      return RemIcsApi.sessionGet(RemIcsApi.lastFileKey(filetype));
    },
    wireEnterAsTab: function (container) {
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
          if (elType === 'hidden' || elType === 'button' || elType === 'submit' || elType === 'file') continue;
          if (!el.offsetParent) continue;
          focusable.push(el);
        }
        var idx = focusable.indexOf(t);
        if (idx >= 0 && idx < focusable.length - 1) focusable[idx + 1].focus();
      });
    },
    firstFocus: function (container, preferredIds) {
      var ids = preferredIds || [];
      var i, el;
      for (i = 0; i < ids.length; i++) {
        el = document.getElementById(ids[i]);
        if (el && !el.readOnly && !el.disabled && el.type !== 'hidden' && el.offsetParent) {
          try { el.focus(); if (el.select) el.select(); } catch (e) { /* ignore */ }
          return;
        }
      }
      if (!container) return;
      var nodes = container.querySelectorAll('input, select, textarea');
      for (i = 0; i < nodes.length; i++) {
        el = nodes[i];
        var elType = (el.type || '').toLowerCase();
        if (el.disabled || el.readOnly || el.tabIndex === -1) continue;
        if (elType === 'hidden' || elType === 'button' || elType === 'submit' || elType === 'file') continue;
        if (!el.offsetParent) continue;
        try { el.focus(); if (el.select) el.select(); } catch (e) { /* ignore */ }
        return;
      }
    }
  };
})();
