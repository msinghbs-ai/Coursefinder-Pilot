// CF-247 Parallel Wave 2 (Platform Admin 17 Nov 2026 17:59): Platform health › Country & category completeness. One read
// (public.admin_completeness_report, Curator and above): how full each of the eight enrichment categories is in each country (from the daily field
// coverage snapshot), what each Layer 1 source keeps (editions, last change, retention), and how long Layer 4 items have waited.
// The Platform Admin can move a field to another category, with a reason. Nothing here prunes or loads anything.
import React,{useCallback,useEffect,useState}from'react'
import{RefreshCw}from'lucide-react'
import{Button,StatusChip,EmptyInline,fmtDate,fmtDateTime,fmtNumber}from'./ui-kit'
import{supabase}from'./lib/supabase'
import{plainError}from'./lib/errors'
import'./completeness-report.css'

const pct=v=>v==null?'—':`${Number(v).toFixed(1)}%`
const days=v=>v==null?'Permanent':`${fmtNumber(v)} days`
const words=v=>String(v||'—').replace(/_/g,' ')
const Bar=({v})=><span className="ccr-bar" aria-hidden="true"><span style={{width:`${Math.max(0,Math.min(100,Number(v)||0))}%`}}/></span>

export default function CompletenessReport({rank=0,onError,client=null}){
  const rpc=client||((fn,args)=>supabase.rpc(fn,args))
  const[d,setD]=useState(null),[err,setErr]=useState(''),[open,setOpen]=useState(null),[note,setNote]=useState(''),[ops,setOps]=useState(null)
  const load=useCallback(()=>{setErr('');Promise.resolve(rpc('admin_completeness_report',{})).then(({data,error})=>{if(error){const m=plainError(error);setErr(m);onError?.(m)}else setD(data)}).catch(e=>setErr(plainError(e)))},[])
  // S1-Build's operations telemetry (public.admin_ops_telemetry, Pilot migration 20261117200000): evidence captured and Layer 4 review items by source.
  // The two counts are shown side by side, never as one ratio (Platform Admin 17 Nov 2026 20:06): a source can capture evidence once and raise many items later.
  const loadOps=useCallback(()=>{Promise.resolve(rpc('admin_ops_telemetry',{})).then(({data,error})=>{setOps(error?{error:plainError(error)}:data)}).catch(e=>setOps({error:plainError(e)}))},[])
  useEffect(()=>{if(rank>=3){load();loadOps()}},[rank])
  if(rank<3)return <EmptyInline text="This report opens for Curator and above."/>
  if(err&&!d)return <EmptyInline text={err}/>
  if(!d)return <p className="sl-sub">Loading…</p>
  const cell=(cc,key)=>(d.cells||[]).find(c=>c.country_code===cc&&c.category_key===key)
  const cats=[...(d.categories||[]),...((d.cells||[]).some(c=>c.category_key==='unmapped')?[{key:'unmapped',label:'No category yet',description:'Coverage fields that are not in a category.'}]:[])]
  const sel=open?cell(open.cc,open.key):null
  async function move(field){const to=window.prompt(`Move "${field}" to which category?\n\n${(d.categories||[]).map(c=>`${c.key} = ${c.label}`).join('\n')}`);if(!to)return
    const why=window.prompt('Reason (kept in the control log):');if(!why||why.trim().length<4)return
    const{error}=await rpc('admin_enrichment_category_field_set',{p_field:field,p_category_key:to.trim(),p_reason:why.trim()});if(error){setNote(plainError(error));return}
    setNote(`${field} moved to ${to.trim()}.`);setOpen(null);load()}
  const l4=d.layer4||{}
  return <div className="ccr" data-completeness-report>
    <div className="ccr-bar-top"><p className="sl-sub">Field fill as measured on {d.snapshot_date?fmtDate(d.snapshot_date):'no snapshot yet'}, by country and enrichment category. Choose a figure to see its fields.</p>
      <Button compact onClick={()=>{load();loadOps()}} data-ccr-refresh><RefreshCw size={13}/> Refresh</Button></div>
    {note&&<p className="ccr-note" role="status" data-ccr-note>{note}</p>}
    <section className="cf-card ccr-card" data-ccr-matrix><h3>Field fill by country and category</h3>
      {(d.countries||[]).length?<div className="ccr-scroll"><table className="cf-table"><thead><tr><th>Category</th>{d.countries.map(cc=><th key={cc} className="num">{cc}</th>)}</tr></thead>
        <tbody>{cats.map(k=><tr key={k.key} data-ccr-category={k.key}><th scope="row" title={k.description}>{k.label}</th>{d.countries.map(cc=>{const c=cell(cc,k.key);return <td key={cc} className="num">{c?<button type="button" className="ccr-cell" aria-pressed={open?.cc===cc&&open?.key===k.key} onClick={()=>setOpen(open?.cc===cc&&open?.key===k.key?null:{cc,key:k.key})} data-ccr-cell={`${cc}:${k.key}`}><Bar v={c.pct}/>{pct(c.pct)}</button>:<span className="ccr-none">Not measured</span>}</td>})}</tr>)}</tbody></table></div>
        :<EmptyInline text="No field coverage has been measured yet."/>}
      {sel&&<div className="ccr-detail" data-ccr-detail><h4>{cats.find(k=>k.key===open.key)?.label} in {open.cc}: {fmtNumber(sel.filled)} of {fmtNumber(sel.total)} values held ({pct(sel.pct)})</h4>
        <table className="cf-table"><thead><tr><th>Field</th><th className="num">Held</th><th className="num">Of</th><th className="num">Fill</th>{rank>=6&&<th></th>}</tr></thead>
          <tbody>{sel.fields.map(x=><tr key={x.field}><td>{x.label}</td><td className="num">{fmtNumber(x.filled)}</td><td className="num">{fmtNumber(x.total)}</td><td className="num"><Bar v={x.pct}/>{pct(x.pct)}</td>{rank>=6&&<td><Button compact onClick={()=>move(x.field)} data-ccr-move={x.field}>Change category</Button></td>}</tr>)}</tbody></table></div>}
    </section>
    <section className="cf-card ccr-card" data-ccr-editions><h3>Layer 1 sources: editions, last change and retention</h3>
      {(d.editions||[]).length?<div className="ccr-scroll"><table className="cf-table"><thead><tr><th>Source</th><th>Country</th><th>Current edition</th><th className="num">Editions kept</th><th>Last checked</th><th className="num">Records before</th><th className="num">Records now</th><th>Change</th><th>Staging kept</th><th>Removed-row hashes kept</th></tr></thead>
        <tbody>{d.editions.map(e=><tr key={e.source_id} data-ccr-source={e.source_id}><td>{e.label}{e.paused&&<> <StatusChip tone="neutral" label="Paused"/></>}</td><td>{e.country_code||'—'}</td><td>{e.current_edition||'—'}</td><td className="num">{fmtNumber(e.editions_kept||0)}</td>
          <td>{e.last_verified_at?fmtDateTime(e.last_verified_at):'Not checked'}</td><td className="num">{e.previous_count==null?'—':fmtNumber(e.previous_count)}</td><td className="num">{e.last_count==null?'—':fmtNumber(e.last_count)}</td>
          <td>{e.variance_percent==null?'—':`${Number(e.variance_percent).toFixed(1)}%`} {e.variance_decision&&e.variance_decision!=='unknown'?<StatusChip tone={e.variance_decision==='block'?'danger':e.variance_decision==='warn'?'warning':'success'} label={words(e.variance_decision)}/>:null}</td>
          <td>{days(e.retention?.staging_keep_days)}{e.retention?.per_source&&<small className="ccr-sub">set for this source</small>}</td><td>{e.retention?.raw_hash_keep_years==null?'—':`${fmtNumber(e.retention.raw_hash_keep_years)} years`}</td></tr>)}</tbody></table></div>
        :<EmptyInline text="No Layer 1 source is registered."/>}
      <p className="sl-sub">Staging kept is the source&rsquo;s own period where one is set (Storage &amp; retention, or the Add source wizard), otherwise the platform period of {d.retention_settings?.staging_keep_days??'—'} days. Nightly pruning is {d.retention_settings?.staging_prune_on?'on':'off: it reports what would go'}. Accepted editions and evidence are never pruned.</p>
    </section>
    <section className="cf-card ccr-card" data-ccr-evidence-items><h3>Evidence captured and Layer 4 review items, by source</h3>
      <p className="sl-sub">Counted over the last {ops?.window_days??'—'} days. The two figures are separate counts: one stored page or file can raise many review items, and items can be raised long after the evidence was captured, so they are not divided into a rate.</p>
      {!ops?<p className="sl-sub">Loading…</p>:ops.error?<EmptyInline text={`Not measured: ${ops.error}`}/>:(ops.l4_escalation_by_source||[]).length?<div className="ccr-scroll"><table className="cf-table"><thead><tr><th>Source</th><th>Country</th><th className="num">Evidence captures</th><th className="num">Layer 4 review items</th><th className="num">Waiting for a person</th><th className="num">Waiting too long</th><th className="num">Approved</th><th className="num">Rejected</th><th className="num">Sent back</th><th className="num">Superseded</th><th>Oldest waiting</th></tr></thead>
        <tbody>{ops.l4_escalation_by_source.map((x,i)=><tr key={x.source_id||`none-${i}`} data-ccr-ei={x.source_id||'none'}><td>{x.source_label}</td><td>{x.country_code||'—'}</td><td className="num" data-ccr-evidence>{fmtNumber(x.evidence_captured||0)}</td><td className="num" data-ccr-items>{fmtNumber(x.layer4_items||0)}</td>
          <td className="num">{fmtNumber(x.pending||0)}</td><td className="num">{fmtNumber(x.pending_aged||0)}</td><td className="num">{fmtNumber(x.approved||0)}</td><td className="num">{fmtNumber(x.rejected||0)}</td><td className="num">{fmtNumber(x.returned||0)}</td><td className="num">{fmtNumber(x.superseded||0)}</td><td>{x.oldest_pending?fmtDate(x.oldest_pending):'—'}</td></tr>)}</tbody></table></div>
        :<EmptyInline text="No evidence was captured and no review item raised in this period."/>}
    </section>
    <section className="cf-card ccr-card" data-ccr-layer4><h3>Layer 4 queue: how long items have waited</h3>
      <p className="sl-sub">{fmtNumber(l4.pending||0)} items wait for a person{l4.oldest_at?`; the oldest since ${fmtDate(l4.oldest_at)}`:''}. Waiting is more than {l4.warn_days} days; old is more than {l4.old_days} days.</p>
      {(l4.by_type||[]).length?<table className="cf-table"><thead><tr><th>Kind</th><th className="num">Waiting for a person</th><th className="num">Up to {l4.warn_days} days</th><th className="num">Waiting</th><th className="num">Old</th><th>Oldest</th></tr></thead>
        <tbody>{l4.by_type.map(x=><tr key={x.entity_type} data-ccr-l4={x.entity_type}><td>{words(x.entity_type)}</td><td className="num">{fmtNumber(x.pending)}</td><td className="num">{fmtNumber(x.fresh)}</td><td className="num">{fmtNumber(x.waiting)}</td><td className="num">{fmtNumber(x.old)}</td><td>{x.oldest_at?fmtDate(x.oldest_at):'—'}</td></tr>)}</tbody></table>
        :<EmptyInline text="Nothing waits in Layer 4."/>}
    </section>
  </div>
}
