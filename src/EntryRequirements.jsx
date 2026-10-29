// CF-247 v2.15.361 Track C Step B (B5; Platform Admin mandate 28 Oct 2026 20:36; admin docs/platform/ENTRY-REQUIREMENTS-STEP-B-DECISION-2026-10-28.md):
// academic entry requirements inside the existing Provider drawer and Course detail blade. Read only, bounded (one provider or one course,
// at most 100 rows a call): the provider's published entry matrix (country, level, qualification, band, minimum, scale, quote, source,
// evidence, as at, status, the reading run and its Layer 4 item), the course's own requirement rows, and the five-rule resolution for a
// country of prior education. A Platform Admin may ask for one course's requirements to be read from its stored page; the rows then wait
// in Layer 4. Nothing here edits a row or admits anything: admission stays in Layer 4.
// AER programme (29 Oct 2026): the provider section also lists its sources and each one's latest read (rows, rows not kept, a hold and its
// reason, cost, Layer 4 item), so a source held or refused is visible, not only one that gave rows.
// v2.15.363 (AER operations workspace, decision W2): these sections stay read-only and are shortcuts into Catalogue › Entry requirements,
// where rows are filtered, corrected, added, withdrawn, re-read and resolved. There is one editing implementation, in the workspace.
// Server: public.admin_entry_requirements(action, args).
import React,{useEffect,useState}from'react'
import{GraduationCap,RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,StatusChip,Pager,fmtDate,fmtNumber}from'./ui-kit'
import{ReasonAction}from'./ProviderOnboarding'
import{plainError}from'./lib/errors'
import{hrefFor}from'./nav-map'
import{orderAerCountries,readAerCountry,saveAerCountry}from'./aer-countries'

const call=async(action,args)=>{const{data,error}=await supabase.rpc('admin_entry_requirements',{p_action:action,p_args:args});if(error)throw error;return data}
const OUTCOME={minimum_published:'A minimum is published',case_by_case:'This qualification is considered case by case',contact_provider:'Requirements for this qualification aren’t published — contact the provider'}
const RULE={course_override:'1 · Course rule',course_country_row:'2 · Course row for this country',band_ladder:'3 · Course band → provider table',provider_minimum:'4 · Provider minimum',contact_provider:'5 · Contact the provider'}
const Src=({url})=>url?<a href={url} target="_blank" rel="noreferrer">source</a>:'—'

export function ProviderEntryMatrix({providerId}){
  const[f,setF]=useState({status:'active',country:'',level:''}),[offset,setOffset]=useState(0),[d,setD]=useState(null),[err,setErr]=useState('')
  const size=50
  useEffect(()=>{if(!providerId)return;let on=true;setErr('')
    call('provider_matrix',{provider_id:providerId,...f,page:Math.floor(offset/size)+1,page_size:size}).then(x=>on&&setD(x)).catch(e=>on&&setErr(plainError(e)))
    return()=>{on=false}},[providerId,f,offset])
  if(err)return <p className="fr-error" role="alert">{err}</p>
  if(!d)return null
  const total=Object.values(d.counts||{}).reduce((a,b)=>a+Number(b||0),0)
  const set=(k,v)=>{setOffset(0);setF(x=>({...x,[k]:v}))}
  const sources=d.sources||[]
  return <section className="rl-provider" data-entry-matrix>
    <h4><GraduationCap size={14}/>Academic entry requirements <a className="cf-link" href={hrefFor('entry','',{provider:providerId})} data-entry-workspace-link>Open in Entry requirements</a></h4>
    {sources.length>0&&<details data-entry-sources open={!total}><summary>Sources and reads ({fmtNumber(d.sources_total||sources.length)})</summary>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Source</th><th>Fetch</th><th>Latest read</th><th>Rows</th><th>Not kept</th><th>Hold or error</th><th>Layer 4</th></tr></thead>
        <tbody>{sources.map(x=><tr key={x.id} data-entry-source={x.status}>
          <td><Src url={x.url}/> <small>{x.title||''}</small></td>
          <td><StatusChip value={x.status} label={x.status}/>{x.read_via&&<small> · {x.read_via}</small>}{x.read_at&&<small> · {fmtDate(x.read_at)}</small>}</td>
          <td>{x.run?<small>{x.run.state}{x.run.basis?` · ${x.run.basis}`:''}{x.run.cost_usd!=null?` · US$${Number(x.run.cost_usd).toFixed(4)}`:''}</small>:'—'}</td>
          <td>{x.run?.rows??'—'}</td><td>{x.run?.not_kept??'—'}</td>
          <td><small>{String(x.run?.error||x.error||'').slice(0,140)||'—'}</small></td>
          <td>{x.run?.review_status||'—'}</td></tr>)}</tbody></table></div>
    </details>}
    {!total?<small>{sources.length?'No row read for this provider yet.':'No entry requirements read for this provider.'}</small>:<>
      <small data-entry-counts>{Object.entries(d.counts||{}).map(([s,n])=>`${fmtNumber(n)} ${s}`).join(' · ')}</small>
      <div className="sd-actions">
        <label>Status <select value={f.status} onChange={e=>set('status',e.target.value)} aria-label="Entry rows status"><option value="">All</option>{['active','proposed','inactive','superseded'].map(s=><option key={s} value={s}>{s}</option>)}</select></label>
        <label>Country <select value={f.country} onChange={e=>set('country',e.target.value)} aria-label="Entry rows country"><option value="">All</option>{orderAerCountries(d.countries).map(c=><option key={c.code} value={c.code}>{c.code} ({fmtNumber(c.n)})</option>)}</select></label>
        <label>Level <select value={f.level} onChange={e=>set('level',e.target.value)} aria-label="Entry rows level"><option value="">All</option>{(d.levels||[]).map(l=><option key={l} value={l}>{l}</option>)}</select></label>
      </div>
      <div className="cf-table-wrap"><table className="cf-table" data-entry-rows><thead><tr><th>Country</th><th>Level</th><th>Qualification</th><th>Band</th><th>Minimum</th><th>Scale</th><th>Quote</th><th>Source</th><th>As at</th><th>Status</th><th>Read</th></tr></thead>
        <tbody>{(d.rows||[]).map(r=><tr key={r.id} data-entry-row={r.status}>
          <td>{r.country}</td><td>{r.level||'—'}{r.course_code&&<small> · {r.course_code}</small>}</td><td>{r.qualification}</td><td>{r.band||'—'}</td>
          <td>{r.min_grade||<em>case by case</em>}{r.conditions&&((r.conditions.subject_minimums||[]).length>0||(r.conditions.alternatives||[]).length>0)&&<small> · conditions</small>}</td><td>{r.scale||'—'}</td>
          <td><small>“{r.quote}”</small></td><td><Src url={r.source_url}/>{r.evidence&&<small> · copy {fmtDate(r.evidence.captured_at)}</small>}</td>
          <td>{fmtDate(r.as_at)}{r.edition&&<small> · {r.edition}</small>}</td>
          <td><StatusChip value={r.status} label={r.status}/>{r.status_reason&&<small title={r.status_reason}> · {r.status_reason.slice(0,60)}</small>}</td>
          <td>{r.run?<small>{r.run.state}{r.run.error?` · ${String(r.run.error).slice(0,60)}`:''}{r.run.review_status?` · Layer 4 ${r.run.review_status}`:''}</small>:'—'}</td></tr>)}</tbody></table></div>
      <Pager offset={offset} limit={size} total={Number(d.total||0)} onOffset={setOffset}/>
    </>}
  </section>
}

export function CourseEntryRequirements({courseId,onError}){
  const[d,setD]=useState(null),[cc,setCc]=useState(''),[res,setRes]=useState(null),[busy,setBusy]=useState(false),[msg,setMsg]=useState('')
  const load=async()=>{try{setD(await call('course',{course_id:courseId}))}catch(e){onError?.(plainError(e))}}
  useEffect(()=>{if(courseId)load()},[courseId])
  // A4 (29 Oct 2026): changing the country only asks the bounded resolver; the choice is kept for this viewer across reloads
  const resolve=async(c,keep=true)=>{setCc(c);setRes(null);if(keep)saveAerCountry(c);if(!c)return;try{setRes(await call('resolve',{course_id:courseId,country:c}))}catch(e){onError?.(plainError(e))}}
  useEffect(()=>{if(!d||cc)return;const k=readAerCountry();if(k&&(d.countries||[]).some(c=>c.code===k))resolve(k,false)},[d])
  const read=async reason=>{setBusy(true);try{await call('read',{course_id:courseId,reason});setMsg('Asked. The rows wait in Layer 4 for a person before any is used.');await load()}catch(e){onError?.(plainError(e));throw e}finally{setBusy(false)}}
  if(!d)return null
  return <section className="rl-provider" data-course-entry>
    <h4><GraduationCap size={14}/>Academic entry requirements <Button compact onClick={load} disabled={busy}><RefreshCw size={13}/>Refresh</Button> <a className="cf-link" href={hrefFor('entry','course',{course:courseId})} data-entry-workspace-link>Open in Entry requirements</a> <a className="cf-link" href={hrefFor('entry','resolve',{course:courseId})}>Inspect resolution</a></h4>
    {(d.rows||[]).length===0?<small>Nothing read from this course's page yet.</small>:
    <div className="cf-table-wrap"><table className="cf-table" data-course-entry-rows><thead><tr><th>Kind</th><th>Requirement</th><th>Score and basis</th><th>Band</th><th>For</th><th>Quote</th><th>Source</th><th>As at</th><th>Status</th></tr></thead>
      <tbody>{d.rows.map(r=><tr key={r.id} data-course-entry-row={r.status}><td>{r.kind.replaceAll('_',' ')}</td><td>{r.description}</td>
        <td>{r.min_entry_score!=null?`${r.min_entry_score} (${r.min_entry_score_basis})`:'—'}</td><td>{r.benchmark_band||'—'}</td><td>{r.audience}</td>
        <td><small>“{r.quote}”</small></td><td><Src url={r.source_url}/></td><td>{fmtDate(r.as_at)}</td>
        <td><StatusChip value={r.status} label={r.status}/>{r.status==='proposed'&&<small> · waiting in Layer 4</small>}</td></tr>)}</tbody></table></div>}
    {(d.reads||[]).length>0&&<small data-course-entry-reads>Last read: {d.reads[0].state}{d.reads[0].reason?` · ${d.reads[0].reason}`:''}{d.reads[0].cost_usd!=null?` · US$${Number(d.reads[0].cost_usd).toFixed(4)}`:''}{(d.reads[0].dropped||[]).length?` · ${d.reads[0].dropped.length} not kept (${[...new Set(d.reads[0].dropped.map(x=>x.reason))].join(', ')})`:''}</small>}
    <div className="sd-actions" data-course-entry-resolve>
      <label style={{display:'flex',flexWrap:'wrap',alignItems:'center',gap:6,minWidth:0,maxWidth:'100%'}}>Country of prior education <select value={cc} onChange={e=>resolve(e.target.value)} aria-label="Country of prior education" style={{minWidth:0,maxWidth:'100%'}}><option value="">Choose…</option>{orderAerCountries(d.countries).map(c=><option key={c.code} value={c.code}>{c.name}</option>)}</select></label>
    </div>
    {res&&<div role="status" data-entry-resolution={res.outcome}>
      <p className="sd-desc"><strong>{OUTCOME[res.outcome]||res.outcome}</strong> <small>({RULE[res.rule]||res.rule}{res.band?` · band ${res.band}`:''})</small></p>
      {res.note&&<p className="sd-desc"><small>{res.note}</small></p>}
      {(res.rows||[]).length>0&&<div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Qualification</th><th>Level</th><th>Minimum</th><th>Scale</th><th>Quote</th><th>As at</th></tr></thead>
        <tbody>{res.rows.map((r,i)=><tr key={i}><td>{r.qualification||r.text}</td><td>{r.study_level||'—'}</td><td>{r.min_grade||r.min_score||<em>case by case</em>}</td><td>{r.scale||r.min_score_basis||'—'}</td><td><small>“{r.quote}”</small></td><td>{fmtDate(r.as_at)}</td></tr>)}</tbody></table></div>}
    </div>}
    {d.can_read&&<div className="sd-actions" data-course-entry-read><ReasonAction label="Read from the stored page" confirm="Read once" testid="course-entry-read" disabled={busy} onDo={read}/></div>}
    {msg&&<small role="status">{msg}</small>}
  </section>
}
