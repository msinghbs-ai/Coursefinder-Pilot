// CF-247 Boost queue (Platform Admin decision 18 Nov 2026 07:03): Platform health › Queues & yield. The Boost queue with Country tier and Priority score,
// worked out when the queue is read from the boost.matrix settings (country weight x category weight; tier 1 and tier 2 country lists). Nothing is stored on
// a course, and these two values are shown only here. Read-only: public.admin_boost_queue_read(args), Curator and above (migration 20261118083707).
import React,{useCallback,useEffect,useState}from'react'
import{supabase}from'./lib/supabase'
import{Button,EmptyInline,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'
import{plainError}from'./lib/errors'
import'./boost-queue.css'

const words=v=>v==null||v===''?'—':String(v).replace(/_/g,' ')
const STATE_TONE={verified:'success',rejected:'warning',failed:'danger',released:'neutral',claimed:'info',pending:'info'}
const PROMO={shadow:'Shadow (not admitted)',refused:'Refused',promoted:'Admitted',admitted:'Admitted'}
export const tierLabel=t=>t===1?'Tier 1':t===2?'Tier 2':'No tier'
const score=v=>fmtNumber(v,{maxDecimals:2})
export default function BoostQueue({onError,client=null}){
  const rpc=client||((fn,args)=>supabase.rpc(fn,args))
  const[d,setD]=useState(null),[err,setErr]=useState(''),[f,setF]=useState({offset:0,sort:'score',direction:'desc'})
  const load=useCallback(()=>{setErr('');Promise.resolve(rpc('admin_boost_queue_read',{p_args:f})).then(({data,error})=>{if(error){const m=plainError(error);setErr(m);onError?.(m)}else setD(data)}).catch(e=>setErr(plainError(e)))},[JSON.stringify(f)])
  useEffect(()=>{load()},[load])
  const set=(k,v)=>setF(x=>({...x,[k]:v,offset:0})),total=d?.total??0,page=d?.page_rows||50,from=total?f.offset+1:0,to=Math.min(f.offset+page,total)
  const filtered=Boolean(f.tier||f.country||f.lane||f.state),t=d?.tiers||{}
  return <section className="cf-card bq" data-boost-queue>
    <div className="bq-head"><div><h3>Boost queue</h3>
      <p className="sl-sub">Every item Boost has taken, with its <b>Country tier</b> and <b>Priority score</b>. Both are worked out now from the Boost priority settings (country weight × category weight); nothing is stored on a course.
        {d&&<> Tier 1: {(t.tier_1||[]).join(', ')||'none'}. Tier 2: {(t.tier_2||[]).join(', ')||'none'}.</>}</p></div>
      {d&&<span className="sl-sub" data-bq-count>{filtered?`${fmtNumber(total)} of ${fmtNumber(d.all_rows)}`:fmtNumber(d.all_rows)} items</span>}</div>
    {d&&d.summary?.length>0&&<div className="m-table-wrap"><table className="m-table bq-summary" data-bq-summary><thead><tr><th>Country tier</th><th>Country</th><th>Lane</th><th>Category</th><th>Priority score</th><th>Items</th><th>Not finished</th></tr></thead>
      <tbody>{d.summary.map((s,i)=><tr key={i}><td>{tierLabel(s.country_tier)}</td><td>{s.country_code||'—'}</td><td>{words(s.lane)}</td><td>{words(s.category)}</td><td>{score(s.priority_score)}</td><td>{fmtNumber(s.items)}</td><td>{fmtNumber(s.waiting)}</td></tr>)}</tbody></table></div>}
    <div className="bq-filters">
      <label>Country tier<select value={f.tier||''} onChange={e=>set('tier',e.target.value)} data-bq-tier><option value="">All</option><option value="1">Tier 1</option><option value="2">Tier 2</option><option value="none">No tier</option></select></label>
      <label>Country<select value={f.country||''} onChange={e=>set('country',e.target.value)} data-bq-country><option value="">All</option>{(d?.filters?.countries||[]).map(c=><option key={c} value={c}>{c}</option>)}</select></label>
      <label>Lane<select value={f.lane||''} onChange={e=>set('lane',e.target.value)} data-bq-lane><option value="">All</option>{(d?.filters?.lanes||[]).map(c=><option key={c} value={c}>{words(c)}</option>)}</select></label>
      <label>State<select value={f.state||''} onChange={e=>set('state',e.target.value)} data-bq-state><option value="">All</option>{(d?.filters?.states||[]).map(c=><option key={c} value={c}>{words(c)}</option>)}</select></label>
      <label>Sort by<select value={`${f.sort}:${f.direction}`} onChange={e=>{const[s,dir]=e.target.value.split(':');setF(x=>({...x,sort:s,direction:dir,offset:0}))}} data-bq-sort>
        <option value="score:desc">Priority score, highest first</option><option value="score:asc">Priority score, lowest first</option><option value="tier:asc">Country tier, tier 1 first</option><option value="done:desc">Finished, newest first</option></select></label>
      {filtered&&<Button compact onClick={()=>setF(x=>({offset:0,sort:x.sort,direction:x.direction}))} data-bq-clear>Clear</Button>}
    </div>
    {err?<EmptyInline text={err}/>:!d?<p className="sl-sub">Loading…</p>:!d.rows.length?<EmptyInline text={d.all_rows?'No item matches. Clear the filters.':'Boost has taken no items yet.'}/>:
      <div className="m-table-wrap"><table className="m-table" data-bq-table><thead><tr><th>Item</th><th>Country</th><th>Country tier</th><th>Lane</th><th>Category</th><th>Priority score</th><th>State</th><th>Staged answer</th><th>Finished</th></tr></thead>
        <tbody>{d.rows.map(r=><tr key={r.item_key} data-bq-row><td className="bq-title" title={r.item_key}>{r.title||r.item_key}</td><td>{r.country_code||'—'}</td>
          <td data-bq-row-tier={r.country_tier??'none'}>{r.country_tier?<StatusChip tone={r.country_tier===1?'success':'info'} label={tierLabel(r.country_tier)}/>:<span className="sl-sub">No tier</span>}</td>
          <td>{words(r.lane)}</td><td>{r.category_label||words(r.category)}</td><td data-bq-row-score>{score(r.priority_score)}</td>
          <td><StatusChip tone={STATE_TONE[r.state]||'neutral'} label={words(r.state)}/></td><td>{r.promotion_state?(PROMO[r.promotion_state]||words(r.promotion_state)):'—'}</td><td>{r.done_at?fmtDateTime(r.done_at):'Not finished'}</td></tr>)}</tbody></table></div>}
    {d&&total>page&&<div className="bq-pager" data-bq-pager><span className="sl-sub">{fmtNumber(from)} to {fmtNumber(to)} of {fmtNumber(total)}</span>
      <Button compact disabled={f.offset<=0} onClick={()=>setF(x=>({...x,offset:Math.max(0,x.offset-page)}))} data-bq-prev>Previous</Button>
      <Button compact disabled={to>=total} onClick={()=>setF(x=>({...x,offset:x.offset+page}))} data-bq-next>Next</Button></div>}
  </section>
}
