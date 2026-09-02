// RemIcsReWrite IP-1  -  hierarchical TS/ES data tree (classic TwsTStree / TwsESTree expandNode).
(function (global) {
  function stripHtml(html) {
    var d = document.createElement('div');
    d.innerHTML = html || '';
    return (d.textContent || d.innerText || '').trim();
  }

  /** Direct-child helpers — avoid :scope (IE / older engines). U3-1 */
  function directChild(parent, tagName, className) {
    if (!parent || !parent.children) return null;
    var tag = tagName ? String(tagName).toUpperCase() : '';
    for (var i = 0; i < parent.children.length; i++) {
      var el = parent.children[i];
      if (tag && el.tagName !== tag) continue;
      if (className && (!el.classList || !el.classList.contains(className))) continue;
      return el;
    }
    return null;
  }

  function treeRow(li) {
    return directChild(li, 'DIV', 'classic-tree-row');
  }

  function treeChildUl(li) {
    return directChild(li, 'UL', 'classic-tree-children');
  }

  function treeToggle(li) {
    var row = treeRow(li);
    return row ? directChild(row, 'BUTTON', 'classic-tree-toggle') : null;
  }

  function treeLabel(li) {
    var row = treeRow(li);
    return row ? directChild(row, 'SPAN', 'classic-tree-label') : null;
  }

  function pdfFromValue(value) {
    var parts = (value || '').split('.');
    return parts.length > 1 ? parts[1] : '';
  }

  function folderPrefixes(filetype) {
    // Classic trees are different. Do not share one prefix list.
    // TS (TwsTStree): file → Sites → site → link → Antennas folder / Channels folder
    //   e file, l chg-call folder, i Sites, s site, k link, b Antennas, h Channels
    // ES (TwsESTree): file → Sites → site → antenna folder (channels are leaves under the antenna)
    //   e file, u chg-loc folder, c chg-call folder, i Sites, s site, n antenna folder
    return filetype === 'ES' ? 'eucisn' : 'eliskbh';
  }

  function normalizeNode(node) {
    if (!node) return { Value: '', Text: '', ExpandMode: 0 };
    return {
      Value: node.Value || node.value || '',
      Text: node.Text || node.text || '',
      ExpandMode: node.ExpandMode != null ? node.ExpandMode : node.expandMode
    };
  }

  function isExpandable(node, filetype) {
    node = normalizeNode(node);
    if (!node.Value || node.Value.indexOf('timeout') === 0) return false;
    var em = node.ExpandMode;
    var byMode = (em === 1 || em === 2 || em === 3 ||
        em === 'WebService' || em === 'ServerSideCallBack' || em === 'ServerSide');
    return byMode || folderPrefixes(filetype).indexOf(node.Value.charAt(0)) >= 0;
  }

  function editablePrefixes(filetype) {
    return filetype === 'ES' ? 'tqdghadm' : 'tgsadc';
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
        { action: 'edit-contents', label: 'Edit Contents' },
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
    if (p === 't') return [{ action: 'edit-node', label: 'Edit' }];
    if (p === 'd') return [
      { action: 'edit-node', label: 'Edit' },
      { action: 'dup-node', label: 'Duplicate' }
    ];
    if (ft === 'ES') {
      if (p === 'a' || p === 'm') return [
        { action: 'edit-node', label: 'Edit' },
        { action: 'dup-node', label: 'Duplicate' }
      ];
      if (p === 'q' || p === 'g') return [
        { action: 'edit-node', label: 'Edit' },
        { action: 'delete-node', label: 'Delete' }
      ];
      if (p === 'h') return [
        { action: 'edit-node', label: 'Edit' },
        { action: 'dup-node', label: 'Duplicate' },
        { action: 'delete-node', label: 'Delete' }
      ];
      if (p === 's') return [
        { action: 'edit-node', label: 'Edit' },
        { action: 'dup-node', label: 'Duplicate' },
        { action: 'delete-node', label: 'Delete Site' },
        { action: 'new-ante', label: 'New Antenna' }
      ];
      if (p === 'n') return [
        { action: 'edit-node', label: 'Edit' },
        { action: 'dup-node', label: 'Duplicate' },
        { action: 'delete-node', label: 'Delete Antenna' },
        { action: 'new-chan', label: 'New Channel' },
        { action: 'new-azim', label: 'New Azimuth' }
      ];
      if (p === 'u') return [{ action: 'new-cloc', label: 'New Change of Location' }];
      if (p === 'c') return [{ action: 'new-chng', label: 'New Change of Call Sign' }];
      if (p === 'i') return [{ action: 'new-site', label: 'New Site' }];
      return [];
    }
    if (p === 'g') return [
      { action: 'edit-node', label: 'Edit' },
      { action: 'delete-node', label: 'Delete' }
    ];
    if (p === 'a' || p === 'c') return [
      { action: 'edit-node', label: 'Edit' },
      { action: 'dup-node', label: 'Duplicate' },
      { action: 'delete-node', label: 'Delete' }
    ];
    if (p === 'l') return [{ action: 'new-chng', label: 'New Change of Call Sign' }];
    if (p === 'i') return [{ action: 'new-site', label: 'New Site' }];
    if (p === 's') return [
      { action: 'edit-node', label: 'Edit' },
      { action: 'dup-node', label: 'Duplicate' },
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
    this.onStatus('Loading ' + this.filetype + ' Data Tree...');
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
    data = normalizeNode(data);
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
    if (isExpandable(data, this.filetype)) {
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
        self.persistExpanded();
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

  function revealPath(filetype, targetValue) {
    var p = String(targetValue || '').split('.');
    var kind = p[0];
    var name = p[1];
    if (!name) return [];
    var path = ['root', 'e.' + name];
    if (kind === 'e') return path;
    if (kind === 't') {
      path.push('t.' + name);
      return path;
    }
    if (filetype === 'ES') {
      if (kind === 'u') { path.push('u.' + name); return path; }
      if (kind === 'c') { path.push('c.' + name); return path; }
      path.push('i.' + name);
      if (kind === 'i') return path;
      var loc = p[2];
      if (!loc) return path;
      path.push('s.' + name + '.' + loc);
      if (kind === 's') return path;
      if (kind === 'd') {
        path.push('d.' + name + '.' + loc);
        return path;
      }
      var esCall = p[3];
      if (!esCall) return path;
      path.push('n.' + name + '.' + loc + '.' + esCall);
      if (kind === 'n') return path;
      if (kind === 'a') path.push('a.' + name + '.' + loc + '.' + esCall);
      else if (kind === 'm') path.push('m.' + name + '.' + loc + '.' + esCall);
      else if (kind === 'h') {
        path.push('h.' + name + '.' + loc + '.' + esCall + (p[4] ? '.' + p[4] : ''));
      }
      return path;
    }
    if (kind === 'l') { path.push('l.' + name); return path; }
    path.push('i.' + name);
    if (kind === 'i') return path;
    var call1 = p[2];
    if (!call1) return path;
    path.push('s.' + name + '.' + call1);
    if (kind === 's') return path;
    if (kind === 'd') {
      path.push('d.' + name + '.' + call1);
      return path;
    }
    var call2 = p[3];
    var band = p[4];
    if (!call2 || !band) return path;
    path.push('k.' + name + '.' + call1 + '.' + call2 + '.' + band);
    if (kind === 'k') return path;
    if (kind === 'b' || kind === 'a') {
      path.push('b.' + name + '.' + call1 + '.' + call2 + '.' + band);
      if (kind === 'a' && p[5]) {
        path.push('a.' + name + '.' + call1 + '.' + call2 + '.' + band + '.' + p[5]);
      }
      return path;
    }
    if (kind === 'h' || kind === 'c') {
      path.push('h.' + name + '.' + call1 + '.' + call2 + '.' + band);
      if (kind === 'c' && p[5]) {
        path.push('c.' + name + '.' + call1 + '.' + call2 + '.' + band + '.' + p[5]);
      }
    }
    return path;
  }

  RemicsDataTree.prototype.findNodeLi = function (value) {
    if (!value || !this.container) return null;
    var want = String(value).toLowerCase();
    var nodes = this.container.querySelectorAll('li.classic-tree-node[data-value]');
    for (var i = 0; i < nodes.length; i++) {
      if (String(nodes[i].getAttribute('data-value') || '').toLowerCase() === want) {
        return nodes[i];
      }
    }
    return null;
  };

  RemicsDataTree.prototype.selectLi = function (li) {
    if (!li || !this.container) return;
    this.container.querySelectorAll('.classic-tree-row').forEach(function (r) {
      r.classList.remove('classic-tree-selected');
    });
    var row = treeRow(li);
    if (row) {
      row.classList.add('classic-tree-selected');
      if (row.scrollIntoView) {
        try { row.scrollIntoView({ block: 'center' }); }
        catch (e) { row.scrollIntoView(true); }
      }
    }
    var val = li.getAttribute('data-value') || '';
    var name = pdfFromValue(val);
    if (name) this.onSelectFile(name);
    this.persistExpanded();
  };

  RemicsDataTree.prototype._ensureExpanded = function (li) {
    if (!li) return Promise.resolve();
    var childUl = treeChildUl(li);
    var toggle = treeToggle(li);
    if (!childUl) return Promise.resolve();
    var val = li.getAttribute('data-value') || '';
    if (toggle && toggle.disabled) {
      if (folderPrefixes(this.filetype).indexOf(val.charAt(0)) < 0) return Promise.resolve();
      toggle.disabled = false;
      toggle.className = 'classic-tree-toggle';
      toggle.textContent = '+';
    }
    if (childUl.children.length) {
      childUl.hidden = false;
      if (toggle) toggle.textContent = '−';
      return Promise.resolve();
    }
    return this._toggleNode(li);
  };

  RemicsDataTree.prototype.getSelectedValue = function () {
    if (!this.container) return '';
    var row = this.container.querySelector('.classic-tree-row.classic-tree-selected');
    if (!row || !row.parentNode) return '';
    return row.parentNode.getAttribute('data-value') || '';
  };

  RemicsDataTree.prototype.getExpandedValues = function () {
    var out = [];
    if (!this.container) return out;
    var nodes = this.container.querySelectorAll('li.classic-tree-node');
    for (var i = 0; i < nodes.length; i++) {
      var li = nodes[i];
      var val = li.getAttribute('data-value') || '';
      if (!val || val === 'root') continue;
      var childUl = treeChildUl(li);
      var toggle = treeToggle(li);
      if (childUl && !childUl.hidden && toggle && toggle.textContent === '−') out.push(val);
    }
    return out;
  };

  RemicsDataTree.prototype.persistExpanded = function () {
    try {
      sessionStorage.setItem('remics-tree-expanded-' + this.filetype, JSON.stringify(this.getExpandedValues()));
      var sel = this.getSelectedValue();
      if (sel) sessionStorage.setItem('remics-tree-selected-' + this.filetype, sel);
    } catch (e) { /* ignore */ }
  };

  RemicsDataTree.prototype.savedExpanded = function () {
    try {
      var raw = sessionStorage.getItem('remics-tree-expanded-' + this.filetype);
      var arr = raw ? JSON.parse(raw) : [];
      return Array.isArray(arr) ? arr : [];
    } catch (e) {
      return [];
    }
  };

  RemicsDataTree.prototype.restoreExpanded = function (values) {
    var self = this;
    var list = (values && values.length) ? values.slice() : this.savedExpanded();
    // TS link (k) and Antennas/Channels (b/h) have the same number of dots.
    // Sort by classic path depth so parents expand before children.
    list.sort(function (a, b) {
      return revealPath(self.filetype, a).length - revealPath(self.filetype, b).length;
    });
    var i = 0;
    function step() {
      if (i >= list.length) return Promise.resolve();
      var val = list[i++];
      var li = self.findNodeLi(val);
      if (li) return self._ensureExpanded(li).then(step);
      return self.reveal(val).then(step);
    }
    return step();
  };

  RemicsDataTree.prototype.selectedFileName = function () {
    var val = this.getSelectedValue() || '';
    if (!val || val === 'root' || val.charAt(0) === 'z' || val === 'HELP') return '';
    return pdfFromValue(val);
  };

  RemicsDataTree.prototype.expandFileForFind = function (name) {
    var self = this;
    if (!name) return Promise.resolve();
    var fileLi = this.findNodeLi('e.' + name);
    if (!fileLi) return Promise.resolve();
    return this._ensureExpanded(fileLi).then(function () {
      var sitesLi = self.findNodeLi('i.' + name);
      if (!sitesLi) return;
      return self._ensureExpanded(sitesLi);
    });
  };

  RemicsDataTree.prototype.findLoaded = function (query, afterLi, fileName) {
    var q = String(query || '').toLowerCase();
    if (!q || !this.container) return null;
    var wantFile = fileName ? String(fileName).toLowerCase() : '';
    var nodes = this.container.querySelectorAll('li.classic-tree-node');
    var start = 0;
    if (afterLi) {
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i] === afterLi) { start = i + 1; break; }
      }
    }
    for (var j = start; j < nodes.length; j++) {
      var li = nodes[j];
      var label = treeLabel(li);
      var text = label ? stripHtml(label.innerHTML) : '';
      var val = li.getAttribute('data-value') || '';
      if (wantFile && pdfFromValue(val).toLowerCase() !== wantFile) continue;
      if ((text && text.toLowerCase().indexOf(q) >= 0) || val.toLowerCase().indexOf(q) >= 0) {
        return li;
      }
    }
    return null;
  };

  RemicsDataTree.prototype._acceptFind = function (hit, note) {
    this._findLastLi = hit;
    this.selectLi(hit);
    this.persistExpanded();
    this.onStatus(note || '');
    return hit;
  };

  RemicsDataTree.prototype.findAllFiles = function (q) {
    var self = this;
    var hit = this.findLoaded(q, this._findLastLi);
    if (hit) return Promise.resolve(this._acceptFind(hit, ''));
    var files = [];
    this.container.querySelectorAll('li.classic-tree-node[data-value^="e."]').forEach(function (li) {
      files.push(li);
    });
    var i = 0;
    this.onStatus('Searching tree...');
    function nextFile() {
      if (i >= files.length) return Promise.resolve(null);
      var fileLi = files[i++];
      var name = pdfFromValue(fileLi.getAttribute('data-value'));
      if (name && name === self._findExhaustedFile) return nextFile();
      return self.expandFileForFind(name).then(function () {
        var found = self.findLoaded(q, self._findLastLi);
        return found || nextFile();
      });
    }
    return nextFile().then(function (found) {
      if (found) return self._acceptFind(found, '');
      if (self._findLastLi) {
        var wrap = self.findLoaded(q, null);
        if (wrap && wrap !== self._findLastLi) return self._acceptFind(wrap, '');
      }
      self.onStatus('No match for "' + q + '"');
      return null;
    });
  };

  RemicsDataTree.prototype.findQuery = function (query) {
    var self = this;
    var q = String(query || '').replace(/^\s+|\s+$/g, '');
    // U3-3: empty Find was a silent no-op.
    if (!q) {
      this.onStatus('Type a search string, then Find (searches the selected file first)');
      return Promise.resolve(null);
    }
    if (this._findQuery !== q) {
      this._findQuery = q;
      this._findLastLi = null;
      this._findExhaustedFile = '';
      this._findPreferFile = this.selectedFileName();
    }
    var prefer = this._findPreferFile;
    if (!prefer && !this._findLastLi) {
      this.onStatus('No file selected — searching the whole tree…');
    }
    if (prefer && this._findExhaustedFile !== prefer) {
      var hit = this.findLoaded(q, this._findLastLi, prefer);
      if (hit) {
        return Promise.resolve(this._acceptFind(hit, 'Found in ' + prefer + ' (this file). Click Find for next.'));
      }
      this.onStatus('Searching ' + prefer + '...');
      return this.expandFileForFind(prefer).then(function () {
        var found = self.findLoaded(q, self._findLastLi, prefer);
        if (found) {
          return self._acceptFind(found, 'Found in ' + prefer + ' (this file). Click Find for next.');
        }
        self._findExhaustedFile = prefer;
        if (!window.confirm('No more matches in ' + prefer + '. Search the rest of the tree?')) {
          self.onStatus('No more matches in ' + prefer);
          return null;
        }
        return self.findAllFiles(q);
      });
    }
    return this.findAllFiles(q);
  };

  RemicsDataTree.prototype.reveal = function (targetValue) {
    var self = this;
    var path = revealPath(this.filetype, targetValue);
    var i = 0;
    function step() {
      if (i >= path.length) return Promise.resolve();
      var val = path[i++];
      var li = self.findNodeLi(val);
      if (!li) return Promise.resolve();
      if (i === path.length) {
        self.selectLi(li);
        return Promise.resolve();
      }
      return self._ensureExpanded(li).then(step);
    }
    return step();
  };

  RemicsDataTree.prototype.appendChildNode = function (parentValue, childData) {
    var parentLi = this.findNodeLi(parentValue);
    if (!parentLi) return false;
    var childUl = treeChildUl(parentLi);
    if (!childUl) return false;
    var depth = parseInt(parentLi.getAttribute('data-depth') || '0', 10) + 1;
    childUl.appendChild(this._makeNode(childData, depth, false));
    childUl.hidden = false;
    var toggle = treeToggle(parentLi);
    if (toggle && !toggle.disabled) toggle.textContent = '−';
    return true;
  };

  RemicsDataTree.prototype._toggleNode = function (li) {
    var self = this;
    var childUl = treeChildUl(li);
    var toggle = treeToggle(li);
    var value = li.getAttribute('data-value') || 'root';
    var label = treeLabel(li);
    var text = label ? stripHtml(label.innerHTML) : self.rootLabel;

    if (!childUl.hidden && childUl.children.length) {
      childUl.hidden = false;
      if (toggle) toggle.textContent = '−';
      return Promise.resolve();
    }

    childUl.innerHTML = '';
    return RemIcsApi.treeExpand(self.filetype, value, text).then(function (r) {
      var nodes = r.nodes || [];
      if (!r.ok) {
        self.onStatus(RemIcsApi.friendlyAsmxError
          ? RemIcsApi.friendlyAsmxError(r.error) : (r.error || 'Tree expand failed'));
        return;
      }
      if (nodes.length && nodes[0].Value === 'timeout') {
        self.onStatus(RemIcsApi.loginExpiredMsg || 'Session expired  -  please log in again.');
        if (RemIcsApi.redirectToLogin) RemIcsApi.redirectToLogin();
        return;
      }
      if (nodes.length && typeof nodes[0].Value === 'string' &&
          nodes[0].Value.indexOf('ERROR') === 0 && nodes[0].Value.indexOf('ERRORS') !== 0) {
        self.onStatus(RemIcsApi.friendlyAsmxError
          ? RemIcsApi.friendlyAsmxError(nodes[0].Value) : nodes[0].Value);
        return;
      }
      nodes.forEach(function (n) {
        childUl.appendChild(self._makeNode(n, parseInt(li.getAttribute('data-depth') || '0', 10) + 1, false));
      });
      childUl.hidden = false;
      if (toggle) toggle.textContent = '−';
      self.persistExpanded();
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
  RemicsDataTree.treeRow = treeRow;
  RemicsDataTree.treeChildUl = treeChildUl;
  RemicsDataTree.treeToggle = treeToggle;
  RemicsDataTree.treeLabel = treeLabel;
})(window);
