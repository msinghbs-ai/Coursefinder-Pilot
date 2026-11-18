// Platform health › Storage & retention, first panel (v2.16.40, Platform Admin 18 Nov 2026 12:50: "Make Storage & retention prominent and
// actionable"). Four figures at the top: database size and its 7-day change, the staging tables and their 7-day growth, whether nightly
// staging retention prunes or only reports (setting retention.staging_prune_on, changed with a reason on Settings), and its last run. The
// table by table detail is S2-Build's Staging tables panel further down (v2.16.39, admin_retention 'storage'). Reads only: that storage
// block, falling back to public.admin_ops_telemetry() (migration 20261117200000), and the sizes StorageSizes reads. It never calls the
// staging preview, because a preview that finds rows due is logged as a run.
import React,{useEffect,useState}from'react'
import{Database,HardDrive,Trash2}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Metric,SectionTitle,StatusChip,fmtNumber}from'./ui-kit'
import{fmtBytes,fmtDateTime}from'./lib/format.js'
import{plainError}from'./lib/errors'

// the staging tables nightly retention settles (security.staging_retention_v1) and the ledger it writes
export const STAGING_TABLES=[
  ['source_record_staging','Layer 1 staging','Rows a Layer 1 source read, kept until applied and past the keep period'],
  ['boost_inbound_staging','Boost staging','Answers the Boost worker brought in, kept until settled and past the keep period'],
  ['staging_hash_ledger','Hash ledger','The hash of every staging row removed, kept 7 years'],
]
const change=(now,before)=>{if(before==null||now==null)return null;return Number(now)-Number(before)}
const signed=d=>d==null?'No record a week ago':d===0?'No change in 7 days':`${d>0?'+':'−'}${fmtBytes(Math.abs(d))} in 7 days`
export const findTable=(tables,name)=>(tables||[]).find(t=>t.name===name||String(t.name).endsWith(`.${name}`))

export default function StagingRetention({sizes,storage,onError}){
  const[t,setT]=useState(null)
  useEffect(()=>{supabase.rpc('admin_ops_telemetry').then(({data,error})=>{if(error)throw error;setT(data||{})}).catch(e=>{setT({});onError?.(plainError(e))})},[])
  const p=storage?.prune,fromAdmin=p?{prune_on:Boolean(p.on),last:(p.last_runs||[]).find(x=>/^staging_retention/.test(String(x?.action||'')))||null}:null
  const s=fromAdmin||t?.staging_retention||{},last=s.last,d=last?.detail||{},daily=sizes?.daily||[]
  const ran=last?.action==='staging_retention',count=last?(d.removed!=null||d.would_remove!=null?Number(ran?d.removed:d.would_remove)||0:Number(d.source_record_staging?.[ran?'removed':'due']||0)+Number(d.boost_inbound_staging?.[ran?'removed':'due']||0)):0
  const weekAgo=sizes?daily.find(x=>x.day<=new Date(new Date(sizes.day).getTime()-7*864e5).toISOString().slice(0,10)):null
  const rows=STAGING_TABLES.map(([name,label,what])=>{const x=findTable(sizes?.tables,name);return{name,label,what,bytes:x?.bytes,rows:x?.rows,d7:change(x?.bytes,x?.bytes_7d_ago)}})
  const staged=rows.reduce((n,r)=>n+Number(r.bytes||0),0),grew=rows.reduce((n,r)=>n+Number(r.d7||0),0)
  return <section className="m-panel rt-summary" data-staging-retention>
    <SectionTitle icon={HardDrive} title="Storage now" subtitle="What the database holds, how fast staging grows, and whether nightly retention removes what has passed its keep period."/>
    <div className="cf-metric-grid">
      <Metric label="Database" icon={Database} value={sizes?fmtBytes(sizes.database_bytes):'…'} detail={sizes?signed(change(sizes.database_bytes,weekAgo?.database_bytes)):'Reading sizes'}/>
      <Metric label="Staging tables" icon={HardDrive} value={sizes?fmtBytes(staged):'…'} detail={sizes?signed(rows.some(r=>r.d7!=null)?grew:null):'Reading sizes'} tone={grew>0?'warning':'neutral'}/>
      <Metric label="Staging retention" icon={Trash2} value={t?(s.prune_on?'Prunes nightly':'Dry run only'):'…'} detail={t?(s.prune_on?'Rows past their keep period are removed at about 03:47; their hashes are kept 7 years.':'Nothing is removed: housekeeping-daily only counts what would go.'):''} tone={s.prune_on?'success':'warning'}/>
      <Metric label="Last retention run" value={last?fmtDateTime(last.at):t||fromAdmin?'None yet':'…'} detail={last?`${ran?'Removed':'Would remove'} ${fmtNumber(count)} rows`:'No staging row has reached its keep period yet.'}/>
    </div>
    {last&&<p className="sl-sub" data-staging-last><StatusChip value={last.action} tone={ran?'success':'info'} label={ran?'Pruned':'Dry run'}/> {fmtDateTime(last.at)}: {d.source_record_staging?`Layer 1 staging ${fmtNumber(d.source_record_staging.due||0)} due, ${fmtNumber(d.source_record_staging.removed||0)} removed; Boost staging ${fmtNumber(d.boost_inbound_staging?.due||0)} due, ${fmtNumber(d.boost_inbound_staging?.removed||0)} removed.`:`${ran?'removed':'would remove'} ${fmtNumber(count)} rows.`} Editions and evidence are never touched.</p>}
    <p className="sl-sub">To switch pruning on or change a keep period, use <a href="#environment?tab=settings" data-staging-settings>Settings</a> (Staging retention: prune, and the keep periods); each change asks for a reason. A source&rsquo;s own keep period is set when it is added in Layer 1. Table by table: Staging tables, below.</p>
  </section>
}
