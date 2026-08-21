// Bridge for TSIP codes crit popups (luTsip*CodesCrit) → RemIcsReWrite shell fields.
(function () {
  function openerWin() {
    var w = window.opener;
    return (w && !w.closed) ? w : null;
  }

  function remicsUpCaseCodes(strCode) {
    var win = openerWin();
    if (!win) return;
    if (typeof win.__remicsUpCaseCodes === 'function') {
      if (win.__remicsUpCaseCodes(strCode) === true) return;
    }
    if (win.txtCode) {
      if (!win.txtCode.value) win.txtCode.value = strCode;
      else win.txtCode.value = win.txtCode.value + ',' + strCode;
    }
  }

  function remicsPlaceLookupOnScreen($dlg) {
    try {
      var $w = $dlg.dialog('widget');
      var dw = Math.ceil($w.outerWidth()) + 48;
      var dh = Math.ceil($w.outerHeight()) + 88;
      if (dw < 520) dw = 520;
      if (dh < 420) dh = 420;
      var aw = (typeof screen !== 'undefined' && (screen.availWidth || screen.width)) || 1024;
      var ah = (typeof screen !== 'undefined' && (screen.availHeight || screen.height)) || 768;
      if (dw > aw) dw = aw;
      if (dh > ah) dh = ah;
      var left = Math.max(0, Math.round(((aw - dw) / 2) * 0.82));
      var top = Math.max(0, Math.round(((ah - dh) / 2) * 0.82));
      if (typeof window.resizeTo === 'function') window.resizeTo(dw, dh);
      if (typeof window.moveTo === 'function') window.moveTo(left, top);
    } catch (e) { /* ignore */ }
  }

  function installTsipLookupBridge() {
    window.upCaseCodes = remicsUpCaseCodes;

    window.LookupDialog1 = function (lookupurl, field, dwidth, dheight, intitle) {
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
              if (typeof noneselected === 'function') noneselected();
            } else if (field === 'caseCodes') {
              remicsUpCaseCodes(selcode);
            } else if (field === 'txtChanCode' && typeof appchan === 'function') {
              appchan(selcode);
            } else if (typeof window.fillfield === 'function') {
              window.fillfield(field, selcode);
            }
          }
        },
        {
          text: 'Cancel',
          click: function () {
            $(this).dialog('close');
            if (typeof callbackcancelled === 'function') callbackcancelled();
          }
        }
      ];

      var $dlg = $('#aspxdialog').dialog({
        autoOpen: false,
        resizable: false,
        height: dheight,
        width: dwidth,
        modal: true,
        title: intitle,
        buttons: btnArray,
        closeOnEscape: false,
        position: { my: 'center', at: 'center', of: window },
        open: function () { $('.ui-dialog-titlebar-close').hide(); remicsPlaceLookupOnScreen($dlg); }
      });
      $dlg.dialog('option', 'buttons', btnArray);
      $dlg.prev('.ui-dialog-titlebar').css({ background: '#0066FF', color: '#ffffff' });
      $dlg.load(lookupurl, function () {
        installTsipLookupBridge();
        remicsPlaceLookupOnScreen($dlg);
      });
      $dlg.dialog('open');
      return false;
    };
  }

  window.installTsipLookupBridge = installTsipLookupBridge;
  installTsipLookupBridge();
})();
