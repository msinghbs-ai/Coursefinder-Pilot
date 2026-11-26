// CF-247 s1272 (DR-19, SS-Programme-Control 26 Nov 2026 19:19, the Platform Admin's mandate "Intelligent monitoring and human-assisted resolution"):
// the Processing journey and diagnosis fold of a Layer 4 card. It reads public.admin_record_journey_v1 when the fold is opened and shows what the
// server says: the eight stages, where processing stopped and why later stages are not reached, and the diagnosis. Nothing is worked out here.
// A value the platform does not hold reads "Not available", an unchecked one "Not verified", and a measured zero reads 0. The authorised next
// action is the card's own decision buttons (the same choices, roles and admission paths). Design: admin
// docs/platform/2026-11-26-dr19-record-journey-and-diagnosis-design.md.
import React,{useState}from'react'
import{supabase}from'./lib/supabase'
import{StatusChip}from'./ui-kit'
import{roleName}from'./nav-map'
import'./layer4-item-lifecycle.css'

export const STATE={done:['Done','success'],failed:['Failed','danger'],held:['Held','warning'],not_started:['Not started','neutral'],skipped:['Not needed','neutral'],
  waiting:['Not reached','neutral'],not_verified:['Not verified','info'],unavailable:['Not available','neutral']}
const NA=({why})=><em className="l4j-na" data-l4j-na title={why||undefined}>Not available{why?` (${why})`:''}</em>
const money=v=>v==null?null:`US$${Number(v).toFixed(Number(v)>0&&Number(v)<0.01?4:2)}`
const words=o=>o&&typeof o==='object'?Object.entries(o).filter(([,v])=>v!==null&&v!==undefined&&v!=='').map(([k,v])=>`${k.replace(/_/g,' ')}: ${typeof v==='object'?JSON.stringify(v):v}`).join(' · '):String(o??'')

export const readJourney=(kind,ref)=>supabase.rpc('admin_record_journey_v1',{p_args:{kind,ref}}).then(({data,error})=>{if(error)throw new Error(error.message);return data})

/** The eight stages as a strip that wraps on a phone. */
export function Stages({stages,stoppedAt}){
  return <ol className="l4j-stages" data-l4j-stages>{(stages||[]).map(s=>{const[l,t]=STATE[s.state]||[s.state,'neutral']
    return <li key={s.key} className={`l4j-stage${s.key===stoppedAt?' is-stop':''}`} data-l4j-stage={s.key} data-l4j-state={s.state}>
      <span className="l4j-stage-head"><strong>{s.label}</strong> <StatusChip tone={t} label={l}/></span>
      {s.reason&&<small>{s.reason}</small>}{s.at&&<small className="l4lc-ref"> · {s.at}</small>}
      {s.detail&&<small className="l4j-detail">{words(s.detail)}</small>}</li>})}</ol>
}

/** The diagnosis rows, each from the server; absent values say so. */
export function Diagnosis({j,actions}){
  const d=j.diagnosis||{},ev=d.evidence,at=d.attempts||{},rd=d.reader,ai=d.ai_diagnosis||{},sim=d.similar,rec=d.recommendation||{},gain=d.gain,out=d.outcome||{}
  const simCounts=sim?.counts&&Object.keys(sim.counts).length?Object.entries(sim.counts).map(([k,v])=>`${v} ${k.replace(/_/g,' ')}`).join(', '):null
  return <dl className="l4lc-steps l4j-diag" data-l4j-diagnosis>
    <dt>Exact failure reason</dt><dd data-l4j="reason">{d.failure_reason||'Every recorded stage is done'}</dd>
    <dt>Stored source evidence</dt><dd data-l4j="evidence">{ev?<>{ev.stored?'Stored copy':'No stored copy'}{ev.type?` · ${ev.type}`:''}{ev.captured?` · ${ev.captured}`:''}{ev.hash?` · hash ${ev.hash}`:''}
      {ev.page&&<> · <a href={ev.page} target="_blank" rel="noopener noreferrer">source page</a></>}</>:<NA why="no stored copy is linked"/>}</dd>
    <dt>Previous attempts</dt><dd data-l4j="attempts">{`${Number(at.events||0)} recorded event${Number(at.events)===1?'':'s'} · ${Number(at.corrected_reads||0)} corrected read${Number(at.corrected_reads)===1?'':'s'}`}
      {at.recovery_attempts!=null&&` · ${at.recovery_attempts} technical recovery attempt${Number(at.recovery_attempts)===1?'':'s'}${at.failure_class?` (${at.failure_class})`:''}`}
      {at.automated_attempts!=null&&` · ${at.automated_attempts} automatic attempt${Number(at.automated_attempts)===1?'':'s'}`}{at.last&&` · last ${at.last}`}</dd>
    <dt>Reader and AI model</dt><dd data-l4j="reader">{!rd?<NA why="this kind of item keeps no reader record"/>:!rd.recorded?<NA why="no reader run is linked to this item"/>:
      <>{rd.reader||'Reader'}{rd.deterministic===true?' · deterministic (no model)':rd.reader_model?` · ${rd.reader_model}`:''}{rd.ai_model?` · AI ${rd.ai_model}`:''}{rd.prompt?` · prompt ${rd.prompt}`:''}{rd.confidence!=null?` · confidence ${rd.confidence}`:''}</>}</dd>
    <dt>Failed validation or admission gate</dt><dd data-l4j="gate">{d.gate?.hold_reason||d.gate?.why_pending||(d.gate?.gate?words(d.gate.gate):'None recorded')}</dd>
    <dt>AI-assisted root cause diagnosis</dt><dd data-l4j="ai" data-l4j-ai={ai.state}>{ai.state==='available'?<>{words(ai.analysis)}{ai.required_input&&<><br/><em>Needs:</em> {words(ai.required_input)}</>}</>:<em>Not run. {ai.reason}</em>}</dd>
    <dt>Similar resolved cases</dt><dd data-l4j="similar">{!sim?<NA why="similar cases are kept for review items"/>:simCounts?<>{simCounts} in the last {sim.days} days{(sim.latest||[]).length>0&&<ul className="l4j-sim">{sim.latest.map(x=><li key={x.ref}>{x.decided} · {String(x.status).replace(/_/g,' ')}{x.subject?` · ${x.subject}`:''}{x.reference?` · ${x.reference}`:''}</li>)}</ul>}</>:`0 in the last ${sim.days} days`}</dd>
    <dt>PR and resolution references</dt><dd data-l4j="references">{(d.references||[]).length?d.references.join(' · '):'None recorded'}</dd>
    <dt>Recommended recovery</dt><dd data-l4j="recommendation">{rec.text?<>{rec.text}{rec.basis?<small className="l4lc-ref"> ({rec.basis})</small>:null}{rec.owner?<small className="l4lc-ref"> · {rec.owner}</small>:null}</>:<NA/>}</dd>
    <dt>Estimated recovery cost</dt><dd data-l4j="cost">{(d.cost||[]).length?d.cost.map((c,i)=><span key={i} className="l4j-cost">{c.action}: {c.usd==null?<NA why={c.basis}/>:<strong>{money(c.usd)}</strong>}{c.usd!=null&&c.basis?<small className="l4lc-ref"> ({c.basis})</small>:null}</span>):<NA why="no recovery cost is recorded for this kind of item"/>}</dd>
    <dt>Data population gain</dt><dd data-l4j="gain">{gain?<>{gain.state==='realised'?'Realised':'Potential'}: {gain.field?.replace(/_/g,' ')}{gain.courses?` for ${gain.courses} course`:''}{gain.providers?` for ${gain.providers} provider`:''}{gain.rows!=null?` · ${gain.rows} row${gain.rows===1?'':'s'}`:''}</>:<NA/>}</dd>
    <dt>Authorised next action</dt><dd data-l4j="actions">{(actions||[]).length?actions.map((a,i)=><span key={i} className="l4j-act" data-l4j-allowed={String(a.allowed)}>{i?' · ':''}{a.label}{a.allowed?'':` (needs ${roleName(a.need)})`}</span>):'No decision is offered on this card'}<small className="l4lc-ref"> Use the card's buttons above.</small></dd>
    <dt>Actual outcome</dt><dd data-l4j="outcome">{[out.status&&String(out.status).replace(/_/g,' '),out.decided&&`decided ${out.decided}`,out.admitted&&`admission: ${out.admitted}`,out.published&&`publication: ${out.published}`].filter(Boolean).join(' · ')||'Not decided yet'}</dd>
  </dl>
}

/** The fold: closed by default; the journey is read when it is first opened, and again with Refresh. */
export default function Layer4Journey({kind,refId,actions}){
  const[j,setJ]=useState(null),[err,setErr]=useState(''),[busy,setBusy]=useState(false)
  const load=()=>{setBusy(true);setErr('');readJourney(kind,refId).then(setJ).catch(e=>setErr(e.message)).finally(()=>setBusy(false))}
  return <details className="l4z-fold l4j" data-l4-fold="journey" onToggle={e=>{if(e.currentTarget.open&&!j&&!busy)load()}}>
    <summary>Processing journey and diagnosis</summary>
    {busy&&!j&&<p className="l4lc-ref" role="status">Reading the journey…</p>}
    {err&&<p className="l4lc-err" role="alert" data-l4j-error>The journey could not be read: {err}</p>}
    {j&&j.found===false&&<p className="l4lc-ref">This record is no longer in Layer 4.</p>}
    {j&&j.found!==false&&<section className="l4lc" data-l4j-family={j.family} data-l4j-stopped={j.stopped_at||'none'}>
      <p className="l4j-stop" data-l4j-stop>{j.stopped_at?<><strong>Stopped at {String(j.stopped_label).toLowerCase()}</strong> ({(STATE[j.stopped_state]||[j.stopped_state])[0].toLowerCase()}): {j.stopped_reason}</>:<strong>Every recorded stage is done.</strong>}</p>
      <Stages stages={j.stages} stoppedAt={j.stopped_at}/>
      <Diagnosis j={j} actions={actions}/>
      <p className="l4lc-ref">Read {j.generated_at} · <button type="button" className="l4j-refresh" onClick={load} disabled={busy}>{busy?'Reading…':'Refresh'}</button></p>
    </section>}
  </details>
}
