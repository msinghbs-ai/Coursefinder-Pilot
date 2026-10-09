import React,{useEffect,useMemo,useState}from'react'
import{StatusChip,Empty,Metric}from'./ui-kit'
import{Check,ExternalLink,RefreshCw,Route,ShieldCheck}from'lucide-react'
import{supabase}from'./lib/supabase'
import ScheduledJobsWorkspace from'./ScheduledJobsWorkspace'
import{useRememberedState}from'./ui-kit'
import{Layer4MassOperations}from'./layer4-mass-operations-entry'
import'./m2-3-intelligence.css'
import{fmtNumber,fmtDateTime,fmtDayMonth}from'./lib/format.js'

const human=v=>String(v??'').replaceAll('_',' ').replace(/\b\w/g,x=>x.toUpperCase())
const when=v=>v?fmtDateTime(v):'—'
const rpc=async(name,args={})=>{const{data,error}=await supabase.rpc(name,args);if(error)throw error;return data}
// Clean-up batch 2 (9 Oct 2026): the never-mounted self-mount entry and the unused Layer3, Links, Dates and
// ProviderCredential exports were removed; mature-main.jsx uses Layer4, Refresh and Onboarding only.
const askReason=label=>window.prompt(`${label} — reason (required)`,'M2.3 governed decision')||''

export function Layer4({onError,rank=0}){
 // L4-A review desk: one decision at a time, with the facts that settle it.
 const[data,setData]=useState({items:[],summary:{}}),[reviewer,setReviewer]=useState(null),[selectedId,setSelectedId]=useState(null),[context,setContext]=useState(null),[note,setNote]=useState(''),[busy,setBusy]=useState(false)
 useEffect(()=>{let live=true;supabase.auth.getSession().then(({data:s})=>{if(live)setReviewer(s?.session?.user?.id||'anonymous')});return()=>{live=false}},[])
 const[filtersState,rememberFilters,clearFilters]=useRememberedState('layer4-review',{status:'pending',task:'',view:'review',who:'all'},{userId:reviewer})
 const{status,task,view,who}=filtersState
 const[scopeQuery,setScopeQuery]=useState(''),[claimInfo,setClaimInfo]=useState(null),[edit,setEdit]=useState(null),[panelError,setPanelError]=useState('')
 // L4-C batches: grouped by task and suggestion; preview, untick, reason, typed confirmation.
 const[batches,setBatches]=useState({groups:[],can_apply:false}),[preview,setPreview]=useState(null),[batchMsg,setBatchMsg]=useState('')
 // L4-D team and forecast (read-only).
 const[team,setTeam]=useState(null),[teamDays,setTeamDays]=useState(7)
 useEffect(()=>{if(view==='team')rpc('layer4_team_forecast_v1',{p_days:teamDays}).then(setTeam).catch(onError)},[view,teamDays])
 const loadBatches=async()=>{try{setBatches(await rpc('layer4_review_batches_v1')||{groups:[]})}catch(e){onError(e)}}
 useEffect(()=>{if(view==='batches')loadBatches()},[view])
 const openPreview=g=>{const ids=(g.item_ids||[]).slice(0,100);const act=['reject','approve','return_layer3'].includes(g.action)?(g.action==='approve'&&!g.can_approve?'':g.action):'';setBatchMsg('');setPreview({group:g,picked:new Set(ids),action:act,reason:act?`Batch: ${g.text}`:'',confirm:''})}
 const applyBatch=async()=>{const ids=[...preview.picked];try{const r=await rpc('layer4_batch_decide_v1',{p_item_ids:ids,p_action:preview.action,p_reason:preview.reason,p_confirmation:preview.confirm,p_batch_label:`${preview.group.task} · ${preview.group.text}`});setBatchMsg(`Done: ${r?.decided||ids.length} item(s) decided (${human(preview.action)}).`);setPreview(null);await loadBatches();await load()}catch(e){onError(e)}}
 const load=async(keepId=null)=>{setBusy(true);try{const r=await rpc('layer4_review_desk_v1',{p_status:status||'',p_limit:250});const next=r||{items:[],summary:{}};setData(next);const items=(next.items||[]).filter(i=>!task||i.task===task);const keep=keepId&&items.find(i=>i.id===keepId);setSelectedId(keep?keep.id:(items[0]?.id||null))}catch(e){onError(e)}finally{setBusy(false)}}
 useEffect(()=>{load()},[status])
 const items=useMemo(()=>(data.items||[]).filter(i=>(!task||i.task===task)&&(who==='all'||(who==='mine'?i.claimed_by_me:!i.claim_active||i.claimed_by_me))),[data,task,who])
 const tasks=useMemo(()=>Object.entries(data.summary?.by_task||{}),[data])
 const current=items.find(i=>i.id===selectedId)||null
 const target=Number(data.summary?.target_days||7)
 const suggestedCount=a=>(data.items||[]).filter(i=>i.status==='pending'&&i.suggestion?.action===a).length
 useEffect(()=>{setClaimInfo(null);setEdit(null);setPanelError('');if(current&&current.status==='pending')rpc('layer4_claim_v1',{p_review_item_id:current.id}).then(r=>{if(r&&r.ok===false&&r.reason==='claimed')setClaimInfo(r);else if(r&&r.ok)setData(d=>({...d,items:(d.items||[]).map(i=>i.id===current.id?{...i,claimed_by_me:true,claim_active:true}:i)}))}).catch(()=>{})},[selectedId])
 useEffect(()=>{setContext(null);setNote(current?.suggestion?.action&&current.suggestion.action!=='check'?current.suggestion.text:'');if(current)rpc('layer4_review_context',{p_review_item_id:current.id}).then(setContext).catch(()=>{})},[selectedId])
 const isContact=r=>r?.technical?.layer2_state&&r?.field_code==='provider_contact_reconciliation'
 const asRow=r=>({...r,entity_type:r?.entity?.type,layer2_state:r?.technical?.layer2_state,proposed_value:r?.technical?.proposed_value})
 const nextAfter=id=>{const i=items.findIndex(x=>x.id===id);return (items[i+1]||items[i-1]||null)?.id||null}
 const decide=async(row,action,label,prepared,reasonOverride)=>{
   setPanelError('')
   const reason=(reasonOverride??note??'').trim();if(reason.length<5){setPanelError('Add a short note (at least 5 characters) saying why, then try again.');return}
   let final=null
   if(action==='edit_and_approve'&&prepared!==undefined){final=prepared}else if(action==='edit_and_approve'){const raw=window.prompt('Final value (JSON)',JSON.stringify(row.technical?.proposed_value));if(raw===null)return;try{final=JSON.parse(raw)}catch{return onError(new Error('Final value must be valid JSON'))}}
   try{const nextId=nextAfter(row.id);await rpc('layer4_review_decide',{p_review_item_id:row.id,p_action:action,p_reason:reason,p_final_value:final});setEdit(null);await load(nextId)}catch(e){setPanelError(`Not saved: ${e?.message||e}`)}
 }
 const contactDecide=async(row,action,targetProviderId=null,targetContactId=null)=>{
   const labels={merge_existing:'Merge with existing',accept_incoming:'Accept incoming as current',keep_existing:'Keep existing',keep_separate:'Keep as separate contact',map_provider_apply:'Map Provider and apply incoming',reject_import:'Reject import row'}
   const reason=askReason(labels[action]||human(action));if(!reason)return
   try{
     const{error}=await supabase.rpc('provider_contact_reconciliation_decide',{
       p_review_item_id:row.id,p_action:action,p_reason:reason,
       p_target_provider_id:targetProviderId||null,p_target_contact_id:targetContactId||null,
     })
     if(error)throw error
     await load(nextAfter(row.id))
   }catch(e){onError(e)}
 }
 const contactActions=row=>{
   const classification=row.layer2_state?.classification
   const candidates=Array.isArray(row.layer2_state?.candidate_providers)?row.layer2_state.candidate_providers:[]
   if(classification==='provider_ambiguous')return <div className="m23-actions">
     {candidates.map(p=><button key={p.provider_id} onClick={e=>{e.stopPropagation();contactDecide(row,'map_provider_apply',p.provider_id)}}>Map & apply · {p.provider_name||p.stable_key}</button>)}
     <button onClick={e=>{e.stopPropagation();contactDecide(row,'reject_import')}}>Reject import</button>
   </div>
   return <div className="m23-actions">
     <button onClick={e=>{e.stopPropagation();contactDecide(row,'merge_existing')}}>Merge · keep existing</button>
     <button onClick={e=>{e.stopPropagation();contactDecide(row,'accept_incoming')}}>Accept incoming</button>
     <button onClick={e=>{e.stopPropagation();contactDecide(row,'keep_existing')}}>Keep existing</button>
     <button onClick={e=>{e.stopPropagation();contactDecide(row,'keep_separate')}}>Keep separate</button>
     <button onClick={e=>{e.stopPropagation();contactDecide(row,'reject_import')}}>Reject import</button>
   </div>
 }
 const actionsFor=r=>{
   const main=[['reject','Reject'],['approve','Approve'],['edit_and_approve','Edit and approve']]
   const s=r.suggestion?.action
   const editOnly=r.can_approve===false&&hasForm(r)
   const allowed=r.can_approve===false?main.filter(([a])=>a==='reject'||(a==='edit_and_approve'&&editOnly)):main
   const ordered=(s==='approve'?[main[1],main[0],main[2]]:main).filter(x=>allowed.includes(x))
   return <div className="l4d-actions">
     {s==='return_layer3'&&<button className="l4d-primary" onClick={()=>decide(r,'return_layer3','Send back to AI check (Layer 3)')}>Send back for AI check</button>}
     {ordered.map(([a,l],i)=><button key={a} className={(s===a||(editOnly&&a==='edit_and_approve'))&&s!=='return_layer3'?'l4d-primary':''} onClick={()=>a==='edit_and_approve'&&hasForm(r)?openEdit(r):decide(r,a,l)}>{l}</button>)}
     <details className="l4d-more"><summary>More</summary><div>
       <button onClick={()=>decide(r,'request_more_evidence','Ask for more evidence')}>Ask for more evidence</button>
       <button onClick={()=>decide(r,'return_layer2','Send back to enrichment (Layer 2)')}>Send back to enrichment (Layer 2)</button>
       <button onClick={()=>decide(r,'return_layer3','Send back to AI check (Layer 3)')}>Send back to AI check (Layer 3)</button>
     </div></details>
   </div>
 }
 const hasForm=r=>['provider_current_tuition_validation','official_course_url'].includes(r?.field_code)
 const openEdit=r=>{if(r?.field_code==='official_course_url'){const v=r?.technical?.proposed_value;setEdit({kind:'link',url:typeof v==='string'?v:(v?.url||''),note:'Found the official course page on the provider\'s website'});return}const v=r?.technical?.proposed_value||{};setEdit({amount:v.amount??'',currency_code:v.currency_code||'AUD',fee_year:v.fee_year??'',basis:['annual','indicative_annual'].includes(v.basis)?v.basis:'annual',audience:v.audience||'international',note:`Checked the page: fee confirmed${v.amount?` as ${v.amount}`:''}`})}
 const saveEdit=r=>{if(edit?.kind==='link'){const u=(edit.url||'').trim();if(!/^https:\/\/[^\s/]+\.[^\s/]+/i.test(u))return setPanelError('Enter the full https:// address of the provider\'s course page.');return decide(r,'edit_and_approve','Edit and approve',u,edit.note)}const amt=Number(edit.amount),yr=edit.fee_year===''?null:Number(edit.fee_year);if(!(amt>0))return setPanelError('Enter a fee amount greater than 0.');if(yr!==null&&!(yr>=2024&&yr<=2030))return setPanelError('Fee year must be between 2024 and 2030, or blank.');decide(r,'edit_and_approve','Edit and approve',{amount:amt,currency_code:edit.currency_code,basis:edit.basis,fee_year:yr,audience:edit.audience},edit.note)}
 // Keyboard: R reject, A approve, E edit, N next (not while typing).
 useEffect(()=>{if(view!=='review')return;const h=e=>{const t=e.target?.tagName;if(['INPUT','TEXTAREA','SELECT'].includes(t)||e.ctrlKey||e.metaKey||e.altKey)return;const k=e.key.toLowerCase();if(k==='n'){const n=nextAfter(selectedId);if(n)setSelectedId(n);return}
   if(!current||current.status!=='pending'||claimInfo)return;if(k==='r')decide(current,'reject','Reject');else if(k==='a'&&current.can_approve!==false)decide(current,'approve','Approve');else if(k==='e'&&hasForm(current))openEdit(current)}
   addEventListener('keydown',h);return()=>removeEventListener('keydown',h)},[view,selectedId,current,claimInfo,note])
 const title=r=>r?.entity?.title||r?.entity?.provider||r?.task
 const chip=a=>a==='reject'?'Suggest reject':a==='approve'?'Suggest approve':a==='return_layer3'?'Suggest send back':'Check'
 return <div className="m23-stack">
   <LayerWorkspaceHeader layer="4" eyebrow="Layer 4 · governed human resolution" title="Layer 4 — Human Resolution" subtitle="Decide the items automation could not settle. Each decision is recorded with its reason and can be reversed." onRefresh={()=>load(selectedId)} busy={busy}/>
   {/* v2.15.129: four even tiles in the compact style. */}
   <section className="m-panel l4-status"><h2 className="l4-status-h">Layer 4 status</h2><div className="cf-metric-grid">
     <Metric label="Waiting for review" value={Number(data.summary?.waiting||0)} detail={tasks.map(([t,n])=>`${t} ${fmtNumber(n)}`).join(' · ')||'—'}/>
     <Metric label="Oldest item" value={`${data.summary?.oldest_days??'—'} days`} detail={`Target: nothing waits more than ${target} days`} tone={Number(data.summary?.oldest_days||0)>target?'warning':'neutral'}/>
     <Metric label="Suggested reject" value={suggestedCount('reject')} detail="The reason is shown on each item"/>
     <Metric label="Suggested approve" value={suggestedCount('approve')} detail="Page shows the amount as a yearly fee"/>
   </div></section>
   <section className="m23-panel l4d"><Head icon={ShieldCheck} title="Human resolution queue"/>
     <div className="l4d-filters">
       <label>Status<select value={status} onChange={e=>rememberFilters({status:e.target.value})}>{[['pending','Waiting for review'],['approved','Approved'],['edited_approved','Edited & approved'],['rejected','Rejected'],['more_evidence','More evidence requested'],['returned_layer2','Sent back to Layer 2'],['returned_layer3','Sent back to Layer 3'],['','All statuses']].map(([v,l])=><option key={v||'all'} value={v}>{l}</option>)}</select></label>
       <div className="l4d-chips">{[['',status==='pending'?`All tasks (${fmtNumber(data.summary?.waiting||0)})`:'All tasks'],...tasks.map(([t,n])=>[t,status==='pending'?`${t} (${fmtNumber(n)})`:t])].map(([v,l])=><button key={v||'all'} type="button" className={task===v?'on':''} onClick={()=>rememberFilters({task:v})}>{l}</button>)}</div>
       {(status!=='pending'||task)&&<button type="button" className="m23-clear" onClick={clearFilters}>Reset filters</button>}
       {view==='review'&&<div className="l4d-chips">{[['all','Everyone'],['mine','Mine'],['unassigned','Unassigned']].map(([v,l])=><button key={v} type="button" className={who===v?'on':''} onClick={()=>rememberFilters({who:v})}>{l}</button>)}</div>}
       <div className="l4d-view">{[['review','Review one by one'],['batches','Bulk decisions'],['team','Team and forecast']].map(([v,l])=><button key={v} type="button" className={view===v?'on':''} onClick={()=>rememberFilters({view:v})}>{l}</button>)}</div>
     </div>
     {view==='team'?<div className="l4t">
       {!team?<Empty text="Loading…"/>:<>
       <div className="l4t-head"><p>{team.scope==='team'?'Everyone\'s work':'Your work'} · last {team.days} days</p><div className="l4d-chips">{[7,30].map(d=><button key={d} type="button" className={teamDays===d?'on':''} onClick={()=>setTeamDays(d)}>{d} days</button>)}</div></div>
       <div className="m23-cards">
         <article><strong>{fmtNumber(team.waiting)}</strong><span>Waiting now</span><small>{team.ages?.over_target||0} older than {team.target_days} days</small></article>
         <article><strong>{fmtNumber(team.arrived)}</strong><span>Arrived</span><small>Sent to people in the last {team.days} days</small></article>
         <article><strong>{fmtNumber(team.decided)}</strong><span>Decided</span><small>In the last {team.days} days</small></article>
         <article className={team.forecast?.state==='growing'?'l4d-late':''}><strong>{team.forecast?.state==='clearing'?fmtDayMonth(team.forecast.date):team.forecast?.state==='clear'?'Clear':'Growing'}</strong><span>Forecast</span><small>{team.forecast?.text}</small></article>
       </div>
       <h3 className="l4b-sub">Arriving and decided each day</h3>
       <div className="l4t-days">{(team.daily||[]).map(d=>{const max=Math.max(1,...(team.daily||[]).map(x=>Math.max(x.arrived,x.decided)));return <div key={d.day} className="l4t-day" title={`${d.day}: ${d.arrived} arrived, ${d.decided} decided`}><div className="l4t-bars"><i className="in" style={{height:`${d.arrived/max*100}%`}}/><i className="out" style={{height:`${d.decided/max*100}%`}}/></div><small>{fmtDayMonth(d.day)}</small></div>})}</div>
       <p className="l4b-note"><i className="l4t-key in"/> arrived <i className="l4t-key out"/> decided</p>
       <h3 className="l4b-sub">How long items have been waiting</h3>
       <div className="l4t-ages">{['0-2','3-7','8-14','15+'].map(k=><div key={k} className={['8-14','15+'].includes(k)?'late':''}><strong>{team.ages?.[k]||0}</strong><small>{k} days</small></div>)}</div>
       <h3 className="l4b-sub">{team.scope==='team'?'Who decided what':'Your decisions'}</h3>
       {(team.people||[]).length===0?<Empty text="No decisions in this period."/>:<table className="l4t-table"><thead><tr><th>Person</th><th>Decided</th><th>Median time</th><th>Approved</th><th>Rejected</th><th>Sent back</th><th>Last decision</th></tr></thead><tbody>{team.people.map(p=><tr key={p.actor_id}><td>{p.who}{p.is_me&&' (you)'}</td><td>{p.decided}</td><td>{p.median_minutes!=null?`${p.median_minutes} min`:'—'}</td><td>{p.approved}</td><td>{p.rejected}</td><td>{p.sent_back}</td><td>{when(p.last_at)}</td></tr>)}</tbody></table>}
       <p className="l4b-note">Median time is from opening an item to deciding it. {team.scope==='team'?'Managers see everyone; operators see only their own figures.':'You see your own figures; managers see the whole team.'}</p>
       </>}
     </div>:view==='batches'?<div className="l4b">
       {batchMsg&&<p className="l4b-msg">{batchMsg}</p>}
       {!batches.can_apply&&<p className="l4b-note">You can preview batches. Applying a batch needs the Pipeline Operator role.</p>}
       {preview?<div className="l4b-preview">
         <header><h3>{preview.group.count} {preview.group.task.toLowerCase()} item(s)</h3><p>{preview.group.text}</p>{preview.group.count>100&&<p className="l4b-note">Showing the oldest 100. Decide these, then preview again for the rest.</p>}</header>
         <ol className="l4b-items">{(preview.group.samples||[]).filter(x=>(preview.group.item_ids||[]).slice(0,100).includes(x.id)).map(x=><li key={x.id}><label><input type="checkbox" checked={preview.picked.has(x.id)} onChange={e=>{const n=new Set(preview.picked);e.target.checked?n.add(x.id):n.delete(x.id);setPreview({...preview,picked:n,confirm:''})}}/><span><strong>{x.title}</strong>{x.code&&<small> · {x.code}</small>}<br/><small>{[x.provider,x.ai_suggested].filter(Boolean).join(' · ')}</small>{x.quote&&<em>“{x.quote}”</em>}</span></label></li>)}</ol>
         <div className="l4b-form">
           <label>Decision<select value={preview.action} onChange={e=>setPreview({...preview,action:e.target.value,confirm:''})}><option value="">Choose…</option><option value="reject">Reject</option>{preview.group.can_approve&&<option value="approve">Approve</option>}<option value="request_more_evidence">Ask for more evidence</option><option value="return_layer2">Send back to enrichment (Layer 2)</option><option value="return_layer3">Send back to AI check (Layer 3)</option></select></label>
           <label>Reason saved with every item<input value={preview.reason} onChange={e=>setPreview({...preview,reason:e.target.value})}/></label>
           {preview.action&&<label>Type <b>{preview.action.toUpperCase()} {preview.picked.size}</b> to confirm<input value={preview.confirm} onChange={e=>setPreview({...preview,confirm:e.target.value})}/></label>}
         </div>
         <div className="l4d-actions"><button className="l4d-primary" disabled={!batches.can_apply||!preview.action||preview.picked.size<2||preview.reason.trim().length<8||preview.confirm.trim()!==`${preview.action.toUpperCase()} ${preview.picked.size}`} onClick={applyBatch}>Apply to {preview.picked.size} item(s)</button><button onClick={()=>setPreview(null)}>Cancel</button></div>
       </div>:<div className="l4b-groups">{(batches.groups||[]).map(g=><article key={g.key} className="l4b-group">
         <div><strong>{g.count} × {g.task}</strong><em className={`l4d-chip ${g.action}`}>{chip(g.action)}</em></div>
         <p>{g.text}</p>
         <small>Oldest {g.oldest_days} days · e.g. {(g.samples||[]).slice(0,3).map(x=>x.title).join('; ')}</small>
         <div><button onClick={()=>openPreview(g)}>Preview batch</button></div>
       </article>)}{(batches.groups||[]).length===0&&<Empty text="No repeat cases to batch right now."/>}</div>}
       <p className="l4b-note l4b-pointer">Which courses a scholarship applies to comes from the study levels, fields and courses its own page names (Layer 2 › Scholarships).</p>
       <h3 className="l4b-sub">Provider departures, findings and decision history</h3>
       <Layer4MassOperations embedded sections={['departures','quality','history']}/>
     </div>:items.length===0?<Empty text="Nothing waiting here. Try another status or task."/>:<div className="l4d-grid">
       <ol className="l4d-queue">{items.map(r=><li key={r.id} className={r.id===selectedId?'on':''} onClick={()=>setSelectedId(r.id)}>
         <strong>{title(r)}</strong>
         <span>{[r.entity?.code,r.task].filter(Boolean).join(' · ')}</span>
         <span className="l4d-meta"><em className={`l4d-chip ${r.suggestion?.action||'check'}`}>{chip(r.suggestion?.action)}</em>{r.claim_active&&!r.claimed_by_me&&<em className="l4d-chip taken">With someone else</em>}{r.claim_active&&r.claimed_by_me&&<em className="l4d-chip mine">Yours</em>}<b className={r.age_days>target?'late':''}>{r.age_days} d</b></span>
       </li>)}</ol>
       {current&&<article className="l4d-panel">
         <header><h3>{title(current)}{current.entity?.code&&<small> · {current.entity.code}</small>}</h3><p>{[current.entity?.provider,current.task,`${current.age_days} days waiting`].filter(Boolean).join(' · ')}</p></header>
         {current.reason&&<p className="l4d-reason">{current.reason}</p>}
         {isContact(current)?contactActions(asRow(current)):<>
           <dl className="l4d-facts">
             {current.recorded&&<><dt>Recorded now</dt><dd>{current.recorded}</dd></>}
             {current.ai_suggested&&<><dt>AI suggested</dt><dd>{current.ai_suggested}</dd></>}
             {current.page_quote&&<><dt>The page says</dt><dd className="l4d-quote">“{current.page_quote}”</dd></>}
             <dt>Suggestion</dt><dd className={`l4d-sugg ${current.suggestion?.action}`}>{current.suggestion?.text}</dd>
           </dl>
           <div className="l4d-links">
             {current.links?.page_url&&<a href={current.links.page_url} target="_blank" rel="noreferrer">Open provider page <ExternalLink size={13}/></a>}
             {current.links?.course_url&&current.links.course_url!==current.links.page_url&&<a href={current.links.course_url} target="_blank" rel="noreferrer">Course page <ExternalLink size={13}/></a>}
             {current.search_url&&<a href={current.search_url} target="_blank" rel="noreferrer">Search the web <ExternalLink size={13}/></a>}
           </div>
           {panelError&&<p className="l4d-error" role="alert">{panelError}</p>}
           {claimInfo&&<p className="l4d-taken">Being reviewed by {claimInfo.claimed_by||'another reviewer'}. It frees up in about {claimInfo.minutes_left} minute(s) if left idle.</p>}
           {edit?.kind==='link'&&<div className="l4d-edit"><strong>Add the official course page, then approve</strong><div className="l4b-form">
             <label className="l4d-edit-note">Official course page link<input type="url" value={edit.url} onChange={e=>setEdit({...edit,url:e.target.value})} placeholder={current.provider_domain?`https://${current.provider_domain}/…`:'https://…'}/></label>
             {current.provider_domain&&<small className="l4b-note">This provider's course pages are usually on {current.provider_domain}.</small>}
             <label className="l4d-edit-note">Note saved with your decision<input value={edit.note} onChange={e=>setEdit({...edit,note:e.target.value})}/></label>
           </div><div className="l4d-actions"><button className="l4d-primary" onClick={()=>saveEdit(current)}>Save and approve</button><button onClick={()=>setEdit(null)}>Cancel</button></div></div>}
           {edit&&edit.kind!=='link'&&<div className="l4d-edit"><strong>Edit the fee, then approve</strong><div className="l4b-form">
             <label>Amount<input type="number" min="1" value={edit.amount} onChange={e=>setEdit({...edit,amount:e.target.value})}/></label>
             <label>Currency<select value={edit.currency_code} onChange={e=>setEdit({...edit,currency_code:e.target.value})}><option>AUD</option><option>NZD</option></select></label>
             <label>Charged<select value={edit.basis} onChange={e=>setEdit({...edit,basis:e.target.value})}><option value="annual">Per year</option><option value="indicative_annual">Per year (indicative)</option></select></label>
             <label>Fee year<input type="number" min="2024" max="2030" value={edit.fee_year??''} onChange={e=>setEdit({...edit,fee_year:e.target.value})} placeholder="blank if not stated"/></label>
             <label className="l4d-edit-note">Note saved with your decision<input value={edit.note} onChange={e=>setEdit({...edit,note:e.target.value})}/></label>
           </div><div className="l4d-actions"><button className="l4d-primary" onClick={()=>saveEdit(current)}>Save and approve</button><button onClick={()=>setEdit(null)}>Cancel</button></div></div>}
           {current.entity?.type==='scholarship'&&current.status==='pending'&&<div className="l4d-edit"><strong>{current.scope_pending>0?`${current.scope_pending} course(s) still need a scope decision`:'All courses have a scope decision'}</strong>
             <p className="l4b-note">Decide which courses this scholarship applies to in batch work, then mark this item as done.</p>
             <div className="l4d-actions">{current.scope_pending>0&&<button className="l4d-primary" onClick={()=>{setScopeQuery(current.entity?.title||'');rememberFilters({view:'batches'})}}>Decide these in Batches</button>}<button className={current.scope_pending>0?'':'l4d-primary'} disabled={current.scope_pending>0} onClick={()=>decide(current,'approve','Mark as done',undefined,note||'Scholarship scope decided in batch work')}>Mark as done</button></div></div>}
           {current.status==='pending'&&!claimInfo&&!edit&&current.entity?.type!=='scholarship'&&<>
             <label className="l4d-note">Note saved with your decision<input value={note} onChange={e=>setNote(e.target.value)} placeholder="Why you decided (required)"/></label>
             {actionsFor(current)}
             <small className="l4d-keys">Keys: R reject · A approve · E edit · N next</small>
           </>}
         </>}
         {rank>=6&&<details className="m23-tech"><summary>Advanced (Platform Admin)</summary>
           <pre>{JSON.stringify({...current.technical,history:context?.history||[],layer3:context?.layer3?{profile:context.layer3.profile_code,model:context.layer3.response_model,status:context.layer3.status,checks:context.layer3.validator_result}:null},null,2)}</pre>
         </details>}
       </article>}
     </div>}
   </section>
 </div>
}

export const Refresh=ScheduledJobsWorkspace

export function Onboarding({rank,onError}){const STAGES=['draft','source_qualification','adapter_assessment','schema_assessment','l1_uat','l2_uat','l3_ready','operational_certification','production_promotion_ready'];const[rows,setRows]=useState([]),[selected,setSelected]=useState(null),[context,setContext]=useState(null),[filters,setFilters]=useState({stage:'',outcome:'',country:'',type:''}),[form,setForm]=useState({case_type:'country',country_code:'',title:'',source_id:'',source_profile_id:'',provider_id:'',course_id:'',adapter_family:'structured_api'});const load=async()=>{try{setRows(await rpc('onboarding_cases_list',{p_stage:filters.stage||null,p_outcome:filters.outcome||null,p_country_code:filters.country||null,p_case_type:filters.type||null,p_limit:100})||[])}catch(e){onError(e)}};useEffect(()=>{load()},[filters.stage,filters.outcome,filters.country,filters.type]);const choose=async r=>{setSelected(r.id);try{setContext(await rpc('onboarding_case_context',{p_case_id:r.id}))}catch(e){onError(e)}};const create=async()=>{if(rank<4)return onError(new Error('Pipeline Operator role required to create onboarding cases'));const reason=askReason('Create onboarding case');if(!reason)return;try{const id=await rpc('onboarding_case_create',{p_case_type:form.case_type,p_country_code:form.country_code||null,p_title:form.title,p_source_id:form.source_id||null,p_source_profile_id:form.source_profile_id||null,p_provider_id:form.provider_id||null,p_course_id:form.course_id||null,p_adapter_family:form.adapter_family||null,p_reason:reason,p_change_control_ref:'CF-CHG-20260825-037',p_uat_ref:null});setForm(f=>({...f,title:'',source_id:'',source_profile_id:'',provider_id:'',course_id:''}));await load();if(id){setSelected(id);setContext(await rpc('onboarding_case_context',{p_case_id:id}))}}catch(e){onError(e)}};const advance=async()=>{if(rank<4||!context?.case?.next_stage)return;const outcome=window.prompt('Outcome: READY / CONDITIONAL / BLOCKED / PAUSED / REJECTED','CONDITIONAL');if(!outcome)return;const reason=askReason(`Advance to ${human(context.case.next_stage)}`);if(!reason)return;try{const c=await rpc('onboarding_case_transition',{p_case_id:context.case.id,p_to_stage:context.case.next_stage,p_outcome:outcome.toUpperCase(),p_reason:reason,p_details:{source:'admin_workspace'},p_evidence_id:null,p_uat_ref:null});setContext(c);await load()}catch(e){onError(e)}};return <div className="m23-stack"><section className="m23-panel"><Head icon={Route} title="Onboarding cases" action={<button onClick={load}><RefreshCw size={14}/>Refresh</button>}/><p className="m23-note">Tracks adding a new country, data source, provider or course type through its checks, one stage at a time. Every country uses the same catalogue; nothing is copied per country.</p><div className="m23-form-grid"><label>Stage<select value={filters.stage} onChange={e=>setFilters(f=>({...f,stage:e.target.value}))}><option value="">All</option>{STAGES.map(x=><option key={x} value={x}>{human(x)}</option>)}</select></label><label>Outcome<select value={filters.outcome} onChange={e=>setFilters(f=>({...f,outcome:e.target.value}))}><option value="">All</option>{['READY','CONDITIONAL','BLOCKED','PAUSED','REJECTED'].map(x=><option key={x} value={x}>{human(x.toLowerCase())}</option>)}</select></label><label>Country<input value={filters.country} onChange={e=>setFilters(f=>({...f,country:e.target.value.toUpperCase()}))}/></label><label>Type<select value={filters.type} onChange={e=>setFilters(f=>({...f,type:e.target.value}))}><option value="">All</option>{['country','source','provider','course'].map(x=><option key={x} value={x}>{human(x)}</option>)}</select></label></div><Table headers={['Type','Country','Title','Stage','Outcome','Next']} rows={rows.map(r=>[<button onClick={()=>choose(r)}>{human(r.case_type)}</button>,r.country_code||'—',r.title,human(r.stage),<State value={r.outcome||'in_progress'}/>,human(r.next_stage||'terminal')])}/></section>{selected&&context&&<section className="m23-panel"><Head icon={ShieldCheck} title="Onboarding lifecycle & immutable history" action={rank>=4&&context.case?.next_stage?<button className="m23-primary" onClick={advance}>Advance to {human(context.case.next_stage)}</button>:null}/><div className="m23-cards"><article><strong>{context.case.title}</strong><span>{human(context.case.case_type)} · {context.case.country_code||'—'}</span><small>Stage {human(context.case.stage)} · outcome {human(context.case.outcome||'in progress')} · adapter {human(context.case.adapter_family||'not assessed')}</small></article><article><strong>Lifecycle</strong><small>{STAGES.map(s=>`${s===context.case.stage?'●':'○'} ${human(s)}`).join(' → ')}</small></article><article><strong>Audit history</strong><small>{(context.history||[]).map(h=>`${human(h.event_type)} · ${human(h.from_stage||'start')} → ${human(h.to_stage||'same')} · ${h.outcome||'—'} · ${h.reason} · ${when(h.created_at)}`).join(' | ')||'No history'}</small></article></div></section>}{rank>=4&&<section className="m23-panel"><Head icon={Check} title="Start an onboarding case"/><div className="m23-form-grid"><label>Type<select value={form.case_type} onChange={e=>setForm(f=>({...f,case_type:e.target.value}))}>{['country','source','provider','course'].map(x=><option key={x} value={x}>{human(x)}</option>)}</select></label><label>Country<input value={form.country_code} onChange={e=>setForm(f=>({...f,country_code:e.target.value.toUpperCase()}))}/></label><label>Title<input value={form.title} onChange={e=>setForm(f=>({...f,title:e.target.value}))}/></label><label>Adapter family<select value={form.adapter_family} onChange={e=>setForm(f=>({...f,adapter_family:e.target.value}))}>{['structured_api','csv_xlsx','json','xml','sitemap_catalogue','html_detail','document_pdf','direct_http','approved_scraper_browser','custom_adapter'].map(x=><option key={x} value={x}>{human(x)}</option>)}</select></label></div><details className="onb-ids"><summary>Link to specific records (optional)</summary><div className="m23-form-grid"><label>Source ID<input value={form.source_id} onChange={e=>setForm(f=>({...f,source_id:e.target.value}))}/></label><label>Source Profile ID<input value={form.source_profile_id} onChange={e=>setForm(f=>({...f,source_profile_id:e.target.value}))}/></label><label>Provider ID<input value={form.provider_id} onChange={e=>setForm(f=>({...f,provider_id:e.target.value}))}/></label><label>Course ID<input value={form.course_id} onChange={e=>setForm(f=>({...f,course_id:e.target.value}))}/></label></div></details><button className="m23-primary" disabled={!form.title} onClick={create}>Start case</button></section>}</div>}

function LayerWorkspaceHeader({layer,eyebrow,title,subtitle,onRefresh,busy}){return <header className={`cf-layer-header cf-layer-header-l${layer} m23-layer-header`} data-layer-header={layer}><div><p>{subtitle}</p></div><div className="cf-layer-header-actions"><button onClick={onRefresh} disabled={busy} aria-label={`Refresh Layer ${layer}`}><RefreshCw size={15}/></button></div></header>}
function Head({icon:Icon,title,action}){return <div className="m23-head"><div><Icon size={17}/><h2>{title}</h2></div>{action}</div>}
function State({value}){return <StatusChip value={value||'unknown'} label={human(value||'unknown')}/>}

function Table({headers,rows}){return <div className="m23-table"><div className="m23-tr head">{headers.map(h=><strong key={h}>{h}</strong>)}</div>{rows.length?rows.map((r,i)=><div className="m23-tr" key={i}>{r.map((v,j)=><span key={j}>{v??'—'}</span>)}</div>):<Empty text="No records."/>}</div>}
