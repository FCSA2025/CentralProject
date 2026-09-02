// TSIP run form  -  live field switching parity with classic tsipValidation.js + tsipParm*.aspx.
var RemicsTsipRunForm = (function () {
  var V = window.RemicsTsipValidation;

  function $(id) { return document.getElementById(id); }

  // Prevent alert+refocus loops (blur/focus handlers re-entering while an alert is up).
  var suppressBlurValidation = false;
  var inFieldAlert = false;

  function beginLeaveForm() {
    suppressBlurValidation = true;
  }

  function endLeaveForm() {
    suppressBlurValidation = false;
  }

  /** Alert + clear + refocus once; ignores re-entry while alert is showing or leaving the form. */
  function fieldReject(el, message) {
    if (!el || suppressBlurValidation || inFieldAlert) return;
    inFieldAlert = true;
    try {
      alert(message);
      el.value = '';
      try { el.focus(); } catch (e) { /* ignore */ }
    } finally {
      setTimeout(function () { inFieldAlert = false; }, 0);
    }
  }

  /** One alert (optionally focus elsewhere) without clearing; same re-entry guard. */
  function oneAlert(message, focusEl) {
    if (suppressBlurValidation || inFieldAlert) return;
    inFieldAlert = true;
    try {
      alert(message);
      if (focusEl) {
        try { focusEl.focus(); } catch (e) { /* ignore */ }
      }
    } finally {
      setTimeout(function () { inFieldAlert = false; }, 0);
    }
  }

  function setDisabled(el, on) {
    if (!el) return;
    // Classic naming: second arg true means enable (disabled = false).
    el.disabled = !on;
  }

  function setReadOnly(el, on) {
    if (!el) return;
    el.readOnly = !!on;
  }

  function lookupBtn(fieldId) {
    return document.querySelector('[data-field="' + fieldId + '"]');
  }

  function fieldMap() {
    return {
      runname: $('tr-runname') ? $('tr-runname').value : '',
      protype: $('tr-protype') ? $('tr-protype').value : '',
      envtype: $('tr-envtype') ? $('tr-envtype').value : '',
      proname: $('tr-proname') ? $('tr-proname').value : '',
      envname: $('tr-envname') ? $('tr-envname').value : '',
      tsorbout: $('tr-tsorbout') ? $('tr-tsorbout').value : '',
      spherecalc: $('tr-spherecalc') ? $('tr-spherecalc').value : '',
      fsep: $('tr-fsep') ? $('tr-fsep').value : '',
      coordist: $('tr-coordist') ? $('tr-coordist').value : '',
      analopt: $('tr-analopt') ? $('tr-analopt').value : '',
      margin: $('tr-margin') ? $('tr-margin').value : '',
      chancodes: $('tr-chancodes') ? $('tr-chancodes').value : '',
      numchan: $('tr-numchan') ? $('tr-numchan').value : '',
      country: $('tr-country') ? $('tr-country').value : '',
      selsites: $('tr-selsites') ? $('tr-selsites').value : '',
      numcodes: $('tr-numcodes') ? $('tr-numcodes').value : '',
      codes: $('tr-codes') ? $('tr-codes').value : '',
      reports: $('tr-reports') ? $('tr-reports').value : '',
      arc: $('tr-arc') ? $('tr-arc').value : '',
      cullmarg: $('tr-cullmarg') ? $('tr-cullmarg').value : '',
      hilosecs: $('tr-hilosecs') ? $('tr-hilosecs').value : ''
    };
  }

  function reportFlags() {
    return {
      exec: $('tr-rpt-exec') ? $('tr-rpt-exec').checked : false,
      study: $('tr-rpt-study') ? $('tr-rpt-study').checked : false,
      stat: $('tr-rpt-stat') ? $('tr-rpt-stat').checked : false,
      detail: $('tr-rpt-detail') ? $('tr-rpt-detail').checked : false,
      summary: $('tr-rpt-summary') ? $('tr-rpt-summary').checked : false,
      aggint: $('tr-rpt-aggint') ? $('tr-rpt-aggint').checked : false,
      aggcsv: $('tr-rpt-aggcsv') ? $('tr-rpt-aggcsv').checked : false,
      ohloss: $('tr-rpt-ohloss') ? $('tr-rpt-ohloss').checked : false,
      hilo: $('tr-rpt-hilo') ? $('tr-rpt-hilo').checked : false
    };
  }

  function applyReportFlags(flags) {
    flags = flags || {};
    var ids = ['exec', 'study', 'stat', 'detail', 'summary', 'aggint', 'aggcsv', 'ohloss', 'hilo'];
    ids.forEach(function (k) {
      var el = $('tr-rpt-' + k);
      if (el) el.checked = !!flags[k];
    });
    hiloCheck();
  }

  function syncProtypeRadios() {
    var v = (V.trim($('tr-protype').value) || 'T').toUpperCase();
    if (v !== 'T' && v !== 'E') v = 'T';
    $('tr-protype').value = v;
    document.querySelectorAll('input[name=tr-protype-r]').forEach(function (r) {
      r.checked = r.value === v;
    });
  }

  function setRepFlags() {
    var filetype = V.trim($('tr-protype').value).toUpperCase();
    var envfiletype = V.trim($('tr-envtype').value).toUpperCase();
    var loss = V.trim($('tr-spherecalc').value);
    var option = V.trim($('tr-analopt').value).toUpperCase();

    var summary = $('tr-rpt-summary');
    var aggint = $('tr-rpt-aggint');
    var aggcsv = $('tr-rpt-aggcsv');
    var ohloss = $('tr-rpt-ohloss');
    var hilo = $('tr-rpt-hilo');
    var cullmarg = $('tr-cullmarg');
    var hilosecs = $('tr-hilosecs');

    if (filetype === 'T') {
      if (envfiletype === 'PDF_ES' || envfiletype === 'MDB_ES') {
        if (summary) { summary.checked = false; summary.disabled = true; }
        if (aggint) { aggint.checked = false; aggint.disabled = true; }
        if (aggcsv) { aggcsv.checked = false; aggcsv.disabled = true; }
        if (cullmarg) { cullmarg.value = ''; cullmarg.disabled = true; }
        if (ohloss) { ohloss.checked = false; ohloss.disabled = true; }
        if (hilo) { hilo.checked = false; hilo.disabled = true; }
        if (hilosecs) { hilosecs.value = ''; hilosecs.disabled = true; }
      } else {
        if ((envfiletype === 'PDF_TS' || envfiletype === 'MDB_TS') && loss === '5') {
          if (ohloss) ohloss.disabled = false;
        } else if (ohloss) {
          ohloss.checked = false;
          ohloss.disabled = true;
        }
        if (summary) summary.disabled = false;
        if (option === 'BAND') {
          if (aggint) { aggint.checked = false; aggint.disabled = true; }
          if (aggcsv) { aggcsv.checked = false; aggcsv.disabled = true; }
        } else {
          if (aggint) aggint.disabled = false;
          if (aggcsv) aggcsv.disabled = false;
        }
        if (hilo) hilo.disabled = false;
        if (hilosecs) hilosecs.disabled = !hilo || !hilo.checked;
        if (cullmarg) cullmarg.disabled = false;
      }
    } else {
      if (summary) { summary.checked = false; summary.disabled = true; }
      if (aggint) { aggint.checked = false; aggint.disabled = true; }
      if (aggcsv) { aggcsv.checked = false; aggcsv.disabled = true; }
      if (ohloss) { ohloss.checked = false; ohloss.disabled = true; }
      if (hilo) { hilo.checked = false; hilo.disabled = true; }
      if (hilosecs) { hilosecs.value = ''; hilosecs.disabled = true; }
      if (cullmarg) { cullmarg.value = ''; cullmarg.disabled = true; }
    }
  }

  function setLabelRequired(id, required) {
    var el = $(id);
    if (!el) return;
    el.className = required ? 'm' : 'o';
  }

  /** Green (.m) only when Save will require the field for the current File/Env type. */
  function syncRequiredLabels() {
    var pdfType = V.trim($('tr-protype') ? $('tr-protype').value : '').toUpperCase();
    var env = V.trim($('tr-envtype') ? $('tr-envtype').value : '').toUpperCase();
    var sites = V.trim($('tr-selsites') ? $('tr-selsites').value : '').toUpperCase();
    var option = V.trim($('tr-analopt') ? $('tr-analopt').value : '').toUpperCase();

    setLabelRequired('tr-lbl-margin', true);
    setLabelRequired('tr-lbl-coordist', pdfType === 'T');
    setLabelRequired('tr-lbl-envname', env === 'PDF_TS' || env === 'PDF_ES');
    setLabelRequired('tr-lbl-country', env !== 'INTRA');
    setLabelRequired('tr-lbl-selsites', env !== 'INTRA');
    setLabelRequired('tr-lbl-codes', sites === 'CALL SIGN' || sites === 'OPERATOR CODE');
    setLabelRequired('tr-lbl-chancodes', option === 'CHAN');
  }

  function chkEnvFile() {
    var envEl = $('tr-envtype');
    if (!envEl) return;
    envEl.value = V.trim(envEl.value).toUpperCase();
    var env = envEl.value;
    var country = $('tr-country');
    var envname = $('tr-envname');
    var sites = $('tr-selsites');

    if (env === 'INTRA') {
      if (country) { country.value = ''; country.disabled = true; }
      setDisabled(lookupBtn('tr-country'), false);
      if (envname) { envname.value = ''; envname.disabled = true; }
      setDisabled(lookupBtn('tr-envname'), false);
      if (sites) { sites.value = ''; sites.disabled = true; }
      setDisabled(lookupBtn('tr-selsites'), false);
    } else if (env === 'PDF_ES' || env === 'PDF_TS') {
      if (country) country.disabled = false;
      setDisabled(lookupBtn('tr-country'), true);
      if (envname) envname.disabled = false;
      setDisabled(lookupBtn('tr-envname'), true);
      if (sites) sites.disabled = false;
      setDisabled(lookupBtn('tr-selsites'), true);
    } else if (env === 'MDB_ES' || env === 'MDB_TS') {
      if (country) country.disabled = false;
      setDisabled(lookupBtn('tr-country'), true);
      if (envname) { envname.value = ''; envname.disabled = true; }
      setDisabled(lookupBtn('tr-envname'), false);
      if (sites) sites.disabled = false;
      setDisabled(lookupBtn('tr-selsites'), true);
    } else {
      syncRequiredLabels();
      return;
    }
    setRepFlags();
    syncRequiredLabels();
  }

  function applyProtypeUi(clearOnChange) {
    var strValue = V.trim($('tr-protype').value).toUpperCase();
    var tsorb = $('tr-tsorbout');
    var tsorbRpt = $('tr-rpt-tsorb');
    var arc = $('tr-arc');
    var coord = $('tr-coordist');

    if (strValue === 'E') {
      if (clearOnChange && tsorb) { tsorb.value = 'N'; if (tsorbRpt) tsorbRpt.checked = false; }
      if (tsorb) tsorb.readOnly = true;
      if (arc) arc.readOnly = false;
      if (clearOnChange && coord) coord.value = '';
    } else {
      if (tsorb) tsorb.readOnly = false;
      if (arc) {
        arc.readOnly = true;
        if (clearOnChange) arc.value = '';
      }
    }
    selectedPdfType();
    setRepFlags();
    syncRequiredLabels();
  }

  function selPdfType(strValue) {
    if (!strValue) return;
    strValue = strValue.toUpperCase();
    if (strValue !== 'T' && strValue !== 'E') return;

    var orig = $('tr-orig-protype');
    var proname = $('tr-proname');
    var changed = orig && orig.value !== strValue;

    if (changed && proname) proname.value = '';
    if (orig) orig.value = strValue;

    applyProtypeUi(changed);
  }

  function selectedPdfType() {
    if (suppressBlurValidation || inFieldAlert) return;
    var pdfType = V.trim($('tr-protype').value).toUpperCase();
    var envEl = $('tr-envtype');
    if (!envEl) return;
    var env = V.trim(envEl.value).toUpperCase();
    if (pdfType === 'E' && env && env !== 'MDB_TS' && env !== 'PDF_TS') {
      fieldReject(envEl, 'Valid Env File Types under File Type of E are MDB_TS or PDF_TS');
      return;
    }
    setRepFlags();
  }

  function envFileType() {
    if (suppressBlurValidation || inFieldAlert) return;
    var envEl = $('tr-envtype');
    if (!envEl) return;
    envEl.value = V.trim(envEl.value).toUpperCase();
    // Empty is normal while filling / opening ? lookups — only reject non-empty junk.
    if (!envEl.value) {
      setRepFlags();
      return;
    }
    if (!V.ENV_TYPES[envEl.value]) {
      fieldReject(envEl, 'You have entered an invalid value for Env File Type');
      return;
    }
    chkEnvFile();
  }

  function checkOption() {
    var optEl = $('tr-analopt');
    if (!optEl) return;
    optEl.value = V.trim(optEl.value).toUpperCase();
    if (optEl.value === 'BAND' || optEl.value === 'PLAN') {
      if ($('tr-chancodes')) $('tr-chancodes').value = '';
      if ($('tr-numchan')) $('tr-numchan').value = '10';
    }
    setRepFlags();
    syncRequiredLabels();
  }

  function chkLossBlur() {
    if (suppressBlurValidation || inFieldAlert) return;
    var lossEl = $('tr-spherecalc');
    if (!lossEl) return;
    if (!V.trim(lossEl.value)) return;
    var ohloss = $('tr-rpt-ohloss');
    var r = V.chkLoss(
      $('tr-protype').value,
      $('tr-envtype').value,
      lossEl.value,
      ohloss && ohloss.checked
    );
    if ($('tr-loss-error')) $('tr-loss-error').value = r.ok ? '0' : '1';
    if (!r.ok) {
      fieldReject(lossEl, r.error);
      return;
    }
    setRepFlags();
  }

  function dispTSORB() {
    if (suppressBlurValidation || inFieldAlert) return;
    var el = $('tr-tsorbout');
    if (!el) return;
    el.value = V.trim(el.value).toUpperCase();
    if (!el.value) return;
    if (el.value !== 'Y' && el.value !== 'N') {
      fieldReject(el, 'TSORB must be Y or N');
      return;
    }
    var rpt = $('tr-rpt-tsorb');
    if (rpt) rpt.checked = el.value === 'Y';
  }

  function hiloCheck() {
    var hilo = $('tr-rpt-hilo');
    var secs = $('tr-hilosecs');
    if (!hilo || !secs) return;
    if (hilo.checked && !hilo.disabled) {
      if (!secs.value) secs.value = '7';
      secs.disabled = false;
    } else if (hilo.disabled || !hilo.checked) {
      if (!hilo.checked) secs.value = '';
      if (hilo.disabled) secs.disabled = true;
    }
  }

  function selectedCountry() {
    if (suppressBlurValidation || inFieldAlert) return;
    var el = $('tr-country');
    if (!el || el.disabled) return;
    el.value = V.trim(el.value).toUpperCase();
    if (!el.value) return;
    if (el.value !== 'CAN' && el.value !== 'USA' && el.value !== 'ALL') {
      fieldReject(el, 'You must provide a valid Country');
    }
  }

  function selectedEnvSites() {
    if (suppressBlurValidation || inFieldAlert) return;
    var env = V.trim($('tr-envtype').value).toUpperCase();
    var el = $('tr-selsites');
    if (!el || el.disabled) return;
    el.value = V.trim(el.value).toUpperCase();
    if (env === 'INTRA') {
      el.value = '';
      syncRequiredLabels();
      return;
    }
    var v = el.value;
    if (!v) {
      syncRequiredLabels();
      return;
    }
    if (!V.ENV_SITES[v]) {
      fieldReject(el, 'You must provide a valid value for Env Site');
      syncRequiredLabels();
      return;
    }
    checkCode();
    syncRequiredLabels();
  }

  function checkCode() {
    var sites = V.trim($('tr-selsites').value).toUpperCase();
    var codes = $('tr-codes');
    var btn = $('tr-codes-lookup');
    if (!codes) return;
    if (sites === 'CALL SIGN' || sites === 'OPERATOR CODE') {
      setReadOnly(codes, false);
      setDisabled(btn, true);
    } else if (sites === 'ALL' || sites === 'ALL EXCEPT SELF') {
      codes.value = '';
      if ($('tr-numcodes')) $('tr-numcodes').value = '0';
      setReadOnly(codes, true);
      setDisabled(btn, false);
    }
  }

  function caseCodes() {
    if (suppressBlurValidation || inFieldAlert) return;
    var codes = $('tr-codes');
    var numcodes = $('tr-numcodes');
    if (!codes) return;
    var norm = V.normalizeCodes(codes.value);
    if (norm.ok === false) {
      oneAlert(norm.error, codes);
      return;
    }
    if (norm.ok) {
      codes.value = norm.codes;
      if (numcodes) numcodes.value = norm.numcodes;
    }
  }

  function chkALL(strValue) {
    if (V.trim(strValue).toUpperCase() === 'ALL' && $('tr-chancodes')) {
      $('tr-chancodes').value = '0,1,2,3,4,5,6,7,8,9';
    }
  }

  function validatePdfFinished(valid, pronameEl) {
    if (suppressBlurValidation || inFieldAlert) return;
    valid = String(valid == null ? '' : valid).replace(/^"|"$/g, '');
    if (valid === 'not found') {
      fieldReject(pronameEl, 'No such File Name');
      return;
    }
    if (valid !== 'U' && valid !== 'T' && valid !== 'S' && valid !== 'K' && valid !== 'M' && valid !== 'L') {
      fieldReject(pronameEl, 'PDF must be validated (Ready) for TSIP');
    }
  }

  function validateEnvFileNameFinished(valid) {
    if (suppressBlurValidation || inFieldAlert) return;
    valid = String(valid == null ? '' : valid).replace(/^"|"$/g, '');
    var envname = $('tr-envname');
    if (valid === 'not found') {
      oneAlert('No such Env File Name', envname);
      return;
    }
    if (valid !== 'U' && valid !== 'T' && valid !== 'S' && valid !== 'K' && valid !== 'M' && valid !== 'L') {
      fieldReject(envname, 'Env PDF must be validated (Ready) for TSIP');
    }
  }

  function validatePdf(strValue) {
    if (suppressBlurValidation || inFieldAlert) return;
    var pdfType = V.trim($('tr-protype').value).toUpperCase();
    var pronameEl = $('tr-proname');
    if (!pdfType) {
      if ($('tr-protype')) $('tr-protype').focus();
      return;
    }
    if (!strValue || !window.RemIcsApi || !RemIcsApi.tsipValidate) return;
    var type = pdfType === 'T' ? 'ft_' : 'fe_';
    RemIcsApi.tsipValidate(type, V.trim(strValue)).then(function (r) {
      if (suppressBlurValidation || inFieldAlert) return;
      if (!r.ok) {
        oneAlert((window.RemIcsApi && RemIcsApi.apiErr)
          ? RemIcsApi.apiErr(r, 'Validate failed') : (r.error || r.body || 'Validate failed'));
        return;
      }
      validatePdfFinished(r.body, pronameEl);
    }).catch(function (ex) {
      oneAlert('Network/validate failed: ' + ((ex && ex.message) || String(ex || 'request failed')), pronameEl);
    });
  }

  function validateEnvFileName() {
    if (suppressBlurValidation || inFieldAlert) return;
    var envType = V.trim($('tr-envtype').value).toUpperCase();
    var envname = $('tr-envname');
    if (!envname || !V.trim(envname.value)) return;
    if (envType !== 'PDF_TS' && envType !== 'PDF_ES') return;
    if (!window.RemIcsApi || !RemIcsApi.tsipValidate) return;
    var type = envType === 'PDF_TS' ? 'ft_' : 'fe_';
    RemIcsApi.tsipValidate(type, V.trim(envname.value)).then(function (r) {
      if (suppressBlurValidation || inFieldAlert) return;
      if (!r.ok) {
        oneAlert((window.RemIcsApi && RemIcsApi.apiErr)
          ? RemIcsApi.apiErr(r, 'Validate failed') : (r.error || r.body || 'Validate failed'));
        return;
      }
      validateEnvFileNameFinished(r.body);
    }).catch(function (ex) {
      oneAlert('Network/validate failed: ' + ((ex && ex.message) || String(ex || 'request failed')), envname);
    });
  }

  function isValidRunNameBlur() {
    if (suppressBlurValidation || inFieldAlert) return;
    var el = $('tr-runname');
    if (!el || el.readOnly) return;
    // Classic isalphanumunder ignores empty — empty is checked only on Save.
    if (!V.trim(el.value)) return;
    var r = V.isValidRunName(el.value);
    if (!r.ok) fieldReject(el, r.error);
  }

  function getCallOper() {
    if (suppressBlurValidation || inFieldAlert) return;
    var sites = V.trim($('tr-selsites').value);
    var pdfType = V.trim($('tr-protype').value);
    var envType = V.trim($('tr-envtype').value);
    var efName = '';

    if (!sites) {
      if ($('tr-codes')) $('tr-codes').value = '';
      if ($('tr-numcodes')) $('tr-numcodes').value = '0';
      oneAlert('You must provide Env Sites info first', $('tr-selsites'));
      return;
    }
    if (!pdfType) {
      oneAlert('You must provide File Type info first');
      return;
    }
    if (!envType) {
      oneAlert('You must provide Env File Type info first', $('tr-envtype'));
      return;
    }
    if (envType.indexOf('PDF') >= 0) {
      efName = V.trim($('tr-envname').value);
      if (!efName) {
        oneAlert('You must provide Env File Name info first', $('tr-envname'));
        return;
      }
    }
    if (envType.indexOf('INTRA') >= 0) {
      efName = V.trim($('tr-proname').value);
      if (!efName) {
        oneAlert('You must provide File Name info first', $('tr-proname'));
        return;
      }
    }
    var args = pdfType + '^' + envType + '^' + efName + '^';
    if (window.RemicsLookup) {
      RemicsLookup.openTsipCodes(args + (sites === 'CALL SIGN' ? 'CALL SIGN' : 'OPERATOR CODE'), 'tr-codes');
    }
  }

  function fillRecord(rec, action) {
    if (!rec) return;
    Object.keys(rec).forEach(function (k) {
      var el = $('tr-' + k);
      if (el && k !== 'reports') el.value = rec[k] != null ? String(rec[k]) : '';
    });
    syncProtypeRadios();
    if ($('tr-orig-protype')) $('tr-orig-protype').value = V.trim(rec.protype || 'T').toUpperCase();

    var flags = V.decodeReportBitmask(rec.protype, rec.envtype, rec.reports);
    applyReportFlags(flags);
    if (V.trim(rec.tsorbout).toUpperCase() === 'Y' && $('tr-rpt-tsorb')) {
      $('tr-rpt-tsorb').checked = true;
    }

    chkEnvFile();
    checkCode();
    applyProtypeUi(false);

    var runEl = $('tr-runname');
    if (runEl) {
      if (action === 'edit') {
        runEl.readOnly = true;
        runEl.className = 'im irok';
      } else if (action === 'dup') {
        runEl.readOnly = false;
        runEl.className = 'im ik';
        runEl.value = '';
      } else {
        runEl.readOnly = false;
        runEl.className = 'im ik';
      }
    }
  }

  function initNewDefaults() {
    if ($('tr-runname')) { $('tr-runname').value = ''; $('tr-runname').readOnly = false; }
    if ($('tr-protype')) $('tr-protype').value = 'T';
    if ($('tr-orig-protype')) $('tr-orig-protype').value = 'T';
    if ($('tr-envtype')) $('tr-envtype').value = 'PDF_TS';
    if ($('tr-tsorbout')) { $('tr-tsorbout').value = 'N'; $('tr-tsorbout').readOnly = false; }
    // Classic tsipParmNew defaults — avoid empty required fields on Save.
    if ($('tr-spherecalc') && !V.trim($('tr-spherecalc').value)) $('tr-spherecalc').value = '3';
    if ($('tr-fsep') && !V.trim($('tr-fsep').value)) $('tr-fsep').value = '300.00';
    if ($('tr-coordist') && !V.trim($('tr-coordist').value)) $('tr-coordist').value = '200.00';
    if ($('tr-margin') && !V.trim($('tr-margin').value)) $('tr-margin').value = '0.00';
    if ($('tr-analopt') && !V.trim($('tr-analopt').value)) $('tr-analopt').value = 'BAND';
    if ($('tr-country') && !V.trim($('tr-country').value)) $('tr-country').value = 'ALL';
    if ($('tr-reports')) $('tr-reports').value = '0';
    if ($('tr-rpt-tsorb')) $('tr-rpt-tsorb').checked = false;
    applyReportFlags({});
    syncProtypeRadios();
    selPdfType('T');
    chkEnvFile();
    checkOption();
    syncRequiredLabels();
  }

  function wireClassicTsipFieldNames() {
    var codes = $('tr-codes');
    var num = $('tr-numcodes');
    if (codes) {
      if (!codes.name) codes.name = 'txtCode';
      window.txtCode = codes;
    }
    if (num) {
      if (!num.name) num.name = 'txtNumCodes';
      window.txtNumCodes = num;
    }
  }

  function wireLookups() {
    wireClassicTsipFieldNames();
    if (window.RemicsLookup) {
      RemicsLookup.bindDataLookupButtons(document);
    }
    // Lookup blur suppress is centralized in RemicsLookup.bindDataLookupButtons (remics-app.js).
    var callBtn = $('tr-codes-lookup');
    if (callBtn) callBtn.onclick = getCallOper;
  }

  function wireEvents() {
    document.querySelectorAll('input[name=tr-protype-r]').forEach(function (r) {
      r.onchange = function () {
        if (!r.checked) return;
        $('tr-protype').value = r.value;
        selPdfType(r.value);
      };
    });

    if ($('tr-envtype')) {
      // Classic: Env File Type has onfocus="" — never run envFileType on focus (alert+refocus loops).
      $('tr-envtype').onblur = function () { envFileType(); chkEnvFile(); };
      $('tr-envtype').onfocus = null;
    }
    if ($('tr-proname')) {
      $('tr-proname').onblur = function () {
        selectedPdfType();
        validatePdf(this.value);
      };
      $('tr-proname').onfocus = null;
    }
    if ($('tr-envname')) {
      $('tr-envname').onblur = function () { validateEnvFileName(); };
      $('tr-envname').onfocus = null;
    }
    if ($('tr-tsorbout')) {
      $('tr-tsorbout').onblur = function () {
        var env = V.trim($('tr-envtype').value).toUpperCase();
        if ((env === 'PDF_TS' || env === 'PDF_ES') && $('tr-envname') && !V.trim($('tr-envname').value)) {
          oneAlert('You must provide an Env File Name under PDF_TS or PDF_ES type', $('tr-envname'));
          return;
        }
        if (env === 'PDF_TS' || env === 'PDF_ES') validateEnvFileName();
        dispTSORB();
      };
      $('tr-tsorbout').onfocus = null;
    }
    if ($('tr-spherecalc')) $('tr-spherecalc').onblur = chkLossBlur;
    if ($('tr-analopt')) $('tr-analopt').onblur = checkOption;
    if ($('tr-chancodes')) $('tr-chancodes').onblur = function () { chkALL(this.value); };
    if ($('tr-country')) $('tr-country').onblur = selectedCountry;
    if ($('tr-selsites')) $('tr-selsites').onblur = selectedEnvSites;
    if ($('tr-codes')) $('tr-codes').onblur = caseCodes;
    if ($('tr-runname')) $('tr-runname').onblur = isValidRunNameBlur;

    ['exec', 'study', 'stat', 'detail', 'summary', 'aggint', 'aggcsv', 'ohloss'].forEach(function (k) {
      var el = $('tr-rpt-' + k);
      if (el) el.onchange = setRepFlags;
    });
    if ($('tr-rpt-hilo')) $('tr-rpt-hilo').onchange = function () { hiloCheck(); setRepFlags(); };
    if ($('tr-rpt-ohloss')) $('tr-rpt-ohloss').onchange = function () { chkLossBlur(); setRepFlags(); };
  }

  /**
   * Mount run form handlers. opts: { action, onReady }.
   */
  function mount(opts) {
    opts = opts || {};
    wireLookups();
    wireEvents();
    if (opts.action === 'new') initNewDefaults();
    else syncRequiredLabels();
    if (typeof opts.onReady === 'function') opts.onReady();
  }

  return {
    mount: mount,
    fieldMap: fieldMap,
    reportFlags: reportFlags,
    fillRecord: fillRecord,
    initNewDefaults: initNewDefaults,
    setRepFlags: setRepFlags,
    chkEnvFile: chkEnvFile,
    checkCode: checkCode,
    beginLeaveForm: beginLeaveForm,
    endLeaveForm: endLeaveForm
  };
})();
