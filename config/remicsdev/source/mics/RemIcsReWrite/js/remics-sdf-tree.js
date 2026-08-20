// RemIcsReWrite IP-5  -  SDF hierarchical tree (TwsSDFTree.asmx).
(function (global) {
  var SDF_CFG = {
    Ante: { tree: 'anteTree', detail: 'anteCode', deleteFn: 'delete_ante' },
    Band: { tree: 'bandTree', detail: 'bandCode', deleteFn: 'delete_band' },
    Ctx: { tree: 'ctxTree', detail: 'ctxCode', deleteFn: 'delete_ctx' },
    Eqpt: { tree: 'eqptTree', detail: 'eqptCode', deleteFn: 'delete_eqpt' },
    Oper: { tree: 'operTree', detail: 'operCode', deleteFn: 'delete_oper' },
    Plan: { tree: 'planTree', detail: 'planCode', deleteFn: 'delete_plan' },
    Rout: { tree: 'routTree', detail: 'routCode', deleteFn: 'delete_rout' },
    Note: { tree: 'noteTree', detail: 'noteCode', deleteFn: 'delete_note' },
    Towr: { tree: 'towrTree', detail: 'towrCode', deleteFn: 'delete_towr' },
    Town: { tree: 'townTree', detail: 'townCode', deleteFn: 'delete_town' },
    Traf: { tree: 'trafTree', detail: 'trafCode', deleteFn: 'delete_traf' }
  };

  function $(id) { return document.getElementById(id); }

  function parseDetailList(body) {
    var items = [];
    if (!body) return items;
    if (body.indexOf('ERRORSYS:') === 0 || /^timeout/i.test(body)) return items;
    if (body.indexOf('ERROR') === 0 && body.indexOf('ERRORS') !== 0) return items;
    body.split('@').forEach(function (chunk) {
      if (!chunk) return;
      var star = chunk.indexOf('*');
      var val = star >= 0 ? chunk.substring(0, star) : chunk;
      var text = star >= 0 ? chunk.substring(star + 1) : chunk;
      var parts = val.split('^');
      if (parts[0] === 'd' && parts.length >= 3) {
        items.push({ value: val, text: text || parts.slice(2).join(' '), sdf: parts[1], key: parts.slice(2).join('^') });
      }
    });
    return items;
  }

  function TreeMount(containerId, type, handlers) {
    this.container = $(containerId);
    this.type = type;
    this.cfg = SDF_CFG[type] || SDF_CFG.Ante;
    this.handlers = handlers || {};
  }

  TreeMount.prototype.renderNode = function (row, node, depth) {
    depth = depth || 0;
    var wrap = document.createElement('div');
    wrap.className = 'classic-tree-row';
    wrap.style.paddingLeft = (depth * 14) + 'px';
    var twisty = document.createElement('span');
    twisty.className = 'classic-tree-twisty';
    twisty.textContent = node.expandable ? (node.expanded ? '▼' : '▶') : '·';
    var label = document.createElement('span');
    label.className = 'classic-tree-label';
    label.textContent = node.text;
    wrap.appendChild(twisty);
    wrap.appendChild(label);
    row.appendChild(wrap);
    if (node.expanded && node.children) {
      var childBox = document.createElement('div');
      row.appendChild(childBox);
      node.children.forEach(function (ch) {
        var cr = document.createElement('div');
        childBox.appendChild(cr);
        this.renderNode(cr, ch, depth + 1);
      }, this);
    }
    var self = this;
    wrap.onclick = function (ev) {
      ev.stopPropagation();
      if (ev.detail > 1) return;
      self._selected = node;
      if (node.expandable) {
        if (node.expanded) {
          node.expanded = false;
          node.children = null;
          self.redraw();
        } else {
          self.expand(node);
        }
      }
      if (self.handlers.onSelect) self.handlers.onSelect(node);
    };
    wrap.ondblclick = function (ev) {
      ev.preventDefault();
      ev.stopPropagation();
      if (self.handlers.onActivate) self.handlers.onActivate(node);
    };
    if (this.handlers.onContext && node.value) {
      wrap.oncontextmenu = function (ev) {
        ev.preventDefault();
        self.handlers.onContext(ev, node);
      };
    }
  };

  TreeMount.prototype.redraw = function () {
    if (!this.container) return;
    this.container.innerHTML = '';
    (this.roots || []).forEach(function (n) {
      var row = document.createElement('div');
      this.container.appendChild(row);
      this.renderNode(row, n, 0);
    }, this);
  };

  TreeMount.prototype.loadRoot = function () {
    var self = this;
    if (!this.container) return Promise.resolve();
    this.container.innerHTML = 'Loading...';
    return RemIcsApi.sdfTreeCall(this.cfg.tree, {}).then(function (r) {
      var body = (r.body || '').toString();
      if (!r.ok) {
        if (r.expired && RemIcsApi.redirectToLogin) RemIcsApi.redirectToLogin();
        self.container.textContent = (RemIcsApi.friendlyAsmxError && r.error)
          ? RemIcsApi.friendlyAsmxError(r.error) : (r.error || 'Load failed');
        return;
      }
      if (/^timeout/i.test(body) || (r && r.expired)) {
        self.container.textContent = RemIcsApi.loginExpiredMsg || 'Session expired  -  please log in again.';
        if (RemIcsApi.redirectToLogin) RemIcsApi.redirectToLogin();
        return;
      }
      if (body.indexOf('ERRORSYS:') === 0 ||
          (body.indexOf('ERROR') === 0 && body.indexOf('ERRORS') !== 0)) {
        self.container.textContent = RemIcsApi.friendlyAsmxError
          ? RemIcsApi.friendlyAsmxError(body) : body;
        return;
      }
      self.roots = [
        { text: 'Help', value: 'HELP', expandable: false },
        { text: 'New ' + self.type + ' Data File', value: 'n.new', expandable: false },
      ];
      if (body !== 'NONE' && body) {
        body.split(':').filter(Boolean).sort().forEach(function (name) {
          self.roots.push({
            text: name,
            value: 'e^' + name,
            sdf: name,
            expandable: true,
            expanded: false
          });
        });
      }
      self.redraw();
    });
  };

  TreeMount.prototype.expand = function (node) {
    var self = this;
    var sdfName = node.sdf || (node.value || '').split('^')[1] || node.text;
    node.expanded = true;
    node.children = [{ text: 'Loading...', expandable: false }];
    self.redraw();
    var param = {};
    param[this.cfg.detail === 'anteCode' ? 'sdfName' : 'sdfName'] = sdfName;
    var args = { sdfName: sdfName };
    return RemIcsApi.sdfTreeCall(this.cfg.detail, args).then(function (r) {
      var body = (r.body || '').toString();
      if (!r.ok) {
        if (r.expired && RemIcsApi.redirectToLogin) RemIcsApi.redirectToLogin();
        node.children = [{
          text: (RemIcsApi.friendlyAsmxError && r.error)
            ? RemIcsApi.friendlyAsmxError(r.error) : (r.error || 'Load failed'),
          expandable: false
        }];
        self.redraw();
        return;
      }
      if (/^timeout/i.test(body) || (r && r.expired)) {
        if (RemIcsApi.redirectToLogin) RemIcsApi.redirectToLogin();
        node.children = [{
          text: RemIcsApi.loginExpiredMsg || 'Session expired  -  please log in again.',
          expandable: false
        }];
        self.redraw();
        return;
      }
      if (body.indexOf('ERRORSYS:') === 0 ||
          (body.indexOf('ERROR') === 0 && body.indexOf('ERRORS') !== 0)) {
        node.children = [{
          text: RemIcsApi.friendlyAsmxError ? RemIcsApi.friendlyAsmxError(body) : body,
          expandable: false
        }];
        self.redraw();
        return;
      }
      var items = parseDetailList(body);
      node.children = items.map(function (it) {
        return { text: it.text, value: it.value, sdf: it.sdf, key: it.key, expandable: false };
      });
      if (!node.children.length) node.children = [{ text: '(no records)', expandable: false }];
      self.redraw();
    });
  };

  TreeMount.prototype.selectedFileName = function () {
    if (this._selected && this._selected.sdf) return this._selected.sdf;
    if (this._selected && (this._selected.value || '').indexOf('e^') === 0) {
      return this._selected.sdf || this._selected.text || '';
    }
    return '';
  };

  TreeMount.prototype.findLoaded = function (query, afterNode, fileName) {
    var q = String(query || '').toLowerCase();
    if (!q) return null;
    var want = fileName ? String(fileName).toLowerCase() : '';
    var list = [];
    function walk(nodes) {
      (nodes || []).forEach(function (n) {
        list.push(n);
        if (n.children) walk(n.children);
      });
    }
    walk(this.roots);
    var start = 0;
    if (afterNode) {
      for (var i = 0; i < list.length; i++) {
        if (list[i] === afterNode) { start = i + 1; break; }
      }
    }
    for (var j = start; j < list.length; j++) {
      var n = list[j];
      var text = (n.text || '').toLowerCase();
      var val = (n.value || '').toLowerCase();
      var sdf = (n.sdf || '').toLowerCase();
      if (want && sdf && sdf !== want && val.indexOf('e^') !== 0) continue;
      if (want && val.indexOf('e^') === 0 && sdf !== want) continue;
      if (text.indexOf(q) >= 0 || val.indexOf(q) >= 0 || (n.key && String(n.key).toLowerCase().indexOf(q) >= 0)) {
        return n;
      }
    }
    return null;
  };

  TreeMount.prototype.highlight = function (node) {
    this._selected = node;
    this.redraw();
    if (this.handlers.onSelect) this.handlers.onSelect(node);
  };

  TreeMount.prototype.findQuery = function (query) {
    var self = this;
    var q = String(query || '').replace(/^\s+|\s+$/g, '');
    if (!q) return Promise.resolve(null);
    if (this._findQuery !== q) {
      this._findQuery = q;
      this._findLast = null;
      this._findExhaustedFile = '';
      this._findPreferFile = this.selectedFileName();
    }
    var prefer = this._findPreferFile;
    function accept(hit, note) {
      self._findLast = hit;
      self.highlight(hit);
      if (self.handlers.onStatus) self.handlers.onStatus(note || '');
      return hit;
    }
    function searchAll() {
      var hit = self.findLoaded(q, self._findLast);
      if (hit) return Promise.resolve(accept(hit, ''));
      var files = (self.roots || []).filter(function (n) { return n.expandable; });
      var i = 0;
      function next() {
        if (i >= files.length) return Promise.resolve(null);
        var file = files[i++];
        if (file.sdf && file.sdf === self._findExhaustedFile) return next();
        var p = file.expanded ? Promise.resolve() : self.expand(file);
        return p.then(function () {
          var found = self.findLoaded(q, self._findLast);
          return found ? accept(found, '') : next();
        });
      }
      return next().then(function (found) {
        if (found) return found;
        if (self.handlers.onStatus) self.handlers.onStatus('No match for "' + q + '"');
        return null;
      });
    }
    if (prefer && this._findExhaustedFile !== prefer) {
      var hit = this.findLoaded(q, this._findLast, prefer);
      if (hit) return Promise.resolve(accept(hit, 'Found in ' + prefer + ' (this file). Click Find for next.'));
      var fileNode = null;
      (this.roots || []).forEach(function (n) {
        if (n.sdf && n.sdf.toUpperCase() === prefer.toUpperCase()) fileNode = n;
      });
      var ready = (fileNode && !fileNode.expanded) ? this.expand(fileNode) : Promise.resolve();
      return ready.then(function () {
        var found = self.findLoaded(q, self._findLast, prefer);
        if (found) return accept(found, 'Found in ' + prefer + ' (this file). Click Find for next.');
        self._findExhaustedFile = prefer;
        if (!window.confirm('No more matches in ' + prefer + '. Search the rest of the tree?')) {
          if (self.handlers.onStatus) self.handlers.onStatus('No more matches in ' + prefer);
          return null;
        }
        return searchAll();
      });
    }
    return searchAll();
  };

  var origRender = TreeMount.prototype.renderNode;
  TreeMount.prototype.renderNode = function (row, node, depth) {
    origRender.call(this, row, node, depth);
    if (this._selected === node) {
      var wrap = row.querySelector('.classic-tree-row');
      if (wrap) wrap.style.background = '#cde';
    }
  };

  global.RemicsSdfTree = { TreeMount: TreeMount, SDF_CFG: SDF_CFG };
})(window);
