// RemIcsReWrite IP-5 — SDF hierarchical tree (TwsSDFTree.asmx).
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
        items.push({ value: val, text: text || parts[2], sdf: parts[1], key: parts[2] });
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
    this.container.innerHTML = 'Loading…';
    return RemIcsApi.sdfTreeCall(this.cfg.tree, {}).then(function (r) {
      var body = (r.body || '').toString();
      if (!r.ok) {
        if (r.expired && RemIcsApi.redirectToLogin) RemIcsApi.redirectToLogin();
        self.container.textContent = (RemIcsApi.friendlyAsmxError && r.error)
          ? RemIcsApi.friendlyAsmxError(r.error) : (r.error || 'Load failed');
        return;
      }
      if (/^timeout/i.test(body) || (r && r.expired)) {
        self.container.textContent = RemIcsApi.loginExpiredMsg || 'Session expired — please log in again.';
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
    node.children = [{ text: 'Loading…', expandable: false }];
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
          text: RemIcsApi.loginExpiredMsg || 'Session expired — please log in again.',
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

  global.RemicsSdfTree = { TreeMount: TreeMount, SDF_CFG: SDF_CFG };
})(window);
