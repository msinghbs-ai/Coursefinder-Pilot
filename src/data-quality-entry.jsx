import React,{useEffect,useMemo,useState}from'react'
import{
  AlertTriangle,BookOpen,CheckCircle2,ChevronLeft,ChevronRight,Database,
  ExternalLink,Filter,GraduationCap,MapPin,RefreshCw,Search,
  ShieldCheck,Sparkles,UsersRound,X
}from'lucide-react'
import{fmtNumber,fmtDate,fmtPercent}from'./lib/format.js'
import{adminRead}from'./lib/supabase'
import'./data-quality.css'

// v2.15.107: this screen no longer mounts its own full-screen shell and side menu. It is the
// 'Readiness by area' tab of Coverage & completeness, drawn inside the standard app shell.
const PAGE_SIZE=50
const STATE_ORDER=['present','source_null','not_applicable','zero','suppressed','not_yet_enriched','stale','ambiguous','rejected']
const STATE_LABEL={
  present:'Present',source_null:'Source-null',not_applicable:'Not applicable',zero:'Zero',
  suppressed:'Suppressed',not_yet_enriched:'Not yet enriched',stale:'Stale',ambiguous:'Ambiguous',rejected:'Rejected'
}
const ENTITY_LABEL={course:'Course',provider:'Provider',campus:'Campus',scholarship:'Scholarship'}
const ENTITY_ICON={course:GraduationCap,provider:UsersRound,campus:MapPin,scholarship:Sparkles}
const ENTITY_ROUTE={course:'courses',provider:'providers',campus:'campuses',scholarship:'scholarships'}

export function DomainReadiness({rank=0}){
  const[country,setCountry]=useState(''),[overview,setOverview]=useState(null),[busy,setBusy]=useState(true),[error,setError]=useState('')
  const[selected,setSelected]=useState(null),[exceptions,setExceptions]=useState(null),[exceptionBusy,setExceptionBusy]=useState(false)
  const[offset,setOffset]=useState(0),[query,setQuery]=useState(''),[submittedQuery,setSubmittedQuery]=useState('')

  const loadOverview=()=>{
    setBusy(true);setError('')
    adminRead('data_quality_overview',country?{country_code:country}:{})
      .then(data=>{setOverview(data);if(selected){const still=(data?.metrics||[]).find(m=>m.domain===selected.domain&&m.entity_type===selected.entity_type);if(!still)setSelected(null)}})
      .catch(e=>setError(e.message||String(e))).finally(()=>setBusy(false))
  }
  useEffect(()=>{setOffset(0);setSelected(null);setExceptions(null);loadOverview()},[country])
  useEffect(()=>{
    if(!selected){setExceptions(null);return}
    setExceptionBusy(true);setError('')
    adminRead('data_quality_exceptions',{
      entity_type:selected.entity_type,domain:selected.domain,state:selected.state,
      country_code:country||null,query:submittedQuery||null,limit:PAGE_SIZE,offset
    }).then(setExceptions).catch(e=>setError(e.message||String(e))).finally(()=>setExceptionBusy(false))
  },[selected,offset,submittedQuery,country])

  const groups=useMemo(()=>{
    const map=new Map()
    for(const metric of overview?.metrics||[]){
      const key=metric.domain
      if(!map.has(key))map.set(key,{domain:key,label:metric.label,definition:metric.definition,authority:metric.authority,metrics:[]})
      map.get(key).metrics.push(metric)
    }
    return [...map.values()]
  },[overview])
  const scope=overview?.scope?.default_scope||country||'AU+NZ'

  function openState(metric,state,count){if(!count)return;setSelected({domain:metric.domain,label:metric.label,entity_type:metric.entity_type,state});setOffset(0);setQuery('');setSubmittedQuery('')}
  function goAdmin(hash='#dashboard'){location.hash=hash}
  function openEntity(row){goAdmin(`#${ENTITY_ROUTE[row.entity_type]}?id=${encodeURIComponent(row.entity_id)}`)}
  function openEvidence(row){if(row.evidence_id&&rank>=3)goAdmin(`#evidence?evidence_id=${encodeURIComponent(row.evidence_id)}`)}
  function openReview(){if(rank>=3)goAdmin('#layer-4-review')}

  return <div className="dq-embedded">
    <div className="cf-page-toolbar"><p className="dq-embedded-intro">{selected?`${selected.label} · ${ENTITY_LABEL[selected.entity_type]} · ${STATE_LABEL[selected.state]}`:'Each area counted separately. Select a count to list those records.'}</p>
      <div className="dq-actions"><label>Scope<select value={country} onChange={e=>setCountry(e.target.value)}><option value="">AU + NZ</option><option value="AU">Australia</option><option value="NZ">New Zealand</option></select></label><button className="dq-icon" title="Refresh" aria-label="Refresh" onClick={loadOverview} disabled={busy}><RefreshCw size={17}/></button></div></div>
    {error&&<div className="dq-alert"><AlertTriangle size={16}/><span>{error}</span><button onClick={()=>setError('')}><X size={15}/></button></div>}
    {!selected?<>
      <section className="dq-legend"><span>Metric state</span>{STATE_ORDER.map(s=><em key={s} className={`dq-state s-${s}`}>{STATE_LABEL[s]}</em>)}</section>
      {busy&&!overview?<ReadinessSkeleton/>:<div className="dq-domain-grid">{groups.map(group=><DomainCard key={group.domain} group={group} onState={openState}/>)}</div>}
    </>:<ExceptionsView selected={selected} data={exceptions} busy={exceptionBusy} offset={offset} query={query} setQuery={setQuery} submitQuery={()=>{setOffset(0);setSubmittedQuery(query.trim())}} setOffset={setOffset} clear={()=>{setSelected(null);setExceptions(null)}} rank={rank} openEntity={openEntity} openEvidence={openEvidence} openReview={openReview}/>}
  </div>
}

function DomainCard({group,onState}){return <section className="dq-domain-card">
  <header><div><span className="dq-domain-kicker">{group.authority}</span><h2>{group.label}</h2><p>{group.definition}</p></div></header>
  <div className="dq-domain-rows">{group.metrics.map(metric=>{
    const Icon=ENTITY_ICON[metric.entity_type]||Database
    return <div className="dq-domain-row" key={`${metric.domain}-${metric.entity_type}`}>
      <div className="dq-entity"><span><Icon size={15}/></span><div><strong>{ENTITY_LABEL[metric.entity_type]||metric.entity_type}</strong><small>{fmt(metric.scope_count)} scoped · {fmt(metric.applicable_count)} applicable</small></div></div>
      <div className="dq-rate"><strong>{metric.readiness_pct==null?'N/A':fmtPercent(metric.readiness_pct)}</strong><small>domain readiness</small></div>
      <div className="dq-state-grid">{STATE_ORDER.map(state=>{const count=Number(metric.states?.[state]||0);return <button key={state} disabled={!count} className={`dq-state-cell s-${state} ${count?'has-count':''}`} title={`${STATE_LABEL[state]}: ${fmt(count)}`} onClick={()=>onState(metric,state,count)}><span>{STATE_LABEL[state]}</span><strong>{fmt(count)}</strong></button>})}</div>
    </div>})}</div>
  </section>}

function ExceptionsView({selected,data,busy,offset,query,setQuery,submitQuery,setOffset,clear,rank,openEntity,openEvidence,openReview}){
  const total=Number(data?.total||0),items=data?.items||[],from=total?offset+1:0,to=Math.min(offset+PAGE_SIZE,total)
  return <div className="dq-exceptions">
    <section className="dq-exception-toolbar"><div><button className="dq-secondary" onClick={clear}><ChevronLeft size={16}/>All domains</button><div className="dq-selection"><span className={`dq-state s-${selected.state}`}>{STATE_LABEL[selected.state]}</span><strong>{selected.label}</strong><small>{ENTITY_LABEL[selected.entity_type]} exceptions</small></div></div><form onSubmit={e=>{e.preventDefault();submitQuery()}}><Search size={15}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Entity, provider, stable key or code"/><button>Search</button></form></section>
    <div className="dq-exception-summary"><span><Filter size={14}/>{fmt(total)} records</span><span>{from}–{to} of {fmt(total)}</span></div>
    <section className="dq-table-panel">
      {busy?<ExceptionSkeleton/>:!items.length?<div className="dq-empty"><CheckCircle2 size={24}/><strong>No matching records</strong><p>This state has no records in the selected scope/query.</p></div>:<div className="dq-table-wrap"><table className="dq-table"><thead><tr><th>Entity</th><th>State</th><th>Source / evidence</th><th>Verification</th><th>Decision context</th><th/></tr></thead><tbody>{items.map(row=><tr key={row.entity_id}>
        <td><button className="dq-entity-link" onClick={()=>openEntity(row)}><strong>{row.entity_name}</strong><small>{row.provider_name||row.stable_key}</small><em>{row.country_code} · {ENTITY_LABEL[row.entity_type]}</em></button></td>
        <td><span className={`dq-state s-${row.state}`}>{STATE_LABEL[row.state]||humanise(row.state)}</span></td>
        <td><div className="dq-source"><strong>{row.source_label||'No domain source recorded'}</strong><small>{row.evidence_id?'Evidence linked':'No evidence ID on this exception row'}</small>{row.evidence_id&&rank>=3&&<button onClick={()=>openEvidence(row)}><BookOpen size={13}/>Evidence</button>}</div></td>
        <td><strong>{dateOnly(row.last_verified_at)||'Not verified'}</strong><small>{row.updated_at?`Updated ${dateOnly(row.updated_at)}`:''}</small></td>
        <td><div className="dq-context"><small>{row.review_id?'Review item linked':'No open review item'}</small>{row.review_id&&rank>=3&&<button onClick={openReview}>Open Review Queue</button>}</div></td>
        <td><button className="dq-open" title="Open canonical entity" onClick={()=>openEntity(row)}><ExternalLink size={15}/></button></td>
      </tr>)}</tbody></table></div>}
      <footer className="dq-pager"><button disabled={offset===0||busy} onClick={()=>setOffset(Math.max(0,offset-PAGE_SIZE))}><ChevronLeft size={15}/>Previous</button><span>Page {Math.floor(offset/PAGE_SIZE)+1} · {fmt(total)} total</span><button disabled={offset+PAGE_SIZE>=total||busy} onClick={()=>setOffset(offset+PAGE_SIZE)}>Next<ChevronRight size={15}/></button></footer>
    </section>
    <section className="dq-read-contract"><Database size={16}/><p>This drill-down is one bounded server-side exception page. Opening an entity, Evidence artifact or Review Queue is an explicit operator action; the page does not issue per-row detail RPCs.</p></section>
  </div>
}

function ReadinessSkeleton(){return <div className="dq-domain-grid">{Array.from({length:6}).map((_,i)=><div className="dq-skeleton domain" key={i}/>)}</div>}
function ExceptionSkeleton(){return <div className="dq-skeleton-list">{Array.from({length:7}).map((_,i)=><div className="dq-skeleton row" key={i}/>)}</div>}
function fmt(v){const n=Number(v);return Number.isFinite(n)?fmtNumber(n):String(v??'—')}
function humanise(v){return String(v??'').replace(/[_-]+/g,' ').replace(/\b\w/g,m=>m.toUpperCase())}
function dateOnly(v){if(!v)return'';const d=new Date(v);return Number.isNaN(d.getTime())?'':fmtDate(d)}
