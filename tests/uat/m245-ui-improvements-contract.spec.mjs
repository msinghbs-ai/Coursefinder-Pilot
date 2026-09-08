import fs from'node:fs/promises'
import{execFileSync}from'node:child_process'
import{test,expect}from'@playwright/test'

test.describe('M2.4.5 reconciled UI improvements contract',()=>{
 test('preserves v2.15.71 semantics and uses governed server reads',async()=>{
  const[shell,compare,ranking,api,migration]=await Promise.all([
   fs.readFile('src/mature-main.jsx','utf8'),
   fs.readFile('src/ComparisonWorkspace.jsx','utf8'),
   fs.readFile('src/RankingDatasetViewer.js','utf8'),
   fs.readFile('src/lib/supabase.ts','utf8'),
   fs.readFile('supabase/migrations/20260907064251_m245_ui_read_contract_reconciliation.sql','utf8'),
  ])

  // No release/version promotion before nominated acceptance.
  expect(shell).toContain("const UI_VERSION='2.15.74'")

  // Scholarship catalogue: bounded Provider filter and authoritative provider_id read.
  expect(shell).toContain("if(type==='scholarship')return <div className=\"m-filter-bar\"")
  expect(shell).toContain('<PagedFilterSelect kind="provider" label="Provider"')
  expect(shell).toContain("if(type==='scholarship'&&filters.provider)a.provider_id=filters.provider")
  expect(shell).toContain("if(['course','scholarship'].includes(type))n.provider=''")
  expect(shell).toContain("limit:10,offset")
  expect(shell).toContain("{key:'provider_name',label:'Provider',width:250,sortKey:'provider'}")
  expect(shell).toContain("{key:'scholarship_type',label:'Type',width:170,sortKey:'type'}")
  expect(shell).toContain("{key:'audience',label:'Audience',width:150,sortKey:'audience'}")
  expect(shell).toContain("{key:'award_value_text',label:'Award',width:180,sortKey:'award'}")
  expect(shell).toContain("{key:'publication_status',label:'Publication',width:130,sortKey:'publication'}")
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
  expect(api).toContain('provider_id: providerId || null, sort, direction')
  expect(api).toContain("supabase.rpc('admin_read'")
  expect(ranking).toContain("sort=p.get('sort')||'rank'")
  expect(ranking).toContain('data-sort="${k}"')
  expect(ranking).toContain('setParams({sort:next,direction:')
  expect(ranking).toContain('Provider mapping remains distinct from the publisher institution identity')
  expect(ranking).not.toContain('min-width:760px')
  expect(migration).toContain("('institution','provider','rank','score','country','status','edition','system')")
  expect(migration).toContain('ranking.observation_provider_links')
  expect(migration).toContain('evidence_artifact_id')
  expect(migration).toContain("'sort',v_sort,'direction',v_dir")

  // Open Dataset / Compare and provider comparison defaults remain publisher-specific.
  expect(shell).toContain("navigate('Statistics & Rankings',{dataset:system,year:selected})")
  expect(shell).toContain("openRanking('qs_wur','qs')")
  expect(shell).toContain("openRanking('the_wur','the')")
  expect(shell).toContain("navigate('Statistics & Rankings',{dataset:system,year:e.target.value})")
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
