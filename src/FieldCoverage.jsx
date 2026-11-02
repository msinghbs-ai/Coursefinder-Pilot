// Every field, every country (v2.15.303, CF-247). Platform Admin, 21 Oct 2026 07:30: "Platform needs to keep working and cross checking on
// missing data fields ... rest of every fields should have cross check and mechanism to enrich the data ongoing. Work only or queue should
// fill them with checks. Also coverage menu should details all data fields filled together not the top 7 ... need to have same attributes
// completeness across the board." Choices: "Stored pages + AI, small reads", "When page changes, or 60 days", "All on Coverage; queue for
// readable ones".
// Shows the field register (15 course and 9 provider fields) by country against each field's target, the standing gap queue (job
// field-gap-queue: one Fill the gaps task when due) and the cross-check differences (held value against a newer page reading).
// Reads and writes: public.admin_field_coverage('overview' | 'findings' | 'finding_decide' | 'queue_set' | 'target_set' | 'run_now' |
// 'stalled' | 'fill_now' | 'release_and_fill' | 'wording_list' | 'wording_set' | 'wording_off').
// CF-247 P1 (Platform Admin, 2 Nov 2026 10:28): Provider descriptions shows the description reader's figures (public.admin_provider_descriptions
// 'metrics': eligible, present, missing, proposed, held, admitted, dead letters, stored pages, pages read, AI reads, cost, rejections, Layer 4
// queue, last run, backlog) and lets a PIM Admin send dead letters and held reads back to the queue with a reason ('retry').
// v2.15.305 (Platform Admin, 21 Oct 2026 "Keep two, fix reader"): blended is a mix inside one course (hours or a share each way); on campus
// and online is a choice of modes; a university's own wording is set in Delivery wording (PIM Admin and above, with a reason).
// v2.15.304 (Platform Admin, 21 Oct 2026 08:42: "go ahead with next step for Field Stalled and action to resolve it"): Stalled fields lists
// each field below target that has not moved (or trails the best country, or has no reader), its main cause, the action that resolves it
// and the universities missing it most; the same list raises Platform health issues (check field_stalled).
import React,{useEffect,useMemo,useState}from'react'
import{AlertTriangle,CheckCircle2,GitCompare,ListChecks,Play,RefreshCw}from'lucide-react'
import{api,supabase}from'./lib/supabase'
import Card from'./Card'
import{Button,Empty,Loading,StatusChip}from'./ui-kit'
import{fmtNumber,fmtDateTime}from'./lib/format.js'
import{plainError}from'./lib/errors'
import SnapshotStamp from'./SnapshotStamp' // CF-247 W35: every country's figures come from a cached snapshot; one university's are read live

const errText=e=>plainError(e) // v2.15.341 (UI audit Phase 0): one plain reading, no internals
const call=async(action,args)=>{const{data,error}=await supabase.rpc('admin_field_coverage',{p_action:action,p_args:args||{}});if(error)throw error;return data}
const COUNTRY={AU:'Australia',NZ:'New Zealand',CA:'Canada'}
export const READER_LABEL={register:'Register',coverage:'Coverage pipeline',enrich:'Enrich fields (standing queue)',none:'No reader yet'}
const STATE_LABEL={queued:'Waiting',waiting:'Waiting',ai:'With AI',leased:'With AI',filled:'Filled',review:'For review',skipped:'Not stated',failed:'Failed'}
const pct=(n,t)=>t?Math.round(n/t*1000)/10:null
const fmtPct=v=>v==null?'—':`${v}%`

export default function FieldCoverage({rank=0,country='',provider=null,onError}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(false)
  const scope={...(country?{country}:{}),...(provider?{provider:provider.id}:{})}
  const load=()=>{setBusy(true);call('overview',scope).then(setData).catch(e=>onError?.(errText(e))).finally(()=>setBusy(false))}
  useEffect(()=>{load()},[country,provider?.id])
  if(!data)return <section className="m-panel"><Loading label="Loading every field…"/></section>
  return <div className="m-page-stack" data-field-coverage>
    <StalledFields scope={scope} onChanged={load} onError={onError}/>
    <FieldMatrix data={data} rank={rank} busy={busy} onReload={load} onSaved={setData} onError={onError}/>
    <GapQueue data={data} rank={rank} onSaved={setData} onReload={load} onError={onError}/>
    <CrossCheck data={data} scope={scope} rank={rank} onDecided={load} onError={onError}/>
    <DeliveryWording onError={onError}/>
    <ProviderDescriptions country={country} rank={rank} onError={onError}/>
  </div>
}

function FieldMatrix({data,rank,busy,onReload,onSaved,onError}){
  const reg=data.register||[]
  const countries=useMemo(()=>{const s=new Set([...(data.courses_by_country||[]),...(data.providers_by_country||[])].map(r=>r.country));return['AU','NZ','CA'].filter(c=>s.has(c)).concat([...s].filter(c=>!['AU','NZ','CA'].includes(c)).sort())},[data])
  const cell=useMemo(()=>{const m={};for(const r of[...(data.courses_by_country||[]),...(data.providers_by_country||[])]){m[`${r.field}|${r.country}`]=r}return m},[data])
  const all=f=>{const rows=countries.map(c=>cell[`${f}|${c}`]).filter(Boolean);const t=rows.reduce((a,r)=>a+Number(r.total||0),0),n=rows.reduce((a,r)=>a+Number(r.filled||0),0);return{t,n}}
  const[edit,setEdit]=useState(null),[reason,setReason]=useState(''),[saving,setSaving]=useState(false)
  const save=async()=>{setSaving(true);try{onSaved(await call('target_set',{field:edit.field,target_pct:Number(edit.value),reason:reason.trim()}));setEdit(null);setReason('')}catch(e){onError?.(errText(e))}finally{setSaving(false)}}
  const groups=[['course','Course fields (share of active courses)'],['provider','Provider fields (share of providers with active courses)']]
  return <Card id="coverage.fields" title="Every field by country" icon={CheckCircle2}
    subtitle="Every course and provider field the platform holds, with the same target in every country. Australia gets most course fields from its register (CRICOS); New Zealand and Canada get them from each provider's website, so the same fields are filled there by adapters, the coverage pipeline and the standing Fill the gaps queue."
    meta={<Button compact className="cf-icon-btn" title="Refresh" aria-label="Refresh every field" onClick={onReload} disabled={busy}><RefreshCw size={14}/></Button>}>
    <p className="sd-desc">Course figures are recounted every hour{data.computed_at?` (last ${fmtDateTime(data.computed_at)})`:''}; provider figures are {data.snapshot?.source==='snapshot'?`counted every ${data.snapshot.refresh_every_minutes} minutes`:'counted when this opens'}. Below target is marked. Select a field in the attribute table further down to list its courses.</p>
    <SnapshotStamp meta={data.snapshot} label="Provider figures counted" what="field-coverage"/>
    {groups.map(([level,title])=><div className="dq-table-wrap" key={level}><table className="dq-table cc-table fc-matrix" data-field-matrix={level}>
      <thead><tr><th>{title}</th><th>Filled by</th>{countries.map(c=><th key={c} className="num">{COUNTRY[c]||c}</th>)}<th className="num">All</th><th className="num">Target</th></tr></thead>
      <tbody>{reg.filter(f=>f.level===level).map(f=>{const a=all(f.field),ap=pct(a.n,a.t);return <tr key={f.field} data-field={f.field}>
        <td><strong>{f.label}</strong><small>{f.group}</small></td>
        <td><small title={f.fills}>{READER_LABEL[f.reader]||f.reader}</small><small className="fc-fills">{f.fills}</small></td>
        {countries.map(c=>{const r=cell[`${f.field}|${c}`];if(!r||!Number(r.total))return <td key={c} className="num"><span className="cc-zero" title={f.field==='registered_tuition'?'A CRICOS value: Australia only':''}>–</span></td>
          const p=pct(Number(r.filled||0),Number(r.total||0)),low=p<Number(f.target_pct)
          return <td key={c} className={`num${low?' fc-low':''}`} data-below-target={low||undefined}><strong>{fmtPct(p)}</strong>
            <small>{fmtNumber(r.filled)} of {fmtNumber(r.total)}{Number(r.in_queue)?` · ${fmtNumber(r.in_queue)} queued`:''}{Number(r.not_stated)?` · ${fmtNumber(r.not_stated)} not stated`:''}</small></td>})}
        <td className="num"><strong>{fmtPct(ap)}</strong></td>
        <td className="num">{edit?.field===f.field?<span className="fc-target-edit"><input type="number" min="0" max="100" value={edit.value} onChange={e=>setEdit({...edit,value:e.target.value})} aria-label={`Target for ${f.label}`}/>%
            <input value={reason} onChange={e=>setReason(e.target.value)} placeholder="Reason" aria-label="Reason for the target"/>
            <Button compact onClick={save} disabled={saving||reason.trim().length<4}>Save</Button><Button compact onClick={()=>setEdit(null)}>Cancel</Button></span>
          :<>{fmtPct(Number(f.target_pct))}{data.can_manage&&<button type="button" className="m-link-button" onClick={()=>setEdit({field:f.field,value:f.target_pct})} aria-label={`Change the target for ${f.label}`}>Change</button>}</>}</td>
      </tr>})}</tbody></table></div>)}
  </Card>
}

function GapQueue({data,rank,onSaved,onReload,onError}){
  const q=data.queue||{},j=q.job,[reason,setReason]=useState(''),[busy,setBusy]=useState(''),[note,setNote]=useState('')
  const label=f=>f==='campus_list'?'Campus list':f==='provider_address'?'Street address':(data.register||[]).find(x=>x.field===f)?.label||f
  const toggle=async()=>{setBusy('toggle');try{onSaved(await call('queue_set',{enabled:!q.enabled,reason:reason.trim()}));setReason('')}catch(e){onError?.(errText(e))}finally{setBusy('')}}
  const runNow=async()=>{setBusy('run');setNote('');try{const r=await call('run_now');setNote(r?.queue==='started'?`Started: ${fmtNumber(r.items)} item(s) to settle.`:r?.queue==='nothing due'?'Nothing is due now.':r?.queue==='previous run still open'?'The previous run is still open.':r?.queue==='off'?'The standing queue is off.':'Done.');onReload()}catch(e){onError?.(errText(e))}finally{setBusy('')}}
  const done=Number(j?.progress?.done||0),total=Number(j?.progress?.total||0)
  return <Card id="coverage.gap-queue" title="Fill the gaps (standing queue)" icon={ListChecks}
    subtitle={`Every ${q.schedule==='23 */6 * * *'?'6 hours':'scheduled run'}, when the previous run has finished, one Enrich fields task takes every course and provider field that is missing and due: stored pages and adapter readings first, then the AI, then up to ${fmtNumber(q.reads_per_day)} new page reads a day. A field the page did not state is tried again when the page is read again with new content, or after ${fmtNumber(q.recheck_days)} days. Values entered or locked by hand are never changed.`}
    meta={<StatusChip value={q.enabled?'on':'off'} tone={q.enabled?'success':'neutral'} label={q.enabled?'On':'Off'}/>} data-gap-queue>
    <div className="cf-metric-row fc-queue-metrics">
      <span><strong>{j?STATE_LABEL[j.state]||j.state:'No run yet'}</strong><small>Latest run{j?.created_at?` · started ${fmtDateTime(j.created_at)}`:''}</small></span>
      <span><strong>{total?`${fmtNumber(done)} of ${fmtNumber(total)}`:'—'}</strong><small>Items settled</small></span>
      <span><strong>{fmtNumber(q.filled_7d||0)}</strong><small>Values filled in 7 days</small></span>
      <span><strong>{fmtNumber(q.reads_today||0)} of {fmtNumber(q.reads_per_day)}</strong><small>New page reads today</small></span>
      <span><strong>US${Number(q.ai_spent_today_usd||0).toFixed(2)}{q.ai_guard_usd!=null?` of ${Number(q.ai_guard_usd).toFixed(0)}`:''}</strong><small>Enrich fields AI today (guard)</small><SnapshotStamp meta={data.snapshot} label="Counted" what="field-coverage-spend"/></span>
    </div>
    {j?.by_field&&<div className="dq-table-wrap"><table className="dq-table cc-table"><thead><tr><th>Field (latest run)</th>{['queued','ai','filled','review','skipped','failed'].map(s=><th key={s} className="num">{STATE_LABEL[s]}</th>)}</tr></thead>
      <tbody>{Object.entries(j.by_field).map(([f,s])=><tr key={f}><td><strong>{label(f)}</strong></td>{['queued','ai','filled','review','skipped','failed'].map(k=>{const n=Number(s?.[k]||0)+(k==='queued'?Number(s?.waiting||0):0)+(k==='ai'?Number(s?.leased||0):0);return <td key={k} className="num">{n?fmtNumber(n):<span className="cc-zero">–</span>}</td>})}</tr>)}</tbody></table></div>}
    {q.last_tick&&<p className="sd-desc">Last check {fmtDateTime(q.last_tick.at)} ({q.last_tick.status}). Limits are on Settings › Pipeline settings › Re-read and retry; sources per field and country on Layer 2 › Enrich fields › Field sources.</p>}
    <div className="fc-actions">
      {data.can_decide&&<Button compact onClick={runNow} disabled={!!busy||!q.enabled}><Play size={14}/>Check now</Button>}
      {data.can_manage&&<><input value={reason} onChange={e=>setReason(e.target.value)} placeholder={q.enabled?'Reason to switch off':'Reason to switch on'} aria-label="Reason for switching the standing queue"/>
        <Button compact onClick={toggle} disabled={!!busy||reason.trim().length<4}>{q.enabled?'Switch off':'Switch on'}</Button></>}
      {note&&<span className="sd-desc" role="status">{note}</span>}
    </div>
  </Card>
}

function CrossCheck({data,scope,rank,onDecided,onError}){
  const counts=useMemo(()=>{const m={};for(const r of data.crosscheck||[]){m[r.field]=m[r.field]||{};m[r.field][r.state]=Number(r.n||0)}return m},[data])
  const[field,setField]=useState(''),[items,setItems]=useState(null),[offset,setOffset]=useState(0),[busy,setBusy]=useState(0)
  const load=()=>call('findings',{...scope,field,limit:25,offset}).then(r=>setItems(r?.items||[])).catch(e=>onError?.(errText(e)))
  useEffect(()=>{load()},[field,offset,scope.country,scope.provider])
  const decide=async(id,decision)=>{setBusy(id);try{await call('finding_decide',{id,decision,reason:decision==='accept'?'Page value taken on Coverage':'Held value kept on Coverage'});await load();onDecided?.()}catch(e){onError?.(errText(e))}finally{setBusy(0)}}
  const show=v=>v?.name||(v?.mode?MODE[v.mode]||v.mode:null)||(v?.value!=null?`${Number(v.value)} ${v.unit||''}`:'—')
  const LABEL={duration:'Duration',level:'Study level',delivery:'Delivery mode'}
  const open=Object.values(counts).reduce((a,s)=>a+Number(s.open||0),0)
  return <Card id="coverage.crosscheck" title="Cross-check differences" icon={GitCompare}
    subtitle="Each standing run compares the held duration, study level and delivery mode with the latest reading of the course page. A difference is listed here with the page's words; nothing is overwritten. Keep the held value, or take the page value (it is then locked as entered by hand). In Australia the held value is usually the register's."
    meta={<span className="cf-chip tone-neutral">{fmtNumber(open)} open</span>} data-crosscheck>
    <div className="cf-filterbar"><span>Field</span>{[['','All'],['duration','Duration'],['level','Study level'],['delivery','Delivery mode']].map(([k,l])=><button key={k||'all'} className={field===k?'active':''} onClick={()=>{setOffset(0);setField(k)}}>{l}{k&&counts[k]?.open?` (${fmtNumber(counts[k].open)})`:''}</button>)}</div>
    {items==null?<Loading compact/>:items.length===0?<Empty text="No open differences."/>:<div className="dq-table-wrap"><table className="dq-table"><thead><tr><th>Course</th><th>Field</th><th>Held</th><th>Course page</th><th>Page words</th>{data.can_decide&&<th/>}</tr></thead>
      <tbody>{items.map(r=><tr key={r.id}><td><button className="dq-entity-link" onClick={()=>{location.hash=`#courses?id=${encodeURIComponent(r.course_id)}`}}><strong>{r.course}</strong></button><small>{r.provider} · {r.country}</small></td>
        <td>{LABEL[r.field]||r.field}</td><td>{show(r.held_value)}</td><td><strong>{show(r.page_value)}</strong></td><td><small>{r.quote}</small></td>
        {data.can_decide&&<td className="fc-decide"><Button compact onClick={()=>decide(r.id,'dismiss')} disabled={busy===r.id}>Keep held</Button><Button compact onClick={()=>decide(r.id,'accept')} disabled={busy===r.id}>Take page value</Button></td>}</tr>)}</tbody></table></div>}
    <footer className="dq-pager"><button disabled={offset===0} onClick={()=>setOffset(Math.max(0,offset-25))}>Previous</button><span>{fmtNumber(offset+1)}–{fmtNumber(offset+(items?.length||0))}</span><button disabled={(items?.length||0)<25} onClick={()=>setOffset(offset+25)}>Next</button></footer>
  </Card>
}

const REASON={flat:['Not moving','warning'],behind:['Behind other countries','info'],no_reader:['No reader yet','neutral']}
const CAUSE={not_stated:'Pages read do not state it',not_read:'Pages not read for it yet',no_page:'No course page found yet',in_review:'Waiting for a person',in_queue:'Being filled now',register:'Register value missing',no_reader:'Nothing reads it yet',provider:'Provider field'}
function StalledFields({scope,onChanged,onError}){
  const[d,setD]=useState(null),[busy,setBusy]=useState(''),[note,setNote]=useState(''),[reason,setReason]=useState('')
  const load=()=>call('stalled',scope).then(setD).catch(e=>onError?.(errText(e)))
  useEffect(()=>{load()},[scope.country])
  const act=async(x,action)=>{const k=`${x.country}|${x.field}|${action}`;setBusy(k);setNote('')
    try{const r=await call(action,{country:x.country,field:x.field,reason:reason.trim()})
      setNote(`${x.label} (${COUNTRY[x.country]||x.country}): ${action==='release_and_fill'?`${fmtNumber(r?.released||0)} hold(s) released; `:''}task started with ${fmtNumber(r?.items||0)} item(s). Progress is in Task manager and Layer 2 › Enrich fields.`);setReason('');load();onChanged?.()}
    catch(e){onError?.(errText(e))}finally{setBusy('')}}
  const items=d?.items||[]
  const flat=items.filter(x=>x.reason==='flat').length
  return <Card id="coverage.stalled" title="Stalled fields" icon={AlertTriangle}
    subtitle={`Fields below their target that have gained less than ${d?fmtNumber(d.min_points):1} point in ${d?fmtNumber(d.days):7} days, that trail the best country by ${d?fmtNumber(d.gap_points):30} points or more, or that nothing reads yet. Each shows its main cause, the action that resolves it and the universities missing it most. The same list raises Platform health issues every 3 hours; an issue closes itself when the field moves again.`}
    meta={<span className={`cf-chip tone-${flat?'warning':'neutral'}`}>{fmtNumber(flat)} not moving · {fmtNumber(items.length)} in all</span>} data-stalled-fields>
    {!d?<Loading compact/>:items.length===0?<Empty text="No field is stalled."/>:<>
    {d.can_release&&<p className="fc-actions"><input value={reason} onChange={e=>setReason(e.target.value)} placeholder="Reason (needed to release holds)" aria-label="Reason for releasing holds"/><small className="sd-desc">Release holds and fill: use after a new central page, adapter rule or reader, so courses whose page did not state the field are read again.</small></p>}
    {note&&<p className="sd-desc" role="status">{note}</p>}
    <div className="dq-table-wrap"><table className="dq-table"><thead><tr><th>Country</th><th>Field</th><th className="num">Now</th><th className="num">{fmtNumber(d.days)} days ago</th><th>Why</th><th>What resolves it</th><th/></tr></thead>
      <tbody>{items.map(x=>{const[rl,tone]=REASON[x.reason]||[x.reason,'neutral'];return <tr key={x.country+x.field} data-stalled={x.reason}>
        <td>{COUNTRY[x.country]||x.country}</td>
        <td><strong>{x.label}</strong><small><StatusChip value={x.reason} tone={tone} label={rl}/></small></td>
        <td className="num"><strong>{fmtPct(Number(x.pct))}</strong><small>target {fmtPct(Number(x.target))}{x.best_country&&x.best_country!==x.country?` · best ${x.best_country} ${fmtPct(Number(x.best_pct))}`:''}</small></td>
        <td className="num">{x.pct_ago==null?<small>no history yet</small>:<>{fmtPct(Number(x.pct_ago))}<small>{Number(x.moved)>=0?'+':''}{x.moved} points</small></>}</td>
        <td>{CAUSE[x.cause]||x.cause}{x.causes&&<small>{Object.entries(x.causes).sort((a,b)=>b[1]-a[1]).slice(0,3).map(([k,n])=>`${CAUSE[k]||k}: ${fmtNumber(n)}`).join(' · ')}</small>}</td>
        <td><small>{x.action}</small>{(x.top_providers||[]).length>0&&<small className="fc-top">Most missing: {x.top_providers.map((p,i)=><span key={p.id}>{i?', ':''}<a className="cf-link" href={`#providers?id=${encodeURIComponent(p.id)}`}>{p.name}</a> ({fmtNumber(p.missing)})</span>)}</small>}</td>
        <td className="fc-decide">{x.can_fill&&d.can_fill&&<Button compact onClick={()=>act(x,'fill_now')} disabled={!!busy}><Play size={14}/>Fill now</Button>}
          {x.can_fill&&d.can_release&&x.cause==='not_stated'&&<Button compact onClick={()=>act(x,'release_and_fill')} disabled={!!busy||reason.trim().length<4} title="Needs a reason above">Release holds and fill</Button>}</td>
      </tr>})}</tbody></table></div></>}
  </Card>
}

export const MODE={on_campus:'On campus',online:'Online',blended:'Blended (a mix in one course)',on_campus_and_online:'On campus or online (a choice)'}
function DeliveryWording({onError}){
  const[d,setD]=useState(null),[f,setF]=useState({phrase:'',mode:'on_campus',provider:null,reason:''}),[busy,setBusy]=useState(false),[note,setNote]=useState(''),[q,setQ]=useState(''),[hits,setHits]=useState([])
  useEffect(()=>{if(q.trim().length<2){setHits([]);return}let live=true;const t=setTimeout(()=>api.catalogueFilterPage({kind:'provider',query:q,limit:8}).then(x=>live&&setHits(x?.items||[])).catch(()=>{}),250);return()=>{live=false;clearTimeout(t)}},[q])
  const load=()=>call('wording_list').then(setD).catch(e=>onError?.(errText(e)))
  useEffect(()=>{load()},[])
  const save=async(action,args)=>{setBusy(true);setNote('');try{const r=await call(action,args);setD(r);setNote(`Saved. Cross-check: ${fmtNumber(r?.crosscheck?.resolved||0)} difference(s) closed, ${fmtNumber(r?.crosscheck?.new||0)} new.`);setF({...f,phrase:'',reason:''})}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  return <Card id="coverage.delivery-wording" title="Delivery wording" icon={ListChecks}
    subtitle="Blended means every student mixes campus and online study inside one course (for example 70% face to face and 30% online, or online with block weeks on campus). On campus or online means the page offers a choice of modes. Where a university uses its own phrase for a mode, add it here; it is applied before the reader, for that university or for every university. Online offered to domestic students only is read as on campus."
    meta={<span className="cf-chip tone-neutral">{fmtNumber((d?.items||[]).filter(x=>x.active).length)} phrase(s)</span>} data-delivery-wording>
    {!d?<Loading compact/>:<>
    {(d.items||[]).length===0?<Empty text="No phrases yet."/>:<div className="dq-table-wrap"><table className="dq-table"><thead><tr><th>Phrase on the page</th><th>Means</th><th>University</th><th>Why</th>{d.can_edit&&<th/>}</tr></thead>
      <tbody>{d.items.map(x=><tr key={x.id} className={x.active?'':'is-muted'}><td><strong>{x.phrase}</strong>{!x.active&&<small>Switched off</small>}</td><td>{MODE[x.mode]||x.mode}</td><td>{x.provider}</td><td><small>{x.reason}</small></td>
        {d.can_edit&&<td>{x.active&&<Button compact disabled={busy||f.reason.trim().length<4} title="Needs a reason below" onClick={()=>save('wording_off',{id:x.id,reason:f.reason.trim()})}>Switch off</Button>}</td>}</tr>)}</tbody></table></div>}
    {d.can_edit&&<div className="fc-actions" data-wording-form>
      <input value={f.phrase} onChange={e=>setF({...f,phrase:e.target.value})} placeholder="Phrase as the page writes it" aria-label="Phrase"/>
      <select value={f.mode} onChange={e=>setF({...f,mode:e.target.value})} aria-label="Mode it means">{Object.entries(MODE).map(([k,l])=><option key={k} value={k}>{l}</option>)}</select>
      {f.provider?<span className="cf-filter-chip">{f.provider.label}<button type="button" aria-label="Every university" onClick={()=>setF({...f,provider:null})}>×</button></span>
        :<span className="ef-unis"><input value={q} onChange={e=>setQ(e.target.value)} placeholder="University (blank = every university)" aria-label="University"/>
          {hits.length>0&&<span className="ef-hits">{hits.map(h=><button type="button" key={h.value} onClick={()=>{setF({...f,provider:{value:h.value,label:h.label}});setQ('');setHits([])}}>{h.label}</button>)}</span>}</span>}
      <input value={f.reason} onChange={e=>setF({...f,reason:e.target.value})} placeholder="Reason" aria-label="Reason"/>
      <Button compact disabled={busy||f.phrase.trim().length<3||f.reason.trim().length<4} onClick={()=>save('wording_set',{phrase:f.phrase,mode:f.mode,provider_id:f.provider?.value||null,reason:f.reason.trim()})}>Add phrase</Button>
    </div>}
    {note&&<p className="sd-desc" role="status">{note}</p>}</>}
  </Card>
}

// CF-247 P1 provider descriptions (Platform Admin 2 Nov 2026 10:28, mandate §8)
const PD_STATE={queued:'Waiting',reading:'Being read',proposed:'In Layer 4',held:'Held',dead_letter:'Dead letter',admitted:'Admitted',verified:'Verified',rejected:'Rejected',superseded:'Replaced'}
function ProviderDescriptions({country,rank,onError}){
  const[d,setD]=useState(null),[reason,setReason]=useState(''),[busy,setBusy]=useState(false)
  const load=()=>supabase.rpc('admin_provider_descriptions',{p_action:'metrics',p_args:country?{country}:{}}).then(({data,error})=>{if(error)throw error;setD(data)}).catch(e=>onError?.(errText(e)))
  useEffect(()=>{load()},[country])
  const retry=async ids=>{setBusy(true);try{const{error}=await supabase.rpc('admin_provider_descriptions',{p_action:'retry',p_args:{provider_ids:ids,reason:reason.trim()}});if(error)throw error;setReason('');await load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const stuck=(d?.providers||[]).filter(p=>p.state==='dead_letter'||p.state==='held')
  const n=k=>fmtNumber(d?.[k]??0)
  return <Card id="coverage.provider-descriptions" title="Provider descriptions" icon={ListChecks}
    subtitle="Descriptions read from each university's own About page, stored copy first. Every sentence quotes the page; a person approves each one in Layer 4 before the website shows it."
    meta={<span className="cf-chip tone-neutral" data-pdesc-switch>{d?.enabled&&d?.job_active?'Reader on':'Reader off'}</span>} data-provider-descriptions>
    {!d?<Loading compact/>:<>
    <dl className="l4i-dl" data-pdesc-metrics>
      <dt>Eligible</dt><dd>{n('eligible')}</dd><dt>Description present</dt><dd>{n('present')}</dd><dt>Missing</dt><dd>{n('missing')}</dd>
      <dt>In Layer 4</dt><dd>{n('proposed')}</dd><dt>Held</dt><dd>{n('held')}</dd><dt>Admitted</dt><dd>{n('admitted')} ({n('published')} shown by the website)</dd>
      <dt>Dead letters</dt><dd>{n('dead_letter')}</dd><dt>Stored About pages</dt><dd>{n('stored_pages_available')}</dd>
      <dt>Pages read</dt><dd>{n('pages_acquired')} new, {n('pages_reused')} reused</dd><dt>AI reads</dt><dd>{n('ai_reads')} (US${d.cost_usd??0}; {d.cost_per_admitted_usd==null?'no admitted description yet':`US$${d.cost_per_admitted_usd} a description admitted`})</dd>
      <dt>Remaining</dt><dd>{n('backlog')}</dd><dt>Last run</dt><dd>{d.last_run?fmtDateTime(d.last_run):'never'}</dd>
    </dl>
    {(d.rejections||[]).length>0&&<p className="sd-desc" data-pdesc-rejections>Held or rejected: {d.rejections.map(r=>`${String(r.rule||'other').replace(/_/g,' ')} ${r.n}`).join(' · ')}</p>}
    {stuck.length>0&&<div className="dq-table-wrap"><table className="dq-table" data-pdesc-stuck><thead><tr><th>University</th><th>State</th><th>Why</th></tr></thead>
      <tbody>{stuck.map(p=><tr key={p.provider_id}><td>{p.provider}</td><td>{PD_STATE[p.state]||p.state}</td><td><small>{String(p.rule||'').replace(/_/g,' ')}</small></td></tr>)}</tbody></table></div>}
    {rank>=5&&stuck.length>0&&<div className="fc-actions" data-pdesc-retry>
      <input value={reason} onChange={e=>setReason(e.target.value)} placeholder="Reason" aria-label="Reason"/>
      <Button compact disabled={busy||reason.trim().length<5} onClick={()=>retry(stuck.map(p=>p.provider_id))}>Read these again</Button>
    </div>}</>}
  </Card>
}
