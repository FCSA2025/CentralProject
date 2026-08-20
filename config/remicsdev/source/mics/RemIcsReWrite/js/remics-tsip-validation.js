// TSIP run validation  -  parity with classic Ttsipmenu/tsipValidation.js validate() + chkLoss + report bitmask.
var RemicsTsipValidation = (function () {
  var ENV_TYPES = { INTRA: 1, PDF_TS: 1, PDF_ES: 1, MDB_TS: 1, MDB_ES: 1 };
  var ENV_SITES = { ALL: 1, 'ALL EXCEPT SELF': 1, 'CALL SIGN': 1, 'OPERATOR CODE': 1 };
  var RUN_NAME_RE = /^[A-Za-z0-9_]{1,5}$/;

  function trim(s) {
    return String(s == null ? '' : s).replace(/^\s+|\s+$/g, '');
  }

  function getReportWeights(protype, envtype) {
    var r6 = 0x00040000;
    var r7 = 0x00020000;
    var r8 = 0x00010000;
    var r9 = 0x00008000;
    protype = trim(protype).toUpperCase();
    envtype = trim(envtype).toUpperCase();
    if (protype === 'T' && (envtype === 'PDF_TS' || envtype === 'INTRA' || envtype === 'MDB_TS')) {
      return { r1: 0x80000000, r2: 0x40000000, r3: 0x08000000, r4: 0x01000000, r5: 0x00800000, r6: r6, r7: r7, r8: r8, r9: r9 };
    }
    if (protype === 'T' && (envtype === 'PDF_ES' || envtype === 'MDB_ES')) {
      return { r1: 0x80000000, r2: 0x20000000, r3: 0x04000000, r4: 0x00400000, r5: 0x00100000, r6: r6, r7: r7, r8: r8, r9: 0 };
    }
    if (protype === 'E' && (envtype === 'MDB_TS' || envtype === 'PDF_TS')) {
      return { r1: 0x80000000, r2: 0x10000000, r3: 0x02000000, r4: 0x00200000, r5: 0x00080000, r6: r6, r7: r7, r8: r8, r9: 0 };
    }
    return null;
  }

  function decodeReportBitmask(protype, envtype, reportValue) {
    var w = getReportWeights(protype, envtype);
    var flags = {
      exec: false, study: false, stat: false, detail: false, summary: false,
      aggint: false, aggcsv: false, ohloss: false, hilo: false
    };
    if (!w) return flags;
    var runm = parseInt(String(reportValue || '0'), 10);
    if (isNaN(runm)) runm = 0;
    runm = runm | 0;
    if ((runm & w.r1) !== 0) flags.exec = true;
    if ((runm & w.r2) !== 0) flags.study = true;
    if ((runm & w.r3) !== 0) flags.stat = true;
    if ((runm & w.r4) !== 0) flags.detail = true;
    if ((runm & w.r5) !== 0) flags.summary = true;
    if ((runm & w.r6) !== 0) flags.aggint = true;
    if ((runm & w.r7) !== 0) flags.aggcsv = true;
    if ((runm & w.r8) !== 0) flags.ohloss = true;
    if (w.r9 && (runm & w.r9) !== 0) flags.hilo = true;
    return flags;
  }

  function buildReportBitmask(protype, envtype, flags) {
    var w = getReportWeights(protype, envtype);
    if (!w || !flags) return 0;
    var report = 0;
    if (flags.exec) report -= w.r1;
    if (flags.study) report += w.r2;
    if (flags.stat) report += w.r3;
    if (flags.detail) report += w.r4;
    if (flags.summary) report += w.r5;
    if (flags.aggint) report += w.r6;
    if (flags.aggcsv) report += w.r7;
    if (flags.ohloss) report += w.r8;
    if (flags.hilo && w.r9) report += w.r9;
    return report;
  }

  function isValidRunName(run) {
    run = trim(run);
    if (!run) return { ok: false, error: 'You must provide a value for TSIP Run Name.' };
    if (run.length > 5) return { ok: false, error: 'Maximum characters for run name is 5.' };
    if (!RUN_NAME_RE.test(run)) {
      return { ok: false, error: 'Run name must use only alphanumeric characters or underscore (max 5).' };
    }
    return { ok: true, value: run };
  }

  function chkLoss(protype, envtype, loss, ohLossOnly) {
    protype = trim(protype).toUpperCase();
    envtype = trim(envtype).toUpperCase();
    loss = trim(loss);
    if (!loss) return { ok: false, error: 'You must enter a value for Propagation Loss.' };
    if (protype === 'E') {
      if (loss !== '1' && loss !== '2') {
        return { ok: false, error: 'Propagation loss must be 1 or 2 under File Type of E.' };
      }
      return { ok: true };
    }
    if (protype === 'T' && (envtype === 'MDB_ES' || envtype === 'PDF_ES')) {
      if (loss !== '1' && loss !== '2') {
        return { ok: false, error: 'Propagation loss must be 1 or 2 under File Type of T and Env File Type of MDB_ES or PDF_ES.' };
      }
      return { ok: true };
    }
    if (protype === 'T' && envtype !== 'MDB_ES' && envtype !== 'PDF_ES') {
      if (loss !== '3' && loss !== '4' && loss !== '5') {
        return { ok: false, error: 'Propagation loss must be 3, 4 or 5 under File Type of T and Env File Type of MDB_TS, PDF_TS or INTRA.' };
      }
      if ((envtype === 'MDB_TS' || envtype === 'PDF_TS') && ohLossOnly && loss !== '5') {
        return { ok: false, error: 'Propagation loss must be 5 if OH Loss Only is checked.' };
      }
    }
    return { ok: true };
  }

  function validateChannelCodes(option, chancodes) {
    option = trim(option).toUpperCase();
    chancodes = trim(chancodes);
    if (!chancodes) {
      if (option === 'CHAN') {
        return { ok: false, error: 'You must provide a value for Channel Status Codes under CHAN analysis option.' };
      }
      return { ok: true, chancodes: '', numchan: option === 'BAND' || option === 'PLAN' ? '10' : '' };
    }
    if (option === 'BAND' || option === 'PLAN') {
      return { ok: true, chancodes: '', numchan: '10' };
    }
    if (chancodes === '0,1,2,3,4,5,6,7,8,9') {
      return { ok: true, chancodes: chancodes, numchan: '10' };
    }
    if (chancodes.length < 1) return { ok: true, chancodes: chancodes, numchan: '' };
    var c0 = chancodes.charCodeAt(0);
    var cN = chancodes.charCodeAt(chancodes.length - 1);
    if (c0 < 48 || c0 > 57) {
      return { ok: false, error: 'Invalid value(s) for Channel Codes, values must start with a number.' };
    }
    if (cN < 48 || cN > 57) {
      return { ok: false, error: 'Invalid value(s) for Channel Codes, values must end with a number.' };
    }
    for (var i = 1; i <= chancodes.length - 1; i++) {
      if (i % 2 === 1) {
        if (chancodes.charCodeAt(i) !== 44) {
          return { ok: false, error: 'You must provide valid values for Channel Status Codes.' };
        }
      } else if (chancodes.charCodeAt(i) < 48 || chancodes.charCodeAt(i) > 57) {
        return { ok: false, error: 'You must provide valid values for Channel Status Codes.' };
      }
    }
    return { ok: true, chancodes: chancodes, numchan: '' };
  }

  function normalizeCodes(codes) {
    codes = trim(codes).toUpperCase();
    if (!codes) return { ok: true, codes: '', numcodes: '0' };
    if (codes.indexOf(' ') >= 0) {
      return { ok: false, error: 'No blanks allowed in codes list. Use commas as separators.' };
    }
    return { ok: true, codes: codes, numcodes: String(codes.split(',').length) };
  }

  /**
   * Full save validation. f = field map; rpt = report checkbox flags object.
   * Returns { ok, errors[], fields } with normalized values including reports bitmask.
   */
  function validate(f, rpt) {
    var errors = [];
    f = f || {};
    rpt = rpt || {};
    var out = {};
    var pdfType = trim(f.protype).toUpperCase();
    var envType = trim(f.envtype).toUpperCase();
    var pdf = trim(f.proname);
    var envName = trim(f.envname);
    var margin = trim(f.margin);
    var loss = trim(f.spherecalc);
    var option = trim(f.analopt).toUpperCase();
    var country = trim(f.country).toUpperCase();
    var sites = trim(f.selsites).toUpperCase();
    var coord = trim(f.coordist);
    var codesRaw = trim(f.codes);
    var tsorb = trim(f.tsorbout).toUpperCase() || 'N';

    if (pdfType !== 'T' && pdfType !== 'E') errors.push('File Type must be T or E.');
    if (!envType) {
      errors.push('You must provide a value for Env File Type.');
    } else if (!ENV_TYPES[envType]) {
      errors.push('You must provide a valid value for Env File Type.');
    }
    if (pdfType === 'E' && envType && envType !== 'MDB_TS' && envType !== 'PDF_TS') {
      errors.push('Valid Env File Types under File Type of E are MDB_TS or PDF_TS.');
    }
    if (!pdf) errors.push('You must provide the File Name info.');
    if (margin === '') {
      errors.push('You must provide a value for Required Margin (default = 0).');
    } else {
      out.margin = margin;
    }
    var lossCheck = chkLoss(pdfType, envType, loss, !!rpt.ohloss);
    if (!lossCheck.ok) errors.push(lossCheck.error);
    else out.spherecalc = loss;

    if (pdfType === 'T' && coord === '') {
      errors.push('You must provide a co-ordination distance for File Type T.');
    } else {
      out.coordist = coord;
    }
    if (!option) {
      errors.push('You must provide a value for Analysis Option.');
    } else if (option !== 'BAND' && option !== 'PLAN' && option !== 'CHAN') {
      errors.push('You must provide a valid value for Analysis Option.');
    } else {
      out.analopt = option;
    }

    var chanCheck = validateChannelCodes(option, f.chancodes);
    if (!chanCheck.ok) errors.push(chanCheck.error);
    else {
      out.chancodes = chanCheck.chancodes != null ? chanCheck.chancodes : trim(f.chancodes);
      if (chanCheck.numchan !== undefined) out.numchan = chanCheck.numchan;
      else out.numchan = trim(f.numchan);
    }

    if (envType === 'MDB_TS' || envType === 'MDB_ES') envName = '';
    if (envType === 'INTRA') {
      out.country = '';
      out.selsites = '';
    } else {
      if (!country) {
        errors.push('You must provide a value for Country.');
      } else if (country !== 'CAN' && country !== 'USA' && country !== 'ALL') {
        errors.push('You must provide a valid value for Country.');
      } else {
        out.country = country;
      }
      if (!sites) {
        errors.push('You must provide a value for Env Sites.');
      } else if (!ENV_SITES[sites]) {
        errors.push('You must provide a valid value for Env Sites.');
      } else {
        out.selsites = sites;
        if (sites === 'CALL SIGN' && trim(codesRaw).length <= 1) {
          errors.push('You must provide at least one call sign.');
        }
        if (sites === 'OPERATOR CODE' && trim(codesRaw).length <= 1) {
          errors.push('You must provide at least one operator code.');
        }
      }
    }

    var runCheck = isValidRunName(f.runname);
    if (!runCheck.ok) errors.push(runCheck.error);
    else out.runname = runCheck.value;

    if ((envType === 'PDF_TS' || envType === 'PDF_ES') && !envName) {
      errors.push('You must provide Env File Name info under PDF_TS or PDF_ES option.');
    } else {
      out.envname = envName;
    }

    if (rpt.hilo) {
      var hilo = trim(f.hilosecs);
      if (!hilo) errors.push('You must provide an Arc Secs value for the HiLo Report.');
      else {
        var hiloN = parseInt(hilo, 10);
        if (isNaN(hiloN) || hiloN < 1 || hiloN > 99) {
          errors.push('HiLo secs of latitude must be between 1 and 99.');
        } else {
          out.hilosecs = String(hiloN);
        }
      }
    } else {
      out.hilosecs = trim(f.hilosecs);
    }

    var codeNorm = normalizeCodes(codesRaw);
    if (codeNorm.ok === false) errors.push(codeNorm.error);
    else if (codeNorm.ok) {
      out.codes = codeNorm.codes;
      out.numcodes = codeNorm.numcodes;
    }

    out.protype = pdfType;
    out.envtype = envType;
    out.proname = pdf;
    out.tsorbout = tsorb === 'Y' ? 'Y' : 'N';
    out.fsep = trim(f.fsep);
    out.arc = trim(f.arc);
    out.cullmarg = trim(f.cullmarg);

    var report = buildReportBitmask(pdfType, envType, rpt);
    if (report === 0 && out.tsorbout !== 'Y') {
      errors.push('You must select at least 1 report.');
    }
    out.reports = String(report);

    return { ok: errors.length === 0, errors: errors, fields: out };
  }

  return {
    trim: trim,
    validate: validate,
    chkLoss: chkLoss,
    isValidRunName: isValidRunName,
    getReportWeights: getReportWeights,
    decodeReportBitmask: decodeReportBitmask,
    buildReportBitmask: buildReportBitmask,
    validateChannelCodes: validateChannelCodes,
    normalizeCodes: normalizeCodes,
    RUN_NAME_RE: RUN_NAME_RE,
    ENV_TYPES: ENV_TYPES,
    ENV_SITES: ENV_SITES
  };
})();
