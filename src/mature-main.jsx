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
import CourseDetailPolish from'./CourseDetailPolish'
import EnrichFields from'./EnrichFields'
import FeeReader from'./FeeReader'
import FieldCoverage from'./FieldCoverage'
import EnrichPlan from'./EnrichPlan'
import{ProviderSummary,PillRow,FactCards,FactCard}from'./DetailSummary'
import{startTableResize}from'./table-resize'
import'./ui-standard.css'
import{CourseEditor,ProviderEditor,CreateRecord}from'./RecordEditor'
import ArchivedReview from'./ArchivedReview'
import ScholarshipCoverage from'./ScholarshipCoverage'
import ScholarshipExtraction from'./ScholarshipExtraction'
import ListEdit from'./ListEdit'
import DashboardHome from'./Dashboard'
import ContextualInsights from'./ContextualInsights'
import ProviderLogo,{ProviderBrand,logoCapability}from'./ProviderLogo'
import FlagsPanel from'./FlagsPanel'
import ApiUsagePanel from'./ApiUsagePanel'
import{SectionTitle,fmtNumber,PanelTitle,Pulse,SummaryCard,EmptyState,EmptyInline,Pager,useRememberedState,StatusChip,FilterChip,PageHeader,PageLayout,StatusDot,Metric}from'./ui-kit'
import{PAGES,SECTIONS,SECTION_OF,resolveTarget,hrefFor,canOpen,shownTabs,effectiveTab}from'./nav-map'
import PlatformHealth,{readPlatformHealth,healthTone,HEALTH_WORDS}from'./PlatformHealth'
import QueueWatch from'./QueueWatch'
import CourseSources from'./CourseSources'
import{DomainReadiness}from'./data-quality-entry'
import CreditBanner from'./CreditBanner'
import{ProviderRankings,RankingLinkPicker}from'./RankingLinks'
import ScholarshipRecord from'./ScholarshipRecord'
import{ProviderScholarshipAction,ProviderScholarshipSearch,CourseScholarshipAction,ProviderFillAction}from'./ScholarshipActions'
import{LayerNotices}from'./Toolsets'
import Layer4Intervention from'./Layer4Intervention'
import{UI_VERSION}from'./release-manifest.js'
import{ReleasePill,applyReleaseIdentity}from'./ReleaseNotes'
import{reportError,plainError}from'./lib/errors'
import'./styles.css'
import'./mature.css'
import'./admin-pages.css'
// v2.15.217 (code split): screens used only inside one page load on demand. If a screen's file is gone because a newer release was deployed
// while this tab was open, the page reloads once to pick up the new release instead of showing an error.
function lazyPage(load,name='default'){return React.lazy(()=>load().then(m=>({default:m[name]})).catch(e=>{let again=false;try{again=sessionStorage.getItem('cf-chunk-reload')!==String(location.pathname+location.hash)}catch{}if(again&&/dynamically imported module|Importing a module script failed|Failed to fetch/i.test(String(e?.message||e))){try{sessionStorage.setItem('cf-chunk-reload',String(location.pathname+location.hash))}catch{}location.reload();return new Promise(()=>{})}throw e}))}
const EvidenceWorkspace=lazyPage(()=>import('./EvidenceWorkspace'))
const ModelsServices=lazyPage(()=>import('./ModelsServices'))
const AiConfig=lazyPage(()=>import('./AiConfig'))
const StatisticsDatasets=lazyPage(()=>import('./StatisticsDatasets'))
const ReferenceSources=lazyPage(()=>import('./ReferenceSources'))
const KeyDates=lazyPage(()=>import('./KeyDates'))
const ComparisonWorkspace=lazyPage(()=>import('./ComparisonWorkspace'))
const ProviderContactsWorkspace=lazyPage(()=>import('./ProviderContactsWorkspace'))
const Layer4Inbox=lazyPage(()=>import('./Layer4Inbox'))
const Automations=lazyPage(()=>import('./Automations'))
const SearchCapCard=lazyPage(()=>import('./SearchCapCard'))
const PipelineSettings=lazyPage(()=>import('./PipelineSettings'))
const CoverageView=lazyPage(()=>import('./course-coverage'),'CoverageView')
const AdaptersWorkspace=lazyPage(()=>import('./AdaptersWorkspace'))
const Layer23Operations=lazyPage(()=>import('./Layer23Operations'))
const ScreenUse=lazyPage(()=>import('./ScreenUse'))
const AdapterBuilderTab=lazyPage(()=>import('./AdapterBuilderTab'))
const BuildAdapter=lazyPage(()=>import('./BuildAdapter'))
const LinkRefresh=lazyPage(()=>import('./LinkRefresh'))
const ScholarshipLayer=lazyPage(()=>import('./ScholarshipLayer'))
const Progress=lazyPage(()=>import('./Progress'))
const AdminTasks=lazyPage(()=>import('./AdminTasks'))
const PlatformGuide=lazyPage(()=>import('./PlatformGuide'))
const Sop=lazyPage(()=>import('./Sops'))
const Layer1Sources=lazyPage(()=>import('./layer1-operations-entry'),'Layer1Sources')
const RefreshWorkspace=lazyPage(()=>import('./m2-3-intelligence-entry'),'Refresh')
const Layer2ProviderConfig=lazyPage(()=>import('./layer2-provider-entry'),'Console')
const PlatformMaturity=lazyPage(()=>import('./platform-maturity-entry'))
const EnvironmentMigrationWorkspace=lazyPage(()=>import('./EnvironmentMigrationWorkspace'))
const AccessRolesEmbedded=lazyPage(()=>import('./access-roles-entry'),'AccessRolesEmbedded')
const JobsWorkspace=lazyPage(()=>import('./pipeline-ops-entry'),'JobsWorkspace')
const SourcesWorkspace=lazyPage(()=>import('./pipeline-ops-entry'),'SourcesWorkspace')
const Toolsets=lazyPage(()=>import('./Toolsets'))
const SettingsBackup=lazyPage(()=>import('./SettingsBackup'))
const RetentionScreen=lazyPage(()=>import('./RetentionScreen'))

// Decision 217: the attributes view and the fee schedules below it share the Coverage country and university filter
// v2.15.301 (Platform Admin, 20 Oct 2026, "Merge into one Sources page"): one Sources page with a layer filter. Registers (Layer 1) shows the
// official registers with run, schedule and settings; All layers lists every source the pipeline reads (the old Sources page).
const SOURCE_FILTERS=[['registers','Registers (Layer 1)'],['all','All layers']]
function SourcesPage({routeParams,navigate}){
  const layer=routeParams?.get?.('layer')==='all'?'all':'registers'
  return <div className="m-page-stack" data-sources-page={layer}>
    <div className="pg-views" role="toolbar" aria-label="Source layer">{SOURCE_FILTERS.map(([k,l])=><button key={k} type="button" className={`pg-view${layer===k?' is-on':''}`} aria-pressed={layer===k} data-sources-layer={k} onClick={()=>navigate('layer1',k==='registers'?{}:{layer:k})}>{l}</button>)}</div>
    {layer==='all'?<SourcesWorkspace/>:<Layer1Sources/>}
  </div>
}
// v2.15.301 (Platform Admin, 20 Oct 2026, "One list with a type filter"): Key dates and Reference sources, one list; Ranking imports is on
// Rankings & statistics › Datasets.
const REFERENCE_TYPES=[['','All'],['dates','Key dates'],['links','Reference sources']]
function ReferenceList({routeParams,navigate,onError}){
  const t=routeParams?.get?.('type')||'',type=REFERENCE_TYPES.some(([k])=>k===t)?t:''
  return <div className="m-page-stack" data-reference-list={type||'all'}>
    <div className="pg-views" role="toolbar" aria-label="Type">{REFERENCE_TYPES.map(([k,l])=><button key={k||'all'} type="button" className={`pg-view${type===k?' is-on':''}`} aria-pressed={type===k} data-reference-type={k||'all'} onClick={()=>navigate('reference',k?{type:k}:{})}>{l}</button>)}</div>
    {type!=='links'&&<KeyDates onError={onError}/>}
    {type!=='dates'&&<ReferenceSources onError={onError}/>}
  </div>
}
function CoverageAttributes({rank}){
  const[scope,setScope]=useState({country:'',provider:null})
  return <div className="m-page-stack"><CoverageView view="attributes" onScope={setScope} belowFilters={({country,provider})=><FieldCoverage rank={rank} country={country} provider={provider}/>}/><details className="m-admin-advanced cov-by-area"><summary>By area: providers, courses, campuses and scholarships</summary><DomainReadiness rank={rank}/></details>{rank>=4&&<p className="sd-desc" data-attributes-moved>Fee schedules, English policies and academic calendars are approved in <a className="cf-link" href="#layer-2-discovery?tab=builder">Layer 2 › Adapter builder</a> (1.3) for one university, or across universities on <a className="cf-link" href="#layer-2-discovery?tab=universities">Layer 2 › Onboarding</a>.</p>}</div>
}

// v2.15.253 (Platform Admin, 12 Oct 2026): Layer 4 › Attributes retired. Fee schedules, English policies and academic calendars are
// approved in Layer 2 › Adapter builder (1.3) for one university, or across universities on Providers › Onboarding.

// v2.15.291: the version comes only from release-manifest.js (the old fixed '2.15.78' here was corrected after drawing by a
// separate script, now retired). The pill and its release notes are ReleaseNotes.jsx.
applyReleaseIdentity()
const PAGE_SIZE=50
// 8 Oct 2026 (Platform Admin): any edition can be uploaded, including next year's (QS names its edition a year ahead): from two years ahead back to 2010.
const rankingYearOptions=()=>{const top=new Date().getFullYear()+2;return Array.from({length:top-2009},(_,i)=>top-i)}
const rankingDefaultYear=system=>system==='qs_wur'?new Date().getFullYear()+1:new Date().getFullYear()
const rankingPublisherName=system=>system==='the_wur'?'Times Higher Education':system==='arwu'?'ShanghaiRanking Consultancy':'QS Quacquarelli Symonds'
// v2.15.121: ranking publisher addresses come from Reference sources (use "Ranking publisher", by ranking key), not code.
let RANKING_SOURCES={}
const rankingSourceUrl=system=>RANKING_SOURCES[system]||''
async function loadRankingSources(){try{const{data}=await supabase.rpc('admin_reference_sources_read');RANKING_SOURCES=Object.fromEntries((data?.items||[]).filter(x=>x.ref_key&&x.enabled&&!x.retired&&(x.uses||[]).includes('ranking_publisher')).map(x=>[x.ref_key,x.url]))}catch{}return RANKING_SOURCES}
const STATUS_OPTIONS=['active','archived','inactive','suspended','retired','unknown','any'].map(x=>({value:x,label:x==='any'?'Any status':humanise(x)}))
const PUBLICATION_OPTIONS=['published','unpublished','draft','review','archived'].map(x=>({value:x,label:humanise(x)}))
// v2.15.312 (Platform Admin, 22 Oct 2026 11:47): Adapter filter on the provider list (Platform Admin)
const ADAPTER_OPTIONS=[['any','Has an adapter'],['admitting','Admitting'],['testing','Testing'],['building','Building'],['off','Switched off'],['none','No adapter'],['no_courses','Not needed: no courses']].map(([value,label])=>({value,label}))

// v2.15.107: the menu, page titles, tabs, role gates and old-address redirects all come from nav-map.js.
const ICONS={dashboard:LayoutDashboard,course:GraduationCap,provider:Building2,scholarship:Sparkles,chart:BarChart3,check:CheckCircle2,database:Database,activity:Activity,ai:BrainCircuit,review:ListChecks,health:HeartPulse,workflow:Workflow,book:BookOpen,plug:Plug,sliders:SlidersHorizontal,shield:ShieldCheck,tags:Tags,users:UsersRound,guide:BookOpen}

// v2.15.268 (Platform Admin, 13 Oct 2026: notice links "doesnt open the specific card"): opens the named cards if closed and scrolls to
// the anchor once it is drawn (a card, a Toolsets settings section or a data-anchor), highlighted briefly.
function focusTarget(cards,at){
  if(!at&&!cards.length)return undefined
  let tries=0,stop=false
  const esc=v=>window.CSS?.escape?CSS.escape(v):v.replace(/["\\]/g,'\\$&')
  const step=()=>{if(stop)return
    for(const id of cards){const c=document.querySelector(`[data-card="${esc(id)}"][data-card-open="false"] .cf-card-toggle`);if(c)c.click()}
    const e=esc(at),el=at?document.querySelector(`[data-card="${e}"],[data-toolset-section="${e}"],[data-anchor="${e}"]`):null
    if(el){el.scrollIntoView?.({block:'start',behavior:'smooth'});el.classList.add('is-focus');setTimeout(()=>el.classList.remove('is-focus'),2500);return}
    if(++tries<40)setTimeout(step,150)}
  step();return()=>{stop=true}
}
function routeFromHash(){
  const raw=location.hash.replace(/^#/,'');const[route,query='']=raw.split('?')
  const r=resolveTarget(route||'dashboard',new URLSearchParams(query))
  // Old addresses keep working: show the new page and quietly replace the address with the new one.
  const canonical=hrefFor(r.page,r.tab,Object.fromEntries(r.params))
  if(raw&&`#${raw}`!==canonical)history.replaceState(null,'',canonical)
  return r
}

// v2.15.291: a ranking dataset page (Rankings & statistics ?dataset=qs_wur|the_wur) names the dataset in the page header.
// Moved from the retired ranking-dataset-header.js, which rewrote the heading after the page was drawn.
const RANKING_DATASET_HEADER={
  qs_wur:{title:'QS World University Rankings',subtitle:'QS ranking positions by edition, matched to our providers, with the source file kept.'},
  the_wur:{title:'Times Higher Education',subtitle:'Times Higher Education ranking positions by edition, matched to our providers, with the source file kept.'}
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
  componentDidCatch(error,info){console.error('StudySearch workspace render failed',error,info);this.props.onError?.(`Workspace render failed: ${error?.message||String(error)}`)}
  componentDidUpdate(prev){if(prev.routeKey!==this.props.routeKey&&this.state.error)this.setState({error:null})}
  render(){if(!this.state.error)return this.props.children;return <section className="m-workspace-error m-panel" role="alert"><PanelTitle icon={AlertTriangle} title="Workspace could not render" subtitle="The Administration shell remains available. Navigate to another section or retry this workspace."/><div className="m-alert compact"><AlertTriangle size={15}/><span>{this.state.error?.message||'Unexpected workspace render error'}</span></div><button className="m-primary" onClick={this.props.onRecover}>Return to Dashboard</button></section>}
}

function App(){
  const[session,setSession]=useState(null),[booting,setBooting]=useState(true),[context,setContext]=useState(null)
  const initialRoute=routeFromHash()
  const[route,setRoute]=useState(initialRoute),[error,setError]=useState(''),[navOpen,setNavOpen]=useState(false),[collapsed,setCollapsed]=useState(false),[health,setHealth]=useState(undefined)
  const mainRef=useRef(null)
  useEffect(()=>startTableResize(document.body),[]) // v2.15.227: every table resizes the same way
  useEffect(()=>{
    supabase.auth.getSession().then(({data})=>{setSession(data.session??null);setBooting(false)})
    const{data}=supabase.auth.onAuthStateChange((_event,next)=>setSession(next));return()=>data.subscription.unsubscribe()
  },[])
  useEffect(()=>{if(!session){setContext(null);return}api.context().then(setContext).catch(e=>setError(reportError(e,'context')))},[session])
  useEffect(()=>{const h=()=>setRoute(routeFromHash());addEventListener('hashchange',h);return()=>removeEventListener('hashchange',h)},[])
  // v2.15.268: a notice's Go to opens its card (card=) and scrolls to the card, setting section or anchor (at=).
  useEffect(()=>focusTarget(String(route.params?.get?.('card')||'').split(',').filter(Boolean),String(route.params?.get?.('at')||'')),[route])
  const rank=Number(context?.role_rank||0)
  // v2.15.300 (Platform Admin, 20 Oct 2026 10:35 "suggest not used navigation items"): each page and tab opened is counted once a day per
  // person (public.admin_screen_open), so screens retire on their use. Failures are ignored; nothing waits for it.
  const openedKey=context?`${route.page}|${effectiveTab(route.page,route.tab,rank)}`:''
  useEffect(()=>{if(!openedKey)return;const[p,t]=openedKey.split('|');supabase.rpc('admin_screen_open',{p_page:p,p_tab:t||''}).then(()=>{},()=>{})},[openedKey])
  // Top-bar health dot: read once after sign-in and every five minutes.
  useEffect(()=>{if(!session||!canOpen('health',rank))return;let live=true;const read=()=>readPlatformHealth().then(h=>{if(live)setHealth(h)});read();const t=setInterval(read,300000);return()=>{live=false;clearInterval(t)}},[session,rank])
  function go(target,params={}){
    const r=resolveTarget(target,new URLSearchParams(Object.entries(params||{}).filter(([,v])=>v!==''&&v!=null).map(([k,v])=>[k,String(v)])))
    const next=hrefFor(r.page,r.tab,Object.fromEntries(r.params))
    setRoute(r);if(location.hash!==next)location.hash=next;setNavOpen(false);setError('');/* v2.15.341 (UI audit Phase 0): a banner belongs to the screen that raised it, never to the next one */requestAnimationFrame(()=>{if(mainRef.current)mainRef.current.scrollTop=0})
  }
  // v2.15.341 (UI audit Phase 0): every error a screen raises is shown as one plain line with a reference; the full text is logged server-side
  const report=m=>setError(m?reportError(m,route.page):'')
  if(booting)return <div className="m-boot"><div className="m-loader"/><span>Loading StudySearch Admin…</span></div>
  if(!session)return <Login onError={m=>setError(m?plainError(m):'')} error={error}/>
  const pageKey=route.page,page=PAGES[pageKey]||PAGES.dashboard,tab=effectiveTab(pageKey,route.tab,rank)
  const tone=health===undefined?'unknown':healthTone(health?.overall)
  const healthLabel=health===undefined?'Checking platform health':HEALTH_WORDS[tone]
  const datasetHeader=pageKey==='rankings'?RANKING_DATASET_HEADER[route.params?.get?.('dataset')||'']:null
  return <div className={`m-shell ${collapsed?'is-collapsed':''}`}>
    <aside className={`m-sidebar ${navOpen?'is-open':''}`}>
      <div className="m-brand-row">
        <button className="m-brand" onClick={()=>go('dashboard')} aria-label="Dashboard"><span className="m-brand-mark">SS</span><span className="m-brand-copy"><strong>StudySearch</strong><small>PIM Admin v{UI_VERSION}</small></span></button>
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
        title={datasetHeader?.title||page.title} subtitle={datasetHeader?.subtitle||page.subtitle}
        actions={<>{canOpen('health',rank)&&<button type="button" className="cf-health-link" onClick={()=>go('health')} title={`Platform health: ${healthLabel}`} aria-label={`Platform health: ${healthLabel}`}><StatusDot tone={tone} label={healthLabel}/><span className="cf-health-text">Health</span></button>}<ReleasePill/><span className="m-role-pill">{roleLabel(context?.role||'Loading')}</span></>}/>
      {/* v2.15.253 (Platform Admin, 12 Oct 2026): credit and limit notices on every page (Curator and above) */}
      <CreditBanner rank={rank} canOpenServices={canOpen('services',rank)}/>
      <DeployedVersionNotice/>
      {error&&<div className="m-alert" data-global-error><AlertTriangle size={16}/><span>{error}</span><button onClick={()=>setError('')} aria-label="Dismiss"><X size={15}/></button></div>}
      <WorkspaceErrorBoundary routeKey={`${pageKey}/${tab}?${route.params.toString()}`} onError={report} onRecover={()=>go('dashboard')}>
        <React.Suspense fallback={<div className="m-page-loading" role="status"><span className="m-spinner"/>Loading…</div>}><Page pageKey={pageKey} tab={tab} routeParams={route.params} rank={rank} actorId={String(context?.user_id||'')} onError={report} navigate={go}/></React.Suspense>
      </WorkspaceErrorBoundary>
    </main>
  </div>
}

// v2.15.341 (UI audit Phase 0, the v2.15.339/v2.15.340 mismatch): a release deploys new screen chunks while the shell a person already has open keeps the
// old version, so the top bar and an inner screen can disagree. The shell reads the deployed version (public/release-history.json, written at every
// build) after sign-in, on every navigation and every five minutes, and asks for a reload when it differs. Nothing reloads by itself.
function DeployedVersionNotice(){
  const[deployed,setDeployed]=useState('')
  useEffect(()=>{let live=true;const read=()=>fetch(`/release-history.json?t=${Date.now()}`,{cache:'no-store'}).then(r=>r.ok?r.json():null).then(j=>{if(live&&j?.current)setDeployed(String(j.current))}).catch(()=>{});read();const t=setInterval(read,300000);const onHash=()=>read();window.addEventListener('hashchange',onHash);return()=>{live=false;clearInterval(t);window.removeEventListener('hashchange',onHash)}},[])
  if(!deployed||deployed===UI_VERSION)return null
  return <div className="m-alert compact" role="status" data-deployed-version={deployed}><AlertTriangle size={15}/><span>A newer version of PIM Admin (v{deployed}) has been released; this window is on v{UI_VERSION}. Reload to update.</span><button type="button" className="m-primary" onClick={()=>location.reload()}>Reload</button></div>
}
function Login({error,onError}){const[email,setEmail]=useState(''),[password,setPassword]=useState(''),[busy,setBusy]=useState(false);async function submit(e){e.preventDefault();setBusy(true);onError('');const{error:x}=await supabase.auth.signInWithPassword({email,password});if(x)onError(x.message);setBusy(false)}return <div className="m-login"><form className="m-login-card" onSubmit={submit}><div className="m-login-brand"><span className="m-brand-mark large">SS</span><div><strong>StudySearch Admin</strong><small>Governed operational workspace</small></div></div><div className="m-login-copy"><h1>Sign in</h1><p>Authorised staff access only. Canonical catalogue, provenance and pipeline operations.</p></div>{error&&<div className="m-alert compact"><AlertTriangle size={15}/><span>{error}</span></div>}<label>Email<input type="email" value={email} onChange={e=>setEmail(e.target.value)} required/></label><label>Password<input type="password" value={password} onChange={e=>setPassword(e.target.value)} required/></label><button className="m-primary" disabled={busy}>{busy?'Signing in…':'Sign in'}</button><small className="m-login-version">PIM Admin v{UI_VERSION}</small></form></div>}

// Every page renders inside the shell through PageLayout: optional tabs, then content. No page draws its own shell.
function Page({pageKey,tab,routeParams,rank,actorId,onError,navigate}){
  const focusId=routeParams?.get?.('id')||''
  const err=e=>onError(e?.message||String(e))
  if(!canOpen(pageKey,rank))return <EmptyState icon={AlertTriangle} title="Not authorised" text="Your role does not include this page. Ask a Platform Admin if you need access."/>
  const page=PAGES[pageKey],tabs=shownTabs(page,rank,tab)
  const onTab=key=>navigate(pageKey,{tab:key})
  const body=pageBody()
  // v2.15.177 (Decision 252): a notice on the layer's page when a toolset it depends on hits a limit or times out
  const layerNo=/^layer[1-4]$/.test(pageKey)?Number(pageKey.slice(5)):null
  return <PageLayout tabs={tabs} active={tab} onTab={onTab} label={`${page.label} sections`}>{layerNo&&<LayerNotices layer={layerNo}/>}{body}</PageLayout>
  function pageBody(){
    switch(pageKey){
      case'dashboard':return <DashboardHome onError={onError}/>
      case'guide':return tab==='admin-sop'||tab==='operator-sop'?<Sop key={tab} id={tab} rank={rank} navigate={navigate}/>:<PlatformGuide rank={rank} navigate={navigate}/>
      case'courses':return <Catalogue key="course" type="course" onError={onError} navigate={navigate} initialId={focusId} rank={rank}/>
      case'providers':
        if(tab==='campuses')return <Catalogue key="campus" type="campus" onError={onError} navigate={navigate} initialId={focusId} rank={rank}/>
        if(tab==='assets')return <ProviderAssetsWorkspace onError={onError} navigate={navigate}/>
        // v2.15.224: the old country and source onboarding cases panel is retired (no case was ever opened)
        if(tab==='archived')return <ArchivedReview onError={onError} navigate={navigate}/>
        // v2.15.253 (Platform Admin, 12 Oct 2026): universities are onboarded automatically up to Ready to admit; admitting stays a person's step.
        return <Catalogue key="provider" type="provider" onError={onError} navigate={navigate} initialId={focusId} rank={rank}/>
      // v2.15.301: Extraction is on Models & services › AI (old address redirects)
      case'scholarships':if(tab==='coverage')return <ScholarshipCoverage rank={rank} onError={onError} navigate={navigate}/>;return <ScholarshipWorkspace rank={rank} onError={onError} navigate={navigate} initialId={focusId}/>
      case'rankings':
        if(tab==='compare')return <ComparisonWorkspace routeParams={routeParams} navigate={navigate} onError={onError}/>
        if(tab==='qilt')return <Qilt onError={onError}/>
        if(tab==='prisms')return <Prisms onError={onError}/>
        // v2.15.301 (Platform Admin, 20 Oct 2026): Ranking imports moved here from Reference data
        if(tab==='datasets')return <div className="m-page-stack"><StatisticsDatasets rank={rank}/>{rank>=4&&<section data-ranking-imports><RankingImportPanel onError={onError} routeParams={routeParams} navigate={navigate}/></section>}</div>
        return <StatisticsRankings onError={onError} navigate={navigate} rank={rank} routeParams={routeParams}/>
      // v2.15.301: Flags moved to Layer 2/3 › Flags
      case'coverage':if(tab==='progress')return <Progress routeParams={routeParams} rank={rank} onError={onError}/>;return tab==='attributes'?<CoverageAttributes rank={rank}/>:<div className="m-page-stack"><CoverageView view="courses"/><LinkRefresh/></div>
      // v2.15.301 (Platform Admin, 20 Oct 2026, "Merge into one Sources page"): one Sources page with a layer filter; registers first
      case'layer1':return <SourcesPage routeParams={routeParams} navigate={navigate}/>
      // v2.15.301 (Platform Admin, 20 Oct 2026, "One list with a type filter"): Key dates and Reference sources in one list
      case'reference':return <ReferenceList routeParams={routeParams} navigate={navigate} onError={err}/>
      case'layer2':
        // v2.15.300 (Platform Admin, 20 Oct 2026, "Operations first"): Layer 2/3 Build & enrich. Operations first; Universities joins the
        // old Onboarding and Adapters tabs (their addresses redirect, see nav-map.js); the Adapter builder opens from a university row.
        // v2.15.301 (Platform Admin, 20 Oct 2026, "One tab on Layer 2/3"): finding scholarships (was Layer 1 › Scholarships), then reading them
        if(tab==='scholarships')return <div className="m-page-stack" data-scholarships-merged><SectionTitle title="Finding scholarships" subtitle="Countries switched on and the sources for each."/><ScholarshipLayer layer={1} rank={rank} onError={err}/><SectionTitle title="Reading scholarships" subtitle="Discovery and reading by country, refusals, the jobs and their limits."/><ScholarshipLayer layer={2} rank={rank} onError={err}/></div>
        if(tab==='flags')return <FlagsPanel onError={onError}/>
        // v2.15.309 (Platform Admin 21 Oct 2026, fee reader): the AI fee reader sits under Enrich fields
        if(tab==='enrich')return <div className="m-page-stack"><EnrichFields rank={rank} onError={err}/><FeeReader onError={err}/></div>
        if(tab==='plan')return <EnrichPlan rank={rank} onError={err} initialProvider={routeParams?.get?.('provider')||''}/>
        // v2.15.287 (Decision 267): Build adapter, one click per university
        if(tab==='build')return <BuildAdapter rank={rank} onError={err} initialProvider={routeParams?.get?.('provider')||''}/>
        if(tab==='builder')return <AdapterBuilderTab rank={rank} onError={err} initialProvider={routeParams?.get?.('provider')||''}/>
        // v2.15.321: Course sources, found by the platform (job source-find), managed here
        if(tab==='sources')return <CourseSources rank={rank} onError={err}/>
        if(tab==='universities')return <AdaptersWorkspace merged rank={rank} actorId={actorId} onError={err} routeParams={routeParams}/>
        return <Layer23Operations rank={rank} actorId={actorId} onError={err}/>
      // v2.15.252 (Platform Admin, 12 Oct 2026): Layer 3 AI validation and Layer 4 AI send-back tab retired; adapters admit the values.
      // v2.15.253 (Platform Admin, 12 Oct 2026): Flagged values, Fee rules, Attributes, Scholarship publishing and Blocks retired (old addresses redirect in nav-map.js).
      // v2.15.300 (Platform Admin, 20 Oct 2026): Review queue, AI could not decide and Websites to find retired into the Inbox kinds.
      case'layer4':return <Layer4Inbox onError={err} routeParams={routeParams}/>
      // v2.15.300: Screen use (Platform Admin) under the health checks, to decide which screens retire
      // v2.15.301: Capacity moved to the Go-live checklist; Storage & retention is a tab here
      case'health':return tab==='storage'?<RetentionScreen onError={onError}/>:tab==='queues'?<QueueWatch onError={onError}/>:<><PlatformHealth onError={onError}/>{rank>=6&&<ScreenUse onError={onError}/>}</>
      case'jobs':return tab==='tasks'?<AdminTasks rank={rank} onError={onError}/>:tab==='automations'?<div className="m-page-stack"><Automations onError={err}/><RefreshWorkspace onError={err}/></div>:<JobsWorkspace/>
      case'evidence':return <EvidenceWorkspace onError={onError} navigate={navigate} routeParams={routeParams}/>
      // CF-247 (16 Oct 2026): calls to the API version URLs (zoho-api-v2 first), by key and action; v2.15.301 Settings › API usage
      case'environment':if(tab==='api')return <ApiUsagePanel onError={onError}/>;if(tab==='backup')return rank>=6?<SettingsBackup onError={err}/>:null;return <><PipelineSettings onError={err}/><EnvironmentMigrationWorkspace rank={rank} onError={onError} view="integrations"/></>
      // Clean-up batch 2 (9 Oct 2026): Source profiles and the Layer 2 workload defaults were retired; the provider registry and keys stay.
      // v2.15.300 (Platform Admin, 20 Oct 2026): Scrapers & fetchers is Models & services › Fetchers
      // v2.15.264: Models & services in three tabs (Services · AI & OpenRouter · Toolsets & limits)
      // v2.15.301: Scholarship extraction (was Scholarships › Extraction) under the AI configuration
      case'services':return tab==='ai'?<div className="m-page-stack">{rank>=4&&<AiConfig onError={err}/>}<section data-scholarship-extraction-moved><SectionTitle title="Scholarship extraction" subtitle="The AI that reads each stored scholarship page: models, qualification, instructions and answers."/><ScholarshipExtraction onError={onError}/></section></div>:tab==='limits'?<div className="m-page-stack"><SearchCapCard/><Toolsets onError={err}/></div>:tab==='fetchers'?<><p className="l3v-note">Switch services on or off on the Services tab. Keys are on <a href="#environment">Settings</a>.</p><Layer2ProviderConfig rank={rank} embedded/></>:<div className="m-page-stack"><ModelsServices onError={err}/></div>
      case'migration':return <div className="m-page-stack"><EnvironmentMigrationWorkspace rank={rank} onError={onError} view="migration"/><PlatformMaturity rank={rank} onError={onError} view="golive"/>{/* v2.15.301: Capacity (was Platform health › Capacity) */}<section data-golive-capacity><PlatformMaturity rank={rank} onError={onError} view="capacity"/></section>{/* v2.15.228: the Reset database control was retired (Platform Admin, 9 Oct 2026) */}</div>
      // v2.15.301 (Platform Admin, 20 Oct 2026): Data model retired (its address opens Coverage › Attributes); Storage & retention is a Platform health tab
      case'users':return <AccessRolesEmbedded actorId={actorId}/>
      case'contacts':return <ProviderContactsWorkspace rank={rank} onError={onError} navigate={navigate} initialProviderId={routeParams?.get?.('provider_id')||''}/>
      default:return <EmptyState icon={AlertTriangle} title="Page not found" text="This address does not match a page. Use the menu to continue."/>
    }
  }
}


// v2.15.291: used while the dataset registry is read, or if it cannot be read (same list the retired enhancer used).
const STAT_REGISTRY_FALLBACK=[
 {dataset_key:'qilt',label:'QILT',dataset_type:'statistics',description:'Quality Indicators for Learning and Teaching',display_enabled:true,display_order:10,compare_enabled:true},
 {dataset_key:'prisms',label:'PRISMS',dataset_type:'statistics',description:'International student-flow observations',display_enabled:true,display_order:20,compare_enabled:true},
 {dataset_key:'qs_wur',label:'QS World University Rankings',dataset_type:'ranking',description:'Imported QS World University Ranking editions',display_enabled:true,display_order:30,compare_enabled:true,source_system_code:'qs_wur'},
 {dataset_key:'the_wur',label:'Times Higher Education',dataset_type:'ranking',description:'Imported Times Higher Education ranking editions',display_enabled:true,display_order:40,compare_enabled:true,source_system_code:'the_wur'}
]
// A dataset added in the registry and switched on, with no dedicated card yet: name, description, latest figures and its details.
function StatDatasetCard({item,systems,onOpen,navigate}){
 const r=(systems||[]).find(x=>x.code===item.source_system_code||x.system_code===item.source_system_code)||null
 const headline=r?.latest_edition||r?.edition_year||'Configured',detail=r?.observations?`${fmtNumber(r.observations)} observations${r.mapped_observations!=null?` · ${fmtNumber(r.mapped_observations)} mapped`:''}`:'No accepted observations yet.'
 return <article className="m-stats-card" data-dataset-key={item.dataset_key}><span>{item.label}</span>{item.description&&<p className="cf-stat-desc">{item.description}</p>}<strong>{headline}</strong><small>{detail}</small><div><button onClick={()=>onOpen({item,summary:detail})}>Open dataset</button>{item.compare_enabled&&<button onClick={()=>navigate('Compare',{type:'provider'})}>Compare</button>}</div></article>
}
function StatDatasetDialog({value,onClose,navigate}){
 const{item,summary}=value
 useEffect(()=>{const k=e=>{if(e.key==='Escape')onClose()};addEventListener('keydown',k);return()=>removeEventListener('keydown',k)},[onClose])
 return <div className="cf-stat-dialog-backdrop" onClick={e=>{if(e.target===e.currentTarget)onClose()}}><section className="cf-stat-dialog" role="dialog" aria-modal="true" aria-label={item.label}><h3>{item.label}</h3><p>{item.description}</p><small><b>Type:</b> {item.dataset_type} · <b>Authority:</b> {item.source_authority||'Governed source'}</small>{summary&&<p>{summary}</p>}<div className="cf-stat-dialog-actions"><button onClick={()=>{onClose();navigate('Compare',{type:'provider'})}}>Compare</button><button onClick={onClose}>Close</button></div></section></div>
}

function StatisticsRankings({onError,navigate,rank,routeParams}){
 const[qilt,setQilt]=useState(null),[prisms,setPrisms]=useState(null),[ranking,setRanking]=useState(null),[busy,setBusy]=useState(true)
 const[rankingYears,setRankingYears]=useState({qs:[],the:[]}),[rankingSelection,setRankingSelection]=useState({qs:'',the:''})
 // v2.15.291: the dataset registry (Rankings & statistics › Datasets) decides which cards show, in what order, with what
 // description; edition figures follow the chosen edition. Moved from the retired StatisticsDatasetEnhancer.js, which
 // rewrote these cards after the page was drawn.
 const[registry,setRegistry]=useState(STAT_REGISTRY_FALLBACK),[rankingEditions,setRankingEditions]=useState({qs:[],the:[]}),[datasetDialog,setDatasetDialog]=useState(null)
 useEffect(()=>{let live=true;supabase.rpc('statistics_dataset_registry_read').then(({data,error})=>{if(live&&!error&&Array.isArray(data))setRegistry(data)}).catch(()=>{});return()=>{live=false}},[])
 useEffect(()=>{let live=true;setBusy(true);Promise.all([
  api.qiltPage({limit:1,offset:0,sort:'year',direction:'desc'}).catch(e=>({error:e})),
  api.prismsPage({limit:1,offset:0,sort:'period',direction:'desc'}).catch(e=>({error:e})),
  api.rankingSummary().catch(e=>({error:e})),
  api.rankingFilters('qs_wur').catch(e=>({error:e})),
  api.rankingFilters('the_wur').catch(e=>({error:e}))
 ]).then(([q,p,r,qsf,thef])=>{if(!live)return;if(q?.error)onError?.(q.error.message);else setQilt(q);if(p?.error)onError?.(p.error.message);else setPrisms(p);if(r?.error)onError?.(r.error.message);else setRanking(r);const qy=(qsf?.years||[]).map(String),ty=(thef?.years||[]).map(String);setRankingYears({qs:qy,the:ty});setRankingEditions({qs:qsf?.editions||[],the:thef?.editions||[]});setRankingSelection(x=>({qs:x.qs&&qy.includes(x.qs)?x.qs:(qy[0]||''),the:x.the&&ty.includes(x.the)?x.the:(ty[0]||'')}))}).finally(()=>live&&setBusy(false));return()=>{live=false}},[])
 const q=qilt?.items?.[0]||qilt?.rows?.[0]||null,p=prisms?.items?.[0]||prisms?.rows?.[0]||null
 const qYear=q?[q.collection_year_from,q.collection_year_to].filter(Boolean).join('–'):'—'
 const pPeriod=p?[p.period_start,p.period_end].filter(Boolean).map(x=>String(x).slice(0,10)).join(' → '):'—'
 const systems=ranking?.systems||[],qs=systems.find(x=>x.code==='qs_wur'),the=systems.find(x=>x.code==='the_wur')
 const activeDataset=routeParams?.get?.('dataset')||'',activeYear=routeParams?.get?.('year')||''
 useEffect(()=>{if(activeDataset==='qs_wur'&&activeYear&&rankingYears.qs.includes(String(activeYear)))setRankingSelection(x=>({...x,qs:String(activeYear)}));if(activeDataset==='the_wur'&&activeYear&&rankingYears.the.includes(String(activeYear)))setRankingSelection(x=>({...x,the:String(activeYear)}))},[activeDataset,activeYear,rankingYears.qs.join('|'),rankingYears.the.join('|')])
 const openRanking=(system,key)=>{const selected=rankingSelection[key]||rankingYears[key][0]||'';if(selected)navigate('Statistics & Rankings',{dataset:system,year:selected})}
 const statCards=registry.filter(x=>x?.display_enabled).sort((a,b)=>Number(a.display_order||0)-Number(b.display_order||0))
 const statDesc=key=>{const d=registry.find(x=>x?.dataset_key===key)?.description;return d?<p className="cf-stat-desc">{d}</p>:null}
 const editionDetail=(key,system)=>{const year=rankingSelection[key]||rankingYears[key][0]||'',e=rankingEditions[key].find(x=>String(x?.year)===String(year))
  if(e)return `${fmtNumber(e.observations||0)} observations · ${fmtNumber(e.mapped_observations||0)} mapped`
  return system?.accepted_editions?`${fmtNumber(system.observations||0)} observations · ${fmtNumber(system.mapped_observations||0)} mapped`:'No accepted edition applied yet.'}
 if(['qs_wur','the_wur'].includes(activeDataset))return <div className="m-page-stack"><RankingDatasetPanel system={activeDataset} year={activeYear} navigate={navigate} onError={onError}/></div>
 return <div className="m-page-stack">
  <section className="m-panel">
   <PanelTitle icon={BarChart3} title="Statistics & Rankings" subtitle="One verification workspace for contextual statistics, ranking editions, coverage and provenance."/>
   <div className="m-stats-grid">
    {statCards.map(item=><React.Fragment key={item.dataset_key}>{({
    qilt:()=><article className="m-stats-card" data-dataset-key="qilt"><span>QILT</span>{statDesc('qilt')}<strong>{busy?'…':fmtNumber(qilt?.total||0)}</strong><small>observations · latest period {qYear}</small><div><button onClick={()=>navigate('Outcomes (QILT)')}>Open dataset</button><button onClick={()=>navigate('Compare',{type:'provider'})}>Compare</button></div></article>,
    prisms:()=><article className="m-stats-card" data-dataset-key="prisms"><span>PRISMS</span>{statDesc('prisms')}<strong>{busy?'…':fmtNumber(prisms?.total||0)}</strong><small>observations · latest period {pPeriod}</small><div><button onClick={()=>navigate('Student Flow (PRISMS)')}>Open dataset</button><button onClick={()=>navigate('Compare',{type:'provider'})}>Compare</button></div></article>,
    qs_wur:()=><article className="m-stats-card" data-dataset-key="qs_wur"><span>QS World University Rankings</span>{statDesc('qs_wur')}<div className="m-ranking-card-picker"><label>Edition<select aria-label="QS ranking edition" value={rankingSelection.qs||rankingYears.qs[0]||''} onChange={e=>setRankingSelection(x=>({...x,qs:e.target.value}))}>{rankingYears.qs.map((y,i)=><option key={y} value={y}>{y}{i===0?' · latest':''}</option>)}</select></label></div><strong>{rankingSelection.qs||qs?.latest_edition||'—'}</strong><small>{editionDetail('qs',qs)}</small><div><button disabled={!rankingYears.qs.length} onClick={()=>openRanking('qs_wur','qs')}>Open Dataset</button><button onClick={()=>navigate('Compare',{type:'provider'})}>Compare</button></div></article>,
    the_wur:()=><article className="m-stats-card" data-dataset-key="the_wur"><span>Times Higher Education</span>{statDesc('the_wur')}<div className="m-ranking-card-picker"><label>Edition<select aria-label="THE ranking edition" value={rankingSelection.the||rankingYears.the[0]||''} onChange={e=>setRankingSelection(x=>({...x,the:e.target.value}))}>{rankingYears.the.map((y,i)=><option key={y} value={y}>{y}{i===0?' · latest':''}</option>)}</select></label></div><strong>{rankingSelection.the||the?.latest_edition||'—'}</strong><small>{editionDetail('the',the)}</small><div><button disabled={!rankingYears.the.length} onClick={()=>openRanking('the_wur','the')}>Open Dataset</button><button onClick={()=>navigate('Compare',{type:'provider'})}>Compare</button></div></article>
    })[item.dataset_key]?.()||<StatDatasetCard item={item} systems={systems} onOpen={setDatasetDialog} navigate={navigate}/>}</React.Fragment>)}
   </div>
   {datasetDialog&&<StatDatasetDialog value={datasetDialog} onClose={()=>setDatasetDialog(null)} navigate={navigate}/>}
  </section>
  <section className="m-panel">
   <div className="m-stats-section-head"><div><h3>Coverage & verification</h3><p>Use dataset drill-downs to inspect exact observations. Ranking coverage, edition filters, Provider mapping and Evidence remain publisher-specific.</p></div><button className="m-secondary" onClick={()=>navigate('Compare',{type:'provider'})}><ArrowLeftRight size={15}/>Open Compare</button></div>
   <div className="m-stats-notes">
    <div><b>Provider context</b><span>QILT, PRISMS and institutional rankings retain their native source grain.</span></div>
    <div><b>Years / editions</b><span>QS and THE use independent edition selectors; Compare retains its own per-ranking edition controls.</span></div>
    <div><b>Evidence</b><span>Every accepted value links back to the source page it came from.</span></div>
    <div><b>Historical publisher files</b><span>{rank>=4?'Ranking files are imported on Rankings &amp; statistics › Datasets.':'Import controls are restricted to authorised operator roles.'}</span></div>
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


// v2.15.231 (Platform Admin, 10 Oct 2026: "Simple logo list"): which providers have a logo and which do not. The old
// logo-finding pipeline (discovered, acquired, approved, blocked) was retired in clean-up batch 6; a logo is added or
// replaced by clicking the logo in the provider's panel.
function ProviderAssetsWorkspace({onError,navigate}){
 const[finder,setFinder]=useState(null)
 const[summary,setSummary]=useState(null),[data,setData]=useState(null),[country,setCountry]=useState('AU'),[state,setState]=useState(''),[query,setQuery]=useState(''),[offset,setOffset]=useState(0),[busy,setBusy]=useState(false)
 const debounced=useDebounce(query,260)
 const countries=[{value:'AU',label:'Australia'},{value:'NZ',label:'New Zealand'},{value:'CA',label:'Canada'},{value:'',label:'All countries'}]
 const states=[{value:'',label:'All providers'},{value:'approved',label:'With a logo'},{value:'missing',label:'No logo'}]
 function load(){setBusy(true);logoCapability().then(c=>setFinder(c?.finder||null));return Promise.all([api.providerAssetSummary({countryCode:country,query:debounced}),api.providerAssetCoverage({limit:50,offset,countryCode:country,query:debounced,state})]).then(([s,p])=>{setSummary(s);setData(p)}).catch(e=>onError?.(e.message)).finally(()=>setBusy(false))}
 useEffect(()=>{load()},[country,state,debounced,offset])
 useEffect(()=>setOffset(0),[country,state,debounced])
 const rows=data?.items||[],total=Number(data?.total||0),all=Number(summary?.expected||0),withLogo=Number(summary?.approved||0)
 return <div className="m-page-stack" data-logo-list>
  <div className="cf-metric-grid">
   <Metric label="Providers" value={busy?'…':fmtNumber(all)} detail="Active, in the selected country" icon={Building2}/>
   <Metric label="With a logo" value={busy?'…':fmtNumber(withLogo)} detail={all?`${Math.round(withLogo/all*100)}% of providers`:'—'} icon={CheckCircle2} tone="success"/>
   <Metric label="No logo" value={busy?'…':fmtNumber(Math.max(0,all-withLogo))} detail="Click a logo to add one, or let the logo finder look" icon={AlertTriangle} tone={all-withLogo>0?'warning':'success'}/>
  </div>
  <section className="m-panel">
   <div className="m-workspace-head"><div><h2>Logos</h2><p>Click a logo to upload one, give an image address, or ask the logo finder to look on the provider's website. The logo finder also works through providers with no logo every 10 minutes.{finder&&<> Logo finder so far: {fmtNumber(finder.found||0)} found, {fmtNumber(finder.not_found||0)} not found, {fmtNumber(finder.waiting||0)} waiting.</>}</p></div><button className="m-secondary compact" onClick={load}><RefreshCw size={14}/>Refresh</button></div>
   <div className="m-search-row"><label className="m-searchbox"><Search size={16}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search provider…"/>{query&&<button onClick={()=>setQuery('')}><X size={14}/></button>}</label></div>
   <div className="m-filter-bar"><FilterSelect label="Country" value={country} onChange={v=>setCountry(v)} options={countries}/><FilterSelect label="Logo" value={state} onChange={v=>setState(v)} options={states}/></div>
   <div className="dense-table-wrap"><table className="dense-table"><thead><tr><th><span>Provider</span></th><th><span>Country</span></th><th><span>Logo</span></th><th><span>Checked</span></th><th><span>Open</span></th></tr></thead><tbody>{rows.length?rows.map(r=>{const has=r.coverage_state==='approved'&&Boolean(r.primary_mime_type);return <tr key={r.provider_id} data-logo-row={has?'yes':'no'}><td className="primary-cell"><ProviderBrand providerId={r.provider_id} name={r.provider_name} size={28} editable/></td><td>{r.country_code}</td><td><StatusChip tone={has?'success':'warning'} label={has?'Has logo':'No logo'}/></td><td>{r.primary_verified_at?fmtDate(r.primary_verified_at):'—'}</td><td><button className="m-secondary compact" onClick={()=>navigate?.('Providers',{id:r.provider_id})}>Open provider</button></td></tr>}):<tr><td colSpan="5"><EmptyInline text={busy?'Loading…':'No matching providers.'}/></td></tr>}</tbody></table></div>
   <Pager offset={offset} limit={50} total={total} onOffset={setOffset}/>
  </section>
 </div>
}

function RankingImportPanel({onError,routeParams,navigate}){
 const requested=routeParams?.get?.('system'),presetSystem=['qs_wur','the_wur','arwu'].includes(requested)?requested:'qs_wur',presetYear=routeParams?.get?.('year')||String(rankingDefaultYear(presetSystem))
 const makeForm=(system=presetSystem,year=presetYear)=>({systemCode:system,editionYear:String(year),publisherName:rankingPublisherName(system),sourceUrl:rankingSourceUrl(system),methodologyUrl:'',licensingNote:'Authorised publisher Evidence obtained for StudySearch ingestion.',revisionNote:'',mode:'file'})
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

function ScholarshipWorkspace({rank,onError,navigate,initialId}){return <div className="m-page-stack"><Catalogue type="scholarship" onError={onError} navigate={navigate} initialId={initialId} rank={rank}/></div>}
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
  const rows=rowsOf(data),total=Number(data?.total??rows.length??0),active=activeFilters(filters).filter(([k])=>type!=='scholarship'||!['status','lifecycle','publication'].includes(k))
  async function open(row){const id=row.id??row.course_id;setSelected(id);setDetailBusy(true);try{setDetail(await adminRead(cfg.detail,{id}))}catch(e){onError(e.message)}finally{setDetailBusy(false)}}
  function patch(k,v,label=''){setFilters(f=>{const n={...f,[k]:v};if(k==='country'){n.subdivision='';if(['course','scholarship'].includes(type))n.provider=''}if(k==='subdivision'&&type==='course')n.provider='';return n});setFilterLabels(l=>{const n={...l,[k]:label||''};if(k==='country'){delete n.subdivision;if(['course','scholarship'].includes(type))delete n.provider}if(k==='subdivision'&&type==='course')delete n.provider;return n})}
  function changeSort(k){if(!k)return;if(sort===k)setDirection(d=>d==='asc'?'desc':'asc');else{setSort(k);setDirection('asc')}}
  // v2.15.215 (Platform Admin, 7 Oct 2026 20:28): an Adapter column beside the provider name, Platform Admin only. Opens Layer 2 › Adapter builder
  // with the provider loaded; providers without an adapter show Create adapter (the builder then offers Build automatically).
  const adapterCol=type==='provider'&&!completenessMode&&Number(rank)>=6
  const[adapterStates,setAdapterStates]=useState({})
  const rowIds=rows.map(r=>String(r.id??'')).filter(Boolean).join(',')
  useEffect(()=>{if(!adapterCol||!rowIds)return;let live=true;supabase.rpc('admin_adapter_autobuild',{p_action:'states',p_args:{provider_ids:rowIds.split(',')}}).then(({data,error})=>{if(error)throw error;if(live)setAdapterStates(data||{})}).catch(e=>onError(e.message));return()=>{live=false}},[adapterCol,rowIds])
  // v2.15.236 (Platform Admin, 10 Oct 2026, Feature 4): a Published switch in the provider list. Published by default; PIM Operator and
  // above can switch it with no reason asked. Unpublished providers are greyed out and are not served to Wix, Zoho or the website.
  const[pubOver,setPubOver]=useState({}),[pubBusy,setPubBusy]=useState('')
  const isPub=r=>(pubOver[r.id]??r.publication_status)==='published'
  const togglePub=async r=>{const next=!isPub(r);setPubBusy(String(r.id));try{const{data,error}=await supabase.rpc('admin_provider_publish',{p_provider_id:r.id,p_published:next});if(error)throw error;setPubOver(o=>({...o,[r.id]:data?.publication_status}))}catch(e){onError(e.message)}finally{setPubBusy('')}}
  const pubCol={key:'publication_status',label:'Published',width:130,render:r=><PublishSwitch on={isPub(r)} busy={pubBusy===String(r.id)} can={Number(rank)>=5&&(r.lifecycle_status||'active')==='active'} archived={(r.lifecycle_status||'active')!=='active'} onToggle={()=>togglePub(r)}/>}
  // v2.15.276 (Decision 258, Platform Admin 14 Oct 2026): a Type column. The type comes from the register rules (Settings › Pipeline settings);
  // a provider no rule matches shows Needs type with the reason. PIM Admin and above can set it by hand (kept) or return it to Auto. No reason asked.
  const typeCol=type==='provider'&&!completenessMode
  const[typeOpts,setTypeOpts]=useState([]),[typeOver,setTypeOver]=useState({}),[typeBusy,setTypeBusy]=useState('')
  useEffect(()=>{if(!typeCol||Number(rank)<5)return;let live=true;supabase.rpc('admin_provider_type_rules',{p_action:'list',p_args:{}}).then(({data,error})=>{if(error)throw error;if(live)setTypeOpts(data?.types||[])}).catch(e=>onError(e.message));return()=>{live=false}},[typeCol,rank])
  const setType=async(r,code)=>{setTypeBusy(String(r.id));try{const{data,error}=await supabase.rpc('admin_provider_set_type',{p_provider_id:r.id,p_type_code:code});if(error)throw error;setTypeOver(o=>({...o,[r.id]:data}))}catch(e){onError(e.message)}finally{setTypeBusy('')}}
  const typeCell={key:'provider_type_name',label:'Type',width:200,sortKey:'type',render:r=><TypeCell row={{...r,...(typeOver[r.id]||{})}} opts={typeOpts} can={Number(rank)>=5} busy={typeBusy===String(r.id)} onSet={code=>setType(r,code)}/>}
  // v2.15.337 (Platform Admin 24 Oct 2026 07:32: CRICOS is Australian only): the registered CRICOS fee column is shown only when the list is Australian or has no country filter
  const baseCols=columns(type,completenessMode).flatMap(c=>type==='provider'&&!completenessMode&&c.key==='publication_status'?[pubCol]:typeCol&&c.key==='country_code'?[c,typeCell]:[c]).filter(c=>!(type==='course'&&c.key==='fee_amount'&&filters.country&&String(filters.country).toUpperCase()!=='AU'))
  // v2.15.271 (Platform Admin, 14 Oct 2026): a visible Scholarship search flag on each provider row; Off rows are switched on in the provider panel
  const schCol=type==='provider'&&!completenessMode
  const[schStates,setSchStates]=useState({})
  useEffect(()=>{if(!schCol||!rowIds)return;let live=true;supabase.rpc('admin_provider_sch_search',{p_action:'states',p_args:{provider_ids:rowIds.split(',')}}).then(({data,error})=>{if(error)throw error;if(live)setSchStates(data||{})}).catch(e=>onError(e.message));return()=>{live=false}},[schCol,rowIds])
  const schCell={key:'_sch_search',label:'Scholarship search',width:150,render:r=>{const s=schStates[String(r.id)];if(!s)return'—';return s.on?<span className="sch-muted" data-sch-flag="on">On</span>:<span data-sch-flag="off"><StatusChip tone="warning" label={s.directory_only&&s.auto?'Off · directory site':'Off'} title={s.reason||undefined}/></span>}}
  const withSch=schCol?[...baseCols.slice(0,-1),schCell,baseCols[baseCols.length-1]]:baseCols
  const cols=adapterCol?[withSch[0],{key:'_adapter',label:'Adapter',width:150,sortKey:'adapter',render:r=><AdapterCell state={adapterStates[String(r.id)]} noCourses={r.adapter_status==='no_courses'} onOpen={()=>navigate?.('layer2',{tab:'builder',provider:r.id})}/>},...withSch.slice(1)]:withSch
  return <div className="m-page-stack">
    
    <section className="m-panel m-catalogue-panel">
      {type!=='scholarship'&&<div className="m-workspace-head"><div><h2>{completenessMode?'Course readiness workspace':`${humanise(type)} catalogue`}</h2>{completenessMode&&<p>Courses missing key facts, by what is missing.</p>}</div><div className="m-result-count">{busy?<><span className="m-spinner"/>Loading…</>:<><strong>{fmtNumber(total)}</strong><span>{active.some(([k])=>/lifecycle/i.test(String(k)))?'matching':'matching · any status'}</span></>}</div></div>}
      <div className="m-search-row"><label className="m-searchbox"><Search size={16}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder={cfg.search}/>{query&&<button onClick={()=>setQuery('')}><X size={14}/></button>}</label>{type==='course'&&<button className={`m-filter-toggle ${advanced?'active':''}`} onClick={()=>setAdvanced(x=>!x)}><SlidersHorizontal size={15}/>Filters{active.length?` · ${active.length}`:''}</button>}<button className="m-secondary compact" onClick={()=>{setQuery('');setFilters({});setFilterLabels({});setOffset(0)}} disabled={!query&&!active.length}><RefreshCw size={14}/>Clear</button>{type==='scholarship'&&<span className="sch-count" data-sch-count>{busy?'Loading…':<><strong>{fmtNumber(total)}</strong> published</>}</span>}{!completenessMode&&['provider','course'].includes(type)&&<button className="m-secondary compact" onClick={()=>navigate?.('Compare',{type})}><Activity size={14}/>Compare {type}s</button>}{!completenessMode&&['provider','course'].includes(type)&&Number(rank)>=5&&<button className="m-secondary compact" onClick={()=>setCreating(true)}><Plus size={14}/>Add {type}</button>}{!completenessMode&&['provider','course','campus','scholarship'].includes(type)&&Number(rank)>=3&&<button className={`m-secondary compact${listEdit?' active':''}`} aria-pressed={listEdit} onClick={()=>setListEdit(x=>!x)}><Pencil size={14}/>{listEdit?'Done editing':'Edit in list'}</button>}</div>
      <FilterBar rank={rank} type={type} filters={filters} filterLabels={filterLabels} patch={patch} data={filterData} busy={filterBusy} advanced={advanced}/>
      {(query||active.length>0)&&<div className="m-chip-row">{query&&<FilterChip label={`Search: ${query}`} onRemove={()=>setQuery('')}/>} {active.map(([k,v])=><FilterChip key={k} label={`${k==='subdivision'?regionLabel(filters.country):filterLabel(k)}: ${filterLabels[k]||filterValueLabel(k,v,filterData)}`} onRemove={()=>patch(k,'')}/>)}</div>}
      {/* v2.15.172 (Platform Admin, 4 Oct 2026 00:11): the module lists published scholarships only; status is handled in Layers 1 to 4 */}
      {listEdit&&!busy&&rows.length?<ListEdit type={type} rows={rows} onError={onError}/>:<DataTable rows={rows} columns={cols} loading={busy} sort={sort} direction={direction} onSort={changeSort} onRow={open} selected={selected} tableId={completenessMode?'completeness':type} rowClass={type==='provider'?(r=>isPub(r)?'':'m-row-muted'):undefined}/>}
      <Pager offset={offset} limit={PAGE_SIZE} total={total} onOffset={setOffset}/>
    </section>
    {selected&&<DetailDrawer type={type} data={detail} busy={detailBusy} navigate={navigate} onError={onError} onChanged={()=>adminRead(cfg.detail,{id:selected}).then(setDetail).catch(e=>onError(e.message))} onClose={()=>{setSelected(null);setDetail(null)}}/>}
    {creating&&<CreateRecord type={type} onError={onError} onClose={()=>setCreating(false)} onCreated={id=>{setCreating(false);if(id)open({id})}}/>}
  </div>
}

function FilterBar({type,filters,filterLabels={},patch,data,busy,advanced,rank}){
  const countries=(data.countries||[]).map(x=>opt(x.code,x.name,x.code)),subdivisions=(data.subdivisions||[]).map(x=>opt(x.code,x.name,x.code))
  if(type==='provider')return <div className="m-filter-bar"><FilterSelect label="Country" value={filters.country||''} onChange={(v,l)=>patch('country',v,l)} options={countries} loading={busy}/><FilterSelect label={regionLabel(filters.country)} value={filters.subdivision||''} onChange={(v,l)=>patch('subdivision',v,l)} options={subdivisions} loading={busy}/><PagedFilterSelect kind="university_group" label="University group" value={filters.universityGroup||''} valueLabel={filterLabels.universityGroup||''} country={filters.country||''} onChange={(v,l)=>patch('universityGroup',v,l)}/><FilterSelect label="Status" value={filters.lifecycle||''} onChange={(v,l)=>patch('lifecycle',v,l)} options={STATUS_OPTIONS} emptyLabel="Active (archived are on Providers › Archived)"/><FilterSelect label="Publication" value={filters.publication||''} onChange={(v,l)=>patch('publication',v,l)} options={PUBLICATION_OPTIONS}/>{Number(rank)>=6&&<FilterSelect label="Adapter" value={filters.adapter||''} onChange={(v,l)=>patch('adapter',v,l)} options={ADAPTER_OPTIONS}/>}</div>
  if(type==='campus')return <div className="m-filter-bar"><FilterSelect label="Country" value={filters.country||''} onChange={(v,l)=>patch('country',v,l)} options={countries} loading={busy}/><FilterSelect label={regionLabel(filters.country)} value={filters.subdivision||''} onChange={(v,l)=>patch('subdivision',v,l)} options={subdivisions} loading={busy}/></div>
  if(type==='scholarship')return <div className="m-filter-bar"><FilterSelect label="Country" value={filters.country||''} onChange={(v,l)=>patch('country',v,l)} options={countries} loading={busy}/><PagedFilterSelect kind="provider" label="Provider" value={filters.provider||''} valueLabel={filterLabels.provider||''} country={filters.country||''} onChange={(v,l)=>patch('provider',v,l)}/><FilterSelect label="Audience" value={filters.audience||''} onChange={(v,l)=>patch('audience',v,l)} options={Object.entries(SCH_AUD).map(([k,v])=>opt(k,v))}/><CourseTextFilter value={filters.course||''} onChange={v=>patch('course',v,v)}/></div>
  if(type!=='course')return null
  return <div className={`m-filter-bar m-course-filters ${advanced?'expanded':''}`}>
    <PagedFilterSelect kind="country" label="Country" value={filters.country||''} valueLabel={filterLabels.country||''} onChange={(v,l)=>patch('country',v,l)}/>
    <PagedFilterSelect kind="subdivision" label={regionLabel(filters.country)} value={filters.subdivision||''} valueLabel={filterLabels.subdivision||''} country={filters.country||''} onChange={(v,l)=>patch('subdivision',v,l)}/>
    <PagedFilterSelect kind="provider" label="Provider" value={filters.provider||''} valueLabel={filterLabels.provider||''} country={filters.country||''} subdivision={filters.subdivision||''} onChange={(v,l)=>patch('provider',v,l)}/>
    <PagedFilterSelect kind="university_group" label="University group" value={filters.universityGroup||''} valueLabel={filterLabels.universityGroup||''} country={filters.country||''} onChange={(v,l)=>patch('universityGroup',v,l)}/>
    <PagedFilterSelect kind="level" label="Study level" value={filters.level||''} valueLabel={filterLabels.level||''} country={filters.country||''} subdivision={filters.subdivision||''} onChange={(v,l)=>patch('level',v,l)}/>
    {advanced&&<><PagedFilterSelect kind="field" label="Field" value={filters.field||''} valueLabel={filterLabels.field||''} country={filters.country||''} subdivision={filters.subdivision||''} onChange={(v,l)=>patch('field',v,l)}/><PagedFilterSelect kind="delivery" label="Delivery" value={filters.delivery||''} valueLabel={filterLabels.delivery||''} country={filters.country||''} subdivision={filters.subdivision||''} onChange={(v,l)=>patch('delivery',v,l)}/><TriFilter label="Has fee" value={filters.hasFee||''} onChange={(v,l)=>patch('hasFee',v,l)}/><TriFilter label="Has intake" value={filters.hasIntake||''} onChange={(v,l)=>patch('hasIntake',v,l)}/><TriFilter label="Has English" value={filters.hasEnglish||''} onChange={(v,l)=>patch('hasEnglish',v,l)}/><FilterSelect label="International students" value={filters.applicant||''} onChange={(v,l)=>patch('applicant',v,l)} options={APPLICANT_OPTIONS}/><TriFilter label="Has scholarship" value={filters.hasScholarship||''} onChange={(v,l)=>patch('hasScholarship',v,l)}/><FilterSelect label="Min legacy presence" value={filters.minCompleteness||''} onChange={(v,l)=>patch('minCompleteness',v,l)} options={[50,75,90,100].map(n=>opt(String(n),`${n}%+`))}/><FilterSelect label="Freshness" value={filters.freshness||''} onChange={(v,l)=>patch('freshness',v,l)} options={[opt('never_verified','Never verified'),opt('modified_7d','Modified in 7 days'),opt('modified_30d','Modified in 30 days'),opt('stale_180d','Stale / never verified (180d)')]}/><FilterSelect label="Status" value={filters.lifecycle||''} onChange={(v,l)=>patch('lifecycle',v,l)} options={STATUS_OPTIONS} emptyLabel="Active (archived are on Providers › Archived)"/><FilterSelect label="Publication" value={filters.publication||''} onChange={(v,l)=>patch('publication',v,l)} options={PUBLICATION_OPTIONS}/></>}
  </div>
}

function buildCatalogueArgs(type,{query,filters,offset,sort,direction}){const a={limit:PAGE_SIZE,offset,query:query||null,sort,direction};if(filters.country)a.country_code=filters.country;if(filters.subdivision)a.subdivision_code=filters.subdivision;if(filters.lifecycle&&filters.lifecycle!=='any'&&type!=='scholarship')a.lifecycle_status=filters.lifecycle;if(!filters.lifecycle&&['provider','course'].includes(type))a.lifecycle_status='active';if(filters.publication&&type!=='scholarship')a.publication_status=filters.publication;if(filters.universityGroup&&['course','provider'].includes(type))a.university_group=filters.universityGroup;if(filters.adapter&&type==='provider')a.adapter=filters.adapter;if(type==='scholarship'&&filters.provider)a.provider_id=filters.provider;if(type==='scholarship'&&filters.audience)a.audience=filters.audience;if(type==='scholarship'&&filters.course)a.course=filters.course;if(type==='scholarship')a.status='published';if(type==='course'){if(filters.provider)a.provider_id=filters.provider;if(filters.level)a.level_code=filters.level;if(filters.field)a.field_code=filters.field;if(filters.delivery)a.delivery_mode=filters.delivery;for(const k of['hasFee','hasIntake','hasEnglish','hasScholarship'])if(filters[k]!==''&&filters[k]!=null)a[camelToSnake(k)]=filters[k]==='true';if(filters.minCompleteness)a.min_completeness=Number(filters.minCompleteness);if(filters.freshness)a.freshness=filters.freshness;if(filters.applicant)a.applicant=filters.applicant}return a}
function camelToSnake(v){return v.replace(/[A-Z]/g,m=>'_'+m.toLowerCase())}
// v2.15.133 (Decision 200): who can apply. English is expected only where international students can apply.
const APPLICANT_OPTIONS=[{value:'international',label:'Open to international students'},{value:'domestic_only',label:'Domestic only'},{value:'both',label:'Open to both'},{value:'unknown',label:'Not yet known'}]
function activeFilters(f){return Object.entries(f).filter(([,v])=>v!==''&&v!==null&&v!==undefined)}
// Decision 219: the state filter is named the way each country names its divisions
export function regionLabel(c){return({AU:'State / territory',CA:'Province / territory',NZ:'Region',US:'State',GB:'Nation / region',IE:'County',DE:'State (Land)'})[String(c||'').toUpperCase()]||'State / region'}
function filterLabel(k){return({country:'Country',subdivision:'State / Region',provider:'Provider',level:'Study level',field:'Field',delivery:'Delivery',hasFee:'Has fee',hasIntake:'Has intake',hasEnglish:'Has English',hasScholarship:'Has scholarship',applicant:'International students',minCompleteness:'Min legacy presence',freshness:'Freshness',lifecycle:'Lifecycle',publication:'Publication',adapter:'Adapter',universityGroup:'University group',audience:'Audience',course:'Course',status:'Status'})[k]||humanise(k)}
const UNIVERSITY_GROUP_OPTIONS=[{value:'go8',label:'Group of Eight'},{value:'atn',label:'Australian Technology Network'},{value:'iru',label:'Innovative Research Universities'},{value:'run',label:'Regional Universities Network'}]
function filterValueLabel(k,v,d){if(['hasFee','hasIntake','hasEnglish','hasScholarship'].includes(k))return v==='true'?'Yes':'No';const sets={country:d.countries,subdivision:d.subdivisions,provider:d.providers,level:d.levels,field:d.fields,delivery:d.delivery_modes,universityGroup:UNIVERSITY_GROUP_OPTIONS};const list=sets[k]||[];const found=list.find(x=>String(x.id??x.code??x.value)===String(v));return found?.name??found?.label??humanise(v)}

// v2.15.169 (Platform Admin, mockup comment 21:36 "Search — on course as well"): scholarships linked to a course, by title or CRICOS / course code
function CourseTextFilter({value,onChange}){const[t,setT]=useState(value);useEffect(()=>setT(value),[value]);const commit=()=>{if(t.trim()!==value)onChange(t.trim())};return <label className="m-filter-select m-filter-text" data-course-filter><span className="m-filter-button has-value" style={{cursor:'text'}}><span><small>Course</small><input value={t} onChange={e=>setT(e.target.value)} onBlur={commit} onKeyDown={e=>{if(e.key==='Enter')commit()}} placeholder="Title or CRICOS code" aria-label="Course title or CRICOS code" style={{border:0,background:'transparent',font:'inherit',fontWeight:700,width:'100%',minWidth:150,outline:'none'}}/></span><Search size={14}/></span></label>}
function FilterSelect({label,value,onChange,options=[],loading=false,emptyLabel='All'}){const[open,setOpen]=useState(false),[search,setSearch]=useState(''),[page,setPage]=useState(0);const ref=useRef(null),inputRef=useRef(null);useEffect(()=>{const close=e=>{if(ref.current&&!ref.current.contains(e.target))setOpen(false)};addEventListener('mousedown',close);return()=>removeEventListener('mousedown',close)},[]);useEffect(()=>setPage(0),[search,options.length]);useEffect(()=>{if(open&&typeof window!=='undefined'&&window.matchMedia?.('(pointer:fine)').matches)setTimeout(()=>inputRef.current?.focus(),0)},[open]);const selected=options.find(x=>String(x.value)===String(value));const filtered=options.filter(x=>`${x.label} ${x.meta||''}`.toLowerCase().includes(search.toLowerCase())),pages=Math.max(1,Math.ceil(filtered.length/10)),safePage=Math.min(page,pages-1),visible=filtered.slice(safePage*10,safePage*10+10);return <div className="m-filter-select" ref={ref}><button className={`m-filter-button ${value?'has-value':''}`} onClick={()=>setOpen(x=>!x)}><span><small>{label}</small><strong>{selected?.label||emptyLabel}</strong></span>{loading?<span className="m-spinner tiny"/>:<ChevronDown size={14}/>}</button>{open&&<div className="m-filter-popover"><div className="m-filter-search"><Search size={14}/><input ref={inputRef} value={search} onChange={e=>setSearch(e.target.value)} placeholder={`Search ${label.toLowerCase()}…`}/></div><button className={!value?'selected':''} onClick={()=>{onChange('',emptyLabel);setOpen(false);setSearch('');setPage(0)}}><span>{emptyLabel}</span></button>{visible.map(x=><button key={String(x.value)} className={String(value)===String(x.value)?'selected':''} onClick={()=>{onChange(x.value,x.label);setOpen(false);setSearch('');setPage(0)}}><span>{x.label}</span>{x.meta&&<small>{x.meta}</small>}</button>)}{!visible.length&&<div className="m-option-empty">No matching options</div>}{filtered.length>10&&<div className="m-filter-pager"><button disabled={safePage===0} onClick={()=>setPage(p=>Math.max(0,p-1))}>Previous</button><span>{safePage+1} / {pages}</span><button disabled={safePage>=pages-1} onClick={()=>setPage(p=>Math.min(pages-1,p+1))}>Next</button></div>}</div>}</div>}
function PagedFilterSelect({kind,label,value,valueLabel='',onChange,country='',subdivision=''}){const[open,setOpen]=useState(false),[search,setSearch]=useState(''),[offset,setOffset]=useState(0),[data,setData]=useState({items:[],total:0,has_more:false}),[busy,setBusy]=useState(false),[selectedLabel,setSelectedLabel]=useState(valueLabel);const ref=useRef(null),inputRef=useRef(null),debounced=useDebounce(search,220);useEffect(()=>{const close=e=>{if(ref.current&&!ref.current.contains(e.target))setOpen(false)};addEventListener('mousedown',close);return()=>removeEventListener('mousedown',close)},[]);useEffect(()=>{setOffset(0)},[debounced,country,subdivision,kind]);useEffect(()=>{if(valueLabel)setSelectedLabel(valueLabel);if(!value)setSelectedLabel('')},[value,valueLabel]);useEffect(()=>{if(!open)return;let live=true;setBusy(true);api.catalogueFilterPage({kind,country,subdivision,query:debounced,limit:10,offset}).then(x=>{if(!live)return;setData(x||{items:[],total:0,has_more:false});const hit=(x?.items||[]).find(y=>String(y.value)===String(value));if(hit)setSelectedLabel(hit.label)}).catch(()=>live&&setData({items:[],total:0,has_more:false})).finally(()=>live&&setBusy(false));return()=>{live=false}},[open,kind,country,subdivision,debounced,offset,value]);useEffect(()=>{if(open&&typeof window!=='undefined'&&window.matchMedia?.('(pointer:fine)').matches)setTimeout(()=>inputRef.current?.focus(),0)},[open]);const items=data.items||[],page=Math.floor(offset/10)+1,pages=Math.max(1,Math.ceil(Number(data.total||0)/10));return <div className="m-filter-select" ref={ref}><button className={`m-filter-button ${value?'has-value':''}`} onClick={()=>setOpen(x=>!x)}><span><small>{label}</small><strong>{selectedLabel||'All'}</strong></span>{busy?<span className="m-spinner tiny"/>:<ChevronDown size={14}/>}</button>{open&&<div className="m-filter-popover"><div className="m-filter-search"><Search size={14}/><input ref={inputRef} value={search} onChange={e=>setSearch(e.target.value)} placeholder={`Search ${label.toLowerCase()}…`}/></div><button className={!value?'selected':''} onClick={()=>{onChange('','All');setSelectedLabel('');setOpen(false);setSearch('');setOffset(0)}}><span>All</span></button>{items.map(x=><button key={String(x.value)} className={String(value)===String(x.value)?'selected':''} onClick={()=>{setSelectedLabel(x.label);onChange(x.value,x.label);setOpen(false);setSearch('');setOffset(0)}}><span>{x.label}</span>{x.meta&&<small>{x.meta}</small>}</button>)}{!items.length&&!busy&&<div className="m-option-empty" data-empty-reason>{(!search&&data.empty_reason)||'No matching options'}</div>}{Number(data.total||0)>10&&<div className="m-filter-pager"><button disabled={offset===0} onClick={()=>setOffset(o=>Math.max(0,o-10))}>Previous</button><span>{page} / {pages}</span><button disabled={!data.has_more} onClick={()=>setOffset(o=>o+10)}>Next</button></div>}</div>}</div>}
function AsyncPagedFilterSelect({kind,label,value,valueLabel='',onChange,country='',survey=''}){const[open,setOpen]=useState(false),[search,setSearch]=useState(''),[offset,setOffset]=useState(0),[data,setData]=useState({items:[],total:0,has_more:false}),[busy,setBusy]=useState(false),[selectedLabel,setSelectedLabel]=useState(valueLabel);const ref=useRef(null),inputRef=useRef(null),debounced=useDebounce(search,220);useEffect(()=>{const close=e=>{if(ref.current&&!ref.current.contains(e.target))setOpen(false)};addEventListener('mousedown',close);return()=>removeEventListener('mousedown',close)},[]);useEffect(()=>{setOffset(0)},[debounced,country,survey,kind]);useEffect(()=>{if(valueLabel)setSelectedLabel(valueLabel);if(!value)setSelectedLabel('')},[value,valueLabel]);useEffect(()=>{if(!open)return;let live=true;setBusy(true);api.filterOptionPage({kind,country,survey,query:debounced,limit:10,offset}).then(x=>{if(!live)return;setData(x||{items:[],total:0,has_more:false});const hit=(x?.items||[]).find(y=>String(y.value)===String(value));if(hit)setSelectedLabel(hit.label)}).catch(()=>live&&setData({items:[],total:0,has_more:false})).finally(()=>live&&setBusy(false));return()=>{live=false}},[open,kind,country,survey,debounced,offset,value]);useEffect(()=>{if(open&&typeof window!=='undefined'&&window.matchMedia?.('(pointer:fine)').matches)setTimeout(()=>inputRef.current?.focus(),0)},[open]);const items=data.items||[],page=Math.floor(offset/10)+1,pages=Math.max(1,Math.ceil(Number(data.total||0)/10));return <div className="m-filter-select" ref={ref}><button className={`m-filter-button ${value?'has-value':''}`} onClick={()=>setOpen(x=>!x)}><span><small>{label}</small><strong>{selectedLabel||'All'}</strong></span>{busy?<span className="m-spinner tiny"/>:<ChevronDown size={14}/>}</button>{open&&<div className="m-filter-popover"><div className="m-filter-search"><Search size={14}/><input ref={inputRef} value={search} onChange={e=>setSearch(e.target.value)} placeholder={`Search ${label.toLowerCase()}…`}/></div><button className={!value?'selected':''} onClick={()=>{onChange('','All');setSelectedLabel('');setOpen(false);setSearch('');setOffset(0)}}><span>All</span></button>{items.map(x=><button key={String(x.value)} className={String(value)===String(x.value)?'selected':''} onClick={()=>{setSelectedLabel(x.label);onChange(x.value,x.label);setOpen(false);setSearch('');setOffset(0)}}><span>{x.label}</span>{x.meta&&<small>{x.meta}</small>}</button>)}{!items.length&&!busy&&<div className="m-option-empty">No matching options</div>}{Number(data.total||0)>10&&<div className="m-filter-pager"><button disabled={offset===0} onClick={()=>setOffset(o=>Math.max(0,o-10))}>Previous</button><span>{page} / {pages}</span><button disabled={!data.has_more} onClick={()=>setOffset(o=>o+10)}>Next</button></div>}</div>}</div>}

function TriFilter({label,value,onChange}){return <FilterSelect label={label} value={value} onChange={onChange} options={[opt('true','Yes'),opt('false','No')]}/>}function opt(value,label,meta=''){return{value,label,meta}}
const ADAPTER_CELL={admitting:['Admitting','tone-success'],testing:['Testing','tone-info'],off:['Switched off','tone-neutral']}
// v2.15.316 (Platform Admin 22 Oct 2026 16:22): a provider with no active course needs no adapter; it says so instead of offering Create adapter
function AdapterCell({state,onOpen,noCourses=false}){if(!state)return <span className="m-row-skeleton"/>;const build=state.build,active=build&&!['done','failed','stopped'].includes(build.status),has=Boolean(state.adapter);if(noCourses&&!has&&!active)return <span className="m-adapter-cell" data-adapter-cell="no_courses"><small className="cf-chip tone-neutral" title="No active courses: nothing for an adapter to read. Onboarding starts by itself once the provider has an active course.">No courses</small></span>;const [l,t]=active?['Building…','tone-info']:ADAPTER_CELL[state.adapter]||['No adapter','tone-neutral'];return <span className="m-adapter-cell" data-adapter-cell={state.adapter||'none'}><button type="button" className="m-secondary compact" onClick={e=>{e.stopPropagation();onOpen()}}>{has||active?'Open adapter':'Create adapter'}</button>{(has||active)&&<small className={`cf-chip ${t}`}>{l}</small>}</span>}
// v2.15.225 (Platform Admin, 9 Oct 2026: "doesn't pan out to page width, columns not adjustable"): every list fills the
// width of the page with a fixed layout, so one long value can never push other columns off screen; drag a heading's right
// edge to resize a column (double-click resets). Widths are remembered per list in this browser only.
function useColumnWidths(id){const key=`cf-colw:${id}`;const[w,setW]=useState(()=>{try{return JSON.parse(localStorage.getItem(key)||'{}')||{}}catch{return{}}});const save=n=>{setW(n);try{localStorage.setItem(key,JSON.stringify(n))}catch{}};return[w,save]}
function DataTable({rows,columns,loading,sort,direction,onSort,onRow,selected,tableId='list',rowClass}){const[widths,setWidths]=useColumnWidths(tableId);const total=columns.reduce((a,c)=>a+Number(c.width||180),0);const minW=columns.reduce((a,c)=>a+(widths[c.key]||Math.max(90,Math.round(Number(c.width||180)*.6))),0);
  const drag=(e,key)=>{e.preventDefault();e.stopPropagation();const th=e.currentTarget.parentElement,x0=e.clientX,w0=th.getBoundingClientRect().width;const move=ev=>setWidths({...widths,[key]:Math.max(64,Math.round(w0+ev.clientX-x0))});const up=()=>{removeEventListener('pointermove',move);removeEventListener('pointerup',up)};addEventListener('pointermove',move);addEventListener('pointerup',up)}
  const reset=(e,key)=>{e.stopPropagation();const n={...widths};delete n[key];setWidths(n)}
  return <div className="m-table-wrap"><table className="m-table m-fluid-table m-fit-table" data-table={tableId} style={{width:'100%',minWidth:minW,tableLayout:'fixed'}}><colgroup>{columns.map(c=><col key={c.key} style={{width:widths[c.key]?`${widths[c.key]}px`:`${(Number(c.width||180)/total*100).toFixed(2)}%`}}/>)}</colgroup><thead><tr>{columns.map((c,i)=><th key={c.key} className={i===0?'sticky-col':''}><button disabled={!c.sortKey} onClick={()=>onSort(c.sortKey)}>{c.label}{c.sortKey&&sort===c.sortKey&&(direction==='asc'?<ArrowUp size={12}/>:<ArrowDown size={12}/>)}</button><span className="m-col-resize" role="separator" aria-orientation="vertical" aria-label={`Resize ${c.label} column`} title="Drag to resize · double-click to reset" data-col-resize={c.key} onPointerDown={e=>drag(e,c.key)} onDoubleClick={e=>reset(e,c.key)} onClick={e=>e.stopPropagation()}/></th>)}</tr></thead><tbody>{loading&&rows.length===0?Array.from({length:8}).map((_,i)=><tr key={i}>{columns.map((c,j)=><td className={j===0?'sticky-col':''} key={c.key}><span className="m-row-skeleton"/></td>)}</tr>):rows.length?rows.map((r,i)=><tr key={r.id??r.course_id??i} className={[String(selected)===String(r.id??r.course_id)?'selected':'',rowClass?.(r)||''].filter(Boolean).join(' ')} onClick={()=>onRow?.(r)}>{columns.map((c,j)=><td key={c.key} className={j===0?'sticky-col':''}>{c.render?c.render(r):cell(r,c.key)}</td>)}</tr>):<tr><td colSpan={columns.length}><EmptyInline text="No records match the current filters."/></td></tr>}</tbody></table></div>}

function columns(type,complete){if(complete)return[{key:'canonical_title',label:'Course',width:300,sortKey:'course'},{key:'provider_name',label:'Provider',width:240,sortKey:'provider'},{key:'course_code',label:'Course code',width:150},{key:'completeness_score_v2',label:'Completeness',width:120,sortKey:'completeness'},{key:'has_fee',label:'Fee',width:90},{key:'has_intake',label:'Intake',width:90},{key:'has_english',label:'English',width:90},{key:'last_verified_at',label:'Verified',width:150,sortKey:'verified'}];if(type==='provider')return[{key:'canonical_name',label:'Provider',width:300,sortKey:'provider'},{key:'country_code',label:'Country',width:110},{key:'subdivision_name',label:'State / Region',width:160},{key:'city',label:'City',width:150},{key:'course_count',label:'Courses',width:95,sortKey:'courses'},{key:'university_groups',label:'Group',width:110},{key:'evidence_count',label:'Evidence',width:95},{key:'lifecycle_status',label:'Lifecycle',width:115},{key:'publication_status',label:'Publication',width:130},{key:'last_verified_at',label:'Verified',width:150,sortKey:'verified'}];if(type==='course')return[{key:'canonical_title',label:'Course',width:310,sortKey:'course'},{key:'provider_name',label:'Provider',width:240,sortKey:'provider'},{key:'course_code',label:'Course code',width:155},{key:'subdivision_name',label:'State / Region',width:150},{key:'city_names',label:'City',width:150,sortKey:'city'},{key:'level_name',label:'Study level',width:150},{key:'field_of_study',label:'Field',width:190,sortKey:'field'},{key:'intl_fee_amount',label:'International fee',width:190,sortKey:'intl_fee'},{key:'fee_amount',label:'Tuition Only',width:150,sortKey:'fee'},{key:'completeness_score_v2',label:'Completeness',width:120,sortKey:'completeness'},{key:'last_verified_at',label:'Verified',width:145,sortKey:'verified'}];if(type==='campus')return[{key:'name',label:'Campus',width:270,sortKey:'campus'},{key:'provider_name',label:'Provider',width:260,sortKey:'provider'},{key:'country_code',label:'Country',width:105},{key:'subdivision_name',label:'State / Region',width:160},{key:'city',label:'City',width:150,sortKey:'city'},{key:'course_count',label:'Courses',width:90,sortKey:'courses'},{key:'status',label:'Status',width:110}];// v2.15.171 (Platform Admin, 3 Oct 2026 23:27: match the mockup): Scholarship with its provider, Value, Who it is for, Closes, Status with its reason
  // v2.15.223 (Platform Admin, 9 Oct 2026: "fluid columns, order on each column heading"): one column per fact, every heading sorts
  return[{key:'sch_name',label:'Scholarship',width:260,sortKey:'scholarship'},{key:'provider_name',label:'Provider',width:190,sortKey:'provider'},{key:'sch_type',label:'Type',width:150,sortKey:'type'},{key:'sch_who',label:'Who it is for',width:200,sortKey:'audience'},{key:'value_label',label:'Value',width:170,sortKey:'award'},{key:'sch_courses',label:'Courses',width:100,sortKey:'courses'},{key:'sch_closes',label:'Closes',width:130,sortKey:'close'}]}
// v2.15.130 (sch-jargon): plain labels for scholarship type and audience codes.
const SCH_TYPE={provider_scholarship:'University scholarship',government_scholarship:'Government scholarship',external_scholarship:'External scholarship',bursary:'Bursary',fee_discount:'Fee discount'},SCH_AUD={international:'International students',domestic:'Domestic students',international_and_domestic:'International and domestic',not_stated:'Not stated on the page',all:'All students'} // v2.15.167 (Decision 244): read from each scholarship's wording
const NAT_NAME={'R-ASEAN':'ASEAN region','R-SASIA':'South Asia','R-LATAM':'Latin America','R-AFRICA':'Africa','R-EUROPE':'Europe','R-MENA':'Middle East','R-PACIFIC':'Pacific','R-NASIA':'North Asia','R-AMERICAS':'The Americas','R-CARIB':'Caribbean','R-CASIA':'Central Asia',IN:'India',CN:'China',NP:'Nepal',PK:'Pakistan',BD:'Bangladesh',LK:'Sri Lanka',VN:'Vietnam',ID:'Indonesia',MY:'Malaysia',SG:'Singapore',TH:'Thailand',PH:'Philippines',KH:'Cambodia',MM:'Myanmar',BN:'Brunei',JP:'Japan',KR:'Korea',TW:'Taiwan',HK:'Hong Kong',NG:'Nigeria',KE:'Kenya',GH:'Ghana',ZA:'South Africa',ZW:'Zimbabwe',CO:'Colombia',MX:'Mexico',CL:'Chile',BR:'Brazil',AR:'Argentina',PE:'Peru',US:'United States',CA:'Canada',GB:'United Kingdom',NZ:'New Zealand',PG:'Papua New Guinea',FJ:'Fiji',AF:'Afghanistan',SA:'Saudi Arabia',AE:'United Arab Emirates'}
// v2.15.224: pill colours — type of scholarship, who it is for, and how close the application closing date is
const SCH_TYPE_TONE={provider_scholarship:'info',government_scholarship:'success',external_scholarship:'violet',bursary:'warning',fee_discount:'neutral'},SCH_AUD_TONE={international:'violet',domestic:'neutral',international_and_domestic:'info',all:'info',not_stated:'neutral'}
function natShort(n){if(!n.length)return'Any nationality';const names=n.map(c=>NAT_NAME[c]||c);return names.length>2?`${names.slice(0,2).join(', ')} +${names.length-2} more`:names.join(', ')}
function closeState(d){if(!d)return{tone:'neutral',label:'No closing date',title:'The page states no closing date'};const t=new Date(`${String(d).slice(0,10)}T23:59:59`),days=Math.ceil((t-new Date())/86400000);if(!Number.isFinite(days))return{tone:'neutral',label:'—'};if(days<0)return{tone:'danger',label:`Closed ${fmtDate(d)}`,title:'Applications have closed'};if(days<=30)return{tone:'warning',label:fmtDate(d),title:`Closes in ${days} day${days===1?'':'s'}`};return{tone:'success',label:fmtDate(d),title:'Open'}}
const SCH_STATUS={published:['Published','sch-st sch-st-pub'],ready:['Ready to publish','sch-st sch-st-ready'],held:['Held','sch-st sch-st-held'],inactive:['Inactive','sch-st sch-st-off']}
const capFirst=t=>t?String(t).charAt(0).toUpperCase()+String(t).slice(1):''
const FEE_BASIS={annual:'per year',per_year:'per year',total_course:'whole course',registered_total_course:'whole course (registered)',per_semester:'per semester',per_trimester:'per trimester',per_unit:'per unit',per_credit:'per credit',per_week:'per week',per_term:'per term'}
const feeBasisLabel=b=>FEE_BASIS[b]||humanise(String(b||''))
function cell(r,key){const v=r[key];
  // v2.15.224 (Platform Admin, 9 Oct 2026: "coloured pills"): type, who it is for, courses and closing date as status pills
  if(key==='sch_courses'){const n=Number(r.mapped_course_count)||0;return <span data-sch-courses><StatusChip tone={n?'success':'warning'} label={n?`${fmtNumber(n)} linked`:'None linked yet'}/></span>}
  if(key==='sch_type'){const t=r.scholarship_type;return t?<StatusChip tone={SCH_TYPE_TONE[t]||'neutral'} label={SCH_TYPE[t]||humanise(t)}/>:<span className="sch-muted">—</span>}
  if(key==='sch_closes'){const c=closeState(r.application_close_date);return <StatusChip tone={c.tone} label={c.label} title={c.title}/>}
  if(key==='provider_name')return <span className="sch-wrap" title={r.provider_name||''}>{r.provider_name||'—'}</span>
  if(key==='sch_name')return <strong className="sch-wrap sch-name" title={r.name}>{r.name??'—'}</strong>
  if(key==='value_label')return v?<span className="sch-wrap" title={v}>{v}</span>:<span className="sch-wrap sch-muted">Value not stated</span>
  if(key==='sch_who'){const n=Array.isArray(r.nationalities)?r.nationalities:[];return <span className="sch-chips"><StatusChip tone={SCH_AUD_TONE[r.audience]||'neutral'} label={SCH_AUD[r.audience]||'Not stated'}/><StatusChip tone="neutral" label={natShort(n)} title={n.length?n.map(c=>NAT_NAME[c]||c).join(', '):'Any nationality'}/></span>}
  if(key==='sch_status'){const st=SCH_STATUS[r.status]||[humanise(r.publication_status||''),'sch-st'],why=Array.isArray(r.held_reasons)&&r.held_reasons.length?r.held_reasons.map(capFirst).join('; '):(r.status==='ready'?'Passes every check':'');return <span className="sch-status"><span className={st[1]}>{st[0]}</span>{why&&<small title={why}>{why}</small>}</span>}
  // v2.15.326 (Platform Admin 23 Oct 2026 12:52: "Still no city or fees on these"): the provider's international fee with its year, and the campus cities
  // v2.15.342 (UI audit Phase 2): the fee with its year and its basis as the blade prints it; "—" when the provider publishes none
  if(key==='intl_fee_amount')return v!=null?<span title="International tuition the provider publishes">{fmtMoney(Number(v),r.intl_fee_currency)}{r.intl_fee_year?` (${r.intl_fee_year})`:''}{r.intl_fee_basis?<small className="m-fee-basis"> · {feeBasisLabel(r.intl_fee_basis)}</small>:null}</span>:'—'
  if(key==='city_names')return v||'—'
  if(key==='application_close_date')return v?fmtDate(v):'—';if(key==='scholarship_type')return v?(SCH_TYPE[v]||humanise(v)):'—';if(key==='audience')return v?(SCH_AUD[v]||humanise(v)):'—';if(key==='nationalities')return Array.isArray(v)&&v.length?v.join(', '):'—';if(key==='award_value_text'){const lab=r.value_label;return lab?<span className="m-cell-clip" title={lab}>{lab}</span>:<span className="m-cell-clip" title={String(v||'')}>Value not stated</span>}if(key==='award_value_text_raw')return v?<span className="m-cell-clip" title={String(v)}>{String(v)}</span>:'—';if(key==='university_groups')return <UniversityGroups value={v} short/>;if(['canonical_name','canonical_title','name'].includes(key))return <span className="m-cell-title"><strong>{v??'—'}</strong>{r.stable_key&&<small>{r.stable_key}</small>}</span>;if(key==='country_code')return <span>{countryFlag(v)} {v||'—'}</span>;if(key==='course_code'){const c=r.display_code||v;if(!c)return'—';return r.code_kind==='studysearch'?<span className="m-code-ss" data-code-kind="studysearch" title="StudySearch code: the university and regulator print no code for this course"><code className="m-code">{c}</code><small>SS</small></span>:<code className="m-code">{c}</code>}if(key==='fee_amount')return v==null?'—':fmtMoney(v,r.fee_currency||'AUD');if(key==='completeness_score_v2')return <Score value={v??r.completeness_score}/>;if(['has_fee','has_intake','has_english','has_scholarship'].includes(key))return <Bool value={v}/>;if(key.includes('status')||key==='status')return <Status value={v}/>;if(key.endsWith('_at'))return v?fmtDate(v):'Never';return v==null||v===''?'—':String(v)}
function UniversityGroups({value,short=false}){const list=Array.isArray(value)?value:[];if(!list.length)return short?'—':null;return <span style={{display:'inline-flex',gap:4,flexWrap:'wrap'}}>{list.map(g=><span key={g.code} className="m-status status-info" title={g.name}>{short?String(g.code||'').toUpperCase():g.name}</span>)}</span>}
function Score({value}){const n=Math.max(0,Math.min(100,Number(value)||0));return <span className="m-score"><span><i style={{width:`${n}%`}}/></span><b>{fmtPercent(n)}</b></span>}
// v2.15.276 (Decision 258): institution type cell. The basis (rule or reason) shows on hover.
function TypeCell({row,opts,can,busy,onSet}){const code=row.provider_type_code,basis=row.provider_type_basis||'',locked=Boolean(row.provider_type_locked)
  const shown=code?<span data-type-code={code} title={basis||undefined}>{row.provider_type_name||code}{locked?' · set by hand':''}</span>:basis?<span data-type-code="none"><StatusChip tone="warning" label="Needs type" title={basis}/></span>:<span data-type-code="none">—</span>
  if(!can||!opts.length)return shown
  return <span className="m-type-cell" style={{display:'grid',gap:4}}>{shown}<select aria-label={`Institution type for ${row.canonical_name||'provider'}`} value={locked&&code?code:'auto'} disabled={busy} onChange={e=>onSet(e.target.value)}><option value="auto">Auto (register rules)</option>{opts.map(t=><option key={t.code} value={t.code}>{t.name}</option>)}</select></span>}
function PublishSwitch({on,busy,can,archived,onToggle}){
  const label=archived?'Archived':on?'Published':'Unpublished'
  return <span className="m-publish" data-publish={on?'on':'off'}><button type="button" role="switch" aria-checked={on} aria-label={`Published: ${label}`} className={`m-switch${on?' on':''}`} disabled={!can||busy} title={archived?'Restore the provider to publish it':can?(on?'Switch off to hide this provider from Wix, Zoho and the website and pause its background work':'Unpublished: hidden and its background work is paused. Switch on to publish this provider'):'PIM Operators and above can change this'} onClick={e=>{e.stopPropagation();onToggle()}}><i/></button><small>{busy?'Saving…':label}</small></span>
}
function Bool({value}){return <span className={`m-bool ${value?'yes':'no'}`}>{value?'Yes':'No'}</span>}
function Status({value}){const s=String(value??'unknown').toLowerCase();return <StatusChip value={s} label={humanise(s)}/>}


function DetailDrawer({type,data,busy,onClose,navigate,onError,onChanged}){useEffect(()=>{const k=e=>e.key==='Escape'&&onClose();addEventListener('keydown',k);return()=>removeEventListener('keydown',k)},[onClose]);const title=detailTitle(data,type);return <><button className="m-drawer-backdrop" onClick={onClose}/><aside className={"m-drawer m-drawer-"+type} aria-label={humanise(type)+" detail"}><div className="m-drawer-head"><div>{type==='provider'&&data?.id?<><small>Provider detail</small><ProviderBrand providerId={data.id} name={title} subtitle={[data?.country_code,data?.primary_city].filter(Boolean).join(' · ')} size={54} editable/></>:<><small>{humanise(type)} detail</small><h2>{title}</h2></>}</div><div style={{display:'flex',gap:6}}>{data?.id&&['provider','course'].includes(type)&&<button title={`Compare this ${type}`} onClick={()=>navigate?.('Compare',{type,ids:data.id})}><Activity size={17}/></button>}{data?.id&&['provider','course','campus','scholarship'].includes(type)&&<button title="Open supporting evidence" onClick={()=>navigate?.('Evidence',{entity_type:type,entity_id:data.id})}><BookOpen size={17}/></button>}<button onClick={onClose} aria-label={"Close "+humanise(type)+" detail"}><X size={18}/></button></div></div><div className="m-drawer-content">{busy?<div className="m-drawer-loading"><span className="m-spinner"/>Loading…</div>:<DetailBody type={type} data={data} navigate={navigate} onError={onError} onChanged={onChanged}/>}</div></aside></>}
// v2.15.226: related insights load only when the fold is opened (provider_detail no longer carries them)
function ProviderMore({data,type,navigate}){const[open,setOpen]=useState(false),[ins,setIns]=useState(null),[err,setErr]=useState('');useEffect(()=>{if(!open||ins||!data?.id)return;let live=true;adminRead('provider_insights',{id:data.id}).then(x=>live&&setIns(x?.contextual_insights||{})).catch(e=>live&&setErr(e.message||String(e)));return()=>{live=false}},[open,data?.id]);return <details className="ds-more" data-provider-more onToggle={e=>setOpen(e.currentTarget.open)}><summary>More about this provider</summary><div><Layer4Intervention type={type} data={data}/>{open&&(err?<p className="fr-error" role="alert">{err}</p>:ins?<ContextualInsights data={ins} navigate={navigate} entityType="provider"/>:<div className="m-drawer-loading"><span className="m-spinner"/>Loading related insights…</div>)}</div></details>}
function detailTitle(d,type){if(!d)return'Loading…';return d.display_title||d.canonical_title||d.canonical_name||d.name||d.stable_key||humanise(type)}
function InternationalContacts({data,navigate}){const block=data?.international_contacts||{},items=Array.isArray(block.items)?block.items:[],events=Array.isArray(block.events)?block.events:[],summary=block.summary||{},profile=block.profile||{},disposition=block.disposition||{};return <section className="m-detail-section cf-contact-intel"><style>{`
.cf-contact-intel{display:grid;gap:10px}.cf-contact-head{display:flex;justify-content:space-between;gap:12px;align-items:flex-start}.cf-contact-head h3{margin:0;font-size:var(--cf-fs-base)}.cf-contact-head p{margin:4px 0 0;color:var(--cf-slate-500);font-size:var(--cf-fs-xs);line-height:1.45}.cf-contact-summary{display:flex;gap:6px;flex-wrap:wrap}.cf-contact-summary span{border:1px solid var(--cf-slate-200);background:var(--cf-slate-50);border-radius:var(--cf-radius-pill);padding:4px 7px;font-size:var(--cf-fs-2xs);color:var(--cf-slate-600);font-weight:750}.cf-contact-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}.cf-contact-card{border:1px solid var(--cf-slate-200);border-radius:var(--cf-radius-lg);background:var(--cf-white);padding:10px;display:grid;gap:7px}.cf-contact-card.primary{border-color:var(--cf-indigo-200);background:var(--cf-slate-50)}.cf-contact-top{display:flex;justify-content:space-between;gap:8px;align-items:flex-start}.cf-contact-name{display:grid;gap:2px}.cf-contact-name strong{font-size:var(--cf-fs-md);color:var(--cf-slate-900)}.cf-contact-name small{font-size:var(--cf-fs-2xs);color:var(--cf-slate-500)}.cf-contact-badge{white-space:nowrap;border-radius:var(--cf-radius-pill);padding:3px 6px;font-size:var(--cf-fs-3xs);font-weight:850;background:var(--cf-indigo-50);color:var(--cf-indigo-700)}.cf-contact-badge.enriched{background:var(--cf-slate-100);color:var(--cf-slate-600)}.cf-contact-territory{display:grid;gap:2px;padding:7px 8px;border-radius:var(--cf-radius-md);background:var(--cf-slate-50)}.cf-contact-territory small{font-size:var(--cf-fs-3xs);text-transform:uppercase;letter-spacing:.04em;color:var(--cf-slate-400);font-weight:800}.cf-contact-territory strong{font-size:var(--cf-fs-xs);color:var(--cf-slate-700);line-height:1.45}.cf-contact-links{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.cf-contact-links a{font-size:var(--cf-fs-2xs);color:var(--cf-indigo-600);text-decoration:none}.cf-contact-meta{font-size:var(--cf-fs-3xs);color:var(--cf-slate-400);line-height:1.4}.cf-contact-changes{border-top:1px solid var(--cf-slate-150);padding-top:8px}.cf-contact-changes strong{font-size:var(--cf-fs-2xs);color:var(--cf-slate-600)}.cf-contact-changes span{display:block;font-size:var(--cf-fs-3xs);color:var(--cf-slate-500);margin-top:3px}@media(max-width:760px){.cf-contact-grid{grid-template-columns:1fr}.cf-contact-head{display:grid}.cf-contact-summary{justify-content:flex-start}}
`}</style><div className="cf-contact-head"><div><h3>International contacts</h3><p>First-party university contacts are preferred. Licensed professional enrichment is secondary and does not overwrite university-published assignments.</p>{data?.id&&<button className="m-secondary compact" style={{marginTop:7}} onClick={()=>navigate?.('Provider Contacts',{provider_id:data.id})}><UsersRound size={12}/>View all Provider Contacts</button>}</div><div className="cf-contact-summary"><span>{humanise(disposition.disposition||'pending_acquisition')}</span><span>{Number(summary.first_party_contacts||0)} first-party</span><span>{Number(summary.enriched_contacts||0)} enriched</span>{Number(summary.unacknowledged_changes||0)>0&&<span>{summary.unacknowledged_changes} change signal{Number(summary.unacknowledged_changes)===1?'':'s'}</span>}</div></div>{!items.length&&disposition.disposition&&<div className="cf-contact-meta">A16 disposition: <strong>{humanise(disposition.disposition)}</strong>. Qualified first-party evidence is retained; missing contacts are never manufactured.</div>}{items.length?<div className="cf-contact-grid">{items.map((x,i)=><article key={x.id||i} className={`cf-contact-card ${x.source_class==='first_party'?'primary':''}`}><div className="cf-contact-top"><div className="cf-contact-name"><strong>{x.full_name||x.team_name||'International team'}</strong><small>{x.job_title||x.team_name||'Professional contact'}</small></div><span className={`cf-contact-badge ${x.source_class==='licensed_enrichment'?'enriched':''}`}>{x.source_class==='first_party'?'First-party university':'Licensed enrichment'}</span></div>{x.territory_text&&<div className="cf-contact-territory"><small>Territory / market</small><strong>{x.territory_text}</strong></div>}<div className="cf-contact-links">{x.work_email&&<a href={`mailto:${x.work_email}`}>{x.work_email}</a>}{x.work_phone&&<a href={`tel:${String(x.work_phone).replace(/[^+0-9]/g,'')}`}>{x.work_phone}</a>}{x.source_url&&<a href={x.source_url} target="_blank" rel="noreferrer">University source <ExternalLink size={9}/></a>}{x.professional_profile_url&&<a href={x.professional_profile_url} target="_blank" rel="noreferrer">Professional profile <ExternalLink size={9}/></a>}{x.evidence_id&&<EvidenceButton id={x.evidence_id} navigate={navigate}/>}</div><div className="cf-contact-meta">{x.source_provider?humanise(x.source_provider):'Source retained'} · Verified {x.last_verified_at?fmtDate(x.last_verified_at):'—'}{x.verification_state&&` · ${humanise(x.verification_state)}`}</div>{x.layer4&&<details><summary style={{fontSize:9,fontWeight:800,cursor:'pointer'}}>Layer 4 resolve</summary><Layer4Intervention type="provider_contact" data={x} publicationEnabled={false}/></details>}</article>)}</div>:<EmptyInline text={profile.enabled===false?'Contact discovery is disabled for this Provider.':'No current international recruitment contact has been verified yet.'}/>} {events.length>0&&<div className="cf-contact-changes"><strong>Recent contact signals</strong>{events.slice(0,3).map((e,i)=><span key={e.id||i}>{humanise(e.event_type)} · {e.detected_at?fmtDate(e.detected_at):'—'}</span>)}</div>}</section>}

function DetailBody({type,data,navigate,onError,onChanged}){if(!data)return <EmptyInline text="No detail returned."/>;if(type==='course')return <CourseDetailPolish data={data} navigate={navigate} editor={data.id?<CourseEditor inline courseId={data.id} onChanged={onChanged} onError={onError}/>:null} more={<Layer4Intervention type={type} data={data}/>}><CourseScholarships data={data.course_scholarships} navigate={navigate}/><CourseScholarshipAction courseId={data.id} title={data.display_title||data.canonical_title}/></CourseDetailPolish>;const scalars=Object.entries(data).filter(([,v])=>v==null||['string','number','boolean'].includes(typeof v)).slice(0,24);if(type==='provider'){
    // v2.15.225 (Platform Admin, 9 Oct 2026: "remove unnecessary text and fields … consolidated view"): pills and fact
    // cards (courses, scholarships, contacts, campuses, website) › provider values as cards with Change › rankings; related
    // insights in one closed fold. The raw identifier, evidence, registration, source and history lists are not shown.
    return <div className="m-drawer-body"><ProviderSummary data={data} navigate={navigate}/><ProviderFillAction providerId={data.id} name={data.display_name||data.canonical_name} website={data.website}/><ProviderScholarshipSearch providerId={data.id} onChanged={onChanged}/><ProviderScholarshipAction providerId={data.id} name={data.display_name||data.canonical_name}/>{data.id&&<ProviderEditor inline providerId={data.id} onChanged={onChanged} onError={onError}/>}{data.id&&<ProviderRankings providerId={data.id} navigate={navigate}/>}<ProviderMore data={data} type={type} navigate={navigate}/></div>}
  // v2.15.171 (mockup, 3 Oct 2026 23:30): the scholarship drawer is the record panel only — one row per fact with its source
  if(type==='scholarship'&&data.id)return <div className="m-drawer-body"><ScholarshipRecord id={data.id} onError={onError} onChanged={onChanged}/><Layer4Intervention type={type} data={data}/></div> // v2.15.243: no Study Australia comparison (Platform Admin, 11 Oct 2026: country-neutral)
  // v2.15.225: every other record uses the same look — status pills, then fact cards; lists sit in the closed "More" fold
  const hidden=k=>k==='id'||k==='stable_key'||k.endsWith('_id')||k.includes('hash')||k.endsWith('_status')||k==='status'
  const facts=scalars.filter(([k,v])=>!hidden(k)&&v!=null&&v!=='')
  const pills=scalars.filter(([k,v])=>(k.endsWith('_status')||k==='status')&&v)
  return <div className="m-drawer-body"><section className="ds-summary" data-generic-summary><PillRow>{pills.map(([k,v])=><StatusChip key={k} value={v} label={`${humanise(k).replace(/ status$/i,'')}: ${humanise(v)}`}/>)}</PillRow><FactCards>{facts.map(([k,v])=><FactCard key={k} id={k} label={humanise(k)} value={formatScalar(k,v)}/>)}</FactCards></section>{['campus','scholarship'].includes(type)&&<Layer4Intervention type={type} data={data}/>}<details className="ds-more"><summary>More detail</summary><div><ObjectSections data={data} exclude={['layer4','layer4_publication']} navigate={navigate}/></div></details></div>}

// v2.15.171 (mockup board 1, 3 Oct 2026 23:30): one card per scholarship — name, who it is for, nationalities, published
// or not, the clean value and the saving a year (an estimate when worked out from the registered CRICOS course cost),
// the closing date and the provider page. Filter by a student's nationality. v2.15.172: published scholarships only.
function CourseScholarships({data,navigate}){
 const items=Array.isArray(data?.items)?data.items:[]
 const[nat,setNat]=useState(''),[open,setOpen]=useState('')
 const codes=[...new Set(items.flatMap(x=>Array.isArray(x.nationalities)?x.nationalities:[]))].sort((a,b)=>{const x=NAT_NAME[a]||a,y=NAT_NAME[b]||b;return x<y?-1:x>y?1:0})
 const pub=x=>x.publication_status==='published'&&(x.lifecycle_status||'active')==='active'
 const natOk=x=>!nat||!(x.nationalities||[]).length||(x.nationalities||[]).includes(nat)
 const shown=items.filter(x=>natOk(x)&&pub(x)),nPub=items.filter(pub).length
 return <section className="m-detail-section cs-panel" data-course-scholarships><h3 title="Only scholarships whose page names this course, or all of the university's courses">Scholarships</h3>
  {items.length>0&&<div className="cs-controls">{codes.length>0&&<label><small>Student nationality</small><select value={nat} onChange={e=>setNat(e.target.value)} aria-label="Student nationality"><option value="">Any nationality</option>{codes.map(c=><option key={c} value={c}>{NAT_NAME[c]||c}</option>)}</select></label>}<span className="cs-count">{fmtNumber(nPub)} scholarship{nPub===1?'':'s'}</span></div>}
  {shown.length?<div className="cs-cards">{shown.map(x=>{const k=x.mapping_id||x.scholarship_id,c=x.calculation||{},est=c.fee_basis==='estimated_annual_from_registered_total',n=Array.isArray(x.nationalities)?x.nationalities:[],isOpen=open===k
   return <article className="cs-card" key={k} data-cs-card>
    <div className="cs-top"><div className="cs-main"><strong>{x.name}</strong><span className="sch-chips"><StatusChip tone={SCH_AUD_TONE[x.audience]||'neutral'} label={SCH_AUD[x.audience]||'Not stated'}/><StatusChip tone="neutral" label={natShort(n)} title={n.length?n.map(c=>NAT_NAME[c]||c).join(', '):'Any nationality'}/></span></div>
     <div className="cs-value"><b>{x.value_label||'Value not stated'}</b>{c.scholarship_saving_amount!=null&&<small data-cs-saving>Saves about {fmtMoney(Number(c.scholarship_saving_amount),c.currency_code||'AUD')} a year{est?' (estimate from the registered CRICOS course cost)':c.fee_year?` (${c.fee_year} fee)`:''}</small>}</div></div>
    <div className="cs-foot"><span>{x.application_close_date?`Applications close ${fmtDate(x.application_close_date)}`:'No closing date stated'}</span><span className="cs-actions"><button type="button" className="m-secondary compact" aria-expanded={isOpen} onClick={()=>setOpen(isOpen?'':k)}>{isOpen?'Less':'More'}</button>{x.source_url&&<a className="m-secondary compact" href={x.source_url} target="_blank" rel="noreferrer">Provider page <ExternalLink size={11}/></a>}{x.evidence_id&&<EvidenceButton id={x.evidence_id} navigate={navigate}/>}</span></div>
    {isOpen&&<div className="cs-more"><div><small>Who it is for</small><span>{SCH_AUD[x.audience]||'Not stated on the page'}{n.length?` from ${n.map(c=>NAT_NAME[c]||c).join(', ')}`:''}</span></div><div><small>Value</small><span>{x.value_label||'Value not stated'}{c.net_fee_amount!=null?` · fee after the scholarship about ${fmtMoney(Number(c.net_fee_amount),c.currency_code||'AUD')} a year`:''}</span></div><div><small>Linked because</small><span>{humanise(x.mapping_basis||'governed mapping')}</span></div></div>}
   </article>})}</div>:<EmptyInline text={nPub?`No scholarship for this course names ${NAT_NAME[nat]||nat} or is open to any nationality.`:'No published scholarship is linked to this course yet.'}/>}
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

// v2.15.301 (Platform Admin, 20 Oct 2026, "Retire the page"): Data model (Attributes) retired; the attribute data stays.

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
