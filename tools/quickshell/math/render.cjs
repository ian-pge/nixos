const readline = require('node:readline');
const MathJax = require('mathjax');

async function main() {
  await MathJax.init({
    loader: {load: ['input/tex-base', '[tex]/ams', 'output/svg', 'adaptors/liteDOM']},
    tex: {packages: ['base', 'ams'], maxBuffer: 8192, maxMacros: 1000,
      formatError: (_jax, error) => { throw error; }},
    // Inline line breaking produces several sibling SVGs in MathJax 4.
    // Qt embeds one image per formula, so keep the whole expression together.
    svg: {fontCache: 'none', linebreaks: {inline: false}},
    startup: {typeset: false}
  });
  const adaptor = MathJax.startup.adaptor;
  for await (const line of readline.createInterface({input: process.stdin})) {
    let request;
    try {
      request = JSON.parse(line);
      const tex = Buffer.from(request.encoded, 'base64').toString('utf8');
      if (!tex.trim() || tex.length > 4096 || !/^#[0-9a-f]{6}$/i.test(request.color)) throw Error('Invalid formula');
      // Reset equation counters between independent expressions.
      MathJax.texReset();
      const node = await MathJax.tex2svgPromise(tex, {display: !!request.display, em: 20, ex: 10});
      const images = adaptor.childNodes(node).filter(child => adaptor.kind(child) === 'svg');
      if (images.length !== 1) throw Error('Expected one complete formula image');
      const svg = images[0];
      const box = adaptor.getAttribute(svg, 'viewBox').split(/\s+/).map(Number);
      const width = Math.ceil(box[2] / 1000 * 20), height = Math.ceil(box[3] / 1000 * 20);
      if (!width || !height || width > 4000 || height > 2000) throw Error('Formula too large');
      adaptor.setAttribute(svg, 'width', String(width));
      adaptor.setAttribute(svg, 'height', String(height));
      let source = adaptor.serializeXML(svg).replaceAll('currentColor', request.color);
      if (source.length > 512000 || /<(?:image|script|foreignObject)\b|(?:href|src)=/i.test(source)) throw Error('Unsupported formula resource');
      process.stdout.write(JSON.stringify({id: request.id, svg: 'data:image/svg+xml;base64,' + Buffer.from(source).toString('base64'), width, height}) + '\n');
    } catch (_) {
      process.stdout.write(JSON.stringify({id: request?.id, error: 'Could not render formula'}) + '\n');
    }
  }
  MathJax.done();
}
main().catch(() => { process.stderr.write('Math renderer failed\n'); process.exitCode = 1; });
