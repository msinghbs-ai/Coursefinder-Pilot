// Scholarship record (v2.15.171, Platform Admin 3 Oct 2026 23:30: the scholarship screens follow the mockup).
// One row per fact, each with where it came from (read from the page, or entered by hand), the page's own words, and a
// Change button. A value entered by hand is kept: the readers leave it alone until someone hands it back with
// "Let automation update this". Read: public.admin_scholarship_record_read(id); write: public.admin_scholarship_edit
// (set_audience, set_nationalities, set_core, release). v2.15.172: publishing status and holds are handled in Layer 4;
// the record lists the courses it is linked to (migration 20261004000100).
// Migration 20261003003100_cf247_scholarship_screens_to_mockup.
// v2.15.243 (CF-247, Platform Admin 11 Oct 2026): applications open, applications close (with rounds) and study start, each with
// the words on the page; each course link with its proof (the course the page names, or the levels and fields it states) and the
// courses the page excludes; and the Evidence & extraction journey: page found, read through the scraper, saved copy, what was read
// from it, what it changed and the publishing checks (migrations 20261011008400 and 20261011008500).
import React,{useEffect,useMemo,useState}from'react'
import{ExternalLink,RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,EmptyInline,Loading,fmtDate,fmtDateTime,fmtNumber}from'./ui-kit'
import{criterionLabel}from'./ScholarshipEligibility'

const AUD={international:'International students',domestic:'Domestic students only',international_and_domestic:'International and domestic students',not_stated:'Not stated on the page'}
const DURATION={one_off:'One-off payment',first_year:'First year only',annual:'Paid each year',annual_program_duration:'Each year, for the length of the course',program_duration:'For the length of the course',per_semester:'Paid each semester'}
const FIELD={audience:'Who it is for',nationalities:'Nationalities',award_amount:'Value',award_percentage:'Value',application_open_date:'Applications open',application_close_date:'Applications close',source_url:'Page'}
const MONTHS=['January','February','March','April','May','June','July','August','September','October','November','December']
// a date the page gives as a month only ("March 2027") is shown as the month
const dateText=(v,prec)=>{if(!v)return '';if(prec==='month'){const[y,m]=String(v).split('-');return `${MONTHS[Number(m)-1]||''} ${y}`.trim()}return fmtDate(v)}
const hitText=h=>h?(h.date?fmtDate(h.date):dateText(`${h.month}-01`,'month')):''
const LINK_KIND={course_code:'Course code named on the page',course_title:'Course named on the page',levels_fields:'Study level or field stated on the page',english_course:'English language course scholarship'}
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
  const ev=d.evidence||{},facts=ev.facts||{},dates=facts.dates||{},rounds=Array.isArray(dates.close_rounds)?dates.close_rounds:[],links=ev.apply_result?.links||{}
  const excluded=Array.isArray(facts.named_courses?.excluded)?facts.named_courses.excluded:[]
  const linkWhy=[links.basis==='page_named_course'?'Linked to the courses the page names.':links.basis==='sweep_level_field_scope'?'Linked by the study levels and fields the page states.':links.basis==='none'?'The page names no course, level or field, so it is not linked to courses (it can still be published).':'',
    excluded.length?`Excluded by the page: ${excluded.map(x=>x.title||x.code).join(', ')}.`:'',
    (links.named_not_matched||[]).length?`Named on the page but not found among the provider's courses: ${links.named_not_matched.map(x=>x.title||x.code).join(', ')}.`:''].filter(Boolean).join(' ')
  const rows=[
    {k:'audience',label:'Who it is for',value:AUD[d.audience]||'Not read yet',lock:'audience',quote:quote(d.audience_phrase),editor:AudienceEditor},
    {k:'nationalities',label:'Nationalities',value:nats.length?nats.map(c=>names[c]||c).join(', '):'Any nationality',lock:'nationalities',quote:Object.values(phr).length?quote(Object.values(phr).join('”, “')):'',editor:NationalityEditor},
    {k:'value',label:'Value',value:d.value_label||'Value not stated',lock:locks.award_amount?'award_amount':'award_percentage',locked:Boolean(locks.award_amount||locks.award_percentage||locks.award_value_type),quote:[quote(d.page_words),tiers.length>1?`Amounts on the page: ${tierText}`:''].filter(Boolean).join(' · '),editor:ValueEditor},
    {k:'duration',label:'How long',value:DURATION[d.duration_basis]||'Not stated',quote:''},
    {k:'who',label:'Who qualifies',value:crit.length?crit.map(([a,b])=>`${a}: ${b}`).join(' · '):'Not read from the page yet',quote:narrative?.human_text?quote(narrative.human_text):(narrative?.value_text?quote(narrative.value_text):'')},
    {k:'open',label:'Applications open',value:d.application_open_date?dateText(d.application_open_date,locks.application_open_date?'day':d.application_open_precision):'Not stated on the page',lock:'application_open_date',quote:quote(dates.open?.text),editor:OpenDateEditor},
    {k:'close',label:'Applications close',value:d.application_close_date?dateText(d.application_close_date,locks.application_close_date?'day':d.application_close_precision):'Not stated on the page',lock:'application_close_date',quote:[quote(dates.close?.text),rounds.length>1?`Rounds on the page: ${rounds.map(hitText).join(', ')}`:''].filter(Boolean).join(' · '),editor:CloseDateEditor},
    {k:'start',label:'Study start',value:d.study_start_label||'Not stated on the page',quote:quote(facts.study_start?.text)},
    {k:'application',label:'Application',value:d.application_required===false?'No application needed':d.application_required?'Application needed':'Not stated',quote:''},
    {k:'page',label:'Provider page',value:d.page?<a href={d.page} target="_blank" rel="noreferrer">{d.page.replace(/^https?:\/\//,'').slice(0,70)} <ExternalLink size={12}/></a>:'No provider page',lock:'source_url',quote:d.page_read_at?`Page last read ${fmtDateTime(d.page_read_at)}`:'Not read yet',editor:PageEditor},
    {k:'courses',label:'Courses it applies to',value:Number(d.courses)?`${fmtNumber(d.courses)} course${Number(d.courses)===1?'':'s'}${levels.length?' — '+levels.map(l=>`${l.level} ${fmtNumber(l.courses)}`).join(' · '):''}`:links.basis==='none'?'No specific course: the page names no course, level or field':'Not linked to a course',source:'Read from page',quote:linkWhy,courses:courseList},
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
        {r.courses&&r.courses.length>0&&<details className="sr-courses" data-sr-courses><summary>Show the courses and why each is linked{Number(d.courses)>r.courses.length?` (first ${fmtNumber(r.courses.length)} of ${fmtNumber(d.courses)})`:''}</summary><ul>{r.courses.map(c=><li key={c.id}><a href={`#courses?id=${c.id}`}>{c.title}</a><small>{[c.level,c.code].filter(Boolean).join(' · ')}</small><small className="sr-proof" data-sr-proof>{c.by_hand?'Linked by a person':c.proof?`${LINK_KIND[c.proof.kind]||'Read from page'}${c.proof.named?`: ${c.proof.named}`:''}${c.proof.text?` — “${c.proof.text}”`:''}`:'Linked before proofs were kept; updated on the next read'}</small></li>)}</ul></details>}
        {locked&&d.can_edit&&<p className="sr-lock">Entered by hand · <button type="button" className="sr-link" disabled={!can} onClick={()=>window.confirm(`Let automation update ${r.label.toLowerCase()} again? The next reading of the page may change it.`)&&run('release',{field:r.lock})}>Let automation update this</button></p>}
        {open&&Ed&&<Ed d={d} names={names} busy={!can} onCancel={()=>setEditing('')} onSave={(action,args)=>run(action,args)}/>}
      </div>})}
    <EvidenceJourney d={d}/>
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
// The evidence journey: how this scholarship's facts were found, read, saved, extracted and applied (CF-247, 11 Oct 2026)
const READ={read:'Read',waiting_scraper:'Waiting for the scraper (no credit or service); tried again within the hour',scrape_failed:'The scraper could not read it; tried again in 6 hours',blocked:'The site refused the scraper; tried again in 2 days',gone:'The page no longer exists',too_thin:'Too little text on the page',name_mismatch:'The page does not name this scholarship',fetch_failed:'Could not be read'}
const FOUND={discovered:'Found on the provider\'s site',admitted:'Found on the provider\'s site and admitted as a new scholarship',hand:'Entered by a person',manual:'Entered by a person'}
const CHANGE={award_value:'Value',application_close_date:'Applications close',application_open_date:'Applications open',study_start:'Study start',course_links:'Course links',first_party_url:'Provider page recorded',register_source_retired:'Kept as a provider-page record (national register source retired)',register_record_retired:'Set inactive (national register record, no provider page)'}
function EvidenceJourney({d}){
  const ev=d.evidence
  if(!ev)return <details className="sr-journey" data-sr-journey><summary>Evidence &amp; extraction</summary><p className="sr-quote">This scholarship has no provider page to read yet.</p></details>
  const f=ev.facts||{},v=f.value||{},dt=f.dates||{},nc=f.named_courses||{},links=ev.apply_result?.links||{},saved=ev.saved
  const valueText=v.type==='percentage'?`${fmtNumber(v.percentage)}% of tuition`:v.type==='fixed_amount'?`${v.currency||''} ${fmtNumber(v.amount)}`.trim():v.type==='ambiguous'?'More than one value on the page (needs a person)':'Not stated'
  const step=(n,title,body,tone='')=><li className={`sr-step ${tone}`} data-sr-step={n}><b>{title}</b><div>{body}</div></li>
  return <details className="sr-journey" data-sr-journey open>
    <summary>Evidence &amp; extraction</summary>
    <ol className="sr-steps">
      {step('page','1. Provider page',<><a href={ev.final_url||ev.url} target="_blank" rel="noreferrer">{String(ev.final_url||ev.url||'').replace(/^https?:\/\//,'').slice(0,80)} <ExternalLink size={11}/></a><small>{FOUND[ev.found_by]||'From the provider\'s own site'}</small></>)}
      {step('read','2. Read through the scraper',<><span>{READ[ev.read_status]||ev.read_status||'Not read yet'}{ev.read_at?` · ${fmtDateTime(ev.read_at)}`:''}{ev.http_status?` · HTTP ${ev.http_status}`:''}</span><small>{ev.fetched_via==='firecrawl'?'Scraper (Firecrawl, rendered page)':ev.fetched_via==='direct'?'Direct read (before 11 Oct 2026)':'—'} · {fmtNumber(ev.credits||0)} credit{Number(ev.credits)===1?'':'s'} used on this page · next read {ev.next_read_at?fmtDateTime(ev.next_read_at):'—'}</small></>,ev.read_status==='read'?'ok':'warn')}
      {step('saved','3. Saved copy',saved?<><span>Version {fmtNumber(saved.version)} of {fmtNumber(ev.versions)} · saved {fmtDateTime(saved.captured_at)}</span><small><a href={`#evidence?evidence_id=${saved.evidence_id}`}>Open in Evidence</a> · fingerprint {String(saved.hash||'').slice(0,12)}</small></>:<span>No saved copy yet</span>)}
      {step('name','4. Page names the scholarship',ev.name_check?<span>{ev.name_check.ok?'Yes':'No'}{ev.name_check.basis?` · ${String(ev.name_check.basis).replace(/_/g,' ')}`:''}</span>:<span>Not checked yet</span>,ev.name_check?.ok?'ok':'')}
      {step('facts','5. What was read from the page',<dl className="sr-facts">
        <dt>Value</dt><dd>{valueText}{v.context&&<q>{v.context}</q>}</dd>
        <dt>Applications open</dt><dd>{hitText(dt.open)||'Not stated'}{dt.open?.text&&<q>{dt.open.text}</q>}</dd>
        <dt>Applications close</dt><dd>{hitText(dt.close)||'Not stated'}{dt.close?.text&&<q>{dt.close.text}</q>}{(dt.close_rounds||[]).length>1&&<small>Rounds: {(dt.close_rounds||[]).map(hitText).join(', ')}</small>}</dd>
        <dt>Study start</dt><dd>{f.study_start?.label||'Not stated'}{f.study_start?.text&&<q>{f.study_start.text}</q>}</dd>
        <dt>Study levels</dt><dd>{(f.levels||[]).length?(f.levels||[]).map(x=>String(x).replace(/_/g,' ')).join(', '):'None stated'}{f.levels_text&&<q>{f.levels_text}</q>}</dd>
        <dt>Fields</dt><dd>{(f.fields||[]).length?`${(f.fields||[]).length} field${(f.fields||[]).length===1?'':'s'}${(f.faculties||[]).length?` (${f.faculties.join(', ')})`:''}`:'None stated'}{f.fields_text&&<q>{f.fields_text}</q>}</dd>
        <dt>Courses named</dt><dd>{[...(nc.codes||[]).map(x=>x.code),...(nc.titles||[]).map(x=>x.title)].join(', ')||'None'}{(nc.excluded||[]).length>0&&<small>Excluded: {(nc.excluded||[]).map(x=>x.title||x.code).join(', ')}</small>}</dd>
        <dt>Reader</dt><dd>{ev.extractor||'—'}</dd>
      </dl>)}
      {step('applied','6. What it changed',<><span>{ev.applied_at?`Applied ${fmtDateTime(ev.applied_at)}`:'Not applied yet'} · course links: {links.basis==='page_named_course'?'courses the page names':links.basis==='sweep_level_field_scope'?'levels and fields the page states':links.basis==='none'?'none (the page names no course, level or field)':'—'}{links.courses!=null?` · ${fmtNumber(links.courses)} course${Number(links.courses)===1?'':'s'}`:''}{links.excluded?` · ${fmtNumber(links.excluded)} excluded`:''}</span>
        {(ev.changes||[]).length>0&&<ul className="sr-history">{ev.changes.map((c,i)=><li key={i}><span>{fmtDateTime(c.at)}</span><b>{CHANGE[c.field]||String(c.field).replace(/_/g,' ')}</b></li>)}</ul>}</>)}
      {step('publish','7. Publishing checks',(d.held_reasons||[]).length?<span>Held: {(d.held_reasons||[]).join(' · ')}</span>:<span>{d.status==='published'?'Published':'Passes every check'}</span>,(d.held_reasons||[]).length?'warn':'ok')}
    </ol>
  </details>
}
function OpenDateEditor({d,busy,onSave,onCancel}){
  const[v,setV]=useState(d.application_open_date||''),[reason,setReason]=useState('')
  return <Shell busy={busy} onCancel={onCancel} reason={reason} setReason={setReason} onSave={()=>onSave('set_core',{field:'application_open_date',value:v||null,reason})}>
    <label><small>Applications open (leave empty if the page states no date)</small><input type="date" value={v} onChange={e=>setV(e.target.value)}/></label>
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
