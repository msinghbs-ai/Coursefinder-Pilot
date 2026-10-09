// Dashboard (v2.15.125): "Today" — what is waiting for a person first, then the few counts that matter, platform health in
// one strip, the four layers as small tiles, and recent activity. Screen review 1 Oct 2026 (Dashboard: waiting list,
// one health strip, fewer tiles, plain headings, security note linked to Platform health).
// Reads: public.admin_waiting_read() (migration 20261001130000_cf247_dashboard_waiting), admin_read 'dashboard',
// 'layer_status_summary' and 'platform_health'.
import React,{useEffect,useState}from'react'
import{ArrowRight,Building2,CheckCircle2,ClipboardCheck,GraduationCap,History,Inbox,Layers3,RefreshCw,ShieldCheck,Sparkles}from'lucide-react'
import{adminRead,supabase}from'./lib/supabase'
import{Button,Loading,Metric,SectionTitle,StatusDot,fmtDate,fmtNumber}from'./ui-kit'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const ago=v=>{if(!v)return'';const d=Math.floor((Date.now()-new Date(v).getTime())/86400000);return d<=0?'today':d===1?'1 day':`${fmtNumber(d)} days`}
const TONE={healthy:'success',ok:'success',pass:'success',warning:'warning',attention:'warning',degraded:'warning',critical:'danger',failed:'danger',unknown:'neutral'}
const WORD={success:'Healthy',warning:'Needs attention',danger:'Problem',neutral:'Not known'}

export default function Dashboard({onError}){
  const[waiting,setWaiting]=useState(null),[data,setData]=useState(null),[layers,setLayers]=useState(null),[health,setHealth]=useState(null),[busy,setBusy]=useState(false)
  const load=async()=>{setBusy(true);try{
    const[w,d,l,h]=await Promise.all([supabase.rpc('admin_waiting_read').then(r=>{if(r.error)throw r.error;return r.data}).catch(e=>{onError?.(errText(e));return{rows:[]}}),
      adminRead('dashboard').catch(()=>null),adminRead('layer_status_summary').catch(()=>null),adminRead('platform_health').catch(()=>null)])
    setWaiting(w||{rows:[]});setData(d);setLayers(l);setHealth(h)}finally{setBusy(false)}}
  useEffect(()=>{load()},[])
  if(!waiting)return <section className="m-panel"><Loading label="Loading today…"/></section>
  const rows=waiting.rows||[],open=rows.filter(r=>Number(r.count)>0),clear=rows.filter(r=>!Number(r.count))
  const go=href=>{if(href)location.hash=href.replace(/^#/,'')}
  // One count for open reviews everywhere on the page (the waiting list is live; the summary can be two minutes old).
  const reviewCount=Number(rows.find(r=>r.key==='review')?.count??data?.open_reviews??layers?.layer4?.pending_reviews??0)
  const tone=TONE[String(health?.overall||'unknown').toLowerCase()]||'neutral'
  return <div className="m-page-stack db-home">
    <section className="m-panel" data-waiting>
      <SectionTitle icon={Inbox} title="Waiting for you" subtitle={open.length?`${open.length} ${open.length===1?'queue needs':'queues need'} a person. Oldest first is a good rule.`:'Nothing is waiting for a person right now.'} action={<Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Updating…':'Refresh'}</Button>}/>
      {open.length?<ul className="db-waiting">{open.map(r=><li key={r.key} data-queue={r.key}>
        <strong className="db-count">{fmtNumber(Number(r.count))}</strong>
        <span className="db-label">{r.label}{r.oldest&&<small>{r.key==='dates'?`next on ${fmtDate(r.oldest)}`:`oldest waiting ${ago(r.oldest)}`}</small>}</span>
        <Button compact onClick={()=>go(r.href)} aria-label={`Open ${r.label}`}>Open<ArrowRight size={13}/></Button></li>)}</ul>:<p className="db-clear"><CheckCircle2 size={16}/>All clear.</p>}
      {clear.length>0&&<p className="db-allclear">Clear: {clear.map(r=>r.label.toLowerCase()).join(' · ')}</p>}
    </section>
    <div className="cf-metric-grid db-tiles">
      <button type="button" className="db-tile" onClick={()=>go('#providers')}><Metric label="Providers" value={fmtNumber(data?.providers||0)} detail="Every status and country" icon={Building2}/></button>
      <button type="button" className="db-tile" onClick={()=>go('#courses')}><Metric label="Courses" value={fmtNumber(data?.courses||0)} detail="Every status and country" icon={GraduationCap}/></button>
      <button type="button" className="db-tile" onClick={()=>go('#scholarships')}><Metric label="Scholarships" value={fmtNumber(data?.scholarships||0)} detail="Every status" icon={Sparkles}/></button>
      <button type="button" className="db-tile" onClick={()=>go('#layer-4-review')}><Metric label="Open reviews" value={fmtNumber(reviewCount)} detail="Waiting for a person" icon={ClipboardCheck} tone={reviewCount?'warning':'success'}/></button>
    </div>
    {health&&<section className="m-panel db-health"><button type="button" className="db-health-row" onClick={()=>go('#platform-health')}>
      <StatusDot tone={tone} label={WORD[tone]}/><strong>Platform health: {WORD[tone]}</strong>
      <span>{fmtNumber(health.jobs?.running||0)} running · {fmtNumber(health.jobs?.failed_24h||0)} failed in 24 hours · {fmtNumber(health.data?.evidence_fetched_24h||0)} pages saved in 24 hours{health.security?.status?` · security ${String(health.security.status).replace(/_/g,' ')}`:''}</span>
      <ArrowRight size={14}/></button></section>}
    {layers&&<section className="m-panel"><SectionTitle icon={Layers3} title="Layers"/>
      <div className="db-layers">
        <button type="button" onClick={()=>go('#layer-1-register')}><small>Layer 1 · Registers</small><strong>{fmtNumber(layers.layer1?.active_sources||0)}</strong><span>sources running</span></button>
        <button type="button" onClick={()=>go('#layer-2-discovery')}><small>Layer 2 · Pages</small><strong>{fmtNumber(layers.layer2?.processed_24h||0)}</strong><span>pages read in 24 hours</span></button>
        <button type="button" onClick={()=>go('#layer-3-ai')}><small>Layer 3 · AI</small><strong>{fmtNumber(layers.layer3?.interpretations_24h||0)}</strong><span>pages checked by AI in 24 hours</span></button>
        <button type="button" onClick={()=>go('#layer-4-review')}><small>Layer 4 · Review</small><strong>{fmtNumber(reviewCount)}</strong><span>waiting for a decision</span></button>
      </div></section>}
    {(data?.recent_activity||[]).length>0&&<section className="m-panel"><SectionTitle icon={History} title="Recent activity"/>
      <ul className="ms-events">{data.recent_activity.slice(0,10).map((a,i)=><li key={i}><strong>{a.title||String(a.kind||'').replace(/_/g,' ')}</strong>{a.detail?` · ${a.detail}`:''}{a.status?` · ${String(a.status).replace(/_/g,' ')}`:''}<span className="l3v-code">{a.occurred_at?(ago(a.occurred_at)==='today'?'today':ago(a.occurred_at)+' ago'):''}</span></li>)}</ul></section>}
  </div>
}
