// v2.15.276 (CF-247, Decision 258; Platform Admin 14 Oct 2026: "Map institution type"): the institution type rules, on Settings ›
// Pipeline settings. Each provider takes the type of the first enabled rule (by position) that matches its register facts
// (TEQSA National Register category and status, CRICOS institution type, NZQA organisation type) and its active courses.
// A type set by hand on the Providers screen is kept. Read: admin_provider_type_rules('list') (any role); change a rule's
// type, position or switch, and run the rules now: Platform Admin. No reason is asked (routine admin action).
import React,{useEffect,useState}from'react'
import{Play,Tags}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,SectionTitle}from'./ui-kit'
import{fmtNumber}from'./lib/format.js'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const PROFILE={vet:'offers VET courses',school_no_vet:'school courses only (no VET)',non_aqf_only:'English or foundation courses only'}
const strip=p=>String(p||'').replace(/^\^\(?|\)?\$$/g,'').replace(/\|/g,' or ')
export function ruleMatch(r){
  const parts=[]
  if(r.teqsa_category)parts.push(`TEQSA ${strip(r.teqsa_category)}${r.teqsa_status?` (${strip(r.teqsa_status)})`:''}`)
  if(r.register_type)parts.push(`CRICOS ${strip(r.register_type)}`)
  if(r.nz_org_type)parts.push(`NZQA ${strip(r.nz_org_type)}`)
  if(r.course_profile)parts.push(PROFILE[r.course_profile]||r.course_profile)
  return parts.join(' · ')||'any provider'
}

export default function InstitutionTypeRules({onError}){
  const[d,setD]=useState(null),[busy,setBusy]=useState(''),[msg,setMsg]=useState(''),[err,setErr]=useState('')
  const call=async(action,args={})=>{const{data,error}=await supabase.rpc('admin_provider_type_rules',{p_action:action,p_args:args});if(error)throw error;return data}
  const load=()=>call('list').then(setD).catch(e=>{setErr(errText(e));onError?.(errText(e))})
  useEffect(()=>{load()},[])
  const save=async(r,patch,label)=>{setBusy(r.id);setMsg('');setErr('');try{const x=await call('save',{id:r.id,...patch});setMsg(`Saved: ${label}. ${fmtNumber(Number(x?.classify?.classified||0))} providers typed, ${fmtNumber(Number(x?.classify?.no_rule||0))} need a type.`);await load()}catch(e){setErr(errText(e))}finally{setBusy('')}}
  const run=async()=>{setBusy('run');setMsg('');setErr('');try{const x=await call('run');setMsg(`Rules run: ${fmtNumber(Number(x?.classified||0))} providers typed, ${fmtNumber(Number(x?.no_rule||0))} need a type, ${fmtNumber(Number(x?.changed||0))} changed.`);await load()}catch(e){setErr(errText(e))}finally{setBusy('')}}
  if(!d)return <section className="m-panel" data-settings-section="institution_type">{err?<p className="fr-error" role="alert">{err}</p>:<p className="sd-desc">Loading institution type rules…</p>}</section>
  const can=Boolean(d.can_edit)&&!busy,types=d.types||[],counts=d.counts||{},name=c=>types.find(t=>t.code===c)?.name||c
  return <section className="m-panel" data-settings-section="institution_type">
    <SectionTitle icon={Tags} title="Institution type rules" subtitle="Each provider takes the type of the first enabled rule that matches its register facts and its courses. Runs every day and after each register read. A type set by hand on the Providers screen is kept. Canada has no rules yet."/>
    <p className="ps-note" data-type-counts>{Object.entries(counts).sort((a,b)=>b[1]-a[1]).map(([k,v])=>`${k==='none'?'No type':name(k)} ${fmtNumber(Number(v))}`).join(' · ')}</p>
    <table className="ps-id-table" data-type-rules><thead><tr><th>Order</th><th>Country</th><th>Matches</th><th>Type</th><th>On</th></tr></thead><tbody>
      {(d.rules||[]).map(r=><tr key={r.id} data-type-rule={r.position}>
        <td><input type="number" className="ps-input" aria-label={`Order of ${r.label}`} defaultValue={r.position} disabled={!can} onBlur={e=>{const v=Number(e.target.value);if(Number.isInteger(v)&&v!==r.position)save(r,{position:v},`${r.label} order ${v}`)}}/></td>
        <td>{r.country_code}</td>
        <td><strong>{r.label}</strong><div className="ps-note">{ruleMatch(r)}</div></td>
        <td><select aria-label={`Type for ${r.label}`} value={r.result_type} disabled={!can} onChange={e=>save(r,{result_type:e.target.value},`${r.label} → ${name(e.target.value)}`)}>{types.map(t=><option key={t.code} value={t.code}>{t.name}</option>)}</select></td>
        <td><input type="checkbox" aria-label={`${r.label} on`} checked={Boolean(r.enabled)} disabled={!can} onChange={e=>save(r,{enabled:e.target.checked},`${r.label} ${e.target.checked?'on':'off'}`)}/></td>
      </tr>)}
    </tbody></table>
    {d.can_edit?<div className="ps-row-edit"><Button onClick={run} disabled={!!busy}><Play size={14}/> {busy==='run'?'Running…':'Run the rules now'}</Button></div>:<p className="l3v-note">Only a Platform Admin can change the rules.</p>}
    {msg&&<p className="sd-desc" role="status">{msg}</p>}{err&&<p className="fr-error" role="alert">{err}</p>}
  </section>
}
