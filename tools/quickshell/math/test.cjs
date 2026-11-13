const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const {test} = require('node:test');
test('renders local SVG math, rejects resources, and recovers from invalid TeX', () => {
  const formulas = ['(A-B)^2=A^2-2AB+B^2', '\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}',
    '\\begin{pmatrix}a&b\\\\c&d\\end{pmatrix}', '\\sum_{i=1}^n i=\\frac{n(n+1)}2',
    '\\href{https://example.test/tracking}{x}', '\\frac{', 'x_1+x_2'];
  const input = formulas.map((tex, id) => JSON.stringify({id, encoded: Buffer.from(tex).toString('base64'), display: true, color: '#cad3f5'})).join('\n') + '\n';
  const process = spawnSync(global.process.execPath, [__dirname + '/render.cjs'], {input, encoding: 'utf8', timeout: 10000});
  assert.equal(process.status, 0, process.stderr);
  const results = process.stdout.trim().split('\n').map(line => JSON.parse(line));
  assert.equal(results.length, formulas.length);
  for (const i of [0, 1, 2, 3, 6]) {
    assert.equal(results[i].error, undefined);
    assert.ok(results[i].width > 0 && results[i].height > 0);
    const svg = Buffer.from(results[i].svg.split(',')[1], 'base64').toString();
    assert.match(svg, /<svg/); assert.match(svg, /<path/); assert.match(svg, /#cad3f5/);
    assert.doesNotMatch(svg, /<(?:image|script|foreignObject)\b|(?:href|src)=/i);
  }
  assert.ok(results[1].height > results[0].height);
  assert.ok(results[4].error); assert.ok(results[5].error);
});

test('inline identities and calculations retain every term', () => {
  const formulas = ['(a + b)^2 = a^2 + 2ab + b^2', '(a - b)^2 = a^2 - 2ab + b^2',
    '(a + b)(a - b) = a^2 - b^2', '102 \\times 98', 'a = 100',
    '102 \\times 98 = (100 + 2)(100 - 2) = 100^2 - 2^2 = 10\\,000 - 4 = 9\\,996'];
  const requests = formulas.flatMap((tex, id) => [false, true].map(display => ({id: id * 2 + Number(display),
    encoded: Buffer.from(tex).toString('base64'), display, color: '#cad3f5'})));
  const process = spawnSync(global.process.execPath, [__dirname + '/render.cjs'], {
    input: requests.map(request => JSON.stringify(request)).join('\n') + '\n', encoding: 'utf8', timeout: 10000});
  assert.equal(process.status, 0, process.stderr);
  const results = process.stdout.trim().split('\n').map(line => JSON.parse(line));
  assert.equal(results.length, requests.length);
  for (let i = 0; i < results.length; i += 2) {
    const inline = results[i], display = results[i + 1];
    assert.equal(inline.error, undefined); assert.equal(display.error, undefined);
    const glyphs = result => [...Buffer.from(result.svg.split(',')[1], 'base64').toString().matchAll(/<path[^>]* d="([^"]+)"/g)].map(match => match[1]);
    assert.ok(glyphs(display).length > 3);
    assert.deepEqual(glyphs(inline), glyphs(display), 'Inline rendering lost part of: ' + formulas[i / 2]);
    assert.ok(inline.width >= display.width * 0.95, 'Inline formula was truncated');
  }
});
