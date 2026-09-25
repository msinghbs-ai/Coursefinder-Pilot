// UI review capture (P3): full-page screenshots of live screens for design review.
// Not part of UAT; run only by the "UI review screenshots" workflow.
import { defineConfig, devices } from '@playwright/test'
export default defineConfig({
  testDir: '.',
  timeout: 15 * 60_000,
  retries: 0,
  workers: 1,
  reporter: 'line',
  use: {
    ...devices['Desktop Chrome'],
    baseURL: process.env.UAT_BASE_URL,
    viewport: { width: 1440, height: 1000 },
    headless: true,
  },
})
