// Guards: Provider description autonomy mandate (4 November 2026), isolated PostgreSQL browser acceptance.
import base from './playwright.config.mjs'

if (process.env.UAT_BASE_URL) throw new Error('Provider description integration requires the isolated local environment; unset UAT_BASE_URL')

export default {
  ...base,
  testDir: './tests/integration-provider-description', // own folder: playwright.intake.config.mjs collects every spec in tests/integration
  testMatch: 'provider-description-postgres.spec.mjs',
  outputDir: 'uat-artifacts/provider-description-db-results',
  reporter: [['list'], ['json', { outputFile: 'uat-artifacts/provider-description-integration.json' }]],
  webServer: [base.webServer, {
    command: 'node tests/fixtures/provider-description-autonomy/server.mjs',
    url: 'http://127.0.0.1:55435/health',
    reuseExistingServer: false,
    timeout: 30_000,
    stdout: 'pipe', // the transport logs every request and socket error; a failed run then shows them in the job log
  }],
}
