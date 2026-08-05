// Phase 6.75 — TSIP run save validation (subset of classic tsipValidation.js).
var RemicsTsipValidation = (function () {
  function trim(s) { return String(s == null ? '' : s).replace(/^\s+|\s+$/g, ''); }

  /** Validate fields object from tsip-run form. Returns { ok, errors[] }. */
  function validate(f) {
    var errors = [];
    f = f || {};
    var pdfType = trim(f.protype).toUpperCase();
    var envType = trim(f.envtype).toUpperCase();
    var run = trim(f.runname);
    var pdf = trim(f.proname);
    var envName = trim(f.envname);
    var margin = trim(f.margin);
    var loss = trim(f.spherecalc);
    var option = trim(f.analopt).toUpperCase();
    var country = trim(f.country).toUpperCase();
    var sites = trim(f.selsites).toUpperCase();
    var coord = trim(f.coordist);
    var reports = trim(f.reports);

    if (pdfType !== 'T' && pdfType !== 'E') errors.push('PDF type must be T or E.');
    var envOk = { INTRA: 1, PDF_TS: 1, PDF_ES: 1, MDB_TS: 1, MDB_ES: 1 };
    if (!envOk[envType]) errors.push('Env file type invalid.');
    if (pdfType === 'E' && envType !== 'MDB_TS' && envType !== 'PDF_TS') {
      errors.push('ES PDF type requires env MDB_TS or PDF_TS.');
    }
    if (!pdf) errors.push('PDF / proname is required.');
    if (!run) errors.push('Run name is required.');
    if (!/^[A-Za-z0-9_]{1,16}$/.test(run)) errors.push('Run name must be 1–16 A-Za-z0-9_.');
    if (margin === '') f.margin = '0.00';
    if (!loss) errors.push('Sphere / loss is required.');
    if (pdfType === 'T' && coord === '') errors.push('Coord dist is required for TS.');
    if (option !== 'BAND' && option !== 'PLAN' && option !== 'CHAN') {
      errors.push('Anal option must be BAND, PLAN, or CHAN.');
    }
    if (option === 'CHAN' && !trim(f.chancodes)) errors.push('Chan codes required when option is CHAN.');
    if (envType !== 'INTRA') {
      if (country !== 'CAN' && country !== 'USA' && country !== 'ALL') {
        errors.push('Country must be CAN, USA, or ALL.');
      }
    }
    if (!sites) errors.push('Env sites selection is required.');
    if ((sites === 'CALL SIGN' || sites === 'OPERATOR CODE') && !trim(f.codes)) {
      errors.push('Codes required for CALL SIGN / OPERATOR CODE.');
    }
    if ((envType === 'PDF_TS' || envType === 'PDF_ES') && !envName) {
      errors.push('Env file name required for PDF_* env types.');
    }
    // Classic builds a report bitmask; rewrite uses numeric reports field (0 allowed for draft).
    if (reports === '' && trim(f.tsorbout).toUpperCase() !== 'Y') {
      errors.push('Reports field required (use 0 for none, or Orb calc = Y).');
    }
    return { ok: errors.length === 0, errors: errors };
  }

  return { validate: validate };
})();
