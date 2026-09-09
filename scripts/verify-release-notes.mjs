import { execFileSync } from 'node:child_process'

const base = process.env.RELEASE_GATE_BASE_SHA || process.argv[2]
const head = process.env.RELEASE_GATE_HEAD_SHA || process.argv[3] || 'HEAD'

if (!base) {
  console.error('Release gate requires RELEASE_GATE_BASE_SHA (or argv[2]).')
  process.exit(2)
}

const gitRaw = (...args) => execFileSync('git', args, { encoding: 'utf8' })
const git = (...args) => gitRaw(...args).trim()
const changed = gitRaw('diff', '--no-renames', '--name-only', '-z', `${base}...${head}`)
  .split('\0')
  .filter(Boolean)

const nonRuntimeRoots = /^(?:tests|scripts|supabase|docs|change-control|node_modules|dist|playwright-report|test-results|uat-artifacts)\//i
const productionModuleExtension = /\.(?:[cm]?[jt]sx?|css|scss|sass|less|styl|stylus|html?)$/i

const isProductionBuildInput = (filePath) => {
  const productionCapableModule = productionModuleExtension.test(filePath)
    && !nonRuntimeRoots.test(filePath)

  return filePath === 'src'
    || filePath.startsWith('src/')
    || filePath === 'index.html'
    || /^vite\.config\.[cm]?[jt]s$/.test(filePath)
    || filePath === 'public'
    || filePath.startsWith('public/')
    || filePath === 'package.json'
    || filePath === 'package-lock.json'
    || productionCapableModule
}

const productionBuildChanged = changed.some(isProductionBuildInput)

if (!productionBuildChanged) {
  console.log('Release gate: no production frontend build-input changes; version/changelog bump not required.')
  process.exit(0)
}

for (const required of ['package.json', 'package-lock.json', 'CHANGELOG.md']) {
  if (!changed.includes(required)) {
    console.error(`Release gate: production frontend build inputs changed but ${required} was not modified.`)
    process.exit(1)
  }
}

const basePackage = JSON.parse(git('show', `${base}:package.json`))
const headPackage = JSON.parse(git('show', `${head}:package.json`))
const headLock = JSON.parse(git('show', `${head}:package-lock.json`))

if (headLock.version !== headPackage.version || headLock.packages?.['']?.version !== headPackage.version) {
  console.error(
    `Release gate: package-lock.json root versions must both equal package.json version ${headPackage.version}.`,
  )
  process.exit(1)
}

const parseSemver = (version) => {
  const match = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/.exec(version)
  if (!match) throw new Error(`Unsupported package version: ${version}`)
  return {
    core: match.slice(1, 4).map(Number),
    prerelease: match[4] ? match[4].split('.') : [],
  }
}

const compareIdentifier = (left, right) => {
  const leftNumeric = /^\d+$/.test(left)
  const rightNumeric = /^\d+$/.test(right)
  if (leftNumeric && rightNumeric) return Number(left) - Number(right)
  if (leftNumeric !== rightNumeric) return leftNumeric ? -1 : 1
  return left === right ? 0 : left < right ? -1 : 1
}

const compareSemver = (left, right) => {
  for (let index = 0; index < 3; index += 1) {
    if (left.core[index] !== right.core[index]) return left.core[index] - right.core[index]
  }

  if (left.prerelease.length === 0 && right.prerelease.length === 0) return 0
  if (left.prerelease.length === 0) return 1
  if (right.prerelease.length === 0) return -1

  const count = Math.max(left.prerelease.length, right.prerelease.length)
  for (let index = 0; index < count; index += 1) {
    if (left.prerelease[index] === undefined) return -1
    if (right.prerelease[index] === undefined) return 1
    const compared = compareIdentifier(left.prerelease[index], right.prerelease[index])
    if (compared !== 0) return compared
  }
  return 0
}

let baseVersion
let headVersion
try {
  baseVersion = parseSemver(basePackage.version)
  headVersion = parseSemver(headPackage.version)
} catch (error) {
  console.error(`Release gate: ${error.message}`)
  process.exit(1)
}

if (compareSemver(headVersion, baseVersion) <= 0) {
  console.error(
    `Release gate: production frontend build inputs changed but package.json version did not increase (${basePackage.version} -> ${headPackage.version}).`,
  )
  process.exit(1)
}

const changelog = gitRaw('show', `${head}:CHANGELOG.md`)
const escapedVersion = headPackage.version.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
const versionHeading = new RegExp(`^## \\[${escapedVersion}\\](?:\\s+-\\s+\\d{4}-\\d{2}-\\d{2})?\\s*$`, 'm')

if (!versionHeading.test(changelog)) {
  console.error(`Release gate: CHANGELOG.md has no "## [${headPackage.version}]" release heading.`)
  process.exit(1)
}

console.log(
  `Release gate: production frontend build-input changes are paired with package/package-lock version ${basePackage.version} -> ${headPackage.version} and a matching changelog entry.`,
)
