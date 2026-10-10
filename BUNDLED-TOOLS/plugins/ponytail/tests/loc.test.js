// Regression guard for the LOC grader's comment handling (benchmarks/loc.js).
const test = require('node:test');
const assert = require('node:assert/strict');
const loc = require('../benchmarks/loc.js');

const score = (src) => loc(src).score;

// /* ... */ block comments must not count as code, whether or not the
// continuation lines are *-aligned (the old filter only caught JSDoc style).
const cases = [
  ['plain block comment not counted', '```js\nfunction f() {\n  /* explain\n     the rest */\n  return 1;\n}\n```', 3],
  ['jsdoc block comment not counted', '```js\nfunction g() {\n  /*\n   * explain\n   */\n  return 2;\n}\n```', 3],
  ['inline block comment keeps its code line', '```js\nconst x = 1; /* note */\nconst y = 2;\n```', 2],
  ['line comments still stripped', '```js\n// header\nconst x = 1;\n```', 1],
  ['plain code unchanged', '```js\nconst a = 1;\nconst b = 2;\n```', 2],
  ['CRLF fences parsed correctly (#339)', '```js\r\nconst a = 1;\r\nconst b = 2;\r\n```', 2],
];
for (const [name, src, want] of cases) test(name, () => assert.equal(score(src), want));
