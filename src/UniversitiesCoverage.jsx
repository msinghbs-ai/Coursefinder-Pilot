// Coverage & completeness › Universities (CF-247 Decision 254, Platform Admin 5 Oct 07:36).
// One row per target university: adapter state and admitted fields, exclusions, central English rule and calendar,
// and how many courses hold intakes, English and fees, with where each value came from. Open a university to see its
// courses in a table (5 Oct 15:36: with location, delivery and entry requirement). A Platform Admin can attach a central English or key-dates page (read through Firecrawl, then
// approved in Layer 4 Review › Attributes).
import React,{useEffect,useMemo,useState}from'react'
import{RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{fmtMoney,fmtShare}from'./lib/format'
import{Button,Empty,Loading,Pager,SectionTitle,fmtDateTime,fmtNumber}from'./ui-kit'

const COUNTRY_NAME={AU:'Australia',NZ:'New Zealand',CA:'Canada'}
const ADAPTER={admitting:['Admitting','success'],testing:['Testing','warning'],off:['Switched off','neutral']}
const FIELD={intakes:'Intakes',english:'English',fee:'Fees',delivery:'Delivery',exit_awards:'Exit awards'}
// Delivery as held in the catalogue (security.delivery_mode_from_text)
const DELIVERY={on_campus:'On campus',online:'Online',on_campus_and_online:'On campus and online',blended:'Blended'}
const POLICY={approved:['Approved','success'],proposed:['Waiting for approval','warning'],no_values:['Read, no rule found','neutral']}
// Where a held value came from
const SOURCE={adapter:['Course page (adapter)','success'],central:['Central rule','info'],reader:['Course page (general reader)','neutral'],hand:['Entered by hand','violet'],other:['Other source','neutral'],missing:['Missing','danger'],catalogue:['Registered campus','info']}
const SHOW=[['all','All courses'],['missing','Something missing'],['excluded','Excluded'],['adapter','Read by the adapter'],['central','From a central rule']]
const errText=e=>e?.message||String(e)

function Pill({tone='neutral',children,title}){return <span className={`cf-chip tone-${tone}`} title={title}>{children}</span>}
function SourcePill({source}){const[l,t]=SOURCE[source]||[source,'neutral'];return <Pill tone={t}>{l}</Pill>}

function Coverage({part,courses}){
  if(!part)return '—'
  const held=Number(part.held||0)
  const tone=!courses||held===0?'danger':held>=courses?'success':'warning'
  return <div className="uc-cov"><Pill tone={tone}>{fmtShare(part.held||0,courses)}</Pill><small className="sl-sub">{fmtNumber(part.held||0)} of {fmtNumber(courses)}</small>
    <span className="uc-src">{part.adapter>0&&<Pill tone="success" title="From the course page, read by the adapter">adapter {fmtNumber(part.adapter)}</Pill>}
      {part.central>0&&<Pill tone="info" title="From the university's central rule">central {fmtNumber(part.central)}</Pill>}
      {part.reader>0&&<Pill title="From the course page, general reader">reader {fmtNumber(part.reader)}</Pill>}
      {part.excluded>0&&<Pill tone="warning" title="Course readings excluded from admission">excluded {fmtNumber(part.excluded)}</Pill>}</span></div>
}

function PolicyCell({p,pages,kind}){
  const own=(pages||[]).filter(x=>x.kind===kind)
  const[l,t]=p?(POLICY[p.status]||[p.status,'neutral']):['None','neutral']
  return <div className="uc-policy"><Pill tone={t}>{l}</Pill>{p?.url&&<a className="cf-link" href={p.url} target="_blank" rel="noreferrer" title={p.url}>page</a>}
    {own.length>0&&<small className="sl-sub">{fmtNumber(own.length)} attached{own.some(x=>x.status==='found')?' · waiting to be read':''}</small>}</div>
}

function AttachPage({u,onDone,onError}){
  const[kind,setKind]=useState('english_policy'),[url,setUrl]=useState(''),[busy,setBusy]=useState(false)
  const add=async()=>{const reason=window.prompt(`Attach this ${kind==='english_policy'?'central English requirements':'key-dates'} page to ${u.name}? It is read through Firecrawl (evidence kept) and parsed into a proposal for approval in Layer 4 Review › Attributes. Give the reason (kept in the log).`,'');if(!reason)return
    setBusy(true);try{const{error}=await supabase.rpc('admin_provider_central_page',{p_action:'add',p_args:{provider_id:u.provider_id,kind,url:url.trim(),reason}});if(error)throw error;setUrl('');onDone?.()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  return <div className="uc-attach" data-central-attach={u.provider_id}>
    <select className="fv-filter" aria-label="Central page kind" value={kind} onChange={e=>setKind(e.target.value)}><option value="english_policy">Central English requirements</option><option value="intake_calendar">Key dates (term months)</option></select>
    <input className="au-search" type="url" aria-label="Central page address" placeholder="https://…" value={url} onChange={e=>setUrl(e.target.value)}/>
    <Button compact disabled={busy||!/^https?:\/\/\S+$/.test(url.trim())} onClick={add}>Attach page</Button></div>
}

function CourseTable({u,onError}){
  const[show,setShow]=useState('all'),[offset,setOffset]=useState(0),[d,setD]=useState(null),[busy,setBusy]=useState(false)
  const LIMIT=100
  useEffect(()=>{setBusy(true);supabase.rpc('admin_university_courses_read',{p_provider_id:u.provider_id,p_args:{show,limit:LIMIT,offset}})
    .then(({data,error})=>{if(error)throw error;setD(data)}).catch(e=>onError?.(errText(e))).finally(()=>setBusy(false))},[u.provider_id,show,offset])
  return <div className="uc-courses" data-university-courses={u.provider_id}>
    <div className="cf-filterbar" role="group" aria-label="Show courses">{SHOW.map(([k,l])=><button key={k} className={show===k?'active':''} onClick={()=>{setOffset(0);setShow(k)}}>{l}</button>)}</div>
    {busy&&!d?<Loading/>:(d?.courses||[]).length===0?<Empty text="No courses match."/>:<>
    <div className="cf-table-wrap"><table className="cf-table uc-course-table"><thead><tr><th>Course</th><th>Location (campus)</th><th>Delivery</th><th>Intakes</th><th>English (IELTS)</th><th>Requirement</th><th>Fee (international, annual)</th></tr></thead><tbody>
      {d.courses.map(c=><tr key={c.course_id}>
        <td><strong>{c.course}</strong><small className="sl-sub">{c.code||'—'}{c.level?` · ${String(c.level).replace(/_/g,' ')}`:''}</small>
          <span className="uc-links">{c.url&&<a className="cf-link" href={c.url} target="_blank" rel="noreferrer">course page</a>}{c.evidence_id&&<a className="cf-link" href={`#evidence?evidence_id=${encodeURIComponent(c.evidence_id)}`}>evidence</a>}
            {c.read_status&&c.read_status!=='read'&&<Pill tone="warning">{String(c.read_status).replace(/_/g,' ')}</Pill>}</span></td>
        <td><span className="uc-val">{c.location?.value||c.location?.read||'—'}</span>{c.location&&<SourcePill source={c.location.source}/>}{c.location?.value&&c.location?.read&&<small className="sl-sub" title="Read on the course page">page: {c.location.read}</small>}</td>
        <td><span className="uc-val">{c.delivery?.value?(DELIVERY[c.delivery.value]||String(c.delivery.value).replace(/_/g,' ')):'—'}</span>{c.delivery&&<SourcePill source={c.delivery.source}/>}{c.delivery?.excluded&&<Pill tone="warning">excluded</Pill>}
          {c.delivery?.read&&<small className="sl-sub" title={c.delivery.read}>page: {String(c.delivery.read).slice(0,60)}</small>}</td>
        <td><span className="uc-val">{(c.intakes?.value||[]).join(', ')||'—'}</span><SourcePill source={c.intakes?.source}/>{c.intakes?.excluded&&<Pill tone="warning">excluded</Pill>}</td>
        <td><span className="uc-val">{c.english?.value??'—'}</span><SourcePill source={c.english?.source}/>{c.english?.excluded&&<Pill tone="warning">excluded</Pill>}</td>
        <td><span className="uc-val uc-req" title={c.requirement?.read||''}>{c.requirement?.read?String(c.requirement.read).slice(0,90):'—'}</span>{c.requirement&&<SourcePill source={c.requirement.source}/>}{c.requirement?.read&&<small className="sl-sub">for review, not admitted</small>}</td>
        <td><span className="uc-val">{c.fee?.value!=null?fmtMoney(c.fee.value,c.fee.currency||'AUD'):'—'}{c.fee?.year?` (${c.fee.year})`:''}</span><SourcePill source={c.fee?.source}/>{c.fee?.excluded&&<Pill tone="warning">excluded</Pill>}</td></tr>)}
    </tbody></table></div>
    <Pager offset={offset} limit={LIMIT} total={Number(d.total||0)} onOffset={setOffset}/></>}
  </div>
}

export function UniversitiesCoverage({rank=0}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(true),[error,setError]=useState(''),[country,setCountry]=useState(''),[q,setQ]=useState(''),[state,setState]=useState(''),[open,setOpen]=useState(null)
  const load=()=>{setBusy(true);setError('');supabase.rpc('admin_universities_read',{p_args:country?{country}:{}})
    .then(({data,error})=>{if(error)throw error;setData(data)}).catch(e=>setError(errText(e))).finally(()=>setBusy(false))}
  useEffect(()=>{load()},[country])
  const rows=useMemo(()=>(data?.universities||[]).filter(u=>(!q.trim()||u.name.toLowerCase().includes(q.trim().toLowerCase()))&&(!state||(state==='none'?!u.adapter:u.adapter?.state===state))),[data,q,state])
  const tally=useMemo(()=>{const t={admitting:0,testing:0,none:0};for(const u of data?.universities||[])t[u.adapter?.state==='admitting'?'admitting':u.adapter?'testing':'none']++;return t},[data])
  const can=rank>=6
  return <section className="m-panel uc-wrap" data-universities-coverage>
    <SectionTitle title="Universities" subtitle="Each target university: its adapter, its central English rule and calendar, and how many courses hold intakes, English and fees, with where each value came from. Open a university to see its courses."
      action={<Button compact className="cf-icon-btn" title="Refresh" aria-label="Refresh" onClick={load} disabled={busy}><RefreshCw size={14}/></Button>}/>
    <section className="cf-filterbar cc-where uc-filters" aria-label="Country and university">
      <label><span>Country</span><select className="fv-filter" aria-label="Universities country" value={country} onChange={e=>setCountry(e.target.value)}><option value="">All countries</option>{Object.entries(COUNTRY_NAME).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></label>
      <label><span>University</span><input className="au-search" type="search" aria-label="Find a university" placeholder="Find a university…" value={q} onChange={e=>setQ(e.target.value)}/></label>
    </section>
    <section className="cf-filterbar" aria-label="Adapter state"><span>Adapter</span>
      {[['','All'],['admitting',`Admitting (${fmtNumber(tally.admitting)})`],['testing',`Testing (${fmtNumber(tally.testing)})`],['none',`No adapter (${fmtNumber(tally.none)})`]].map(([k,l])=><button key={k||'all'} className={state===k?'active':''} onClick={()=>setState(k)}>{l}</button>)}
    </section>
    {error&&<div className="dq-alert"><span>{error}</span></div>}
    {busy&&!data?<Loading/>:<div className="cf-table-wrap"><table className="cf-table uc-table"><thead><tr><th>University</th><th>Adapter</th><th>Central English rule</th><th>Calendar</th><th>Intakes</th><th>English</th><th>Fees</th><th></th></tr></thead><tbody>
      {rows.map(u=>{const[al,at]=u.adapter?(ADAPTER[u.adapter.state]||[u.adapter.state,'neutral']):['No adapter','neutral'];const isOpen=open===u.provider_id
        return <React.Fragment key={u.provider_id}><tr data-university-row={u.provider_id} className={isOpen?'uc-open':''}>
          <td><strong>{u.name}</strong><span className="uc-meta"><Pill>{u.country}</Pill><small className="sl-sub">{fmtNumber(u.courses)} courses · {fmtNumber(u.pages_read)} pages read</small></span></td>
          <td><Pill tone={at}>{al}</Pill>{u.adapter?.state==='admitting'&&<span className="uc-fields">{(u.adapter.fields||[]).map(f=><Pill key={f} tone="success">{FIELD[f]||f}</Pill>)}</span>}
            {Number(u.adapter?.exclusions||0)>0&&<Pill tone="warning" title="Course readings excluded from admission">{fmtNumber(u.adapter.exclusions)} excluded</Pill>}
            {u.adapter?.admit_changed_at&&<small className="sl-sub">since {fmtDateTime(u.adapter.admit_changed_at)}</small>}</td>
          <td><PolicyCell p={u.english_policy} pages={u.central_pages} kind="english_policy"/></td>
          <td><PolicyCell p={u.calendar} pages={u.central_pages} kind="intake_calendar"/></td>
          <td><Coverage part={u.intakes} courses={u.courses}/></td>
          <td><Coverage part={u.english} courses={u.courses}/></td>
          <td><Coverage part={u.fee} courses={u.courses}/></td>
          <td><Button compact aria-expanded={isOpen} onClick={()=>setOpen(isOpen?null:u.provider_id)}>{isOpen?'Close':'Open'}</Button></td></tr>
          {isOpen&&<tr className="uc-detail"><td colSpan={8}>
            {can&&<AttachPage u={u} onDone={load} onError={setError}/>}
            {(u.central_pages||[]).length>0&&<ul className="tn-list uc-pages">{u.central_pages.map((p,i)=><li key={i}><Pill tone={p.status==='read'||p.status==='parsed'?'success':p.status==='found'?'warning':'neutral'}>{p.kind==='english_policy'?'English':'Key dates'} · {String(p.status).replace(/_/g,' ')}</Pill> <a className="cf-link" href={p.url} target="_blank" rel="noreferrer">{p.url}</a>{p.read_at&&<small className="sl-sub"> read {fmtDateTime(p.read_at)}</small>}{p.evidence_id&&<a className="cf-link" href={`#evidence?evidence_id=${encodeURIComponent(p.evidence_id)}`}> evidence</a>}</li>)}</ul>}
            <CourseTable u={u} onError={setError}/></td></tr>}
        </React.Fragment>})}
      {rows.length===0&&<tr><td colSpan={8}><Empty text="No university matches."/></td></tr>}
    </tbody></table></div>}
    <p className="sl-sub uc-legend">Where a value came from: <SourcePill source="adapter"/> <SourcePill source="central"/> <SourcePill source="reader"/> <SourcePill source="hand"/> <SourcePill source="missing"/>. A course page reading comes first, the central rule fills courses with no English requirement, and a value entered by hand is never changed. Approve central rules in <a className="cf-link" href="#layer-4-review?tab=attributes">Layer 4 Review › Attributes</a>; set adapters in Models & services › University adapters.</p>
  </section>
}
