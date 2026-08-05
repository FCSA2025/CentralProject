// RemIcsReWrite IP-1 — hierarchical TS/ES data tree (classic TwsTStree / TwsESTree expandNode).
(function (global) {
  function stripHtml(html) {
    var d = document.createElement('div');
    d.innerHTML = html || '';
    return (d.textContent || d.innerText || '').trim();
  }

  function pdfFromValue(value) {
    var parts = (value || '').split('.');
    return parts.length > 1 ? parts[1] : '';
  }

  function isExpandable(node) {
    if (!node || !node.Value || node.Value.indexOf('timeout') === 0) return false;
    var em = node.ExpandMode;
    if (em === 1 || em === 'WebService' || em === 'ServerSideCallBack') return true;
    var p = node.Value.charAt(0);
    return 'elisubcnh'.indexOf(p) >= 0;
  }

  function editablePrefixes(filetype) {
    return filetype === 'ES' ? 'tqdghad' : 'tgadc';
  }

  function menuItems(value, filetype) {
    var p = (value || '').charAt(0);
    var ft = filetype === 'ES' ? 'ES' : 'TS';
    if (p === 'z') {
      return [
        { action: 'create', label: 'Create new file' },
        { action: 'import', label: 'Import txt file' }
      ];
    }
    if (p === 'e') {
      var items = [
        { action: 'validate', label: 'Validate' },
        { action: 'export', label: 'Export' },
        { action: 'pcn', label: 'PCN Coordination' },
        { action: 'dbupdate', label: 'Database Update' },
        { action: 'delete', label: 'Delete' },
        { action: 'copy', label: 'Copy' }
      ];
      if (ft === 'TS') items.push({ action: 'kml', label: 'KML Export' });
      return items;
    }
    if (p === 't' || p === 'd') return [{ action: 'edit-node', label: 'Edit' }];
    if (ft === 'ES') {
      if (p === 'q' || p === 'g' || p === 'h') return [
        { action: 'edit-node', label: 'Edit' },
        { action: 'delete-node', label: 'Delete' }
      ];
      if (p === 's') return [
        { action: 'delete-node', label: 'Delete Site' },
        { action: 'new-ante', label: 'New Antenna' }
      ];
      if (p === 'n') return [
        { action: 'delete-node', label: 'Delete Antenna' },
        { action: 'new-chan', label: 'New Channel' }
      ];
      if (p === 'u') return [{ action: 'new-cloc', label: 'New Change of Location' }];
      if (p === 'c') return [{ action: 'new-chng', label: 'New Change of Call Sign' }];
      if (p === 'i') return [{ action: 'new-site', label: 'New Site' }];
      return [];
    }
    if (p === 'g' || p === 'a' || p === 'c') return [
      { action: 'edit-node', label: 'Edit' },
      { action: 'delete-node', label: 'Delete' }
    ];
    if (p === 'l') return [{ action: 'new-chng', label: 'New Change of Call Sign' }];
    if (p === 'i') return [{ action: 'new-site', label: 'New Site' }];
    if (p === 's') return [
      { action: 'new-link', label: 'New Link' },
      { action: 'delete-node', label: 'Delete' }
    ];
    if (p === 'k') return [{ action: 'delete-node', label: 'Delete' }];
    if (p === 'b') return [{ action: 'new-ante', label: 'New Antenna' }];
    if (p === 'h') return [{ action: 'new-chan', label: 'New Channel' }];
    if (p === 'u') return [{ action: 'new-cloc', label: 'New Change of Location' }];
    return [];
  }

  function RemicsDataTree(container, options) {
    this.container = container;
    this.filetype = options.filetype || 'TS';
    this.rootLabel = options.rootLabel || (this.filetype === 'ES' ? 'ES Data Tree' : 'TS Data Tree');
    this.onAction = options.onAction || function () {};
    this.onSelectFile = options.onSelectFile || function () {};
    this.onStatus = options.onStatus || function () {};
    this.ctxNode = null;
    this.ctxMenu = null;
    this._bindDocClick();
  }

  RemicsDataTree.prototype.load = function () {
    var self = this;
    this.container.innerHTML = '';
    this.onStatus('Loading ' + this.filetype + ' Data Tree…');
    var rootLi = this._makeNode({
      Value: 'root',
      Text: this.rootLabel,
      ExpandMode: 1
    }, 0, true);
    this.container.appendChild(rootLi);
    return this._toggleNode(rootLi).then(function () {
      self.onStatus('Right-click for actions · double-click records to edit · double-click file to validate');
    });
  };

  RemicsDataTree.prototype._bindDocClick = function () {
    if (global.__remicsTreeDocBound) return;
    global.__remicsTreeDocBound = true;
    document.addEventListener('click', function () {
      document.querySelectorAll('.classic-tree-context').forEach(function (m) {
        m.hidden = true;
      });
    });
  };

  RemicsDataTree.prototype._makeNode = function (data, depth, expanded) {
    var self = this;
    var li = document.createElement('li');
    li.className = 'classic-tree-node';
    li.setAttribute('data-value', data.Value || '');
    li.setAttribute('data-depth', String(depth));

    var row = document.createElement('div');
    row.className = 'classic-tree-row';

    var toggle = document.createElement('button');
    toggle.type = 'button';
    toggle.className = 'classic-tree-toggle';
    toggle.setAttribute('aria-label', 'Expand');
    if (isExpandable(data)) {
      toggle.textContent = expanded ? '−' : '+';
    } else {
      toggle.textContent = ' ';
      toggle.disabled = true;
      toggle.className += ' classic-tree-toggle-leaf';
    }

    var label = document.createElement('span');
    label.className = 'classic-tree-label';
    label.innerHTML = data.Text || '';
    label.title = stripHtml(data.Text);

    row.appendChild(toggle);
    row.appendChild(label);
    li.appendChild(row);

    var childUl = document.createElement('ul');
    childUl.className = 'classic-tree-children';
    childUl.hidden = !expanded;
    li.appendChild(childUl);

    toggle.addEventListener('click', function (ev) {
      ev.stopPropagation();
      if (toggle.disabled) return;
      if (childUl.hidden) self._toggleNode(li);
      else {
        childUl.hidden = true;
        toggle.textContent = '+';
      }
    });

    row.addEventListener('click', function (ev) {
      ev.stopPropagation();
      self.container.querySelectorAll('.classic-tree-row').forEach(function (r) {
        r.classList.remove('classic-tree-selected');
      });
      row.classList.add('classic-tree-selected');
      var val = li.getAttribute('data-value') || '';
      if (val.charAt(0) === 'e') {
        self.onSelectFile(pdfFromValue(val));
      }
      if (val.charAt(0) === 'H') {
        self.onAction('help', { value: val, filetype: self.filetype });
      }
    });

    row.addEventListener('dblclick', function (ev) {
      ev.preventDefault();
      ev.stopPropagation();
      var val = li.getAttribute('data-value') || '';
      var p = val.charAt(0);
      if (p === 'e') {
        self.onAction('validate', { fileName: pdfFromValue(val), value: val, filetype: self.filetype });
      } else if (editablePrefixes(self.filetype).indexOf(p) >= 0) {
        self.onAction('edit-node', {
          fileName: pdfFromValue(val),
          value: val,
          filetype: self.filetype,
          nodeType: p
        });
      }
    });

    row.addEventListener('contextmenu', function (ev) {
      ev.preventDefault();
      var val = li.getAttribute('data-value') || '';
      var items = menuItems(val, self.filetype);
      if (!items.length) return;
      var labelEl = row.querySelector('.classic-tree-label');
      var nodeText = labelEl ? stripHtml(labelEl.innerHTML) : val;
      self._openContext(ev.clientX, ev.clientY, val, items, nodeText);
    });

    return li;
  };

  RemicsDataTree.prototype._toggleNode = function (li) {
    var self = this;
    var childUl = li.querySelector(':scope > ul.classic-tree-children');
    var toggle = li.querySelector(':scope > .classic-tree-row > .classic-tree-toggle');
    var value = li.getAttribute('data-value') || 'root';
    var label = li.querySelector(':scope > .classic-tree-row > .classic-tree-label');
    var text = label ? stripHtml(label.innerHTML) : self.rootLabel;

    if (!childUl.hidden && childUl.children.length) {
      childUl.hidden = false;
      if (toggle) toggle.textContent = '−';
      return Promise.resolve();
    }

    childUl.innerHTML = '';
    return RemIcsApi.treeExpand(self.filetype, value, text).then(function (r) {
      if (!r.ok) {
        self.onStatus(r.error || 'Tree expand failed');
        return;
      }
      var nodes = r.nodes || [];
      if (nodes.length && nodes[0].Value === 'timeout') {
        self.onStatus('Session timeout — please log in again.');
        return;
      }
      nodes.forEach(function (n) {
        childUl.appendChild(self._makeNode(n, parseInt(li.getAttribute('data-depth') || '0', 10) + 1, false));
      });
      childUl.hidden = false;
      if (toggle) toggle.textContent = '−';
    }).catch(function (ex) {
      self.onStatus(ex.message || String(ex));
    });
  };

  RemicsDataTree.prototype._openContext = function (x, y, nodeValue, items, nodeText) {
    var self = this;
    if (!this.ctxMenu) {
      this.ctxMenu = document.createElement('div');
      this.ctxMenu.className = 'classic-context classic-tree-context';
      this.ctxMenu.hidden = true;
      document.body.appendChild(this.ctxMenu);
    }
    this.ctxNode = nodeValue;
    this.ctxMenu.innerHTML = '';
    items.forEach(function (it) {
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.textContent = it.label;
      btn.setAttribute('data-action', it.action);
      btn.addEventListener('click', function (ev) {
        ev.stopPropagation();
        self.ctxMenu.hidden = true;
        self.onAction(it.action, {
          fileName: pdfFromValue(nodeValue),
          value: nodeValue,
          filetype: self.filetype,
          nodeText: nodeText || nodeValue
        });
      });
      self.ctxMenu.appendChild(btn);
    });
    this.ctxMenu.hidden = false;
    this.ctxMenu.style.left = Math.min(x, window.innerWidth - 200) + 'px';
    this.ctxMenu.style.top = Math.min(y, window.innerHeight - 240) + 'px';
  };

  global.RemicsDataTree = RemicsDataTree;
})(window);
