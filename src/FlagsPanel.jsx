// CF-247 (15 Oct 2026): Coverage & completeness › Flags. Platform Admin, 15 Oct 2026 15:20: "have flag unit that can be removed or raised
// manually and automatically by tried burn. evidence of that flag will details why it was raised or released manually and the said entry or
// provider get re-entered in queue." A raised flag holds a provider, a course field or a job out of every queue; release puts it back.
import React,{useEffect,useState}from'react'
import{Flag,History,RotateCcw,ShieldOff,X}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Metric,Pager,StatusChip,EmptyInline,fmtDateTime}from'./ui-kit'
import{fmtNumber}from'./lib/format.js'
import'./FlagsPanel.css'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const call=(action,args={})=>supabase.rpc('admin_flags',{p_action:action,p_args:args}).then(({data,error})=>{if(error)throw error;return data})
export const REASONS={course_pages_not_found:'Course pages not found',
 enrich_no_value:'Page gives no value (Enrich fields)',outside_focus:'Outside the focus providers',page_not_found:'No course page found',
 logo_not_found:'No logo on the home page',site_unreachable:'Website does not answer',central_not_due:'Central pages not due',central_budget:'No credit left today',
 idle_paused:'Job ran empty',manual_hold:'Held by a person',fee_crosscheck:'Fee fails the cross-check',policy_disagrees:'Policy disagrees with pages',
 adapter_fee_fails_check:'Adapter fee fails its check',flip_flop:'Value kept changing',
 course_pages_not_listed:'Search off: the site lists too few course pages',not_on_provider_site:'Not on the provider\'s site',not_offered:'Not offered'}
// v2.15.310 (Platform Admin, 22 Oct 2026 08:12): each flag shows the toolset used on the university or course before it was flagged
export const TOOL_LABELS={course_search:'Course-page search',page_reads:'Page reads',ai_page_match:'AI page match',ai_field_reader:'AI field reader',
 fee_reader:'Fee reader',scholarship_ai:'Scholarship AI',other_credits:'Other scraper credits',flags_raised:'Flags raised'}
const n0=v=>Number(v||0)
// one line for the table: the tools that ran, "used · worked / did not work · credits"
export const toolLine=t=>{if(!t)return'';const parts=(t.tools||[]).filter(x=>x.tool!=='flags_raised'&&(n0(x.used)||n0(x.credits))).map(x=>`${TOOL_LABELS[x.tool]||x.tool} ${fmtNumber(n0(x.used))}× (${fmtNumber(n0(x.ok))} worked, ${fmtNumber(n0(x.failed))} did not)${n0(x.credits)?` · ${fmtNumber(n0(x.credits))} credits`:''}`)
 const sm=t.site_map;if(sm)parts.unshift(sm.status==='failed'?'Site map failed':`Site lists ${fmtNumber(n0(sm.pages))} pages, ${fmtNumber(n0(sm.course_pages))} course-like`)
 return parts.join(' · ')}
function ToolTable({t}){
 if(!t||!(t.tools||[]).length&&!t.site_map)return null
 return <div className="cf-flag-tools" data-flag-tools><p><b>Toolset used before this flag</b>{t.scope==='provider'&&t.since?` (since ${t.since})`:''}</p>
  {t.site_map&&<p className="cf-flag-site">{t.site_map.status==='failed'?'The site map failed: no course pages could be listed.':`The provider's site lists ${fmtNumber(n0(t.site_map.pages))} pages, of which ${fmtNumber(n0(t.site_map.course_pages))} look like course pages.`}</p>}
  {(t.tools||[]).length>0&&<table className="dense-table"><thead><tr><th>Tool</th><th>Used</th><th>Worked</th><th>Did not work</th><th>Credits</th><th>AI cost</th></tr></thead>
   <tbody>{t.tools.map(x=><tr key={x.tool}><td>{TOOL_LABELS[x.tool]||x.tool}{x.note&&<small> · {x.note}</small>}</td><td>{fmtNumber(n0(x.used))}</td><td>{fmtNumber(n0(x.ok))}</td><td>{fmtNumber(n0(x.failed))}</td><td>{fmtNumber(n0(x.credits))}</td><td>{n0(x.cost_usd)?n0(x.cost_usd).toFixed(3):'—'}</td></tr>)}</tbody></table>}
 </div>}
const reasonLabel=c=>REASONS[c]||String(c||'').replace(/_/g,' ')
const what=f=>f.entity==='job'?`Job ${f.entity_key}`:f.entity==='course'?`${f.course_title||'Course'}${f.field?' · '+f.field.replace(/_/g,' '):''}`:f.entity==='provider'?(f.provider_name||'Provider'):`${f.entity} ${f.entity_key}`
const tone=s=>s==='raised'?'warning':s==='counting'?'info':'success'
const stateLabel=s=>s==='raised'?'Held':s==='counting'?'Tried once':'Released'

function FlagHistory({id,onClose}){
 const[d,setD]=useState(null),[err,setErr]=useState('')
 useEffect(()=>{call('events',{id}).then(setD).catch(e=>setErr(errText(e)))},[id])
 return <div className="cf-flag-history-backdrop" onClick={e=>{if(e.target===e.currentTarget)onClose()}}><section className="cf-flag-history" role="dialog" aria-modal="true" aria-label="Flag history">
  <header><h3>Flag history</h3><button onClick={onClose} aria-label="Close"><X size={16}/></button></header>
  {err&&<p className="cf-flag-err">{err}</p>}
  {d?.flag&&<p className="cf-flag-head"><b>{reasonLabel(d.flag.reason_code)}</b> · {d.flag.reason}</p>}
  <ToolTable t={d?.tools}/>
  {d?.flag?.evidence&&Object.keys(d.flag.evidence).length>0&&<details open><summary>Evidence</summary><pre>{JSON.stringify(d.flag.evidence,null,2)}</pre></details>}
  <ol className="cf-flag-events">{(d?.events||[]).map(e=><li key={e.id}><span><StatusChip tone={e.action==='released'||e.action==='requeued'?'success':e.action==='counted'?'info':'warning'} label={e.action.replace(/_/g,' ')}/> {fmtDateTime(e.at)} · {e.actor_kind==='person'?'by ':''}{e.actor}</span><span>{e.reason}</span>{e.evidence&&Object.keys(e.evidence).length>0&&<pre>{JSON.stringify(e.evidence,null,2)}</pre>}</li>)}</ol>
  {!d&&!err&&<p>Loading…</p>}
 </section></div>
}

export default function FlagsPanel({onError}){
 const[summary,setSummary]=useState(null),[data,setData]=useState(null),[state,setState]=useState('raised'),[entity,setEntity]=useState(''),[reason,setReason]=useState(''),[q,setQ]=useState(''),[offset,setOffset]=useState(0)
 const[picked,setPicked]=useState([]),[note,setNote]=useState(''),[busy,setBusy]=useState(false),[history,setHistory]=useState(null),[raise,setRaise]=useState(null)
 const load=()=>{setBusy(true);return Promise.all([call('summary'),call('list',{state,entity,reason_code:reason,q,limit:50,offset})]).then(([s,l])=>{setSummary(s);setData(l)}).catch(e=>onError?.(errText(e))).finally(()=>setBusy(false))}
 useEffect(()=>{load()},[state,entity,reason,offset])
 useEffect(()=>{const t=setTimeout(()=>{setOffset(0);load()},300);return()=>clearTimeout(t)},[q])
 useEffect(()=>{setPicked([]);},[state,entity,reason,offset,q])
 const can=Boolean(summary?.can_change),rel=summary?.release_codes||[],canRel=f=>can||rel.includes('*')||rel.includes(f?.reason_code),relAny=can||rel.length>0,rows=data?.items||[],held=(summary?.by_reason||[]).reduce((a,x)=>a+Number(x.held||0),0)
 const reasons=[...new Set((summary?.by_reason||[]).map(x=>x.reason_code))]
 async function release(ids){const why=prompt(`Release ${ids.length} flag${ids.length>1?'s':''} and put ${ids.length>1?'them':'it'} back in the queue. Reason (kept with the flag):`);if(!why)return
  try{const r=await call('release',{ids,reason:why});setNote(`${r.released} released and re-queued.`);setPicked([]);load()}catch(e){setNote('Not released: '+errText(e))}}
 return <div className="m-page-stack" data-flags>
  <div className="cf-metric-grid">
   <Metric label="Held now" value={busy&&!summary?'…':fmtNumber(held)} detail="Out of every queue until released" icon={Flag} tone={held?'warning':'success'}/>
   <Metric label="Raised in 24 hours" value={fmtNumber((summary?.last_24h?.raised||0)+(summary?.last_24h?.re_raised||0))} detail={`${fmtNumber(summary?.last_24h?.counted||0)} first tries counted`}/>
   <Metric label="Released in 24 hours" value={fmtNumber(summary?.last_24h?.released||0)} detail="Input changed, site back, due, or by a person" icon={RotateCcw} tone="success"/>
  </div>
  <section className="m-panel">
   <div className="m-workspace-head"><div><h2>Flags</h2><p>Work that keeps failing is held here instead of being tried again. Each item is released automatically when its input changes, its website answers a free check, or its date comes; a person can release or hold anything, with a reason. Released items go back in their queue. Settings: Pipeline settings › Flags.</p></div>
    {can&&<button className="m-secondary compact" onClick={()=>setRaise({entity:'provider',key:'',label:'',reason:'',options:[]})}><ShieldOff size={14}/>Hold a provider or job</button>}</div>
   <div className="cf-flag-reasons">{(summary?.by_reason||[]).filter(x=>Number(x.held)+Number(x.counting)>0).map(x=><button key={x.entity+x.reason_code} className={reason===x.reason_code?'active':''} onClick={()=>{setReason(reason===x.reason_code?'':x.reason_code);setOffset(0)}}><b>{fmtNumber(Number(x.held))}</b> {reasonLabel(x.reason_code)}{Number(x.counting)>0&&<small> · {fmtNumber(Number(x.counting))} tried once</small>}</button>)}</div>
   <div className="m-search-row cf-flag-filters">
    <input className="cf-flag-search" value={q} onChange={e=>setQ(e.target.value)} placeholder="Search provider, course or job…"/>
    <label>State<select value={state} onChange={e=>{setState(e.target.value);setOffset(0)}}><option value="raised">Held</option><option value="counting">Tried once</option><option value="released">Released</option><option value="">All</option></select></label>
    <label>On<select value={entity} onChange={e=>{setEntity(e.target.value);setOffset(0)}}><option value="">Everything</option><option value="provider">Providers</option><option value="course">Course fields</option><option value="job">Jobs</option></select></label>
    <label>Reason<select value={reason} onChange={e=>{setReason(e.target.value);setOffset(0)}}><option value="">All reasons</option>{reasons.map(r=><option key={r} value={r}>{reasonLabel(r)}</option>)}</select></label>
    {relAny&&picked.length>0&&<button className="m-secondary compact" onClick={()=>release(picked)}><RotateCcw size={14}/>Release {picked.length}</button>}
   </div>
   {note&&<p className="cf-flag-note" role="status">{note}</p>}
   <div className="dense-table-wrap"><table className="dense-table"><thead><tr>{relAny&&<th/>}<th><span>Held item</span></th><th><span>Reason</span></th><th><span>State</span></th><th><span>Raised</span></th><th><span>Next check</span></th><th><span>History</span></th></tr></thead><tbody>
    {rows.length?rows.map(f=><tr key={f.id} data-flag-row={f.state}>
     {relAny&&<td>{f.state!=='released'&&canRel(f)&&<input type="checkbox" aria-label="Select" checked={picked.includes(f.id)} onChange={e=>setPicked(p=>e.target.checked?[...p,f.id]:p.filter(x=>x!==f.id))}/>}</td>}
     <td className="primary-cell"><strong>{what(f)}</strong>{f.entity==='course'&&f.provider_name&&<small> · {f.provider_name}</small>}</td>
     <td><b>{reasonLabel(f.reason_code)}</b><br/><small>{f.reason}</small>{f.tools&&toolLine(f.tools)&&<><br/><small className="cf-flag-toolline" data-flag-toolline>Tried: {toolLine(f.tools)}</small></>}</td>
     <td><StatusChip tone={tone(f.state)} label={stateLabel(f.state)}/>{f.kind==='soft'&&f.state!=='released'&&<small> {f.tries} {f.tries===1?'try':'tries'}</small>}{f.state==='released'&&<small><br/>{f.release_kind==='person'?'by '+f.released_by:f.release_reason}</small>}</td>
     <td>{fmtDateTime(f.flagged_at)}<br/><small>{f.raised_by_kind==='person'?'by ':''}{f.raised_by}</small></td>
     <td>{f.state==='raised'?(f.next_check_at?fmtDateTime(f.next_check_at):<small>{f.entity==='course'?'when the page changes':'when released'}</small>):'—'}</td>
     <td><button className="m-secondary compact" onClick={()=>setHistory(f.id)}><History size={13}/>History</button>{canRel(f)&&f.state!=='released'&&<button className="m-secondary compact" onClick={()=>release([f.id])}>Release</button>}</td>
    </tr>):<tr><td colSpan={relAny?7:6}><EmptyInline text={busy?'Loading…':'No flags match.'}/></td></tr>}
   </tbody></table></div>
   <Pager offset={offset} limit={50} total={Number(data?.total||0)} onOffset={setOffset}/>
  </section>
  {history&&<FlagHistory id={history} onClose={()=>setHistory(null)}/>}
  {raise&&<div className="cf-flag-history-backdrop" onClick={e=>{if(e.target===e.currentTarget)setRaise(null)}}><section className="cf-flag-history" role="dialog" aria-modal="true" aria-label="Hold a provider or job">
   <header><h3>Hold a provider or job</h3><button onClick={()=>setRaise(null)} aria-label="Close"><X size={16}/></button></header>
   <p>A held provider is left out of every enrichment queue; a held job is switched off. Nothing is retried until a person releases it.</p>
   <label>Hold<select value={raise.entity} onChange={e=>setRaise({...raise,entity:e.target.value,key:'',label:'',options:[]})}><option value="provider">A provider</option><option value="job">A job</option></select></label>
   <label>{raise.entity==='job'?'Job':'Provider'}<input value={raise.label} placeholder="Type to search…" onChange={async e=>{const v=e.target.value;setRaise(r=>({...r,label:v,key:''}));if(v.length>1){const t=await call('targets',{q:v}).catch(()=>null);setRaise(r=>({...r,options:(raise.entity==='job'?t?.jobs:t?.providers)||[]}))}}}/></label>
   {raise.options.length>0&&!raise.key&&<div className="cf-flag-options">{raise.options.map(o=><button key={o.key} onClick={()=>setRaise(r=>({...r,key:o.key,label:o.label,options:[]}))}>{o.label}</button>)}</div>}
   <label>Reason (kept with the flag)<input value={raise.reason} onChange={e=>setRaise({...raise,reason:e.target.value})}/></label>
   <div className="cf-flag-actions"><button onClick={()=>setRaise(null)}>Cancel</button><button className="primary" disabled={!raise.key||raise.reason.trim().length<4} onClick={async()=>{try{await call('raise',{entity:raise.entity,key:raise.key,reason:raise.reason});setNote(`${raise.label} held.`);setRaise(null);load()}catch(e){setNote('Not held: '+errText(e));setRaise(null)}}}>Hold</button></div>
  </section></div>}
 </div>
}
