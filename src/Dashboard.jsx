// Dashboard (v2.15.125): "Today" — what is waiting for a person first, then the few counts that matter, platform health in
// one strip, the layers as small tiles, and recent activity. v2.15.252 (Platform Admin, 12 Oct 2026): Layer 3 tile removed (Layer 3 retired). Screen review 1 Oct 2026 (Dashboard: waiting list,
// one health strip, fewer tiles, plain headings, security note linked to Platform health).
// Reads: public.admin_waiting_read() (migration 20261001130000_cf247_dashboard_waiting), admin_read 'dashboard',
// 'layer_status_summary' and 'platform_health'.
// v2.15.266: reads only admin_waiting_read and admin_read 'dashboard' (Waiting for you and the four tiles).
// v2.15.301 (Platform Admin, 20 Oct 2026, "Keep, Waiting = Inbox"): Waiting for you is the Layer 4 Inbox: each kind with its count and the
// oldest, one click to the Inbox on that kind (public.admin_layer4_inbox 'summary', Curator and above). The few things that are not Inbox
// items (failed jobs, key dates, reference sites, scholarship links) stay below as "Also". The old onboarding and review rows are Inbox kinds.
import React,{useEffect,useState}from'react'
import{ArrowRight,Award,Building2,CalendarClock,CheckCircle2,ClipboardCheck,Globe,GraduationCap,Inbox,Link2,PauseCircle,RefreshCw,Sparkles,Workflow,XCircle}from'lucide-react'
import{adminRead,supabase}from'./lib/supabase'
import{Button,Loading,Metric,SectionTitle,fmtDate,fmtNumber}from'./ui-kit'
import{plainError}from'./lib/errors'

// v2.15.284 (Platform Admin, 16 Oct 2026: "Dashboard should display Icons"): an icon for each queue in Waiting for you
const INBOX_ONLY=new Set(['review','onboarding_admit','onboarding_stopped'])
const QUEUE_ICON={review:ClipboardCheck,onboarding_admit:Building2,onboarding_stopped:PauseCircle,scholarship_links:Link2,scholarships_ready:Award,reference:Globe,dates:CalendarClock,failed_jobs:XCircle,failed_automations:Workflow}
const errText=e=>plainError(e) // v2.15.341 (UI audit Phase 0): one plain reading, no internals
const ago=v=>{if(!v)return'';const d=Math.floor((Date.now()-new Date(v).getTime())/86400000);return d<=0?'today':d===1?'1 day':`${fmtNumber(d)} days`}

export default function Dashboard({onError}){
  const[waiting,setWaiting]=useState(null),[data,setData]=useState(null),[inbox,setInbox]=useState(null),[busy,setBusy]=useState(false)
  const load=async()=>{setBusy(true);try{
    const[w,d,i]=await Promise.all([supabase.rpc('admin_waiting_read').then(r=>{if(r.error)throw r.error;return r.data}).catch(e=>{onError?.(errText(e));return{rows:[]}}),
      adminRead('dashboard').catch(()=>null),
      supabase.rpc('admin_layer4_inbox',{p_action:'summary',p_args:{}}).then(r=>r.error?null:r.data,()=>null)])
    setWaiting(w||{rows:[]});setData(d);setInbox(i)}finally{setBusy(false)}}
  useEffect(()=>{load()},[])
  if(!waiting)return <section className="m-panel"><Loading label="Loading today…"/></section>
  const rows=(waiting.rows||[]).filter(r=>!INBOX_ONLY.has(r.key)),open=rows.filter(r=>Number(r.count)>0),clear=rows.filter(r=>!Number(r.count))
  const kinds=inbox?.kinds||{},bk=inbox?.by_kind||{}
  const inboxRows=Object.entries(bk).filter(([,v])=>Number(v?.n)>0).sort((a,b)=>(kinds[a[0]]?.order||99)-(kinds[b[0]]?.order||99))
  const go=href=>{if(href)location.hash=href.replace(/^#/,'')}
  // One count for what waits for a person everywhere on the page: the Inbox total (falls back to the summary's open reviews).
  const reviewCount=Number(inbox?.total??data?.open_reviews??0)
  return <div className="m-page-stack db-home">
    <section className="m-panel" data-waiting>
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
        <span className="db-label">{r.label}{r.oldest&&<small>{r.key==='dates'?`next on ${fmtDate(r.oldest)}`:`oldest waiting ${ago(r.oldest)}`}</small>}</span>
        <Button compact onClick={()=>go(r.href)} aria-label={`Open ${r.label}`}>Open<ArrowRight size={13}/></Button></li>})}</ul></>}
      {clear.length>0&&<p className="db-allclear">Clear: {clear.map(r=>r.label.toLowerCase()).join(' · ')}</p>}
    </section>
    <div className="cf-metric-grid db-tiles">
      <button type="button" className="db-tile" onClick={()=>go('#providers')}><Metric label="Providers" value={fmtNumber(data?.providers||0)} detail="Every status and country" icon={Building2}/></button>
      <button type="button" className="db-tile" onClick={()=>go('#courses')}><Metric label="Courses" value={fmtNumber(data?.courses||0)} detail="Every status and country" icon={GraduationCap}/></button>
      <button type="button" className="db-tile" onClick={()=>go('#scholarships')}><Metric label="Scholarships" value={fmtNumber(data?.scholarships_published??(data?.scholarships||0))} detail={data?.scholarships_active!=null?`published · ${fmtNumber(data.scholarships_active)} active · ${fmtNumber(Math.max(0,(data.scholarships||0)-(data.scholarships_active||0)))} retired`:'Every status'} icon={Sparkles}/></button>
      <button type="button" className="db-tile" onClick={()=>go('#layer-4-review')}><Metric label="Inbox" value={fmtNumber(reviewCount)} detail="Waiting for a person" icon={ClipboardCheck} tone={reviewCount?'warning':'success'}/></button>
    </div>
    {/* v2.15.266 (Platform Admin, 13 Oct 2026): the health strip, Layers and Recent activity are retired; how the platform is progressing,
        what is running and what to tweak are on Coverage & completeness › Progress, and health checks on Platform health. */}
    <p className="sd-desc db-progress-link" data-dashboard-progress>How the platform is progressing: <a className="cf-link" href="#coverage?tab=progress">Coverage &amp; completeness › Progress</a>. What is running: <a className="cf-link" href="#layer-2-discovery">Layer 2/3 › Operations</a>.</p>
  </div>
}
