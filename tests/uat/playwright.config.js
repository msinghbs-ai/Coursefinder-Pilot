import path from 'node:path'
import { fileURLToPath } from 'node:url'
import rootConfig from '../../playwright.config.mjs'

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')

export default {
  ...rootConfig,
  testDir: path.join(repositoryRoot, 'tests/uat'),
  webServer: rootConfig.webServer
    ? { ...rootConfig.webServer, cwd: repositoryRoot }
    : undefined,
}
