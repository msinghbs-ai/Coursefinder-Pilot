import fs from'node:fs/promises'
import{execFileSync}from'node:child_process'
import{test,expect}from'@playwright/test'

test.describe('M2.4.5 reconciled UI improvements contract',()=>{
 test('preserves accepted UI semantics and uses governed server reads',async()=>{
  const[shell,compare,ranking,api,migration]=await Promise.all([
   fs.readFile('src/mature-main.jsx','utf8'),
   fs.readFile('src/ComparisonWorkspace.jsx','utf8'),
   fs.readFile('src/mature-main.jsx','utf8') /* 7 Oct 2026: RankingDatasetViewer.js was folded into mature-main.jsx */,
   fs.readFile('src/lib/supabase.js','utf8'),
   fs.readFile('supabase/migrations/20260907064251_m245_ui_read_contract_reconciliation.sql','utf8'),
  ])

  // 7 Oct 2026: rewritten to the current screens. The version is pinned in release-manifest.js (its own contract); the scholarship
  // list became Scholarship, Value, Who it is for, Closes (v2.15.171), then one sortable column per fact (v2.15.223); RankingDatasetViewer.js was folded into mature-main.jsx.

  // Scholarship catalogue: bounded Provider filter and authoritative provider_id read.
  expect(shell).toContain("if(type==='scholarship')return <div className=\"m-filter-bar\"")
  expect(shell).toContain('<PagedFilterSelect kind="provider" label="Provider"')
  expect(shell).toContain("if(type==='scholarship'&&filters.provider)a.provider_id=filters.provider")
  expect(shell).toContain("if(['course','scholarship'].includes(type))n.provider=''")
  expect(shell).toContain("limit:10,offset")
  expect(shell).toContain("{key:'sch_name',label:'Scholarship',width:260,sortKey:'scholarship'},{key:'provider_name',label:'Provider',width:190,sortKey:'provider'},{key:'sch_type',label:'Type',width:150,sortKey:'type'},{key:'sch_who',label:'Who it is for',width:200,sortKey:'audience'},{key:'value_label',label:'Value',width:170,sortKey:'award'},{key:'sch_courses',label:'Courses',width:100,sortKey:'courses'},{key:'sch_closes',label:'Closes',width:130,sortKey:'close'}")
  expect(shell).toContain('m-fluid-table')
  expect(shell).toContain('minWidth:`clamp(')

  expect(migration).toContain('security.admin_scholarships_page')
  expect(migration).toContain("v_provider_id uuid:=nullif(p_args->>'provider_id','')::uuid")
  expect(migration).toContain('s.provider_id=v_provider_id')
  expect(migration).toContain('revoke all on function security.admin_scholarships_page(jsonb) from public')
  expect(migration).toContain("if auth.uid() is null then raise exception 'authentication required'")
  expect(migration).toContain('security.current_role_rank()')

  // QILT/PRISMS retain their native source-specific server ordering.
  expect(shell).toContain("[sort,setSort]=useState(kind==='qilt'?'provider':'geography')")
  expect(shell).toContain("provider_name:'provider'")
  expect(shell).toContain("metric_value:'value'")
  expect(shell).toContain("national_benchmark:'benchmark'")
  expect(shell).toContain("response_count:'responses'")
  expect(shell).toContain("source_geography_name:'geography'")
  expect(shell).toContain("enrolments:'enrolments'")
  expect(shell).toContain("commencements:'commencements'")
  expect(shell).toContain("period_end:'period'")

  // QS/THE use server ordering across the full paged ranking dataset.
  expect(api).toContain("sort = 'rank', direction = 'asc'")
  expect(api).toContain('provider_id: providerId || null, country: country || null, state: state || null, link: link || null, sort, direction')
  expect(ranking).toContain("[sort,setSort]=useState('rank'),[direction,setDirection]=useState('asc')")
  expect(ranking).toContain("{sortHead('rank','Rank')}")
  expect(ranking).toContain('Provider mapping and Evidence remain publisher-specific.')
  expect(ranking).not.toContain('min-width:760px')
  expect(migration).toContain("('institution','provider','rank','score','country','status','edition','system')")
  expect(migration).toContain('ranking.observation_provider_links')
  expect(migration).toContain('evidence_artifact_id')
  expect(migration).toContain("'sort',v_sort,'direction',v_dir")

  // Open Dataset / Compare and provider comparison defaults remain publisher-specific.
  expect(shell).toContain("navigate('Statistics & Rankings',{dataset:system,year:selected})")
  expect(shell).toContain("openRanking('qs_wur','qs')")
  expect(shell).toContain("openRanking('the_wur','the')")
  expect(shell).toMatch(/QS World University Rankings[\s\S]*Open Dataset[\s\S]*Compare/)
  expect(shell).toMatch(/Times Higher Education[\s\S]*Open Dataset[\s\S]*Compare/)
  expect(compare).toContain("datasets,setDatasets]=useState({qilt:true,prisms:true,qs:true,the:true})")
  expect(compare).toContain('retained editions')
  expect(compare).toContain('No accepted observation for edition')
  expect(compare).toContain('cf-flow-sticky')
  expect(compare).toContain('<ProviderLogo providerId={logoProviderId}')
  expect(compare).not.toMatch(/\b(update|delete|publish)\s*\(/i)

  const output=execFileSync('npm',['run','build'],{cwd:process.cwd(),env:process.env,encoding:'utf8',timeout:60000,stdio:['ignore','pipe','pipe']})
  expect(output).toContain('built in')
 })
})
