// Dashboard (v2.15.125): "Today" — what is waiting for a person first, then the few counts that matter, platform health in
// one strip, the layers as small tiles, and recent activity. v2.15.252 (Platform Admin, 12 Oct 2026): Layer 3 tile removed (Layer 3 retired). Screen review 1 Oct 2026 (Dashboard: waiting list,
// one health strip, fewer tiles, plain headings, security note linked to Platform health).
// Reads: public.admin_waiting_read() (migration 20261001130000_cf247_dashboard_waiting), admin_read 'dashboard',
// 'layer_status_summary' and 'platform_health'.
// v2.15.266: reads only admin_waiting_read and admin_read 'dashboard' (Waiting for you and the four tiles).
import React,{useEffect,useState}from'react'
import{ArrowRight,Award,Building2,CalendarClock,CheckCircle2,ClipboardCheck,Globe,GraduationCap,Inbox,Link2,PauseCircle,RefreshCw,Sparkles,Workflow,XCircle}from'lucide-react'
import{adminRead,supabase}from'./lib/supabase'
import{Button,Loading,Metric,SectionTitle,fmtDate,fmtNumber}from'./ui-kit'

// v2.15.284 (Platform Admin, 16 Oct 2026: "Dashboard should display Icons"): an icon for each queue in Waiting for you
const QUEUE_ICON={review:ClipboardCheck,onboarding_admit:Building2,onboarding_stopped:PauseCircle,scholarship_links:Link2,scholarships_ready:Award,reference:Globe,dates:CalendarClock,failed_jobs:XCircle,failed_automations:Workflow}
const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const ago=v=>{if(!v)return'';const d=Math.floor((Date.now()-new Date(v).getTime())/86400000);return d<=0?'today':d===1?'1 day':`${fmtNumber(d)} days`}

export default function Dashboard({onError}){
  const[waiting,setWaiting]=useState(null),[data,setData]=useState(null),[busy,setBusy]=useState(false)
  const load=async()=>{setBusy(true);try{
    const[w,d]=await Promise.all([supabase.rpc('admin_waiting_read').then(r=>{if(r.error)throw r.error;return r.data}).catch(e=>{onError?.(errText(e));return{rows:[]}}),
      adminRead('dashboard').catch(()=>null)])
    setWaiting(w||{rows:[]});setData(d)}finally{setBusy(false)}}
  useEffect(()=>{load()},[])
  if(!waiting)return <section className="m-panel"><Loading label="Loading today…"/></section>
  const rows=waiting.rows||[],open=rows.filter(r=>Number(r.count)>0),clear=rows.filter(r=>!Number(r.count))
  const go=href=>{if(href)location.hash=href.replace(/^#/,'')}
  // One count for open reviews everywhere on the page (the waiting list is live; the summary can be two minutes old).
  const reviewCount=Number(rows.find(r=>r.key==='review')?.count??data?.open_reviews??0)
  return <div className="m-page-stack db-home">
    <section className="m-panel" data-waiting>
      <SectionTitle icon={Inbox} title="Waiting for you" subtitle={open.length?`${open.length} ${open.length===1?'queue needs':'queues need'} a person. Oldest first is a good rule.`:'Nothing is waiting for a person right now.'} action={<Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Updating…':'Refresh'}</Button>}/>
      {open.length?<ul className="db-waiting">{open.map(r=>{const Icon=QUEUE_ICON[r.key]||Inbox;return <li key={r.key} data-queue={r.key}>
        <span className="db-queue-icon" aria-hidden="true"><Icon size={16}/></span>
        <strong className="db-count">{fmtNumber(Number(r.count))}</strong>
        <span className="db-label">{r.label}{r.oldest&&<small>{r.key==='dates'?`next on ${fmtDate(r.oldest)}`:`oldest waiting ${ago(r.oldest)}`}</small>}</span>
        <Button compact onClick={()=>go(r.href)} aria-label={`Open ${r.label}`}>Open<ArrowRight size={13}/></Button></li>})}</ul>:<p className="db-clear"><CheckCircle2 size={16}/>All clear.</p>}
      {clear.length>0&&<p className="db-allclear">Clear: {clear.map(r=>r.label.toLowerCase()).join(' · ')}</p>}
    </section>
    <div className="cf-metric-grid db-tiles">
      <button type="button" className="db-tile" onClick={()=>go('#providers')}><Metric label="Providers" value={fmtNumber(data?.providers||0)} detail="Every status and country" icon={Building2}/></button>
      <button type="button" className="db-tile" onClick={()=>go('#courses')}><Metric label="Courses" value={fmtNumber(data?.courses||0)} detail="Every status and country" icon={GraduationCap}/></button>
      <button type="button" className="db-tile" onClick={()=>go('#scholarships')}><Metric label="Scholarships" value={fmtNumber(data?.scholarships||0)} detail="Every status" icon={Sparkles}/></button>
      <button type="button" className="db-tile" onClick={()=>go('#layer-4-review')}><Metric label="Open reviews" value={fmtNumber(reviewCount)} detail="Waiting for a person" icon={ClipboardCheck} tone={reviewCount?'warning':'success'}/></button>
    </div>
    {/* v2.15.266 (Platform Admin, 13 Oct 2026): the health strip, Layers and Recent activity are retired; how the platform is progressing,
        what is running and what to tweak are on Coverage & completeness › Progress, and health checks on Platform health. */}
    <p className="sd-desc db-progress-link" data-dashboard-progress>How the platform is progressing, what is running and where to tweak it: <a className="cf-link" href="#coverage?tab=progress">Coverage &amp; completeness › Progress</a>.</p>
  </div>
}
