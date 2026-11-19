// CF-247 s807 (Platform Admin 20 Nov 2026 06:10, chat S1-RM-Design): the UnoPim patterns on the Courses and Providers grids.
//   - CompletenessBar: a per-row bar. Courses use the score the server already works out (completeness_score_v2: registration, structure, fee, intake,
//     English and description held, six signals). Providers use the share of the nine provider fields that security.provider_missing_fields_v1 tracks.
//   - MissingFieldBar: a row of pills; each pill that is on narrows the list to records that lack that field (all pills on = lacking every one of them).
//     The filter runs on the server before the page is cut: Courses through the filters courses_page already has, Providers through the `missing`
//     argument of security.admin_providers_page_v3 (migration 20261120100000).
//   - ProviderBulkBar: what a ticked set of providers can do (fill fields, export the ticked rows, clear).
// Nothing here writes to the catalogue, and no value here is an operational limit (G2): the bar has no colour bands or thresholds.
import React from'react'
import{Download,Wand2,X}from'lucide-react'
import{fmtNumber}from'./lib/format.js'
import'./completeness-bar.css'

// fixed: the nine provider fields security.provider_missing_fields_v1 reports, in its order (the server is the source of truth; the migration checks the same list)
export const PROVIDER_TRACKED_FIELDS=['description','website','city','state_region','provider_type','phone','email','address','established_year']
export const PROVIDER_FIELD_WORDS={description:'Description',website:'Website',city:'City',state_region:'State / Region',provider_type:'Type',phone:'Phone',email:'Email',address:'Address',established_year:'Established year'}

/** Whole-number percentage of the tracked provider fields held, or null when the row does not say what is missing. */
export function providerCompleteness(missing){
  if(!Array.isArray(missing))return null
  const total=PROVIDER_TRACKED_FIELDS.length,gone=new Set(missing.filter(m=>PROVIDER_TRACKED_FIELDS.includes(m))).size
  return Math.round(((total-gone)*100)/total)
}
/** The course score as a whole number, or null when the row carries none. */
export function courseCompleteness(score){
  const n=Number(score)
  return score==null||score===''||!Number.isFinite(n)?null:Math.max(0,Math.min(100,Math.round(n)))
}

export function CompletenessBar({pct,title,compact=false}){
  if(pct==null)return <span className="cbar-unknown" data-completeness="unknown" title="This row does not say how complete it is">—</span>
  return <span className={`cbar${compact?' compact':''}${pct===100?' full':''}`} data-completeness={pct} title={title||`${pct}% complete`}>
    <span className="cbar-track" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct} aria-label={`${pct}% complete`}><span className="cbar-fill" style={{width:`${pct}%`}}/></span>
    <b className="cbar-n">{pct}%</b>
  </span>
}

// The Course pills ride the filters the course list already has: a pill is on when its filter holds the "missing" value.
export const COURSE_MISSING_PILLS=[
  {id:'fee',label:'Fee',key:'hasFee',value:'false'},
  {id:'intake',label:'Intake',key:'hasIntake',value:'false'},
  {id:'english',label:'English',key:'hasEnglish',value:'false'},
  {id:'scholarship',label:'Scholarship',key:'hasScholarship',value:'false'},
  {id:'description',label:'Description',key:'courseDescription',value:'missing'},
  {id:'study_load',label:'Study load',key:'studyLoad',value:'none'},
]
export const providerMissingList=v=>String(v||'').split(',').map(s=>s.trim()).filter(Boolean)

export function MissingFieldBar({type,filters,patch,total,busy}){
  if(type==='course'){
    const on=COURSE_MISSING_PILLS.filter(p=>filters[p.key]===p.value)
    return <div className="mfb" data-missing-bar="course" role="group" aria-label="Missing field filter">
      <span className="mfb-label">Missing field</span>
      {COURSE_MISSING_PILLS.map(p=>{const active=filters[p.key]===p.value
        return <button key={p.id} type="button" className={`mfb-pill${active?' on':''}`} aria-pressed={active} data-missing-pill={p.id} onClick={()=>patch(p.key,active?'':p.value,active?'':p.label)}>{p.label}</button>})}
      {on.length>0&&<><span className="mfb-note" data-missing-count aria-live="polite">{busy?'…':`${fmtNumber(total||0)} lack ${on.length>1?'all of these':'this'}`}</span>
        <button type="button" className="mfb-clear" data-missing-clear onClick={()=>on.forEach(p=>patch(p.key,''))}><X size={12}/>Clear</button></>}
    </div>
  }
  if(type==='provider'){
    const on=providerMissingList(filters.missing)
    const toggle=id=>{const next=on.includes(id)?on.filter(x=>x!==id):[...on,id];patch('missing',next.join(','),next.map(x=>PROVIDER_FIELD_WORDS[x]).join(', '))}
    return <div className="mfb" data-missing-bar="provider" role="group" aria-label="Missing field filter">
      <span className="mfb-label">Missing field</span>
      {PROVIDER_TRACKED_FIELDS.map(id=>{const active=on.includes(id)
        return <button key={id} type="button" className={`mfb-pill${active?' on':''}`} aria-pressed={active} data-missing-pill={id} onClick={()=>toggle(id)}>{PROVIDER_FIELD_WORDS[id]}</button>})}
      {on.length>0&&<><span className="mfb-note" data-missing-count aria-live="polite">{busy?'…':`${fmtNumber(total||0)} lack ${on.length>1?'all of these':'this'}`}</span>
        <button type="button" className="mfb-clear" data-missing-clear onClick={()=>patch('missing','')}><X size={12}/>Clear</button></>}
    </div>
  }
  return null
}

const csvCell=v=>{const s=v==null?'':String(v);return /[",\r\n]/.test(s)?`"${s.replace(/"/g,'""')}"`:s}
/** The ticked providers as CSV text: what the grid shows for them, nothing the grid does not already hold. */
export function pickedProvidersCsv(rows,pickedIds){
  const ids=new Set(pickedIds.map(String)),head=['id','provider','country','completeness_percent','missing_fields']
  const lines=[head.join(',')]
  for(const r of rows||[]){
    if(!ids.has(String(r.id)))continue
    const miss=r.pdesc&&Array.isArray(r.pdesc.missing_fields)?r.pdesc.missing_fields:null,pct=providerCompleteness(miss)
    lines.push([r.id,r.display_name||r.canonical_name,r.country_code,pct==null?'':pct,miss?miss.join(' '):''].map(csvCell).join(','))
  }
  return lines.join('\r\n')+'\r\n'
}

export function ProviderBulkBar({picked,rows,cap,onFill,onClear,canFill}){
  if(!picked.length)return null
  const exportCsv=()=>{
    const blob=new Blob([pickedProvidersCsv(rows,picked)],{type:'text/csv;charset=utf-8'}),a=document.createElement('a')
    a.href=URL.createObjectURL(blob);a.download='providers-selected.csv';document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(a.href),1000)
  }
  return <div className="cbulk" data-bulk-bar role="toolbar" aria-label="Actions for the ticked providers">
    <strong data-bulk-count>{fmtNumber(picked.length)} selected{cap?<small> of at most {fmtNumber(cap)}</small>:null}</strong>
    {canFill&&<button type="button" className="m-secondary compact" data-bulk-fill onClick={onFill}><Wand2 size={13}/>Fill fields for these</button>}
    <button type="button" className="m-secondary compact" data-bulk-export onClick={exportCsv}><Download size={13}/>Export selected (CSV)</button>
    <button type="button" className="mfb-clear" data-bulk-clear onClick={onClear}><X size={12}/>Clear selection</button>
  </div>
}

// Where a provider's description came from, in the three words the platform uses: Register (written from verified register facts), AI verified (a machine
// reading that passed the checks, or a person's approval of one) and Human input (entered by hand, locked against automation).
const TIER_PILL={registry_factual:['Register','register'],stored:['AI verified','ai'],direct:['AI verified','ai'],firecrawl:['AI verified','ai']}
export function ProvenancePill({kind,title}){
  const k={register:'Register',ai:'AI verified',human:'Human input · Locked',unknown:'Source not recorded'}[kind]||'Source not recorded'
  return <span className={`cprov cprov-${kind||'unknown'}`} data-provenance={kind||'unknown'} title={title}>{k}</span>
}
export function ProviderProvenancePanel({row,data}){
  const d=row&&row.pdesc&&typeof row.pdesc==='object'?row.pdesc:null
  const missing=d&&Array.isArray(d.missing_fields)?d.missing_fields:(Array.isArray(data?.missing_fields)?data.missing_fields:null)
  if(!missing&&!d)return null
  const tier=d?.source_tier,t=TIER_PILL[tier],filled=d?!!d.description_filled:(missing?!missing.includes('description'):null)
  return <section className="cprov-panel" data-provenance-panel aria-label="Where this provider's values came from">
    <h4>Completeness and provenance</h4>
    <CompletenessBar pct={providerCompleteness(missing)} title="Share of the nine tracked provider fields that hold a value"/>
    <ul className="cprov-list">
      {PROVIDER_TRACKED_FIELDS.map(f=>{const gone=missing?missing.includes(f):null
        return <li key={f} data-prov-field={f}><span>{PROVIDER_FIELD_WORDS[f]}</span>
          {gone==null?<em>not read</em>:gone?<em className="cprov-missing">Missing</em>:f==='description'&&filled&&t?<ProvenancePill kind={t[1]} title={`Description source: ${tier}`}/>:f==='description'&&filled?<ProvenancePill kind="unknown" title="A description is held but how it was read was not recorded"/>:<span className="cprov-held">Held</span>}</li>})}
    </ul>
    <p className="cprov-note">Only the description records where it came from. The other fields show Held or Missing: their source is not recorded per field yet.</p>
  </section>
}
