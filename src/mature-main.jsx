import React,{useEffect,useMemo,useRef,useState}from'react'
import{createRoot}from'react-dom/client'
import{
  Activity,AlertTriangle,ArrowDown,ArrowUp,ArrowLeftRight,BarChart3,BookOpen,Building2,CheckCircle2,ChevronDown,
  CircleGauge,ClipboardCheck,Database,FileCheck2,Filter,GraduationCap,History,LayoutDashboard,
  ListChecks,LogOut,Menu,RefreshCw,Search,SearchCheck,Settings2,SlidersHorizontal,Sparkles,
  ShieldCheck,Tags,UsersRound,Workflow,X,Zap,MapPin,Layers3,Clock3,PanelLeftClose,PanelLeftOpen,ExternalLink,HeartPulse,Plug,BrainCircuit,Plus,Pencil,Link2
}from'lucide-react'
import{fmtDate,fmtDateTime,fmtMoney,fmtPercent,fmtShare}from'./lib/format.js'
import{adminRead,api,supabase}from'./lib/supabase'
import RegulatorySettings from'./RegulatorySettings'
import EvidenceWorkspace from'./EvidenceWorkspace'
import CourseDetailPolish from'./CourseDetailPolish'
import{CourseEditor,ProviderEditor,CreateRecord}from'./RecordEditor'
import ScholarshipLinks from'./ScholarshipLinks'
import FeeRules from'./FeeRules'
import ModelsServices from'./ModelsServices'
import ListEdit from'./ListEdit'
import StatisticsDatasets from'./StatisticsDatasets'
import ProviderOnboarding from'./layer2-provider-onboarding'
import DashboardHome from'./Dashboard'
import ReferenceSources from'./ReferenceSources'
import KeyDates from'./KeyDates'
import ContextualInsights from'./ContextualInsights'
import ComparisonWorkspace from'./ComparisonWorkspace'
import ProviderContactsWorkspace from'./ProviderContactsWorkspace'
import ProviderLogo,{ProviderBrand}from'./ProviderLogo'
import{fmtNumber,PanelTitle,Pulse,SummaryCard,EmptyState,EmptyInline,Pager,useRememberedState,StatusChip,FilterChip,PageHeader,PageLayout,StatusDot}from'./ui-kit'
import{PAGES,SECTIONS,SECTION_OF,resolveTarget,hrefFor,canOpen,allowedTabs,effectiveTab}from'./nav-map'
import PlatformHealth,{readPlatformHealth,healthTone,HEALTH_WORDS}from'./PlatformHealth'
import Layer3Operations from'./Layer3Operations'
import FlaggedValues from'./FlaggedValues'
import Automations from'./Automations'
import SendBackToAI from'./SendBackToAI'
import ScholarshipPublishing from'./ScholarshipPublishing'
import PriorityQueue from'./PriorityQueue'
import SourceComparison from'./SourceComparison'
import{DomainReadiness}from'./data-quality-entry'
import{CoverageView}from'./course-coverage'
import LinkRefresh from'./LinkRefresh'
import FeeSchedules from'./FeeSchedules'
import{ProviderRankings,RankingLinkPicker}from'./RankingLinks'
import ScholarshipEligibility from'./ScholarshipEligibility'
import LiveActivity from'./LiveActivity'
import PlatformGuide from'./PlatformGuide'
import Layer4Intervention from'./Layer4Intervention'
import{Layer1Operations,Layer1SourceSettings}from'./layer1-operations-entry'
import{Workspace as Layer2Workspace}from'./layer2-operations-entry'
import{Layer3 as Layer3Workspace,Layer4 as Layer4Workspace,Refresh as RefreshWorkspace,Onboarding as OnboardingWorkspace}from'./m2-3-intelligence-entry'
import{Console as Layer2SourceConfig}from'./layer2-platform-entry'
import{Console as Layer2ProviderConfig}from'./layer2-provider-entry'
import{ScholarshipSelectionWorkspace}from'./scholarship-selection-entry'
import PlatformMaturity from'./platform-maturity-entry'
import EnvironmentMigrationWorkspace from'./EnvironmentMigrationWorkspace'
import{AccessRolesEmbedded}from'./access-roles-entry'
import{JobsWorkspace,SourcesWorkspace}from'./pipeline-ops-entry'
import'./styles.css'
import'./mature.css'
import'./admin-pages.css'

// Decision 217: the attributes view and the fee schedules below it share the Coverage country and university filter
function CoverageAttributes({rank}){
  const[scope,setScope]=useState({country:'',provider:null})
  return <div className="m-page-stack"><CoverageView view="attributes" onScope={setScope}/><details className="m-admin-advanced cov-by-area"><summary>By area: providers, courses, campuses and scholarships</summary><DomainReadiness rank={rank}/></details>{rank>=4&&<FeeSchedules country={scope.country} provider={scope.provider}/>}</div>
}

const UI_VERSION='2.15.78'
const UI_FIXES=[
 'Independent QILT, PRISMS, QS and THE year/edition controls in Provider Compare.',
 'Frozen Provider/university identity headers across comparison statistics and rankings.',
 'Standard Statistics & Rankings breadcrumbs with dedicated QILT, PRISMS, QS and THE dataset subpages.',
 'QS/THE dataset pages aligned to the standard CourseFinder dataset table theme.'
]
const PAGE_SIZE=50
const rankingYearOptions=system=>system==='qs_wur'?[2026,2027,...Array.from({length:11},(_,i)=>2025-i)]:system==='the_wur'?Array.from({length:16},(_,i)=>2026-i):Array.from({length:12},(_,i)=>2026-i)
const rankingDefaultYear=system=>rankingYearOptions(system)[0]
const rankingPublisherName=system=>system==='the_wur'?'Times Higher Education':system==='arwu'?'ShanghaiRanking Consultancy':'QS Quacquarelli Symonds'
// v2.15.121: ranking publisher addresses come from Reference sources (use "Ranking publisher", by ranking key), not code.
let RANKING_SOURCES={}
const rankingSourceUrl=system=>RANKING_SOURCES[system]||''
async function loadRankingSources(){try{const{data}=await supabase.rpc('admin_reference_sources_read');RANKING_SOURCES=Object.fromEntries((data?.items||[]).filter(x=>x.ref_key&&x.enabled&&!x.retired&&(x.uses||[]).includes('ranking_publisher')).map(x=>[x.ref_key,x.url]))}catch{}return RANKING_SOURCES}
const STATUS_OPTIONS=['active','inactive','suspended','retired','unknown'].map(x=>({value:x,label:humanise(x)}))
const PUBLICATION_OPTIONS=['published','unpublished','draft','review','archived'].map(x=>({value:x,label:humanise(x)}))

// v2.15.107: the menu, page titles, tabs, role gates and old-address redirects all come from nav-map.js.
const ICONS={dashboard:LayoutDashboard,course:GraduationCap,provider:Building2,scholarship:Sparkles,chart:BarChart3,check:CheckCircle2,database:Database,activity:Activity,ai:BrainCircuit,review:ListChecks,health:HeartPulse,workflow:Workflow,book:BookOpen,plug:Plug,sliders:SlidersHorizontal,shield:ShieldCheck,tags:Tags,users:UsersRound,guide:BookOpen}

function routeFromHash(){
  const raw=location.hash.replace(/^#/,'');const[route,query='']=raw.split('?')
  const r=resolveTarget(route||'dashboard',new URLSearchParams(query))
  // Old addresses keep working: show the new page and quietly replace the address with the new one.
  const canonical=hrefFor(r.page,r.tab,Object.fromEntries(r.params))
  if(raw&&`#${raw}`!==canonical)history.replaceState(null,'',canonical)
  return r
}

function pageBreadcrumbs(pageKey,tab,routeParams){
  if(pageKey==='dashboard')return[]
  const page=PAGES[pageKey],crumbs=[{label:'Home',page:'dashboard'}],section=SECTION_OF[pageKey]
  if(section)crumbs.push({label:section})
  crumbs.push({label:page.label,page:pageKey})
  const t=page.tabs?.find(x=>x.key===tab)
  if(t&&page.tabs[0].key!==t.key)crumbs.push({label:t.label})
  const dataset=routeParams?.get?.('dataset')||''
  if(pageKey==='rankings'&&(dataset==='qs_wur'||dataset==='the_wur'))crumbs.push({label:dataset==='qs_wur'?'QS':'THE'})
  return crumbs
}

function AppBreadcrumbs({pageKey,tab,routeParams,navigate}){
 const crumbs=pageBreadcrumbs(pageKey,tab,routeParams)
 if(!crumbs.length)return null
 return <nav className="m-breadcrumbs" aria-label="Breadcrumb">{crumbs.map((x,i)=><React.Fragment key={x.label+i}><button disabled={!x.page||i===crumbs.length-1} onClick={()=>x.page&&navigate(x.page)}>{x.label}</button>{i<crumbs.length-1&&<span>/</span>}</React.Fragment>)}</nav>
}

class WorkspaceErrorBoundary extends React.Component{
  constructor(props){super(props);this.state={error:null}}
  static getDerivedStateFromError(error){return{error}}
  componentDidCatch(error,info){console.error('CourseFinder workspace render failed',error,info);this.props.onError?.(`Workspace render failed: ${error?.message||String(error)}`)}
  componentDidUpdate(prev){if(prev.routeKey!==this.props.routeKey&&this.state.error)this.setState({error:null})}
  render(){if(!this.state.error)return this.props.children;return <section className="m-workspace-error m-panel" role="alert"><PanelTitle icon={AlertTriangle} title="Workspace could not render" subtitle="The Administration shell remains available. Navigate to another section or retry this workspace."/><div className="m-alert compact"><AlertTriangle size={15}/><span>{this.state.error?.message||'Unexpected workspace render error'}</span></div><button className="m-primary" onClick={this.props.onRecover}>Return to Dashboard</button></section>}
}

function App(){
  const[session,setSession]=useState(null),[booting,setBooting]=useState(true),[context,setContext]=useState(null)
  const initialRoute=routeFromHash()
  const[route,setRoute]=useState(initialRoute),[error,setError]=useState(''),[navOpen,setNavOpen]=useState(false),[collapsed,setCollapsed]=useState(false),[health,setHealth]=useState(undefined)
  const mainRef=useRef(null)
  useEffect(()=>{
    supabase.auth.getSession().then(({data})=>{setSession(data.session??null);setBooting(false)})
    const{data}=supabase.auth.onAuthStateChange((_event,next)=>setSession(next));return()=>data.subscription.unsubscribe()
  },[])
  useEffect(()=>{if(!session){setContext(null);return}api.context().then(setContext).catch(e=>setError(e.message))},[session])
  useEffect(()=>{const h=()=>setRoute(routeFromHash());addEventListener('hashchange',h);return()=>removeEventListener('hashchange',h)},[])
  const rank=Number(context?.role_rank||0)
  // Top-bar health dot: read once after sign-in and every five minutes.
  useEffect(()=>{if(!session||!canOpen('health',rank))return;let live=true;const read=()=>readPlatformHealth().then(h=>{if(live)setHealth(h)});read();const t=setInterval(read,300000);return()=>{live=false;clearInterval(t)}},[session,rank])
  function go(target,params={}){
    const r=resolveTarget(target,new URLSearchParams(Object.entries(params||{}).filter(([,v])=>v!==''&&v!=null).map(([k,v])=>[k,String(v)])))
    const next=hrefFor(r.page,r.tab,Object.fromEntries(r.params))
    setRoute(r);if(location.hash!==next)location.hash=next;setNavOpen(false);requestAnimationFrame(()=>{if(mainRef.current)mainRef.current.scrollTop=0})
  }
  if(booting)return <div className="m-boot"><div className="m-loader"/><span>Loading Coursefinder Admin…</span></div>
  if(!session)return <Login onError={setError} error={error}/>
  const pageKey=route.page,page=PAGES[pageKey]||PAGES.dashboard,tab=effectiveTab(pageKey,route.tab,rank)
  const tone=health===undefined?'unknown':healthTone(health?.overall)
  const healthLabel=health===undefined?'Checking platform health':HEALTH_WORDS[tone]
  return <div className={`m-shell ${collapsed?'is-collapsed':''}`}>
    <aside className={`m-sidebar ${navOpen?'is-open':''}`}>
      <div className="m-brand-row">
        <button className="m-brand" onClick={()=>go('dashboard')} aria-label="Dashboard"><span className="m-brand-mark">CF</span><span className="m-brand-copy"><strong>Coursefinder</strong><small>PIM Admin v{UI_VERSION}</small></span></button>
        <button className="m-sidebar-collapse" onClick={()=>setCollapsed(x=>!x)} title={collapsed?'Expand navigation':'Collapse navigation'}>{collapsed?<PanelLeftOpen size={17}/>:<PanelLeftClose size={17}/>}</button>
      </div>
      <div className="m-nav-scroll"><nav className="m-nav" aria-label="Main menu">{SECTIONS.map(section=>{const allowed=section.pages.filter(k=>canOpen(k,rank));if(!allowed.length)return null;return <div className={`m-nav-group${section.label?'':' is-plain'}`} key={section.label||'home'}>{section.label&&<div className="m-nav-label">{section.label}</div>}{allowed.map(k=>{const p=PAGES[k],Icon=ICONS[p.icon]||Settings2;return <button key={k} title={collapsed?p.label:undefined} aria-current={pageKey===k?'page':undefined} className={`m-nav-item ${pageKey===k?'active':''}`} onClick={()=>go(k)}><Icon size={17}/><span>{p.label}</span>{k==='health'&&<StatusDot tone={tone} label={healthLabel}/>}</button>})}</div>})}</nav></div>
      <div className="m-account">
        <div className="m-avatar">{(session.user.email?.[0]||'U').toUpperCase()}</div>
        <div className="m-account-copy"><strong>{roleLabel(context?.role||'Authorised user')}</strong><small>{session.user.email}</small></div>
        <button className="m-icon-button" title="Sign out" onClick={()=>supabase.auth.signOut()}><LogOut size={17}/></button>
      </div>
    </aside>
    {navOpen&&<button className="m-backdrop" onClick={()=>setNavOpen(false)} aria-label="Close navigation"/>}
    <main className="m-main" ref={mainRef}>
      <PageHeader
        leading={<button className="m-mobile-menu" onClick={()=>setNavOpen(true)} aria-label="Open menu"><Menu size={20}/></button>}
        breadcrumbs={<AppBreadcrumbs pageKey={pageKey} tab={tab} routeParams={route.params} navigate={go}/>}
        title={page.title} subtitle={page.subtitle}
        actions={<>{canOpen('health',rank)&&<button type="button" className="cf-health-link" onClick={()=>go('health')} title={`Platform health: ${healthLabel}`} aria-label={`Platform health: ${healthLabel}`}><StatusDot tone={tone} label={healthLabel}/><span className="cf-health-text">Health</span></button>}<span className="m-release-pill"><span className="m-live-dot"/><span className="m-release-version-label">v{UI_VERSION}</span></span><span className="m-role-pill">{roleLabel(context?.role||'Loading')}</span></>}/>
      {error&&<div className="m-alert"><AlertTriangle size={16}/><span>{error}</span><button onClick={()=>setError('')}><X size={15}/></button></div>}
      <WorkspaceErrorBoundary routeKey={`${pageKey}/${tab}?${route.params.toString()}`} onError={setError} onRecover={()=>go('dashboard')}>
        <Page pageKey={pageKey} tab={tab} routeParams={route.params} rank={rank} actorId={String(context?.user_id||'')} onError={setError} navigate={go}/>
      </WorkspaceErrorBoundary>
    </main>
  </div>
}

function Login({error,onError}){const[email,setEmail]=useState(''),[password,setPassword]=useState(''),[busy,setBusy]=useState(false);async function submit(e){e.preventDefault();setBusy(true);onError('');const{error:x}=await supabase.auth.signInWithPassword({email,password});if(x)onError(x.message);setBusy(false)}return <div className="m-login"><form className="m-login-card" onSubmit={submit}><div className="m-login-brand"><span className="m-brand-mark large">CF</span><div><strong>Coursefinder Admin</strong><small>Governed operational workspace</small></div></div><div className="m-login-copy"><h1>Sign in</h1><p>Authorised staff access only. Canonical catalogue, provenance and pipeline operations.</p></div>{error&&<div className="m-alert compact"><AlertTriangle size={15}/><span>{error}</span></div>}<label>Email<input type="email" value={email} onChange={e=>setEmail(e.target.value)} required/></label><label>Password<input type="password" value={password} onChange={e=>setPassword(e.target.value)} required/></label><button className="m-primary" disabled={busy}>{busy?'Signing in…':'Sign in'}</button><small className="m-login-version">PIM Admin v{UI_VERSION}</small></form></div>}

// Every page renders inside the shell through PageLayout: optional tabs, then content. No page draws its own shell.
function Page({pageKey,tab,routeParams,rank,actorId,onError,navigate}){
  const focusId=routeParams?.get?.('id')||''
  const err=e=>onError(e?.message||String(e))
  if(!canOpen(pageKey,rank))return <EmptyState icon={AlertTriangle} title="Not authorised" text="Your role does not include this page. Ask a Platform Admin if you need access."/>
  const page=PAGES[pageKey],tabs=allowedTabs(page,rank)
  const onTab=key=>navigate(pageKey,{tab:key})
  const body=pageBody()
  return <PageLayout tabs={tabs} active={tab} onTab={onTab} label={`${page.label} sections`}>{body}</PageLayout>
  function pageBody(){
    switch(pageKey){
      case'dashboard':return <DashboardHome onError={onError}/>
      case'guide':return <PlatformGuide rank={rank} navigate={navigate}/>
      case'activity':return <LiveActivity navigate={navigate} rank={rank}/>
      case'courses':return <Catalogue key="course" type="course" onError={onError} navigate={navigate} initialId={focusId} rank={rank}/>
      case'providers':
        if(tab==='campuses')return <Catalogue key="campus" type="campus" onError={onError} navigate={navigate} initialId={focusId} rank={rank}/>
        if(tab==='assets')return <ProviderAssetsWorkspace onError={onError} navigate={navigate}/>
        if(tab==='onboarding')return <div className="m-page-stack">{/* v2.15.131: Layer 2's provider onboarding queue merged here (screen review l2r-onboard, l2r-qualify: merge/keep into Providers › Onboarding). */}<ProviderOnboarding rank={rank} openEvidence={id=>{location.hash=`#evidence${id?`?evidence_id=${encodeURIComponent(id)}`:''}`}}/><details className="cf-collapse onb-cases"><summary>Country and source onboarding cases</summary><OnboardingWorkspace rank={rank} onError={err}/></details></div>
        return <Catalogue key="provider" type="provider" onError={onError} navigate={navigate} initialId={focusId} rank={rank}/>
      case'scholarships':return tab==='publishing'?<div className="m-page-stack"><ScholarshipPublishing onError={err}/></div>:tab==='links'?<div className="m-page-stack"><ScholarshipLinks onError={err}/><ScholarshipLinkTools rank={rank} onError={onError}/></div>:<ScholarshipWorkspace rank={rank} onError={onError} navigate={navigate} initialId={focusId}/>
      case'rankings':
        if(tab==='compare')return <ComparisonWorkspace routeParams={routeParams} navigate={navigate} onError={onError}/>
        if(tab==='qilt')return <Qilt onError={onError}/>
        if(tab==='prisms')return <Prisms onError={onError}/>
        if(tab==='datasets')return <StatisticsDatasets rank={rank}/>
        return <StatisticsRankings onError={onError} navigate={navigate} rank={rank} routeParams={routeParams}/>
      case'coverage':return tab==='attributes'?<CoverageAttributes rank={rank}/>:<div className="m-page-stack"><CoverageView view="courses"/><LinkRefresh/></div>
      case'layer1':
        if(tab==='settings')return <Layer1SourceSettings/>
        if(tab==='batch')return <div className="m-legacy-host"><RegulatorySettings onError={onError} mode="batch"/></div>
        return <Layer1Operations embedded/>
      case'reference':
        if(tab==='dates')return <div className="m-page-stack"><KeyDates onError={err}/></div>
        if(tab==='links')return <div className="m-page-stack"><ReferenceSources onError={err}/></div>
        return <RankingImportPanel onError={onError} routeParams={routeParams} navigate={navigate}/>
      case'layer2':
        if(tab==='profiles')return <Layer2SourceConfig rank={rank} embedded onOpenProviders={()=>navigate('scrapers')}/>
        return <Layer2Workspace rank={rank} embedded view={tab==='start'?'start':tab==='history'?'history':'overview'}/>
      case'layer3':return <Layer3Operations tab={tab} rank={rank} onError={onError}/>
      case'layer4':return tab==='blocks'?<div className="m-page-stack"><PlatformMaturity rank={rank} onError={onError} view="blocks"/></div>:tab==='flags'?<FlaggedValues onError={err}/>:tab==='sendback'?<div className="m-page-stack"><SendBackToAI onError={err}/></div>:tab==='rules'?<div className="m-page-stack"><FeeRules onError={err}/></div>:<div className="m-page-stack"><Layer4Workspace onError={err}/></div>
      case'health':return tab==='readiness'?<PlatformMaturity rank={rank} onError={onError} view="capacity"/>:<PlatformHealth onError={onError}/>
      case'jobs':return tab==='priority'?<div className="m-page-stack"><PriorityQueue onError={err}/></div>:tab==='automations'?<div className="m-page-stack"><Automations onError={err}/><RefreshWorkspace onError={err}/></div>:<JobsWorkspace/>
      case'evidence':return <EvidenceWorkspace onError={onError} navigate={navigate} routeParams={routeParams}/>
      case'sources':return <SourcesWorkspace/>
      case'environment':return <EnvironmentMigrationWorkspace rank={rank} onError={onError} view="integrations"/>
      case'scrapers':return <><p className="l3v-note">Switch services on or off in <a href="#models-services">Models &amp; services</a>. Keys are on <a href="#environment">Environment &amp; integrations</a>.</p><Layer2ProviderConfig rank={rank} embedded/>{rank>=5&&<details className="m-admin-advanced"><summary>Advanced Layer 2 workload defaults</summary><Layer2ExecutionPolicySettings/></details>}</>
      case'services':return <div className="m-page-stack"><ModelsServices onError={err}/></div>
      case'migration':return <div className="m-page-stack"><EnvironmentMigrationWorkspace rank={rank} onError={onError} view="migration"/><PlatformMaturity rank={rank} onError={onError} view="golive"/><div className="m-legacy-host"><RegulatorySettings onError={onError} mode="reset"/></div></div>
      case'dataModel':return <Attributes onError={onError}/>
      case'users':return <AccessRolesEmbedded actorId={actorId}/>
      case'contacts':return <ProviderContactsWorkspace rank={rank} onError={onError} navigate={navigate} initialProviderId={routeParams?.get?.('provider_id')||''}/>
      default:return <EmptyState icon={AlertTriangle} title="Page not found" text="This address does not match a page. Use the menu to continue."/>
    }
  }
}


function StatisticsRankings({onError,navigate,rank,routeParams}){
 const[qilt,setQilt]=useState(null),[prisms,setPrisms]=useState(null),[ranking,setRanking]=useState(null),[busy,setBusy]=useState(true)
 const[rankingYears,setRankingYears]=useState({qs:[],the:[]}),[rankingSelection,setRankingSelection]=useState({qs:'',the:''})
 useEffect(()=>{let live=true;setBusy(true);Promise.all([
  api.qiltPage({limit:1,offset:0,sort:'year',direction:'desc'}).catch(e=>({error:e})),
  api.prismsPage({limit:1,offset:0,sort:'period',direction:'desc'}).catch(e=>({error:e})),
  api.rankingSummary().catch(e=>({error:e})),
  api.rankingFilters('qs_wur').catch(e=>({error:e})),
  api.rankingFilters('the_wur').catch(e=>({error:e}))
 ]).then(([q,p,r,qsf,thef])=>{if(!live)return;if(q?.error)onError?.(q.error.message);else setQilt(q);if(p?.error)onError?.(p.error.message);else setPrisms(p);if(r?.error)onError?.(r.error.message);else setRanking(r);const qy=(qsf?.years||[]).map(String),ty=(thef?.years||[]).map(String);setRankingYears({qs:qy,the:ty});setRankingSelection(x=>({qs:x.qs&&qy.includes(x.qs)?x.qs:(qy[0]||''),the:x.the&&ty.includes(x.the)?x.the:(ty[0]||'')}))}).finally(()=>live&&setBusy(false));return()=>{live=false}},[])
 const q=qilt?.items?.[0]||qilt?.rows?.[0]||null,p=prisms?.items?.[0]||prisms?.rows?.[0]||null
 const qYear=q?[q.collection_year_from,q.collection_year_to].filter(Boolean).join('–'):'—'
 const pPeriod=p?[p.period_start,p.period_end].filter(Boolean).map(x=>String(x).slice(0,10)).join(' → '):'—'
 const systems=ranking?.systems||[],qs=systems.find(x=>x.code==='qs_wur'),the=systems.find(x=>x.code==='the_wur')
 const activeDataset=routeParams?.get?.('dataset')||'',activeYear=routeParams?.get?.('year')||''
 useEffect(()=>{if(activeDataset==='qs_wur'&&activeYear&&rankingYears.qs.includes(String(activeYear)))setRankingSelection(x=>({...x,qs:String(activeYear)}));if(activeDataset==='the_wur'&&activeYear&&rankingYears.the.includes(String(activeYear)))setRankingSelection(x=>({...x,the:String(activeYear)}))},[activeDataset,activeYear,rankingYears.qs.join('|'),rankingYears.the.join('|')])
 const openRanking=(system,key)=>{const selected=rankingSelection[key]||rankingYears[key][0]||'';if(selected)navigate('Statistics & Rankings',{dataset:system,year:selected})}
 if(['qs_wur','the_wur'].includes(activeDataset))return <div className="m-page-stack"><RankingDatasetPanel system={activeDataset} year={activeYear} navigate={navigate} onError={onError}/></div>
 return <div className="m-page-stack">
  <section className="m-panel">
   <PanelTitle icon={BarChart3} title="Statistics & Rankings" subtitle="One verification workspace for contextual statistics, ranking editions, coverage and provenance."/>
   <div className="m-stats-grid">
    <article className="m-stats-card"><span>QILT</span><strong>{busy?'…':fmtNumber(qilt?.total||0)}</strong><small>observations · latest period {qYear}</small><div><button onClick={()=>navigate('Outcomes (QILT)')}>Open dataset</button><button onClick={()=>navigate('Compare',{type:'provider'})}>Compare</button></div></article>
    <article className="m-stats-card"><span>PRISMS</span><strong>{busy?'…':fmtNumber(prisms?.total||0)}</strong><small>observations · latest period {pPeriod}</small><div><button onClick={()=>navigate('Student Flow (PRISMS)')}>Open dataset</button><button onClick={()=>navigate('Compare',{type:'provider'})}>Compare</button></div></article>
    <article className="m-stats-card"><span>QS World University Rankings</span><div className="m-ranking-card-picker"><label>Edition<select aria-label="QS ranking edition" value={rankingSelection.qs||rankingYears.qs[0]||''} onChange={e=>setRankingSelection(x=>({...x,qs:e.target.value}))}>{rankingYears.qs.map((y,i)=><option key={y} value={y}>{y}{i===0?' · latest':''}</option>)}</select></label></div><strong>{rankingSelection.qs||qs?.latest_edition||'—'}</strong><small>{qs?.accepted_editions?`${fmtNumber(qs.observations||0)} observations · ${fmtNumber(qs.mapped_observations||0)} mapped`:'No accepted edition applied yet.'}</small><div><button disabled={!rankingYears.qs.length} onClick={()=>openRanking('qs_wur','qs')}>Open Dataset</button><button onClick={()=>navigate('Compare',{type:'provider'})}>Compare</button></div></article>
    <article className="m-stats-card"><span>Times Higher Education</span><div className="m-ranking-card-picker"><label>Edition<select aria-label="THE ranking edition" value={rankingSelection.the||rankingYears.the[0]||''} onChange={e=>setRankingSelection(x=>({...x,the:e.target.value}))}>{rankingYears.the.map((y,i)=><option key={y} value={y}>{y}{i===0?' · latest':''}</option>)}</select></label></div><strong>{rankingSelection.the||the?.latest_edition||'—'}</strong><small>{the?.accepted_editions?`${fmtNumber(the.observations||0)} observations · ${fmtNumber(the.mapped_observations||0)} mapped`:'No accepted edition applied yet.'}</small><div><button disabled={!rankingYears.the.length} onClick={()=>openRanking('the_wur','the')}>Open Dataset</button><button onClick={()=>navigate('Compare',{type:'provider'})}>Compare</button></div></article>
   </div>
  </section>
  <section className="m-panel">
   <div className="m-stats-section-head"><div><h3>Coverage & verification</h3><p>Use dataset drill-downs to inspect exact observations. Ranking coverage, edition filters, Provider mapping and Evidence remain publisher-specific.</p></div><button className="m-secondary" onClick={()=>navigate('Compare',{type:'provider'})}><ArrowLeftRight size={15}/>Open Compare</button></div>
   <div className="m-stats-notes">
    <div><b>Provider context</b><span>QILT, PRISMS and institutional rankings retain their native source grain.</span></div>
    <div><b>Years / editions</b><span>QS and THE use independent edition selectors; Compare retains its own per-ranking edition controls.</span></div>
    <div><b>Evidence</b><span>Every accepted value links back to the source page it came from.</span></div>
    <div><b>Historical publisher files</b><span>{rank>=4?'Ranking files are imported in Reference data › Ranking imports.':'Import controls are restricted to authorised operator roles.'}</span></div>
   </div>
  </section>
 </div>
}

function RankingDatasetPanel({system,year,navigate,onError}){
 // v2.15.135 (Decision 208): filters by country, state, provider and link; a linked provider opens its record; a
 // ranked university with no provider can be linked by a Curator (suggestions + search). Links are kept up to date by
 // the job "Link ranked universities to providers".
 const[filters,setFilters]=useState(null),[opts,setOpts]=useState(null),[data,setData]=useState(null),[query,setQuery]=useState(''),[offset,setOffset]=useState(0),[sort,setSort]=useState('rank'),[direction,setDirection]=useState('asc'),[busy,setBusy]=useState(false)
 const[country,setCountry]=useState(''),[state,setState]=useState(''),[providerId,setProviderId]=useState(''),[link,setLink]=useState(''),[picking,setPicking]=useState(null),[reload,setReload]=useState(0)
 const debounced=useDebounce(query,260),label=system==='qs_wur'?'QS World University Rankings':'Times Higher Education'
 useEffect(()=>{let live=true;api.rankingFilters(system).then(x=>live&&setFilters(x)).catch(e=>onError?.(e.message));return()=>{live=false}},[system])
 const years=(filters?.years||[]).map(String),selectedYear=years.includes(String(year))?String(year):(years[0]||String(year||''))
 useEffect(()=>{let live=true;if(!system||!selectedYear)return;api.rankingFilterOptions({systemCode:system,editionYear:selectedYear,country}).then(x=>live&&setOpts(x)).catch(e=>onError?.(e.message));return()=>{live=false}},[system,selectedYear,country,reload])
 useEffect(()=>{setState('');setProviderId('')},[country])
 useEffect(()=>{setOffset(0)},[system,selectedYear,debounced,sort,direction,country,state,providerId,link])
 useEffect(()=>{let live=true;if(!system||!selectedYear)return;setBusy(true);api.rankingObservations({limit:50,offset,query:debounced,systemCode:system,editionYear:selectedYear,country,state,providerId,link,sort,direction}).then(x=>live&&setData(x)).catch(e=>onError?.(e.message)).finally(()=>live&&setBusy(false));return()=>{live=false}},[system,selectedYear,debounced,offset,sort,direction,country,state,providerId,link,reload])
 const rows=data?.items||[],total=Number(data?.total||0),canLink=Boolean(opts?.can_link)
 const countryOptions=(opts?.countries||[]).map(c=>({value:c.value,label:c.value,meta:`${fmtNumber(c.count)} ranked${c.in_catalogue?' · in catalogue':''}`}))
 const stateOptions=(opts?.states||[]).map(x=>({value:x.value,label:x.label,meta:`${fmtNumber(x.count)} ranked`}))
 const providerOptions=(opts?.providers||[]).map(x=>({value:x.value,label:x.label}))
 const linkOptions=[{value:'linked',label:'Linked to a provider'},{value:'not_linked',label:'Not linked'}]
 const sortHead=(key,title)=><button type="button" onClick={()=>{if(sort===key)setDirection(x=>x==='asc'?'desc':'asc');else{setSort(key);setDirection('asc')}}}>{title}{sort===key?(direction==='asc'?' ↑':' ↓'):''}</button>
 return <section className="m-panel" data-react-ranking-viewer="1">
  <div className="m-workspace-head"><div><div className="m-section-kicker">Imported ranking dataset</div><h2>{label}</h2><p>Accepted values for the selected edition. Universities are linked to our providers in the same country when the names agree; close matches wait for a person.</p></div><label className="m-ranking-dataset-edition">Edition<select aria-label={`${label} dataset edition`} value={selectedYear} onChange={e=>navigate('Statistics & Rankings',{dataset:system,year:e.target.value})}>{years.map((y,i)=><option key={y} value={y}>{y}{i===0?' · latest':''}</option>)}</select></label></div>
  <div className="m-search-row"><label className="m-searchbox"><Search size={16}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search publisher institution or mapped Provider…"/>{query&&<button onClick={()=>setQuery('')}><X size={14}/></button>}</label></div>
  <div className="m-filter-bar" data-ranking-filters><FilterSelect label="Country" value={country} onChange={v=>setCountry(v)} options={countryOptions}/>{stateOptions.length>0&&<FilterSelect label="State" value={state} onChange={v=>setState(v)} options={stateOptions}/>}<FilterSelect label="Provider" value={providerId} onChange={v=>setProviderId(v)} options={providerOptions}/><FilterSelect label="Link" value={link} onChange={v=>setLink(v)} options={linkOptions}/></div>
  {opts&&<p className="m-help rl-summary" data-ranking-link-summary>{fmtNumber(opts.linked||0)} linked to a provider · {fmtNumber(opts.not_linked||0)} not linked{country?` in ${country}`:''}{Number(opts.not_linked_in_catalogue_countries||0)>0?` · ${fmtNumber(opts.not_linked_in_catalogue_countries)} of those are in a country we hold providers for`:''}</p>}
  <div className="dense-table-wrap"><table className="dense-table m-fluid-table"><thead><tr><th>{sortHead('institution','Publisher institution')}</th><th>{sortHead('provider','Canonical Provider')}</th><th>{sortHead('rank','Rank')}</th><th>{sortHead('score','Overall score')}</th><th>{sortHead('country','Country')}</th><th><span>State</span></th><th><span>Evidence</span></th></tr></thead><tbody>{rows.length?rows.map((x,i)=><React.Fragment key={`${x.publisher_institution_name||i}-${x.rank_display||x.rank_exact||''}`}><tr><td className="primary-cell">{x.publisher_institution_name||'—'}<small style={{display:'block',color:'var(--cf-slate-400)'}}>{x.ranking_name||label}</small></td>
   <td>{x.provider_id?<button type="button" className="m-link-button rl-provider-link" onClick={()=>navigate('Providers',{id:x.provider_id})}>{x.provider_name}</button>:<span className="rl-unlinked">Not linked{canLink&&x.publisher_institution_id&&<button type="button" className="m-secondary compact" onClick={()=>setPicking(picking===x.publisher_institution_id?null:x.publisher_institution_id)}><Link2 size={12}/>Link</button>}</span>}</td>
   <td>{x.rank_display||x.rank_exact||'—'}</td><td>{x.overall_score==null?'—':x.overall_score}</td><td>{x.country_text||'—'}</td><td>{x.state_code?x.state_code.replace(/^[A-Z]{2}-/,''):'—'}</td><td>{x.evidence_artifact_id?<button className="m-secondary compact" onClick={()=>navigate('Evidence',{id:x.evidence_artifact_id})}>Open Evidence</button>:'—'}</td></tr>
   {picking&&picking===x.publisher_institution_id&&<tr><td colSpan="7"><RankingLinkPicker row={x} onClose={()=>setPicking(null)} onLinked={()=>{setPicking(null);setReload(r=>r+1)}}/></td></tr>}</React.Fragment>):<tr><td colSpan="7"><EmptyInline text={busy?'Loading ranking observations…':'No accepted observations match this edition, filters and search.'}/></td></tr>}</tbody></table></div>
  <Pager offset={offset} limit={50} total={total} onOffset={setOffset}/>
 </section>
}


function ProviderAssetsWorkspace({onError,navigate}){
 const[summary,setSummary]=useState(null),[data,setData]=useState(null),[country,setCountry]=useState('AU'),[state,setState]=useState(''),[query,setQuery]=useState(''),[offset,setOffset]=useState(0),[busy,setBusy]=useState(false)
 const debounced=useDebounce(query,260)
 const countries=[{value:'AU',label:'Australia'},{value:'NZ',label:'New Zealand'},{value:'CA',label:'Canada'},{value:'',label:'All countries'}]
 const states=[{value:'',label:'All states'},{value:'blocked',label:'Blocked'},{value:'needs_review',label:'Needs review'},{value:'missing',label:'Missing'},{value:'approved',label:'Approved'}]
 function load(){setBusy(true);return Promise.all([api.providerAssetSummary({countryCode:country,query:debounced}),api.providerAssetCoverage({limit:50,offset,countryCode:country,query:debounced,state})]).then(([s,p])=>{setSummary(s);setData(p)}).catch(e=>onError?.(e.message)).finally(()=>setBusy(false))}
 useEffect(()=>{load()},[country,state,debounced,offset])
 useEffect(()=>setOffset(0),[country,state,debounced])
 const rows=data?.items||[],total=Number(data?.total||0)
 return <div className="m-page-stack">
  <section className="m-panel">
   <PanelTitle icon={Building2} title="Provider Assets" subtitle="How many providers have a logo. The provider's own website is preferred; finding a logo never creates or merges a provider."/>
   <div className="m-stats-grid">
    {[['Expected',summary?.expected],['Discovered',summary?.discovered],['Acquired',summary?.acquired],['Approved',summary?.approved],['Blocked',summary?.blocked],['Missing',summary?.missing]].map(([label,value])=><article className="m-stats-card" key={label}><span>{label}</span><strong>{busy?'…':fmtNumber(value||0)}</strong><small>{label==='Approved'?'Managed primary logos':label==='Blocked'?'Accepted candidate not promoted':label==='Missing'?'No logo candidate yet':'Current filtered scope'}</small></article>)}
   </div>
   <p className="m-help" style={{marginTop:12}}>{summary?.scope_basis||'Counted against the active providers in the selected country.'}</p>
  </section>
  <section className="m-panel">
   <div className="m-workspace-head"><div><h2>Coverage matrix</h2><p>Prioritises blocked and review cases before missing coverage. Approved assets retain source URL, Evidence, hash and verification time.</p></div><button className="m-secondary compact" onClick={load}><RefreshCw size={14}/>Refresh</button></div>
   <div className="m-search-row"><label className="m-searchbox"><Search size={16}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search Provider or stable key…"/>{query&&<button onClick={()=>setQuery('')}><X size={14}/></button>}</label></div>
   <div className="m-filter-bar"><FilterSelect label="Country" value={country} onChange={v=>setCountry(v)} options={countries}/><FilterSelect label="Coverage state" value={state} onChange={v=>setState(v)} options={states}/></div>
   <div className="dense-table-wrap"><table className="dense-table"><thead><tr><th><span>Provider</span></th><th><span>Country</span></th><th><span>State</span></th><th><span>Candidates</span></th><th><span>Evidence-backed</span></th><th><span>Primary asset</span></th><th><span>Verified</span></th><th><span>Actions</span></th></tr></thead><tbody>{rows.length?rows.map(r=><tr key={r.provider_id}><td className="primary-cell">{r.provider_name}<small style={{display:'block',color:'var(--cf-slate-400)'}}>{r.stable_key}</small></td><td>{r.country_code}</td><td><Status value={r.coverage_state}/></td><td>{r.candidate_count}</td><td>{r.evidence_candidate_count}</td><td>{r.primary_mime_type||'—'}</td><td>{r.primary_verified_at?fmtDate(r.primary_verified_at):'—'}</td><td><button className="m-secondary compact" onClick={()=>navigate?.('Providers',{id:r.provider_id})}>Open Provider</button>{r.primary_evidence_id&&<EvidenceButton id={r.primary_evidence_id} navigate={navigate}/>}</td></tr>):<tr><td colSpan="8"><EmptyInline text={busy?'Loading Provider asset coverage…':'No matching Providers.'}/></td></tr>}</tbody></table></div>
   <Pager offset={offset} limit={50} total={total} onOffset={setOffset}/>
  </section>
 </div>
}

function RankingImportPanel({onError,routeParams,navigate}){
 const requested=routeParams?.get?.('system'),presetSystem=['qs_wur','the_wur','arwu'].includes(requested)?requested:'qs_wur',presetYear=routeParams?.get?.('year')||String(rankingDefaultYear(presetSystem))
 const makeForm=(system=presetSystem,year=presetYear)=>({systemCode:system,editionYear:String(year),publisherName:rankingPublisherName(system),sourceUrl:rankingSourceUrl(system),methodologyUrl:'',licensingNote:'Authorised publisher Evidence obtained for CourseFinder ingestion.',revisionNote:'',mode:'file'})
 const[form,setForm]=useState(makeForm()),[files,setFiles]=useState([]),[busy,setBusy]=useState(false),[saved,setSaved]=useState(''),[imports,setImports]=useState([]),[detected,setDetected]=useState(null),[advanced,setAdvanced]=useState(false),[processingId,setProcessingId]=useState(''),[lastParsedKey,setLastParsedKey]=useState(''),[overwriteKey,setOverwriteKey]=useState(''),[historySystem,setHistorySystem]=useState('all')
 useEffect(()=>{let live=true;loadRankingSources().then(()=>{if(live)setForm(x=>x.sourceUrl?x:{...x,sourceUrl:rankingSourceUrl(x.systemCode)})});return()=>{live=false}},[])
 const sameEditionImports=imports.filter(x=>x.system_code===form.systemCode&&String(x.edition_year)===String(form.editionYear))
 const existingCountries=[...new Set(sameEditionImports.flatMap(x=>Array.isArray(x.detected_scope)?x.detected_scope:[]).map(x=>String(x||'').trim()).filter(Boolean))]
 const selectedCountries=Array.isArray(detected?.countries)?detected.countries:[]
 const newCountries=selectedCountries.filter(x=>!existingCountries.includes(x)),overlapCountries=selectedCountries.filter(x=>existingCountries.includes(x))
 const addingCountryScope=!!sameEditionImports.length&&!!selectedCountries.length&&newCountries.length===selectedCountries.length
 const load=async()=>{try{const x=await api.rankingImports({limit:100});setImports(x?.items||[]);return x?.items||[]}catch(e){onError?.(e.message);return[]}}
 useEffect(()=>{load()},[])
 const editionKey=(system=form.systemCode,year=form.editionYear)=>system+':'+String(year)
 const clearOutcome=()=>{setSaved('');setOverwriteKey('')}
 const patch=(k,v)=>{if(k==='editionYear'||k==='systemCode')clearOutcome();setForm(x=>({...x,[k]:v}))}
 const chooseSystem=v=>{clearOutcome();setFiles([]);setDetected(null);setForm(x=>({...x,systemCode:v,editionYear:String(rankingDefaultYear(v)),publisherName:rankingPublisherName(v),sourceUrl:rankingSourceUrl(v),mode:'file'}))}
 async function inspectFiles(nextList){
  const selected=Array.from(nextList||[]);setFiles(selected);setSaved('');setDetected(null)
  if(!selected.length)return
  try{
   let system=null,year=null,rows=0;const countries=new Set()
   for(const next of selected){
    if(!/\.(txt|json)$/i.test(next.name))continue
    const clean=(await next.text()).replace(/^\uFEFF/,'').trim(),m=clean.match(/^Year\s+(\d{4})\s*[\r\n]+/i),headerYear=m?Number(m[1]):null,body=m?clean.slice(m[0].length):clean,payload=JSON.parse(body),d=payload?.data??payload
    let detectedSystem=null,detectedRows=[],detectedYear=headerYear
    if(Array.isArray(d?.universities)){detectedSystem='qs_wur';detectedRows=d.universities;detectedYear=detectedYear||Number(d?.edition_year||payload?.edition_year)}
    else if(Array.isArray(d?.rankings)){detectedSystem='arwu';detectedRows=d.rankings;detectedYear=detectedYear||Number(d?.year||payload?.year)}
    else if(Array.isArray(payload?.data?.data)){detectedSystem='the_wur';detectedRows=payload.data.data}
    if(!detectedSystem)continue
    if(system&&system!==detectedSystem)throw new Error('Selected files contain mixed ranking systems.')
    if(year&&detectedYear&&year!==detectedYear)throw new Error('Selected files contain mixed edition years.')
    system=detectedSystem;year=detectedYear||year;rows+=detectedRows.length
    detectedRows.forEach(r=>{const country=String(r?.country||r?.location||r?.region||'').trim();if(country)countries.add(country)})
   }
   if(system){
    const y=year||Number(form.editionYear)||2026,label=system==='qs_wur'?'QS World University Rankings':system==='the_wur'?'Times Higher Education':'Academic Ranking of World Universities'
    setDetected({system:label,year:y,format:selected.length>1?'Country/multi-page bundle':'Publisher JSON/TXT',rows,countries:[...countries]})
    setForm(x=>({...x,systemCode:system,editionYear:String(y),publisherName:rankingPublisherName(system),sourceUrl:rankingSourceUrl(system),mode:'file'}))
   }
  }catch(err){onError?.(readableError(err))}
 }
 function readableError(err){
  const raw=String(err?.message||err||'Import failed')
  const map={txt_native_json_is_the_only:'This TXT file is supported only when it contains a Times Higher Education native JSON export.',edition_year_mismatch:'The selected edition does not match the year declared in the file.',the_native_json_invalid:'The file is not a valid Times Higher Education native JSON export.',the_native_json_shape_invalid:'The JSON file does not contain the expected Times Higher Education data structure.'}
  return map[raw]||raw.replaceAll('_',' ')
 }
 async function processImport(importId,action='validate'){
  if(!importId)return
  setProcessingId(importId);onError?.('')
  try{
   const r=await api.rankingPublisherControl({action,importId})
   if(action==='validate')setSaved('The imported edition was checked and applied. Any university names that could not be matched wait for review.')
   else setSaved('Edition applied to Statistics & Rankings. Mapping exceptions remain reviewable.')
   await load();return r
  }catch(err){onError?.(readableError(err));throw err}
  finally{setProcessingId('')}
 }
 async function submit(e){
  e.preventDefault();setSaved('')
  const key=editionKey(),existing=imports.find(x=>x.system_code===form.systemCode&&String(x.edition_year)===String(form.editionYear))
  if(existing&&!addingCountryScope&&overwriteKey!==key){
   const scopeText=selectedCountries.length
    ?(newCountries.length&&overlapCountries.length
      ?'This upload mixes new country scope ('+newCountries.join(', ')+') with already-loaded scope ('+overlapCountries.join(', ')+').'
      :'This upload overlaps already-loaded country scope'+(overlapCountries.length?' ('+overlapCountries.join(', ')+')':'')+'.')
    :'Country scope could not be proven from this file.'
   setSaved('WARNING:'+humanise(form.systemCode)+' '+form.editionYear+' already exists ('+humanise(existing.status)+'). '+scopeText+' Registering it creates a new Evidence revision; Apply remains manual and must not overwrite unrelated countries.')
   return
  }
  setBusy(true)
  try{
   let r
   if(!files.length)throw new Error('Choose at least one authorised publisher file.')
   r=await api.uploadRankingPublisherFile({...form,editionYear:Number(form.editionYear),files})
   setFiles([]);setDetected(null);e.currentTarget?.reset?.()
   await load()
   if(r?.import_id)await processImport(r.import_id,'validate')
   await load()
   setLastParsedKey(key);setOverwriteKey('')
   setSaved((r?.duplicate?'Existing Evidence reused. ':'')+humanise(form.systemCode)+' '+form.editionYear+(addingCountryScope&&newCountries.length?' extended with '+newCountries.join(', '):'')+' processed successfully through Layer 1 Ranking ETL. '+(addingCountryScope?'Existing country scope was preserved and the edition was reapplied automatically.':'Change the edition year or add another country scope before running another import.'))
  }catch(err){onError?.(readableError(err))}
  finally{setBusy(false)}
 }
 return <div className="m-page-stack m-ranking-import-page">
  <section className="m-panel m-ranking-import-compact">
   <div className="m-ranking-import-head"><div><div className="m-section-kicker">Reference data / Ranking imports</div><h2>Register ranking publisher file</h2><p>File upload is the preferred ranking acquisition route. Upload one global file or combine multiple country/page JSON/TXT files for the same publisher and edition.</p></div><FileCheck2 size={22}/></div>
   <form className="m-ranking-import-form compact" onSubmit={submit}>
    <div className="m-ranking-essentials">
      <label>Ranking system<select value={form.systemCode} onChange={e=>chooseSystem(e.target.value)}><option value="qs_wur">QS World University Rankings</option><option value="the_wur">Times Higher Education</option><option value="arwu">Academic Ranking of World Universities</option></select></label>
      <label>Edition year<select value={form.editionYear} onChange={e=>patch('editionYear',e.target.value)}>{rankingYearOptions(form.systemCode).map(y=><option key={y} value={y}>{y}</option>)}</select></label>
    </div>
    <div className="m-ranking-essentials">
      <label>Publisher file(s)<input type="file" multiple accept=".csv,.xlsx,.json,.txt" onChange={e=>inspectFiles(e.target.files)} required/><small>Select one global file or multiple country/page JSON/TXT files for the same ranking system and year.</small></label>
    </div>
    {detected&&<div className="m-ranking-detected"><CheckCircle2 size={16}/><span><b>{detected.system+' · '+detected.year}</b><small>{detected.format+' · '+fmtNumber(detected.rows||0)+' source rows detected'+(detected.countries?.length?' · '+detected.countries.join(', '):'')}</small>{sameEditionImports.length&&selectedCountries.length?<small className="m-ranking-scope-note">{addingCountryScope?'Add country data · new scope: '+newCountries.join(', '):(newCountries.length?'Mixed scope · new: '+newCountries.join(', ')+' · existing: '+overlapCountries.join(', '):'Existing country scope · this will be treated as a source revision')}</small>:null}</span></div>}
    <button type="button" className="m-ranking-advanced-toggle" aria-expanded={advanced} onClick={()=>setAdvanced(x=>!x)}><Settings2 size={14}/>{advanced?'Hide metadata':'Advanced metadata'}<ChevronDown size={14}/></button>
    {advanced&&<div className="m-ranking-advanced">
      <label>Publisher<input value={form.publisherName} onChange={e=>patch('publisherName',e.target.value)} required/></label>
      <label>Publisher/source URL<input type="url" value={form.sourceUrl} onChange={e=>patch('sourceUrl',e.target.value)} required/></label>
      <label>Methodology URL<input type="url" value={form.methodologyUrl} onChange={e=>patch('methodologyUrl',e.target.value)} placeholder="Optional"/></label>
      <label>Access / licence note<input value={form.licensingNote} onChange={e=>patch('licensingNote',e.target.value)} required/></label>
      <label className="wide">Revision note<input value={form.revisionNote} onChange={e=>patch('revisionNote',e.target.value)} placeholder="Optional edition/correction note"/></label>
    </div>}
    {saved?.startsWith('WARNING:')&&<div className="m-ranking-detected warning"><AlertTriangle size={16}/><span><b>Existing edition</b><small>{saved.slice(8)}</small><button type="button" className="m-secondary compact" onClick={()=>{setOverwriteKey(editionKey());setSaved('Ready to register a new revision for '+humanise(form.systemCode)+' '+form.editionYear+'.')}}>Continue with new revision</button></span></div>}
    <div className="m-ranking-import-actions"><button className="m-primary" disabled={busy||lastParsedKey===editionKey()}>{busy?'Registering…':(lastParsedKey===editionKey()?'Parsed successfully — change year':form.mode==='url'?'Parse import':addingCountryScope?'Add country data & parse':'Register file & parse')}</button>{saved&&!saved.startsWith('WARNING:')&&<span className="success">{saved}</span>}</div>
   </form>
  </section>
  <section className="m-panel m-ranking-import-history">
   <div className="m-ranking-history-head"><div><h3>Imported files</h3><p>Each file is checked and applied automatically; university names that cannot be matched wait for review. Every edition stays listed here.</p></div><div className="m-ranking-import-row-actions"><label className="m-compact-filter">Publisher<select value={historySystem} onChange={e=>setHistorySystem(e.target.value)}><option value="all">All</option><option value="qs_wur">QS</option><option value="the_wur">THE</option><option value="arwu">ARWU</option></select></label><button className="m-secondary compact" onClick={()=>navigate?.('Jobs')}><Workflow size={13}/>Jobs</button></div></div>
   <div className="m-ranking-import-list">{imports.filter(x=>historySystem==='all'||x.system_code===historySystem).length?imports.filter(x=>historySystem==='all'||x.system_code===historySystem).map(x=>{const validating=processingId===x.id,validated=['validated','parsed','reconciled'].includes(x.status),available=['applied','needs_review'].includes(x.status),count=x.validation_summary?.candidate_observations??x.parse_summary?.rows??x.parse_summary?.candidate_observations,job=x.latest_job;return <article key={x.id} className="m-ranking-import-row"><div className="m-ranking-import-identity"><strong>{String(x.system_code||'').toUpperCase()+' '+x.edition_year}</strong><span>{x.original_filename}</span>{Array.isArray(x.detected_scope)&&x.detected_scope.length?<small>Country scope: {x.detected_scope.join(', ')}{Number(x.logical_revision_count||0)>1?' · '+x.logical_revision_count+' source revisions':''}</small>:null}{count!=null&&<small>{fmtNumber(count)} parsed observations</small>}{job&&<small>Latest Job: {humanise(job.job_type)} · {humanise(job.status)}{Number(x.job_count||0)>1?' · '+x.job_count+' jobs':''}</small>}</div><div className="m-ranking-import-state"><b className={'status '+x.status}>{humanise(x.status)}</b><small>{(x.updated_at||x.uploaded_at)?'Updated '+fmtDateTime(x.updated_at||x.uploaded_at):'—'}</small></div><div className="m-ranking-import-row-actions">{x.status==='uploaded'&&<button disabled={validating} onClick={()=>processImport(x.id,'validate')}>{validating?'Parsing…':'Parse & validate'}</button>}{validated&&<button className="primary" disabled={validating} onClick={()=>processImport(x.id,'apply')}>{validating?'Applying…':'Apply edition'}</button>}{available&&<button disabled={validating} onClick={()=>x.status==='needs_review'?processImport(x.id,'validate'):navigate?.('Statistics & Rankings')}>{x.status==='needs_review'?(validating?'Processing…':'Process & apply'):'View module'}</button>}<button className="m-link-button" disabled={processingId===x.id} onClick={async()=>{try{const{data,error}=await supabase.functions.invoke('ranking-evidence-export',{body:{system_code:x.system_code,edition_year:Number(x.edition_year),import_id:x.id}});if(error)throw error;if(!data?.signed_url)throw new Error('Exportable XLSX Evidence not found');const a=document.createElement('a');a.href=data.signed_url;a.download=data.filename||'';a.rel='noopener';document.body.appendChild(a);a.click();a.remove()}catch(e){setSaved(`Export failed: ${e.message||String(e)}`)}}}>Export XLSX</button><button className="m-secondary compact" onClick={()=>navigate?.('Jobs')}>Jobs{Number(x.job_count||0)>0?' ('+x.job_count+')':''}</button></div></article>}):<EmptyState icon={FileCheck2} title="No ranking imports for this publisher" text="Change the publisher filter, or add the ranking on Reference data › Reference sources."/>}</div>
  </section>
 </div>
}

function Layer2ExecutionPolicySettings(){
 const[data,setData]=useState(null),[form,setForm]=useState(null),[busy,setBusy]=useState(true),[saving,setSaving]=useState(false),[error,setError]=useState(''),[saved,setSaved]=useState('')
 const invoke=async body=>{const{data:r,error:e}=await supabase.functions.invoke('layer2-sync-control',{body});if(e)throw e;if(r?.error)throw new Error(r.error);return r}
 const load=async()=>{setBusy(true);setError('');try{const r=await invoke({action:'policy'}),p=r?.policy||{};setData(r);setForm({qualification_provider_wave_size:p.qualification_provider_wave_size??50,qualification_sample_size:p.qualification_sample_size??10,qualification_retry_hours:p.qualification_retry_hours??168,qualification_finalizer_run_limit:p.qualification_finalizer_run_limit??2,qualification_pattern_provider_limit:p.qualification_pattern_provider_limit??3,production_target_wave_size:p.production_target_wave_size??500,production_max_wave_size:p.production_max_wave_size??1000,schedule_remaining:p.schedule_remaining!==false})}catch(e){setError(e.message||String(e))}finally{setBusy(false)}}
 useEffect(()=>{load()},[])
 const save=async()=>{if(!form)return;setSaving(true);setError('');setSaved('');try{const r=await invoke({action:'update_policy',patch:{...form,qualification_provider_wave_size:Number(form.qualification_provider_wave_size),qualification_sample_size:Number(form.qualification_sample_size),qualification_retry_hours:Number(form.qualification_retry_hours),qualification_finalizer_run_limit:Number(form.qualification_finalizer_run_limit),qualification_pattern_provider_limit:Number(form.qualification_pattern_provider_limit),production_target_wave_size:Number(form.production_target_wave_size),production_max_wave_size:Number(form.production_max_wave_size)}});setData(r);setSaved('Layer 2 execution policy saved. New background requests use these limits.')}catch(e){setError(e.message||String(e))}finally{setSaving(false)}}
 const b=data?.firecrawl?.budget_status||{},fc=data?.firecrawl||{}
 return <section className="m-panel"><PanelTitle icon={Activity} title="Layer 2 workload defaults" subtitle="Batch sizes, how often sites are checked and wave limits. Which fetchers a source uses is set on Layer 2 › Source profiles." action={<button className="m-secondary compact" onClick={load} disabled={busy||saving}><RefreshCw size={13}/>Refresh</button>}/>
  {busy&&!form?<div className="m-empty-inline">Loading Layer 2 policy…</div>:form&&<><div className="m-summary-strip"><SummaryCard icon={Database} label="Firecrawl monthly limit" value={fmtNumber(b.limit_units)} tone="blue"/><SummaryCard icon={Activity} label="Used this period" value={fmtNumber(b.used_units)} tone="violet"/><SummaryCard icon={ShieldCheck} label="Safety reserve" value={fmtNumber(b.stop_at_remaining_units)} tone="amber"/><div className="m-summary-note"><strong>{fc.enabled?'Firecrawl enabled':'Firecrawl disabled'}</strong><span>{fmtNumber(fc.rate_limit_per_minute)} requests/min · concurrency {fmtNumber(fc.concurrency)} · credential {fc.credential_configured?'configured':'missing'} · quota managed in Scraper Config above.</span></div></div>
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
    <div className="m-kv-readonly"><span>Legacy global route mode</span><strong>{humanise(data?.policy?.route_mode||'managed')}</strong><small>Read-only here. Which fetchers a source uses is set on Layer 2 › Source profiles.</small></div>
    <label style={{display:'flex',alignItems:'center',gap:8}}><input aria-label="Layer 2 schedule remaining waves policy" type="checkbox" checked={form.schedule_remaining} onChange={e=>setForm(x=>({...x,schedule_remaining:e.target.checked}))}/><span>Schedule remaining waves automatically</span></label>
   </div></div>
  </div>
  <div style={{display:'flex',alignItems:'center',gap:10,marginTop:12}}><button className="m-primary" onClick={save} disabled={saving}>{saving?'Saving…':'Save workload defaults'}</button>{saved&&<span style={{fontSize:10,color:'var(--cf-green-700)'}}>{saved}</span>}</div></>}
  {error&&<div className="m-alert compact" style={{marginTop:10}}><AlertTriangle size={14}/><span>{error}</span><span/></div>}
 </section>
}

// v2.15.130 (screen review sch-fill-overlap, sch-decision-support): the list page is the list only. The bulk fill and
// course decision support moved to Scholarships › Course links, so everything that links scholarships to courses is in
// one place (ScholarshipLinkTools below the Course links list).
function ScholarshipWorkspace({rank,onError,navigate,initialId}){return <div className="m-page-stack"><Catalogue type="scholarship" onError={onError} navigate={navigate} initialId={initialId} rank={rank}/></div>}
function ScholarshipLinkTools({rank,onError}){const[selectionOpen,setSelectionOpen]=useState(false);return <details className="cf-collapse sl-tools"><summary>More ways to link scholarships to courses</summary><div className="m-drawer-body">
  {rank>=4&&<ScholarshipFillControl onError={onError}/>}
  <section className="m-panel"><PanelTitle icon={GraduationCap} title="Course decision support" subtitle="For one course, see which scholarships could apply and why. Eligibility for a particular student is not decided here."/><button className="m-secondary compact" onClick={()=>setSelectionOpen(true)}><GraduationCap size={15}/>Open Course decision support</button></section>
  {selectionOpen&&<ScholarshipSelectionWorkspace onClose={()=>setSelectionOpen(false)}/>}</div></details>}
function ScholarshipFillControl({onError}){
 const[country,setCountry]=useState('AU'),[busy,setBusy]=useState(false),[result,setResult]=useState(null)
 const run=async action=>{setBusy(true);try{const{data,error}=await supabase.functions.invoke('scholarship-course-fill-control',{body:{action,country_code:country}});if(error)throw error;if(data?.error)throw new Error(data.error);setResult(data)}catch(e){onError(e.message||String(e))}finally{setBusy(false)}}
 return <section className="m-panel"><PanelTitle icon={Sparkles} title="Fill links from clear scopes" subtitle="Links a scholarship to courses only where its page names the course or the whole university. Anything less clear stays on this tab for a person to decide."/>
  <div className="m-filter-bar"><label className="m-filter-select"><span>Country</span><select className="fv-filter" aria-label="Scholarship fill country" value={country} onChange={e=>setCountry(e.target.value)}><option value="AU">Australia</option><option value="NZ">New Zealand</option></select></label></div>
  <div className="m-attention-grid"><Attention tone="info" icon={SearchCheck} title="Preview" text="Count the courses and links this would add, and those left for review." action="Preview" onClick={()=>run('preview')}/><Attention tone="success" icon={CheckCircle2} title="Fill links" text="Adds only the clear links; running it again changes nothing. Course details and publishing are not changed." action="Fill now" onClick={()=>run('fill')}/><Attention tone="warning" icon={ClipboardCheck} title="Send the rest for review" text="Scholarships whose page does not say which courses they cover are listed for a person on this tab; nothing is guessed." action="Queue review" onClick={()=>run('queue_review')}/></div>
  {busy&&<div className="m-empty-inline">Filling links…</div>}{result&&<div className="m-summary-strip"><SummaryCard icon={GraduationCap} label="Courses" value={fmtNumber(result.courses??result.deterministic_mappings??0)} tone="blue"/><SummaryCard icon={Sparkles} label="Deterministic mappings" value={fmtNumber(result.deterministic_mappings??result.written_or_refreshed??0)} tone="green"/><SummaryCard icon={ClipboardCheck} label="Review candidates" value={fmtNumber(result.provider_level_candidates??0)} tone="amber"/><div className="m-summary-note"><strong>{humanise(result.status||'preview ready')}</strong><span>{result.rule||'No Scholarship eligibility is manufactured.'}</span></div></div>}
 </section>
}

function DashboardSkeleton(){return <div className="m-page-stack"><div className="m-skeleton hero"/><div className="m-metric-grid">{Array.from({length:8}).map((_,i)=><div className="m-skeleton metric" key={i}/>)}</div><div className="m-grid-2"><div className="m-skeleton panel"/><div className="m-skeleton panel"/></div></div>}
function Fresh({label,value,number,text}){return <div><small>{label}</small><strong>{number?fmtNumber(value):text?(value??'—'):value?`${relativeTime(value)} · ${fmtDateTime(value)}`:'—'}</strong></div>}
function ActivityFeed({items,navigate}){if(!items.length)return <EmptyInline text="No recent activity."/>;return <div className="m-activity-list">{items.map((x,i)=>{const Icon=x.kind==='job'?Workflow:x.kind==='review'?ClipboardCheck:FileCheck2;const target=x.kind==='job'?'Jobs':x.kind==='review'?'Review Queue':'Evidence';const params=x.kind==='evidence'&&x.id?{evidence_id:x.id}:{};return <button key={x.id||i} onClick={()=>navigate(target,params)} className="m-activity-row"><span className={`m-activity-icon kind-${x.kind}`}><Icon size={15}/></span><span className="m-activity-copy"><strong>{x.title||humanise(x.kind)}</strong><small>{x.detail||'Governed activity'} · {relativeTime(x.occurred_at)}</small></span><Status value={x.status}/></button>})}</div>}
function Attention({tone,icon:Icon,title,text,action,onClick}){return <div className={`m-attention tone-${tone}`}><span className="m-attention-icon"><Icon size={17}/></span><div><strong>{title}</strong><p>{text}</p><button onClick={onClick}>{action} →</button></div></div>}

const ENTITY={
  provider:{operation:'providers_page',detail:'provider_detail',sort:'provider',search:'Search Provider name, CRICOS code, stable key or location'},
  course:{operation:'courses_page',detail:'course_detail',sort:'course',search:'Search Course, Provider, CRICOS/course code or stable key'},
  campus:{operation:'campuses_page',detail:'campus_detail',sort:'campus',search:'Search Campus, Provider, code, city or stable key'},
  scholarship:{operation:'scholarships_page',detail:'scholarship_detail',sort:'scholarship',search:'Search Scholarship or Provider'},
}

function Catalogue({type,onError,navigate,initialId='',completenessMode=false,rank=0}){
  const[creating,setCreating]=useState(false),[listEdit,setListEdit]=useState(false)
  const cfg=ENTITY[type]
  const[offset,setOffset]=useState(0)
  // UI-2: search, filters, sort and layout are remembered per user and screen via the shared kit.
  // Same storage key as before, so existing saved choices carry over.
  const[catalogueUser,setCatalogueUser]=useState(null)
  const[remembered,remember]=useRememberedState(type,{query:'',filters:{},filterLabels:{},advanced:type==='course',sort:completenessMode?'completeness':cfg.sort,direction:'asc'},{userId:catalogueUser})
  const{query,filters,filterLabels,advanced,sort,direction}=remembered
  const rememberField=k=>v=>remember(s=>({[k]:typeof v==='function'?v(s[k]):v}))
  const setQuery=rememberField('query'),setFilters=rememberField('filters'),setFilterLabels=rememberField('filterLabels'),setAdvanced=rememberField('advanced'),setSort=rememberField('sort'),setDirection=rememberField('direction')
  const[data,setData]=useState(null),[busy,setBusy]=useState(false),[filterData,setFilterData]=useState({}),[filterBusy,setFilterBusy]=useState(false),[selected,setSelected]=useState(null),[detail,setDetail]=useState(null),[detailBusy,setDetailBusy]=useState(false)
  useEffect(()=>{let live=true;supabase.auth.getSession().then(({data:s})=>{if(live)setCatalogueUser(s?.session?.user?.id||'anonymous')});return()=>{live=false}},[])
    const debounced=useDebounce(query,280)
  const args=useMemo(()=>buildCatalogueArgs(type,{query:debounced,filters,offset,sort,direction}),[type,debounced,filters,offset,sort,direction])
  useEffect(()=>{let live=true;setBusy(true);adminRead(cfg.operation,args).then(x=>live&&setData(x)).catch(e=>onError(e.message)).finally(()=>live&&setBusy(false));return()=>{live=false}},[cfg.operation,JSON.stringify(args)])
  useEffect(()=>{if(!['provider','course','campus','scholarship'].includes(type))return;if(type==='course'){setFilterData({});setFilterBusy(false);return}let live=true;setFilterBusy(true);api.providerFilterOptions(filters.country||'').then(x=>live&&setFilterData(x||{})).catch(e=>onError(e.message)).finally(()=>live&&setFilterBusy(false));return()=>{live=false}},[type,filters.country,filters.subdivision])
  useEffect(()=>setOffset(0),[debounced,JSON.stringify(filters),sort,direction])
  useEffect(()=>{if(initialId&&String(initialId)!==String(selected))open({id:initialId,course_id:initialId})},[initialId,type])
  const rows=rowsOf(data),total=Number(data?.total??rows.length??0),active=activeFilters(filters)
  async function open(row){const id=row.id??row.course_id;setSelected(id);setDetailBusy(true);try{setDetail(await adminRead(cfg.detail,{id}))}catch(e){onError(e.message)}finally{setDetailBusy(false)}}
  function patch(k,v,label=''){setFilters(f=>{const n={...f,[k]:v};if(k==='country'){n.subdivision='';if(['course','scholarship'].includes(type))n.provider=''}if(k==='subdivision'&&type==='course')n.provider='';return n});setFilterLabels(l=>{const n={...l,[k]:label||''};if(k==='country'){delete n.subdivision;if(['course','scholarship'].includes(type))delete n.provider}if(k==='subdivision'&&type==='course')delete n.provider;return n})}
  function changeSort(k){if(!k)return;if(sort===k)setDirection(d=>d==='asc'?'desc':'asc');else{setSort(k);setDirection('asc')}}
  const cols=columns(type,completenessMode)
  return <div className="m-page-stack">
    
    <section className="m-panel m-catalogue-panel">
      <div className="m-workspace-head"><div><h2>{completenessMode?'Course readiness workspace':`${humanise(type)} catalogue`}</h2>{completenessMode&&<p>Courses missing key facts, by what is missing.</p>}</div><div className="m-result-count">{busy?<><span className="m-spinner"/>Loading…</>:<><strong>{fmtNumber(total)}</strong><span>{active.some(([k])=>/lifecycle/i.test(String(k)))?'matching':'matching · any status'}</span></>}</div></div>
      <div className="m-search-row"><label className="m-searchbox"><Search size={16}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder={cfg.search}/>{query&&<button onClick={()=>setQuery('')}><X size={14}/></button>}</label>{type==='course'&&<button className={`m-filter-toggle ${advanced?'active':''}`} onClick={()=>setAdvanced(x=>!x)}><SlidersHorizontal size={15}/>Filters{active.length?` · ${active.length}`:''}</button>}<button className="m-secondary compact" onClick={()=>{setQuery('');setFilters({});setFilterLabels({});setOffset(0)}} disabled={!query&&!active.length}><RefreshCw size={14}/>Clear</button>{!completenessMode&&['provider','course'].includes(type)&&<button className="m-secondary compact" onClick={()=>navigate?.('Compare',{type})}><Activity size={14}/>Compare {type}s</button>}{!completenessMode&&['provider','course'].includes(type)&&Number(rank)>=5&&<button className="m-secondary compact" onClick={()=>setCreating(true)}><Plus size={14}/>Add {type}</button>}{!completenessMode&&['provider','course','campus','scholarship'].includes(type)&&Number(rank)>=3&&<button className={`m-secondary compact${listEdit?' active':''}`} aria-pressed={listEdit} onClick={()=>setListEdit(x=>!x)}><Pencil size={14}/>{listEdit?'Done editing':'Edit in list'}</button>}</div>
      <FilterBar type={type} filters={filters} filterLabels={filterLabels} patch={patch} data={filterData} busy={filterBusy} advanced={advanced}/>
      {(query||active.length>0)&&<div className="m-chip-row">{query&&<FilterChip label={`Search: ${query}`} onRemove={()=>setQuery('')}/>} {active.map(([k,v])=><FilterChip key={k} label={`${k==='subdivision'?regionLabel(filters.country):filterLabel(k)}: ${filterLabels[k]||filterValueLabel(k,v,filterData)}`} onRemove={()=>patch(k,'')}/>)}</div>}
      {listEdit&&!busy&&rows.length?<ListEdit type={type} rows={rows} onError={onError}/>:<DataTable rows={rows} columns={cols} loading={busy} sort={sort} direction={direction} onSort={changeSort} onRow={open} selected={selected}/>}
      <Pager offset={offset} limit={PAGE_SIZE} total={total} onOffset={setOffset}/>
    </section>
    {selected&&<DetailDrawer type={type} data={detail} busy={detailBusy} navigate={navigate} onError={onError} onChanged={()=>adminRead(cfg.detail,{id:selected}).then(setDetail).catch(e=>onError(e.message))} onClose={()=>{setSelected(null);setDetail(null)}}/>}
    {creating&&<CreateRecord type={type} onError={onError} onClose={()=>setCreating(false)} onCreated={id=>{setCreating(false);if(id)open({id})}}/>}
  </div>
}

function FilterBar({type,filters,filterLabels={},patch,data,busy,advanced}){
  const countries=(data.countries||[]).map(x=>opt(x.code,x.name,x.code)),subdivisions=(data.subdivisions||[]).map(x=>opt(x.code,x.name,x.code))
  if(type==='provider')return <div className="m-filter-bar"><FilterSelect label="Country" value={filters.country||''} onChange={(v,l)=>patch('country',v,l)} options={countries} loading={busy}/><FilterSelect label={regionLabel(filters.country)} value={filters.subdivision||''} onChange={(v,l)=>patch('subdivision',v,l)} options={subdivisions} loading={busy}/><PagedFilterSelect kind="university_group" label="University group" value={filters.universityGroup||''} valueLabel={filterLabels.universityGroup||''} country={filters.country||''} onChange={(v,l)=>patch('universityGroup',v,l)}/><FilterSelect label="Lifecycle" value={filters.lifecycle||''} onChange={(v,l)=>patch('lifecycle',v,l)} options={STATUS_OPTIONS}/><FilterSelect label="Publication" value={filters.publication||''} onChange={(v,l)=>patch('publication',v,l)} options={PUBLICATION_OPTIONS}/></div>
  if(type==='campus')return <div className="m-filter-bar"><FilterSelect label="Country" value={filters.country||''} onChange={(v,l)=>patch('country',v,l)} options={countries} loading={busy}/><FilterSelect label={regionLabel(filters.country)} value={filters.subdivision||''} onChange={(v,l)=>patch('subdivision',v,l)} options={subdivisions} loading={busy}/></div>
  if(type==='scholarship')return <div className="m-filter-bar"><FilterSelect label="Country" value={filters.country||''} onChange={(v,l)=>patch('country',v,l)} options={countries} loading={busy}/><PagedFilterSelect kind="provider" label="Provider" value={filters.provider||''} valueLabel={filterLabels.provider||''} country={filters.country||''} onChange={(v,l)=>patch('provider',v,l)}/><FilterSelect label="Lifecycle" value={filters.lifecycle||''} onChange={(v,l)=>patch('lifecycle',v,l)} options={STATUS_OPTIONS}/><FilterSelect label="Publication" value={filters.publication||''} onChange={(v,l)=>patch('publication',v,l)} options={PUBLICATION_OPTIONS}/></div>
  if(type!=='course')return null
  return <div className={`m-filter-bar m-course-filters ${advanced?'expanded':''}`}>
    <PagedFilterSelect kind="country" label="Country" value={filters.country||''} valueLabel={filterLabels.country||''} onChange={(v,l)=>patch('country',v,l)}/>
    <PagedFilterSelect kind="subdivision" label={regionLabel(filters.country)} value={filters.subdivision||''} valueLabel={filterLabels.subdivision||''} country={filters.country||''} onChange={(v,l)=>patch('subdivision',v,l)}/>
    <PagedFilterSelect kind="provider" label="Provider" value={filters.provider||''} valueLabel={filterLabels.provider||''} country={filters.country||''} subdivision={filters.subdivision||''} onChange={(v,l)=>patch('provider',v,l)}/>
    <PagedFilterSelect kind="university_group" label="University group" value={filters.universityGroup||''} valueLabel={filterLabels.universityGroup||''} country={filters.country||''} onChange={(v,l)=>patch('universityGroup',v,l)}/>
    <PagedFilterSelect kind="level" label="Study level" value={filters.level||''} valueLabel={filterLabels.level||''} country={filters.country||''} subdivision={filters.subdivision||''} onChange={(v,l)=>patch('level',v,l)}/>
    {advanced&&<><PagedFilterSelect kind="field" label="Field" value={filters.field||''} valueLabel={filterLabels.field||''} country={filters.country||''} subdivision={filters.subdivision||''} onChange={(v,l)=>patch('field',v,l)}/><PagedFilterSelect kind="delivery" label="Delivery" value={filters.delivery||''} valueLabel={filterLabels.delivery||''} country={filters.country||''} subdivision={filters.subdivision||''} onChange={(v,l)=>patch('delivery',v,l)}/><TriFilter label="Has fee" value={filters.hasFee||''} onChange={(v,l)=>patch('hasFee',v,l)}/><TriFilter label="Has intake" value={filters.hasIntake||''} onChange={(v,l)=>patch('hasIntake',v,l)}/><TriFilter label="Has English" value={filters.hasEnglish||''} onChange={(v,l)=>patch('hasEnglish',v,l)}/><FilterSelect label="International students" value={filters.applicant||''} onChange={(v,l)=>patch('applicant',v,l)} options={APPLICANT_OPTIONS}/><TriFilter label="Has scholarship" value={filters.hasScholarship||''} onChange={(v,l)=>patch('hasScholarship',v,l)}/><FilterSelect label="Min legacy presence" value={filters.minCompleteness||''} onChange={(v,l)=>patch('minCompleteness',v,l)} options={[50,75,90,100].map(n=>opt(String(n),`${n}%+`))}/><FilterSelect label="Freshness" value={filters.freshness||''} onChange={(v,l)=>patch('freshness',v,l)} options={[opt('never_verified','Never verified'),opt('modified_7d','Modified in 7 days'),opt('modified_30d','Modified in 30 days'),opt('stale_180d','Stale / never verified (180d)')]}/><FilterSelect label="Lifecycle" value={filters.lifecycle||''} onChange={(v,l)=>patch('lifecycle',v,l)} options={STATUS_OPTIONS}/><FilterSelect label="Publication" value={filters.publication||''} onChange={(v,l)=>patch('publication',v,l)} options={PUBLICATION_OPTIONS}/></>}
  </div>
}

function buildCatalogueArgs(type,{query,filters,offset,sort,direction}){const a={limit:PAGE_SIZE,offset,query:query||null,sort,direction};if(filters.country)a.country_code=filters.country;if(filters.subdivision)a.subdivision_code=filters.subdivision;if(filters.lifecycle)a.lifecycle_status=filters.lifecycle;if(filters.publication)a.publication_status=filters.publication;if(filters.universityGroup&&['course','provider'].includes(type))a.university_group=filters.universityGroup;if(type==='scholarship'&&filters.provider)a.provider_id=filters.provider;if(type==='course'){if(filters.provider)a.provider_id=filters.provider;if(filters.level)a.level_code=filters.level;if(filters.field)a.field_code=filters.field;if(filters.delivery)a.delivery_mode=filters.delivery;for(const k of['hasFee','hasIntake','hasEnglish','hasScholarship'])if(filters[k]!==''&&filters[k]!=null)a[camelToSnake(k)]=filters[k]==='true';if(filters.minCompleteness)a.min_completeness=Number(filters.minCompleteness);if(filters.freshness)a.freshness=filters.freshness;if(filters.applicant)a.applicant=filters.applicant}return a}
function camelToSnake(v){return v.replace(/[A-Z]/g,m=>'_'+m.toLowerCase())}
// v2.15.133 (Decision 200): who can apply. English is expected only where international students can apply.
const APPLICANT_OPTIONS=[{value:'international',label:'Open to international students'},{value:'domestic_only',label:'Domestic only'},{value:'both',label:'Open to both'},{value:'unknown',label:'Not yet known'}]
function activeFilters(f){return Object.entries(f).filter(([,v])=>v!==''&&v!==null&&v!==undefined)}
// Decision 219: the state filter is named the way each country names its divisions
export function regionLabel(c){return({AU:'State / territory',CA:'Province / territory',NZ:'Region',US:'State',GB:'Nation / region',IE:'County',DE:'State (Land)'})[String(c||'').toUpperCase()]||'State / region'}
function filterLabel(k){return({country:'Country',subdivision:'State / Region',provider:'Provider',level:'Study level',field:'Field',delivery:'Delivery',hasFee:'Has fee',hasIntake:'Has intake',hasEnglish:'Has English',hasScholarship:'Has scholarship',applicant:'International students',minCompleteness:'Min legacy presence',freshness:'Freshness',lifecycle:'Lifecycle',publication:'Publication',universityGroup:'University group'})[k]||humanise(k)}
const UNIVERSITY_GROUP_OPTIONS=[{value:'go8',label:'Group of Eight'},{value:'atn',label:'Australian Technology Network'},{value:'iru',label:'Innovative Research Universities'},{value:'run',label:'Regional Universities Network'}]
function filterValueLabel(k,v,d){if(['hasFee','hasIntake','hasEnglish','hasScholarship'].includes(k))return v==='true'?'Yes':'No';const sets={country:d.countries,subdivision:d.subdivisions,provider:d.providers,level:d.levels,field:d.fields,delivery:d.delivery_modes,universityGroup:UNIVERSITY_GROUP_OPTIONS};const list=sets[k]||[];const found=list.find(x=>String(x.id??x.code??x.value)===String(v));return found?.name??found?.label??humanise(v)}

function FilterSelect({label,value,onChange,options=[],loading=false}){const[open,setOpen]=useState(false),[search,setSearch]=useState(''),[page,setPage]=useState(0);const ref=useRef(null),inputRef=useRef(null);useEffect(()=>{const close=e=>{if(ref.current&&!ref.current.contains(e.target))setOpen(false)};addEventListener('mousedown',close);return()=>removeEventListener('mousedown',close)},[]);useEffect(()=>setPage(0),[search,options.length]);useEffect(()=>{if(open&&typeof window!=='undefined'&&window.matchMedia?.('(pointer:fine)').matches)setTimeout(()=>inputRef.current?.focus(),0)},[open]);const selected=options.find(x=>String(x.value)===String(value));const filtered=options.filter(x=>`${x.label} ${x.meta||''}`.toLowerCase().includes(search.toLowerCase())),pages=Math.max(1,Math.ceil(filtered.length/10)),safePage=Math.min(page,pages-1),visible=filtered.slice(safePage*10,safePage*10+10);return <div className="m-filter-select" ref={ref}><button className={`m-filter-button ${value?'has-value':''}`} onClick={()=>setOpen(x=>!x)}><span><small>{label}</small><strong>{selected?.label||'All'}</strong></span>{loading?<span className="m-spinner tiny"/>:<ChevronDown size={14}/>}</button>{open&&<div className="m-filter-popover"><div className="m-filter-search"><Search size={14}/><input ref={inputRef} value={search} onChange={e=>setSearch(e.target.value)} placeholder={`Search ${label.toLowerCase()}…`}/></div><button className={!value?'selected':''} onClick={()=>{onChange('','All');setOpen(false);setSearch('');setPage(0)}}><span>All</span></button>{visible.map(x=><button key={String(x.value)} className={String(value)===String(x.value)?'selected':''} onClick={()=>{onChange(x.value,x.label);setOpen(false);setSearch('');setPage(0)}}><span>{x.label}</span>{x.meta&&<small>{x.meta}</small>}</button>)}{!visible.length&&<div className="m-option-empty">No matching options</div>}{filtered.length>10&&<div className="m-filter-pager"><button disabled={safePage===0} onClick={()=>setPage(p=>Math.max(0,p-1))}>Previous</button><span>{safePage+1} / {pages}</span><button disabled={safePage>=pages-1} onClick={()=>setPage(p=>Math.min(pages-1,p+1))}>Next</button></div>}</div>}</div>}
function PagedFilterSelect({kind,label,value,valueLabel='',onChange,country='',subdivision=''}){const[open,setOpen]=useState(false),[search,setSearch]=useState(''),[offset,setOffset]=useState(0),[data,setData]=useState({items:[],total:0,has_more:false}),[busy,setBusy]=useState(false),[selectedLabel,setSelectedLabel]=useState(valueLabel);const ref=useRef(null),inputRef=useRef(null),debounced=useDebounce(search,220);useEffect(()=>{const close=e=>{if(ref.current&&!ref.current.contains(e.target))setOpen(false)};addEventListener('mousedown',close);return()=>removeEventListener('mousedown',close)},[]);useEffect(()=>{setOffset(0)},[debounced,country,subdivision,kind]);useEffect(()=>{if(valueLabel)setSelectedLabel(valueLabel);if(!value)setSelectedLabel('')},[value,valueLabel]);useEffect(()=>{if(!open)return;let live=true;setBusy(true);api.catalogueFilterPage({kind,country,subdivision,query:debounced,limit:10,offset}).then(x=>{if(!live)return;setData(x||{items:[],total:0,has_more:false});const hit=(x?.items||[]).find(y=>String(y.value)===String(value));if(hit)setSelectedLabel(hit.label)}).catch(()=>live&&setData({items:[],total:0,has_more:false})).finally(()=>live&&setBusy(false));return()=>{live=false}},[open,kind,country,subdivision,debounced,offset,value]);useEffect(()=>{if(open&&typeof window!=='undefined'&&window.matchMedia?.('(pointer:fine)').matches)setTimeout(()=>inputRef.current?.focus(),0)},[open]);const items=data.items||[],page=Math.floor(offset/10)+1,pages=Math.max(1,Math.ceil(Number(data.total||0)/10));return <div className="m-filter-select" ref={ref}><button className={`m-filter-button ${value?'has-value':''}`} onClick={()=>setOpen(x=>!x)}><span><small>{label}</small><strong>{selectedLabel||'All'}</strong></span>{busy?<span className="m-spinner tiny"/>:<ChevronDown size={14}/>}</button>{open&&<div className="m-filter-popover"><div className="m-filter-search"><Search size={14}/><input ref={inputRef} value={search} onChange={e=>setSearch(e.target.value)} placeholder={`Search ${label.toLowerCase()}…`}/></div><button className={!value?'selected':''} onClick={()=>{onChange('','All');setSelectedLabel('');setOpen(false);setSearch('');setOffset(0)}}><span>All</span></button>{items.map(x=><button key={String(x.value)} className={String(value)===String(x.value)?'selected':''} onClick={()=>{setSelectedLabel(x.label);onChange(x.value,x.label);setOpen(false);setSearch('');setOffset(0)}}><span>{x.label}</span>{x.meta&&<small>{x.meta}</small>}</button>)}{!items.length&&!busy&&<div className="m-option-empty">No matching options</div>}{Number(data.total||0)>10&&<div className="m-filter-pager"><button disabled={offset===0} onClick={()=>setOffset(o=>Math.max(0,o-10))}>Previous</button><span>{page} / {pages}</span><button disabled={!data.has_more} onClick={()=>setOffset(o=>o+10)}>Next</button></div>}</div>}</div>}
function AsyncPagedFilterSelect({kind,label,value,valueLabel='',onChange,country='',survey=''}){const[open,setOpen]=useState(false),[search,setSearch]=useState(''),[offset,setOffset]=useState(0),[data,setData]=useState({items:[],total:0,has_more:false}),[busy,setBusy]=useState(false),[selectedLabel,setSelectedLabel]=useState(valueLabel);const ref=useRef(null),inputRef=useRef(null),debounced=useDebounce(search,220);useEffect(()=>{const close=e=>{if(ref.current&&!ref.current.contains(e.target))setOpen(false)};addEventListener('mousedown',close);return()=>removeEventListener('mousedown',close)},[]);useEffect(()=>{setOffset(0)},[debounced,country,survey,kind]);useEffect(()=>{if(valueLabel)setSelectedLabel(valueLabel);if(!value)setSelectedLabel('')},[value,valueLabel]);useEffect(()=>{if(!open)return;let live=true;setBusy(true);api.filterOptionPage({kind,country,survey,query:debounced,limit:10,offset}).then(x=>{if(!live)return;setData(x||{items:[],total:0,has_more:false});const hit=(x?.items||[]).find(y=>String(y.value)===String(value));if(hit)setSelectedLabel(hit.label)}).catch(()=>live&&setData({items:[],total:0,has_more:false})).finally(()=>live&&setBusy(false));return()=>{live=false}},[open,kind,country,survey,debounced,offset,value]);useEffect(()=>{if(open&&typeof window!=='undefined'&&window.matchMedia?.('(pointer:fine)').matches)setTimeout(()=>inputRef.current?.focus(),0)},[open]);const items=data.items||[],page=Math.floor(offset/10)+1,pages=Math.max(1,Math.ceil(Number(data.total||0)/10));return <div className="m-filter-select" ref={ref}><button className={`m-filter-button ${value?'has-value':''}`} onClick={()=>setOpen(x=>!x)}><span><small>{label}</small><strong>{selectedLabel||'All'}</strong></span>{busy?<span className="m-spinner tiny"/>:<ChevronDown size={14}/>}</button>{open&&<div className="m-filter-popover"><div className="m-filter-search"><Search size={14}/><input ref={inputRef} value={search} onChange={e=>setSearch(e.target.value)} placeholder={`Search ${label.toLowerCase()}…`}/></div><button className={!value?'selected':''} onClick={()=>{onChange('','All');setSelectedLabel('');setOpen(false);setSearch('');setOffset(0)}}><span>All</span></button>{items.map(x=><button key={String(x.value)} className={String(value)===String(x.value)?'selected':''} onClick={()=>{setSelectedLabel(x.label);onChange(x.value,x.label);setOpen(false);setSearch('');setOffset(0)}}><span>{x.label}</span>{x.meta&&<small>{x.meta}</small>}</button>)}{!items.length&&!busy&&<div className="m-option-empty">No matching options</div>}{Number(data.total||0)>10&&<div className="m-filter-pager"><button disabled={offset===0} onClick={()=>setOffset(o=>Math.max(0,o-10))}>Previous</button><span>{page} / {pages}</span><button disabled={!data.has_more} onClick={()=>setOffset(o=>o+10)}>Next</button></div>}</div>}</div>}

function TriFilter({label,value,onChange}){return <FilterSelect label={label} value={value} onChange={onChange} options={[opt('true','Yes'),opt('false','No')]}/>}function opt(value,label,meta=''){return{value,label,meta}}
function DataTable({rows,columns,loading,sort,direction,onSort,onRow,selected}){return <div className="m-table-wrap"><table className="m-table m-fluid-table" style={{width:'100%',minWidth:'max-content'}}><thead><tr>{columns.map((c,i)=>{const max=Number(c.width||180),min=Math.min(max,96),vw=Math.max(9,Math.round(max/18));return <th key={c.key} className={i===0?'sticky-col':''} style={{minWidth:`clamp(${min}px,${vw}vw,${max}px)`}}><button disabled={!c.sortKey} onClick={()=>onSort(c.sortKey)}>{c.label}{c.sortKey&&sort===c.sortKey&&(direction==='asc'?<ArrowUp size={12}/>:<ArrowDown size={12}/>)}</button></th>})}</tr></thead><tbody>{loading&&rows.length===0?Array.from({length:8}).map((_,i)=><tr key={i}>{columns.map((c,j)=><td className={j===0?'sticky-col':''} key={c.key}><span className="m-row-skeleton"/></td>)}</tr>):rows.length?rows.map((r,i)=><tr key={r.id??r.course_id??i} className={String(selected)===String(r.id??r.course_id)?'selected':''} onClick={()=>onRow?.(r)}>{columns.map((c,j)=><td key={c.key} className={j===0?'sticky-col':''}>{cell(r,c.key)}</td>)}</tr>):<tr><td colSpan={columns.length}><EmptyInline text="No records match the current filters."/></td></tr>}</tbody></table></div>}

function columns(type,complete){if(complete)return[{key:'canonical_title',label:'Course',width:300,sortKey:'course'},{key:'provider_name',label:'Provider',width:240,sortKey:'provider'},{key:'course_code',label:'CRICOS / Course code',width:150},{key:'completeness_score_v2',label:'Legacy presence',width:120,sortKey:'completeness'},{key:'has_fee',label:'Fee',width:90},{key:'has_intake',label:'Intake',width:90},{key:'has_english',label:'English',width:90},{key:'last_verified_at',label:'Verified',width:150,sortKey:'verified'}];if(type==='provider')return[{key:'canonical_name',label:'Provider',width:300,sortKey:'provider'},{key:'country_code',label:'Country',width:110},{key:'subdivision_name',label:'State / Region',width:160},{key:'city',label:'City',width:150},{key:'course_count',label:'Courses',width:95,sortKey:'courses'},{key:'university_groups',label:'Group',width:110},{key:'evidence_count',label:'Evidence',width:95},{key:'lifecycle_status',label:'Lifecycle',width:115},{key:'publication_status',label:'Publication',width:130},{key:'last_verified_at',label:'Verified',width:150,sortKey:'verified'}];if(type==='course')return[{key:'canonical_title',label:'Course',width:310,sortKey:'course'},{key:'provider_name',label:'Provider',width:240,sortKey:'provider'},{key:'course_code',label:'CRICOS / Course code',width:155},{key:'subdivision_name',label:'State / Region',width:150},{key:'level_name',label:'Study level',width:150},{key:'field_of_study',label:'Field',width:190,sortKey:'field'},{key:'fee_amount',label:'CRICOS tuition',width:150,sortKey:'fee'},{key:'completeness_score_v2',label:'Legacy presence',width:120,sortKey:'completeness'},{key:'last_verified_at',label:'Verified',width:145,sortKey:'verified'}];if(type==='campus')return[{key:'name',label:'Campus',width:270,sortKey:'campus'},{key:'provider_name',label:'Provider',width:260,sortKey:'provider'},{key:'country_code',label:'Country',width:105},{key:'subdivision_name',label:'State / Region',width:160},{key:'city',label:'City',width:150,sortKey:'city'},{key:'course_count',label:'Courses',width:90,sortKey:'courses'},{key:'status',label:'Status',width:110}];return[{key:'name',label:'Scholarship',width:310,sortKey:'scholarship'},{key:'provider_name',label:'Provider',width:250,sortKey:'provider'},{key:'scholarship_type',label:'Type',width:170,sortKey:'type'},{key:'audience',label:'Audience',width:150,sortKey:'audience'},{key:'award_value_text',label:'Award',width:180,sortKey:'award'},{key:'publication_status',label:'Publication',width:130,sortKey:'publication'}]}
// v2.15.130 (sch-jargon): plain labels for scholarship type and audience codes.
const SCH_TYPE={provider_scholarship:'University scholarship',government_scholarship:'Government scholarship',external_scholarship:'External scholarship',bursary:'Bursary',fee_discount:'Fee discount'},SCH_AUD={international:'International students',domestic:'Domestic students',all:'All students'}
function cell(r,key){const v=r[key];if(key==='scholarship_type')return v?(SCH_TYPE[v]||humanise(v)):'—';if(key==='audience')return v?(SCH_AUD[v]||humanise(v)):'—';if(key==='university_groups')return <UniversityGroups value={v} short/>;if(['canonical_name','canonical_title','name'].includes(key))return <span className="m-cell-title"><strong>{v??'—'}</strong>{r.stable_key&&<small>{r.stable_key}</small>}</span>;if(key==='country_code')return <span>{countryFlag(v)} {v||'—'}</span>;if(key==='course_code')return v?<code className="m-code">{v}</code>:'—';if(key==='fee_amount')return v==null?'—':fmtMoney(v,r.fee_currency||'AUD');if(key==='completeness_score_v2')return <Score value={v??r.completeness_score}/>;if(['has_fee','has_intake','has_english','has_scholarship'].includes(key))return <Bool value={v}/>;if(key.includes('status')||key==='status')return <Status value={v}/>;if(key.endsWith('_at'))return v?fmtDate(v):'Never';return v==null||v===''?'—':String(v)}
function UniversityGroups({value,short=false}){const list=Array.isArray(value)?value:[];if(!list.length)return short?'—':null;return <span style={{display:'inline-flex',gap:4,flexWrap:'wrap'}}>{list.map(g=><span key={g.code} className="m-status status-info" title={g.name}>{short?String(g.code||'').toUpperCase():g.name}</span>)}</span>}
function Score({value}){const n=Math.max(0,Math.min(100,Number(value)||0));return <span className="m-score"><span><i style={{width:`${n}%`}}/></span><b>{fmtPercent(n)}</b></span>}
function Bool({value}){return <span className={`m-bool ${value?'yes':'no'}`}>{value?'Yes':'No'}</span>}
function Status({value}){const s=String(value??'unknown').toLowerCase();return <StatusChip value={s} label={humanise(s)}/>}


function DetailDrawer({type,data,busy,onClose,navigate,onError,onChanged}){useEffect(()=>{const k=e=>e.key==='Escape'&&onClose();addEventListener('keydown',k);return()=>removeEventListener('keydown',k)},[onClose]);const title=detailTitle(data,type);return <><button className="m-drawer-backdrop" onClick={onClose}/><aside className={"m-drawer m-drawer-"+type} aria-label={humanise(type)+" detail"}><div className="m-drawer-head"><div>{type==='provider'&&data?.id?<><small>Provider detail</small><ProviderBrand providerId={data.id} name={title} subtitle={[data?.country_code,data?.primary_city].filter(Boolean).join(' · ')} size={54}/></>:<><small>{humanise(type)} detail</small><h2>{title}</h2></>}</div><div style={{display:'flex',gap:6}}>{data?.id&&['provider','course'].includes(type)&&<button title={`Compare this ${type}`} onClick={()=>navigate?.('Compare',{type,ids:data.id})}><Activity size={17}/></button>}{data?.id&&['provider','course','campus','scholarship'].includes(type)&&<button title="Open supporting evidence" onClick={()=>navigate?.('Evidence',{entity_type:type,entity_id:data.id})}><BookOpen size={17}/></button>}<button onClick={onClose} aria-label={"Close "+humanise(type)+" detail"}><X size={18}/></button></div></div><div className="m-drawer-content">{busy?<div className="m-drawer-loading"><span className="m-spinner"/>Loading…</div>:<DetailBody type={type} data={data} navigate={navigate} onError={onError} onChanged={onChanged}/>}</div></aside></>}
function detailTitle(d,type){if(!d)return'Loading…';return d.display_title||d.canonical_title||d.canonical_name||d.name||d.stable_key||humanise(type)}
function InternationalContacts({data,navigate}){const block=data?.international_contacts||{},items=Array.isArray(block.items)?block.items:[],events=Array.isArray(block.events)?block.events:[],summary=block.summary||{},profile=block.profile||{},disposition=block.disposition||{};return <section className="m-detail-section cf-contact-intel"><style>{`
.cf-contact-intel{display:grid;gap:10px}.cf-contact-head{display:flex;justify-content:space-between;gap:12px;align-items:flex-start}.cf-contact-head h3{margin:0;font-size:var(--cf-fs-base)}.cf-contact-head p{margin:4px 0 0;color:var(--cf-slate-500);font-size:var(--cf-fs-xs);line-height:1.45}.cf-contact-summary{display:flex;gap:6px;flex-wrap:wrap}.cf-contact-summary span{border:1px solid var(--cf-slate-200);background:var(--cf-slate-50);border-radius:var(--cf-radius-pill);padding:4px 7px;font-size:var(--cf-fs-2xs);color:var(--cf-slate-600);font-weight:750}.cf-contact-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}.cf-contact-card{border:1px solid var(--cf-slate-200);border-radius:var(--cf-radius-lg);background:var(--cf-white);padding:10px;display:grid;gap:7px}.cf-contact-card.primary{border-color:var(--cf-indigo-200);background:var(--cf-slate-50)}.cf-contact-top{display:flex;justify-content:space-between;gap:8px;align-items:flex-start}.cf-contact-name{display:grid;gap:2px}.cf-contact-name strong{font-size:var(--cf-fs-md);color:var(--cf-slate-900)}.cf-contact-name small{font-size:var(--cf-fs-2xs);color:var(--cf-slate-500)}.cf-contact-badge{white-space:nowrap;border-radius:var(--cf-radius-pill);padding:3px 6px;font-size:var(--cf-fs-3xs);font-weight:850;background:var(--cf-indigo-50);color:var(--cf-indigo-700)}.cf-contact-badge.enriched{background:var(--cf-slate-100);color:var(--cf-slate-600)}.cf-contact-territory{display:grid;gap:2px;padding:7px 8px;border-radius:var(--cf-radius-md);background:var(--cf-slate-50)}.cf-contact-territory small{font-size:var(--cf-fs-3xs);text-transform:uppercase;letter-spacing:.04em;color:var(--cf-slate-400);font-weight:800}.cf-contact-territory strong{font-size:var(--cf-fs-xs);color:var(--cf-slate-700);line-height:1.45}.cf-contact-links{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.cf-contact-links a{font-size:var(--cf-fs-2xs);color:var(--cf-indigo-600);text-decoration:none}.cf-contact-meta{font-size:var(--cf-fs-3xs);color:var(--cf-slate-400);line-height:1.4}.cf-contact-changes{border-top:1px solid var(--cf-slate-150);padding-top:8px}.cf-contact-changes strong{font-size:var(--cf-fs-2xs);color:var(--cf-slate-600)}.cf-contact-changes span{display:block;font-size:var(--cf-fs-3xs);color:var(--cf-slate-500);margin-top:3px}@media(max-width:760px){.cf-contact-grid{grid-template-columns:1fr}.cf-contact-head{display:grid}.cf-contact-summary{justify-content:flex-start}}
`}</style><div className="cf-contact-head"><div><h3>International contacts</h3><p>First-party university contacts are preferred. Licensed professional enrichment is secondary and does not overwrite university-published assignments.</p>{data?.id&&<button className="m-secondary compact" style={{marginTop:7}} onClick={()=>navigate?.('Provider Contacts',{provider_id:data.id})}><UsersRound size={12}/>View all Provider Contacts</button>}</div><div className="cf-contact-summary"><span>{humanise(disposition.disposition||'pending_acquisition')}</span><span>{Number(summary.first_party_contacts||0)} first-party</span><span>{Number(summary.enriched_contacts||0)} enriched</span>{Number(summary.unacknowledged_changes||0)>0&&<span>{summary.unacknowledged_changes} change signal{Number(summary.unacknowledged_changes)===1?'':'s'}</span>}</div></div>{!items.length&&disposition.disposition&&<div className="cf-contact-meta">A16 disposition: <strong>{humanise(disposition.disposition)}</strong>. Qualified first-party evidence is retained; missing contacts are never manufactured.</div>}{items.length?<div className="cf-contact-grid">{items.map((x,i)=><article key={x.id||i} className={`cf-contact-card ${x.source_class==='first_party'?'primary':''}`}><div className="cf-contact-top"><div className="cf-contact-name"><strong>{x.full_name||x.team_name||'International team'}</strong><small>{x.job_title||x.team_name||'Professional contact'}</small></div><span className={`cf-contact-badge ${x.source_class==='licensed_enrichment'?'enriched':''}`}>{x.source_class==='first_party'?'First-party university':'Licensed enrichment'}</span></div>{x.territory_text&&<div className="cf-contact-territory"><small>Territory / market</small><strong>{x.territory_text}</strong></div>}<div className="cf-contact-links">{x.work_email&&<a href={`mailto:${x.work_email}`}>{x.work_email}</a>}{x.work_phone&&<a href={`tel:${String(x.work_phone).replace(/[^+0-9]/g,'')}`}>{x.work_phone}</a>}{x.source_url&&<a href={x.source_url} target="_blank" rel="noreferrer">University source <ExternalLink size={9}/></a>}{x.professional_profile_url&&<a href={x.professional_profile_url} target="_blank" rel="noreferrer">Professional profile <ExternalLink size={9}/></a>}{x.evidence_id&&<EvidenceButton id={x.evidence_id} navigate={navigate}/>}</div><div className="cf-contact-meta">{x.source_provider?humanise(x.source_provider):'Source retained'} · Verified {x.last_verified_at?fmtDate(x.last_verified_at):'—'}{x.verification_state&&` · ${humanise(x.verification_state)}`}</div>{x.layer4&&<details><summary style={{fontSize:9,fontWeight:800,cursor:'pointer'}}>Layer 4 resolve</summary><Layer4Intervention type="provider_contact" data={x} publicationEnabled={false}/></details>}</article>)}</div>:<EmptyInline text={profile.enabled===false?'Contact discovery is disabled for this Provider.':'No current international recruitment contact has been verified yet.'}/>} {events.length>0&&<div className="cf-contact-changes"><strong>Recent contact signals</strong>{events.slice(0,3).map((e,i)=><span key={e.id||i}>{humanise(e.event_type)} · {e.detected_at?fmtDate(e.detected_at):'—'}</span>)}</div>}</section>}

function DetailBody({type,data,navigate,onError,onChanged}){if(!data)return <EmptyInline text="No detail returned."/>;if(type==='course')return <div><div className="m-drawer-body" style={{paddingBottom:0}}>{data.id&&<CourseEditor courseId={data.id} onChanged={onChanged} onError={onError}/>}<SourceComparison type="course" id={data.id} navigate={navigate}/></div><CourseDetailPolish data={data} navigate={navigate}/><div className="m-drawer-body" style={{paddingTop:0}}><CourseScholarships data={data.course_scholarships} navigate={navigate}/><Layer4Intervention type={type} data={data}/></div></div>;const scalars=Object.entries(data).filter(([,v])=>v==null||['string','number','boolean'].includes(typeof v)).slice(0,24);return <div className="m-drawer-body">{type==='provider'&&data.id&&<ProviderEditor providerId={data.id} onChanged={onChanged} onError={onError}/>}{type==='provider'&&data.id&&<ProviderRankings providerId={data.id} navigate={navigate}/>}{type==='scholarship'&&data.id&&<SourceComparison type="scholarship" id={data.id} navigate={navigate}/>}{type==='scholarship'&&<ScholarshipEligibility data={data}/>}<div className="m-detail-grid">{type==='provider'&&Array.isArray(data.university_groups)&&data.university_groups.length>0&&<div className="m-detail-university-group"><small>University group</small><strong><UniversityGroups value={data.university_groups}/></strong></div>}{scalars.map(([k,v])=><div key={k}><small>{humanise(k)}</small><strong>{formatScalar(k,v)}</strong></div>)}</div>{type==='provider'&&<InternationalContacts data={data} navigate={navigate}/>} {type==='provider'&&<ContextualInsights data={data.contextual_insights} navigate={navigate} entityType="provider"/>}{['provider','campus','scholarship'].includes(type)&&<Layer4Intervention type={type} data={data}/>}<ObjectSections data={data} exclude={type==='provider'?['contextual_insights','international_contacts','layer4','layer4_publication','university_groups']:['layer4','layer4_publication']} navigate={navigate}/></div>}

function CourseScholarships({data,navigate}){
 const items=Array.isArray(data?.items)?data.items:[]
 return <section className="m-detail-section"><h3>Scholarships</h3><p className="m-help">Only scholarships whose page names this course, or all of the university's courses, are shown. A scholarship from the same university is not assumed to apply.</p>
  {items.length?<div className="m-record-list">{items.map(x=><div className="m-record" key={x.mapping_id||x.scholarship_id}><strong>{x.name}</strong><span>{x.award_value_text||'Award value not published'}{x.academic_year?' · '+x.academic_year:''}</span><small>{humanise(x.mapping_basis||'governed mapping')} · {humanise(x.mapping_state||'mapped')}</small><div>{x.source_url&&<a href={x.source_url} target="_blank" rel="noreferrer">Official Scholarship source <ExternalLink size={11}/></a>}{x.evidence_id&&<EvidenceButton id={x.evidence_id} navigate={navigate}/>}</div></div>)}</div>:<EmptyInline text={data?.state==='needs_review'?'Possible scholarships wait for a decision on Scholarships › Course links.':'No scholarship is linked to this course yet.'}/>}
 </section>
}

function CourseSemantics({data,navigate}){const fees=data.fee_summary||{},cricos=fees.cricos_registered||[],provider=fees.provider_current||[];return <><section className="m-detail-section"><h3>Fee semantics</h3><p className="m-help">CRICOS registered total-course values are kept separate from Provider-current published fees. Evidence links open the exact supporting artifact.</p><div className="m-semantic-grid"><div><small>CRICOS registered rows</small><strong>{cricos.length}</strong>{cricos.slice(0,4).map((x,i)=><span key={i}>{humanise(x.fee_type)} · {x.amount==null?'—':fmtMoney(x.amount,x.currency||x.currency_code||'AUD')} · {humanise(x.basis)} {evidenceIdOf(x)&&<EvidenceButton id={evidenceIdOf(x)} navigate={navigate}/>}</span>)}</div><div><small>Provider-current rows</small><strong>{provider.length}</strong>{provider.length?provider.slice(0,4).map((x,i)=><span key={i}>{humanise(x.fee_type)} · {x.amount==null?'—':fmtMoney(x.amount,x.currency||x.currency_code||'AUD')} {evidenceIdOf(x)&&<EvidenceButton id={evidenceIdOf(x)} navigate={navigate}/>}</span>):<span>No Provider-current fee observation.</span>}</div></div></section>{data.state_summary&&<KeyObject title="Publication & Search state" value={data.state_summary} navigate={navigate}/>} {data.entry_summary&&<KeyObject title="Intakes & English" value={data.entry_summary} navigate={navigate}/>} {data.taxonomy_summary&&<KeyObject title="Taxonomy lineage" value={data.taxonomy_summary} navigate={navigate}/>}</>}
function ObjectSections({data,exclude=[],navigate}){return <>{Object.entries(data).filter(([k,v])=>!exclude.includes(k)&&v&&typeof v==='object').map(([k,v])=><KeyObject key={k} title={humanise(k)} value={v} navigate={navigate}/>)}</>}
function KeyObject({title,value,navigate}){const arr=Array.isArray(value)?value:null;return <section className="m-detail-section"><h3>{title}</h3>{arr?<div className="m-record-list">{arr.length?arr.slice(0,25).map((x,i)=><Record key={x?.id||i} value={x} navigate={navigate}/>):<EmptyInline text="No records."/>}</div>:<div className="m-kv-list">{Object.entries(value||{}).slice(0,30).map(([k,v])=><div key={k}><span>{humanise(k)}</span><strong>{typeof v==='object'?summarise(v):formatScalar(k,v)}</strong>{typeof v==='object'&&evidenceIdOf(v)&&<EvidenceButton id={evidenceIdOf(v)} navigate={navigate}/>}</div>)}</div>}</section>}
function Record({value,navigate}){if(value==null)return null;if(typeof value!=='object')return <div className="m-record"><span>{String(value)}</span></div>;const title=value.title||value.name||value.canonical_title||value.source_label||value.evidence_type||value.status||value.code||value.id;return <div className="m-record"><strong>{title||'Record'}</strong><span>{Object.entries(value).filter(([k,v])=>k!=='id'&&v!=null&&typeof v!=='object').slice(0,4).map(([k,v])=>`${humanise(k)}: ${formatScalar(k,v)}`).join(' · ')}</span>{evidenceIdOf(value)&&<EvidenceButton id={evidenceIdOf(value)} navigate={navigate}/>}</div>}
function evidenceIdOf(v){return v?.evidence_id||v?.evidence?.id||v?.source_evidence_id||null}
function EvidenceButton({id,navigate}){return <button className="m-secondary compact" style={{marginLeft:6,padding:'3px 6px',fontSize:8}} onClick={e=>{e.stopPropagation();navigate?.('Evidence',{evidence_id:id})}}><BookOpen size={11}/>Evidence</button>}


function Qilt({onError}){return <InsightWorkspace kind="qilt" onError={onError}/>}function Prisms({onError}){return <InsightWorkspace kind="prisms" onError={onError}/>} 
function InsightWorkspace({kind,onError}){
 const[filters,setFilters]=useState({}),[filterLabels,setFilterLabels]=useState({}),[options,setOptions]=useState({}),[data,setData]=useState(null),[busy,setBusy]=useState(false),[offset,setOffset]=useState(0),[query,setQuery]=useState(''),[sort,setSort]=useState(kind==='qilt'?'provider':'geography'),[direction,setDirection]=useState('asc')
 useEffect(()=>{const p=kind==='qilt'?api.qiltFilterOptions(filters.survey||''):api.prismsFilterOptions();p.then(setOptions).catch(e=>onError(e.message))},[kind,filters.survey])
 const debounced=useDebounce(query,280)
 useEffect(()=>{setBusy(true);const p=kind==='qilt'?api.qiltPage({limit:PAGE_SIZE,offset,query:debounced,survey:filters.survey||'',metric:filters.metric||'',provider:filters.provider||'',status:filters.status||'',year:filters.year||'',sort,direction}):api.prismsPage({limit:PAGE_SIZE,offset,query:debounced,subdivision:filters.subdivision||'',studyArea:filters.studyArea||'',sector:filters.sector||'',remoteness:filters.remoteness||'',suppressed:filters.suppressed===''?null:filters.suppressed==='true',sort,direction});p.then(setData).catch(e=>onError(e.message)).finally(()=>setBusy(false))},[kind,offset,debounced,JSON.stringify(filters),sort,direction])
 useEffect(()=>setOffset(0),[debounced,JSON.stringify(filters),sort,direction])
 const rows=rowsOf(data),total=Number(data?.total??rows.length)
 function patch(k,v,label=''){setFilters(f=>{const n={...f,[k]:v};if(kind==='qilt'&&k==='survey'){n.metric='';n.provider=''}return n});setFilterLabels(l=>{const n={...l,[k]:label||''};if(kind==='qilt'&&k==='survey'){delete n.metric;delete n.provider}return n})}
 function changeSort(k){if(!k)return;if(sort===k)setDirection(d=>d==='asc'?'desc':'asc');else{setSort(k);setDirection('asc')}}
 const sortMap=kind==='qilt'?{provider_name:'provider',survey_code:'survey',survey_name:'survey',metric_code:'metric',metric_name:'metric',metric_value:'value',national_benchmark:'benchmark',response_count:'responses',collection_year_from:'year',collection_year_to:'year'}:{source_geography_name:'geography',subdivision_code:'state',subdivision_name:'state',source_study_area_code:'study_area',source_study_area_name:'study_area',enrolments:'enrolments',commencements:'commencements',period_start:'period',period_end:'period'}
 return <div className="m-page-stack"><section className="m-panel"><div className="m-workspace-head"><div><h2>{kind==='qilt'?'QILT outcomes':'PRISMS student flow'}</h2><p>Figures as published, kept separately from our provider records.</p></div><div className="m-result-count"><strong>{fmtNumber(total)}</strong><span>matching</span></div></div><div className="m-search-row"><label className="m-searchbox"><Search size={16}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search…"/></label></div><div className="m-filter-bar">{kind==='qilt'?<><FilterSelect label="Survey" value={filters.survey||''} onChange={(v,l)=>patch('survey',v,l)} options={normaliseOptions(options.surveys)}/><AsyncPagedFilterSelect kind="qilt_metric" label="Metric" value={filters.metric||''} valueLabel={filterLabels.metric||''} survey={filters.survey||''} onChange={(v,l)=>patch('metric',v,l)}/><AsyncPagedFilterSelect kind="qilt_provider" label="Provider" value={filters.provider||''} valueLabel={filterLabels.provider||''} survey={filters.survey||''} onChange={(v,l)=>patch('provider',v,l)}/><FilterSelect label="Year" value={filters.year||''} onChange={(v,l)=>patch('year',v,l)} options={normaliseOptions(options.years)}/><FilterSelect label="Status" value={filters.status||''} onChange={(v,l)=>patch('status',v,l)} options={normaliseOptions(options.statuses)}/></>:<><FilterSelect label={regionLabel(filters.country)} value={filters.subdivision||''} onChange={(v,l)=>patch('subdivision',v,l)} options={normaliseOptions(options.subdivisions)}/><AsyncPagedFilterSelect kind="prisms_study_area" label="Study area" value={filters.studyArea||''} valueLabel={filterLabels.studyArea||''} onChange={(v,l)=>patch('studyArea',v,l)}/><FilterSelect label="Sector" value={filters.sector||''} onChange={(v,l)=>patch('sector',v,l)} options={normaliseOptions(options.sectors)}/><FilterSelect label="Remoteness" value={filters.remoteness||''} onChange={(v,l)=>patch('remoteness',v,l)} options={normaliseOptions(options.remoteness)}/></>}</div><DynamicTable rows={rows} loading={busy} sort={sort} direction={direction} sortMap={sortMap} onSort={changeSort}/><Pager offset={offset} limit={PAGE_SIZE} total={total} onOffset={setOffset}/></section></div>
}


function OperationalList({operation,title,onError}){const[data,setData]=useState(null),[busy,setBusy]=useState(true),[query,setQuery]=useState('');useEffect(()=>{setBusy(true);adminRead(operation,{limit:200,offset:0,query:query||null}).then(setData).catch(e=>onError(e.message)).finally(()=>setBusy(false))},[operation,query]);const rows=rowsOf(data);return <div className="m-page-stack"><section className="m-panel"><div className="m-workspace-head"><div><h2>{title}</h2><p>Role-checked operational data; sensitive internal schemas remain private.</p></div><div className="m-result-count"><strong>{fmtNumber(data?.total??rows.length)}</strong><span>records</span></div></div><div className="m-search-row"><label className="m-searchbox"><Search size={16}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder={`Search ${title.toLowerCase()}…`}/></label></div><DynamicTable rows={rows} loading={busy}/></section></div>}

function Attributes({onError}){const[data,setData]=useState(null),[busy,setBusy]=useState(true);useEffect(()=>{adminRead('attributes',{limit:200}).then(setData).catch(e=>onError(e.message)).finally(()=>setBusy(false))},[]);if(busy)return <div className="m-skeleton panel tall"/>;const groups=[['Families',data?.families,Layers3],['Groups',data?.groups,Tags],['Attributes',data?.attributes,SlidersHorizontal],['Options',data?.options,ListChecks],['Completeness profiles',data?.completeness_profiles,CheckCircle2]];return <div className="m-page-stack"><div className="m-summary-strip attributes">{groups.map(([label,rows,Icon])=><SummaryCard key={label} icon={Icon} label={label} value={fmtNumber(rows?.length||0)} tone="indigo"/>)}</div>{groups.map(([label,rows,Icon])=><section className="m-panel" key={label}><PanelTitle icon={Icon} title={label} subtitle={`Governed PIM ${label.toLowerCase()} configuration`}/><DynamicTable rows={rows||[]} loading={false}/></section>)}</div>}

function DynamicTable({rows,loading,sort='',direction='asc',sortMap={},onSort}){const cols=useMemo(()=>dynamicColumns(rows),[rows]);return <div className="m-table-wrap"><table className="m-table dynamic m-fluid-table" style={{width:'100%',minWidth:'max-content'}}><thead><tr>{cols.map((c,i)=>{const sk=sortMap[c]||'';return <th key={c} className={i===0?'sticky-col':''} style={{minWidth:`clamp(96px,12vw,220px)`}}>{sk?<button onClick={()=>onSort?.(sk)}>{humanise(c)}{sort===sk&&(direction==='asc'?<ArrowUp size={12}/>:<ArrowDown size={12}/>)}</button>:<span>{humanise(c)}</span>}</th>})}</tr></thead><tbody>{loading&&rows.length===0?Array.from({length:6}).map((_,i)=><tr key={i}>{Array.from({length:Math.max(cols.length,5)}).map((_,j)=><td key={j}><span className="m-row-skeleton"/></td>)}</tr>):rows.length?rows.map((r,i)=><tr key={r.id??i}>{cols.map((c,j)=><td key={c} className={j===0?'sticky-col':''}>{genericCell(c,r[c])}</td>)}</tr>):<tr><td colSpan={Math.max(cols.length,1)}><EmptyInline text="No records yet."/></td></tr>}</tbody></table></div>}
function dynamicColumns(rows){if(!rows?.length)return['status'];const priority=['name','title','source_label','job_type','domain','status','country_code','provider_name','course_title','evidence_type','priority','created_at','updated_at','captured_at'];const keys=Object.keys(rows[0]).filter(k=>!['payload','result','metadata','content'].includes(k)&&typeof rows[0][k]!=='object');return[...priority.filter(k=>keys.includes(k)),...keys.filter(k=>!priority.includes(k))].slice(0,11)}
function genericCell(k,v){if(v==null||v==='')return'—';if(k.includes('status')||k==='status')return <Status value={v}/>;if(k.endsWith('_at'))return fmtDateTime(v);if(k==='country_code')return `${countryFlag(v)} ${v}`;if(k==='id'||k.endsWith('_id'))return <code className="m-code subtle">{String(v).slice(0,8)}…</code>;return String(v)}


function useDebounce(value,delay){const[v,setV]=useState(value);useEffect(()=>{const t=setTimeout(()=>setV(value),delay);return()=>clearTimeout(t)},[value,delay]);return v}
function rowsOf(data){if(Array.isArray(data))return data;return data?.items??data?.rows??data?.data??[]}
function normaliseOptions(list){if(!Array.isArray(list))return[];return list.map(x=>{if(x==null)return null;if(typeof x!=='object')return opt(String(x),humanise(x));const value=x.id??x.code??x.value??x.name??x.label;return opt(String(value),x.name??x.label??humanise(value),x.code&&x.code!==value?x.code:'')}).filter(Boolean)}
function roleLabel(value){return value==='pim_admin'?'PIM Operator':humanise(value)}
function humanise(v){if(v==null)return'—';return String(v).replace(/[_-]+/g,' ').replace(/\b\w/g,m=>m.toUpperCase())}
function relativeTime(v){const d=new Date(v);if(Number.isNaN(+d))return'unknown';const s=Math.round((Date.now()-d.getTime())/1000),a=Math.abs(s);if(a<60)return'just now';if(a<3600)return`${Math.round(a/60)}m ago`;if(a<86400)return`${Math.round(a/3600)}h ago`;if(a<604800)return`${Math.round(a/86400)}d ago`;return fmtDate(v)}
function countryFlag(code){const c=String(code||'').toUpperCase();if(c.length!==2)return'';return String.fromCodePoint(...[...c].map(x=>127397+x.charCodeAt()))}
function formatScalar(k,v){if(v==null||v==='')return'—';if(typeof v==='boolean')return v?'Yes':'No';if(k.endsWith('_at')||k==='valid_from'||k==='valid_to')return fmtDateTime(v);if(typeof v==='number')return fmtNumber(v);return String(v)}
function summarise(v){if(Array.isArray(v))return`${v.length} record${v.length===1?'':'s'}`;return`${Object.keys(v||{}).length} fields`}

createRoot(document.getElementById('root')).render(<React.StrictMode><App/></React.StrictMode>)
