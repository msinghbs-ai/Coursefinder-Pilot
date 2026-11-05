// Guards: Platform Admin mandate 5 Nov 2026 17:31, Course Catalogue columns: browser-to-PostgreSQL integration, never a deployed target.
// The app is the real Admin UI; the Course catalogue's two RPCs go to isolated PostgreSQL (tests/fixtures/course-catalogue-columns/server.mjs).
if (process.env.UAT_BASE_URL) throw Error('Course Catalogue columns integration must run locally; unset UAT_BASE_URL')
const base = (await import(process.env.CCOL_BASE_CONFIG || './playwright.config.mjs')).default
export default {
  ...base, outputDir: 'uat-artifacts/course-columns-db-results', testDir: './tests/integration', testMatch: /course-columns-postgres\.spec\.mjs/,
  reporter: [['list'], ['json', { outputFile: 'uat-artifacts/course-columns-integration.json' }]],
  webServer: [base.webServer, { command: 'node tests/fixtures/course-catalogue-columns/server.mjs', url: 'http://127.0.0.1:55434/health', reuseExistingServer: false }],
}
