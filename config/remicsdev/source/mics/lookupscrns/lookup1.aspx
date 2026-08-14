<%@ Page Language="C#" %>
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>MICS Lookup</title>
  <link rel="stylesheet" type="text/css" href="../styleSheets/main.css" />
  <link rel="stylesheet" href="//code.jquery.com/ui/1.12.1/themes/smoothness/jquery-ui.css" />
  <script type="text/javascript" src='<%= ResolveUrl("~/micsjquery.js") %>'></script>
  <script type="text/javascript" src="https://code.jquery.com/ui/1.12.1/jquery-ui.min.js"></script>
  <script type="text/javascript" src="lookup-js.ashx?f=lookupfcns"></script>
  <script type="text/javascript" src="lookup-js.ashx?f=lookuped"></script>
  <script type="text/javascript" src="lookup-js.ashx?f=lookuptsip"></script>
</head>
<body class="b" onload="startLookup()">
  <div id="aspxdialog" style="display:none"></div>
  <script type="text/javascript">
  function parseParams() {
    var out = {};
    (window.location.search.substring(1) || '').split('&').forEach(function (part) {
      if (!part) return;
      var kv = part.split('=');
      out[decodeURIComponent(kv[0] || '')] = decodeURIComponent((kv[1] || '').replace(/\+/g, ' '));
    });
    return out;
  }

  function openerWin() {
    var win = window.opener;
    return (win && !win.closed) ? win : null;
  }

  function resolveOpenerField(id) {
    var win = openerWin();
    if (!win || !id) return null;
    var doc = win.document;
    var el = doc.getElementById(id);
    if (!el && win.__remicsLookupFieldId) el = doc.getElementById(win.__remicsLookupFieldId);
    if (!el) el = doc.querySelector('[name="' + String(id).replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"]');
    return el;
  }

  function openerFieldValue(id) {
    var el = resolveOpenerField(id);
    return el ? (el.value || '') : '';
  }

  function postLookupMessage(field, val) {
    var win = openerWin();
    if (!win) return false;
    var origin = window.location.origin || (window.location.protocol + '//' + window.location.host);
    var msg = { type: 'remicsLookupResult', field: field, value: val };
    try { win.postMessage(msg, origin); return true; } catch (e) { return false; }
  }

  function notifyOpenerField(id, val) {
    var win = openerWin();
    if (!id) return false;

    if (win && typeof win.__remicsLookupReturn === 'function') {
      try {
        if (win.__remicsLookupReturn(id, val) === true) return true;
      } catch (e) { /* fall through */ }
    }

    if (win) {
      var el = resolveOpenerField(id);
      if (el) {
        el.value = val;
        try {
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
        } catch (e) { /* ignore */ }
        try { el.focus(); } catch (e) { /* ignore */ }
        return true;
      }
    }

    if (postLookupMessage(id, val)) return true;
    return false;
  }

  function setOpenerField(id, val) {
    return notifyOpenerField(id, val);
  }

  function stripLookupQuotes(s) {
    if (!s) return '';
    s = String(s);
    if (s.length >= 2 && s.charAt(0) === "'") return s.slice(1, -1);
    return s;
  }

  function remicsFillField(field, strCode) {
    if (strCode === 'Timeout') {
      window.location.href = '../relogin.aspx?reason=0&errcode=&source=lookupscreen';
      return;
    }
    if (!strCode || strCode === 'null') return;
    if (!setOpenerField(field, stripLookupQuotes(strCode))) {
      alert('Could not update field "' + field + '" on the calling screen.');
      return;
    }
    try { $('#aspxdialog').dialog('close'); } catch (e) { /* ignore */ }
    window.close();
  }

  function remicsFillField2(field1, field2, strCode) {
    if (strCode === 'Timeout') {
      window.location.href = '../relogin.aspx?reason=0&errcode=&source=lookupscreen';
      return;
    }
    if (!strCode || strCode === 'null') return;
    var parts = String(strCode).split('^');
    if (parts.length >= 2) {
      var ok2 = setOpenerField(field2, stripLookupQuotes(parts[0]));
      var ok1 = setOpenerField(field1, stripLookupQuotes(parts[1]));
      if (!ok2 || !ok1) {
        alert('Could not update linked lookup fields on the calling screen.');
        return;
      }
    }
    try { $('#aspxdialog').dialog('close'); } catch (e) { /* ignore */ }
    window.close();
  }

  function remicsLookupDialog1(lookupurl, field, dwidth, dheight, intitle) {
    var btnArray = [
      {
        text: 'Select',
        click: function () {
          var selcode = '';
          var comma = '';
          var frm = document.frmLookup;
          if (!frm || !frm.cboCode) {
            alert('Lookup list is not ready yet.');
            return;
          }
          for (var i = 0; i <= frm.cboCode.options.length - 1; i++) {
            if (frm.cboCode.options[i].selected) {
              selcode = selcode + comma + frm.cboCode.options[i].value;
              comma = ',';
            }
          }
          $(this).dialog('close');
          if (selcode === '') {
            window.noneselected();
          } else if (field === 'txtChanCode' && typeof appchan === 'function') {
            appchan(selcode);
          } else if (field === 'caseCodes' && typeof upCaseCodes === 'function') {
            upCaseCodes(selcode);
          } else {
            remicsFillField(field, selcode);
          }
        }
      },
      {
        text: 'Cancel',
        click: function () {
          $(this).dialog('close');
          window.callbackcancelled();
        }
      }
    ];

    var $asxpdialog = $('#aspxdialog').dialog({
      autoOpen: false,
      resizable: false,
      height: dheight,
      width: dwidth,
      modal: true,
      title: intitle,
      buttons: btnArray,
      closeOnEscape: false,
      open: function () { $('.ui-dialog-titlebar-close').hide(); }
    });

    $asxpdialog.dialog('option', 'buttons', btnArray);
    $asxpdialog.prev('.ui-dialog-titlebar').css({ background: '#0066FF', color: '#ffffff' });
    $asxpdialog.load(lookupurl, function () { installBridge(); });
    $asxpdialog.dialog('open');
    return false;
  }

  function remicsLookupDialog2(lookupurl, field1, field2, dwidth, dheight, intitle) {
    var btnArray = [
      {
        text: 'Select',
        click: function () {
          var selcode = '';
          var comma = '';
          var frm = document.frmLookup;
          if (!frm || !frm.cboCode) {
            alert('Lookup list is not ready yet.');
            return;
          }
          for (var i = 0; i <= frm.cboCode.options.length - 1; i++) {
            if (frm.cboCode.options[i].selected) {
              var v = frm.cboCode.options[i].value;
              if (typeof addQuotes === 'function' && typeof trim === 'function') {
                v = addQuotes(trim(v));
              }
              selcode = selcode + comma + v;
              comma = ',';
            }
          }

          if (lookupurl.indexOf('EqptTraf') > 0 && frm.cboCode.selectedIndex !== -1) {
            selcode = frm.cboCode[frm.cboCode.selectedIndex].text.substr(74);
            selcode = selcode.concat('^' + frm.cboCode[frm.cboCode.selectedIndex].value);
          } else if (lookupurl.indexOf('TrafEqpt') > 0 && frm.cboCode.selectedIndex !== -1) {
            var ecode = frm.cboCode[frm.cboCode.selectedIndex].text.substr(10, 9);
            var dotstart = ecode.indexOf('.');
            ecode = ecode.substr(0, dotstart);
            selcode = ecode + '^' + frm.cboCode[frm.cboCode.selectedIndex].value;
          } else if (lookupurl.indexOf('LocationCode') > 0 && frm.cboCode.selectedIndex !== -1) {
            var loccode = frm.cboCode[frm.cboCode.selectedIndex].text.substr(11);
            selcode = loccode.concat('^' + frm.cboCode[frm.cboCode.selectedIndex].value);
          } else if (lookupurl.indexOf('LocationName') > 0 && frm.cboCode.selectedIndex !== -1) {
            var locname = frm.cboCode[frm.cboCode.selectedIndex].value;
            selcode = locname.concat('^' + frm.cboCode[frm.cboCode.selectedIndex].text.substr(11));
          } else if (lookupurl.indexOf('TSCallName') > 0 && frm.cboCode.selectedIndex !== -1) {
            locname = frm.cboCode[frm.cboCode.selectedIndex].value;
            selcode = locname.concat('^' + frm.cboCode[frm.cboCode.selectedIndex].text.substr(11));
          } else if (lookupurl.indexOf('TSCall1') > 0 && frm.cboCode.selectedIndex !== -1) {
            var name1 = frm.cboCode[frm.cboCode.selectedIndex].text.substr(10);
            selcode = name1.concat('^' + frm.cboCode[frm.cboCode.selectedIndex].value);
          }

          $(this).dialog('close');
          if (selcode === '') {
            window.noneselected();
          } else if (typeof filleqpttraf === 'function') {
            remicsFillField2(field1, field2, selcode);
          } else {
            remicsFillField2(field1, field2, selcode);
          }
        }
      },
      {
        text: 'Cancel',
        click: function () {
          $(this).dialog('close');
          window.callbackcancelled();
        }
      }
    ];

    var $asxpdialog = $('#aspxdialog').dialog({
      autoOpen: false,
      resizable: false,
      height: dheight,
      width: dwidth,
      modal: true,
      title: intitle,
      buttons: btnArray,
      closeOnEscape: false,
      open: function () { $('.ui-dialog-titlebar-close').hide(); }
    });

    $asxpdialog.dialog('option', 'buttons', btnArray);
    $asxpdialog.prev('.ui-dialog-titlebar').css({ background: '#0066FF', color: '#ffffff' });
    $asxpdialog.load(lookupurl, function () { installBridge(); });
    $asxpdialog.dialog('open');
    return false;
  }

  function installBridge() {
    window.fillfield = remicsFillField;
    window.fillfield2 = remicsFillField2;
    fillfield = remicsFillField;
    fillfield2 = remicsFillField2;

    window.LookupDialog1 = remicsLookupDialog1;
    window.LookupDialog2 = remicsLookupDialog2;
    LookupDialog1 = remicsLookupDialog1;
    LookupDialog2 = remicsLookupDialog2;

    window.callbackcancelled = function () { window.close(); };
    window.noneselected = function () { alert('No Items selected'); };
    callbackcancelled = window.callbackcancelled;
    noneselected = window.noneselected;

    if (typeof TsipPdfList === 'function') {
      TsipPdfList = function (text1, field1, field2) {
        var text2 = openerFieldValue(field2);
        var text = text2 + '^' + text1;
        var lookupurl = '../lookuptsip/luTsipPdfList.aspx?type=ed&text=' + encodeURIComponent(text);
        LookupDialog1(lookupurl, field1, 30 * 16, 25 * 16, 'Select a list of PDFs');
      };
    }

    if (typeof TsipEnvFileName === 'function') {
      TsipEnvFileName = function (type, text1, field1) {
        var text = type + '^' + text1;
        var lookupurl = '../lookuptsip/luTsipEnvFileName.aspx?type=ed&text=' + encodeURIComponent(text);
        LookupDialog1(lookupurl, field1, 30 * 16, 25 * 16, 'Select an Environment File Name');
      };
    }
  }

  function resolveLookup(type) {
    if (typeof window[type] === 'function') return window[type];
    return null;
  }

  function startLookup() {
    installBridge();
    var params = parseParams();
    var fld = params.fld || '';
    var win = openerWin();
    if (win && fld) {
      try { win.__remicsLookupFieldId = fld; } catch (e) { /* ignore */ }
    }
    var type = params.type || '';
    var fld2 = params.fld2 || '';
    var mandatory = params.m === '1';
    var text = params.text || openerFieldValue(fld);
    var fn = resolveLookup(type);

    if (!type || !fld) {
      alert('Lookup not configured.');
      window.close();
      return;
    }
    if (mandatory && !text) {
      alert('Must have starting text to limit lookup');
      window.close();
      return;
    }
    if (!fn) {
      alert('Unknown lookup type: ' + type);
      window.close();
      return;
    }

    if (type === 'TsipPdfList') {
      if (!fld2) fld2 = 'tr-envtype';
      if (!openerFieldValue(fld2)) {
        alert('Must have value in Env File Type field for this lookup');
        window.close();
        return;
      }
      fn(text, fld, fld2);
      return;
    }

    if (type === 'TsipEnvFileName' || type === 'TsipEnvList') {
      if (!fld2) fld2 = 'tr-envtype';
      var envType = openerFieldValue(fld2);
      if (!envType) {
        alert('Must have value in Env File Type field for this lookup');
        window.close();
        return;
      }
      fn(envType, text, fld);
      return;
    }

    if (params.mode === 'two') {
      if (!fld2) {
        alert('Lookup requires a linked field.');
        window.close();
        return;
      }
      fn(text, fld, fld2, 'ed');
      return;
    }

    if (params.mode === '2' || (fld2 && type.indexOf('Tsip') !== 0)) {
      if (!fld2) {
        alert('Lookup requires a linked field.');
        window.close();
        return;
      }
      if (!openerFieldValue(fld2)) {
        alert('Must have a value in the linked field for this lookup.');
        window.close();
        return;
      }
      fn(text, fld, fld2, 'ed');
      return;
    }

    if (type.indexOf('Tsip') === 0) {
      fn(text, fld);
      return;
    }

    fn(text, fld, 'ed');
  }
  </script>
</body>
</html>
