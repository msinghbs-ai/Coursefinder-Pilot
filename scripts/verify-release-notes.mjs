import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const base = process.env.RELEASE_GATE_BASE_SHA || process.argv[2]
const head = process.env.RELEASE_GATE_HEAD_SHA || process.argv[3] || 'HEAD'

if (!base) {
  console.error('Release gate requires RELEASE_GATE_BASE_SHA (or argv[2]).')
  process.exit(2)
}

const git = (...args) => execFileSync('git', args, { encoding: 'utf8' }).trim()
const changed = git('diff', '--name-only', `${base}...${head}`)
  .split('\n')
  .map((value) => value.trim())
  .filter(Boolean)

const sourceChanged = changed.some((path) => path === 'src' || path.startsWith('src/'))

if (!sourceChanged) {
  console.log('Release gate: no src/ changes; version/changelog bump not required.')
  process.exit(0)
}

for (const required of ['package.json', 'CHANGELOG.md']) {
  if (!changed.includes(required)) {
    console.error(`Release gate: src/ changed but ${required} was not modified.`)
    process.exit(1)
  }
}

const basePackage = JSON.parse(git('show', `${base}:package.json`))
const headPackage = JSON.parse(readFileSync('package.json', 'utf8'))

const parseSemver = (version) => {
  const match = /^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$/.exec(version)
  if (!match) throw new Error(`Unsupported package version: ${version}`)
  return match.slice(1, 4).map(Number)
}

const compareSemver = (left, right) => {
  for (let index = 0; index < 3; index += 1) {
    if (left[index] !== right[index]) return left[index] - right[index]
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
    `Release gate: src/ changed but package.json version did not increase (${basePackage.version} -> ${headPackage.version}).`,
  )
  process.exit(1)
}

const changelog = readFileSync('CHANGELOG.md', 'utf8')
const escapedVersion = headPackage.version.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
const versionHeading = new RegExp(`^## \\[${escapedVersion}\\](?:\\s+-\\s+\\d{4}-\\d{2}-\\d{2})?\\s*$`, 'm')

if (!versionHeading.test(changelog)) {
  console.error(`Release gate: CHANGELOG.md has no "## [${headPackage.version}]" release heading.`)
  process.exit(1)
}

console.log(
  `Release gate: src/ changes are paired with package version ${basePackage.version} -> ${headPackage.version} and a matching changelog entry.`,
)
