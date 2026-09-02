import React,{useEffect,useMemo,useRef,useState}from'react'
import{createRoot}from'react-dom/client'
import{
  Activity,AlertTriangle,ArrowDown,ArrowUp,ArrowLeftRight,BarChart3,BookOpen,Building2,CheckCircle2,ChevronDown,
  CircleGauge,ClipboardCheck,Database,FileCheck2,Filter,GraduationCap,History,LayoutDashboard,
  ListChecks,LogOut,Menu,RefreshCw,Search,SearchCheck,Settings2,SlidersHorizontal,Sparkles,
  Tags,UsersRound,Workflow,X,Zap,MapPin,Layers3,Clock3,PanelLeftClose,PanelLeftOpen,ExternalLink
}from'lucide-react'
import{adminRead,api,supabase}from'./lib/supabase'
import RegulatorySettings from'./RegulatorySettings'
import EvidenceWorkspace from'./EvidenceWorkspace'
import CourseDetailPolish from'./CourseDetailPolish'
import ContextualInsights from'./ContextualInsights'
import ComparisonWorkspace from'./ComparisonWorkspace'
import Layer4Intervention from'./Layer4Intervention'
import{Layer1Operations,Layer1SourceSettings}from'./layer1-operations-entry'
import{Workspace as Layer2Workspace}from'./layer2-operations-entry'
import{Layer3 as Layer3Workspace,Layer4 as Layer4Workspace,Links as ImportantLinksWorkspace,Dates as ImportantDatesWorkspace,Refresh as RefreshWorkspace,Onboarding as OnboardingWorkspace}from'./m2-3-intelligence-entry'
import{Console as Layer2SourceConfig}from'./layer2-platform-entry'
import{Console as Layer2ProviderConfig}from'./layer2-provider-entry'
import{ScholarshipSelectionWorkspace}from'./scholarship-selection-entry'
import PlatformMaturity from'./platform-maturity-entry'
import{JobsWorkspace,SourcesWorkspace}from'./pipeline-ops-entry'
import'./styles.css'
import'./mature.css'

const UI_VERSION='2.15.26'
const PAGE_SIZE=50
const STATUS_OPTIONS=['active','inactive','suspended','retired','unknown'].map(x=>({value:x,label:humanise(x)}))
const PUBLICATION_OPTIONS=['published','unpublished','draft','review','archived'].map(x=>({value:x,label:humanise(x)}))

const NAV=[
  ['Overview',[
    item('Dashboard',LayoutDashboard,1),
  ]],
  ['Catalogue',[
    item('Providers',Building2,1),item('Courses',GraduationCap,1),item('Campuses',MapPin,1),item('Scholarships',Sparkles,1),
  ]],
  ['Statistics & Insights',[
    item('Statistics & Rankings',BarChart3,1),item('Compare',ArrowLeftRight,1),
  ]],
  ['Data Operations',[
    item('Layer 1 — Authority',Database,4),item('Layer 2 — Enrichment',Activity,4),item('Layer 3 — AI Interpretation',Sparkles,3),item('Layer 4 — Human Resolution',ListChecks,3),item('Evidence',BookOpen,3),item('Jobs',Workflow,4),
  ]],
  ['Quality & Review',[
    item('Completeness',CheckCircle2,1),item('Review Queue',ListChecks,3),
  ]],
  ['Administration',[
    item('Administration',Settings2,4),
  ]],
]

const PAGE_META={
  Dashboard:['Operational overview','Catalogue health, pipeline attention and recent activity.'],
  Providers:['Providers','Governed provider catalogue with geographic and lifecycle filters.'],
  Courses:['Courses','Decision-grade course catalogue with authoritative identity and enrichment signals.'],
  Campuses:['Campuses','Campus geography and Provider relationships without synthetic identity.'],
  Scholarships:['Scholarships','Relational scholarship catalogue and publication state.'],
  'Statistics & Rankings':['Statistics & Rankings','Coverage, years, observations and provenance for QILT, PRISMS, QS and THE.'],
  'Outcomes (QILT)':['Outcomes (QILT)','Structured provider outcomes enrichment.'],
  'Student Flow (PRISMS)':['Student Flow (PRISMS)','Time-scoped international student-flow observations.'],
  Compare:['Compare providers & courses','Choose entities, datasets and aligned periods for a governed comparison.'],
  Completeness:['Completeness & readiness','Operational presence signals; not truth, approval or Search admission.'],
  Evidence:['Evidence & provenance','Source snapshots, evidence artifacts and canonical consequences.'],
  'Review Queue':['Review Queue','Human-resolution workload and exception state.'],
  'Layer 1 — Authority':['Layer 1 — Authority','Authoritative source health, regulatory ingestion progress, exceptions and controlled run actions.'],
  'Layer 2 — Enrichment':['Layer 2 — Enrichment','Scoped enrichment waves, governed acquisition routes, Evidence and deterministic fall-out.'],
  'Layer 3 — AI Interpretation':['Layer 3 — AI Interpretation','Evidence-bound AI interpretation, qualified route health, usage and recent outcomes.'],
  'Layer 4 — Human Resolution':['Layer 4 — Human Resolution','Human resolution queue, effective-value decisions, audit and reversibility.'],
  'Important Links':['Important Links','Governed operational and authority link registry.'],
  'Important Dates':['Important Dates','Sourced regulatory and operational dates.'],
  Administration:['Administration','Central PIM, source, scheduling, acquisition and platform configuration.'],
  'Refresh & Scheduling':['Refresh & Scheduling','Targeted refresh policies, queues and downstream signals.'],
  Onboarding:['Onboarding','Governed source/country onboarding lifecycle.'],
  Jobs:['Jobs','Pipeline execution history and operational status.'],
  Sources:['Sources','Governed regulatory and enrichment source inventory.'],
  Attributes:['PIM Configuration','Attribute families, groups, options and completeness profiles.'],
  Settings:['Platform Settings','Privileged ingestion and Pilot operational controls.'],
}

function item(label,Icon,min){return{label,Icon,min,slug:slug(label)}}
function slug(v){return String(v).toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'')}
const HIDDEN_ROUTES=[item('Outcomes (QILT)',Activity,1),item('Student Flow (PRISMS)',CircleGauge,1),item('Sources',Database,4),item('Attributes',Tags,5),item('Settings',Settings2,6),item('Refresh & Scheduling',RefreshCw,3),item('Onboarding',Workflow,3)]
function routeFromHash(){const raw=location.hash.replace(/^#/,'');const[route,query='']=raw.split('?');const aliases={'layer-1-regulatory':'Layer 1 — Authority','layer-1-operations':'Layer 1 — Authority','layer-2-operations':'Layer 2 — Enrichment','layer-3-ai':'Layer 3 — AI Interpretation','layer-4-review':'Layer 4 — Human Resolution'};if(aliases[route])return{page:aliases[route],params:new URLSearchParams(query)};for(const[,items]of NAV)for(const i of items)if(i.slug===route)return{page:i.label,params:new URLSearchParams(query)};for(const i of HIDDEN_ROUTES)if(i.slug===route)return{page:i.label,params:new URLSearchParams(query)};return{page:'Dashboard',params:new URLSearchParams()}}

function App(){
  const[session,setSession]=useState(null),[booting,setBooting]=useState(true),[context,setContext]=useState(null)
  const initialRoute=routeFromHash()
  const[page,setPage]=useState(initialRoute.page),[routeParams,setRouteParams]=useState(initialRoute.params),[error,setError]=useState(''),[navOpen,setNavOpen]=useState(false),[collapsed,setCollapsed]=useState(false)
  const mainRef=useRef(null)
  useEffect(()=>{
    supabase.auth.getSession().then(({data})=>{setSession(data.session??null);setBooting(false)})
    const{data}=supabase.auth.onAuthStateChange((_event,next)=>setSession(next));return()=>data.subscription.unsubscribe()
  },[])
  useEffect(()=>{if(!session){setContext(null);return}api.context().then(setContext).catch(e=>setError(e.message))},[session])
  useEffect(()=>{const h=()=>{const r=routeFromHash();setPage(r.page);setRouteParams(r.params)};addEventListener('hashchange',h);return()=>removeEventListener('hashchange',h)},[])
  function go(label,params={}){const target=slug(label),q=new URLSearchParams(Object.entries(params||{}).filter(([,v])=>v!==''&&v!=null)).toString(),next=`#${target}${q?`?${q}`:''}`;if(location.hash!==next)location.hash=next;else{setPage(label);setRouteParams(new URLSearchParams(q))}setNavOpen(false);requestAnimationFrame(()=>{if(mainRef.current)mainRef.current.scrollTop=0})}
  if(booting)return <div className="m-boot"><div className="m-loader"/><span>Loading Coursefinder Admin…</span></div>
  if(!session)return <Login onError={setError} error={error}/>
  const rank=Number(context?.role_rank||0)
  const[title,subtitle]=PAGE_META[page]??[page,'Governed CourseFinder administration.']
  return <div className={`m-shell ${collapsed?'is-collapsed':''}`}>
    <aside className={`m-sidebar ${navOpen?'is-open':''}`}>
      <div className="m-brand-row">
        <button className="m-brand" onClick={()=>go('Dashboard')} aria-label="Dashboard"><span className="m-brand-mark">CF</span><span className="m-brand-copy"><strong>Coursefinder</strong><small>PIM Admin v{UI_VERSION}</small></span></button>
        <button className="m-sidebar-collapse" onClick={()=>setCollapsed(x=>!x)} title={collapsed?'Expand navigation':'Collapse navigation'}>{collapsed?<PanelLeftOpen size={17}/>:<PanelLeftClose size={17}/>}</button>
      </div>
      <div className="m-nav-scroll"><nav className="m-nav">{NAV.map(([group,items])=>{const allowed=items.filter(i=>rank>=i.min);if(!allowed.length)return null;return <div className="m-nav-group" key={group}><div className="m-nav-label">{group}</div>{allowed.map(({label,Icon})=><button key={label} title={collapsed?label:undefined} className={`m-nav-item ${page===label?'active':''}`} onClick={()=>go(label)}><Icon size={17}/><span>{label}</span></button>)}</div>})}</nav></div>
      <div className="m-account">
        <div className="m-avatar">{(session.user.email?.[0]||'U').toUpperCase()}</div>
        <div className="m-account-copy"><strong>{humanise(context?.role||'Authorised user')}</strong><small>{session.user.email}</small></div>
        <button className="m-icon-button" title="Sign out" onClick={()=>supabase.auth.signOut()}><LogOut size={17}/></button>
      </div>
    </aside>
    {navOpen&&<button className="m-backdrop" onClick={()=>setNavOpen(false)} aria-label="Close navigation"/>}
    <main className="m-main" ref={mainRef}>
      <header className="m-topbar">
        <div className="m-title-wrap"><button className="m-mobile-menu" onClick={()=>setNavOpen(true)}><Menu size={20}/></button><div><div className="m-eyebrow">Canonical governance · governed browser RPC</div><h1>{title}</h1><p>{subtitle}</p></div></div>
        <div className="m-topbar-actions"><span className="m-release-pill"><span className="m-live-dot"/>v{UI_VERSION}</span><span className="m-role-pill">{humanise(context?.role||'Loading')}</span></div>
      </header>
      {error&&<div className="m-alert"><AlertTriangle size={16}/><span>{error}</span><button onClick={()=>setError('')}><X size={15}/></button></div>}
      <Page page={page} routeParams={routeParams} rank={rank} onError={setError} navigate={go}/>
    </main>
  </div>
}

function Login({error,onError}){const[email,setEmail]=useState(''),[password,setPassword]=useState(''),[busy,setBusy]=useState(false);async function submit(e){e.preventDefault();setBusy(true);onError('');const{error:x}=await supabase.auth.signInWithPassword({email,password});if(x)onError(x.message);setBusy(false)}return <div className="m-login"><form className="m-login-card" onSubmit={submit}><div className="m-login-brand"><span className="m-brand-mark large">CF</span><div><strong>Coursefinder Admin</strong><small>Governed operational workspace</small></div></div><div className="m-login-copy"><h1>Sign in</h1><p>Authorised staff access only. Canonical catalogue, provenance and pipeline operations.</p></div>{error&&<div className="m-alert compact"><AlertTriangle size={15}/><span>{error}</span></div>}<label>Email<input type="email" value={email} onChange={e=>setEmail(e.target.value)} required/></label><label>Password<input type="password" value={password} onChange={e=>setPassword(e.target.value)} required/></label><button className="m-primary" disabled={busy}>{busy?'Signing in…':'Sign in'}</button><small className="m-login-version">PIM Admin v{UI_VERSION}</small></form></div>}

function Page({page,routeParams,rank,onError,navigate}){
  const focusId=routeParams?.get?.('id')||''
  if(page==='Dashboard')return <Dashboard onError={onError} navigate={navigate}/>
  if(page==='Providers')return <Catalogue type="provider" onError={onError} navigate={navigate} initialId={focusId}/>
  if(page==='Courses')return <Catalogue type="course" onError={onError} navigate={navigate} initialId={focusId}/>
  if(page==='Campuses')return <Catalogue type="campus" onError={onError} navigate={navigate} initialId={focusId}/>
  if(page==='Scholarships')return <ScholarshipWorkspace rank={rank} onError={onError} navigate={navigate} initialId={focusId}/>
  if(page==='Completeness')return <Completeness onError={onError} navigate={navigate}/>
  if(page==='Statistics & Rankings')return <StatisticsRankings onError={onError} navigate={navigate} rank={rank}/>
  if(page==='Outcomes (QILT)')return <Qilt onError={onError}/>
  if(page==='Student Flow (PRISMS)')return <Prisms onError={onError}/>
  if(page==='Compare')return <ComparisonWorkspace routeParams={routeParams} navigate={navigate} onError={onError}/>
  if(page==='Evidence'&&rank>=3)return <EvidenceWorkspace onError={onError} navigate={navigate} routeParams={routeParams}/>
  if(page==='Layer 1 — Authority'&&rank>=4)return <Layer1Operations embedded/>
  if(page==='Layer 2 — Enrichment'&&rank>=4)return <Layer2Workspace rank={rank} embedded/>
  if(page==='Layer 3 — AI Interpretation'&&rank>=3)return <div className="m-page-stack"><Layer3Workspace rank={rank} onError={e=>onError(e?.message||String(e))}/></div>
  if(page==='Layer 4 — Human Resolution'&&rank>=3)return <div className="m-page-stack"><Layer4Workspace onError={e=>onError(e?.message||String(e))}/></div>
  if(page==='Important Links'&&rank>=3)return <div className="m-page-stack"><ImportantLinksWorkspace rank={rank} onError={e=>onError(e?.message||String(e))}/></div>
  if(page==='Important Dates'&&rank>=3)return <div className="m-page-stack"><ImportantDatesWorkspace rank={rank} onError={e=>onError(e?.message||String(e))}/></div>
  if(page==='Administration'&&rank>=4)return <AdministrationHome rank={rank} navigate={navigate} routeParams={routeParams} onError={onError}/>
  if(page==='Refresh & Scheduling'&&rank>=3)return <div className="m-page-stack"><RefreshWorkspace onError={e=>onError(e?.message||String(e))}/></div>
  if(page==='Onboarding'&&rank>=3)return <div className="m-page-stack"><OnboardingWorkspace rank={rank} onError={e=>onError(e?.message||String(e))}/></div>
  if(page==='Review Queue'&&rank>=3)return <OperationalList operation="reviews_page" title="Human resolution queue" onError={onError}/>
  if(page==='Jobs'&&rank>=4)return <JobsWorkspace/>
  if(page==='Sources'&&rank>=4)return <SourcesWorkspace/>
  if(page==='Attributes'&&rank>=5)return <Attributes onError={onError}/>
  if(page==='Settings'&&rank>=6)return <div className="m-legacy-host"><RegulatorySettings onError={onError}/></div>
  return <EmptyState icon={AlertTriangle} title="Not authorised" text="Your assigned CourseFinder role does not permit this workspace."/>
}


function StatisticsRankings({onError,navigate,rank}){
 const[qilt,setQilt]=useState(null),[prisms,setPrisms]=useState(null),[ranking,setRanking]=useState(null),[busy,setBusy]=useState(true)
 useEffect(()=>{let live=true;setBusy(true);Promise.all([
  api.qiltPage({limit:1,offset:0,sort:'year',direction:'desc'}).catch(e=>({error:e})),
  api.prismsPage({limit:1,offset:0,sort:'period',direction:'desc'}).catch(e=>({error:e})),
  api.rankingSummary().catch(e=>({error:e}))
 ]).then(([q,p,r])=>{if(!live)return;if(q?.error)onError?.(q.error.message);else setQilt(q);if(p?.error)onError?.(p.error.message);else setPrisms(p);if(r?.error)onError?.(r.error.message);else setRanking(r)}).finally(()=>live&&setBusy(false));return()=>{live=false}},[])
 const q=qilt?.items?.[0]||qilt?.rows?.[0]||null,p=prisms?.items?.[0]||prisms?.rows?.[0]||null
 const qYear=q?[q.collection_year_from,q.collection_year_to].filter(Boolean).join('–'):'—'
 const pPeriod=p?[p.period_start,p.period_end].filter(Boolean).map(x=>String(x).slice(0,10)).join(' → '):'—'
 const systems=ranking?.systems||[],qs=systems.find(x=>x.code==='qs_wur'),the=systems.find(x=>x.code==='the_wur')
 return <div className="m-page-stack">
  <section className="m-panel">
   <PanelTitle icon={BarChart3} title="Statistics & Rankings" subtitle="One verification workspace for contextual statistics, ranking editions, coverage and provenance."/>
   <div className="m-stats-grid">
    <article className="m-stats-card"><span>QILT</span><strong>{busy?'…':Number(qilt?.total||0).toLocaleString()}</strong><small>observations · latest period {qYear}</small><div><button onClick={()=>navigate('Outcomes (QILT)')}>Open dataset</button><button onClick={()=>navigate('Compare',{type:'provider'})}>Compare</button></div></article>
    <article className="m-stats-card"><span>PRISMS</span><strong>{busy?'…':Number(prisms?.total||0).toLocaleString()}</strong><small>observations · latest period {pPeriod}</small><div><button onClick={()=>navigate('Student Flow (PRISMS)')}>Open dataset</button><button onClick={()=>navigate('Compare',{type:'provider'})}>Compare</button></div></article>
    <article className={`m-stats-card ${qs?.accepted_editions?'':'pending'}`}><span>QS World University Rankings</span><strong>{qs?.latest_edition||'2026 / 2027'}</strong><small>{qs?.accepted_editions?`${Number(qs.observations||0).toLocaleString()} observations · ${Number(qs.mapped_observations||0).toLocaleString()} mapped`:'Schema ready · no accepted edition ingested yet.'}</small><div><button disabled={!qs?.accepted_editions} onClick={()=>navigate('Statistics & Rankings')}>{qs?.accepted_editions?'View coverage':'Awaiting ingestion'}</button></div></article>
    <article className={`m-stats-card ${the?.accepted_editions?'':'pending'}`}><span>Times Higher Education</span><strong>{the?.latest_edition||'2026'}</strong><small>{the?.accepted_editions?`${Number(the.observations||0).toLocaleString()} observations · ${Number(the.mapped_observations||0).toLocaleString()} mapped`:'Schema ready · no accepted edition ingested yet.'}</small><div><button disabled={!the?.accepted_editions} onClick={()=>navigate('Statistics & Rankings')}>{the?.accepted_editions?'View coverage':'Awaiting ingestion'}</button></div></article>
   </div>
  </section>
  <section className="m-panel">
   <div className="m-stats-section-head"><div><h3>Coverage & verification</h3><p>Use dataset drill-downs to inspect exact observations now. Ranking coverage, edition filters and mapping reconciliation appear here when CF-063 ingestion is applied.</p></div><button className="m-secondary" onClick={()=>navigate('Compare',{type:'provider'})}><ArrowLeftRight size={15}/>Open Compare</button></div>
   <div className="m-stats-notes">
    <div><b>Provider context</b><span>QILT, PRISMS and institutional rankings retain their native source grain.</span></div>
    <div><b>Years / editions</b><span>Comparison will use latest common period by default, with explicit dataset/year selection.</span></div>
    <div><b>Evidence</b><span>Every accepted observation remains traceable to governed source Evidence.</span></div>
    <div><b>Historical publisher files</b><span>{rank>=4?'Authorised CSV/XLSX/PDF/JSON/ZIP artifacts will be registered through Administration → Sources & Imports.':'Import controls are restricted to authorised operator roles.'}</span></div>
   </div>
  </section>
 </div>
}


function AdministrationHome({rank,navigate,routeParams,onError}){
 const sections=[
  ['overview','Overview',Settings2,rank>=4],
  ['sources-imports','Sources & Imports',Database,rank>=4],
  ['layer1-sources','Layer 1 sources',Database,rank>=6],
  ['layer2-sources','Layer 2 sources',Database,rank>=4],
  ['layer2-providers','Acquisition',SlidersHorizontal,rank>=4],
  ['scheduling','Scheduling',RefreshCw,rank>=4],
  ['onboarding','Onboarding',Workflow,rank>=4],
  ['pim','PIM configuration',Tags,rank>=5],
  ['platform','Platform',Settings2,rank>=6],
 ]
 const allowed=sections.filter(x=>x[3])
 const requested=routeParams?.get?.('section')||'overview'
 const tool=allowed.some(x=>x[0]===requested)?requested:(allowed[0]?.[0]||'overview')
 const selectTool=key=>navigate('Administration',key==='overview'?{}:{section:key})
 const openRoute=label=>navigate(label)
 return <div className="m-page-stack"><section className="m-panel"><PanelTitle icon={Settings2} title="Administration" subtitle="Central configuration. Choose a section below; operational Layer workspaces remain separate."/>
  <div className="m-admin-subnav" role="tablist" aria-label="Administration sections">{allowed.map(([key,label,Icon])=><button key={key} role="tab" aria-selected={tool===key} className={tool===key?'active':''} onClick={()=>selectTool(key)}><Icon size={15}/><span>{label}</span></button>)}</div>
 </section>
 {tool==='overview'&&<section className="m-panel"><PanelTitle icon={Settings2} title="Administration overview" subtitle="Configuration is grouped here rather than scattered through Layer operations."/><div className="m-attention-grid">
  <Attention tone="info" icon={Database} title="Sources & onboarding" text="Governed sources, qualification and onboarding lifecycle." action="Open sources" onClick={()=>openRoute('Sources')}/>
  <Attention tone="info" icon={RefreshCw} title="Scheduling" text="Refresh cadence, targeted scheduling and policy controls." action="Open scheduling" onClick={()=>selectTool('scheduling')}/>
  <Attention tone="info" icon={SlidersHorizontal} title="Acquisition" text="Layer 2 source profiles, Firecrawl/direct routes and execution policy." action="Open acquisition" onClick={()=>selectTool('layer2-providers')}/>
  {rank>=5&&<Attention tone="info" icon={Tags} title="PIM configuration" text="Attributes, groups, families, options and completeness profiles." action="Open PIM" onClick={()=>selectTool('pim')}/>}
 </div></section>}
 {tool==='sources-imports'&&<RankingImportPanel onError={onError} routeParams={routeParams}/>} 
 {tool==='layer1-sources'&&rank>=6&&<Layer1SourceSettings/>} 
 {tool==='layer2-sources'&&<Layer2SourceConfig rank={rank} embedded onOpenProviders={()=>selectTool('layer2-providers')}/>} 
 {tool==='layer2-providers'&&<><Layer2ProviderConfig rank={rank} embedded/>{rank>=5&&<Layer2ExecutionPolicySettings/>}</>}
 {tool==='scheduling'&&<div className="m-page-stack"><RefreshWorkspace onError={()=>{}}/></div>}
 {tool==='onboarding'&&<div className="m-page-stack"><OnboardingWorkspace rank={rank} onError={()=>{}}/></div>}
 {tool==='pim'&&rank>=5&&<Attributes onError={()=>{}}/>}
 {tool==='platform'&&rank>=6&&<PlatformMaturity rank={rank} onError={onError}/>} 
 </div>
}
function RankingImportPanel({onError,routeParams}){
 const presetSystem=routeParams?.get?.('system')==='the_wur'?'the_wur':'qs_wur',presetYear=routeParams?.get?.('year')||'2026'
 const empty={systemCode:presetSystem,editionYear:presetYear,publisherName:presetSystem==='the_wur'?'Times Higher Education':'QS Quacquarelli Symonds',sourceUrl:'',methodologyUrl:'',licensingNote:'Authorised publisher file obtained for CourseFinder ingestion.',revisionNote:''}
 const[form,setForm]=useState(empty),[file,setFile]=useState(null),[busy,setBusy]=useState(false),[saved,setSaved]=useState(''),[imports,setImports]=useState([])
 const load=()=>api.rankingImports({limit:20}).then(x=>setImports(x?.items||[])).catch(e=>onError?.(e.message))
 useEffect(()=>{load()},[])
 const patch=(k,v)=>setForm(x=>({...x,[k]:v}))
 async function submit(e){
  e.preventDefault();setSaved('')
  if(!file){onError?.('Choose an authorised publisher file.');return}
  setBusy(true)
  try{
   const r=await api.uploadRankingPublisherFile({...form,editionYear:Number(form.editionYear),file})
   setSaved(r?.duplicate?'Duplicate file already registered; no new Evidence created.':'Publisher file uploaded and registered as private Evidence.')
   setFile(null);e.currentTarget.reset();setForm(x=>({...x,sourceUrl:'',methodologyUrl:'',revisionNote:''}));await load()
  }catch(err){onError?.(err?.message||String(err))}
  finally{setBusy(false)}
 }
 return <div className="m-page-stack">
  <section className="m-panel"><PanelTitle icon={FileCheck2} title="Historical ranking publisher files" subtitle="Use only an authorised QS/THE artifact when automated publisher retrieval is restricted."/>
   <form className="m-ranking-import-form" onSubmit={submit}>
    <label>Ranking system<select value={form.systemCode} onChange={e=>{const v=e.target.value;patch('systemCode',v);patch('publisherName',v==='the_wur'?'Times Higher Education':'QS Quacquarelli Symonds')}}><option value="qs_wur">QS World University Rankings</option><option value="the_wur">Times Higher Education World University Rankings</option></select></label>
    <label>Edition year<input type="number" min="2000" max="2100" value={form.editionYear} onChange={e=>patch('editionYear',e.target.value)} required/></label>
    <label>Publisher<input value={form.publisherName} onChange={e=>patch('publisherName',e.target.value)} required/></label>
    <label className="wide">Publisher/source URL<input type="url" value={form.sourceUrl} onChange={e=>patch('sourceUrl',e.target.value)} placeholder="https://…" required/></label>
    <label className="wide">Methodology URL<input type="url" value={form.methodologyUrl} onChange={e=>patch('methodologyUrl',e.target.value)} placeholder="Optional"/></label>
    <label className="wide">Access / licence note<textarea value={form.licensingNote} onChange={e=>patch('licensingNote',e.target.value)} required/></label>
    <label className="wide">Revision note<input value={form.revisionNote} onChange={e=>patch('revisionNote',e.target.value)} placeholder="Optional edition/correction note"/></label>
    <label className="wide">Publisher file<input type="file" accept=".csv,.xlsx,.pdf,.json,.zip" onChange={e=>setFile(e.target.files?.[0]||null)} required/><small>Private Evidence · CSV/XLSX/PDF/JSON/ZIP · maximum 50 MB.</small></label>
    <div className="wide m-ranking-import-actions"><button className="m-primary" disabled={busy}>{busy?'Uploading…':'Upload & register Evidence'}</button>{saved&&<span>{saved}</span>}</div>
   </form>
  </section>
  <section className="m-panel"><PanelTitle icon={History} title="Recent ranking imports" subtitle="Upload is only the first state; validation, parsing, reconciliation and apply remain separate."/>
   <div className="m-ranking-import-list">{imports.length?imports.map(x=><article key={x.id}><div><strong>{x.system_code?.toUpperCase()} {x.edition_year}</strong><span>{x.original_filename}</span></div><div><b>{humanise(x.status)}</b><small>{x.uploaded_at?new Date(x.uploaded_at).toLocaleString():'—'}</small></div></article>):<EmptyState icon={FileCheck2} title="No ranking files uploaded" text="Historical publisher files will appear here after governed registration."/>}</div>
  </section>
 </div>
}

function Layer2ExecutionPolicySettings(){
 const[data,setData]=useState(null),[form,setForm]=useState(null),[busy,setBusy]=useState(true),[saving,setSaving]=useState(false),[error,setError]=useState(''),[saved,setSaved]=useState('')
 const invoke=async body=>{const{data:r,error:e}=await supabase.functions.invoke('layer2-sync-control',{body});if(e)throw e;if(r?.error)throw new Error(r.error);return r}
 const load=async()=>{setBusy(true);setError('');try{const r=await invoke({action:'policy'}),p=r?.policy||{};setData(r);setForm({qualification_provider_wave_size:p.qualification_provider_wave_size??50,qualification_sample_size:p.qualification_sample_size??10,qualification_retry_hours:p.qualification_retry_hours??168,qualification_finalizer_run_limit:p.qualification_finalizer_run_limit??2,qualification_pattern_provider_limit:p.qualification_pattern_provider_limit??3,production_target_wave_size:p.production_target_wave_size??500,production_max_wave_size:p.production_max_wave_size??1000,route_mode:p.route_mode||'scraper_first',schedule_remaining:p.schedule_remaining!==false})}catch(e){setError(e.message||String(e))}finally{setBusy(false)}}
 useEffect(()=>{load()},[])
 const save=async()=>{if(!form)return;setSaving(true);setError('');setSaved('');try{const r=await invoke({action:'update_policy',patch:{...form,qualification_provider_wave_size:Number(form.qualification_provider_wave_size),qualification_sample_size:Number(form.qualification_sample_size),qualification_retry_hours:Number(form.qualification_retry_hours),qualification_finalizer_run_limit:Number(form.qualification_finalizer_run_limit),qualification_pattern_provider_limit:Number(form.qualification_pattern_provider_limit),production_target_wave_size:Number(form.production_target_wave_size),production_max_wave_size:Number(form.production_max_wave_size)}});setData(r);setSaved('Layer 2 execution policy saved. New background requests use these limits.')}catch(e){setError(e.message||String(e))}finally{setSaving(false)}}
 const b=data?.firecrawl?.budget_status||{},fc=data?.firecrawl||{}
 return <section className="m-panel"><PanelTitle icon={Activity} title="Layer 2 execution policy" subtitle="Central source-qualification, production wave and Firecrawl budget policy. Operators see effective values in Layer 2; they do not edit them there." action={<button className="m-secondary compact" onClick={load} disabled={busy||saving}><RefreshCw size={13}/>Refresh</button>}/>
  {busy&&!form?<div className="m-empty-inline">Loading Layer 2 policy…</div>:form&&<><div className="m-summary-strip"><SummaryCard icon={Database} label="Firecrawl monthly limit" value={fmtNumber(b.limit_units)} tone="blue"/><SummaryCard icon={Activity} label="Used this period" value={fmtNumber(b.used_units)} tone="violet"/><SummaryCard icon={ShieldCheck} label="Safety reserve" value={fmtNumber(b.stop_at_remaining_units)} tone="amber"/><div className="m-summary-note"><strong>{fc.enabled?'Firecrawl enabled':'Firecrawl disabled'}</strong><span>{fmtNumber(fc.rate_limit_per_minute)} requests/min · concurrency {fmtNumber(fc.concurrency)} · credential {fc.credential_configured?'configured':'missing'}.</span></div></div>
  <div className="m-grid-2">
   <div className="m-detail-section"><h3>Background qualification</h3><p className="m-help">Each Provider requires one seed acquisition; Course samples are identity controls, not individual scrapes.</p><div className="m-kv-list">
    <label><span>Providers per scheduler batch</span><input aria-label="Layer 2 qualification Providers per batch" type="number" min="1" max="500" value={form.qualification_provider_wave_size} onChange={e=>setForm(x=>({...x,qualification_provider_wave_size:e.target.value}))}/></label>
    <label><span>Identity samples per Provider</span><input aria-label="Layer 2 qualification samples per Provider" type="number" min="1" max="50" value={form.qualification_sample_size} onChange={e=>setForm(x=>({...x,qualification_sample_size:e.target.value}))}/></label>
    <label><span>Requalification interval (hours)</span><input aria-label="Layer 2 qualification retry hours" type="number" min="1" max="2160" value={form.qualification_retry_hours} onChange={e=>setForm(x=>({...x,qualification_retry_hours:e.target.value}))}/></label>
    <label><span>Finaliser runs per cycle</span><input aria-label="Layer 2 qualification finaliser runs per cycle" type="number" min="1" max="10" value={form.qualification_finalizer_run_limit} onChange={e=>setForm(x=>({...x,qualification_finalizer_run_limit:e.target.value}))}/></label>
    <label><span>Pattern Providers per finaliser run</span><input aria-label="Layer 2 pattern Providers per finaliser run" type="number" min="1" max="5" value={form.qualification_pattern_provider_limit} onChange={e=>setForm(x=>({...x,qualification_pattern_provider_limit:e.target.value}))}/></label>
   </div></div>
   <div className="m-detail-section"><h3>Production enrichment</h3><p className="m-help">The accepted wave is automatically clamped by the current Firecrawl entitlement and reserve.</p><div className="m-kv-list">
    <label><span>Target Courses per wave</span><input aria-label="Layer 2 production target wave" type="number" min="1" max="5000" value={form.production_target_wave_size} onChange={e=>setForm(x=>({...x,production_target_wave_size:e.target.value}))}/></label>
    <label><span>Maximum Courses per wave</span><input aria-label="Layer 2 production maximum wave" type="number" min="1" max="5000" value={form.production_max_wave_size} onChange={e=>setForm(x=>({...x,production_max_wave_size:e.target.value}))}/></label>
    <label><span>Primary route</span><select aria-label="Layer 2 production route mode" value={form.route_mode} onChange={e=>setForm(x=>({...x,route_mode:e.target.value}))}><option value="scraper_first">Firecrawl direct / scraper-first</option><option value="managed">Managed route</option></select></label>
    <label style={{display:'flex',alignItems:'center',gap:8}}><input aria-label="Layer 2 schedule remaining waves policy" type="checkbox" checked={form.schedule_remaining} onChange={e=>setForm(x=>({...x,schedule_remaining:e.target.checked}))}/><span>Schedule remaining waves automatically</span></label>
   </div></div>
  </div>
  <div style={{display:'flex',alignItems:'center',gap:10,marginTop:12}}><button className="m-primary" onClick={save} disabled={saving}>{saving?'Saving…':'Save Layer 2 policy'}</button>{saved&&<span style={{fontSize:10,color:'#15803d'}}>{saved}</span>}</div></>}
  {error&&<div className="m-alert compact" style={{marginTop:10}}><AlertTriangle size={14}/><span>{error}</span><span/></div>}
 </section>
}

function OpsOverlayLauncher({tab}){
  useEffect(()=>{window.dispatchEvent(new CustomEvent('coursefinder:m23-open',{detail:{tab}}))},[tab])
  return <div className="m-page-stack"><section className="m-panel"><PanelTitle icon={Workflow} title={tab} subtitle="This governed operational registry is now launched from primary navigation."/>
    <button className="m-primary" onClick={()=>window.dispatchEvent(new CustomEvent('coursefinder:m23-open',{detail:{tab}}))}>Open {tab}</button>
  </section></div>
}

function ScholarshipWorkspace({rank,onError,navigate,initialId}){const[selectionOpen,setSelectionOpen]=useState(false);return <div className="m-page-stack"><section className="m-panel"><PanelTitle icon={Sparkles} title="Scholarship decision support" subtitle="Structural candidate scoring only. Student eligibility remains unresolved unless separately verified."/><button className="m-secondary" onClick={()=>setSelectionOpen(true)}><GraduationCap size={15}/>Open Course decision support</button></section>{rank>=4&&<ScholarshipFillControl onError={onError}/>}<Catalogue type="scholarship" onError={onError} navigate={navigate} initialId={initialId}/>{selectionOpen&&<ScholarshipSelectionWorkspace onClose={()=>setSelectionOpen(false)}/>}</div>}

function ScholarshipFillControl({onError}){
 const[country,setCountry]=useState('AU'),[busy,setBusy]=useState(false),[result,setResult]=useState(null)
 const run=async action=>{setBusy(true);try{const{data,error}=await supabase.functions.invoke('scholarship-course-fill-control',{body:{action,country_code:country}});if(error)throw error;if(data?.error)throw new Error(data.error);setResult(data)}catch(e){onError(e.message||String(e))}finally{setBusy(false)}}
 return <section className="m-panel"><PanelTitle icon={Sparkles} title="Fill Course Scholarships" subtitle="Materialises only explicit Course/Provider Scholarship scopes. Provider ownership alone is review-only."/>
  <div className="m-filter-bar"><label className="m-filter-select"><span>Country</span><select aria-label="Scholarship fill country" value={country} onChange={e=>setCountry(e.target.value)}><option value="AU">Australia</option><option value="NZ">New Zealand</option></select></label></div>
  <div className="m-attention-grid"><Attention tone="info" icon={SearchCheck} title="Preview mapping" text="Count Courses, explicit deterministic mappings and review-only candidates." action="Preview" onClick={()=>run('preview')}/><Attention tone="success" icon={CheckCircle2} title="Fill mapped Scholarships" text="Idempotently writes only explicit include-scope mappings; no Course canonical fields or publication state are changed." action="Fill now" onClick={()=>run('fill')}/><Attention tone="warning" icon={ClipboardCheck} title="Queue unresolved" text="Provider-owned Scholarships without explicit Course/Provider scope are retained for review rather than inferred." action="Queue review" onClick={()=>run('queue_review')}/></div>
  {busy&&<div className="m-empty-inline">Running governed Scholarship mapping…</div>}{result&&<div className="m-summary-strip"><SummaryCard icon={GraduationCap} label="Courses" value={fmtNumber(result.courses??result.deterministic_mappings??0)} tone="blue"/><SummaryCard icon={Sparkles} label="Deterministic mappings" value={fmtNumber(result.deterministic_mappings??result.written_or_refreshed??0)} tone="green"/><SummaryCard icon={ClipboardCheck} label="Review candidates" value={fmtNumber(result.provider_level_candidates??0)} tone="amber"/><div className="m-summary-note"><strong>{humanise(result.status||'preview ready')}</strong><span>{result.rule||'No Scholarship eligibility is manufactured.'}</span></div></div>}
 </section>
}

function Dashboard({onError,navigate}){
  const[data,setData]=useState(null),[layerStatus,setLayerStatus]=useState(null),[busy,setBusy]=useState(true)
  const load=()=>{setBusy(true);Promise.all([adminRead('dashboard'),adminRead('layer_status_summary')]).then(([d,l])=>{setData(d);setLayerStatus(l)}).catch(e=>onError(e.message)).finally(()=>setBusy(false))}
  useEffect(load,[])
  if(busy&&!data)return <DashboardSkeleton/>
  const op=data?.operational??{},failed=Number(op.failed_jobs_24h||0),running=Number(op.running_jobs||0),reviews=Number(data?.open_reviews||0)
  const health=failed>0?'attention':running>0?'active':'healthy'
  const metrics=[
    ['Providers',data?.providers,Building2,'indigo','Providers'],['Courses',data?.courses,GraduationCap,'blue','Courses'],
    ['Evidence',data?.evidence,FileCheck2,'violet','Evidence'],['Open reviews',data?.open_reviews,ClipboardCheck,reviews?'amber':'green','Review Queue'],
    ['Jobs',data?.jobs,Workflow,'teal','Jobs'],['Search documents',data?.search_documents,SearchCheck,'cyan','Courses'],
    ['Scholarships',data?.scholarships,Sparkles,'pink','Scholarships'],['Attributes',data?.attributes,Tags,'slate','Attributes'],
  ]
  return <div className="m-page-stack">
    <section className="m-dashboard-intro"><div><span className={`m-health m-health-${health}`}><span/>{health==='healthy'?'Operationally healthy':health==='active'?'Pipeline activity in progress':'Attention required'}</span><h2>Operational command view</h2><p>Counts, freshness and human-attention signals from the governed canonical and pipeline layers.</p></div><button className="m-secondary" onClick={load}><RefreshCw size={15}/>Refresh</button></section>
    <div className="m-metric-grid">{metrics.map(([label,value,Icon,tone,target])=><button className={`m-metric-card tone-${tone}`} key={label} onClick={()=>navigate(target)}><span className="m-metric-icon"><Icon size={18}/></span><span className="m-metric-copy"><small>{label}</small><strong>{fmtNumber(value)}</strong></span><span className="m-metric-arrow">→</span></button>)}</div>
    {layerStatus&&<section className="m-panel">
      <PanelTitle icon={Layers3} title="Layer status" subtitle="Operational state across authority, enrichment, interpretation and human resolution"/>
      <div className="m-grid-2">
        <div className="m-record"><strong>Layer 1 · Authority</strong><span>{fmtNumber(layerStatus.layer1?.active_sources)} active source(s) · {fmtNumber(layerStatus.layer1?.running_jobs)} running job(s)</span><small>{fmtNumber(layerStatus.layer1?.failed_24h)} failed in 24h · latest {layerStatus.layer1?.latest_activity?relativeTime(layerStatus.layer1.latest_activity):'—'}</small></div>
        <div className="m-record"><strong>Layer 2 · Enrichment</strong><span>{fmtNumber(layerStatus.layer2?.active_batches)} active batch(es) · {fmtNumber(layerStatus.layer2?.scheduled_wave_requests)} scheduled wave request(s)</span><small>{fmtNumber(layerStatus.layer2?.wave_pending_courses)} Courses pending · {fmtNumber(layerStatus.layer2?.processed_24h)} processed in 24h · {fmtNumber(layerStatus.layer2?.evidence_24h)} Evidence captures</small></div>
        <div className="m-record"><strong>Layer 3 · AI interpretation</strong><span>{fmtNumber(layerStatus.layer3?.qualified_profiles)} qualified profile(s) · {fmtNumber(layerStatus.layer3?.pending_evidence_candidates)} pending Evidence candidate(s)</span><small>{fmtNumber(layerStatus.layer3?.interpretations_24h)} interpretations · {fmtNumber(layerStatus.layer3?.calls_24h)} calls · {fmtNumber(layerStatus.layer3?.tokens_24h)} tokens · USD {Number(layerStatus.layer3?.recorded_cost_24h||0).toFixed(4)} recorded</small></div>
        <div className="m-record"><strong>Layer 4 · Human resolution</strong><span>{fmtNumber(layerStatus.layer4?.pending_reviews)} pending review(s) · {fmtNumber(layerStatus.layer4?.active_overrides)} active override(s)</span><small>{fmtNumber(layerStatus.layer4?.publication_decisions)} publication decision event(s) · {fmtNumber(layerStatus.scholarships?.course_mappings)} Course-Scholarship mappings</small></div>
      </div>
    </section>}
    <div className="m-grid-2 dashboard-grid">
      <section className="m-panel"><PanelTitle icon={Zap} title="Operational pulse" subtitle="What requires attention now"/>
        <div className="m-pulse-grid"><Pulse label="Running jobs" value={op.running_jobs} tone={running?'info':'neutral'} icon={Workflow}/><Pulse label="Failed jobs · 24h" value={op.failed_jobs_24h} tone={failed?'danger':'success'} icon={AlertTriangle}/><Pulse label="Completed jobs · 24h" value={op.completed_jobs_24h} tone="success" icon={CheckCircle2}/><Pulse label="Evidence captured · 24h" value={op.evidence_24h} tone="violet" icon={FileCheck2}/></div>
        <div className="m-freshness"><Fresh label="Latest pipeline activity" value={op.latest_job_at}/><Fresh label="Latest evidence" value={op.latest_evidence_at}/><Fresh label="Search projection rebuilt" value={op.search_rebuilt_at}/><Fresh label="Search projection rows" value={op.search_row_count} number/></div>
      </section>
      <section className="m-panel"><PanelTitle icon={History} title="Recent activity" subtitle="Latest jobs, review events and evidence captures"/><ActivityFeed items={data?.recent_activity??[]} navigate={navigate}/></section>
    </div>
    <section className="m-panel"><PanelTitle icon={AlertTriangle} title="Attention & next actions" subtitle="Exception-first operational guidance"/>
      <div className="m-attention-grid">
        <Attention tone={failed?'danger':'success'} icon={failed?AlertTriangle:CheckCircle2} title={failed?`${failed} failed job${failed===1?'':'s'} in the last 24 hours`:'No failed jobs in the last 24 hours'} text={failed?'Review pipeline failures before the next scheduled run.':'Pipeline failure signal is clear.'} action="Open Jobs" onClick={()=>navigate('Jobs')}/>
        <Attention tone={reviews?'warning':'success'} icon={ClipboardCheck} title={reviews?`${reviews} review item${reviews===1?'':'s'} awaiting resolution`:'Review queue is clear'} text={reviews?'Prioritise high-impact or identity-sensitive exceptions.':'No current human-resolution backlog.'} action="Open Review Queue" onClick={()=>navigate('Review Queue')}/>
        <Attention tone="info" icon={SearchCheck} title={`${fmtNumber(op.search_row_count??data?.search_documents)} projected Search rows`} text={op.search_rebuilt_at?`Last rebuilt ${relativeTime(op.search_rebuilt_at)}.`:'Search rebuild timestamp is not available.'} action="Open Courses" onClick={()=>navigate('Courses')}/>
      </div>
    </section>
  </div>
}

function DashboardSkeleton(){return <div className="m-page-stack"><div className="m-skeleton hero"/><div className="m-metric-grid">{Array.from({length:8}).map((_,i)=><div className="m-skeleton metric" key={i}/>)}</div><div className="m-grid-2"><div className="m-skeleton panel"/><div className="m-skeleton panel"/></div></div>}
function PanelTitle({icon:Icon,title,subtitle,action}){return <div className="m-panel-title"><div className="m-panel-heading">{Icon&&<span className="m-panel-icon"><Icon size={16}/></span>}<div><h2>{title}</h2>{subtitle&&<p>{subtitle}</p>}</div></div>{action}</div>}
function Pulse({label,value,tone,icon:Icon}){return <div className={`m-pulse tone-${tone}`}><span><Icon size={15}/></span><div><small>{label}</small><strong>{fmtNumber(value)}</strong></div></div>}
function Fresh({label,value,number}){return <div><small>{label}</small><strong>{number?fmtNumber(value):value?`${relativeTime(value)} · ${fmtDateTime(value)}`:'—'}</strong></div>}
function ActivityFeed({items,navigate}){if(!items.length)return <EmptyInline text="No recent governed activity is available."/>;return <div className="m-activity-list">{items.map((x,i)=>{const Icon=x.kind==='job'?Workflow:x.kind==='review'?ClipboardCheck:FileCheck2;const target=x.kind==='job'?'Jobs':x.kind==='review'?'Review Queue':'Evidence';const params=x.kind==='evidence'&&x.id?{evidence_id:x.id}:{};return <button key={x.id||i} onClick={()=>navigate(target,params)} className="m-activity-row"><span className={`m-activity-icon kind-${x.kind}`}><Icon size={15}/></span><span className="m-activity-copy"><strong>{x.title||humanise(x.kind)}</strong><small>{x.detail||'Governed activity'} · {relativeTime(x.occurred_at)}</small></span><Status value={x.status}/></button>})}</div>}
function Attention({tone,icon:Icon,title,text,action,onClick}){return <div className={`m-attention tone-${tone}`}><span className="m-attention-icon"><Icon size={17}/></span><div><strong>{title}</strong><p>{text}</p><button onClick={onClick}>{action} →</button></div></div>}

const ENTITY={
  provider:{operation:'providers_page',detail:'provider_detail',sort:'provider',search:'Search Provider name, CRICOS code, stable key or location'},
  course:{operation:'courses_page',detail:'course_detail',sort:'course',search:'Search Course, Provider, CRICOS/course code or stable key'},
  campus:{operation:'campuses_page',detail:'campus_detail',sort:'campus',search:'Search Campus, Provider, code, city or stable key'},
  scholarship:{operation:'scholarships_page',detail:'scholarship_detail',sort:'scholarship',search:'Search Scholarship or Provider'},
}

function Catalogue({type,onError,navigate,initialId='',completenessMode=false}){
  const cfg=ENTITY[type]
  const[query,setQuery]=useState(''),[filters,setFilters]=useState({}),[offset,setOffset]=useState(0),[sort,setSort]=useState(completenessMode?'completeness':cfg.sort),[direction,setDirection]=useState(completenessMode?'asc':'asc')
  const[data,setData]=useState(null),[busy,setBusy]=useState(false),[filterData,setFilterData]=useState({}),[filterLabels,setFilterLabels]=useState({}),[filterBusy,setFilterBusy]=useState(false),[selected,setSelected]=useState(null),[detail,setDetail]=useState(null),[detailBusy,setDetailBusy]=useState(false),[advanced,setAdvanced]=useState(type==='course'),[screenStateKey,setScreenStateKey]=useState(''),[screenStateReady,setScreenStateReady]=useState(false)
  useEffect(()=>{let live=true;supabase.auth.getSession().then(({data:s})=>{if(!live)return;const uid=s?.session?.user?.id||'anonymous',key=`coursefinder:pim:screen-state:v1:${uid}:${type}`;setScreenStateKey(key);try{const saved=JSON.parse(localStorage.getItem(key)||'null');if(saved&&typeof saved==='object'){if(typeof saved.query==='string')setQuery(saved.query);if(saved.filters&&typeof saved.filters==='object')setFilters(saved.filters);if(saved.filterLabels&&typeof saved.filterLabels==='object')setFilterLabels(saved.filterLabels);if(typeof saved.advanced==='boolean')setAdvanced(saved.advanced);if(typeof saved.sort==='string')setSort(saved.sort);if(saved.direction==='asc'||saved.direction==='desc')setDirection(saved.direction)}}catch{}setScreenStateReady(true)});return()=>{live=false}},[type])
  useEffect(()=>{if(!screenStateReady||!screenStateKey)return;localStorage.setItem(screenStateKey,JSON.stringify({query,filters,filterLabels,advanced,sort,direction}))},[screenStateReady,screenStateKey,query,JSON.stringify(filters),JSON.stringify(filterLabels),advanced,sort,direction])
  const debounced=useDebounce(query,280)
  const args=useMemo(()=>buildCatalogueArgs(type,{query:debounced,filters,offset,sort,direction}),[type,debounced,filters,offset,sort,direction])
  useEffect(()=>{let live=true;setBusy(true);adminRead(cfg.operation,args).then(x=>live&&setData(x)).catch(e=>onError(e.message)).finally(()=>live&&setBusy(false));return()=>{live=false}},[cfg.operation,JSON.stringify(args)])
  useEffect(()=>{if(!['provider','course','campus','scholarship'].includes(type))return;if(type==='course'){setFilterData({});setFilterBusy(false);return}let live=true;setFilterBusy(true);api.providerFilterOptions(filters.country||'').then(x=>live&&setFilterData(x||{})).catch(e=>onError(e.message)).finally(()=>live&&setFilterBusy(false));return()=>{live=false}},[type,filters.country,filters.subdivision])
  useEffect(()=>setOffset(0),[debounced,JSON.stringify(filters),sort,direction])
  useEffect(()=>{if(initialId&&String(initialId)!==String(selected))open({id:initialId,course_id:initialId})},[initialId,type])
  const rows=rowsOf(data),total=Number(data?.total??rows.length??0),active=activeFilters(filters)
  async function open(row){const id=row.id??row.course_id;setSelected(id);setDetailBusy(true);try{setDetail(await adminRead(cfg.detail,{id}))}catch(e){onError(e.message)}finally{setDetailBusy(false)}}
  function patch(k,v,label=''){setFilters(f=>{const n={...f,[k]:v};if(k==='country'){n.subdivision='';if(type==='course')n.provider=''}if(k==='subdivision'&&type==='course')n.provider='';return n});setFilterLabels(l=>{const n={...l,[k]:label||''};if(k==='country'){delete n.subdivision;if(type==='course')delete n.provider}if(k==='subdivision'&&type==='course')delete n.provider;return n})}
  function changeSort(k){if(!k)return;if(sort===k)setDirection(d=>d==='asc'?'desc':'asc');else{setSort(k);setDirection('asc')}}
  const cols=columns(type,completenessMode)
  return <div className="m-page-stack">
    {completenessMode&&<CompletenessSummary onError={onError}/>} 
    <section className="m-panel m-catalogue-panel">
      <div className="m-workspace-head"><div><h2>{completenessMode?'Course readiness workspace':`${humanise(type)} catalogue`}</h2><p>{completenessMode?'Find missing core-presence signals without treating completeness as truth.':'Filter → inspect → cross-check → decide.'}</p></div><div className="m-result-count">{busy?<><span className="m-spinner"/>Loading…</>:<><strong>{fmtNumber(total)}</strong><span>matching</span></>}</div></div>
      <div className="m-search-row"><label className="m-searchbox"><Search size={16}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder={cfg.search}/>{query&&<button onClick={()=>setQuery('')}><X size={14}/></button>}</label>{type==='course'&&<button className={`m-filter-toggle ${advanced?'active':''}`} onClick={()=>setAdvanced(x=>!x)}><SlidersHorizontal size={15}/>Filters{active.length?` · ${active.length}`:''}</button>}<button className="m-secondary compact" onClick={()=>{setQuery('');setFilters({});setFilterLabels({});setOffset(0);if(screenStateKey)localStorage.removeItem(screenStateKey)}} disabled={!query&&!active.length}><RefreshCw size={14}/>Clear</button>{!completenessMode&&['provider','course'].includes(type)&&<button className="m-secondary compact" onClick={()=>navigate?.('Compare',{type})}><Activity size={14}/>Compare {type}s</button>}</div>
      <FilterBar type={type} filters={filters} filterLabels={filterLabels} patch={patch} data={filterData} busy={filterBusy} advanced={advanced}/>
      {(query||active.length>0)&&<div className="m-chip-row">{query&&<FilterChip label={`Search: ${query}`} onRemove={()=>setQuery('')}/>} {active.map(([k,v])=><FilterChip key={k} label={`${filterLabel(k)}: ${filterLabels[k]||filterValueLabel(k,v,filterData)}`} onRemove={()=>patch(k,'')}/>)}</div>}
      <DataTable rows={rows} columns={cols} loading={busy} sort={sort} direction={direction} onSort={changeSort} onRow={open} selected={selected}/>
      <Pager offset={offset} limit={PAGE_SIZE} total={total} onOffset={setOffset}/>
    </section>
    {selected&&<DetailDrawer type={type} data={detail} busy={detailBusy} navigate={navigate} onClose={()=>{setSelected(null);setDetail(null)}}/>}
  </div>
}

function FilterBar({type,filters,filterLabels={},patch,data,busy,advanced}){
  const countries=(data.countries||[]).map(x=>opt(x.code,x.name,x.code)),subdivisions=(data.subdivisions||[]).map(x=>opt(x.code,x.name,x.code))
  if(type==='provider')return <div className="m-filter-bar"><FilterSelect label="Country" value={filters.country||''} onChange={(v,l)=>patch('country',v,l)} options={countries} loading={busy}/><FilterSelect label="State / Region" value={filters.subdivision||''} onChange={(v,l)=>patch('subdivision',v,l)} options={subdivisions} loading={busy}/><FilterSelect label="Lifecycle" value={filters.lifecycle||''} onChange={(v,l)=>patch('lifecycle',v,l)} options={STATUS_OPTIONS}/><FilterSelect label="Publication" value={filters.publication||''} onChange={(v,l)=>patch('publication',v,l)} options={PUBLICATION_OPTIONS}/></div>
  if(type==='campus')return <div className="m-filter-bar"><FilterSelect label="Country" value={filters.country||''} onChange={(v,l)=>patch('country',v,l)} options={countries} loading={busy}/><FilterSelect label="State / Region" value={filters.subdivision||''} onChange={(v,l)=>patch('subdivision',v,l)} options={subdivisions} loading={busy}/></div>
  if(type==='scholarship')return <div className="m-filter-bar"><FilterSelect label="Country" value={filters.country||''} onChange={(v,l)=>patch('country',v,l)} options={countries} loading={busy}/><FilterSelect label="Lifecycle" value={filters.lifecycle||''} onChange={(v,l)=>patch('lifecycle',v,l)} options={STATUS_OPTIONS}/><FilterSelect label="Publication" value={filters.publication||''} onChange={(v,l)=>patch('publication',v,l)} options={PUBLICATION_OPTIONS}/></div>
  if(type!=='course')return null
  return <div className={`m-filter-bar m-course-filters ${advanced?'expanded':''}`}>
    <PagedFilterSelect kind="country" label="Country" value={filters.country||''} valueLabel={filterLabels.country||''} onChange={(v,l)=>patch('country',v,l)}/>
    <PagedFilterSelect kind="subdivision" label="State / Region" value={filters.subdivision||''} valueLabel={filterLabels.subdivision||''} country={filters.country||''} onChange={(v,l)=>patch('subdivision',v,l)}/>
    <PagedFilterSelect kind="provider" label="Provider" value={filters.provider||''} valueLabel={filterLabels.provider||''} country={filters.country||''} subdivision={filters.subdivision||''} onChange={(v,l)=>patch('provider',v,l)}/>
    <PagedFilterSelect kind="level" label="Study level" value={filters.level||''} valueLabel={filterLabels.level||''} country={filters.country||''} subdivision={filters.subdivision||''} onChange={(v,l)=>patch('level',v,l)}/>
    {advanced&&<><PagedFilterSelect kind="field" label="Field" value={filters.field||''} valueLabel={filterLabels.field||''} country={filters.country||''} subdivision={filters.subdivision||''} onChange={(v,l)=>patch('field',v,l)}/><PagedFilterSelect kind="delivery" label="Delivery" value={filters.delivery||''} valueLabel={filterLabels.delivery||''} country={filters.country||''} subdivision={filters.subdivision||''} onChange={(v,l)=>patch('delivery',v,l)}/><TriFilter label="Has fee" value={filters.hasFee||''} onChange={(v,l)=>patch('hasFee',v,l)}/><TriFilter label="Has intake" value={filters.hasIntake||''} onChange={(v,l)=>patch('hasIntake',v,l)}/><TriFilter label="Has English" value={filters.hasEnglish||''} onChange={(v,l)=>patch('hasEnglish',v,l)}/><TriFilter label="Has scholarship" value={filters.hasScholarship||''} onChange={(v,l)=>patch('hasScholarship',v,l)}/><FilterSelect label="Min readiness" value={filters.minCompleteness||''} onChange={(v,l)=>patch('minCompleteness',v,l)} options={[50,75,90,100].map(n=>opt(String(n),`${n}%+`))}/><FilterSelect label="Freshness" value={filters.freshness||''} onChange={(v,l)=>patch('freshness',v,l)} options={[opt('never_verified','Never verified'),opt('modified_7d','Modified in 7 days'),opt('modified_30d','Modified in 30 days'),opt('stale_180d','Stale / never verified (180d)')]}/><FilterSelect label="Lifecycle" value={filters.lifecycle||''} onChange={(v,l)=>patch('lifecycle',v,l)} options={STATUS_OPTIONS}/><FilterSelect label="Publication" value={filters.publication||''} onChange={(v,l)=>patch('publication',v,l)} options={PUBLICATION_OPTIONS}/></>}
  </div>
}

function buildCatalogueArgs(type,{query,filters,offset,sort,direction}){const a={limit:PAGE_SIZE,offset,query:query||null,sort,direction};if(filters.country)a.country_code=filters.country;if(filters.subdivision)a.subdivision_code=filters.subdivision;if(filters.lifecycle)a.lifecycle_status=filters.lifecycle;if(filters.publication)a.publication_status=filters.publication;if(type==='course'){if(filters.provider)a.provider_id=filters.provider;if(filters.level)a.level_code=filters.level;if(filters.field)a.field_code=filters.field;if(filters.delivery)a.delivery_mode=filters.delivery;for(const k of['hasFee','hasIntake','hasEnglish','hasScholarship'])if(filters[k]!==''&&filters[k]!=null)a[camelToSnake(k)]=filters[k]==='true';if(filters.minCompleteness)a.min_completeness=Number(filters.minCompleteness);if(filters.freshness)a.freshness=filters.freshness}return a}
function camelToSnake(v){return v.replace(/[A-Z]/g,m=>'_'+m.toLowerCase())}
function activeFilters(f){return Object.entries(f).filter(([,v])=>v!==''&&v!==null&&v!==undefined)}
function filterLabel(k){return({country:'Country',subdivision:'State / Region',provider:'Provider',level:'Study level',field:'Field',delivery:'Delivery',hasFee:'Has fee',hasIntake:'Has intake',hasEnglish:'Has English',hasScholarship:'Has scholarship',minCompleteness:'Min readiness',freshness:'Freshness',lifecycle:'Lifecycle',publication:'Publication'})[k]||humanise(k)}
function filterValueLabel(k,v,d){if(['hasFee','hasIntake','hasEnglish','hasScholarship'].includes(k))return v==='true'?'Yes':'No';const sets={country:d.countries,subdivision:d.subdivisions,provider:d.providers,level:d.levels,field:d.fields,delivery:d.delivery_modes};const list=sets[k]||[];const found=list.find(x=>String(x.id??x.code??x.value)===String(v));return found?.name??found?.label??humanise(v)}

function FilterSelect({label,value,onChange,options=[],loading=false}){const[open,setOpen]=useState(false),[search,setSearch]=useState(''),[page,setPage]=useState(0);const ref=useRef(null),inputRef=useRef(null);useEffect(()=>{const close=e=>{if(ref.current&&!ref.current.contains(e.target))setOpen(false)};addEventListener('mousedown',close);return()=>removeEventListener('mousedown',close)},[]);useEffect(()=>setPage(0),[search,options.length]);useEffect(()=>{if(open&&typeof window!=='undefined'&&window.matchMedia?.('(pointer:fine)').matches)setTimeout(()=>inputRef.current?.focus(),0)},[open]);const selected=options.find(x=>String(x.value)===String(value));const filtered=options.filter(x=>`${x.label} ${x.meta||''}`.toLowerCase().includes(search.toLowerCase())),pages=Math.max(1,Math.ceil(filtered.length/10)),safePage=Math.min(page,pages-1),visible=filtered.slice(safePage*10,safePage*10+10);return <div className="m-filter-select" ref={ref}><button className={`m-filter-button ${value?'has-value':''}`} onClick={()=>setOpen(x=>!x)}><span><small>{label}</small><strong>{selected?.label||'All'}</strong></span>{loading?<span className="m-spinner tiny"/>:<ChevronDown size={14}/>}</button>{open&&<div className="m-filter-popover"><div className="m-filter-search"><Search size={14}/><input ref={inputRef} value={search} onChange={e=>setSearch(e.target.value)} placeholder={`Search ${label.toLowerCase()}…`}/></div><button className={!value?'selected':''} onClick={()=>{onChange('','All');setOpen(false);setSearch('');setPage(0)}}><span>All</span></button>{visible.map(x=><button key={String(x.value)} className={String(value)===String(x.value)?'selected':''} onClick={()=>{onChange(x.value,x.label);setOpen(false);setSearch('');setPage(0)}}><span>{x.label}</span>{x.meta&&<small>{x.meta}</small>}</button>)}{!visible.length&&<div className="m-option-empty">No matching options</div>}{filtered.length>10&&<div className="m-filter-pager"><button disabled={safePage===0} onClick={()=>setPage(p=>Math.max(0,p-1))}>Previous</button><span>{safePage+1} / {pages}</span><button disabled={safePage>=pages-1} onClick={()=>setPage(p=>Math.min(pages-1,p+1))}>Next</button></div>}</div>}</div>}
function PagedFilterSelect({kind,label,value,valueLabel='',onChange,country='',subdivision=''}){const[open,setOpen]=useState(false),[search,setSearch]=useState(''),[offset,setOffset]=useState(0),[data,setData]=useState({items:[],total:0,has_more:false}),[busy,setBusy]=useState(false),[selectedLabel,setSelectedLabel]=useState(valueLabel);const ref=useRef(null),inputRef=useRef(null),debounced=useDebounce(search,220);useEffect(()=>{const close=e=>{if(ref.current&&!ref.current.contains(e.target))setOpen(false)};addEventListener('mousedown',close);return()=>removeEventListener('mousedown',close)},[]);useEffect(()=>{setOffset(0)},[debounced,country,subdivision,kind]);useEffect(()=>{if(valueLabel)setSelectedLabel(valueLabel);if(!value)setSelectedLabel('')},[value,valueLabel]);useEffect(()=>{if(!open)return;let live=true;setBusy(true);api.catalogueFilterPage({kind,country,subdivision,query:debounced,limit:10,offset}).then(x=>{if(!live)return;setData(x||{items:[],total:0,has_more:false});const hit=(x?.items||[]).find(y=>String(y.value)===String(value));if(hit)setSelectedLabel(hit.label)}).catch(()=>live&&setData({items:[],total:0,has_more:false})).finally(()=>live&&setBusy(false));return()=>{live=false}},[open,kind,country,subdivision,debounced,offset,value]);useEffect(()=>{if(open&&typeof window!=='undefined'&&window.matchMedia?.('(pointer:fine)').matches)setTimeout(()=>inputRef.current?.focus(),0)},[open]);const items=data.items||[],page=Math.floor(offset/10)+1,pages=Math.max(1,Math.ceil(Number(data.total||0)/10));return <div className="m-filter-select" ref={ref}><button className={`m-filter-button ${value?'has-value':''}`} onClick={()=>setOpen(x=>!x)}><span><small>{label}</small><strong>{selectedLabel||'All'}</strong></span>{busy?<span className="m-spinner tiny"/>:<ChevronDown size={14}/>}</button>{open&&<div className="m-filter-popover"><div className="m-filter-search"><Search size={14}/><input ref={inputRef} value={search} onChange={e=>setSearch(e.target.value)} placeholder={`Search ${label.toLowerCase()}…`}/></div><button className={!value?'selected':''} onClick={()=>{onChange('','All');setSelectedLabel('');setOpen(false);setSearch('');setOffset(0)}}><span>All</span></button>{items.map(x=><button key={String(x.value)} className={String(value)===String(x.value)?'selected':''} onClick={()=>{setSelectedLabel(x.label);onChange(x.value,x.label);setOpen(false);setSearch('');setOffset(0)}}><span>{x.label}</span>{x.meta&&<small>{x.meta}</small>}</button>)}{!items.length&&!busy&&<div className="m-option-empty">No matching options</div>}{Number(data.total||0)>10&&<div className="m-filter-pager"><button disabled={offset===0} onClick={()=>setOffset(o=>Math.max(0,o-10))}>Previous</button><span>{page} / {pages}</span><button disabled={!data.has_more} onClick={()=>setOffset(o=>o+10)}>Next</button></div>}</div>}</div>}
function AsyncPagedFilterSelect({kind,label,value,valueLabel='',onChange,country='',survey=''}){const[open,setOpen]=useState(false),[search,setSearch]=useState(''),[offset,setOffset]=useState(0),[data,setData]=useState({items:[],total:0,has_more:false}),[busy,setBusy]=useState(false),[selectedLabel,setSelectedLabel]=useState(valueLabel);const ref=useRef(null),inputRef=useRef(null),debounced=useDebounce(search,220);useEffect(()=>{const close=e=>{if(ref.current&&!ref.current.contains(e.target))setOpen(false)};addEventListener('mousedown',close);return()=>removeEventListener('mousedown',close)},[]);useEffect(()=>{setOffset(0)},[debounced,country,survey,kind]);useEffect(()=>{if(valueLabel)setSelectedLabel(valueLabel);if(!value)setSelectedLabel('')},[value,valueLabel]);useEffect(()=>{if(!open)return;let live=true;setBusy(true);api.filterOptionPage({kind,country,survey,query:debounced,limit:10,offset}).then(x=>{if(!live)return;setData(x||{items:[],total:0,has_more:false});const hit=(x?.items||[]).find(y=>String(y.value)===String(value));if(hit)setSelectedLabel(hit.label)}).catch(()=>live&&setData({items:[],total:0,has_more:false})).finally(()=>live&&setBusy(false));return()=>{live=false}},[open,kind,country,survey,debounced,offset,value]);useEffect(()=>{if(open&&typeof window!=='undefined'&&window.matchMedia?.('(pointer:fine)').matches)setTimeout(()=>inputRef.current?.focus(),0)},[open]);const items=data.items||[],page=Math.floor(offset/10)+1,pages=Math.max(1,Math.ceil(Number(data.total||0)/10));return <div className="m-filter-select" ref={ref}><button className={`m-filter-button ${value?'has-value':''}`} onClick={()=>setOpen(x=>!x)}><span><small>{label}</small><strong>{selectedLabel||'All'}</strong></span>{busy?<span className="m-spinner tiny"/>:<ChevronDown size={14}/>}</button>{open&&<div className="m-filter-popover"><div className="m-filter-search"><Search size={14}/><input ref={inputRef} value={search} onChange={e=>setSearch(e.target.value)} placeholder={`Search ${label.toLowerCase()}…`}/></div><button className={!value?'selected':''} onClick={()=>{onChange('','All');setSelectedLabel('');setOpen(false);setSearch('');setOffset(0)}}><span>All</span></button>{items.map(x=><button key={String(x.value)} className={String(value)===String(x.value)?'selected':''} onClick={()=>{setSelectedLabel(x.label);onChange(x.value,x.label);setOpen(false);setSearch('');setOffset(0)}}><span>{x.label}</span>{x.meta&&<small>{x.meta}</small>}</button>)}{!items.length&&!busy&&<div className="m-option-empty">No matching options</div>}{Number(data.total||0)>10&&<div className="m-filter-pager"><button disabled={offset===0} onClick={()=>setOffset(o=>Math.max(0,o-10))}>Previous</button><span>{page} / {pages}</span><button disabled={!data.has_more} onClick={()=>setOffset(o=>o+10)}>Next</button></div>}</div>}</div>}

function TriFilter({label,value,onChange}){return <FilterSelect label={label} value={value} onChange={onChange} options={[opt('true','Yes'),opt('false','No')]}/>}function opt(value,label,meta=''){return{value,label,meta}}function FilterChip({label,onRemove}){return <span className="m-filter-chip">{label}<button onClick={onRemove}><X size={12}/></button></span>}

function DataTable({rows,columns,loading,sort,direction,onSort,onRow,selected}){return <div className="m-table-wrap"><table className="m-table"><thead><tr>{columns.map((c,i)=><th key={c.key} className={i===0?'sticky-col':''} style={{minWidth:c.width||120}}><button disabled={!c.sortKey} onClick={()=>onSort(c.sortKey)}>{c.label}{c.sortKey&&sort===c.sortKey&&(direction==='asc'?<ArrowUp size={12}/>:<ArrowDown size={12}/>)}</button></th>)}</tr></thead><tbody>{loading&&rows.length===0?Array.from({length:8}).map((_,i)=><tr key={i}>{columns.map((c,j)=><td className={j===0?'sticky-col':''} key={c.key}><span className="m-row-skeleton"/></td>)}</tr>):rows.length?rows.map((r,i)=><tr key={r.id??r.course_id??i} className={String(selected)===String(r.id??r.course_id)?'selected':''} onClick={()=>onRow?.(r)}>{columns.map((c,j)=><td key={c.key} className={j===0?'sticky-col':''}>{cell(r,c.key)}</td>)}</tr>):<tr><td colSpan={columns.length}><EmptyInline text="No records match the current filters."/></td></tr>}</tbody></table></div>}

function columns(type,complete){if(complete)return[{key:'canonical_title',label:'Course',width:300,sortKey:'course'},{key:'provider_name',label:'Provider',width:240,sortKey:'provider'},{key:'course_code',label:'CRICOS / Course code',width:150},{key:'completeness_score_v2',label:'Readiness',width:120,sortKey:'completeness'},{key:'has_fee',label:'Fee',width:90},{key:'has_intake',label:'Intake',width:90},{key:'has_english',label:'English',width:90},{key:'last_verified_at',label:'Verified',width:150,sortKey:'verified'}];if(type==='provider')return[{key:'canonical_name',label:'Provider',width:300,sortKey:'provider'},{key:'country_code',label:'Country',width:110},{key:'subdivision_name',label:'State / Region',width:160},{key:'city',label:'City',width:150},{key:'course_count',label:'Courses',width:95,sortKey:'courses'},{key:'evidence_count',label:'Evidence',width:95},{key:'lifecycle_status',label:'Lifecycle',width:115},{key:'publication_status',label:'Publication',width:130},{key:'last_verified_at',label:'Verified',width:150,sortKey:'verified'}];if(type==='course')return[{key:'canonical_title',label:'Course',width:310,sortKey:'course'},{key:'provider_name',label:'Provider',width:240,sortKey:'provider'},{key:'course_code',label:'CRICOS / Course code',width:155},{key:'subdivision_name',label:'State / Region',width:150},{key:'level_name',label:'Study level',width:150},{key:'field_of_study',label:'Field',width:190,sortKey:'field'},{key:'fee_amount',label:'CRICOS tuition',width:150,sortKey:'fee'},{key:'completeness_score_v2',label:'Readiness',width:120,sortKey:'completeness'},{key:'last_verified_at',label:'Verified',width:145,sortKey:'verified'}];if(type==='campus')return[{key:'name',label:'Campus',width:270,sortKey:'campus'},{key:'provider_name',label:'Provider',width:260,sortKey:'provider'},{key:'country_code',label:'Country',width:105},{key:'subdivision_name',label:'State / Region',width:160},{key:'city',label:'City',width:150,sortKey:'city'},{key:'course_count',label:'Courses',width:90,sortKey:'courses'},{key:'status',label:'Status',width:110}];return[{key:'name',label:'Scholarship',width:310,sortKey:'scholarship'},{key:'provider_name',label:'Provider',width:250},{key:'scholarship_type',label:'Type',width:170},{key:'audience',label:'Audience',width:150},{key:'award_value_text',label:'Award',width:180},{key:'publication_status',label:'Publication',width:130}]}
function cell(r,key){const v=r[key];if(['canonical_name','canonical_title','name'].includes(key))return <span className="m-cell-title"><strong>{v??'—'}</strong>{r.stable_key&&<small>{r.stable_key}</small>}</span>;if(key==='country_code')return <span>{countryFlag(v)} {v||'—'}</span>;if(key==='course_code')return v?<code className="m-code">{v}</code>:'—';if(key==='fee_amount')return v==null?'—':`${r.fee_currency||''} ${Number(v).toLocaleString()}`.trim();if(key==='completeness_score_v2')return <Score value={v??r.completeness_score}/>;if(['has_fee','has_intake','has_english','has_scholarship'].includes(key))return <Bool value={v}/>;if(key.includes('status')||key==='status')return <Status value={v}/>;if(key.endsWith('_at'))return v?fmtDate(v):'Never';return v==null||v===''?'—':String(v)}
function Score({value}){const n=Math.max(0,Math.min(100,Number(value)||0));return <span className="m-score"><span><i style={{width:`${n}%`}}/></span><b>{Math.round(n)}%</b></span>}
function Bool({value}){return <span className={`m-bool ${value?'yes':'no'}`}>{value?'Yes':'No'}</span>}
function Status({value}){const s=String(value??'unknown').toLowerCase();return <span className={`m-status status-${statusTone(s)}`}>{humanise(s)}</span>}
function statusTone(s){if(['completed','succeeded','published','active','resolved','captured'].includes(s))return'success';if(['failed','error','rejected','blocked'].includes(s))return'danger';if(['running','processing','queued','pending','in_review'].includes(s))return'info';if(['open','draft','review','warning'].includes(s))return'warning';return'neutral'}

function Pager({offset,limit,total,onOffset}){const page=Math.floor(offset/limit)+1,pages=Math.max(1,Math.ceil(total/limit));return <div className="m-pager"><span>Page <strong>{page}</strong> of {pages} · {fmtNumber(total)} records</span><div><button disabled={offset<=0} onClick={()=>onOffset(Math.max(0,offset-limit))}>Previous</button><button disabled={offset+limit>=total} onClick={()=>onOffset(offset+limit)}>Next</button></div></div>}

function DetailDrawer({type,data,busy,onClose,navigate}){useEffect(()=>{const k=e=>e.key==='Escape'&&onClose();addEventListener('keydown',k);return()=>removeEventListener('keydown',k)},[onClose]);return <><button className="m-drawer-backdrop" onClick={onClose}/><aside className={"m-drawer m-drawer-"+type} aria-label={humanise(type)+" detail"}><div className="m-drawer-head"><div><small>{humanise(type)} detail</small><h2>{detailTitle(data,type)}</h2></div><div style={{display:'flex',gap:6}}>{data?.id&&['provider','course'].includes(type)&&<button title={`Compare this ${type}`} onClick={()=>navigate?.('Compare',{type,ids:data.id})}><Activity size={17}/></button>}{data?.id&&['provider','course','campus','scholarship'].includes(type)&&<button title="Open supporting evidence" onClick={()=>navigate?.('Evidence',{entity_type:type,entity_id:data.id})}><BookOpen size={17}/></button>}<button onClick={onClose} aria-label={"Close "+humanise(type)+" detail"}><X size={18}/></button></div></div><div className="m-drawer-content">{busy?<div className="m-drawer-loading"><span className="m-spinner"/>Loading governed detail…</div>:<DetailBody type={type} data={data} navigate={navigate}/>}</div></aside></>}
function detailTitle(d,type){if(!d)return'Loading…';return d.display_title||d.canonical_title||d.canonical_name||d.name||d.stable_key||humanise(type)}
function InternationalContacts({data,navigate}){const block=data?.international_contacts||{},items=Array.isArray(block.items)?block.items:[],events=Array.isArray(block.events)?block.events:[],summary=block.summary||{},profile=block.profile||{},disposition=block.disposition||{};return <section className="m-detail-section cf-contact-intel"><style>{`
.cf-contact-intel{display:grid;gap:10px}.cf-contact-head{display:flex;justify-content:space-between;gap:12px;align-items:flex-start}.cf-contact-head h3{margin:0;font-size:13px}.cf-contact-head p{margin:4px 0 0;color:#64748b;font-size:10px;line-height:1.45}.cf-contact-summary{display:flex;gap:6px;flex-wrap:wrap}.cf-contact-summary span{border:1px solid #e2e8f0;background:#f8fafc;border-radius:999px;padding:4px 7px;font-size:9px;color:#475569;font-weight:750}.cf-contact-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}.cf-contact-card{border:1px solid #e2e8f0;border-radius:10px;background:#fff;padding:10px;display:grid;gap:7px}.cf-contact-card.primary{border-color:#c7d2fe;background:#fafaff}.cf-contact-top{display:flex;justify-content:space-between;gap:8px;align-items:flex-start}.cf-contact-name{display:grid;gap:2px}.cf-contact-name strong{font-size:12px;color:#0f172a}.cf-contact-name small{font-size:9px;color:#64748b}.cf-contact-badge{white-space:nowrap;border-radius:999px;padding:3px 6px;font-size:8px;font-weight:850;background:#eef2ff;color:#4338ca}.cf-contact-badge.enriched{background:#f1f5f9;color:#475569}.cf-contact-territory{display:grid;gap:2px;padding:7px 8px;border-radius:8px;background:#f8fafc}.cf-contact-territory small{font-size:8px;text-transform:uppercase;letter-spacing:.04em;color:#94a3b8;font-weight:800}.cf-contact-territory strong{font-size:10px;color:#334155;line-height:1.45}.cf-contact-links{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.cf-contact-links a{font-size:9px;color:#4f46e5;text-decoration:none}.cf-contact-meta{font-size:8px;color:#94a3b8;line-height:1.4}.cf-contact-changes{border-top:1px solid #eef2f7;padding-top:8px}.cf-contact-changes strong{font-size:9px;color:#475569}.cf-contact-changes span{display:block;font-size:8px;color:#64748b;margin-top:3px}@media(max-width:760px){.cf-contact-grid{grid-template-columns:1fr}.cf-contact-head{display:grid}.cf-contact-summary{justify-content:flex-start}}
`}</style><div className="cf-contact-head"><div><h3>International contacts</h3><p>First-party university contacts are preferred. Licensed professional enrichment is secondary and does not overwrite university-published assignments.</p></div><div className="cf-contact-summary"><span>{humanise(disposition.disposition||'pending_acquisition')}</span><span>{Number(summary.first_party_contacts||0)} first-party</span><span>{Number(summary.enriched_contacts||0)} enriched</span>{Number(summary.unacknowledged_changes||0)>0&&<span>{summary.unacknowledged_changes} change signal{Number(summary.unacknowledged_changes)===1?'':'s'}</span>}</div></div>{!items.length&&disposition.disposition&&<div className="cf-contact-meta">A16 disposition: <strong>{humanise(disposition.disposition)}</strong>. Qualified first-party evidence is retained; missing contacts are never manufactured.</div>}{items.length?<div className="cf-contact-grid">{items.map((x,i)=><article key={x.id||i} className={`cf-contact-card ${x.source_class==='first_party'?'primary':''}`}><div className="cf-contact-top"><div className="cf-contact-name"><strong>{x.full_name||x.team_name||'International team'}</strong><small>{x.job_title||x.team_name||'Professional contact'}</small></div><span className={`cf-contact-badge ${x.source_class==='licensed_enrichment'?'enriched':''}`}>{x.source_class==='first_party'?'First-party university':'Licensed enrichment'}</span></div>{x.territory_text&&<div className="cf-contact-territory"><small>Territory / market</small><strong>{x.territory_text}</strong></div>}<div className="cf-contact-links">{x.work_email&&<a href={`mailto:${x.work_email}`}>{x.work_email}</a>}{x.work_phone&&<a href={`tel:${String(x.work_phone).replace(/[^+0-9]/g,'')}`}>{x.work_phone}</a>}{x.source_url&&<a href={x.source_url} target="_blank" rel="noreferrer">University source <ExternalLink size={9}/></a>}{x.professional_profile_url&&<a href={x.professional_profile_url} target="_blank" rel="noreferrer">Professional profile <ExternalLink size={9}/></a>}{x.evidence_id&&<EvidenceButton id={x.evidence_id} navigate={navigate}/>}</div><div className="cf-contact-meta">{x.source_provider?humanise(x.source_provider):'Source retained'} · Verified {x.last_verified_at?fmtDate(x.last_verified_at):'—'}{x.verification_state&&` · ${humanise(x.verification_state)}`}</div>{x.layer4&&<details><summary style={{fontSize:9,fontWeight:800,cursor:'pointer'}}>Layer 4 resolve</summary><Layer4Intervention type="provider_contact" data={x} publicationEnabled={false}/></details>}</article>)}</div>:<EmptyInline text={profile.enabled===false?'Contact discovery is disabled for this Provider.':'No current international recruitment contact has been verified yet.'}/>} {events.length>0&&<div className="cf-contact-changes"><strong>Recent contact signals</strong>{events.slice(0,3).map((e,i)=><span key={e.id||i}>{humanise(e.event_type)} · {e.detected_at?fmtDate(e.detected_at):'—'}</span>)}</div>}</section>}

function DetailBody({type,data,navigate}){if(!data)return <EmptyInline text="No detail returned."/>;if(type==='course')return <div><CourseDetailPolish data={data} navigate={navigate}/><div className="m-drawer-body" style={{paddingTop:0}}><CourseScholarships data={data.course_scholarships} navigate={navigate}/><Layer4Intervention type={type} data={data}/></div></div>;const scalars=Object.entries(data).filter(([,v])=>v==null||['string','number','boolean'].includes(typeof v)).slice(0,24);return <div className="m-drawer-body"><div className="m-detail-grid">{scalars.map(([k,v])=><div key={k}><small>{humanise(k)}</small><strong>{formatScalar(k,v)}</strong></div>)}</div>{type==='provider'&&<InternationalContacts data={data} navigate={navigate}/>} {type==='provider'&&<ContextualInsights data={data.contextual_insights} navigate={navigate} entityType="provider"/>}{['provider','campus','scholarship'].includes(type)&&<Layer4Intervention type={type} data={data}/>}<ObjectSections data={data} exclude={type==='provider'?['contextual_insights','international_contacts','layer4','layer4_publication']:['layer4','layer4_publication']} navigate={navigate}/></div>}

function CourseScholarships({data,navigate}){
 const items=Array.isArray(data?.items)?data.items:[]
 return <section className="m-detail-section"><h3>Scholarships</h3><p className="m-help">Course applicability is shown only from explicit governed Scholarship scopes. Provider ownership alone is not treated as Course eligibility.</p>
  {items.length?<div className="m-record-list">{items.map(x=><div className="m-record" key={x.mapping_id||x.scholarship_id}><strong>{x.name}</strong><span>{x.award_value_text||'Award value not published'}{x.academic_year?' · '+x.academic_year:''}</span><small>{humanise(x.mapping_basis||'governed mapping')} · {humanise(x.mapping_state||'mapped')}</small><div>{x.source_url&&<a href={x.source_url} target="_blank" rel="noreferrer">Official Scholarship source <ExternalLink size={11}/></a>}{x.evidence_id&&<EvidenceButton id={x.evidence_id} navigate={navigate}/>}</div></div>)}</div>:<EmptyInline text={data?.state==='needs_review'?'Scholarship candidates require governed review before Course mapping.':'No governed Scholarship mapping for this Course.'}/>}
 </section>
}

function CourseSemantics({data,navigate}){const fees=data.fee_summary||{},cricos=fees.cricos_registered||[],provider=fees.provider_current||[];return <><section className="m-detail-section"><h3>Fee semantics</h3><p className="m-help">CRICOS registered total-course values are kept separate from Provider-current published fees. Evidence links open the exact supporting artifact.</p><div className="m-semantic-grid"><div><small>CRICOS registered rows</small><strong>{cricos.length}</strong>{cricos.slice(0,4).map((x,i)=><span key={i}>{humanise(x.fee_type)} · {x.currency||x.currency_code||''} {x.amount==null?'—':Number(x.amount).toLocaleString()} · {humanise(x.basis)} {evidenceIdOf(x)&&<EvidenceButton id={evidenceIdOf(x)} navigate={navigate}/>}</span>)}</div><div><small>Provider-current rows</small><strong>{provider.length}</strong>{provider.length?provider.slice(0,4).map((x,i)=><span key={i}>{humanise(x.fee_type)} · {x.currency||x.currency_code||''} {x.amount==null?'—':Number(x.amount).toLocaleString()} {evidenceIdOf(x)&&<EvidenceButton id={evidenceIdOf(x)} navigate={navigate}/>}</span>):<span>No Provider-current fee observation.</span>}</div></div></section>{data.state_summary&&<KeyObject title="Publication & Search state" value={data.state_summary} navigate={navigate}/>} {data.entry_summary&&<KeyObject title="Intakes & English" value={data.entry_summary} navigate={navigate}/>} {data.taxonomy_summary&&<KeyObject title="Taxonomy lineage" value={data.taxonomy_summary} navigate={navigate}/>}</>}
function ObjectSections({data,exclude=[],navigate}){return <>{Object.entries(data).filter(([k,v])=>!exclude.includes(k)&&v&&typeof v==='object').map(([k,v])=><KeyObject key={k} title={humanise(k)} value={v} navigate={navigate}/>)}</>}
function KeyObject({title,value,navigate}){const arr=Array.isArray(value)?value:null;return <section className="m-detail-section"><h3>{title}</h3>{arr?<div className="m-record-list">{arr.length?arr.slice(0,25).map((x,i)=><Record key={x?.id||i} value={x} navigate={navigate}/>):<EmptyInline text="No records."/>}</div>:<div className="m-kv-list">{Object.entries(value||{}).slice(0,30).map(([k,v])=><div key={k}><span>{humanise(k)}</span><strong>{typeof v==='object'?summarise(v):formatScalar(k,v)}</strong>{typeof v==='object'&&evidenceIdOf(v)&&<EvidenceButton id={evidenceIdOf(v)} navigate={navigate}/>}</div>)}</div>}</section>}
function Record({value,navigate}){if(value==null)return null;if(typeof value!=='object')return <div className="m-record"><span>{String(value)}</span></div>;const title=value.title||value.name||value.canonical_title||value.source_label||value.evidence_type||value.status||value.code||value.id;return <div className="m-record"><strong>{title||'Record'}</strong><span>{Object.entries(value).filter(([k,v])=>k!=='id'&&v!=null&&typeof v!=='object').slice(0,4).map(([k,v])=>`${humanise(k)}: ${formatScalar(k,v)}`).join(' · ')}</span>{evidenceIdOf(value)&&<EvidenceButton id={evidenceIdOf(value)} navigate={navigate}/>}</div>}
function evidenceIdOf(v){return v?.evidence_id||v?.evidence?.id||v?.source_evidence_id||null}
function EvidenceButton({id,navigate}){return <button className="m-secondary compact" style={{marginLeft:6,padding:'3px 6px',fontSize:8}} onClick={e=>{e.stopPropagation();navigate?.('Evidence',{evidence_id:id})}}><BookOpen size={11}/>Evidence</button>}

function Completeness({onError,navigate}){return <Catalogue type="course" onError={onError} navigate={navigate} completenessMode/>}
function CompletenessSummary({onError}){const[all,setAll]=useState(null),[ready,setReady]=useState(null);useEffect(()=>{Promise.all([adminRead('courses_page',{limit:1,offset:0}),adminRead('courses_page',{limit:1,offset:0,min_completeness:100})]).then(([a,r])=>{setAll(Number(a?.total||0));setReady(Number(r?.total||0))}).catch(e=>onError(e.message))},[]);const needs=all==null||ready==null?null:Math.max(0,all-ready);return <div className="m-summary-strip"><SummaryCard icon={CheckCircle2} label="100% core presence" value={all?`${Math.round(ready/all*100)}%`:'—'} tone="green"/><SummaryCard icon={AlertTriangle} label="Needs enrichment" value={needs==null?'—':fmtNumber(needs)} tone="amber"/><SummaryCard icon={GraduationCap} label="Catalogue Courses" value={all==null?'—':fmtNumber(all)} tone="blue"/><div className="m-summary-note"><strong>Readiness is a coverage signal.</strong><span>It does not approve, publish or override source evidence.</span></div></div>}
function SummaryCard({icon:Icon,label,value,tone}){return <div className={`m-summary-card tone-${tone}`}><Icon size={18}/><div><small>{label}</small><strong>{value}</strong></div></div>}

function Qilt({onError}){return <InsightWorkspace kind="qilt" onError={onError}/>}function Prisms({onError}){return <InsightWorkspace kind="prisms" onError={onError}/>} 
function InsightWorkspace({kind,onError}){const[filters,setFilters]=useState({}),[filterLabels,setFilterLabels]=useState({}),[options,setOptions]=useState({}),[data,setData]=useState(null),[busy,setBusy]=useState(false),[offset,setOffset]=useState(0),[query,setQuery]=useState('');useEffect(()=>{const p=kind==='qilt'?api.qiltFilterOptions(filters.survey||''):api.prismsFilterOptions();p.then(setOptions).catch(e=>onError(e.message))},[kind,filters.survey]);const debounced=useDebounce(query,280);useEffect(()=>{setBusy(true);const p=kind==='qilt'?api.qiltPage({limit:PAGE_SIZE,offset,query:debounced,survey:filters.survey||'',metric:filters.metric||'',provider:filters.provider||'',status:filters.status||'',year:filters.year||'',sort:'provider',direction:'asc'}):api.prismsPage({limit:PAGE_SIZE,offset,query:debounced,subdivision:filters.subdivision||'',studyArea:filters.studyArea||'',sector:filters.sector||'',remoteness:filters.remoteness||'',suppressed:filters.suppressed===''?null:filters.suppressed==='true'});p.then(setData).catch(e=>onError(e.message)).finally(()=>setBusy(false))},[kind,offset,debounced,JSON.stringify(filters)]);useEffect(()=>setOffset(0),[debounced,JSON.stringify(filters)]);const rows=rowsOf(data),total=Number(data?.total??rows.length);function patch(k,v,label=''){setFilters(f=>{const n={...f,[k]:v};if(kind==='qilt'&&k==='survey'){n.metric='';n.provider=''}return n});setFilterLabels(l=>{const n={...l,[k]:label||''};if(kind==='qilt'&&k==='survey'){delete n.metric;delete n.provider}return n})}const qiltDefs=[['survey','Survey',options.surveys],['year','Year',options.years],['status','Status',options.statuses]],prismsDefs=[['subdivision','State / Region',options.subdivisions],['sector','Sector',options.sectors],['remoteness','Remoteness',options.remoteness_areas]];return <div className="m-page-stack"><section className="m-panel"><div className="m-workspace-head"><div><h2>{kind==='qilt'?'QILT outcomes':'PRISMS student flow'}</h2><p>Structured Layer 2 observations remain separate from canonical identity.</p></div><div className="m-result-count"><strong>{fmtNumber(total)}</strong><span>matching</span></div></div><div className="m-search-row"><label className="m-searchbox"><Search size={16}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search governed observations…"/></label></div><div className="m-filter-bar">{kind==='qilt'?<><FilterSelect label="Survey" value={filters.survey||''} onChange={(v,l)=>patch('survey',v,l)} options={normaliseOptions(options.surveys)}/><AsyncPagedFilterSelect kind="qilt_metric" label="Metric" value={filters.metric||''} valueLabel={filterLabels.metric||''} survey={filters.survey||''} onChange={(v,l)=>patch('metric',v,l)}/><AsyncPagedFilterSelect kind="qilt_provider" label="Provider" value={filters.provider||''} valueLabel={filterLabels.provider||''} survey={filters.survey||''} onChange={(v,l)=>patch('provider',v,l)}/><FilterSelect label="Year" value={filters.year||''} onChange={(v,l)=>patch('year',v,l)} options={normaliseOptions(options.years)}/><FilterSelect label="Status" value={filters.status||''} onChange={(v,l)=>patch('status',v,l)} options={normaliseOptions(options.statuses)}/></>:<><FilterSelect label="State / Region" value={filters.subdivision||''} onChange={(v,l)=>patch('subdivision',v,l)} options={normaliseOptions(options.subdivisions)}/><AsyncPagedFilterSelect kind="prisms_study_area" label="Study area" value={filters.studyArea||''} valueLabel={filterLabels.studyArea||''} onChange={(v,l)=>patch('studyArea',v,l)}/><FilterSelect label="Sector" value={filters.sector||''} onChange={(v,l)=>patch('sector',v,l)} options={normaliseOptions(options.sectors)}/><FilterSelect label="Remoteness" value={filters.remoteness||''} onChange={(v,l)=>patch('remoteness',v,l)} options={normaliseOptions(options.remoteness)}/></>}</div><DynamicTable rows={rows} loading={busy}/><Pager offset={offset} limit={PAGE_SIZE} total={total} onOffset={setOffset}/></section></div>}



function OperationalList({operation,title,onError}){const[data,setData]=useState(null),[busy,setBusy]=useState(true),[query,setQuery]=useState('');useEffect(()=>{setBusy(true);adminRead(operation,{limit:200,offset:0,query:query||null}).then(setData).catch(e=>onError(e.message)).finally(()=>setBusy(false))},[operation,query]);const rows=rowsOf(data);return <div className="m-page-stack"><section className="m-panel"><div className="m-workspace-head"><div><h2>{title}</h2><p>Role-checked operational data; sensitive internal schemas remain private.</p></div><div className="m-result-count"><strong>{fmtNumber(data?.total??rows.length)}</strong><span>records</span></div></div><div className="m-search-row"><label className="m-searchbox"><Search size={16}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder={`Search ${title.toLowerCase()}…`}/></label></div><DynamicTable rows={rows} loading={busy}/></section></div>}

function Attributes({onError}){const[data,setData]=useState(null),[busy,setBusy]=useState(true);useEffect(()=>{adminRead('attributes',{limit:200}).then(setData).catch(e=>onError(e.message)).finally(()=>setBusy(false))},[]);if(busy)return <div className="m-skeleton panel tall"/>;const groups=[['Families',data?.families,Layers3],['Groups',data?.groups,Tags],['Attributes',data?.attributes,SlidersHorizontal],['Options',data?.options,ListChecks],['Completeness profiles',data?.completeness_profiles,CheckCircle2]];return <div className="m-page-stack"><div className="m-summary-strip attributes">{groups.map(([label,rows,Icon])=><SummaryCard key={label} icon={Icon} label={label} value={fmtNumber(rows?.length||0)} tone="indigo"/>)}</div>{groups.map(([label,rows,Icon])=><section className="m-panel" key={label}><PanelTitle icon={Icon} title={label} subtitle={`Governed PIM ${label.toLowerCase()} configuration`}/><DynamicTable rows={rows||[]} loading={false}/></section>)}</div>}

function DynamicTable({rows,loading}){const cols=useMemo(()=>dynamicColumns(rows),[rows]);return <div className="m-table-wrap"><table className="m-table dynamic"><thead><tr>{cols.map((c,i)=><th key={c} className={i===0?'sticky-col':''}><span>{humanise(c)}</span></th>)}</tr></thead><tbody>{loading&&rows.length===0?Array.from({length:6}).map((_,i)=><tr key={i}>{Array.from({length:Math.max(cols.length,5)}).map((_,j)=><td key={j}><span className="m-row-skeleton"/></td>)}</tr>):rows.length?rows.map((r,i)=><tr key={r.id??i}>{cols.map((c,j)=><td key={c} className={j===0?'sticky-col':''}>{genericCell(c,r[c])}</td>)}</tr>):<tr><td colSpan={Math.max(cols.length,1)}><EmptyInline text="No governed records are currently available."/></td></tr>}</tbody></table></div>}
function dynamicColumns(rows){if(!rows?.length)return['status'];const priority=['name','title','source_label','job_type','domain','status','country_code','provider_name','course_title','evidence_type','priority','created_at','updated_at','captured_at'];const keys=Object.keys(rows[0]).filter(k=>!['payload','result','metadata','content'].includes(k)&&typeof rows[0][k]!=='object');return[...priority.filter(k=>keys.includes(k)),...keys.filter(k=>!priority.includes(k))].slice(0,11)}
function genericCell(k,v){if(v==null||v==='')return'—';if(k.includes('status')||k==='status')return <Status value={v}/>;if(k.endsWith('_at'))return fmtDateTime(v);if(k==='country_code')return `${countryFlag(v)} ${v}`;if(k==='id'||k.endsWith('_id'))return <code className="m-code subtle">{String(v).slice(0,8)}…</code>;return String(v)}

function EmptyState({icon:Icon,title,text}){return <div className="m-empty-state"><span><Icon size={24}/></span><h2>{title}</h2><p>{text}</p></div>}
function EmptyInline({text}){return <div className="m-empty-inline"><Database size={18}/><span>{text}</span></div>}

function useDebounce(value,delay){const[v,setV]=useState(value);useEffect(()=>{const t=setTimeout(()=>setV(value),delay);return()=>clearTimeout(t)},[value,delay]);return v}
function rowsOf(data){if(Array.isArray(data))return data;return data?.items??data?.rows??data?.data??[]}
function normaliseOptions(list){if(!Array.isArray(list))return[];return list.map(x=>{if(x==null)return null;if(typeof x!=='object')return opt(String(x),humanise(x));const value=x.id??x.code??x.value??x.name??x.label;return opt(String(value),x.name??x.label??humanise(value),x.code&&x.code!==value?x.code:'')}).filter(Boolean)}
function humanise(v){if(v==null)return'—';return String(v).replace(/[_-]+/g,' ').replace(/\b\w/g,m=>m.toUpperCase())}
function fmtNumber(v){const n=Number(v);return Number.isFinite(n)?n.toLocaleString():'—'}
function fmtDate(v){const d=new Date(v);return Number.isNaN(+d)?String(v):d.toLocaleDateString(undefined,{day:'2-digit',month:'short',year:'numeric'})}
function fmtDateTime(v){const d=new Date(v);return Number.isNaN(+d)?String(v):d.toLocaleString(undefined,{day:'2-digit',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'})}
function relativeTime(v){const d=new Date(v);if(Number.isNaN(+d))return'unknown';const s=Math.round((Date.now()-d.getTime())/1000),a=Math.abs(s);if(a<60)return'just now';if(a<3600)return`${Math.round(a/60)}m ago`;if(a<86400)return`${Math.round(a/3600)}h ago`;if(a<604800)return`${Math.round(a/86400)}d ago`;return fmtDate(v)}
function countryFlag(code){const c=String(code||'').toUpperCase();if(c.length!==2)return'';return String.fromCodePoint(...[...c].map(x=>127397+x.charCodeAt()))}
function formatScalar(k,v){if(v==null||v==='')return'—';if(typeof v==='boolean')return v?'Yes':'No';if(k.endsWith('_at')||k==='valid_from'||k==='valid_to')return fmtDateTime(v);if(typeof v==='number')return v.toLocaleString();return String(v)}
function summarise(v){if(Array.isArray(v))return`${v.length} record${v.length===1?'':'s'}`;return`${Object.keys(v||{}).length} fields`}

createRoot(document.getElementById('root')).render(<React.StrictMode><App/></React.StrictMode>)