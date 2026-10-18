import assert from 'node:assert/strict';

import { decodeBasicHtml } from '../_CANONICAL-SKILLS/impeccable/scripts/live-manual-edit-evidence.mjs';
import { parseSvelteComponentFile } from '../_CANONICAL-SKILLS/impeccable/scripts/live/svelte-component.mjs';
import { detectText } from '../_CANONICAL-SKILLS/impeccable/scripts/detector/engines/regex/detect-text.mjs';

import { isFullPage } from '../_CANONICAL-SKILLS/impeccable/scripts/detector/shared/page.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

assert.equal(decodeBasicHtml('&amp;quot;'), '&quot;');
assert.equal(decodeBasicHtml('&quot;&amp;&lt;&gt;&#39;&apos;'), '"&<>\'\'');

const parsed = parseSvelteComponentFile([
  '<script>const bait = "streamline your";</script \t data-impeccable-test>',
  '<main>safe</main>',
  '<style>.safe { color: red; }</style \n data-impeccable-test>',
].join('\n'));
assert.equal(parsed.markup, '<main>safe</main>');
assert.deepEqual(parsed.cssLines, ['.safe { color: red; }']);

const findings = detectText(
  '<!doctype html><html><body><script>streamline your</script \t bogus><main>plain</main></body></html>',
  'fixture.html',
);
assert.equal(findings.some((finding) => finding.antipattern === 'marketing-buzzword'), false);

assert.equal(isFullPage('<!-- <!doctype html> --><div>fragment</div>'), false);
assert.equal(isFullPage('<!-- comment --><!doctype html><html><body>page</body></html>'), true);

const scriptsRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../_CANONICAL-SKILLS/impeccable/scripts');
const liveBrowser = fs.readFileSync(path.join(scriptsRoot, 'live-browser.js'), 'utf-8');
assert.equal(/\.src\s*=\s*['"]http:\/\/localhost:/.test(liveBrowser), false);

const liveAccept = fs.readFileSync(path.join(scriptsRoot, 'live-accept.mjs'), 'utf-8');
assert.equal(/\.replace\(\/<style\\b\[\^>\]\*>/i.test(liveAccept), false);

console.log('impeccable security regressions PASS');
console.log('IMPECCABLE SECURITY REGRESSIONS: PASS');
