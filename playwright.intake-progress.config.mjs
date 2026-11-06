// Guards: Platform Admin decision 5 Nov 2026 16:36 §8: the Automation Progress browser-to-PostgreSQL track, isolated, never a deployed target.
import base from './playwright.config.mjs'
if (process.env.UAT_BASE_URL) throw Error('Automation Progress integration must run locally; unset UAT_BASE_URL')
export default {
  ...base, outputDir: 'uat-artifacts/intake-progress-results', testDir: './tests/integration-progress',
  reporter: [['list'], ['json', { outputFile: 'uat-artifacts/intake-progress-integration.json' }]],
  webServer: [base.webServer, { command: 'node tests/fixtures/intake-progress/server.mjs', url: 'http://127.0.0.1:55443/health', reuseExistingServer: false }],
}
