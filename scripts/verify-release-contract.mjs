import fs from'node:fs'
import path from'node:path'
import{pathToFileURL}from'node:url'

const root=process.cwd()
const read=p=>fs.readFileSync(path.join(root,p),'utf8')
const fail=msg=>{console.error(`release-contract: ${msg}`);process.exitCode=1}
const manifest=await import(`${pathToFileURL(path.join(root,'src/release-manifest.js')).href}?t=${Date.now()}`)
const{UI_VERSION,PACKAGE_VERSION,PREVIOUS_ACCEPTED_RELEASE}=manifest
const pkg=JSON.parse(read('package.json'))
const changelog=read('CHANGELOG.md')
const history=read('src/pim-version-entry.js')
const overlay=read('src/release-currentness-entry.js')
const shell=read('src/mature-main.jsx')
const html=read('index.html')

if(!/^2\.15\.\d+$/.test(UI_VERSION))fail(`invalid UI_VERSION ${UI_VERSION}`)
if(pkg.version!==PACKAGE_VERSION)fail(`package.json ${pkg.version} != manifest ${PACKAGE_VERSION}`)
if(!changelog.includes(`## ${PACKAGE_VERSION} —`))fail(`CHANGELOG missing package release ${PACKAGE_VERSION}`)
if(!changelog.includes(`**v${UI_VERSION}**`))fail(`CHANGELOG ${PACKAGE_VERSION} missing visible release v${UI_VERSION}`)
if(!history.includes(`{version:'${PREVIOUS_ACCEPTED_RELEASE.version}'`))fail(`retained history missing recovery release ${PREVIOUS_ACCEPTED_RELEASE.version}`)
const historyBaseline=history.match(/^const VERSION='([^']+)'/)?.[1]
if(historyBaseline!==PREVIOUS_ACCEPTED_RELEASE.version)fail(`history baseline ${historyBaseline||'missing'} != previous accepted ${PREVIOUS_ACCEPTED_RELEASE.version}`)
const shellFallback=shell.match(/const UI_VERSION='([^']+)'/)?.[1]
if(shellFallback!==PREVIOUS_ACCEPTED_RELEASE.version)fail(`shell safe fallback ${shellFallback||'missing'} != previous accepted ${PREVIOUS_ACCEPTED_RELEASE.version}`)
if(!overlay.includes("import{UI_VERSION as VERSION,RELEASE}from'./release-manifest.js'"))fail('release-currentness overlay must import the canonical manifest')
if(/const VERSION='2\.15\.\d+'/.test(overlay))fail('release-currentness overlay defines a competing current-version literal')
if(/Coursefinder PIM Admin v2\.15\.\d+/.test(html))fail('index.html contains a duplicate current-version literal')
if(!html.includes('<title>Coursefinder PIM Admin</title>'))fail('index.html must keep a version-neutral bootstrap title')
if(!overlay.includes('document.title=`Coursefinder PIM Admin v${VERSION}`'))fail('runtime title is not reconciled from the canonical manifest')
if(process.exitCode)process.exit(process.exitCode)
console.log(`release-contract: PASS candidate v${UI_VERSION} / package ${PACKAGE_VERSION}; recovery baseline v${PREVIOUS_ACCEPTED_RELEASE.version} @ ${PREVIOUS_ACCEPTED_RELEASE.pilotMain}`)
