// Dashboard (v2.15.125): "Today" — what is waiting for a person first, then the few counts that matter, platform health in
// one strip, the layers as small tiles, and recent activity. v2.15.252 (Platform Admin, 12 Oct 2026): Layer 3 tile removed (Layer 3 retired). Screen review 1 Oct 2026 (Dashboard: waiting list,
// one health strip, fewer tiles, plain headings, security note linked to Platform health).
// Reads: public.admin_waiting_read() (migration 20261001130000_cf247_dashboard_waiting), admin_read 'dashboard',
// 'layer_status_summary' and 'platform_health'.
// v2.15.266: reads only admin_waiting_read and admin_read 'dashboard' (Waiting for you and the four tiles).
// v2.15.301 (Platform Admin, 20 Oct 2026, "Keep, Waiting = Inbox"): Waiting for you is the Layer 4 Inbox: each kind with its count and the
// oldest, one click to the Inbox on that kind (public.admin_layer4_inbox 'summary', Curator and above). The few things that are not Inbox
// items (failed jobs, key dates, reference sites, scholarship links) stay below as "Also". The old onboarding and review rows are Inbox kinds.
// v2.16.35 (Platform Admin 18 Nov 2026 10:31 and 10:33, role-centric Dashboard; mockup on the design canvas "StudySearch role-centric dashboard
// mockup"): one Dashboard, drawn for the signed-in role. Every role gets its role line with a link to its guide (Guides › Role guides) and
// Continue where you left off (src/lib/recent-activity.js, this browser only). A Viewer or Counsellor (rank 1-2) starts with Search the catalogue
// and sees no pipeline or Inbox counts; a Curator (3) gets Waiting for you without the operator rows (failed jobs and automations); operators (4-5)
// keep the operator Dashboard; a Platform Admin (6) also gets Waiting for your approval (editions ready to publish, Layer 1 drafts, email delivery).
import React,{useEffect,useState}from'react'
import{ArrowRight,BookOpen,Building2,ClipboardCheck,Clock3,GraduationCap,Search,ShieldCheck,Sparkles,X,XCircle}from'lucide-react'
import{Button,Loading,SectionTitle,fmtDateTime,rememberedStateKey}from'./ui-kit'
import{guideForRank}from'./guide/roleGuides'
// CF-247 S1-UX s824 (Platform Admin 20 Nov 2026 10:31, 10:46 and 11:24): the five KPI cards with icons and three country completeness bars (Curator and
// above) and Active failures (operators and above), from the stored ops pulse (admin_read 'platform_health', a stored row); a Viewer or Counsellor
// (rank 1-2) now makes no pipeline or telemetry read at all (OperatorToday and its admin_read 'dashboard' are not mounted for them)
import{PulseStamp,PulseStrip}from'./OpsPulse'
import{readPlatformHealth}from'./PlatformHealth'
import{pulseOf,withBudgetCap}from'./lib/ops-pulse.js'
import{dashboardFailures}from'./health-exec.js'
import{clearRecent,readRecent,resumeRecent}from'./lib/recent-activity'
// CF-247 s836 (Platform Admin 20 Nov 2026 14:40, S1-UI-Parity; mockup s820-s827): the Dashboard is the role line, the five KPI cards and Active
// failures, then Continue where you left off (the 3 most recent). Waiting for your approval, Waiting for you, Also, the four summary cards and the
// Layer 2/3 › Operations link are removed: Layer 4 Review, Layer 1 Register and Platform Health are where those are worked.

// CF-247 S1-UX s824 and s836 (Platform Admin 20 Nov 2026 10:31 and 14:40): the five KPI cards (Curator and above) and Active failures (operators and
// above). The cards come from the stored ops pulse (admin_read 'platform_health'); the spend card takes the daily cap from the budgets check in the
// same answer when the pulse has none. Active failures lists genuine failures and warnings only (src/health-exec.js dashboardFailures), not the
// coverage and progress watchdogs.
function DashboardPulse({rank}){const[h,setH]=useState(undefined)
  useEffect(()=>{let live=true;readPlatformHealth().then(x=>{if(live)setH(x||null)});return()=>{live=false}},[])
  if(h===undefined)return <section className="m-panel" data-db-pulse="loading"><Loading label="Reading the stored figures…"/></section>
  const p=withBudgetCap(pulseOf(h),h)
  if(!p)return null
  return <><section className="m-panel" data-db-pulse><PulseStrip pulse={p}/><PulseStamp pulse={p}/></section>
    {rank>=4&&<DashboardFailures health={h}/>}</>}
const FAIL_SHOWN=6
function DashboardFailures({health}){const rows=dashboardFailures(health)
  return <section className="m-panel" data-db-failures={rows.length}><SectionTitle icon={XCircle} title="Active failures" subtitle={rows.length?'Failures and warnings that need a person, worst first, with the screen to fix each.':'Nothing is failing.'}/>
    {rows.length?<div className="op-fails"><ul>{rows.slice(0,FAIL_SHOWN).map(r=>{const tone=r.tone==='critical'?'crit':'warn';return <li key={r.key} className={`tone-${tone}`} data-db-failure={r.kind}>
      <span className={`op-badge sm tone-${tone}`}><XCircle size={15} aria-hidden="true"/></span>
      <span className="op-fail-label"><b>{r.title}</b>{r.why&&<small>{r.why}</small>}</span>
      <a className="op-btn ghost sm" href={r.href}>Open<ArrowRight size={13}/></a></li>})}</ul></div>
      :<p className="op-none" data-db-failures-none>No failure or warning needs a person.</p>}
    {rows.length>FAIL_SHOWN&&<p className="op-none"><a href="#platform-health" data-db-failures-more>{rows.length-FAIL_SHOWN} more on Platform Health</a></p>}
  </section>}

const RECENT_SHOWN=3
const ROLE_ICON=r=>r<=2?Search:r===3?ClipboardCheck:ShieldCheck
function RoleLine({rank,navigate}){const g=guideForRank(rank),RoleIcon=ROLE_ICON(Number(g.rank)||Number(rank)||1)
  return <section className="m-panel db-role" data-db-role={g.id}><div><span className="db-role-pill"><RoleIcon size={14} aria-hidden="true"/>{g.role} · rank {g.rank}</span><p className="sd-desc">{g.purpose}</p></div>
    <Button compact onClick={()=>navigate?.('guide',{tab:'role-guides'})} data-db-role-guide><BookOpen size={14}/>Your role guide</Button></section>}

// v2.16.35: Search the catalogue (Viewer and Counsellor): the text goes into the Courses list's remembered search, then Courses opens
function SearchStart({actorId,navigate}){const[q,setQ]=useState('')
  const go=e=>{e.preventDefault();const text=q.trim()
    try{const k=rememberedStateKey('course',actorId||'anonymous'),saved=JSON.parse(localStorage.getItem(k)||'{}');localStorage.setItem(k,JSON.stringify({...(saved&&typeof saved==='object'?saved:{}),query:text,filters:{},filterLabels:{}}))}catch{}
    navigate?.('courses')}
  return <section className="m-panel db-search" data-db-search>
    <SectionTitle icon={Search} title="Search the catalogue" subtitle="Courses by title, field, city or provider. Every value shows where it came from."/>
    <form className="db-search-row" onSubmit={go}><label className="db-sr" htmlFor="db-search-q">Search courses</label>
      <input id="db-search-q" value={q} onChange={e=>setQ(e.target.value)} placeholder="For example: Master of Nursing Melbourne" data-db-search-q/>
      <Button variant="primary" type="submit" data-db-search-go><Search size={14}/>Search courses</Button></form>
    <div className="db-starts">{[['courses','Courses','Fees, intakes, English and study load',GraduationCap],['providers','Providers','Universities, TAFEs and colleges',Building2],['scholarships','Scholarships','Open to international students',Sparkles],['entry','Entry requirements','By country of prior education',ClipboardCheck]].map(([k,l,d,Icon])=>
      <button type="button" key={k} className="db-start" onClick={()=>navigate?.(k)} data-db-start={k}><Icon size={16}/><span><strong>{l}</strong><small>{d}</small></span><ArrowRight size={13}/></button>)}</div>
  </section>}

// v2.16.35: Continue where you left off: the person's own last searches, review queues and pages, on this browser
const KIND_LABEL={search:'Search',queue:'Review queue',page:'Page'}
function ContinueWhereLeft({actorId}){const[all,setItems]=useState(()=>readRecent(actorId)),items=(all||[]).slice(0,RECENT_SHOWN)
  useEffect(()=>setItems(readRecent(actorId)),[actorId])
  return <section className="m-panel db-recent" data-db-recent>
    <SectionTitle icon={Clock3} title="Continue where you left off" subtitle="Your 3 most recent searches, review queues and pages, kept on this browser only." action={items.length?<Button compact onClick={()=>{clearRecent(actorId);setItems([])}} data-db-recent-clear><X size={13}/>Clear</Button>:null}/>
    {items.length?<ul className="db-recent-list">{items.map(x=><li key={x.id} data-db-recent-item={x.kind}>
      <span className="db-recent-kind">{KIND_LABEL[x.kind]||'Page'}</span>
      <span className="db-recent-what"><strong>{x.label}</strong>{x.detail&&<small>{x.detail}</small>}</span>
      <small className="db-recent-when">{x.at?fmtDateTime(x.at):''}</small>
      <Button compact onClick={()=>resumeRecent(actorId,x)} aria-label={`Resume ${x.label}${x.detail?` ${x.detail}`:''}`} data-db-recent-resume>Resume<ArrowRight size={13}/></Button></li>)}</ul>
      :<p className="db-clear" data-db-recent-empty>Nothing yet. Searches, review queues and pages you open will be listed here.</p>}
  </section>}

export default function Dashboard({onError,rank=1,actorId='',navigate}){
  const r=Number(rank)||1
  return <div className="m-page-stack db-home" data-db-rank={r}>
    <RoleLine rank={r} navigate={navigate}/>
    {r<=2&&<SearchStart actorId={actorId} navigate={navigate}/>}
    {r>=3&&<DashboardPulse rank={r}/>}
    <ContinueWhereLeft actorId={actorId}/>
  </div>
}
