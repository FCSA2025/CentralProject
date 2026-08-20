// RemIcsReWrite  -  SDF record layouts (classic Tsdfmenu sdf*.aspx).
(function (global) {
  function f(name, label, extra) {
    var o = { name: name, label: label };
    if (extra) Object.keys(extra).forEach(function (k) { o[k] = extra[k]; });
    return o;
  }

  var SPECS = {
    Eqpt: {
      kind: 'Equipment', keys: ['ecode'], keyMsg: 'You must enter an Equipment Code to continue',
      rows: [
        [f('cmd', 'SDB Operation', { max: 1, lookup: 'MdbOperation', cmd: true, colspan: 3 })],
        [f('ecode', 'Equipment Code', { max: 8, key: true }), f('etraf', 'Traffic Code', { max: 6 })],
        [f('estab', 'Stability', { max: 8, blur: 'f,0,0.999999,6' }), f('emission', 'Emission<br>Designator', { max: 10, opt: true })],
        [f('exref', 'Cross Reference', { max: 8, opt: true, lookup: 'EqptCode', lookupM: true, colspan: 3 })],
        [f('ebndcde', 'Frequency Band', { max: 4, opt: true, lookup: 'BandCode' }), f('etype', 'Type', { max: 2, lookup: 'EqptType' })],
        [f('emanu', 'Manufacturer', { max: 10, lookup: 'EqptManu', lookupM: true }), f('emodel', 'Model', { max: 20, opt: true })],
        [f('edesc', 'Equipment Description', { max: 32, colspan: 3 })],
        [f('e1stif', 'First IF', { max: 5, blur: 'f,0.1,999.9,1' }), f('e2ndif', 'Second IF', { max: 5, blur: 'f,0.1,999.9,1' })],
        [f('thhold', 'Receive Threshold', { max: 6, opt: true, blur: 'f,-200.0,0.0,1' })]
      ]
    },
    Oper: {
      kind: 'Operator', keys: ['oper'], keyMsg: 'You must enter an Operator code to continue',
      rows: [
        [f('cmd', 'SDB Operation', { max: 1, lookup: 'MdbOperation', cmd: true, colspan: 3 })],
        [f('oper', 'Operator', { max: 6, key: true, lookup: 'Operator', lookupM: true }), f('admin', 'Administrator', { max: 13, opt: true })],
        [f('nameop', 'Operator Name', { max: 60, textarea: true, rows: 3, cols: 22, opt: true, colspan: 3 })],
        [f('cooper', 'Co-operator', { max: 6, opt: true }), f('mdbm', 'MDB Manager', { max: 6 })],
        [f('addr', 'Address', { max: 50, opt: true, size: 64, colspan: 3 })],
        [f('city', 'City', { max: 15, opt: true }), f('prstat', 'Prov/State', { max: 2, opt: true })],
        [f('zippc', 'Postal/Zip', { max: 10, opt: true })],
        [f('dept', 'Department', { max: 40, opt: true, size: 64, colspan: 3 })],
        [f('namep', 'Contact Name', { max: 40, opt: true, size: 64, colspan: 3 })],
        [f('email', 'Email', { max: 40, opt: true, size: 64, colspan: 3 })],
        [f('phonep', 'Phone', { max: 13, opt: true }), f('faxnum', 'Fax', { max: 13, opt: true })],
        [f('opnote', 'Note Number', { max: 2 })]
      ]
    },
    Note: {
      kind: 'Note', keys: ['oper', 'nonum'], keyMsg: 'You must enter Operator and Note Number to continue',
      rows: [
        [f('cmd', 'SDB Operation', { max: 1, lookup: 'MdbOperation', cmd: true, colspan: 3 })],
        [f('oper', 'Operator', { max: 6, key: true, lookup: 'Operator', lookupM: true }), f('nonum', 'Note Number', { max: 4, key: true })],
        [f('note', 'Note', { max: 60, textarea: true, rows: 3, cols: 20, colspan: 3 })]
      ]
    },
    Traf: {
      kind: 'Traffic', keys: ['trafcode', 'ecode'], keyMsg: 'You must enter Traffic Code and Equipment Code to continue',
      rows: [
        [f('cmd', 'SDB Operation', { max: 1, lookup: 'MdbOperation', cmd: true, colspan: 3 })],
        [f('trafcode', 'Traffic Code', { max: 6, key: true }), f('ecode', 'Equipment Code', { max: 8, key: true, lookup: 'EqptCode', lookupM: true })],
        [f('xreftrcde', 'Xref Traffic', { max: 6, opt: true }), f('xrefeqcde', 'Xref Equipment', { max: 8, opt: true })],
        [f('trdesc', 'Description', { max: 30, colspan: 3 })]
      ]
    },
    Rout: {
      kind: 'Route', keys: ['rcomp', 'routnumb'], keyMsg: 'You must enter Operator and Route Number to continue',
      rows: [
        [f('cmd', 'SDB Operation', { max: 1, lookup: 'MdbOperation', cmd: true, colspan: 3 })],
        [f('rcomp', 'Operator', { max: 6, key: true, lookup: 'Operator', lookupM: true }), f('routnumb', 'Route Number', { max: 8, key: true })],
        [f('rtprov', 'Province', { max: 2 }), f('rtcall', 'Call Sign', { max: 9 })],
        [f('rtname', 'Route Name', { max: 48, textarea: true, rows: 3, cols: 22, colspan: 3 })]
      ]
    },
    Towr: {
      kind: 'Tower', keys: ['twcode'], keyMsg: 'You must enter a Tower Code to continue',
      rows: [
        [f('cmd', 'SDB Operation', { max: 1, lookup: 'MdbOperation', cmd: true, colspan: 3 })],
        [f('twcode', 'Tower Code', { max: 4, key: true, lookup: 'TowerCode' })],
        [f('twdesc', 'Description', { max: 60, textarea: true, rows: 3, cols: 22, colspan: 3 })]
      ]
    },
    Town: {
      kind: 'Tower Note', keys: ['call1', 'atwrno'], keyMsg: 'You must enter Call Sign and Tower Number to continue',
      rows: [
        [f('cmd', 'SDB Operation', { max: 1, lookup: 'MdbOperation', cmd: true, colspan: 3 })],
        [f('call1', 'Site Call Sign', { max: 9, key: true }), f('atwrno', 'Tower Number', { max: 1, key: true })],
        [f('oper', 'Operator', { max: 6, lookup: 'Operator', lookupM: true }), f('twcode', 'Tower Code', { max: 4, opt: true, lookup: 'TowerCode' })],
        [f('twht', 'Tower Height', { max: 6, opt: true, blur: 'f,0.00,999.99,2' }), f('nott', 'Tower Note Number', { max: 4, opt: true })],
        [f('twpa', 'Tower Painted', { radio: [['Y', 'Yes'], ['N', 'No']], opt: true }), f('twli', 'Tower Lighted', { radio: [['Y', 'Yes'], ['N', 'No']], opt: true })],
        [f('tpoint', 'Tower Pointer', { max: 4, opt: true }), f('adate', 'Date Approved', { date3: 'a', opt: true })],
        [f('sdate', 'Date Submitted', { date3: 's', opt: true })]
      ]
    },
    Ctx: {
      kind: 'CTX Pattern', keys: ['tfcr', 'tfci', 'rxeqp'], keyMsg: 'You must enter Desired, Interfering, and Receive Equipment to continue',
      child: 'ctxd', childNew: 'New Separation',
      rows: [
        [f('cmd', 'SDB Operation', { max: 1, lookup: 'MdbOperation', cmd: true, colspan: 3 })],
        [f('tfcr', 'Desired Traffic Type', { max: 6, key: true }), f('tfci', 'Interfering Traffic Type', { max: 6, key: true })],
        [f('rxeqp', 'Receive Equipment', { max: 8, key: true, lookup: 'EqptCode', lookupM: true, colspan: 3 })],
        [f('ctxdesc', 'Description', { max: 40, size: 70, colspan: 3 })],
        [f('rqco', 'Co-Channel Objective', { max: 6, blur: 'f,-200.0,200.0,1' }), f('rqcull', 'Best Objective', { max: 6, blur: 'f,-200.0,200.0,1' })],
        [f('ctxndp', 'Number of Points', { ro: true }), f('rqwrst', 'Worst Objective', { max: 6, blur: 'f,-200.0,200.0,1' })]
      ]
    },
    Plan: {
      kind: 'Plan', keys: ['sband', 'splan'], keyMsg: 'You must enter Band and Plan to continue',
      child: 'plnd', childNew: 'New Frequency',
      rows: [
        [f('cmd', 'SDB Operation', { max: 1, lookup: 'MdbOperation', cmd: true, colspan: 3 })],
        [f('sband', 'Band', { max: 4, key: true, lookup: 'BandCode' }), f('splan', 'Plan', { max: 4, key: true })],
        [f('srsp', 'Standard Radio<br>System Plan', { max: 10 }), f('srspiss', 'Issue Number', { max: 2 })],
        [f('conform', 'Conforming Plan', { radio: [['Y', 'Yes'], ['N', 'No']] }), f('uscan', 'Plan', { radio: [['C', 'Canadian'], ['U', 'US']] })]
      ]
    }
  };

  var CHILD = {
    antd: {
      title: 'Discrimination', key: 'antang', keyMsg: 'You must enter an Antenna Angle to continue',
      cols: [
        { name: 'cmd', label: 'Cmd' }, { name: 'antang', label: 'Angle' },
        { name: 'dcov', label: 'Co-V' }, { name: 'dxpv', label: 'Xp-V' },
        { name: 'dcoh', label: 'Co-H' }, { name: 'dxph', label: 'Xp-H' },
        { name: 'dtilt', label: 'Tilt' }
      ],
      rows: [
        [f('cmd', 'SDB Operation', { max: 1, lookup: 'MdbOperation', cmd: true, colspan: 3 })],
        [f('antang', 'Angle', { max: 6, key: true, blur: 'f,0,359.99,2' })],
        [f('dcov', 'Co-V', { max: 6, blur: 'f,0,99.99,2' }), f('dxpv', 'Xp-V', { max: 6, blur: 'f,0,99.99,2' })],
        [f('dcoh', 'Co-H', { max: 6, blur: 'f,0,99.99,2' }), f('dxph', 'Xp-H', { max: 6, blur: 'f,0,99.99,2' })],
        [f('dtilt', 'Tilt', { max: 6, opt: true, blur: 'f,0,99.99,2' })]
      ]
    },
    ctxd: {
      title: 'Frequency Separation', key: 'fsep', keyMsg: 'You must enter a Frequency Separation to continue',
      cols: [
        { name: 'cmd', label: 'Cmd' }, { name: 'fsep', label: 'Fsep' }, { name: 'rq', label: 'RQ' }
      ],
      rows: [
        [f('cmd', 'SDB Operation', { max: 1, lookup: 'MdbOperation', cmd: true, colspan: 3 })],
        [f('fsep', 'Frequency Separation', { max: 12, key: true, blur: 'f,0.00,400000.00,2' })],
        [f('rq', 'RQ', { max: 6, blur: 'f,-200.0,200.0,1' })]
      ]
    },
    plnd: {
      title: 'Plan Frequency', key: 'spno', keyMsg: 'You must enter a Position Number to continue',
      cols: [
        { name: 'cmd', label: 'Cmd' }, { name: 'spno', label: 'Pos' },
        { name: 'set1', label: 'Set1' }, { name: 's1chid', label: 'Ch1' },
        { name: 'set2', label: 'Set2' }, { name: 's2chid', label: 'Ch2' },
        { name: 'set3', label: 'Set3' }, { name: 's3chid', label: 'Ch3' },
        { name: 'set4', label: 'Set4' }, { name: 's4chid', label: 'Ch4' }
      ],
      rows: [
        [f('cmd', 'SDB Operation', { max: 1, lookup: 'MdbOperation', cmd: true, colspan: 3 })],
        [f('spno', 'Position Number', { max: 3, key: true, blur: 'i,1,255' })],
        [f('set1', 'Set 1', { max: 11, blur: 'f,0,99999999.99,2' }), f('s1chid', 'Ch 1', { max: 4 })],
        [f('set2', 'Set 2', { max: 11, opt: true, blur: 'f,0,99999999.99,2' }), f('s2chid', 'Ch 2', { max: 4, opt: true })],
        [f('set3', 'Set 3', { max: 11, opt: true, blur: 'f,0,99999999.99,2' }), f('s3chid', 'Ch 3', { max: 4, opt: true })],
        [f('set4', 'Set 4', { max: 11, opt: true, blur: 'f,0,99999999.99,2' }), f('s4chid', 'Ch 4', { max: 4, opt: true })]
      ]
    }
  };

  function spec(type) { return SPECS[type] || null; }
  function childSpec(kind) { return CHILD[kind] || null; }
  function kindName(type) {
    if (type === 'Ante') return 'Antenna';
    if (type === 'Band') return 'Band';
    var s = SPECS[type];
    return (s && s.kind) || type;
  }

  global.RemicsSdfTypes = { spec: spec, childSpec: childSpec, kindName: kindName, SPECS: SPECS };
})(window);
