// RemIcsReWrite — same-origin fetch helpers for TwsTabUtil.asmx (no jQuery/Telerik).
var RemIcsApi = (function () {
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

  function callAsmx(method, params) {
    var body = JSON.stringify(params);
    return fetch(asmxUrl(method), {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json; charset=utf-8' },
      body: body
    }).then(function (resp) {
      return resp.text().then(function (text) {
        var parsed = null;
        var value = text;
        try {
          parsed = JSON.parse(text);
          if (parsed && typeof parsed.d !== 'undefined') value = parsed.d;
        } catch (e) { /* raw text */ }

        var ok = resp.ok;
        var err = null;
        if (resp.status === 401) {
          err = 'HTTP 401 — forms auth cookie missing or expired. Check Application → Cookies for .ADAuthCookie.';
        } else if (!resp.ok) {
          err = 'HTTP ' + resp.status;
        } else if (typeof value === 'string' && value.toLowerCase().indexOf('timeout') === 0) {
          ok = false;
          err = 'Session timeout';
        } else if (typeof value === 'string' && value.indexOf('ERROR') === 0 && value.indexOf('ERRORS') !== 0) {
          ok = false;
          err = value;
        } else if (typeof value === 'string' && value.indexOf('OK') === 0) {
          ok = true;
        }

        return {
          ok: ok,
          status: resp.status,
          body: typeof value === 'string' ? value : JSON.stringify(value),
          error: err,
          diag: cookieDiag()
        };
      });
    }).catch(function (ex) {
      return { ok: false, status: 0, body: '', error: ex.message || String(ex), diag: cookieDiag() };
    });
  }

  function parseJsonResponse(resp) {
    return resp.text().then(function (text) {
      var data;
      try { data = JSON.parse(text); } catch (e) { data = { ok: false, error: text }; }
      data.status = resp.status;
      data.ok = resp.ok && !!data.ok;
      data.diag = cookieDiag();
      return data;
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
        var value = text;
        try {
          var parsed = JSON.parse(text);
          if (parsed && typeof parsed.d !== 'undefined') value = parsed.d;
        } catch (e) { /* raw */ }
        var ok = resp.ok;
        var err = null;
        if (!resp.ok) err = 'HTTP ' + resp.status;
        else if (typeof value === 'string' && value.toLowerCase().indexOf('timeout') === 0) {
          ok = false;
          err = 'Session timeout';
        } else if (typeof value === 'string' && value.indexOf('ERROR') === 0) {
          ok = false;
          err = value;
        }
        if (!ok && err) {
          var ex = new Error(err);
          ex.body = value;
          throw ex;
        }
        return { ok: ok, status: resp.status, body: value, error: err, diag: cookieDiag() };
      });
    });
  }

  return {
    micsRoot: micsRoot,
    cookieDiag: cookieDiag,
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
            var data;
            try { data = JSON.parse(text); } catch (e) { data = { ok: false, error: text }; }
            data.status = resp.status;
            data.ok = resp.ok && !!data.ok;
            data.diag = cookieDiag();
            return data;
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
          var data;
          try { data = JSON.parse(text); } catch (e) { data = { ok: false, error: text }; }
          data.status = resp.status;
          data.ok = resp.ok && !!data.ok;
          data.diag = cookieDiag();
          return data;
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
            return {
              ok: resp.ok,
              status: resp.status,
              body: text,
              error: resp.ok ? null : ('HTTP ' + resp.status)
            };
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
            return data;
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
    sdfTreeCall: function (method, params) {
      return callAsmxPath('Tsdfmenu/TwsSDFTree.asmx', method, params || {});
    }
  };
})();
