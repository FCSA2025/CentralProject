// RemIcsReWrite - collapsible classic-style nav tree renderer.
(function (global) {
  var NAV_ALL = global.RemicsNavData || [];
  // Classic TnavigationLeft.aspx internal_users  -  FCSA staff / dev accounts only.
  var FCSA_INTERNAL_USERS = (
    'fwmda,fwoad,fwrse,frse1,hulme1,venn1,venn2,compa1,comph1,import1,import2'
  ).split(',');
  var NAV = NAV_ALL.slice();
  var currentUser = '';
  var expandedKey = 'remics-nav-expanded';
  var expanded = loadExpanded();
  var onSelectCb = null;
  var activeView = '';
  var activeQuery = '';
  var containerEl = null;

  function normalizeUser(user) {
    return String(user || '').trim().toLowerCase();
  }

  function isFcsaUser(user) {
    var u = normalizeUser(user);
    if (!u) return false;
    return FCSA_INTERNAL_USERS.indexOf(u) >= 0;
  }

  function applyNavFilter(user) {
    currentUser = normalizeUser(user);
    var showFcsaOnly = isFcsaUser(currentUser);
    NAV = NAV_ALL.filter(function (item) {
      return !item.fcsaOnly || showFcsaOnly;
    });
  }

  function loadExpanded() {
    try {
      var raw = sessionStorage.getItem(expandedKey);
      return raw ? JSON.parse(raw) : {};
    } catch (e) {
      return {};
    }
  }

  function saveExpanded() {
    try {
      sessionStorage.setItem(expandedKey, JSON.stringify(expanded));
    } catch (e) { /* ignore */ }
  }

  function buildTree(flat) {
    var root = { children: [] };
    var stack = [{ node: root, level: -1 }];
    flat.forEach(function (item, index) {
      var level = item.level || 0;
      while (stack.length > 1 && stack[stack.length - 1].level >= level) {
        stack.pop();
      }
      var node = { item: item, index: String(index), children: [] };
      stack[stack.length - 1].node.children.push(node);
      if (item.folder) {
        stack.push({ node: node, level: level });
      }
    });
    return root.children;
  }

  function isExpanded(index) {
    return expanded[index] === true;
  }

  function setExpanded(index, open) {
    if (open) expanded[index] = true;
    else delete expanded[index];
    saveExpanded();
  }

  function expandAncestors(flatIndex) {
    var level = NAV[flatIndex].level;
    for (var i = flatIndex - 1; i >= 0; i--) {
      if (NAV[i].folder && NAV[i].level < level) {
        expanded[String(i)] = true;
        level = NAV[i].level;
      }
    }
    saveExpanded();
  }

  function parseQuery(q) {
    var out = {};
    if (!q) return out;
    q.split('&').forEach(function (part) {
      var kv = part.split('=');
      if (kv[0]) out[kv[0]] = decodeURIComponent(kv[1] || '');
    });
    return out;
  }

  function itemMatches(item, view, query) {
    if (!item.view || item.view !== view) return false;
    var want = parseQuery(query || '');
    var have = parseQuery(item.query || '');
    var keys = Object.keys(have);
    if (!keys.length && !Object.keys(want).length) return true;
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i];
      if (have[k] !== want[k]) return false;
    }
    return true;
  }

  function renderNode(node) {
    var item = node.item;
    var idx = node.index;
    var li = document.createElement('li');
    li.className = 'nav-node nav-l' + (item.level || 0);
    if (item.folder) li.classList.add('nav-folder-node');

    var row = document.createElement('div');
    row.className = 'nav-row';

    if (item.folder && node.children.length) {
      var toggle = document.createElement('button');
      toggle.type = 'button';
      toggle.className = 'nav-toggle';
      toggle.setAttribute('aria-expanded', isExpanded(idx) ? 'true' : 'false');
      toggle.setAttribute('aria-label', (isExpanded(idx) ? 'Collapse ' : 'Expand ') + item.label);
      toggle.textContent = isExpanded(idx) ? '\u2212' : '+';
      toggle.addEventListener('click', function (ev) {
        ev.stopPropagation();
        setExpanded(idx, !isExpanded(idx));
        rerender();
      });
      row.appendChild(toggle);
    } else {
      var spacer = document.createElement('span');
      spacer.className = 'nav-toggle-spacer';
      spacer.setAttribute('aria-hidden', 'true');
      row.appendChild(spacer);
    }

    if (item.folder) {
      var folderLabel = document.createElement('span');
      folderLabel.className = 'nav-folder-label';
      folderLabel.textContent = item.label;
      row.appendChild(folderLabel);
    } else if (item.disabled) {
      var disabled = document.createElement('span');
      disabled.className = 'nav-leaf nav-disabled';
      disabled.title = item.note || 'Not migrated yet';
      disabled.textContent = item.label;
      row.appendChild(disabled);
    } else if (item.help) {
      var helpBtn = document.createElement('button');
      helpBtn.type = 'button';
      helpBtn.className = 'nav-leaf nav-link';
      helpBtn.textContent = item.label;
      helpBtn.addEventListener('click', function () {
        var root = (global.RemIcsApi && RemIcsApi.micsRoot) ? RemIcsApi.micsRoot() : '/mics/';
        window.open(root + item.help, 'WndHelp',
          'toolbar=no,menubar=yes,scrollbars=yes,location=yes,resizable=yes,status=yes');
      });
      row.appendChild(helpBtn);
    } else if (item.href) {
      var link = document.createElement('a');
      link.className = 'nav-leaf nav-link';
      link.href = item.href;
      link.textContent = item.label;
      row.appendChild(link);
    } else {
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'nav-leaf nav-link';
      if (itemMatches(item, activeView, activeQuery)) btn.classList.add('nav-selected');
      btn.textContent = item.label;
      btn.setAttribute('data-view', item.view);
      if (item.query) btn.setAttribute('data-query', item.query);
      btn.addEventListener('click', function () {
        if (onSelectCb) onSelectCb(item.view, item.query || '');
      });
      row.appendChild(btn);
    }

    li.appendChild(row);

    if (node.children.length && item.folder) {
      var childUl = document.createElement('ul');
      childUl.className = 'nav-children';
      if (!isExpanded(idx)) childUl.hidden = true;
      node.children.forEach(function (child) {
        childUl.appendChild(renderNode(child));
      });
      li.appendChild(childUl);
    }

    return li;
  }

  function renderTree(container, nodes) {
    var ul = document.createElement('ul');
    ul.className = 'nav-tree-root';
    nodes.forEach(function (node) {
      ul.appendChild(renderNode(node));
    });
    container.innerHTML = '';
    container.appendChild(ul);
  }

  function rerender() {
    if (!containerEl) return;
    renderTree(containerEl, buildTree(NAV));
  }

  function renderNav(container, onSelect) {
    containerEl = container;
    onSelectCb = onSelect;
    if (!currentUser) {
      var shell = global.REMICS_SHELL || {};
      var session = global.RemicsApp && RemicsApp.getSession ? RemicsApp.getSession() : null;
      applyNavFilter((session && session.user) || shell.user || '');
    }
    rerender();
  }

  function setUser(user) {
    applyNavFilter(user);
    rerender();
  }

  function highlightRoute(view, query) {
    activeView = view || '';
    activeQuery = query || '';
    for (var i = 0; i < NAV.length; i++) {
      if (itemMatches(NAV[i], activeView, activeQuery)) {
        expandAncestors(i);
        break;
      }
    }
    rerender();
  }

  function updateHeader() {
    var login = document.getElementById('nav-login-name');
    var db = document.getElementById('nav-db-name');
    var shell = global.REMICS_SHELL || {};
    var session = global.RemicsApp && RemicsApp.getSession ? RemicsApp.getSession() : null;
    if (login) {
      login.textContent = (session && session.user) || shell.user || '';
    }
    if (db) {
      db.textContent = (session && session.schema) || shell.schema || '';
    }
  }

  global.RemicsNav = {
    render: renderNav,
    highlightRoute: highlightRoute,
    updateHeader: updateHeader,
    setUser: setUser,
    isFcsaUser: isFcsaUser,
    tree: NAV,
    flatLabels: function () {
      return NAV.map(function (n) { return n.label; });
    }
  };
})(window);
