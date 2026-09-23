import {defineConfig} from 'vite';
import {fileURLToPath} from 'node:url';
import {readFileSync} from 'node:fs';
import {checkShader} from './scripts/check-shader.mjs';

export default defineConfig({
  // Serve only the viewer. The GLSL is checked by Node, never exposed through
  // a broad filesystem allow-list or a CDN dependency.
  server: {host: '127.0.0.1', port: 5173, strictPort: true, fs: {strict: true, allow: ['.']}},
  preview: {host: '127.0.0.1', port: 5173, strictPort: true},
  plugins: [{
    name: 'check-glass-profile',
    buildStart() { checkShader(); },
    configureServer(server) {
      const manifests = ['pebble','cushion'].map(name=>new URL('../'+name+'-source.json',import.meta.url));
      const watched = new Set([
        fileURLToPath(new URL('../shaders/previous.frag', import.meta.url)),
        ...manifests.map(fileURLToPath),
        ...manifests.flatMap(manifest=>Object.keys(JSON.parse(readFileSync(manifest, 'utf8')).sources))
          .map(file => fileURLToPath(new URL('../' + file, import.meta.url))),
      ]);
      server.watcher.add([...watched]);
      server.watcher.on('change', file => {
        if (!watched.has(file)) return;
        try { checkShader(); server.ws.send({type: 'full-reload'}); }
        catch (error) { server.ws.send({type: 'error', err: {message: String(error), stack: '', plugin: 'check-glass-profile'}}); }
      });
    },
  }],
});
