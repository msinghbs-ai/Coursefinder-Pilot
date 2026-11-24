import './ui-kit.css'
// Coverage & completeness › Courses › Pipeline & field ETA (v2.16.54, s777; Platform Admin 19 Nov 2026 15:36): every canonical API v3 field for all
// courses, one country or one university: Admitted, Trying, Needs a source, Not possible, Wave 2, the observed daily velocity, the primary
// bottleneck and the expected date every achievable course has the field. Read: admin_field_coverage('pipeline_eta'), one row of the readiness
// snapshot (rollup target course-field-readiness, one part every 4 minutes, all parts about every hour). Any StudySearch role; nothing here writes.
import React,{useEffect,useRef,useState}from'react'
import{supabase}from'../lib/supabase'
import{Empty,Loading,SectionTitle,fmtNumber}from'./kit.jsx'
import{fmtDate,fmtDateTime}from'../lib/format.js'
import{plainError}from'../lib/errors'

const COUNTRY={AU:'Australia',NZ:'New Zealand',CA:'Canada'}
const LABEL={official_url:'Official course page',description:'Description',study_load:'Study load',tuition_fee:'Tuition fee',fee_basis:'Fee basis',intake_dates:'Intake dates',
  application_deadlines:'Application deadlines',duration:'Duration',campus_locality:'Campus locality',aer_academic:'Academic entry',english_requirements:'English requirements',
  scholarships:'Scholarships',destination_city_stats:'Destination city figures',career_outcomes:'Career outcomes'}
const BOTTLENECK={trying:'In the pipeline',needs_source:'Needs a source page',not_possible:'Not published by the provider',wave2:'Wave 2 (country not started)'}
const pct=(n,t)=>t?`${(Math.round(1000*n/t)/10).toFixed(1)}%`:'0.0%'
const addDays=d=>{const x=new Date();x.setDate(x.getDate()+Number(d));return x}

function eta(f){
  if(f.eta_state==='complete')return 'Complete'
  if(f.eta_state==='forecast')return `~${fmtNumber(f.eta_days)} days (${fmtDate(addDays(f.eta_days))})`
  if(f.eta_state==='no_progress')return 'No gain in the window'
  return 'After velocity is measured'
}

export default function PipelineEta({onError}){
  const[scope,setScope]=useState('all'),[country,setCountry]=useState('AU'),[q,setQ]=useState(''),[query,setQuery]=useState(''),[provider,setProvider]=useState(null)
  const[data,setData]=useState(null),[list,setList]=useState([]),[busy,setBusy]=useState(false)
  const seq=useRef(0)
  useEffect(()=>{const t=setTimeout(()=>setQuery(q.trim()),280);return()=>clearTimeout(t)},[q])
  const call=args=>supabase.rpc('admin_field_coverage',{p_action:'pipeline_eta',p_args:args}).then(({data:d,error})=>{if(error)throw error;return d})
  // the table for the chosen scope
  useEffect(()=>{
    if(scope==='provider'&&!provider){setData(null);return}
    const n=++seq.current;setBusy(true)
    const args=scope==='country'?{scope,country}:scope==='provider'?{scope,provider:provider.id}:{scope:'all'}
    call(args).then(d=>{if(n===seq.current)setData(d)}).catch(e=>onError?.(plainError(e))).finally(()=>{if(n===seq.current)setBusy(false)})
  },[scope,country,provider?.id])
  // the university search list
  useEffect(()=>{
    if(scope!=='provider'||query.length<2){setList([]);return}
    call({scope:'provider',q:query}).then(d=>setList(d?.providers||[])).catch(e=>onError?.(plainError(e)))
  },[scope,query])
  const fields=data?.fields||[],total=Number(data?.courses||0)
  return <section className="ui-card ui-pe-panel" data-pipeline-eta>
    <SectionTitle title="Pipeline & field ETA" subtitle="Each API v3 field: admitted now, still in the pipeline, still needing a source, not published, Wave 2, how fast it is filling and when every achievable course is expected to have it."/>
    <div className="ui-pe-bar">
      <div className="ui-ar-tabs" role="tablist" aria-label="Scope">
        {[['all','Consolidated'],['country','By country'],['provider','By university']].map(([k,l])=><button key={k} role="tab" aria-selected={scope===k} className={scope===k?'ui-active':''} onClick={()=>setScope(k)} data-pe-scope={k}>{l}</button>)}
      </div>
      {scope==='country'&&<label className="ui-pe-field"><span>Country</span><select value={country} onChange={e=>setCountry(e.target.value)} data-pe-country>
        {Object.entries(COUNTRY).map(([k,l])=><option key={k} value={k}>{l}</option>)}</select></label>}
      {scope==='provider'&&<div className="ui-pe-search">
        <label className="ui-pe-field"><span>University or provider</span><input value={q} onChange={e=>setQ(e.target.value)} placeholder="Type at least 2 letters" aria-label="Search university" data-pe-search/></label>
        {list.length>0&&<ul className="ui-pe-list" role="listbox" aria-label="Matching providers">{list.map(p=><li key={p.id}><button type="button" role="option" aria-selected={provider?.id===p.id} onClick={()=>{setProvider(p);setList([]);setQ(p.name)}} data-pe-provider={p.id}>
          <strong>{p.name}</strong><small>{p.country} · {fmtNumber(p.courses)} courses</small></button></li>)}</ul>}
      </div>}
    </div>
    {data&&data.ready===false?<Empty text={data.note}/>:scope==='provider'&&!provider?<Empty text="Search for a university to see its fields."/>:busy&&!data?<Loading label="Loading pipeline…"/>:data?<>
      <p className="ui-pe-meta" data-pe-meta><strong>{scope==='country'?COUNTRY[data.label]||data.label:data.label}</strong>: {fmtNumber(total)} active courses.
        {' '}Snapshot built in parts{data.parts_built<data.parts?` (${data.parts_built} of ${data.parts} built so far)`:''}, oldest part {fmtDateTime(data.oldest_part_at)}.
        {' '}{data.velocity_days?`Velocity: admitted courses a day over ${data.velocity_days} day${data.velocity_days>1?'s':''} since ${fmtDate(data.velocity_from)}.`:'Velocity is measured from the second day of daily marks.'}</p>
      <div className="ui-tablewrap"><table className="ui-table ui-pe-table">
        <thead><tr><th>Field</th><th className="ui-num">Admitted</th><th className="ui-num">Trying</th><th className="ui-num">Needs a source</th><th className="ui-num">Not possible</th><th className="ui-num">Wave 2</th><th className="ui-num">Daily velocity</th><th>Primary bottleneck</th><th>Expected 100% (achievable)</th></tr></thead>
        <tbody>{fields.map(f=><tr key={f.field} data-pe-field={f.field}>
          <td><strong>{LABEL[f.field]||f.field}</strong><small className="ui-pe-code">{f.field}</small></td>
          <td className="ui-num">{fmtNumber(f.admitted)} <small>{pct(f.admitted,total)}</small></td>
          <td className="ui-num">{fmtNumber(f.trying)}</td><td className="ui-num">{fmtNumber(f.needs_source)}</td><td className="ui-num">{fmtNumber(f.not_possible)}</td><td className="ui-num">{fmtNumber(f.wave2)}</td>
          <td className="ui-num">{f.velocity==null?'—':`${f.velocity>0?'+':''}${fmtNumber(f.velocity)}/day`}</td>
          <td>{f.bottleneck?<>{BOTTLENECK[f.bottleneck]} <small>({fmtNumber(f[f.bottleneck])})</small></>:'None'}</td>
          <td data-pe-eta={f.eta_state}>{eta(f)}{f.remaining>0&&<small className="ui-pe-sub"> {fmtNumber(f.remaining)} to go</small>}</td></tr>)}</tbody>
      </table></div>
      <p className="ui-pe-note">Achievable means admitted, trying or needing a source; courses whose provider does not publish the field, and Wave 2 countries, are left out of the date.</p>
    </>:null}
  </section>
}
