// CF-247 (16 Oct 2026): Operations › API usage — the console for the API version URLs (zoho-api-v2, website-api-v2). Platform Admin 14:31:
// "Create me a ui to check stats on Both APIs with relevant metrics/API calls or statistics, success & failure, last login, full sync, delta
// sync, bandwidth, load size etc. be able to rotate their keys. and on Demand fresh statistics by pressing a button, otherwise get refresh
// daily basis."
// Statistics come from pipeline.api_usage_summary (rebuilt daily by api-usage-rollup, or now by the Refresh button). Key rotation, switch
// off/on and ending an old key early are Platform Admin actions (rank 6); a new key is shown once here and never stored.
import React,{useEffect,useMemo,useState}from'react'
import{RefreshCw,KeyRound,Power,Copy,AlertTriangle,Clock}from'lucide-react'
import{supabase}from'./lib/supabase'
import'./settings.css'
import{Metric,StatusChip,EmptyInline,fmtDateTime}from'./ui-kit'
import{fmtNumber,fmtBytes,fmtPercent,fmtRelative}from'./lib/format.js'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const PLATFORMS=[{key:'zoho',label:'Zoho API v2',url:'zoho-api-v2'},{key:'website',label:'Website API v2',url:'website-api-v2'}]
const PERIODS=[{key:'24h',label:'24 hours'},{key:'7d',label:'7 days'},{key:'30d',label:'30 days'}]
const ms=v=>v==null?'—':`${fmtNumber(v)} ms`
const dur=s=>s==null?'—':s<120?`${fmtNumber(s)} s`:`${fmtNumber(Math.round(s/60))} min`
const sum=(rows,k)=>rows.reduce((a,r)=>a+(Number(r?.[k])||0),0)
const EVENT={rotated:'Rotated',switched_off:'Switched off',switched_on:'Switched on',previous_ended:'Old key ended'}

export function platformTotals(keys,period){
 const st=keys.map(k=>k.stats?.[period]).filter(Boolean)
 const calls=sum(st,'calls'),ok=sum(st,'ok')
 const last=st.map(s=>s.last_call_at).filter(Boolean).sort().pop()||null
 return{calls,ok,failures:calls-ok,success:calls?Math.round(1000*ok/calls)/10:null,bytes:sum(st,'bytes'),last,on:keys.filter(k=>k.enabled).length,total:keys.length}
}

function KeyDialog({mode,k,overlap,onClose,onDone,onError}){
 const[hours,setHours]=useState(String(overlap??24)),[note,setNote]=useState(''),[busy,setBusy]=useState(false),[result,setResult]=useState(null),[copied,setCopied]=useState(false)
 const go=async()=>{setBusy(true)
  try{
   if(mode==='rotate'){const h=Number(hours);if(!Number.isFinite(h)||h<0||h>168)throw new Error('Overlap must be 0 to 168 hours')
    const{data,error}=await supabase.rpc('admin_api_key_rotate',{p_key_name:k.key_name,p_overlap_hours:h,p_note:note||null});if(error)throw error;setResult(data)}
   else if(mode==='end'){const{error}=await supabase.rpc('admin_api_key_end_previous',{p_key_name:k.key_name,p_note:note||null});if(error)throw error;onDone();onClose()}
   else{const{error}=await supabase.rpc('admin_api_key_set_enabled',{p_key_name:k.key_name,p_enabled:!k.enabled,p_note:note||null});if(error)throw error;onDone();onClose()}
  }catch(e){onError?.(errText(e))}finally{setBusy(false)}}
 const copy=()=>{navigator.clipboard?.writeText(result.key).then(()=>setCopied(true)).catch(()=>{})}
 const title=mode==='rotate'?`Rotate ${k.key_name}`:mode==='end'?`End the old key for ${k.key_name}`:k.enabled?`Switch off ${k.key_name}`:`Switch on ${k.key_name}`
 if(result)return <div className="confirm-backdrop" role="presentation"><div className="confirm-card cf-api-newkey" role="dialog" aria-modal="true" aria-label="New key">
  <div className="confirm-icon"><KeyRound size={22}/></div><h3>New key for {result.key_name}</h3>
  <p>This is the only time the key is shown: it is not stored anywhere. Copy it now and send it to {k.consumer} by a secure channel. {result.previous_valid_until?<>The old key keeps working until <strong>{fmtDateTime(result.previous_valid_until)}</strong>.</>:<>The old key has stopped working.</>}</p>
  <code className="cf-api-key-value" data-testid="new-key">{result.key}</code>
  <div className="confirm-actions"><button className="m-secondary" onClick={copy}><Copy size={14}/> {copied?'Copied':'Copy key'}</button><button className="m-primary" onClick={()=>{onDone();onClose()}}>I have stored it</button></div>
 </div></div>
 return <div className="confirm-backdrop" role="presentation" onMouseDown={()=>!busy&&onClose()}><div className="confirm-card" role="dialog" aria-modal="true" aria-label={title} onMouseDown={e=>e.stopPropagation()}>
  <div className="confirm-icon"><AlertTriangle size={22}/></div><h3>{title}</h3>
  {mode==='rotate'&&<p>A new key is made for {k.consumer}. Calls with the old key keep working for the overlap below so they can switch; 0 stops the old key at once.</p>}
  {mode==='end'&&<p>The old key stops working now. Calls still using it get 401.</p>}
  {mode==='switch'&&<p>{k.enabled?`Every call with this key (and any old key in overlap) gets 401 until it is switched on again.`:`The key works again straight away.`}</p>}
  {mode==='rotate'&&<><label htmlFor="cf-api-overlap">Hours the old key keeps working</label><input id="cf-api-overlap" type="number" min="0" max="168" value={hours} onChange={e=>setHours(e.target.value)}/></>}
  <label htmlFor="cf-api-note" style={{marginTop:12}}>Note (optional)</label><input id="cf-api-note" value={note} onChange={e=>setNote(e.target.value)} placeholder="Why"/>
  <div className="confirm-actions"><button className="m-secondary" onClick={onClose} disabled={busy}>Cancel</button><button className="danger-soft" onClick={go} disabled={busy}>{busy?'Working…':mode==='rotate'?'Rotate key':mode==='end'?'End old key':k.enabled?'Switch off':'Switch on'}</button></div>
 </div></div>
}

export default function ApiUsagePanel({onError}){
 const[days,setDays]=useState(14),[period,setPeriod]=useState('7d'),[d,setD]=useState(null),[busy,setBusy]=useState(false),[refreshing,setRefreshing]=useState(false),[key,setKey]=useState(''),[dialog,setDialog]=useState(null)
 const load=()=>{setBusy(true);supabase.rpc('admin_api_usage',{p_days:days}).then(({data,error})=>{if(error)throw error;setD(data)}).catch(e=>onError?.(errText(e))).finally(()=>setBusy(false))}
 const refresh=()=>{setRefreshing(true);supabase.rpc('admin_api_usage_refresh').then(({error})=>{if(error)throw error;load()}).catch(e=>onError?.(errText(e))).finally(()=>setRefreshing(false))}
 useEffect(()=>{load()},[days])
 const keys=d?.keys||[],manage=d?.can_manage_keys===true
 const daily=useMemo(()=>(d?.daily||[]).filter(r=>!key||r.key_name===key||r.key_name===`${key}#previous`),[d,key])
 const byDay=useMemo(()=>{const m=new Map();for(const r of daily){const x=m.get(r.day)||{day:r.day,calls:0,ok:0,client_errors:0,rate_limited:0,server_errors:0,items:0,bytes:0,ms:0};x.calls+=r.calls;x.ok+=r.ok;x.client_errors+=r.client_errors;x.rate_limited+=r.rate_limited;x.server_errors+=r.server_errors;x.items+=Number(r.items)||0;x.bytes+=Number(r.bytes)||0;x.ms+=(r.avg_ms||0)*r.calls;m.set(r.day,x)}return[...m.values()].sort((a,b)=>a.day<b.day?1:-1)},[daily])
 const ref=d?.refreshed
 return <div className="m-page-stack">
  <section className="m-panel">
   <header className="m-workspace-head"><h3>API usage</h3>
    <div className="m-search-row">
     <label>Period <select value={period} onChange={e=>setPeriod(e.target.value)} aria-label="Period">{PERIODS.map(p=><option key={p.key} value={p.key}>{p.label}</option>)}</select></label>
     <button className="m-primary compact cf-api-refresh" onClick={refresh} disabled={refreshing||busy}><RefreshCw size={14}/> {refreshing?'Refreshing…':'Refresh statistics now'}</button>
    </div>
   </header>
   <p className="l3v-note cf-api-asof"><Clock size={13}/> {ref?<>Statistics as of <strong>{fmtDateTime(ref.at)}</strong> ({ref.trigger==='on_demand'?`refreshed on demand${ref.by?` by ${ref.by}`:''}`:'daily refresh'}, {fmtRelative(ref.at)}). They refresh every day at about 00:20 Melbourne time, or now with the button.</>:'Statistics have not been built yet: press Refresh statistics now.'} Calls to the older URLs (Zoho v1, and the website through wix-course-api) are not logged here.</p>
   <div className="cf-api-platforms">
    {PLATFORMS.map(p=>{const ks=keys.filter(k=>k.platform===p.key),t=platformTotals(ks,period);return <div key={p.key} className="cf-api-platform" data-platform={p.key}>
     <h4>{p.label} <small><code>{p.url}</code> · keys on: {t.on} of {t.total}</small></h4>
     <div className="cf-metric-grid">
      <Metric label={`Calls (${PERIODS.find(x=>x.key===period).label})`} value={fmtNumber(t.calls)}/>
      <Metric label="Success rate" value={t.success==null?'—':fmtPercent(t.success)} tone={t.success!=null&&t.success<95?'warning':'neutral'}/>
      <Metric label="Failures" value={fmtNumber(t.failures)} tone={t.failures?'warning':'neutral'}/>
      <Metric label="Bandwidth sent" value={fmtBytes(t.bytes)}/>
      <Metric label="Last call" value={t.last?fmtRelative(t.last):'Never'}/>
     </div></div>})}
   </div>
  </section>

  <section className="m-panel"><header className="m-workspace-head"><h3>Keys</h3></header>
   {keys.length===0?<EmptyInline text="No keys."/>:<div className="dense-table-wrap"><table className="dense-table cf-api-keys"><thead><tr><th>Key</th><th>Used by</th><th>Status</th><th>Last call</th><th>Last success</th><th>Calls</th><th>Success</th><th>Failures (client / limited / server)</th><th>Bandwidth</th><th>Average reply</th><th>Largest reply</th><th>Time (average / 95%)</th><th>Rotated</th>{manage&&<th>Actions</th>}</tr></thead>
    <tbody>{keys.map(k=>{const s=k.stats?.[period]||{};return <tr key={k.key_name} data-key={k.key_name}>
     <td><code>{k.key_name}</code><div className="cf-api-sub">{k.platform} {k.api_version} · {fmtNumber(k.rate_per_minute)}/min · hash {k.key_hint}…</div></td>
     <td>{k.consumer}</td>
     <td><StatusChip tone={k.enabled?'success':'neutral'} label={k.enabled?'On':'Off'}/>{k.previous_valid_until&&<div className="cf-api-sub cf-api-overlap">Old key works until {fmtDateTime(k.previous_valid_until)}{s.previous_key_last_at?` · last used ${fmtRelative(s.previous_key_last_at)}`:' · not used'}</div>}</td>
     <td>{s.last_call_at?fmtDateTime(s.last_call_at):k.last_used_at?fmtDateTime(k.last_used_at):'Never'}</td>
     <td>{s.last_ok_at?fmtDateTime(s.last_ok_at):'—'}</td>
     <td>{fmtNumber(s.calls||0)}</td>
     <td>{s.success_rate==null?'—':fmtPercent(s.success_rate)}</td>
     <td>{fmtNumber(s.client_errors||0)} / {fmtNumber(s.rate_limited||0)} / {fmtNumber(s.server_errors||0)}{s.last_error_code&&<div className="cf-api-sub">last {s.last_error_code}, {fmtRelative(s.last_error_at)}</div>}</td>
     <td>{fmtBytes(s.bytes||0)}</td>
     <td>{s.avg_bytes==null?'—':fmtBytes(s.avg_bytes)}</td>
     <td>{s.max_bytes==null?'—':fmtBytes(s.max_bytes)}</td>
     <td>{ms(s.avg_ms)} / {ms(s.p95_ms)}</td>
     <td>{k.rotated_at?fmtDateTime(k.rotated_at):'Never'}</td>
     {manage&&<td className="cf-api-key-actions"><button className="m-secondary compact" onClick={()=>setDialog({mode:'rotate',k})}><KeyRound size={13}/> Rotate</button><button className="m-secondary compact" onClick={()=>setDialog({mode:'switch',k})}><Power size={13}/> {k.enabled?'Switch off':'Switch on'}</button>{k.previous_valid_until&&<button className="m-secondary compact" onClick={()=>setDialog({mode:'end',k})}>End old key</button>}</td>}
    </tr>})}</tbody></table></div>}
   {!manage&&<p className="l3v-note">Rotating and switching keys is for the Platform Admin.</p>}
  </section>

  <section className="m-panel"><header className="m-workspace-head"><h3>Full loads and deltas</h3></header>
   <p className="l3v-note">A full load is every page from the first <code>sync</code> without a cursor to the page that ends it; a delta is a <code>sync</code> with a stored cursor. CSV exports are the Zoho CRM files. Counts are for the period; the last full load is the latest in the kept log.</p>
   {keys.length===0?<EmptyInline text="No keys."/>:<div className="dense-table-wrap"><table className="dense-table cf-api-sync"><thead><tr><th>Key</th><th>Last full load finished</th><th>Took</th><th>Pages</th><th>Items</th><th>Load size</th><th>Full-load started (latest)</th><th>Full loads done</th><th>Deltas</th><th>Delta items</th><th>Delta size</th><th>Last delta</th><th>CSV exports</th><th>Searches</th></tr></thead>
    <tbody>{keys.map(k=>{const s=k.stats?.[period]||{},f=s.last_full_load;return <tr key={k.key_name}>
     <td><code>{k.key_name}</code></td>
     <td>{f?fmtDateTime(f.finished_at):'None yet'}</td><td>{f?dur(f.seconds):'—'}</td><td>{f?fmtNumber(f.pages):'—'}</td><td>{f?fmtNumber(f.items):'—'}</td><td>{f?fmtBytes(f.bytes):'—'}</td>
     <td>{s.last_full_load_started_at?fmtDateTime(s.last_full_load_started_at):'—'}</td>
     <td>{fmtNumber(s.full_loads_completed||0)}</td><td>{fmtNumber(s.delta_calls||0)}</td><td>{fmtNumber(s.delta_items||0)}</td><td>{fmtBytes(s.delta_bytes||0)}</td>
     <td>{s.last_delta_at?fmtDateTime(s.last_delta_at):'—'}</td>
     <td>{fmtNumber(s.exports||0)}{s.exports?` (${fmtBytes(s.export_bytes)})`:''}</td><td>{fmtNumber(s.searches||0)}</td>
    </tr>})}</tbody></table></div>}
  </section>

  <section className="m-panel"><header className="m-workspace-head"><h3>By day</h3>
   <div className="m-search-row">
    <label>Key <select value={key} onChange={e=>setKey(e.target.value)} aria-label="Key"><option value="">All keys</option>{keys.map(k=><option key={k.key_name} value={k.key_name}>{k.key_name}</option>)}</select></label>
    <label>Days <select value={days} onChange={e=>setDays(Number(e.target.value))} aria-label="Days">{[1,7,14,30,90].map(n=><option key={n} value={n}>{n}</option>)}</select></label>
   </div></header>
   {byDay.length===0?<EmptyInline text="No calls in this period."/>:<div className="dense-table-wrap"><table className="dense-table cf-api-days"><thead><tr><th>Day</th><th>Calls</th><th>OK</th><th>Client errors</th><th>Rate limited</th><th>Server errors</th><th>Items returned</th><th>Bandwidth</th><th>Average time</th></tr></thead>
    <tbody>{byDay.map(r=><tr key={r.day}><td>{r.day}</td><td>{fmtNumber(r.calls)}</td><td>{fmtNumber(r.ok)}</td><td>{fmtNumber(r.client_errors)}</td><td>{fmtNumber(r.rate_limited)}</td><td>{fmtNumber(r.server_errors)}</td><td>{fmtNumber(r.items)}</td><td>{fmtBytes(r.bytes)}</td><td>{r.calls?`${fmtNumber(Math.round(r.ms/r.calls))} ms`:'—'}</td></tr>)}</tbody></table></div>}
  </section>

  <section className="m-panel"><header className="m-workspace-head"><h3>By key and action</h3></header>
   {daily.length===0?<EmptyInline text="No calls in this period."/>:<div className="dense-table-wrap"><table className="dense-table cf-api-actions"><thead><tr><th>Day</th><th>Key</th><th>Action</th><th>Calls</th><th>Errors</th><th>Bandwidth</th><th>Average</th><th>95% within</th><th>Slowest</th><th>Last call</th></tr></thead>
    <tbody>{daily.map(r=><tr key={`${r.day}-${r.key_name}-${r.action}`}><td>{r.day}</td><td><code>{r.key_name}</code></td><td>{r.action}</td><td>{fmtNumber(r.calls)}</td><td>{fmtNumber(r.client_errors+r.server_errors)}</td><td>{fmtBytes(r.bytes)}</td><td>{ms(r.avg_ms)}</td><td>{ms(r.p95_ms)}</td><td>{ms(r.max_ms)}</td><td>{fmtDateTime(r.last_at)}</td></tr>)}</tbody></table></div>}
  </section>

  <section className="m-panel"><header className="m-workspace-head"><h3>Latest errors</h3></header>
   {(d?.recent_errors||[]).length===0?<EmptyInline text="No errors."/>:<div className="dense-table-wrap"><table className="dense-table cf-api-errors"><thead><tr><th>When</th><th>Key</th><th>Action</th><th>Status</th><th>Error</th><th>Request id</th></tr></thead>
    <tbody>{d.recent_errors.map(r=><tr key={r.request_id||r.at}><td>{fmtDateTime(r.at)}</td><td><code>{r.key_name||'(no key)'}</code></td><td>{r.action||'—'}</td><td>{r.status}</td><td>{r.error_code||'—'}</td><td><code>{r.request_id}</code></td></tr>)}</tbody></table></div>}
  </section>

  <section className="m-panel"><header className="m-workspace-head"><h3>Key changes</h3></header>
   {(d?.events||[]).length===0?<EmptyInline text="No key has been rotated or switched yet."/>:<div className="dense-table-wrap"><table className="dense-table cf-api-events"><thead><tr><th>When</th><th>Key</th><th>Change</th><th>By</th><th>Old key worked until</th><th>Note</th></tr></thead>
    <tbody>{d.events.map((e,i)=><tr key={`${e.at}-${i}`}><td>{fmtDateTime(e.at)}</td><td><code>{e.key_name}</code></td><td>{EVENT[e.event]||e.event}</td><td>{e.by||'—'}</td><td>{e.previous_valid_until?fmtDateTime(e.previous_valid_until):'—'}</td><td>{e.note||'—'}</td></tr>)}</tbody></table></div>}
  </section>
  {dialog&&<KeyDialog mode={dialog.mode} k={dialog.k} overlap={d?.overlap_hours} onClose={()=>setDialog(null)} onDone={load} onError={onError}/>}
 </div>
}
