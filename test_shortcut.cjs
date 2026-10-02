const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(`${__dirname}/Shortcut.js`, 'utf8').replace(/^\.pragma library\s*/, ''), context);
const cases = [
  [['Left Alt', 'Right Shift'], 'grp:alt_shift_toggle'],
  [['Shift', 'Ctrl'], 'grp:ctrl_shift_toggle'],
  [['Right Ctrl', 'Left Alt'], 'grp:ctrl_alt_toggle'],
  [['Left Shift', 'Right Shift'], 'grp:shifts_toggle'],
  [['Left Ctrl', 'Right Ctrl'], 'grp:ctrls_toggle'],
  [['Left Alt', 'Right Alt'], 'grp:alts_toggle'],
  [['Space', 'Left Super'], 'grp:win_space_toggle'],
  [['Space', 'Ctrl'], 'grp:ctrl_space_toggle'],
  [['Caps Lock', 'Alt'], 'grp:alt_caps_toggle'],
  [['Caps Lock'], 'grp:caps_toggle'],
  [['Right Alt'], 'grp:toggle'],
  [['Unsupported key', 'Ctrl'], ''],
  [['Unsupported key (Q)', 'Ctrl'], ''],
  [['Space', 'Alt', 'Shift'], ''],
  [['Alt'], ''], // A generic modifier alone cannot identify its side safely.
  [[], '']
];
for (const [keys, expected] of cases) {
  assert.equal(context.optionFor(keys), expected, keys.join('+'));
  assert.equal(context.optionFor(keys.slice().reverse()), expected);
}
console.log('Shortcut mapping tests passed');
