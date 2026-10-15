// CF-247 (16 Oct 2026): Operations › API usage. Platform Admin, 16 Oct 2026 09:43: "create separate API URL and Key for Zoho V2 API ... with
// summary and stat collection as well". Every call to a versioned API URL (from zoho-api-v2 on) is logged; this screen shows the keys, the
// calls per day, key and action (ok, errors, rate limited, times) and the latest errors. Read only.
import React,{useEffect,useMemo,useState}from'react'
import{RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Metric,StatusChip,EmptyInline,fmtDateTime}from'./ui-kit'
import{fmtNumber}from'./lib/format.js'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const sum=(rows,k)=>rows.reduce((a,r)=>a+(Number(r[k])||0),0)

export default function ApiUsagePanel({onError}){
 const[days,setDays]=useState(14),[d,setD]=useState(null),[busy,setBusy]=useState(false),[key,setKey]=useState('')
 const load=()=>{setBusy(true);supabase.rpc('admin_api_usage',{p_days:days}).then(({data,error})=>{if(error)throw error;setD(data)}).catch(e=>onError?.(errText(e))).finally(()=>setBusy(false))}
 useEffect(()=>{load()},[days])
 const daily=useMemo(()=>(d?.daily||[]).filter(r=>!key||r.key_name===key),[d,key])
 const byDay=useMemo(()=>{const m=new Map();for(const r of daily){const x=m.get(r.day)||{day:r.day,calls:0,ok:0,client_errors:0,rate_limited:0,server_errors:0,items:0,ms:0};x.calls+=r.calls;x.ok+=r.ok;x.client_errors+=r.client_errors;x.rate_limited+=r.rate_limited;x.server_errors+=r.server_errors;x.items+=Number(r.items)||0;x.ms+=(r.avg_ms||0)*r.calls;m.set(r.day,x)}return[...m.values()].sort((a,b)=>a.day<b.day?1:-1)},[daily])
 const calls=sum(daily,'calls'),errors=sum(daily,'client_errors')+sum(daily,'server_errors'),limited=sum(daily,'rate_limited')
 const avg=calls?Math.round(daily.reduce((a,r)=>a+(r.avg_ms||0)*r.calls,0)/calls):null
 return <div className="m-page-stack">
  <section className="m-panel">
   <header className="m-workspace-head"><h3>API usage</h3>
    <div className="m-search-row">
     <label>Key <select value={key} onChange={e=>setKey(e.target.value)} aria-label="Key"><option value="">All keys</option>{(d?.keys||[]).map(k=><option key={k.key_name} value={k.key_name}>{k.key_name}</option>)}</select></label>
     <label>Days <select value={days} onChange={e=>setDays(Number(e.target.value))} aria-label="Days">{[1,7,14,30,90].map(n=><option key={n} value={n}>{n}</option>)}</select></label>
     <button className="m-secondary compact" onClick={load} disabled={busy} aria-label="Refresh"><RefreshCw size={14}/> Refresh</button>
    </div>
   </header>
   <p className="l3v-note">Every call to an API version URL (from Zoho API v2 on) is logged and summed every 15 minutes. Website and Zoho v1 calls are not logged here yet.</p>
   <div className="cf-metric-grid">
    <Metric label={`Calls (${days} days)`} value={fmtNumber(calls)}/>
    <Metric label="Errors" value={fmtNumber(errors)}/>
    <Metric label="Rate limited" value={fmtNumber(limited)}/>
    <Metric label="Average time" value={avg==null?'—':`${fmtNumber(avg)} ms`}/>
   </div>
  </section>
  <section className="m-panel"><header className="m-workspace-head"><h3>Keys</h3></header>
   {(d?.keys||[]).length===0?<EmptyInline text="No keys."/>:<div className="dense-table-wrap"><table className="dense-table cf-api-keys"><thead><tr><th>Key</th><th>Platform</th><th>Version</th><th>Used by</th><th>Calls a minute</th><th>Last used</th><th>Status</th></tr></thead>
    <tbody>{d.keys.map(k=><tr key={k.key_name}><td><code>{k.key_name}</code></td><td>{k.platform}</td><td>{k.api_version}</td><td>{k.consumer}</td><td>{fmtNumber(k.rate_per_minute)}</td><td>{k.last_used_at?fmtDateTime(k.last_used_at):'Never'}</td><td><StatusChip tone={k.enabled?'success':'neutral'} label={k.enabled?'On':'Off'}/></td></tr>)}</tbody></table></div>}
  </section>
  <section className="m-panel"><header className="m-workspace-head"><h3>By day</h3></header>
   {byDay.length===0?<EmptyInline text="No calls in this period."/>:<div className="dense-table-wrap"><table className="dense-table cf-api-days"><thead><tr><th>Day</th><th>Calls</th><th>OK</th><th>Client errors</th><th>Rate limited</th><th>Server errors</th><th>Items returned</th><th>Average time</th></tr></thead>
    <tbody>{byDay.map(r=><tr key={r.day}><td>{r.day}</td><td>{fmtNumber(r.calls)}</td><td>{fmtNumber(r.ok)}</td><td>{fmtNumber(r.client_errors)}</td><td>{fmtNumber(r.rate_limited)}</td><td>{fmtNumber(r.server_errors)}</td><td>{fmtNumber(r.items)}</td><td>{r.calls?`${fmtNumber(Math.round(r.ms/r.calls))} ms`:'—'}</td></tr>)}</tbody></table></div>}
  </section>
  <section className="m-panel"><header className="m-workspace-head"><h3>By key and action</h3></header>
   {daily.length===0?<EmptyInline text="No calls in this period."/>:<div className="dense-table-wrap"><table className="dense-table cf-api-actions"><thead><tr><th>Day</th><th>Key</th><th>Action</th><th>Calls</th><th>Errors</th><th>Average</th><th>95% within</th><th>Slowest</th><th>Last call</th></tr></thead>
    <tbody>{daily.map(r=><tr key={`${r.day}-${r.key_name}-${r.action}`}><td>{r.day}</td><td><code>{r.key_name}</code></td><td>{r.action}</td><td>{fmtNumber(r.calls)}</td><td>{fmtNumber(r.client_errors+r.server_errors)}</td><td>{r.avg_ms==null?'—':`${fmtNumber(r.avg_ms)} ms`}</td><td>{r.p95_ms==null?'—':`${fmtNumber(r.p95_ms)} ms`}</td><td>{r.max_ms==null?'—':`${fmtNumber(r.max_ms)} ms`}</td><td>{fmtDateTime(r.last_at)}</td></tr>)}</tbody></table></div>}
  </section>
  <section className="m-panel"><header className="m-workspace-head"><h3>Latest errors</h3></header>
   {(d?.recent_errors||[]).length===0?<EmptyInline text="No errors."/>:<div className="dense-table-wrap"><table className="dense-table cf-api-errors"><thead><tr><th>When</th><th>Key</th><th>Action</th><th>Status</th><th>Error</th><th>Request id</th></tr></thead>
    <tbody>{d.recent_errors.map(r=><tr key={r.request_id||r.at}><td>{fmtDateTime(r.at)}</td><td><code>{r.key_name||'(no key)'}</code></td><td>{r.action||'—'}</td><td>{r.status}</td><td>{r.error_code||'—'}</td><td><code>{r.request_id}</code></td></tr>)}</tbody></table></div>}
  </section>
 </div>
}
