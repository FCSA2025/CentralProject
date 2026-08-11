/**
 * Bulk-verify TSIP report bitmasks from remicsdev DB round-trip through RemicsTsipValidation.
 * Run: node tests/remicsdev/tsip-db-report-parity.test.js
 * Requires: prior agent/session with SQL access exported to tests/remicsdev/fixtures/tsip-parm-samples.tsv
 *           OR run scripts/Export-TsipParmSamples.ps1 first.
 */
'use strict';

var fs = require('fs');
var path = require('path');
var vm = require('vm');

var fixture = path.join(__dirname, 'fixtures/tsip-parm-samples.tsv');
if (!fs.existsSync(fixture)) {
  console.log('Skip DB bulk test — no fixture at ' + fixture);
  console.log('Run: scripts/Export-TsipParmSamples.ps1');
  process.exit(0);
}

var src = fs.readFileSync(
  path.join(__dirname, '../../config/remicsdev/source/mics/RemIcsReWrite/js/remics-tsip-validation.js'),
  'utf8'
);
var sandbox = {};
vm.runInNewContext(src, sandbox);
var V = sandbox.RemicsTsipValidation;

var lines = fs.readFileSync(fixture, 'utf8').split(/\r?\n/).filter(Boolean);
var header = lines.shift().split('\t');
var idx = {};
header.forEach(function (h, i) { idx[h.trim()] = i; });

var passed = 0;
var failed = 0;
lines.forEach(function (line, n) {
  var cols = line.split('\t');
  var protype = cols[idx.protype].trim();
  var envtype = cols[idx.envtype].trim();
  var reports = cols[idx.reports].trim();
  if (!reports || reports === 'NULL' || protype === '-' || envtype === '-') return;
  var decoded = V.decodeReportBitmask(protype, envtype, reports);
  var rebuilt = V.buildReportBitmask(protype, envtype, decoded);
  if (String(rebuilt) !== String(parseInt(reports, 10))) {
    console.error('FAIL line', n + 2, protype, envtype, reports, '->', rebuilt);
    failed++;
  } else {
    passed++;
  }
});

if (failed) {
  console.error(failed + ' failed, ' + passed + ' passed');
  process.exit(1);
}
console.log('DB bulk report parity: ' + passed + ' samples OK');
