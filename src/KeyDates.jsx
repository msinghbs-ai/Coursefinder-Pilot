// Key dates (v2.15.121): application deadlines, intakes, scholarship windows and data release dates, edited in place.
// Screen review 1 Oct 2026 (Key dates: list first, edit in place, cancel, plain labels, dd/mm/yyyy). Click a cell to
// change it; Enter or leaving the cell saves, Esc cancels. "Add date" opens a short form; linking a date to a source,
// provider, course or scholarship is under "More". Curator and above; every change is logged.
// Read: public.admin_key_dates_read(); write: public.admin_key_date_save(id, fields), public.admin_key_date_action(id, action)
// (migration 20261001112000_cf247_key_dates_edit).
import React,{useEffect,useRef,useState}from'react'
import{CalendarClock,ExternalLink,History,Plus}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,SectionTitle,StatusChip,fmtDateTime}from'./ui-kit'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
export const KINDS={course_application_deadline:'Course application deadline',provider_application_window:'University application window',intake_date:'Intake date',scholarship_window:'Scholarship window',regulatory_dataset_release:'Government data release',national_education_event:'National education event'}
export const PRECISION={exact:'Exact date',date_range:'Date range',month:'Month only',term:'Term only',year:'Year only',source_vague:'Vague (keep the wording)'}
const COUNTRY={AU:'Australia',NZ:'New Zealand'}
export const auDate=v=>{if(!v)return'';const[y,m,d]=String(v).slice(0,10).split('-');return d&&m&&y?`${d}/${m}/${y}`:String(v)}

export default function KeyDates({onError}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(false),[err,setErr]=useState(''),[done,setDone]=useState(''),[adding,setAdding]=useState(false),[showCancelled,setShowCancelled]=useState(false)
  const load=async()=>{try{const{data:d,error}=await supabase.rpc('admin_key_dates_read');if(error)throw error;setData(d||{})}catch(e){onError?.(errText(e))}}
  useEffect(()=>{load()},[])
  const call=async(fn,args,msg)=>{setBusy(true);setErr('');setDone('');try{const{data:d,error}=await supabase.rpc(fn,args);if(error)throw error;setData(d||{});if(msg)setDone(msg);return true}catch(e){setErr(errText(e));return false}finally{setBusy(false)}}
  if(!data)return <section className="m-panel"><Loading label="Loading key dates…"/></section>
  const can=Boolean(data.can_edit),items=(data.items||[]).filter(x=>showCancelled||x.status!=='cancelled')
  const save=(x,f)=>call('admin_key_date_save',{p_id:x.id,p_fields:f},`${f.title||x.title} saved.`)
  return <>
    <section className="m-panel">
      <SectionTitle icon={CalendarClock} title="Key dates" subtitle="Deadlines, intakes, scholarship windows and data releases. A vague date keeps the source's own wording." action={<div className="l3c-actions">
        <label className="rs-check"><input type="checkbox" checked={showCancelled} onChange={e=>setShowCancelled(e.target.checked)}/>Show cancelled</label>
        {can&&<Button compact variant="primary" onClick={()=>setAdding(a=>!a)}><Plus size={14}/>Add date</Button>}</div>}/>
      {err&&<p className="fr-error" role="alert">{err}</p>}
      {done&&<p className="sb-done" role="status">{done}</p>}
      {adding&&<AddDate onCancel={()=>setAdding(false)} onSave={async f=>{if(await call('admin_key_date_save',{p_id:null,p_fields:f},'Date added.'))setAdding(false)}}/>}
      {items.length?<div className="cf-table-wrap"><table className="cf-table rs-table" data-key-dates>
        <thead><tr><th>Date</th><th>What</th><th>Kind</th><th>Precision</th><th>Source</th><th>Warn</th><th/></tr></thead>
        <tbody>{items.map(x=><tr key={x.id} className={x.status==='cancelled'?'ms-off':''} data-date={x.title}>
          <td><DateCell x={x} can={can&&x.status!=='cancelled'} onSave={f=>save(x,f)}/></td>
          <td className="rs-site"><Text value={x.title} can={can} label={`Title of ${x.title}`} onSave={v=>save(x,{title:v})} strong/>
            {(x.precision==='source_vague'||x.wording)&&<Text value={x.wording||''} can={can} label={`Source wording of ${x.title}`} onSave={v=>save(x,{wording:v})} muted placeholder="Add the source wording"/>}
            <span className="l3v-code">{COUNTRY[x.country]||x.country}{x.scope&&x.scope!=='country_reference'?` · tied to a ${x.scope}`:''}{x.refresh_layer?` · refreshes Layer ${x.refresh_layer}`:''}</span></td>
          <td>{can?<select className="fv-filter" value={x.event_type} aria-label={`Kind of ${x.title}`} onChange={e=>save(x,{event_type:e.target.value})}>{Object.entries(KINDS).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select>:KINDS[x.event_type]||x.event_type}</td>
          <td>{can?<select className="fv-filter" value={x.precision} aria-label={`Precision of ${x.title}`} onChange={e=>save(x,{precision:e.target.value})}>{Object.entries(PRECISION).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select>:PRECISION[x.precision]||x.precision}</td>
          <td><Text value={x.source_url} can={can} label={`Source address of ${x.title}`} onSave={v=>save(x,{source_url:v})} link short/></td>
          <td><Text value={String(x.warning_days??'')} can={can} label={`Warning days for ${x.title}`} onSave={v=>save(x,{warning_days:v})} suffix=" days"/></td>
          <td>{x.status==='cancelled'?<>{can&&<Button compact onClick={()=>call('admin_key_date_action',{p_id:x.id,p_action:'restore'},`${x.title} restored.`)} disabled={busy}>Restore</Button>}</>:can&&<Button compact onClick={()=>{if(window.confirm(`Cancel "${x.title}"? It stays listed as cancelled and can be restored.`))call('admin_key_date_action',{p_id:x.id,p_action:'cancel'},`${x.title} cancelled.`)}} disabled={busy}>Cancel date</Button>}</td>
        </tr>)}</tbody></table></div>:<Empty text="No key dates yet. Use Add date to record one from its source."/>}
    </section>
    {(data.events||[]).length>0&&<section className="m-panel"><SectionTitle icon={History} title="Recent changes"/>
      <ul className="ms-events">{data.events.map((e,i)=><li key={i}><strong>{e.target}</strong> {e.action==='change'?'changed':e.action==='add'?'added':e.action==='cancel'?'cancelled':'restored'}<span className="l3v-code">{[e.by,fmtDateTime(e.at)].filter(Boolean).join(' · ')}</span></li>)}</ul></section>}
  </>
}

function DateCell({x,can,onSave}){
  const[edit,setEdit]=useState(false),[a,setA]=useState(x.starts_on||''),[b,setB]=useState(x.ends_on||''),ref=useRef(null)
  useEffect(()=>{if(!edit){setA(x.starts_on||'');setB(x.ends_on||'')}},[edit,x.starts_on,x.ends_on])
  useEffect(()=>{if(edit)ref.current?.querySelector('input')?.focus()},[edit])
  const shown=x.starts_on?`${auDate(x.starts_on)}${x.ends_on?` – ${auDate(x.ends_on)}`:''}`:''
  const commit=async()=>{if(a===(x.starts_on||'')&&b===(x.ends_on||'')){setEdit(false);return}if(await onSave({starts_on:a,ends_on:b}))setEdit(false)}
  if(!can)return <strong>{shown||'—'}</strong>
  if(!edit)return <button type="button" className="le-btn" aria-label={`Edit date of ${x.title}`} onClick={()=>setEdit(true)}><strong className={shown?'':'le-empty'}>{shown||'Add a date'}</strong></button>
  return <span ref={ref} className="le-duration" onBlur={e=>{if(!e.currentTarget.contains(e.relatedTarget))commit()}} onKeyDown={e=>{if(e.key==='Enter'){e.preventDefault();commit()}if(e.key==='Escape')setEdit(false)}}>
    <input className="fv-input" type="date" aria-label={`Start of ${x.title}`} value={a} onChange={e=>setA(e.target.value)}/>
    <input className="fv-input" type="date" aria-label={`End of ${x.title}`} value={b} onChange={e=>setB(e.target.value)}/></span>
}

function Text({value,can,label,onSave,strong,muted,link,short,placeholder,suffix=''}){
  const[edit,setEdit]=useState(false),[draft,setDraft]=useState(value),ref=useRef(null)
  useEffect(()=>{if(!edit)setDraft(value)},[value,edit])
  useEffect(()=>{if(edit)ref.current?.focus()},[edit])
  const commit=async()=>{const v=String(draft).trim();if(v===String(value||'')){setEdit(false);return}if(await onSave(v))setEdit(false)}
  if(edit)return <input ref={ref} className="fv-input le-input" aria-label={label} value={draft} onChange={e=>setDraft(e.target.value)} onBlur={commit} onKeyDown={e=>{if(e.key==='Enter'){e.preventDefault();commit()}if(e.key==='Escape')setEdit(false)}}/>
  let shown=value?(short&&link?(()=>{try{return new URL(value).hostname.replace(/^www\./,'')}catch{return value}})():value)+(value?suffix:''):''
  const text=shown||<span className="le-empty">{placeholder||'—'}</span>
  const cls=['rs-cell',strong&&'rs-strong',muted&&'rs-muted'].filter(Boolean).join(' ')
  return <span className={cls} title={short?value:undefined}>{can?<button type="button" className="le-btn" aria-label={`Edit ${label}`} onClick={()=>setEdit(true)}>{text}</button>:<span>{text}</span>}
    {link&&value&&<a className="cf-link" href={value} target="_blank" rel="noreferrer" aria-label={`Open ${value}`}><ExternalLink size={12}/></a>}</span>
}

function AddDate({onSave,onCancel}){
  const[f,setF]=useState({country:'AU',event_type:'course_application_deadline',title:'',source_url:'https://',precision:'exact',starts_on:'',ends_on:'',wording:'',warning_days:'14',scope:'country_reference',entity_type:'',entity_id:'',refresh_layer:''}),[more,setMore]=useState(false)
  const set=(k,v)=>setF(x=>({...x,[k]:v}))
  const ok=f.title.trim().length>2&&/^https?:\/\/.+/.test(f.source_url)&&(f.precision!=='source_vague'||f.wording.trim())&&(f.precision!=='exact'||f.starts_on)
  const fields=Object.fromEntries(Object.entries(f).filter(([k,v])=>v!==''&&(more||!['scope','entity_type','entity_id','refresh_layer'].includes(k))))
  return <div className="rs-add" data-add-date>
    <div className="rs-add-grid">
      <label className="rs-wide"><small>What</small><input className="fv-input" value={f.title} onChange={e=>set('title',e.target.value)} placeholder="e.g. UQ Semester 1 2027 application deadline"/></label>
      <label><small>Kind</small><select className="fv-filter" value={f.event_type} onChange={e=>set('event_type',e.target.value)}>{Object.entries(KINDS).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></label>
      <label><small>Country</small><select className="fv-filter" value={f.country} onChange={e=>set('country',e.target.value)}>{Object.entries(COUNTRY).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></label>
      <label><small>Precision</small><select className="fv-filter" value={f.precision} onChange={e=>set('precision',e.target.value)}>{Object.entries(PRECISION).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></label>
      <label><small>Date</small><input className="fv-input" type="date" value={f.starts_on} onChange={e=>set('starts_on',e.target.value)}/></label>
      <label><small>End date (optional)</small><input className="fv-input" type="date" value={f.ends_on} onChange={e=>set('ends_on',e.target.value)}/></label>
      <label className="rs-wide"><small>Source address</small><input className="fv-input" value={f.source_url} onChange={e=>set('source_url',e.target.value)}/></label>
      <label className="rs-wide"><small>Wording from the source {f.precision==='source_vague'?'(required)':'(optional)'}</small><input className="fv-input" value={f.wording} onChange={e=>set('wording',e.target.value)} placeholder="e.g. Applications close late November"/></label>
      <label><small>Warn this many days before</small><input className="fv-input" type="number" min="0" max="365" value={f.warning_days} onChange={e=>set('warning_days',e.target.value)}/></label>
    </div>
    <button type="button" className="cf-link rs-more" onClick={()=>setMore(m=>!m)} aria-expanded={more}>{more?'Fewer options':'More: tie it to a provider, course or scholarship'}</button>
    {more&&<div className="rs-add-grid">
      <label><small>Tied to</small><select className="fv-filter" value={f.scope} onChange={e=>set('scope',e.target.value)}><option value="country_reference">Nothing (reference only)</option><option value="provider">A provider</option><option value="course">A course</option><option value="scholarship">A scholarship</option><option value="source">A source</option></select></label>
      {f.scope!=='country_reference'&&<label className="rs-wide"><small>Its ID (from the record's page)</small><input className="fv-input" value={f.entity_id} onChange={e=>{set('entity_id',e.target.value.trim());set('entity_type',f.scope)}}/></label>}
      <label><small>Refresh when it arrives</small><select className="fv-filter" value={f.refresh_layer} onChange={e=>set('refresh_layer',e.target.value)}><option value="">No refresh</option><option value="1">Layer 1 (registers)</option><option value="2">Layer 2 (pages)</option></select></label>
    </div>}
    <div className="l3c-actions"><Button compact onClick={onCancel}>Cancel</Button><Button compact variant="primary" disabled={!ok} onClick={()=>onSave(fields)}><Plus size={13}/>Add date</Button></div>
  </div>
}
