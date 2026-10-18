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
const history=read('src/release-history-legacy.js')
const pill=read('src/ReleaseNotes.jsx')
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
const historyBaseline=history.match(/^export const LEGACY_BASELINE='([^']+)'/m)?.[1]
if(!historyBaseline)fail('legacy release history baseline is missing')
if(!history.includes(`{version:'${historyBaseline}'`))fail(`legacy release history missing its baseline ${historyBaseline}`)
// v2.15.291: the post-render patch scripts are retired; React draws the version from the manifest and nothing else holds one.
for(const gone of['pim-version-entry.js','release-currentness-entry.js','StatisticsDatasetEnhancer.js','ranking-dataset-header.js','evidence-acquisition-provenance-entry.js']){
  if(fs.existsSync(path.join(root,'src',gone)))fail(`retired page-patch script src/${gone} is back`)
  if(html.includes(`/src/${gone}`))fail(`index.html loads retired page-patch script ${gone}`)
}
if((html.match(/<script\b/g)||[]).length!==1||!html.includes('<script type="module" src="/src/mature-main.jsx"></script>'))fail('index.html must load only the React entry (src/mature-main.jsx)')
if(/const UI_VERSION='2\.15\.\d+'/.test(shell))fail('mature-main.jsx defines a competing version literal; import UI_VERSION from release-manifest.js')
if(!shell.includes("import{UI_VERSION}from'./release-manifest.js'"))fail('mature-main.jsx must take UI_VERSION from the canonical manifest')
if(!pill.includes("import{UI_VERSION,RELEASE}from'./release-manifest.js'"))fail('ReleaseNotes.jsx must import the canonical manifest')
if(/const UI_VERSION='2\.15\.\d+'/.test(pill))fail('ReleaseNotes.jsx defines a competing current-version literal')
if(/StudySearch PIM Admin v2\.15\.\d+/.test(html))fail('index.html contains a duplicate current-version literal')
if(!html.includes('<title>StudySearch PIM Admin</title>'))fail('index.html must keep a version-neutral bootstrap title')
if(!pill.includes('`StudySearch PIM Admin v${UI_VERSION}`')||!pill.includes('document.title=RELEASE_TITLE'))fail('runtime title is not set from the canonical manifest')
// Decision 209: the in-app Platform guide is reviewed with every release.
const guide=await import(`${pathToFileURL(path.join(root,'src/guide/platformGuide.js')).href}?t=${Date.now()}`)
const nav=await import(`${pathToFileURL(path.join(root,'src/nav-map.js')).href}?t=${Date.now()}`)
if(guide.GUIDE_REVIEWED_FOR!==UI_VERSION)fail(`Platform guide reviewed for ${guide.GUIDE_REVIEWED_FOR}, not ${UI_VERSION}: review src/guide/platformGuide.js for this release, then set GUIDE_REVIEWED_FOR`)
const guideMissing=Object.keys(nav.PAGES).filter(k=>k!=='guide'&&!guide.SCREENS?.[k])
if(guideMissing.length)fail(`Platform guide has no entry for menu page(s): ${guideMissing.join(', ')}`)
if(process.exitCode)process.exit(process.exitCode)
console.log(`release-contract: PASS ${RELEASE_STATE} v${UI_VERSION} / package ${PACKAGE_VERSION}; recovery v${RECOVERY_RELEASE.version} @ ${RECOVERY_RELEASE.pilotMain}`)
