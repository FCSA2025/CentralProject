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
        open: function () { $('.ui-dialog-titlebar-close').hide(); }
      });
      $dlg.dialog('option', 'buttons', btnArray);
      $dlg.prev('.ui-dialog-titlebar').css({ background: '#0066FF', color: '#ffffff' });
      $dlg.load(lookupurl, function () { installTsipLookupBridge(); });
      $dlg.dialog('open');
      return false;
    };
  }

  window.installTsipLookupBridge = installTsipLookupBridge;
  installTsipLookupBridge();
})();
