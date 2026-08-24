import React from 'react'
import {BookOpen,ExternalLink} from 'lucide-react'

const empty=v=>v==null||v===''||(Array.isArray(v)&&v.length===0)||(typeof v==='object'&&!Array.isArray(v)&&Object.keys(v||{}).length===0)
const money=x=>x?.amount==null?'—':`${x.currency||x.currency_code||'AUD'} ${Number(x.amount).toLocaleString()}`
const fmtDate=v=>{const d=new Date(v);return Number.isNaN(+d)?String(v||'—'):d.toLocaleDateString(undefined,{day:'2-digit',month:'short',year:'numeric'})}
const bool=v=>v===true?'Yes':v===false?'No':'—'
const evidenceIdOf=v=>v?.evidence_id||v?.source_evidence_id||(v?.storage_path&&v?.id?v.id:null)

function EvidenceButton({id,navigate,label='Evidence'}){if(!id)return null;return <button className="m-secondary compact" style={{marginLeft:6,padding:'4px 7px',fontSize:9}} onClick={e=>{e.stopPropagation();navigate?.('Evidence',{evidence_id:id})}}><BookOpen size={11}/>{label}</button>}
function Row({label,value,children}){if(empty(value)&&!children)return null;return <div><span>{label}</span><strong>{children??value}</strong></div>}
function Section({title,children,help}){return <section className="m-detail-section"><h3>{title}</h3>{help&&<p className="m-help">{help}</p>}{children}</section>}

function Overview({data}){
  const duration=data.duration_value?`${data.duration_value} ${data.duration_unit||''}`.trim():'—'
  return <>
    <div className="m-detail-grid">
      <div><small>Provider</small><strong>{data.provider_name||'—'}</strong></div>
      <div><small>CRICOS / Course code</small><strong>{data.course_code||'—'}</strong></div>
      <div><small>Study level</small><strong>{data.level_name||data.level_code||'—'}</strong></div>
      <div><small>Field of study</small><strong>{data.field_name||data.field_code||'—'}</strong></div>
      <div><small>Duration</small><strong>{duration}</strong></div>
      <div><small>Delivery</small><strong>{data.delivery_mode||'—'}</strong></div>
      <div><small>Lifecycle</small><strong>{data.lifecycle_status||'—'}</strong></div>
      <div><small>Publication</small><strong>{data.publication_status||'—'}</strong></div>
      <div><small>Last verified</small><strong>{data.last_verified_at?fmtDate(data.last_verified_at):'—'}</strong></div>
      <div><small>Official Course URL</small><strong>{data.course_url?<a href={data.course_url} target="_blank" rel="noreferrer" style={{display:'inline-flex',alignItems:'center',gap:4,color:'#4f46e5',wordBreak:'break-word'}}>Open first-party page <ExternalLink size={11}/></a>:'Not yet captured'}</strong></div>
    </div>
    {data.description&&<Section title="Course description"><p style={{margin:0,lineHeight:1.55}}>{data.description}</p></Section>}
  </>
}

function FeeRecord({x,registered,navigate}){
  const type=String(x.fee_type||x.type||'tuition').toLowerCase()
  const title=registered
    ? type==='tuition'?'Registered tuition':type==='non_tuition'?'Registered non-tuition':type==='estimated_total_course_cost'?'Estimated total course cost':'Registered course cost'
    : 'Current provider tuition'
  const meta=[x.fee_year?`Year ${x.fee_year}`:null,x.audience?String(x.audience).replaceAll('_',' '):null,x.basis?String(x.basis).replaceAll('_',' '):null].filter(Boolean).join(' · ')
  return <div className="m-record"><strong>{title}</strong><span>{money(x)}{meta?` · ${meta}`:''}</span><EvidenceButton id={evidenceIdOf(x)} navigate={navigate}/></div>
}
function Fees({data,navigate}){
  const f=data.fee_summary||{},registered=f.cricos_registered||[],current=f.provider_current||[]
  return <Section title="Fees" help="Registered CRICOS course-cost facts and Provider-current tuition are separate facts. Layer 2 never replaces the registered CRICOS values.">
    <div className="m-semantic-grid">
      <div><small>Registered CRICOS course cost</small><strong>{registered.length}</strong><div className="m-record-list">{registered.length?registered.map((x,i)=><FeeRecord key={x.id||i} x={x} registered navigate={navigate}/>):<span>No current registered fee rows.</span>}</div></div>
      <div><small>Current Provider tuition</small><strong>{current.length}</strong><div className="m-record-list">{current.length?current.map((x,i)=><FeeRecord key={x.id||i} x={x} navigate={navigate}/>):<span>No evidence-backed current Provider tuition captured.</span>}</div></div>
    </div>
  </Section>
}

function EntryRequirements({data}){
  const intakes=data.intakes||[],english=data.english||[]
  if(!intakes.length&&!english.length)return null
  return <Section title="Intakes & English">
    <div className="m-kv-list">
      {intakes.length>0&&<Row label="Intakes" value={intakes.map(x=>[x.label,x.year].filter(Boolean).join(' ')).join(', ')}/>} 
      {english.map((x,i)=><Row key={i} label={x.test_name||x.test_code||'English test'} value={[x.overall_score!=null?`Overall ${x.overall_score}`:null,x.confidence!=null?`Confidence ${x.confidence}`:null].filter(Boolean).join(' · ')||'Requirement captured'}/>)}
    </div>
  </Section>
}

function Campuses({rows}){if(!rows?.length)return null;return <Section title="Campuses"><div className="m-record-list">{rows.map((x,i)=><div className="m-record" key={x.id||i}><strong>{x.name||x.campus_name||'Campus'}</strong><span>{[x.city,x.subdivision_name||x.state,x.postcode].filter(Boolean).join(' · ')}</span></div>)}</div></Section>}

function Regulatory({data,navigate}){
  const rows=data.regulatory_facts||[]
  if(!rows.length)return null
  return <Section title="Regulatory facts" help="Authoritative CRICOS observations retained from Layer 1. These are regulatory facts, not Layer 2 enrichment.">
    <div className="m-record-list">{rows.map((x,i)=>{
      const parts=[]
      if(x.course_language)parts.push(`Language: ${x.course_language}`)
      if(x.work_component!=null)parts.push(`Work component: ${bool(x.work_component)}`)
      if(x.work_component_total_hours!=null)parts.push(`Work hours: ${Number(x.work_component_total_hours).toLocaleString()}`)
      if(x.foundation_studies!=null)parts.push(`Foundation studies: ${bool(x.foundation_studies)}`)
      if(x.dual_qualification!=null)parts.push(`Dual qualification: ${bool(x.dual_qualification)}`)
      return <div className="m-record" key={x.evidence_id||i}><strong>{String(x.scheme||'CRICOS').toUpperCase()} registration · {x.status||'current'}</strong><span>{parts.join(' · ')||'Current regulatory registration observation.'}</span><EvidenceButton id={evidenceIdOf(x)} navigate={navigate}/></div>
    })}</div>
  </Section>
}

function Evidence({rows,navigate}){if(!rows?.length)return null;return <Section title="Evidence" help="Open an artifact to review the source, capture, hash and lineage in the Evidence workspace."><div className="m-record-list">{rows.map((x,i)=><button key={x.id||i} className="m-record" style={{textAlign:'left',width:'100%',cursor:'pointer'}} onClick={()=>x.id&&navigate?.('Evidence',{evidence_id:x.id})}><strong>{x.evidence_type||x.type||'Evidence artifact'}</strong><span>{[x.captured_at?`Captured ${fmtDate(x.captured_at)}`:null,x.source_url||null,x.content_hash?`SHA ${String(x.content_hash).slice(0,12)}…`:null].filter(Boolean).join(' · ')}</span><span style={{display:'inline-flex',alignItems:'center',gap:4,fontWeight:700,color:'#4f46e5'}}><BookOpen size={11}/> Open Evidence</span></button>)}</div></Section>}

function OptionalList({title,rows}){if(!rows?.length)return null;return <Section title={title}><div className="m-record-list">{rows.map((x,i)=><div className="m-record" key={x.id||i}><strong>{x.name||x.title||x.code||title.slice(0,-1)}</strong><span>{[x.type,x.relationship_type,x.description].filter(Boolean).join(' · ')}</span></div>)}</div></Section>}

function OperationalState({data}){
  const s=data.state_summary||{}
  if(!Object.keys(s).length)return null
  const search=s.search??s.search_fields,canonical=s.canonical??s.canonical_fields,ready=s.admin_readiness??s.admin_readiness_fields,channels=s.consumer_channels
  return <Section title="Operational state"><div className="m-kv-list">
    <Row label="Publication" value={data.publication_status||'—'}/>
    {!empty(search)&&<Row label="Search projection" value={`${search} field${Number(search)===1?'':'s'}`}/>} 
    {!empty(canonical)&&<Row label="Canonical coverage" value={`${canonical} field${Number(canonical)===1?'':'s'}`}/>} 
    {!empty(ready)&&<Row label="Admin readiness" value={`${ready} field${Number(ready)===1?'':'s'}`}/>} 
    {!empty(channels)&&<Row label="Consumer channels" value={typeof channels==='number'?`${channels} record${channels===1?'':'s'}`:String(channels)}/>} 
  </div></Section>
}

export default function CourseDetailPolish({data,navigate}){
  if(!data)return null
  return <div className="m-drawer-body">
    <Overview data={data}/>
    <Fees data={data} navigate={navigate}/>
    <EntryRequirements data={data}/>
    <Campuses rows={data.campuses}/>
    <OptionalList title="Academic options" rows={data.academic_options}/>
    <OptionalList title="Categories" rows={data.categories}/>
    <OptionalList title="Collections" rows={data.collections}/>
    <Regulatory data={data} navigate={navigate}/>
    <Evidence rows={data.evidence} navigate={navigate}/>
    <OperationalState data={data}/>
  </div>
}
