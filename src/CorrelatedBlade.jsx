// CF-247 S1-RM-Design (Platform Admin 18 Nov 2026 21:23; admin docs/platform/2026-11-18-correlated-blades-role-visibility-mockup.md):
// read-only correlated sections in the Course and Provider drawers, joined in the browser from reads the admin already has
// (no new schema). Course: Location & weather, Career pathway, Visa & living-cost snapshot, Entry requirements & scholarships.
// Provider: Rankings, Campus city profiles, Scholarships & accreditations. The joins and the column list are in
// src/lib/correlation-adapters.js (CARD_SPEC); what each role sees is in src/lib/field-visibility.js. Internal fields carry
// data-vis="<field>" so the drawer hides them for Viewer and Counsellor, and for an Editor previewing as one.
// City figures, careers and full rule rows are read with admin_destination_review, which the server opens to Curator and
// above; a Viewer or Counsellor sees the read-gap note until a student-facing read is added (hand-off to S2-Build).
import React,{useEffect,useState}from'react'
import{Eye,MapPin,Briefcase,Plane,GraduationCap,Trophy,Building2,Award}from'lucide-react'
import{StatusChip}from'./ui-kit'
import{fmtNumber,fmtMoney}from'./lib/format.js'
import{supabase,api}from'./lib/supabase'
import{CLIMATE_ICONS}from'./lib/climate-icons.js'
import{campusLocalities,cityProfile,careerOutlook,visaSnapshot,rankingSnapshot,EMPTY_CAREERS}from'./lib/correlation-adapters.js'
import{PREVIEW_ROLES,audienceOf,studentHideCss,STUDENT_ONLY_EMPTY_ENTRY,STUDENT_FACING_ENTRY}from'./lib/field-visibility.js'
import{useShowAll}from'./ShowAllToggle'
import'./correlated-blade.css'
import'./field-visibility.css'

// the global destination lists are the same for every record: read once a session, per kind
const LISTS=new Map()
function reviewList(kind){if(!LISTS.has(kind))LISTS.set(kind,Promise.resolve(supabase.rpc('admin_destination_review',{p_kind:kind,p_status:null})).then(({data,error})=>{if(error)throw error;return data?.rows||[]}).catch(e=>{LISTS.delete(kind);throw e}));return LISTS.get(kind)}
const rpc=(name,args)=>Promise.resolve(supabase.rpc(name,args)).then(({data,error})=>{if(error)throw error;return data})
function useRead(fn,deps,on=true){const[s,setS]=useState({data:null,err:null,done:false})
  useEffect(()=>{if(!on){setS({data:null,err:null,done:true});return}let live=true;setS({data:null,err:null,done:false})
    fn().then(d=>live&&setS({data:d,err:null,done:true})).catch(e=>live&&setS({data:null,err:e?.message||String(e),done:true}));return()=>{live=false}},deps)
  return s}

const Card=({id,icon:I,title,children,note})=><section className="cb-card" data-cb-card={id}><h4><I size={14} aria-hidden="true"/>{title}</h4>{children}{note&&<small className="cb-note">{note}</small>}</section>
const Gap=({children})=><p className="cb-gap" data-cb-read-gap>{children}</p>
const Empty=({children,id})=><p className="cb-empty" data-cb-empty={id}>{children}</p>
const kindLabel=k=>{const t=String(k||'').replaceAll('_',' ');return t.length<=4?t.toUpperCase():t.replace(/^./,c=>c.toUpperCase())}
const deg=v=>v==null?'—':`${Number(v).toFixed(1)}°`
const GAP_TEXT='City figures, careers and visa figures show for Curators and above until the student-facing read is added (S2-Build).'

function ClimateIcon({k}){if(!k||!CLIMATE_ICONS[k])return null;const[I,label]=CLIMATE_ICONS[k];return <span className="cb-icon" data-cb-climate={k} title={`${label} (long-term average, not a forecast)`}><I size={16} aria-hidden="true"/><span className="sr-only">{label}</span></span>}
function City({loc,metrics}){
  const p=metrics?cityProfile(loc.locality?.locality_id,metrics,{student:false}):null
  return <div className="cb-city" data-cb-city={loc.locality?.name||loc.campus}>
    <div className="cb-city-head"><strong>{loc.campus}{loc.is_primary&&<span className="cb-tag">Primary</span>}</strong>
      <span>{loc.locality?<><MapPin size={11}/>{loc.locality.name}</>:<em>No city mapped yet</em>}</span>
      {loc.match_share!=null&&<span className="cb-int" data-vis="confidence">match {Math.round(loc.match_share*100)}%</span>}
      {loc.pending==='in_layer4'&&<span className="cb-int" data-vis="layer4_queue_state">waiting in Layer 4</span>}</div>
    {p&&(p.has_climate||p.population)?<div className="cb-facts">
      {p.has_climate&&<><ClimateIcon k={p.icon}/>
        <span data-cb-fact="summer">Summer <b>{deg(p.climate.summer_max)}</b> / {deg(p.climate.summer_min)}</span>
        <span data-cb-fact="winter">Winter <b>{deg(p.climate.winter_max)}</b> / {deg(p.climate.winter_min)}</span>
        <span data-cb-fact="rainfall">Rainfall <b>{p.climate.rainfall==null?'—':`${fmtNumber(p.climate.rainfall)} mm`}</b> a year</span></>}
      {p.population&&<span data-cb-fact="population">Population <b>{fmtNumber(p.population.value)}</b>{p.population.period?` (${p.population.period})`:''}</span>}
    </div>:loc.locality&&metrics&&<Empty id="city">No climate or population figure is held for {loc.locality.name} yet.</Empty>}
    {p&&p.attribution.length>0&&<small className="cb-attr" data-cb-attribution>{p.attribution.join(' · ')}</small>}
    {p&&p.editions.length>0&&<small className="cb-int" data-vis="dataset_edition">{p.editions.join(', ')} · {p.statuses.join(', ')}</small>}
  </div>}

export function CourseCorrelated({data,rank=0}){
  const curator=Number(rank)>=3,courseId=data?.id,providerId=data?.provider_id
  const pd=useRead(()=>rpc('admin_provider_destination_read',{p_provider_id:providerId}),[providerId],!!providerId)
  const cd=useRead(()=>rpc('admin_course_destination_read',{p_course_id:courseId}),[courseId],!!courseId)
  const mt=useRead(()=>reviewList('locality_metric'),[curator],curator)
  const co=useRead(()=>reviewList('career_outcome'),[curator],curator)
  const sr=useRead(()=>reviewList('study_rule'),[curator],curator)
  const er=useRead(()=>rpc('admin_entry_requirements',{p_action:'course',p_args:{course_id:courseId}}),[courseId],!!courseId)
  const entry=(er.data?.rows||[]).filter(r=>!['rejected','inactive'].includes(String(r.status))),sch=Array.isArray(data?.course_scholarships?.items)?data.course_scholarships.items.filter(x=>(x.publication_status||'published')==='published'):[]
  const{shown:schShown,toggle:schToggle}=useShowAll(sch,{id:'cb-scholarships'}) // s697: first three, then Show all (N) scholarships
  if(!courseId)return null
  const locs=campusLocalities(data.campuses,pd.data?.campuses),cc=cd.data?.country_code||null
  const careers=curator&&co.done?careerOutlook(data.field_code,co.data,{country:cc}):null
  const visa=visaSnapshot(cd.data?.study_rules,sr.data)
  return <section className="cb" data-correlated="course" aria-label="Around this course">
    <header className="cb-head"><strong>Around this course</strong><small>Read only. Joined from the campus city, the field of study and the destination's rules.</small></header>
    <div className="cb-grid">
      <Card id="location" icon={MapPin} title="Location & weather">
        {!pd.done?<small>Loading…</small>:!locs.length?<Empty id="location">No campus is held for this course yet.</Empty>:locs.map((l,i)=><City key={i} loc={l} metrics={curator?mt.data:null}/>)}
        {!curator&&<Gap>{GAP_TEXT}</Gap>}
      </Card>
      <Card id="careers" icon={Briefcase} title="Career pathway, jobs & salary outlook" note={data.field_name?`Field of study: ${data.field_name}`:null}>
        {!curator?<Gap>{GAP_TEXT}</Gap>:!careers?<small>Loading…</small>:careers.state!=='matched'?<Empty id="careers">{EMPTY_CAREERS[careers.state]}{careers.held?<span className="cb-int" data-vis="dataset_edition"> {fmtNumber(careers.held)} occupation rows read, {fmtNumber(careers.with_figures||0)} with figures.</span>:null}</Empty>:
          <table className="cf-table cb-table" data-cb-careers><thead><tr><th>Occupation</th><th>Growth</th><th>Median salary</th><th>Shortage</th></tr></thead>
            <tbody>{careers.items.slice(0,5).map((o,i)=><tr key={i}><td>{o.occupation}<small className="cb-sub">{o.code}</small></td><td>{o.growth||'—'}{o.horizon?<small className="cb-sub">{o.horizon}-year outlook</small>:null}</td>
              <td className="num">{o.median_salary!=null?fmtMoney(o.median_salary,o.currency||'AUD'):'—'}</td><td>{o.shortage||'—'}</td></tr>)}</tbody></table>}
      </Card>
      <Card id="visa" icon={Plane} title="Visa & living-cost snapshot" note={cc?`Destination: ${cc}`:null}>
        {!cd.done?<small>Loading…</small>:!visa.rules?<Empty id="visa">No visa or living-cost rule is proven for this course's destination yet.</Empty>:<ul className="cb-list" data-cb-visa>
          <li data-cb-fact="work_hours"><span>Work while studying</span><b>{visa.work_hours_fortnight!=null?`${visa.work_hours_fortnight} hours a fortnight`:'Not held yet'}</b></li>
          <li data-cb-fact="post_study_work"><span>Post-study work rights</span><b>{visa.post_study_work?`${visa.post_study_work.min??'?'}${visa.post_study_work.max&&visa.post_study_work.max!==visa.post_study_work.min?`–${visa.post_study_work.max}`:''} years`:'Not held yet'}</b></li>
          <li data-cb-fact="financial_capacity"><span>Financial-capacity benchmark</span><b>{visa.financial_capacity?.amount!=null?`${fmtMoney(visa.financial_capacity.amount,visa.financial_capacity.currency)} a year`:'Not held yet'}</b></li>
          {visa.visa_fees.map((f,i)=><li key={i} data-cb-fact="visa_fee"><span>{f.title}</span><b>{f.amount!=null?fmtMoney(f.amount,f.currency):'—'}</b>{f.rule_id&&<code className="cb-int" data-vis="rule_id">{String(f.rule_id).slice(0,8)}</code>}</li>)}
          {visa.health_cover.map((h,i)=><li key={`h${i}`} data-cb-fact="health_cover"><span>Health cover</span><b>{h.title}</b></li>)}
        </ul>}
        {!curator&&visa.rules>0&&<Gap>Figures for each rule show for Curators and above until the student-facing read is added (S2-Build).</Gap>}
      </Card>
      <Card id="entry" icon={GraduationCap} title="Entry requirements & scholarships">
        <div className="cb-two">
          <div data-cb-entry><small className="cb-label">Academic entry</small>{!er.done?<small>Loading…</small>:!entry.length?<Empty id="entry">{STUDENT_ONLY_EMPTY_ENTRY}</Empty>:
            <><ul className="cb-list">{entry.slice(0,3).map(r=><li key={r.id} data-vis={STUDENT_FACING_ENTRY.has(String(r.status))?undefined:'unapproved_entry'}><span>{kindLabel(r.kind)}</span><b>{r.min_entry_score!=null?`${r.min_entry_score} (${r.min_entry_score_basis})`:r.description}</b>
              {r.quote&&<small className="cb-int" data-vis="raw_quote">“{r.quote}”</small>}{r.status==='proposed'&&<small className="cb-int" data-vis="layer4_queue_state">waiting in Layer 4</small>}</li>)}</ul>
              {!entry.some(r=>STUDENT_FACING_ENTRY.has(String(r.status)))&&<p className="cb-empty" data-student-only data-cb-empty="entry-approved">{STUDENT_ONLY_EMPTY_ENTRY}</p>}</>}</div>
          <div data-cb-scholarships><small className="cb-label">Scholarships</small>{!sch.length?<Empty id="scholarships">No published scholarship applies to this course.</Empty>:
            <><ul className="cb-list" data-cb-sch-list>{schShown.map((s,i)=><li key={s.id||s.mapping_id||i}><span>{s.name||s.title}</span><b>{s.value_label||s.value_text||s.amount_text||(s.amount!=null?fmtMoney(s.amount,s.currency||'AUD'):'')}</b></li>)}</ul>{schToggle}</>}</div>
        </div>
      </Card>
    </div>
  </section>}

export function ProviderCorrelated({data,rank=0}){
  const curator=Number(rank)>=3,providerId=data?.id
  const pd=useRead(()=>rpc('admin_provider_destination_read',{p_provider_id:providerId}),[providerId],!!providerId)
  const rk=useRead(()=>api.providerRankingHistory(providerId).then(d=>d?.items||[]),[providerId],!!providerId)
  const mt=useRead(()=>reviewList('locality_metric'),[curator],curator)
  if(!providerId)return null
  const snap=rankingSnapshot(rk.data),campuses=(pd.data?.campuses||[]).map(p=>campusLocalities([{name:p.name}],[p])[0]).filter(Boolean)
  const regs=pd.data?.registrations||[]
  return <section className="cb" data-correlated="provider" aria-label="Around this provider">
    <header className="cb-head"><strong>Around this provider</strong><small>Read only. Rankings by provider, each campus city, and what the provider holds.</small></header>
    <div className="cb-grid">
      <Card id="rankings" icon={Trophy} title="Rankings">
        {!rk.done?<small>Loading…</small>:rk.err?<Empty id="rankings">{rk.err}</Empty>:<div className="cb-ranks" data-cb-ranks>{snap.systems.map(s=><div key={s.code} className="cb-rank" data-cb-rank={s.code}>
          <small>{s.label}</small><b>{s.latest?.rank?`#${String(s.latest.rank).replace(/^#/,'')}`:'Not ranked'}</b>
          <span>{s.latest?`${s.latest.year} edition`:'No edition linked'}{s.previous?` · ${s.previous.year}: #${String(s.previous.rank||'—').replace(/^#/,'')}`:''}</span>
          {s.latest?.score!=null&&<span className="cb-int" data-vis="confidence">score {s.latest.score}</span>}</div>)}</div>}
        {rk.done&&!rk.err&&<p className="cb-sub" data-cb-subject>{snap.subject.length?`Subject ranks: ${snap.subject.slice(0,4).map(x=>`${x.label} #${x.rank||'—'}`).join(' · ')}`:'No subject rank is held yet.'}</p>}
      </Card>
      <Card id="campus_cities" icon={Building2} title="Campus city profiles">
        {!pd.done?<small>Loading…</small>:!campuses.length?<Empty id="campus_cities">No campus is held for this provider yet.</Empty>:campuses.slice(0,6).map((l,i)=><City key={i} loc={l} metrics={curator?mt.data:null}/>)}
        {campuses.length>6&&<small className="cb-sub">and {campuses.length-6} more campuses</small>}
        {!curator&&<Gap>{GAP_TEXT}</Gap>}
      </Card>
      <Card id="scholarships_accreditations" icon={Award} title="Scholarships & accreditations">
        <ul className="cb-list">
          <li data-cb-fact="scholarships"><span>Scholarships</span><b>{fmtNumber(Number(data.scholarship_count||0))}</b></li>
          <li data-cb-fact="accreditations"><span>Accreditations (AACSB, EQUIS, AMBA)</span><b>{Array.isArray(data.accreditations)&&data.accreditations.length?data.accreditations.map(a=>a.body_code||a).join(', '):'Sent in API v3'}</b></li>
          {regs.slice(0,3).map((r,i)=><li key={i} data-cb-fact="registration"><span>{r.label||String(r.scheme).toUpperCase()}</span><b>{r.code}</b></li>)}
        </ul>
        {!Array.isArray(data.accreditations)&&<Gap>Accreditations are sent to the website as item.provider.accreditations; the admin read for them is part of the S2-Build hand-off.</Gap>}
      </Card>
    </div>
  </section>}

// "Preview as" in the drawer header, for Editors and Platform Admins: shows the drawer as a lower role sees it
export function PreviewAs({value,onChange}){
  return <div className="cb-preview" role="toolbar" aria-label="Preview as" data-preview-as={value}><Eye size={13} aria-hidden="true"/><small>Preview as</small>
    {PREVIEW_ROLES.map(r=><button key={r.key} type="button" className={`cb-preview-btn${value===r.key?' is-on':''}`} aria-pressed={value===r.key} data-preview-role={r.key} onClick={()=>onChange(r.key)}>{r.label}</button>)}</div>}
// one <style> that hides internal markers inside a drawer showing a student-facing view
export function VisibilityStyle(){return <style data-visibility-style>{studentHideCss()}</style>}
export const audienceAttr=tier=>audienceOf(tier)
