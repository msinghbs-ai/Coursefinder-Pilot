import React,{useEffect,useState}from'react'
import{Activity,AlertTriangle,Database,DollarSign,HardDrive,RefreshCw,Save}from'lucide-react'
import{supabase}from'./lib/supabase'
import'./platform-resources.css'

// Package 8.2 (Decision 153): resource utilisation, forecast and toolset cost.
// Reads pre-recorded hourly observations (no heavy queries on open).
const rpc=async(fn,args)=>{const{data,error}=await supabase.rpc(fn,args);if(error)throw new Error(error.message);return data}
const mb=b=>b==null?'—':Math.round(Number(b)/1048576).toLocaleString('en-AU')+' MB'
const gb=b=>b==null?'—':(Number(b)/1073741824).toFixed(1)+' GB'
const usd=v=>v==null?'—':'US$'+Number(v).toLocaleString('en-AU',{minimumFractionDigits:2,maximumFractionDigits:2})
const n=v=>v==null?'—':Number(v).toLocaleString('en-AU')
const when=v=>v?new Date(v).toLocaleString('en-AU',{day:'numeric',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'}):'—'
const cycle=d=>{d=Number(d);return d>=365?'annually':d>=180?'twice a year':d>=90?'quarterly':d>=28?'monthly':d===7?'weekly':`every ${d} days`}
const MON=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']
const months=a=>a.length>1?`${MON[a[0]-1]}–${MON[a[a.length-1]-1]} window`:`${MON[a[0]-1]} window`

export function resourceAlerts(d){
  const out=[],l=d?.latest,t=d?.thresholds,ratio=Number(d?.memory_ratio||0)
  if(!l)return[{level:'warn',text:'No resource observation recorded yet. The recorder runs at the start of each hour.'}]
  if(ratio>=1)out.push({level:'high',text:`Database (${mb(l.db_bytes)}) is larger than memory (${mb(l.memory_bytes)}). Reads increasingly come from disk; review the largest tables or plan the next compute size.`})
  else if(ratio>=0.85)out.push({level:'warn',text:`Database is at ${Math.round(ratio*100)}% of memory.`})
  if(t&&Number(l.db_bytes)>=Number(t.database_critical_bytes))out.push({level:'high',text:'Database size is above the critical threshold.'})
  else if(t&&Number(l.db_bytes)>=Number(t.database_high_bytes))out.push({level:'high',text:'Database size is above the high threshold.'})
  else if(t&&Number(l.db_bytes)>=Number(t.database_warn_bytes))out.push({level:'warn',text:'Database size is above the warning threshold.'})
  if(Number(l.cron_failures)>0)out.push({level:Number(l.cron_failures)>5?'high':'warn',text:`${l.cron_failures} of ${l.cron_runs} scheduled job runs did not succeed in the last recorded hour.`})
  if(Number(l.cron_max_concurrent)>3)out.push({level:'warn',text:`${l.cron_max_concurrent} jobs ran at the same time; heavy jobs should never overlap.`})
  if(l.cache_hit_pct!=null&&Number(l.cache_hit_pct)<98)out.push({level:'warn',text:`Cache hit rate is ${l.cache_hit_pct}%; below 98% means more reads from disk.`})
  return out
}

function Spark({values,label}){
  const v=(values||[]).map(Number).filter(x=>!Number.isNaN(x))
  if(v.length<2)return <span className="pr-spark-empty">Trend appears after two days of data</span>
  const w=160,h=36,max=Math.max(...v),min=Math.min(...v),span=max-min||1
  const pts=v.map((x,i)=>`${(i*(w/(v.length-1))).toFixed(1)},${(h-((x-min)/span)*(h-4)-2).toFixed(1)}`).join(' ')
  return <svg className="pr-spark" width={w} height={h} role="img" aria-label={label}><polyline points={pts} fill="none" stroke="currentColor" strokeWidth="2"/></svg>
}

export default function PlatformResourcesPanel({onError=()=>{}}){
  const[data,setData]=useState(null),[life,setLife]=useState([]),[busy,setBusy]=useState(false),[edits,setEdits]=useState({}),[saving,setSaving]=useState(''),[msg,setMsg]=useState('')
  const load=async()=>{setBusy(true);try{const[r,l]=await Promise.all([rpc('admin_platform_resources_read_v1',{p_days:30}),rpc('admin_admission_lifecycle_read_v1',{})]);setData(r);setLife(Array.isArray(l)?l:[])}catch(e){onError(e.message)}finally{setBusy(false)}}
  useEffect(()=>{load()},[])
  const save=async key=>{setSaving(key);setMsg('');try{setData(await rpc('admin_platform_cost_model_save_v1',{p_item_key:key,p_monthly_usd:Number(edits[key]),p_notes:null}));setEdits({...edits,[key]:undefined});setMsg('Cost saved.')}catch(e){onError(e.message)}finally{setSaving('')}}
  if(!data)return <section className="env-panel pr-panel">{busy?'Loading platform resources…':'Platform resources are unavailable.'}</section>
  const l=data.latest||{},c=data.compute||{},daily=data.daily||[],alerts=resourceAlerts(data),costs=data.costs||{},st=data.storage||{}
  const ratio=Number(data.memory_ratio||0)
  return <section className="env-panel pr-panel" aria-label="Platform resources and cost">
    <div className="env-head"><div><small>Administration / Environment & Migration</small><h2>Platform resources and cost</h2><p>Recorded hourly from the database's own statistics. Use it to plan compute size and toolset spend before limits are reached.</p></div>
      <button onClick={load} disabled={busy} aria-label="Refresh resources"><RefreshCw size={15}/>Refresh resources</button></div>
    {alerts.length>0&&<div className="pr-alerts">{alerts.map((a,i)=><div key={i} className={`pr-alert ${a.level}`}><AlertTriangle size={15}/><span>{a.text}</span></div>)}</div>}
    <div className="pr-tiles">
      <article><Database size={16}/><span>Database vs memory</span><strong>{mb(l.db_bytes)} / {mb(c.memory_bytes)}</strong><small className={ratio>=1?'bad':ratio>=0.85?'warn':''}>{Math.round(ratio*100)}% of memory · {c.compute_size||'—'} compute</small>
        <small>{data.days_until_memory!=null?`About ${n(data.days_until_memory)} days until it exceeds memory`:Number(data.growth_bytes_per_day)>0?'Already above memory':'Growth forecast needs a few days of data'}</small></article>
      <article><Activity size={16}/><span>Cache hit rate</span><strong>{l.cache_hit_pct!=null?`${l.cache_hit_pct}%`:'—'}</strong><small>{n(l.connections)} connections of {n(c.max_connections)}</small></article>
      <article><Activity size={16}/><span>Scheduled jobs (last hour)</span><strong>{n(l.cron_runs)} runs</strong><small className={Number(l.cron_failures)>0?'warn':''}>{n(l.cron_failures)} not succeeded · longest {l.cron_max_seconds??'—'} s · up to {n(l.cron_max_concurrent)} at once</small></article>
      <article><HardDrive size={16}/><span>Evidence storage</span><strong>{gb(st.evidence_object_bytes)}</strong><small>{n(st.evidence_objects)} files · {n(st.orphans)} without a record</small></article>
      <article><DollarSign size={16}/><span>Monthly toolset cost</span><strong>{usd(costs.total_monthly_usd)}</strong><small>Acquisition this month: {n(costs.acquisition_units_mtd)} units · AI this month: {usd(l.ai_cost_mtd_usd)}</small></article>
    </div>
    <div className="pr-two">
      <div className="pr-box"><h3>Last 30 days</h3>
        <div className="pr-trend"><span>Database size</span><Spark values={daily.map(x=>x.db_bytes)} label="Database size trend"/><small>{daily.length?mb(daily[daily.length-1].db_bytes):'—'}</small></div>
        <div className="pr-trend"><span>Job runs not succeeded</span><Spark values={daily.map(x=>x.cron_failures)} label="Job failure trend"/><small>{n(daily.reduce((s,x)=>s+Number(x.cron_failures||0),0))} in period</small></div>
        <div className="pr-trend"><span>Acquisition units</span><Spark values={daily.map(x=>x.acquisition_units)} label="Acquisition units trend"/><small>{n(daily.reduce((s,x)=>s+Number(x.acquisition_units||0),0))} in period</small></div>
        <p className="pr-note">Growth: {mb(data.growth_bytes_per_day)} per day. Last observation {when(l.observed_at)}.</p>
      </div>
      <div className="pr-box"><h3>Largest tables</h3>
        <table className="pr-table"><tbody>{(l.largest_tables||[]).map(x=><tr key={x.table}><td>{x.table}</td><td>{mb(x.bytes)}</td></tr>)}</tbody></table>
      </div>
    </div>
    <div className="pr-box"><h3>Admission lifecycle</h3><p className="pr-note">Data is admitted once, then re-checked only on its cycle or on demand.</p>
      <table className="pr-table"><thead><tr><th>Data</th><th>Layer</th><th>Re-check</th><th>Status</th></tr></thead><tbody>
        {life.map(x=><tr key={x.data_type}><td>{x.label}<small className="pr-sub">{x.rationale}</small></td><td>{x.layer}</td>
          <td>{cycle(x.cycle_days)}{x.check_days&&x.check_days!==x.cycle_days?` · checked ${cycle(x.check_days)}`:''}{x.window_months?.length?` · ${months(x.window_months)}`:''}</td>
          <td>{x.layer==='L2'?`${n(x.aligned)} of ${n(x.profiles)} profiles aligned`:x.next_due?(new Date(x.next_due)<new Date()?<span className="pr-bad">Overdue since {when(x.next_due)}</span>:`Next ${when(x.next_due)}`):'On publication'}</td></tr>)}
      </tbody></table></div>
    <div className="pr-box"><h3>Cost model (US$ per month)</h3>
      <table className="pr-table pr-costs"><thead><tr><th>Item</th><th>Basis</th><th>Monthly</th><th>Notes</th><th/></tr></thead><tbody>
        {(costs.items||[]).map(it=>{const editable=data.can_edit&&it.basis!=='usage_actual',val=edits[it.key]??it.monthly_usd
          return <tr key={it.key}><td>{it.label}</td><td>{it.basis==='usage_actual'?'Actual usage':it.basis==='credit'?'Credit':'Fixed'}</td>
            <td>{editable?<input aria-label={`Monthly cost for ${it.label}`} type="number" step="0.01" value={val} onChange={e=>setEdits({...edits,[it.key]:e.target.value})}/>:usd(it.monthly_usd)}</td>
            <td><small>{it.notes}</small></td>
            <td>{editable&&edits[it.key]!==undefined&&<button onClick={()=>save(it.key)} disabled={saving===it.key} aria-label={`Save cost for ${it.label}`}><Save size={13}/>Save</button>}</td></tr>})}
        <tr className="pr-total"><td>Total</td><td/><td>{usd(costs.total_monthly_usd)}</td><td colSpan={2}/></tr>
      </tbody></table>
      {!data.can_edit&&<p className="pr-note">Only a Platform Admin can change costs.</p>}{msg&&<p className="pr-ok">{msg}</p>}
    </div>
  </section>
}
