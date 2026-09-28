'use strict';
// CodeQL #228: exercise the actual exported helper in a bounded child process.
const assert = require('node:assert/strict');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..', 'BUNDLED-TOOLS', 'plugins', 'ponytail');

if (process.argv.includes('--worker')) {
  const { isPonytailHook } = require(path.join(root, 'scripts', 'cursor-hooks.js'));
  assert.equal(isPonytailHook({ command: 'ponytail-'.repeat(100000) + '!' }), false);
  assert.equal(isPonytailHook({ command: 'node "/hooks/ponytail-mode-tracker.js"' }), true);
  assert.equal(isPonytailHook({ command: 'node "C:\\hooks\\ponytail-toggle.js"' }), true);
  assert.equal(isPonytailHook({ command: 'node "/hooks/personal-ponytail-toggle.js"' }), false);
  assert.equal(isPonytailHook({ command: 'personal-hook.cmd' }), false);
  console.log('PONYTAIL CURSOR REGRESSION: PASS');
} else {
  const result = spawnSync(process.execPath, [__filename, '--worker'], {
    encoding: 'utf8', timeout: 3000,
  });
  assert.equal(result.status, 0, String(result.error || result.stderr));
  assert.match(result.stdout, /PONYTAIL CURSOR REGRESSION: PASS/);
  process.stdout.write(result.stdout);
}
