// Guards: PR #872 isolated browser-to-PostgreSQL workflow, never a deployed test target.
import base from './playwright.config.mjs'
if (process.env.UAT_BASE_URL) throw Error('Intake integration must run locally; unset UAT_BASE_URL')
export default {
  ...base, timeout: 600_000, outputDir: 'uat-artifacts/intake-db-results', testDir: './tests/integration', reporter: [['list'], ['json', { outputFile: 'uat-artifacts/intake-integration.json' }]],
  webServer: [base.webServer, { command: 'node tests/fixtures/intake-ui/server.mjs', url: 'http://127.0.0.1:55433/health', reuseExistingServer: false }],
}
