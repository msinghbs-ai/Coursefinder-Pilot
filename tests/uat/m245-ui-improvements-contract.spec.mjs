import fs from'node:fs/promises'
import{execFileSync}from'node:child_process'
import{test,expect}from'@playwright/test'

// M2.4.5 UI-only candidate contract. This deliberately does not waive
// the governed read-contract gaps for Scholarship Provider filtering or
// ranking-observation server ordering.
test.describe('M2.4.5 UI improvements source contract',()=>{
 test('preserves v2.15.71 semantics while applying supported UI behavior',async()=>{
  const[shell,compare,ranking]=await Promise.all([
   fs.readFile('src/mature-main.jsx','utf8'),
   fs.readFile('src/ComparisonWorkspace.jsx','utf8'),
   fs.readFile('src/RankingDatasetViewer.js','utf8'),
  ])

  // No release/version promotion before functional acceptance.
  expect(shell).toContain("const UI_VERSION='2.15.71'")

  // Scholarship list: only server-governed sort keys are surfaced.
  expect(shell).toContain("{key:'provider_name',label:'Provider',width:250,sortKey:'provider'}")
  expect(shell).toContain("{key:'award_value_text',label:'Award',width:180,sortKey:'award'}")
  expect(shell).toContain("{key:'academic_year',label:'Year',width:110,sortKey:'year'}")
  expect(shell).toContain("{key:'application_close_date',label:'Close',width:130,sortKey:'close'}")
  expect(shell).toContain("{key:'mapped_course_count',label:'Mapped Courses',width:120,sortKey:'courses'}")
  expect(shell).toContain("{key:'evidence_count',label:'Evidence',width:100,sortKey:'evidence'}")
  expect(shell).toContain('m-fluid-table')
  expect(shell).toContain('minWidth:`clamp(')

  // QILT/PRISMS use the restored authoritative server ordering contracts.
  expect(shell).toContain("[sort,setSort]=useState(kind==='qilt'?'provider':'geography')")
  expect(shell).toContain("provider_name:'provider'")
  expect(shell).toContain("metric_value:'value'")
  expect(shell).toContain("national_benchmark:'benchmark'")
  expect(shell).toContain("response_count:'responses'")
  expect(shell).toContain("source_geography_name:'geography'")
  expect(shell).toContain("enrolments:'enrolments'")
  expect(shell).toContain("commencements:'commencements'")
  expect(shell).toContain("period_end:'period'")

  // QS/THE match the Open Dataset / Compare interaction model.
  expect(shell).toContain('dataset=qs_wur&year=')
  expect(shell).toContain('dataset=the_wur&year=')
  expect(shell).toMatch(/QS World University Rankings[\s\S]*Open Dataset[\s\S]*Compare/)
  expect(shell).toMatch(/Times Higher Education[\s\S]*Open Dataset[\s\S]*Compare/)
  expect(ranking).not.toContain('min-width:760px')
  expect(ranking).toContain('min-width:clamp(92px,11vw,180px)')
  expect(ranking).toContain('Provider mapping remains distinct from the publisher institution identity')

  // Provider Compare defaults and history remain publisher-specific and evidence-safe.
  expect(compare).toContain("datasets,setDatasets]=useState({qilt:true,prisms:true,qs:true,the:true})")
  expect(compare).toContain('historical editions')
  expect(compare).toContain('No accepted observation for edition')
  expect(compare).toContain('currentEdition={rankingSelection.qs}')
  expect(compare).toContain('currentEdition={rankingSelection.the}')
  expect(compare).toContain('cf-flow-sticky')
  expect(compare).toContain('<ProviderLogo providerId={logoProviderId}')
  expect(compare).toContain('max-height:min(58vh,620px);overflow:auto')
  expect(compare).not.toMatch(/\b(update|delete|publish)\s*\(/i)

  const output=execFileSync('npm',['run','build'],{cwd:process.cwd(),env:process.env,encoding:'utf8',timeout:60000,stdio:['ignore','pipe','pipe']})
  expect(output).toContain('built in')
 })
})
