import {defineConfig} from '@playwright/test';

export default defineConfig({
  testDir: './tests/browser',
  fullyParallel: false,
  workers: 1,
  timeout: 60_000,
  use: {
    baseURL: 'http://127.0.0.1:5174',
    viewport: {width: 1440, height: 1080},
    launchOptions: {
      executablePath: process.env.GLASS_VIEWER_CHROME || '/run/current-system/sw/bin/google-chrome',
      // Software rendering only in the isolated test browser. This neither
      // changes the user's Chrome profile nor requires a downloaded browser.
      args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
    },
  },
  webServer: {
    command: 'node node_modules/vite/bin/vite.js --host 127.0.0.1 --port 5174 --strictPort',
    url: 'http://127.0.0.1:5174',
    reuseExistingServer: false,
    timeout: 30_000,
  },
});
