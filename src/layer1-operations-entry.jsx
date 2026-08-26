import React,{useEffect,useMemo,useState}from'react'
import{createRoot}from'react-dom/client'
import{Activity,BookOpen,CheckCircle2,Database,RefreshCw,ShieldCheck,X}from'lucide-react'
import{api}from'./lib/supabase'

const ROOT_ID='layer1-operations-root'

function Layer1Operations(){
  const[open,setOpen]=useState(false),[context,setContext]=useState(null),[rows,setRows]=useState([]),[busy,setBusy]=useState(false),[error,setError]=useState('')
  const load=async()=>{setBusy(true);setError('');try{const[c,s]=await Promise.all([api.context(),api.regulatorySources()]);setContext(c||null);setRows(Array.isArray(s)?s:[])}catch(e){setError(e.message||String(e))}finally{setBusy(false)}}
  useEffect(()=>{
    const sync=()=>{if(location.hash.replace(/^#/,'').split('?')[0]!=='settings')return;setOpen(true);location.hash='#layer-1-regulatory';load()}
    addEventListener('hashchange',sync);sync();return()=>removeEventListener('hashchange',sync)
  },[])
  const rank=Number(context?.role_rank||0)
  const countries=useMemo(()=>[...new Set(rows.map(r=>r.country_code).filter(Boolean))].sort(),[rows])
  const healthy=useMemo(()=>rows.filter(r=>r.source_id&&r.last_success_at&&(!r.last_failure_at||new Date(r.last_success_at)>=new Date(r.last_failure_at))).length,[rows])
  if(!open)return null
  const close=()=>{setOpen(false);location.hash='#dashboard'}
  return <div className="l1o-backdrop" role="presentation" onMouseDown={e=>{if(e.target===e.currentTarget)close()}}>
    <section className="l1o-shell" role="dialog" aria-modal="true" aria-labelledby="l1o-title">
      <header><div><span>Data Operations · authoritative source layer</span><h1 id="l1o-title">Layer 1 — Regulatory</h1><p>Regulatory source health, catalogue coverage and governed ingestion readiness.</p></div><button onClick={close} aria-label="Close Layer 1 Regulatory"><X size={20}/></button></header>
      {rank>0&&rank<4?<main><div className="l1o-state"><ShieldCheck size={22}/><h2>Not authorised</h2><p>Your assigned CourseFinder role does not permit Layer 1 operations.</p></div></main>:<main>
        <div className="l1o-toolbar"><div><b>Operator view</b><span>{context?.role||'Authorised operator'} · server-side authority remains enforced</span></div><button onClick={load} disabled={busy}><RefreshCw size={15}/>{busy?'Refreshing…':'Refresh'}</button></div>
        {error&&<div className="l1o-error">{error}</div>}
        <div className="l1o-metrics"><article><Database/><span>Configured sources</span><b>{rows.filter(r=>r.source_id).length}</b></article><article><Activity/><span>Healthy sources</span><b>{healthy}</b></article><article><BookOpen/><span>Countries</span><b>{countries.length}</b></article><article><CheckCircle2/><span>Authority</span><b>Governed</b></article></div>
        <section className="l1o-panel"><div><span>Current source registry</span><h2>Regulatory coverage</h2><p>Routine operators inspect source readiness here. Qualification probes, database reset and other destructive controls are intentionally excluded from this primary journey.</p></div><div className="l1o-table"><table><thead><tr><th>Country</th><th>Source</th><th>Status</th><th>Last success</th></tr></thead><tbody>{rows.filter(r=>r.source_id).slice(0,80).map((r,i)=><tr key={r.source_id||i}><td><b>{r.country_name||r.country_code}</b><small>{r.country_code}</small></td><td>{r.source_label||r.system_name||'—'}</td><td>{r.source_status||'unknown'}</td><td>{r.last_success_at?new Date(r.last_success_at).toLocaleString():'—'}</td></tr>)}</tbody></table></div></section>
      </main>}
    </section>
    <style>{`.l1o-backdrop{position:fixed;inset:0;z-index:51000;background:rgba(15,23,42,.55);display:flex;align-items:flex-start;justify-content:center;padding:28px;overflow:auto;backdrop-filter:blur(3px)}.l1o-shell{width:min(1120px,100%);background:#fff;border-radius:16px;box-shadow:0 28px 80px rgba(15,23,42,.28);overflow:hidden;color:#182230}.l1o-shell>header{display:flex;justify-content:space-between;gap:20px;padding:22px 24px;border-bottom:1px solid #e6eaf0}.l1o-shell header span,.l1o-toolbar span,.l1o-panel>div>span{font-size:10px;font-weight:800;text-transform:uppercase;letter-spacing:.08em;color:#667085}.l1o-shell h1{font-size:24px;margin:4px 0}.l1o-shell header p,.l1o-panel p{margin:0;color:#667085;font-size:12px}.l1o-shell header button,.l1o-toolbar button{border:1px solid #d8dee8;background:#fff;border-radius:9px;padding:8px 10px;cursor:pointer}.l1o-shell main{padding:22px 24px}.l1o-toolbar{display:flex;justify-content:space-between;gap:16px;align-items:center}.l1o-toolbar>div{display:grid;gap:3px}.l1o-toolbar button{display:flex;gap:7px;align-items:center}.l1o-metrics{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin:18px 0}.l1o-metrics article{border:1px solid #e3e8f0;border-radius:11px;padding:14px;display:grid;grid-template-columns:auto 1fr;gap:6px 10px;align-items:center}.l1o-metrics svg{width:17px}.l1o-metrics span{font-size:11px;color:#667085}.l1o-metrics b{grid-column:2;font-size:18px}.l1o-panel{border:1px solid #e3e8f0;border-radius:12px;overflow:hidden}.l1o-panel>div:first-child{padding:16px}.l1o-panel h2{margin:4px 0;font-size:16px}.l1o-table{overflow:auto;border-top:1px solid #e3e8f0}.l1o-table table{width:100%;border-collapse:collapse;font-size:12px}.l1o-table th,.l1o-table td{text-align:left;padding:10px 12px;border-bottom:1px solid #edf0f4}.l1o-table th{font-size:10px;text-transform:uppercase;color:#667085}.l1o-table td:first-child{display:grid}.l1o-table small{color:#7b8798}.l1o-error{margin-top:14px;padding:10px;border-radius:8px;background:#fff4f4;color:#9b1c1c}.l1o-state{padding:40px;text-align:center;display:grid;gap:8px;justify-items:center}.l1o-state h2,.l1o-state p{margin:0}@media(max-width:760px){.l1o-backdrop{padding:10px}.l1o-metrics{grid-template-columns:repeat(2,minmax(0,1fr))}.l1o-shell main{padding:16px}.l1o-shell>header{padding:18px}}`}</style>
  </div>
}

const root=document.getElementById(ROOT_ID)
if(root)createRoot(root).render(<Layer1Operations/>)
