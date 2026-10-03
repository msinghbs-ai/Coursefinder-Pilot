// Scholarship record (v2.15.171, Platform Admin 3 Oct 2026 23:30: the scholarship screens follow the mockup).
// One row per fact, each with where it came from (read from the page, or entered by hand), the page's own words, and a
// Change button. A value entered by hand is kept: the readers leave it alone until someone hands it back with
// "Let automation update this". Read: public.admin_scholarship_record_read(id); write: public.admin_scholarship_edit
// (set_audience, set_nationalities, set_core, release). v2.15.172: publishing status and holds are handled in Layer 4;
// the record lists the courses it is linked to (migration 20261004000100).
// Migration 20261003003100_cf247_scholarship_screens_to_mockup.
import React,{useEffect,useMemo,useState}from'react'
import{ExternalLink,RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,EmptyInline,Loading,fmtDate,fmtDateTime,fmtNumber}from'./ui-kit'
import{criterionLabel}from'./ScholarshipEligibility'

const AUD={international:'International students',domestic:'Domestic students only',international_and_domestic:'International and domestic students',not_stated:'Not stated on the page'}
const DURATION={one_off:'One-off payment',first_year:'First year only',annual:'Paid each year',annual_program_duration:'Each year, for the length of the course',program_duration:'For the length of the course',per_semester:'Paid each semester'}
const FIELD={audience:'Who it is for',nationalities:'Nationalities',award_amount:'Value',award_percentage:'Value',application_close_date:'Application closes',source_url:'Page'}
const errText=e=>e?.message||String(e)
const quote=t=>t?`Page: “${String(t).trim()}”`:''

export default function ScholarshipRecord({id,onError,onChanged}){
  const[d,setD]=useState(null),[failed,setFailed]=useState(''),[editing,setEditing]=useState(''),[busy,setBusy]=useState(false)
  const load=async()=>{setFailed('');try{const{data,error}=await supabase.rpc('admin_scholarship_record_read',{p_id:id});if(error)throw error;setD(data||{})}catch(e){setFailed(errText(e))}}
  useEffect(()=>{setD(null);setEditing('');load()},[id])
  const names=useMemo(()=>Object.fromEntries((d?.nationality_terms||[]).map(t=>[t.code,t.name])),[d])
  if(failed&&!d)return <section className="sr-panel"><EmptyInline text={`The scholarship record could not be loaded: ${failed}`}/><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></section>
  if(!d)return <Loading label="Loading the scholarship…"/>
  const locks=d.locks||{},can=Boolean(d.can_edit)&&!busy
  const run=async(action,args)=>{setBusy(true);try{const{error}=await supabase.rpc('admin_scholarship_edit',{p_scholarship_id:id,p_action:action,p_args:args});if(error)throw error;setEditing('');await load();onChanged?.()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const nats=Array.isArray(d.nationalities)?d.nationalities:[],phr=d.nationality_phrases||{}
  const tiers=Array.isArray(d.tiers)?d.tiers:[]
  const tierText=tiers.map(t=>t.percentage!=null?`${fmtNumber(t.percentage)}%`:t.amount!=null?`${t.currency&&t.currency!=='AUD'?t.currency+' ':'A$'}${fmtNumber(t.amount)}`:t.label).join(', ')
  const crit=(d.criteria||[]).filter(c=>c.criterion_type!=='published_eligibility_narrative').map(c=>criterionLabel(c)).filter(([,v])=>v)
  const narrative=(d.criteria||[]).find(c=>c.criterion_type==='published_eligibility_narrative')
  const levels=Array.isArray(d.course_levels)?d.course_levels:[],courseList=Array.isArray(d.course_list)?d.course_list:[]
  const rows=[
    {k:'audience',label:'Who it is for',value:AUD[d.audience]||'Not read yet',lock:'audience',quote:quote(d.audience_phrase),editor:AudienceEditor},
    {k:'nationalities',label:'Nationalities',value:nats.length?nats.map(c=>names[c]||c).join(', '):'Any nationality',lock:'nationalities',quote:Object.values(phr).length?quote(Object.values(phr).join('”, “')):'',editor:NationalityEditor},
    {k:'value',label:'Value',value:d.value_label||'Value not stated',lock:locks.award_amount?'award_amount':'award_percentage',locked:Boolean(locks.award_amount||locks.award_percentage||locks.award_value_type),quote:[quote(d.page_words),tiers.length>1?`Amounts on the page: ${tierText}`:''].filter(Boolean).join(' · '),editor:ValueEditor},
    {k:'duration',label:'How long',value:DURATION[d.duration_basis]||'Not stated',quote:''},
    {k:'who',label:'Who qualifies',value:crit.length?crit.map(([a,b])=>`${a}: ${b}`).join(' · '):'Not read from the page yet',quote:narrative?.human_text?quote(narrative.human_text):(narrative?.value_text?quote(narrative.value_text):'')},
    {k:'application',label:'Application',value:`${d.application_required===false?'No application needed':d.application_required?'Application needed':'Application not stated'} · ${d.application_close_date?`closes ${fmtDate(d.application_close_date)}`:'no closing date stated'}`,lock:'application_close_date',quote:'',editor:CloseDateEditor},
    {k:'page',label:'Provider page',value:d.page?<a href={d.page} target="_blank" rel="noreferrer">{d.page.replace(/^https?:\/\//,'').slice(0,70)} <ExternalLink size={12}/></a>:'No provider page',lock:'source_url',quote:d.page_read_at?`Page last read ${fmtDateTime(d.page_read_at)}`:'Not read yet',editor:PageEditor},
    {k:'courses',label:'Courses it applies to',value:Number(d.courses)?`${fmtNumber(d.courses)} course${Number(d.courses)===1?'':'s'}${levels.length?' — '+levels.map(l=>`${l.level} ${fmtNumber(l.courses)}`).join(' · '):''}`:'No course linked yet',source:'Course links',quote:'',courses:courseList,link:['#scholarships?tab=links','Open Course links']},
  ]
  return <section className="sr-panel" data-scholarship-record>
    <header className="sr-head">
      <div className="sr-meta"><span>{d.provider||'—'}</span>{d.page&&<a href={d.page} target="_blank" rel="noreferrer">Provider page <ExternalLink size={11}/></a>}</div>
      {!d.can_edit&&<p className="sr-reasons">You can view this scholarship. Curators and above can change it.</p>}
    </header>
    {rows.map(r=>{const locked=r.locked??Boolean(r.lock&&locks[r.lock]),open=editing===r.k,Ed=r.editor
      return <div className="sr-row" key={r.k} data-sr-row={r.k}>
        <div className="sr-row-top">
          <div className="sr-row-main"><small>{r.label}</small><strong>{r.value}</strong></div>
          <div className="sr-row-actions">
            <span className="sch-chip" data-sr-source>{r.source||(locked?'Entered by hand':'Read from page')}</span>
            {Ed&&d.can_edit&&<Button compact onClick={()=>setEditing(open?'':r.k)} disabled={busy} aria-label={`${open?'Close':'Change'} ${r.label}`}>{open?'Close':'Change'}</Button>}
            {r.link&&<a className="cf-btn compact" href={r.link[0]}>{r.link[1]}</a>}
          </div>
        </div>
        {r.quote&&<p className="sr-quote">{r.quote}</p>}
        {r.courses&&r.courses.length>0&&<details className="sr-courses" data-sr-courses><summary>Show the courses{Number(d.courses)>r.courses.length?` (first ${fmtNumber(r.courses.length)} of ${fmtNumber(d.courses)})`:''}</summary><ul>{r.courses.map(c=><li key={c.id}><a href={`#courses?id=${c.id}`}>{c.title}</a>{c.level&&<small>{c.level}{c.code?` · ${c.code}`:''}</small>}</li>)}</ul></details>}
        {locked&&d.can_edit&&<p className="sr-lock">Entered by hand · <button type="button" className="sr-link" disabled={!can} onClick={()=>window.confirm(`Let automation update ${r.label.toLowerCase()} again? The next reading of the page may change it.`)&&run('release',{field:r.lock})}>Let automation update this</button></p>}
        {open&&Ed&&<Ed d={d} names={names} busy={!can} onCancel={()=>setEditing('')} onSave={(action,args)=>run(action,args)}/>}
      </div>})}
    <div className="sr-foot">
      <small>History</small>
      {(d.history||[]).length?<ul className="sr-history">{d.history.map((h,i)=><li key={i}><span>{fmtDateTime(h.at)}</span><b>{h.action==='release'?'Handed back to automation':'Changed'}{h.field?` · ${FIELD[h.field]||h.field.replace(/_/g,' ')}`:''}</b>{h.reason&&<em>{h.reason}</em>}</li>)}</ul>:<p className="sr-quote">No changes by hand yet.</p>}
    </div>
  </section>
}

function Shell({children,onSave,onCancel,busy,reason,setReason,ok=true}){
  return <form className="sr-edit" onSubmit={e=>{e.preventDefault();if(ok)onSave()}}>
    {children}
    <label><small>Reason (kept in the history)</small><input value={reason} onChange={e=>setReason(e.target.value)} placeholder="e.g. Checked on the provider page"/></label>
    <p className="sr-hint">Saved as entered by a person; automation will not change it until you hand it back.</p>
    <div className="sr-edit-actions"><Button type="submit" variant="primary" disabled={busy||!ok}>Save</Button><Button onClick={onCancel}>Cancel</Button></div>
  </form>
}
function AudienceEditor({d,busy,onSave,onCancel}){
  const[v,setV]=useState(d.audience||'not_stated'),[reason,setReason]=useState('')
  return <Shell busy={busy} onCancel={onCancel} reason={reason} setReason={setReason} onSave={()=>onSave('set_audience',{value:v,reason})}>
    <label><small>Who it is for</small><select value={v} onChange={e=>setV(e.target.value)}>{Object.entries(AUD).map(([k,l])=><option key={k} value={k}>{l}</option>)}</select></label>
  </Shell>
}
function NationalityEditor({d,names,busy,onSave,onCancel}){
  const[sel,setSel]=useState(new Set(d.nationalities||[])),[q,setQ]=useState(''),[reason,setReason]=useState('')
  const terms=(d.nationality_terms||[]).filter(t=>!q||t.name.toLowerCase().includes(q.toLowerCase())||sel.has(t.code))
  const flip=c=>setSel(s=>{const n=new Set(s);n.has(c)?n.delete(c):n.add(c);return n})
  return <Shell busy={busy} onCancel={onCancel} reason={reason} setReason={setReason} onSave={()=>onSave('set_nationalities',{value:[...sel],reason})}>
    <p className="sr-hint">{sel.size?`Named: ${[...sel].map(c=>names[c]||c).join(', ')}`:'None named: open to any nationality.'}</p>
    <label><small>Find a country or region</small><input type="search" value={q} onChange={e=>setQ(e.target.value)} placeholder="e.g. Vietnam"/></label>
    <div className="sr-checks">{terms.map(t=><label key={t.code}><input type="checkbox" checked={sel.has(t.code)} onChange={()=>flip(t.code)}/>{t.name}</label>)}</div>
  </Shell>
}
function ValueEditor({d,busy,onSave,onCancel}){
  const[kind,setKind]=useState(d.award_value_type==='percentage'?'award_percentage':'award_amount'),[v,setV]=useState(String((kind==='award_percentage'?d.award_percentage:d.award_amount)??'')),[reason,setReason]=useState('')
  const ok=/^\d+(\.\d+)?$/.test(v.trim())&&Number(v)>0&&(kind!=='award_percentage'||Number(v)<=100)
  return <Shell busy={busy} ok={ok} onCancel={onCancel} reason={reason} setReason={setReason} onSave={()=>onSave('set_core',{field:kind,value:v.trim(),reason})}>
    <label><small>The page states</small><select value={kind} onChange={e=>{setKind(e.target.value);setV('')}}><option value="award_amount">An amount (A$)</option><option value="award_percentage">A percentage of tuition</option></select></label>
    <label><small>{kind==='award_percentage'?'Percentage (1 to 100)':'Amount in A$'}</small><input inputMode="decimal" value={v} onChange={e=>setV(e.target.value)} placeholder={kind==='award_percentage'?'e.g. 20':'e.g. 10000'}/></label>
  </Shell>
}
function CloseDateEditor({d,busy,onSave,onCancel}){
  const[v,setV]=useState(d.application_close_date||''),[reason,setReason]=useState('')
  return <Shell busy={busy} onCancel={onCancel} reason={reason} setReason={setReason} onSave={()=>onSave('set_core',{field:'application_close_date',value:v||null,reason})}>
    <label><small>Applications close (leave empty if the page states no date)</small><input type="date" value={v} onChange={e=>setV(e.target.value)}/></label>
  </Shell>
}
function PageEditor({d,busy,onSave,onCancel}){
  const[v,setV]=useState(d.page||''),[reason,setReason]=useState('')
  const ok=/^https?:\/\/\S+\.\S+$/i.test(v.trim())
  return <Shell busy={busy} ok={ok} onCancel={onCancel} reason={reason} setReason={setReason} onSave={()=>onSave('set_core',{field:'source_url',value:v.trim(),reason})}>
    <label><small>Provider page address</small><input type="url" value={v} onChange={e=>setV(e.target.value)} placeholder="https://"/></label>
  </Shell>
}
