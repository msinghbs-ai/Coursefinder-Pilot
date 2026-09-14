import fs from'node:fs'
import path from'node:path'
import{pathToFileURL}from'node:url'

const root=process.cwd()
const read=p=>fs.readFileSync(path.join(root,p),'utf8')
const fail=msg=>{console.error(`release-contract: ${msg}`);process.exitCode=1}
const manifest=await import(`${pathToFileURL(path.join(root,'src/release-manifest.js')).href}?t=${Date.now()}`)
const{UI_VERSION,PACKAGE_VERSION,RELEASE_STATE,RELEASE,ACCEPTED_RELEASES,RECOVERY_RELEASE}=manifest
const pkg=JSON.parse(read('package.json'))
const changelog=read('CHANGELOG.md')
const history=read('src/pim-version-entry.js')
const overlay=read('src/release-currentness-entry.js')
const shell=read('src/mature-main.jsx')
const html=read('index.html')

if(!/^2\.15\.\d+$/.test(UI_VERSION))fail(`invalid UI_VERSION ${UI_VERSION}`)
if(!['candidate','accepted'].includes(RELEASE_STATE))fail(`invalid RELEASE_STATE ${RELEASE_STATE}`)
if(RELEASE?.version!==UI_VERSION)fail(`RELEASE version ${RELEASE?.version||'missing'} != UI_VERSION ${UI_VERSION}`)
if(RELEASE?.packageVersion!==PACKAGE_VERSION)fail(`RELEASE package ${RELEASE?.packageVersion||'missing'} != PACKAGE_VERSION ${PACKAGE_VERSION}`)
if(pkg.version!==PACKAGE_VERSION)fail(`package.json ${pkg.version} != manifest ${PACKAGE_VERSION}`)
if(!changelog.includes(`## ${PACKAGE_VERSION} —`))fail(`CHANGELOG missing package release ${PACKAGE_VERSION}`)
if(!changelog.includes(`**v${UI_VERSION}**`))fail(`CHANGELOG ${PACKAGE_VERSION} missing visible release v${UI_VERSION}`)
if(!Array.isArray(ACCEPTED_RELEASES)||!ACCEPTED_RELEASES.length)fail('ACCEPTED_RELEASES must contain at least one accepted release')
if(!RECOVERY_RELEASE)fail('RECOVERY_RELEASE is missing')
if(RECOVERY_RELEASE&&ACCEPTED_RELEASES?.[0]!==RECOVERY_RELEASE)fail('RECOVERY_RELEASE must be the first accepted release')
if(RELEASE_STATE==='accepted'){
  if(RECOVERY_RELEASE?.version!==UI_VERSION)fail(`accepted release ${UI_VERSION} must be the recovery release, found ${RECOVERY_RELEASE?.version||'missing'}`)
  if(RECOVERY_RELEASE?.packageVersion!==PACKAGE_VERSION)fail(`accepted recovery package ${RECOVERY_RELEASE?.packageVersion||'missing'} != ${PACKAGE_VERSION}`)
  if(!RECOVERY_RELEASE?.pilotMain)fail('accepted recovery release requires validated pilotMain')
}else{
  if(RECOVERY_RELEASE?.version===UI_VERSION)fail(`candidate ${UI_VERSION} cannot also be the accepted recovery release`)
}
const historyBaseline=history.match(/^const VERSION='([^']+)'/)?.[1]
if(!historyBaseline)fail('legacy release history baseline is missing')
if(!history.includes(`{version:'${historyBaseline}'`))fail(`legacy release history missing its baseline ${historyBaseline}`)
const shellFallback=shell.match(/const UI_VERSION='([^']+)'/)?.[1]
if(!shellFallback)fail('shell safe fallback is missing')
if(!history.includes(`{version:'${shellFallback}'`))fail(`shell safe fallback ${shellFallback} is not retained in release history`)
if(!overlay.includes("import{UI_VERSION as VERSION,RELEASE}from'./release-manifest.js'"))fail('release-currentness overlay must import the canonical manifest')
if(/const VERSION='2\.15\.\d+'/.test(overlay))fail('release-currentness overlay defines a competing current-version literal')
if(/Coursefinder PIM Admin v2\.15\.\d+/.test(html))fail('index.html contains a duplicate current-version literal')
if(!html.includes('<title>Coursefinder PIM Admin</title>'))fail('index.html must keep a version-neutral bootstrap title')
if(!overlay.includes('document.title=`Coursefinder PIM Admin v${VERSION}`'))fail('runtime title is not reconciled from the canonical manifest')
if(process.exitCode)process.exit(process.exitCode)
console.log(`release-contract: PASS ${RELEASE_STATE} v${UI_VERSION} / package ${PACKAGE_VERSION}; recovery v${RECOVERY_RELEASE.version} @ ${RECOVERY_RELEASE.pilotMain}`)
