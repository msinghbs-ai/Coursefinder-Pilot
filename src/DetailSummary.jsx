// v2.15.225 (Platform Admin, 9 Oct 2026: "remove unnecessary text and fields … modern UI with coloured pills and a
// consolidated view with main info … card, multi-column, adaptable to width … standardised through the app"):
// the one summary used at the top of every catalogue detail panel — a row of coloured pills for what the record is,
// then cards with the main facts that reflow from one to four columns with the width of the panel.
import React from'react'
import{ExternalLink,UsersRound}from'lucide-react'
import{StatusChip}from'./ui-kit'
import{fmtNumber,fmtDate,fmtMoney}from'./lib/format.js'
import'./detail-summary.css'

const human=v=>String(v??'').replaceAll('_',' ').replace(/^./,c=>c.toUpperCase())
const DELIVERY={on_campus:'On campus',online:'Online',blended:'Blended',mixed:'Blended'}
const BASIS={annual:'a year',per_semester:'a semester',per_trimester:'a trimester',total_indicative:'whole course',registered_total_course:'whole course'}

export function PillRow({children}){return <div className="ds-pills" data-ds-pills>{children}</div>}
export function FactCards({children}){return <div className="ds-cards" data-ds-cards>{children}</div>}
export function FactCard({label,value,sub,children,wide=false,tone='',id}){return <div className={`ds-card${wide?' wide':''}${tone?' tone-'+tone:''}`} data-ds-card={id||label}>
  <small>{label}</small>{value!=null&&<strong>{value}</strong>}{children&&<div className="ds-card-body">{children}</div>}{sub&&<span className="ds-sub">{sub}</span>}</div>}
export function Pills({items,empty='Not stated',tone='neutral'}){return items?.length?<span className="ds-pill-list">{items.map((x,i)=>typeof x==='string'?<StatusChip key={i} tone={tone} label={x}/>:<StatusChip key={i} tone={x.tone||tone} label={x.label} title={x.title}/>)}</span>:<span className="ds-muted">{empty}</span>}

function publication(v){return v==='published'?<StatusChip tone="success" label="Published"/>:<StatusChip tone="warning" label="Not published"/>}
function lifecycle(v){return v&&v!=='active'?<StatusChip tone="danger" label={human(v)}/>:null}

/** Course: what it is (pills), then fee, intakes, English, campuses and freshness. */
export function CourseSummary({data,feeUsed}){
  const f=data.fee_summary||{},reg=f.cricos_registered||[],used=f.fee_used
  const regBy=t=>reg.find(x=>String(x.fee_type||x.type)===t)
  const tuition=regBy('tuition'),total=regBy('estimated_total_course_cost'),non=regBy('non_tuition')
  const duration=data.duration_value?`${fmtNumber(Number(data.duration_value))} ${data.duration_unit||''}`.trim():null
  const english=(data.english||[]).map(x=>({label:`${x.test_name||x.test_code} ${x.overall_score!=null?Number(x.overall_score):''}`.trim(),tone:'info'}))
  const intakes=(data.intakes||[]).filter(x=>(x.status||'active')==='active').map(x=>({label:[x.label,x.year].filter(Boolean).join(' '),tone:'violet'}))
  const campuses=(data.campuses||[]).map(x=>({label:x.city||x.name,title:x.name,tone:'neutral'}))
  const code=data.course_code
  return <section className="ds-summary" data-course-summary>
    <PillRow>
      {data.level_name&&<StatusChip tone="info" label={data.level_name}/>}
      {data.field_name&&<StatusChip tone="violet" label={data.field_name}/>}
      {data.delivery_mode&&<StatusChip tone="neutral" label={DELIVERY[data.delivery_mode]||human(data.delivery_mode)}/>}
      {duration&&<StatusChip tone="neutral" label={duration}/>}
      {code&&<StatusChip tone="neutral" label={`CRICOS ${code}`}/>}
      {publication(data.publication_status)}{lifecycle(data.lifecycle_status)}
    </PillRow>
    <FactCards>
      <FactCard id="fee" label="Tuition used" value={used?.per_year!=null?`${fmtMoney(used.per_year,used.currency||'AUD')} a year`:'Not known yet'} tone={used?.per_year!=null?'':'warning'}>{feeUsed}</FactCard>
      <FactCard id="registered" label="Registered course cost (CRICOS)" value={tuition?fmtMoney(tuition.amount,tuition.currency||'AUD'):'—'} sub={[total&&`${fmtMoney(total.amount,total.currency||'AUD')} with non-tuition`,non&&`non-tuition ${fmtMoney(non.amount,non.currency||'AUD')}`].filter(Boolean).join(' · ')||'Whole course'}/>
      <FactCard id="intakes" label="Intakes"><Pills items={intakes} empty="No intake found yet"/></FactCard>
      <FactCard id="english" label="English"><Pills items={english} empty="No requirement found yet"/></FactCard>
      <FactCard id="campuses" label={`Campus${campuses.length===1?'':'es'}`}><Pills items={campuses} empty="—"/></FactCard>
      <FactCard id="checked" label="Last checked" value={data.last_verified_at?fmtDate(data.last_verified_at):'—'} sub={data.course_url?<a className="cf-link" href={data.course_url} target="_blank" rel="noreferrer">Course page <ExternalLink size={11}/></a>:'No course page yet'}/>
    </FactCards>
  </section>}

/** Provider: what it is (pills), then size, campuses, contacts and website. */
export function ProviderSummary({data,navigate}){
  const reg=(data.registrations||data.identifiers||[]).find(x=>x.scheme==='cricos')
  const code=reg?.code||reg?.identifier
  const groups=Array.isArray(data.university_groups)?data.university_groups:[]
  const campuses=data.campuses_page?.items||[]
  const contacts=data.international_contacts?.summary||{}
  const nContacts=Number(contacts.current_contacts||0)+Number(contacts.manual_contacts||0)||Number(contacts.first_party_contacts||0)+Number(contacts.enriched_contacts||0)
  return <section className="ds-summary" data-provider-summary>
    <PillRow>
      {data.country_code&&<StatusChip tone="info" label={data.country_code}/>}
      {groups.map(g=><StatusChip key={g.code} tone="violet" label={g.name} title={String(g.code||'').toUpperCase()}/>)}
      {code&&<StatusChip tone="neutral" label={`CRICOS ${code}`}/>}
      {publication(data.publication_status)}{lifecycle(data.lifecycle_status)}
    </PillRow>
    <FactCards>
      <FactCard id="courses" label="Courses" value={fmtNumber(Number(data.course_count||0))} sub={data.projected_course_count!=null?`${fmtNumber(Number(data.projected_course_count))} in search`:null}/>
      <FactCard id="scholarships" label="Scholarships" value={fmtNumber(Number(data.scholarship_count||0))}/>
      <FactCard id="contacts" label="International contacts" value={fmtNumber(nContacts)}>{data.id&&<button type="button" className="m-secondary compact" onClick={()=>navigate?.('Provider Contacts',{provider_id:data.id})}><UsersRound size={12}/>View contacts</button>}</FactCard>
      <FactCard id="checked" label="Last checked" value={data.last_verified_at?fmtDate(data.last_verified_at):'—'} sub={data.website?<a className="cf-link" href={data.website} target="_blank" rel="noreferrer">{String(data.website).replace(/^https?:\/\//,'')} <ExternalLink size={11}/></a>:'No website yet'}/>
      {campuses.length>0&&<FactCard id="campuses" wide label={`Campuses (${fmtNumber(Number(data.campuses_page?.total||campuses.length))})`}><Pills items={campuses.map(c=>({label:`${c.city||c.name}${c.course_count!=null?` · ${fmtNumber(c.course_count)}`:''}`,title:`${c.name}${c.course_count!=null?` — ${c.course_count} courses`:''}`,tone:'neutral'}))}/></FactCard>}
    </FactCards>
  </section>}
