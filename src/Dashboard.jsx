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
import{ArrowRight,Award,BookOpen,Building2,CalendarClock,CheckCircle2,ClipboardCheck,Clock3,Globe,GraduationCap,Inbox,Link2,Mail,PauseCircle,RefreshCw,Search,ShieldCheck,Sparkles,Workflow,X,XCircle}from'lucide-react'
import{adminRead,supabase}from'./lib/supabase'
import{Button,Loading,Metric,SectionTitle,fmtDate,fmtDateTime,fmtNumber,rememberedStateKey}from'./ui-kit'
import{guideForRank}from'./guide/roleGuides'
// CF-247 S1-UX s824 (Platform Admin 20 Nov 2026 10:31, 10:46 and 11:24): the five KPI cards with icons and three country completeness bars (Curator and
// above) and Active failures (operators and above), from the stored ops pulse (admin_read 'platform_health', a stored row); a Viewer or Counsellor
// (rank 1-2) now makes no pipeline or telemetry read at all (OperatorToday and its admin_read 'dashboard' are not mounted for them)
import{ActiveFailures,PulseStamp,PulseStrip}from'./OpsPulse'
import{readPlatformHealth}from'./PlatformHealth'
import{pulseOf}from'./lib/ops-pulse.js'
import{clearRecent,readRecent,resumeRecent}from'./lib/recent-activity'
import{plainError}from'./lib/errors'
import SnapshotStamp from'./SnapshotStamp' // CF-247 W35: Scholarships ready to publish is counted from a cached snapshot

// v2.15.284 (Platform Admin, 16 Oct 2026: "Dashboard should display Icons"): an icon for each queue in Waiting for you
const INBOX_ONLY=new Set(['review','onboarding_admit','onboarding_stopped'])
// v2.16.35: rows only operators act on (rank 4 and above); a Curator does not see them
const OPERATOR_ONLY=new Set(['failed_jobs','failed_automations'])
const QUEUE_ICON={review:ClipboardCheck,onboarding_admit:Building2,onboarding_stopped:PauseCircle,scholarship_links:Link2,scholarships_ready:Award,reference:Globe,dates:CalendarClock,failed_jobs:XCircle,failed_automations:Workflow}
const errText=e=>plainError(e) // v2.15.341 (UI audit Phase 0): one plain reading, no internals
const ago=v=>{if(!v)return'';const d=Math.floor((Date.now()-new Date(v).getTime())/86400000);return d<=0?'today':d===1?'1 day':`${fmtNumber(d)} days`}

function OperatorToday({onError,rank=6}){
  const[waiting,setWaiting]=useState(null),[data,setData]=useState(null),[inbox,setInbox]=useState(null),[busy,setBusy]=useState(false)
  const load=async()=>{setBusy(true);try{
    const[w,d,i]=await Promise.all([(rank<3?Promise.resolve({rows:[]}):supabase.rpc('admin_waiting_read')).then(r=>{if(r.error)throw r.error;return r.data}).catch(e=>{onError?.(errText(e));return{rows:[]}}),
      adminRead('dashboard').catch(()=>null),
      (rank>=3?supabase.rpc('admin_layer4_inbox',{p_action:'summary',p_args:{}}).then(r=>r.error?null:r.data,()=>null):Promise.resolve(null))])
    setWaiting(w||{rows:[]});setData(d);setInbox(i)}finally{setBusy(false)}}
  useEffect(()=>{load()},[])
  if(!waiting)return <section className="m-panel"><Loading label="Loading today…"/></section>
  const rows=(waiting.rows||[]).filter(r=>!INBOX_ONLY.has(r.key)&&(rank>=4||!OPERATOR_ONLY.has(r.key))),open=rows.filter(r=>Number(r.count)>0),clear=rows.filter(r=>!Number(r.count))
  const kinds=inbox?.kinds||{},bk=inbox?.by_kind||{}
  const inboxRows=Object.entries(bk).filter(([,v])=>Number(v?.n)>0).sort((a,b)=>(kinds[a[0]]?.order||99)-(kinds[b[0]]?.order||99))
  const go=href=>{if(href)location.hash=href.replace(/^#/,'')}
  // One count for what waits for a person everywhere on the page: the Inbox total (falls back to the summary's open reviews).
  const reviewCount=Number(inbox?.total??data?.open_reviews??0)
  return <div className="m-page-stack db-today">
    {rank>=3&&<section className="m-panel" data-waiting>
      <SectionTitle icon={Inbox} title="Waiting for you" subtitle={inbox?(inboxRows.length?`${fmtNumber(inbox.total)} items at ${fmtNumber(inbox.universities)} universities need a person; ${fmtNumber(inbox.late)} are older than ${inbox.target_days} days. Oldest first is a good rule.`:'Nothing in the Inbox needs a person right now.'):'The Inbox opens for Curators and above.'} action={<Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Updating…':'Refresh'}</Button>}/>
      {/* v2.15.343 (UI audit Phase 3): the per-kind rows live on Layer 4 Review › By kind (the one source); the Dashboard states the total and opens it */}
      {inbox&&(inboxRows.length?<ul className="db-waiting" data-waiting-inbox><li data-queue="inbox" data-inbox-total>
        <span className="db-queue-icon" aria-hidden="true"><Inbox size={16}/></span>
        <strong className="db-count">{fmtNumber(Number(inbox.total||0))}</strong>
        <span className="db-label">Inbox items across {fmtNumber(inboxRows.length)} kind{inboxRows.length===1?'':'s'}<small>{Number(inbox.late)?`${fmtNumber(inbox.late)} older than ${inbox.target_days} days · `:''}by kind and oldest first on Layer 4 Review</small></span>
        <Button compact onClick={()=>go('#layer-4-review?view=kind')} aria-label="Open the Inbox by kind">Open<ArrowRight size={13}/></Button></li></ul>:<p className="db-clear"><CheckCircle2 size={16}/>All clear.</p>)}
      {open.length>0&&<><h4 className="db-also">Also</h4><ul className="db-waiting" data-waiting-also>{open.map(r=>{const Icon=QUEUE_ICON[r.key]||Inbox;return <li key={r.key} data-queue={r.key}>
        <span className="db-queue-icon" aria-hidden="true"><Icon size={16}/></span>
        <strong className="db-count">{fmtNumber(Number(r.count))}</strong>
        <span className="db-label">{r.label}{r.oldest&&<small>{r.key==='dates'?`next on ${fmtDate(r.oldest)}`:`oldest waiting ${ago(r.oldest)}`}</small>}<SnapshotStamp meta={r.snapshot} label="Counted" what={r.key}/></span>
        <Button compact onClick={()=>go(r.href)} aria-label={`Open ${r.label}`}>Open<ArrowRight size={13}/></Button></li>})}</ul></>}
      {clear.length>0&&<p className="db-allclear">Clear: {clear.map(r=>r.label.toLowerCase()).join(' · ')}</p>}
    </section>}
    <div className="cf-metric-grid db-tiles">
      <button type="button" className="db-tile" onClick={()=>go('#providers')}><Metric label="Providers" value={fmtNumber(data?.providers||0)} detail="Every status and country" icon={Building2}/></button>
      <button type="button" className="db-tile" onClick={()=>go('#courses')}><Metric label="Courses" value={fmtNumber(data?.courses||0)} detail="Every status and country" icon={GraduationCap}/></button>
      <button type="button" className="db-tile" onClick={()=>go('#scholarships')}><Metric label="Scholarships" value={fmtNumber(data?.scholarships_published??(data?.scholarships||0))} detail={data?.scholarships_active!=null?`published · ${fmtNumber(data.scholarships_active)} active · ${fmtNumber(Math.max(0,(data.scholarships||0)-(data.scholarships_active||0)))} retired`:'Every status'} icon={Sparkles}/></button>
      {rank>=3&&<button type="button" className="db-tile" onClick={()=>go('#layer-4-review')}><Metric label="Inbox" value={fmtNumber(reviewCount)} detail="Waiting for a person" icon={ClipboardCheck} tone={reviewCount?'warning':'success'}/></button>}
    </div>
    {/* v2.15.266 (Platform Admin, 13 Oct 2026): the health strip, Layers and Recent activity are retired; how the platform is progressing,
        what is running and what to tweak are on Coverage & completeness › Progress, and health checks on Platform health. */}
    {rank>=3&&<p className="sd-desc db-progress-link" data-dashboard-progress>How the platform is progressing and what is running: <a className="cf-link" href="#layer-2-discovery">Layer 2/3 › Operations</a> (SS-020: Progress moved there).</p>}
  </div>
}

// v2.16.35: the role line at the top: who you are signed in as, what the role is for, and its guide
function DashboardPulse({rank}){const[p,setP]=useState(undefined)
  useEffect(()=>{let live=true;readPlatformHealth().then(h=>{if(live)setP(pulseOf(h))});return()=>{live=false}},[])
  if(p===undefined)return <section className="m-panel" data-db-pulse="loading"><Loading label="Reading the stored figures…"/></section>
  if(!p)return null
  return <><section className="m-panel" data-db-pulse><PulseStrip pulse={p}/><PulseStamp pulse={p}/></section>
    {rank>=4&&<section className="m-panel" data-db-failures><SectionTitle icon={XCircle} title="Active failures" subtitle="Every pipeline stage check that is slowed, due or stopped, with the screen to fix it."/><ActiveFailures pulse={p}/></section>}</>}
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
function ContinueWhereLeft({actorId}){const[items,setItems]=useState(()=>readRecent(actorId))
  useEffect(()=>setItems(readRecent(actorId)),[actorId])
  return <section className="m-panel db-recent" data-db-recent>
    <SectionTitle icon={Clock3} title="Continue where you left off" subtitle="Your last searches, review queues and pages, kept on this browser only." action={items.length?<Button compact onClick={()=>{clearRecent(actorId);setItems([])}} data-db-recent-clear><X size={13}/>Clear</Button>:null}/>
    {items.length?<ul className="db-recent-list">{items.map(x=><li key={x.id} data-db-recent-item={x.kind}>
      <span className="db-recent-kind">{KIND_LABEL[x.kind]||'Page'}</span>
      <span className="db-recent-what"><strong>{x.label}</strong>{x.detail&&<small>{x.detail}</small>}</span>
      <small className="db-recent-when">{x.at?fmtDateTime(x.at):''}</small>
      <Button compact onClick={()=>resumeRecent(actorId,x)} aria-label={`Resume ${x.label}${x.detail?` ${x.detail}`:''}`} data-db-recent-resume>Resume<ArrowRight size={13}/></Button></li>)}</ul>
      :<p className="db-clear" data-db-recent-empty>Nothing yet. Searches, review queues and pages you open will be listed here.</p>}
  </section>}

// v2.16.35: Waiting for your approval (Platform Admin): what only a Platform Admin can do, read from the screens that do it
function Approvals({navigate}){const[rows,setRows]=useState(null)
  useEffect(()=>{let live=true
    Promise.all([supabase.rpc('admin_destination_overview').then(r=>r.error?null:r.data,()=>null),
      supabase.rpc('admin_layer1_induction_read',{p_id:null}).then(r=>r.error?null:r.data,()=>null),
      supabase.rpc('admin_email_delivery_read',{}).then(r=>r.error?null:r.data,()=>null)]).then(([d,l,e])=>{if(!live)return
      const out=[]
      for(const x of d?.editions_list||[])if(['draft','in_review'].includes(x.status)&&x.terms_status==='approved'&&Number(x.rows_approved)>0)
        out.push({key:`ed:${x.edition_id}`,count:x.rows_approved,label:`Destination edition ready to publish: ${x.country_code} ${x.edition_label}`,detail:`${fmtNumber(x.rows_approved)} of ${fmtNumber(x.rows)} rows approved`,go:()=>navigate?.('destination',{tab:'overview'}),act:'Publish',icon:Globe})
      const drafts=(l?.drafts||[]).filter(x=>!['activated','cancelled'].includes(x.status))
      if(drafts.length)out.push({key:'l1',count:drafts.length,label:'Layer 1 drafts waiting for activation',detail:'Continue a draft on Layer 1 Register › + Add source',go:()=>navigate?.('layer1'),act:'Review',icon:Workflow})
      const dv=e?.delivery;if(dv&&!(dv.email_provider==='resend'&&dv.key_saved&&dv.from_email))out.push({key:'mail',count:null,label:'Email delivery: Supabase Built-in',detail:dv.key_saved?'Resend key saved; choose Resend API to use it':'Resend not set up: no key and sender saved',go:()=>navigate?.('users',{tab:'templates'}),act:'Open',icon:Mail})
      setRows(out)})
    return()=>{live=false}},[])
  if(!rows)return <section className="m-panel" data-db-approvals><Loading label="Checking approvals…"/></section>
  return <section className="m-panel" data-db-approvals>
    <SectionTitle icon={ShieldCheck} title="Waiting for your approval" subtitle={rows.length?'Only a Platform Admin can do these. Each needs a reason and is kept in the control log.':'Nothing waits for a Platform Admin right now.'}/>
    {rows.length>0&&<ul className="db-waiting">{rows.map(r=>{const Icon=r.icon;return <li key={r.key} data-db-approval={r.key}>
      <span className="db-queue-icon" aria-hidden="true"><Icon size={16}/></span><strong className="db-count">{r.count==null?'':fmtNumber(r.count)}</strong>
      <span className="db-label">{r.label}<small>{r.detail}</small></span><Button compact onClick={r.go}>{r.act}<ArrowRight size={13}/></Button></li>})}</ul>}
  </section>}

export default function Dashboard({onError,rank=1,actorId='',navigate}){
  const r=Number(rank)||1
  return <div className="m-page-stack db-home" data-db-rank={r}>
    <RoleLine rank={r} navigate={navigate}/>
    {r<=2&&<SearchStart actorId={actorId} navigate={navigate}/>}
    <ContinueWhereLeft actorId={actorId}/>
    {r>=3&&<DashboardPulse rank={r}/>}
    {r>=6&&<Approvals navigate={navigate}/>}
    {r>=3&&<OperatorToday onError={onError} rank={r}/>}
  </div>
}
