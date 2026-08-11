// TSIP run form — live field switching parity with classic tsipValidation.js + tsipParm*.aspx.
var RemicsTsipRunForm = (function () {
  var V = window.RemicsTsipValidation;

  function $(id) { return document.getElementById(id); }

  function setDisabled(el, on) {
    if (!el) return;
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
      return;
    }
    setRepFlags();
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
    var pdfType = V.trim($('tr-protype').value).toUpperCase();
    var envEl = $('tr-envtype');
    if (!envEl) return;
    var env = V.trim(envEl.value).toUpperCase();
    if (pdfType === 'E' && env && env !== 'MDB_TS' && env !== 'PDF_TS') {
      alert('Valid Env File Types under File Type of E are MDB_TS or PDF_TS');
      envEl.value = '';
      envEl.focus();
      return;
    }
    setRepFlags();
  }

  function envFileType() {
    var envEl = $('tr-envtype');
    if (!envEl) return;
    envEl.value = V.trim(envEl.value).toUpperCase();
    if (!V.ENV_TYPES[envEl.value]) {
      alert('You have entered an invalid value for Env File Type');
      envEl.value = '';
      envEl.focus();
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
  }

  function chkLossBlur() {
    var lossEl = $('tr-spherecalc');
    if (!lossEl) return;
    var ohloss = $('tr-rpt-ohloss');
    var r = V.chkLoss(
      $('tr-protype').value,
      $('tr-envtype').value,
      lossEl.value,
      ohloss && ohloss.checked
    );
    if ($('tr-loss-error')) $('tr-loss-error').value = r.ok ? '0' : '1';
    if (!r.ok) {
      alert(r.error);
      lossEl.value = '';
      lossEl.focus();
      return;
    }
    setRepFlags();
  }

  function dispTSORB() {
    var el = $('tr-tsorbout');
    if (!el) return;
    el.value = V.trim(el.value).toUpperCase();
    if (el.value !== 'Y' && el.value !== 'N') {
      alert('TSORB must be Y or N');
      el.value = '';
      el.focus();
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
    var el = $('tr-country');
    if (!el || el.disabled) return;
    el.value = V.trim(el.value).toUpperCase();
    if (el.value && el.value !== 'CAN' && el.value !== 'USA' && el.value !== 'ALL') {
      alert('You must provide a valid Country');
      el.value = '';
      el.focus();
    }
  }

  function selectedEnvSites() {
    var env = V.trim($('tr-envtype').value).toUpperCase();
    var el = $('tr-selsites');
    if (!el || el.disabled) return;
    el.value = V.trim(el.value).toUpperCase();
    if (env === 'INTRA') {
      el.value = '';
      return;
    }
    var v = el.value;
    if (v && !V.ENV_SITES[v]) {
      alert('You must provide a valid value for Env Site');
      el.value = '';
      el.focus();
      return;
    }
    checkCode();
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
    var codes = $('tr-codes');
    var numcodes = $('tr-numcodes');
    if (!codes) return;
    var norm = V.normalizeCodes(codes.value);
    if (norm.ok === false) {
      alert(norm.error);
      codes.focus();
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
    valid = String(valid == null ? '' : valid).replace(/^"|"$/g, '');
    if (valid === 'not found') {
      alert('No such File Name');
      if (pronameEl) { pronameEl.value = ''; pronameEl.focus(); }
      return;
    }
    if (valid !== 'U' && valid !== 'T' && valid !== 'S' && valid !== 'K' && valid !== 'M' && valid !== 'L') {
      alert('Your Pdf is not a valid file for running TSIP');
      if (pronameEl) { pronameEl.value = ''; pronameEl.focus(); }
    }
  }

  function validateEnvFileNameFinished(valid) {
    valid = String(valid == null ? '' : valid).replace(/^"|"$/g, '');
    var envname = $('tr-envname');
    if (valid === 'not found') {
      alert('No such Env File Name');
      if (envname) envname.focus();
      return;
    }
    if (valid !== 'U' && valid !== 'T' && valid !== 'S' && valid !== 'K' && valid !== 'M' && valid !== 'L') {
      alert('Your Env File Name is not a valid file for running TSIP');
      if (envname) { envname.value = ''; envname.focus(); }
    }
  }

  function validatePdf(strValue) {
    var pdfType = V.trim($('tr-protype').value).toUpperCase();
    var pronameEl = $('tr-proname');
    if (!pdfType) {
      $('tr-protype').focus();
      return;
    }
    if (!strValue || !window.RemIcsApi || !RemIcsApi.tsipValidate) return;
    var type = pdfType === 'T' ? 'ft_' : 'fe_';
    RemIcsApi.tsipValidate(type, V.trim(strValue)).then(function (r) {
      validatePdfFinished(r.body, pronameEl);
    }).catch(function () { /* ignore network */ });
  }

  function validateEnvFileName() {
    var envType = V.trim($('tr-envtype').value).toUpperCase();
    var envname = $('tr-envname');
    if (!envname || !V.trim(envname.value)) return;
    if (envType !== 'PDF_TS' && envType !== 'PDF_ES') return;
    if (!window.RemIcsApi || !RemIcsApi.tsipValidate) return;
    var type = envType === 'PDF_TS' ? 'ft_' : 'fe_';
    RemIcsApi.tsipValidate(type, V.trim(envname.value)).then(function (r) {
      validateEnvFileNameFinished(r.body);
    }).catch(function () { /* ignore */ });
  }

  function isValidRunNameBlur() {
    var el = $('tr-runname');
    if (!el || el.readOnly) return;
    var r = V.isValidRunName(el.value);
    if (!r.ok) {
      alert(r.error);
      el.value = '';
      el.focus();
    }
  }

  function getCallOper() {
    var sites = V.trim($('tr-selsites').value);
    var pdfType = V.trim($('tr-protype').value);
    var envType = V.trim($('tr-envtype').value);
    var efName = '';
    var root = (window.RemIcsApi && RemIcsApi.micsRoot) ? RemIcsApi.micsRoot() : '/mics/';

    if (!sites) {
      alert('You must provide Env Sites info first');
      if ($('tr-codes')) $('tr-codes').value = '';
      if ($('tr-numcodes')) $('tr-numcodes').value = '0';
      $('tr-selsites').focus();
      return;
    }
    if (!pdfType) {
      alert('You must provide File Type info first');
      return;
    }
    if (!envType) {
      alert('You must provide Env File Type info first');
      return;
    }
    if (envType.indexOf('PDF') >= 0) {
      efName = V.trim($('tr-envname').value);
      if (!efName) {
        alert('You must provide Env File Name info first');
        return;
      }
    }
    if (envType.indexOf('INTRA') >= 0) {
      efName = V.trim($('tr-proname').value);
      if (!efName) {
        alert('You must provide File Name info first');
        return;
      }
    }
    var args = pdfType + '^' + envType + '^' + efName + '^';
    if (sites === 'CALL SIGN') {
      window.open(root + 'lookuptsip/luTsipSiteCodesCrit.aspx?text=' + encodeURIComponent(args + 'CALL SIGN'), 'XX',
        'left=100,top=100,width=550,height=600');
    } else {
      window.open(root + 'lookuptsip/luTsipOperCodesCrit.aspx?text=' + encodeURIComponent(args + 'OPERATOR CODE'), 'YY',
        'left=100,top=100,width=550,height=600');
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
    if ($('tr-reports')) $('tr-reports').value = '0';
    if ($('tr-rpt-tsorb')) $('tr-rpt-tsorb').checked = false;
    applyReportFlags({});
    syncProtypeRadios();
    selPdfType('T');
    chkEnvFile();
  }

  function wireLookups() {
    document.querySelectorAll('[data-lookup]').forEach(function (btn) {
      if (btn.getAttribute('data-lookup') === 'TsipCallOper') return;
      btn.onclick = function () {
        var lt = btn.getAttribute('data-lookup');
        var fld = btn.getAttribute('data-field');
        var root = (window.RemIcsApi && RemIcsApi.micsRoot) ? RemIcsApi.micsRoot() : '/mics/';
        window.open(root + 'lookupscrns/lookup1.aspx?type=' + encodeURIComponent(lt) +
          '&fld=' + encodeURIComponent(fld), 'WndLookup',
          'toolbar=no,menubar=yes,scrollbars=yes,resizable=yes,width=520,height=420');
      };
    });
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
      $('tr-envtype').onblur = function () { envFileType(); chkEnvFile(); };
      $('tr-envtype').onfocus = function () { envFileType(); };
    }
    if ($('tr-proname')) {
      $('tr-proname').onblur = function () { validatePdf(this.value); };
      $('tr-proname').onfocus = function () { envFileType(); selectedPdfType(); };
    }
    if ($('tr-envname')) {
      $('tr-envname').onblur = function () { validateEnvFileName(); };
      $('tr-envname').onfocus = function () {
        var env = V.trim($('tr-envtype').value).toUpperCase();
        if (env !== 'PDF_TS' && env !== 'PDF_ES') {
          if ($('tr-tsorbout') && !$('tr-tsorbout').readOnly) $('tr-tsorbout').focus();
          else if ($('tr-spherecalc')) $('tr-spherecalc').focus();
        }
      };
    }
    if ($('tr-tsorbout')) {
      $('tr-tsorbout').onblur = function () {
        var env = V.trim($('tr-envtype').value).toUpperCase();
        if (env === 'PDF_TS' || env === 'PDF_ES') validateEnvFileName();
        dispTSORB();
      };
      $('tr-tsorbout').onfocus = function () {
        var env = V.trim($('tr-envtype').value).toUpperCase();
        if ((env === 'PDF_TS' || env === 'PDF_ES') && $('tr-envname') && !$('tr-envname').value) {
          alert('You must provide an Env File Name under PDF_TS or PDF_ES type');
          $('tr-envname').focus();
        }
      };
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
    if (typeof opts.onReady === 'function') opts.onReady();
  }

  return {
    mount: mount,
    fieldMap: fieldMap,
    reportFlags: reportFlags,
    fillRecord: fillRecord,
    initNewDefaults: initNewDefaults,
    setRepFlags: setRepFlags,
    chkEnvFile: chkEnvFile
  };
})();
