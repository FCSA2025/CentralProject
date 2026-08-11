/**
 * TSIP validation parity tests — mirrors classic tsipValidation.js report bitmask + rules.
 * Run: node tests/remicsdev/tsip-validation-parity.test.js
 */
'use strict';

var fs = require('fs');
var path = require('path');
var vm = require('vm');

var src = fs.readFileSync(
  path.join(__dirname, '../../config/remicsdev/source/mics/RemIcsReWrite/js/remics-tsip-validation.js'),
  'utf8'
);
var sandbox = { window: {} };
vm.runInNewContext(src, sandbox);
var V = sandbox.RemicsTsipValidation;

function classicBuild(protype, envtype, flags) {
  var r1, r2, r3, r4, r5, r6 = 0x00040000, r7 = 0x00020000, r8 = 0x00010000, r9;
  protype = protype.toUpperCase();
  envtype = envtype.toUpperCase();
  if (protype === 'T' && (envtype === 'PDF_TS' || envtype === 'INTRA' || envtype === 'MDB_TS')) {
    r1 = 0x80000000; r2 = 0x40000000; r3 = 0x8000000; r4 = 0x1000000; r5 = 0x800000; r9 = 0x00008000;
  } else if (protype === 'T' && (envtype === 'PDF_ES' || envtype === 'MDB_ES')) {
    r1 = 0x80000000; r2 = 0x20000000; r3 = 0x4000000; r4 = 0x400000; r5 = 0x100000; r9 = 0;
  } else if (protype === 'E' && (envtype === 'MDB_TS' || envtype === 'PDF_TS')) {
    r1 = 0x80000000; r2 = 0x10000000; r3 = 0x2000000; r4 = 0x200000; r5 = 0x80000; r9 = 0;
  } else {
    return null;
  }
  var s = flags;
  return - (s.exec ? 1 : 0) * r1
    + (s.study ? 1 : 0) * r2
    + (s.stat ? 1 : 0) * r3
    + (s.detail ? 1 : 0) * r4
    + (s.summary ? 1 : 0) * r5
    + (s.aggint ? 1 : 0) * r6
    + (s.aggcsv ? 1 : 0) * r7
    + (s.ohloss ? 1 : 0) * r8
    + (s.hilo && r9 ? 1 : 0) * r9;
}

function assert(cond, msg) {
  if (!cond) throw new Error('FAIL: ' + msg);
}

var combos = [
  ['T', 'PDF_TS'], ['T', 'MDB_TS'], ['T', 'INTRA'], ['T', 'PDF_ES'], ['T', 'MDB_ES'],
  ['E', 'PDF_TS'], ['E', 'MDB_TS']
];
var flagKeys = ['exec', 'study', 'stat', 'detail', 'summary', 'aggint', 'aggcsv', 'ohloss', 'hilo'];
var passed = 0;

combos.forEach(function (c) {
  var protype = c[0], envtype = c[1];
  flagKeys.forEach(function (fk) {
    var flags = {};
    flagKeys.forEach(function (k) { flags[k] = k === fk; });
    if (fk === 'hilo' && protype === 'T' && (envtype === 'PDF_ES' || envtype === 'MDB_ES')) return;
    if (fk === 'hilo' && protype === 'E') return;
    var classic = classicBuild(protype, envtype, flags);
    var ours = V.buildReportBitmask(protype, envtype, flags);
    assert(classic === ours, protype + '+' + envtype + ' flag=' + fk + ' classic=' + classic + ' ours=' + ours);
    var decoded = V.decodeReportBitmask(protype, envtype, ours);
    assert(!!decoded[fk], 'round-trip decode ' + fk + ' for ' + protype + '+' + envtype);
    passed++;
  });

  // all flags on (where allowed)
  var all = { exec: true, study: true, stat: true, detail: true, summary: true, aggint: true, aggcsv: true, ohloss: true, hilo: true };
  if (protype === 'T' && (envtype === 'PDF_ES' || envtype === 'MDB_ES')) all.hilo = false;
  if (protype === 'E') all.hilo = false;
  var cAll = classicBuild(protype, envtype, all);
  var oAll = V.buildReportBitmask(protype, envtype, all);
  assert(cAll === oAll, 'all-flags ' + protype + '+' + envtype + ' classic=' + cAll + ' ours=' + oAll);
  passed++;
});

// chkLoss matrix
[
  ['E', 'PDF_TS', '1', false, true],
  ['E', 'PDF_TS', '3', false, false],
  ['T', 'PDF_ES', '2', false, true],
  ['T', 'PDF_TS', '5', true, true],
  ['T', 'PDF_TS', '4', true, false],
  ['T', 'INTRA', '3', false, true],
  ['T', 'INTRA', '1', false, false]
].forEach(function (t) {
  var r = V.chkLoss(t[0], t[1], t[2], t[3]);
  assert(r.ok === t[4], 'chkLoss ' + t.join(','));
  passed++;
});

// validate minimal valid TS run
var base = {
  protype: 'T', envtype: 'PDF_TS', proname: 'testpdf', envname: 'testenv',
  margin: '0', spherecalc: '3', coordist: '50', analopt: 'BAND',
  country: 'CAN', selsites: 'ALL', runname: 'run01', codes: '', chancodes: '', numchan: '',
  tsorbout: 'N', fsep: '', arc: '', cullmarg: '', hilosecs: ''
};
var rpt = { exec: true, study: false, stat: false, detail: false, summary: false, aggint: false, aggcsv: false, ohloss: false, hilo: false };
var vr = V.validate(base, rpt);
assert(vr.ok, 'minimal valid TS: ' + vr.errors.join('; '));
assert(vr.fields.reports === String(V.buildReportBitmask('T', 'PDF_TS', rpt)), 'reports in fields');
passed++;

// INTRA skips country/sites
var intra = Object.assign({}, base, { envtype: 'INTRA', envname: '', country: '', selsites: '' });
var vi = V.validate(intra, rpt);
assert(vi.ok, 'INTRA valid: ' + vi.errors.join('; '));
passed++;

// ES env restriction
var esBad = Object.assign({}, base, { protype: 'E', envtype: 'PDF_ES' });
var ve = V.validate(esBad, rpt);
assert(!ve.ok, 'ES+PDF_ES should fail');
passed++;

// run name length
assert(!V.isValidRunName('123456').ok, 'run name >5 fails');
assert(V.isValidRunName('abc_1').ok, 'run name 5 ok');
passed++;

// BuildParmParm parity (mirrors tsip-run.ashx BuildParmParm)
function buildParmParm(f) {
  if (f.parmparm) return f.parmparm;
  var c = '';
  var protype = (f.protype || '').toUpperCase();
  var envtype = (f.envtype || '').toUpperCase();
  if (protype === 'E' && f.arc) c = 'ARCSTEP=' + f.arc;
  if (protype === 'T' && (envtype === 'INTRA' || envtype === 'MDB_TS' || envtype === 'PDF_TS')) {
    if (f.cullmarg) {
      c += 'CM=' + f.cullmarg;
      if (f.hilosecs) c += ',HILO=' + f.hilosecs;
    } else if (f.hilosecs) {
      c = 'HILO=' + f.hilosecs;
    }
  }
  return c;
}
[
  [{ protype: 'E', envtype: 'MDB_TS', arc: '2' }, 'ARCSTEP=2'],
  [{ protype: 'T', envtype: 'MDB_TS', cullmarg: '10', hilosecs: '7' }, 'CM=10,HILO=7'],
  [{ protype: 'T', envtype: 'INTRA', hilosecs: '7' }, 'HILO=7'],
  [{ protype: 'T', envtype: 'PDF_TS', cullmarg: '5' }, 'CM=5'],
  [{ protype: 'T', envtype: 'MDB_ES', hilosecs: '7' }, ''],
  [{ protype: 'E', envtype: 'PDF_TS', arc: '' }, '']
].forEach(function (t) {
  assert(buildParmParm(t[0]) === t[1], 'BuildParmParm ' + JSON.stringify(t[0]));
  passed++;
});

// Real DB record: frse.tp_agginttest_parm run "1"
(function () {
  var flags = V.decodeReportBitmask('T', 'MDB_TS', '1225097216');
  var f = {
    runname: '1', protype: 'T', envtype: 'MDB_TS', proname: 'agginttest', envname: '',
    tsorbout: 'N', spherecalc: '5', fsep: '300.0', coordist: '200.0', analopt: 'CHAN',
    margin: '10.0', chancodes: '0,1,2,3,4,5,6,7,8,9', numchan: '10', country: 'ALL',
    selsites: 'ALL', codes: '', cullmarg: '10', hilosecs: '7', arc: ''
  };
  var vr = V.validate(f, flags);
  assert(vr.ok, 'DB run agginttest/1: ' + vr.errors.join('; '));
  assert(vr.fields.reports === '1225097216', 'DB run reports match');
  assert(buildParmParm({ protype: 'T', envtype: 'MDB_TS', cullmarg: '10', hilosecs: '7' }) === 'CM=10,HILO=7', 'parmparm match');
  passed += 3;
})();

console.log('All ' + passed + ' TSIP parity checks passed.');
