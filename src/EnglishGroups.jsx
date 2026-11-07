// Coverage › Attributes › English policies: course-group binding and "No rule yet" (CF-247 English requirements, Platform Admin 6 Nov 2026 §3 and §5).
// A faculty or course-group table is read by the parser (policy.ts v0.3.0) as groups. Nothing reaches the catalogue until a Platform Admin approves the policy
// AND binds each group to courses (public.admin_provider_english_groups_set_v1). A group is matched by field of education and/or a title pattern; a course that two
// groups with different scores reach is held, never guessed. The status read is public.admin_provider_english_status_read (Pipeline Operator and above);
// Run now uses the existing job control (public.admin_automation_control, job policy-add-tests). No other scheduler or monitor is created here.
import React,{useEffect,useState}from'react'
import{Play,RefreshCw,Save}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Loading}from'./ui-kit'
import{fmtDateTime,fmtNumber}from'./lib/format.js'
import{plainError}from'./lib/errors'

const errText=e=>plainError(e)
const LEVEL={undergraduate:'Undergraduate',postgraduate:'Postgraduate coursework'}
export const STAGE_LABEL={approved:'Approved policy',group_proposed:'Course groups waiting for approval and binding',rule_proposed:'Rule waiting for approval',rejected:'Rule rejected',
  page_read_no_rule:'Page read, no rule found',page_not_stored:'Page found, copy not stored yet',weak_candidates_only:'Only weak candidate pages',mapped_no_page:'Searched, no page found',not_mapped:'Not searched yet'}
const key=g=>`${g.group_name}|${g.level||''}`
const reqText=g=>(g.reqs||[]).map(r=>`${r.test_code} ${fmtNumber(Number(r.overall_score))}`).join('; ')

// The editor opened from a policy's detail row. Groups come from the proposal itself (admin_provider_policies_read with the proposal id returns it whole).
export function GroupBinding({id,canBind,onDone}){
  const[p,setP]=useState(null),[err,setErr]=useState(''),[busy,setBusy]=useState(false),[draft,setDraft]=useState({}),[reason,setReason]=useState(''),[msg,setMsg]=useState('')
  useEffect(()=>{supabase.rpc('admin_provider_policies_read',{p_kind:'english_policy',p_id:id}).then(({data,error})=>{
    if(error)return setErr(errText(error))
    const pr=data?.proposal||{},groups=pr.proposal?.groups||[],bound=Object.fromEntries((pr.proposal?.group_bindings||[]).map(b=>[key(b),b]))
    setP({status:pr.status,groups});setDraft(Object.fromEntries(groups.map(g=>[key(g),{fields:(bound[key(g)]?.fields||[]).join(', '),title_regex:bound[key(g)]?.title_regex||''}])))})},[id])
  if(err)return <p className="fr-error" role="alert">{err}</p>
  if(!p)return <Loading label="Loading course groups…"/>
  if(!p.groups.length)return null
  const save=async()=>{setBusy(true);setErr('');setMsg('')
    try{const bindings=p.groups.map(g=>({group_name:g.group_name,level:g.level,fields:(draft[key(g)]?.fields||'').split(/[,\s]+/).filter(Boolean),title_regex:draft[key(g)]?.title_regex||null}))
        .filter(b=>b.fields.length||b.title_regex)
      const{data,error}=await supabase.rpc('admin_provider_english_groups_set_v1',{p_proposal_id:id,p_bindings:bindings,p_reason:reason});if(error)throw error
      setMsg(`${fmtNumber(data?.bound||0)} groups bound${data?.withdrawn_rows?`, ${fmtNumber(data.withdrawn_rows)} earlier rows withdrawn`:''}.`);onDone?.()}catch(e){setErr(errText(e))}finally{setBusy(false)}}
  return <div className="pp-groups" data-english-groups>
    <p className="sd-desc">This policy gives scores by course group (a faculty or a course type). A group reaches courses only after a Platform Admin approves the policy and binds the group to a field of education (ASCED code, for example asced-0805) and/or a title pattern. A course that two groups with different scores reach is held back, and a course with its own page reading, a course set by hand and a course the policy names are never changed.</p>
    <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Group</th><th>Level</th><th>Score</th><th>Fields of education</th><th>Title pattern</th></tr></thead>
      <tbody>{p.groups.map(g=><tr key={key(g)} data-group={g.group_name}>
        <td>{g.group_name}</td><td>{LEVEL[g.level]||g.level||'Any'}</td><td>{reqText(g)}</td>
        <td>{canBind?<input className="fv-input" value={draft[key(g)]?.fields||''} onChange={e=>setDraft(d=>({...d,[key(g)]:{...d[key(g)],fields:e.target.value}}))} aria-label={`${g.group_name} fields of education`} disabled={busy}/>:(draft[key(g)]?.fields||'—')}</td>
        <td>{canBind?<input className="fv-input" value={draft[key(g)]?.title_regex||''} onChange={e=>setDraft(d=>({...d,[key(g)]:{...d[key(g)],title_regex:e.target.value}}))} aria-label={`${g.group_name} title pattern`} disabled={busy}/>:(draft[key(g)]?.title_regex||'—')}</td></tr>)}</tbody></table></div>
    {canBind?<div className="sd-actions"><input className="fv-input" placeholder="Reason (kept in the log)" value={reason} onChange={e=>setReason(e.target.value)} aria-label="Reason for the binding" disabled={busy}/>
      <Button compact variant="primary" onClick={save} disabled={busy||reason.trim().length<4}><Save size={13}/>Save binding</Button></div>
      :<p className="sd-desc">A Platform Admin binds the groups.</p>}
    {msg&&<p className="sd-desc" role="status" data-groups-saved>{msg}</p>}
  </div>
}

// "No rule yet": every provider by stage, with the reason, the pages tried and the next try; Run now is the existing policy-add-tests job.
export function EnglishStatus({can}){
  const[d,setD]=useState(null),[err,setErr]=useState(''),[stage,setStage]=useState(''),[busy,setBusy]=useState(false)
  const load=()=>{setErr('');supabase.rpc('admin_provider_english_status_read',{p_provider:null,p_stage:stage||null,p_limit:200}).then(({data,error})=>error?setErr(errText(error)):setD(data))}
  useEffect(load,[stage])
  const run=async()=>{if(!window.confirm('Run "policy-add-tests" now? It reads stored English pages again once, in addition to its schedule. No page is fetched and no credits are used.'))return
    setBusy(true);try{const{error}=await supabase.rpc('admin_automation_control',{p_job:'policy-add-tests',p_action:'run_now',p_args:{}});if(error)throw error;load()}catch(e){setErr(errText(e))}finally{setBusy(false)}}
  if(err)return <p className="fr-error" role="alert">{err}</p>
  if(!d)return <Loading label="Loading English status…"/>
  const types=Array.isArray(d.scope?.provider_types)?d.scope.provider_types:[]
  return <div className="pp-status" data-english-status>
    <h3 className="sd-h3">No rule yet</h3>
    <p className="sd-desc">Provider types in scope: {types.includes('*')?'all':types.join(', ')||'none'} · search for providers with no central page: {Number(d.scope?.search_new_providers)===1?'on':'off'} · rows written from course groups: {fmtNumber(d.rows_from_groups||0)}</p>
    <dl className="fs-totals">{Object.entries(d.stages||{}).map(([k,v])=><div key={k}><dt>{STAGE_LABEL[k]||k}</dt><dd>{fmtNumber(v.providers)}</dd></div>)}</dl>
    <div className="fs-bar"><label><small>Stage</small><select className="fv-filter" value={stage} onChange={e=>setStage(e.target.value)} aria-label="Stage">
      <option value="">All</option>{Object.keys(STAGE_LABEL).map(k=><option key={k} value={k}>{STAGE_LABEL[k]}</option>)}</select></label>
      <Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>Refresh</Button>
      {can&&<Button compact onClick={run} disabled={busy}><Play size={14}/>Run now</Button>}</div>
    <div className="cf-table-wrap"><table className="cf-table" data-english-status-rows><thead><tr><th>Provider</th><th>Stage</th><th>Why</th><th>Courses without English</th><th>Next try</th></tr></thead>
      <tbody>{(d.rows||[]).map(r=><tr key={r.provider_id} data-stage={r.stage}><td>{r.provider}<div className="sd-desc">{r.country} · {r.provider_type}</div></td><td>{STAGE_LABEL[r.stage]||r.stage}</td><td>{r.why}</td>
        <td>{fmtNumber(r.missing_courses||0)}</td><td>{r.next_try||'—'}</td></tr>)}</tbody></table></div>
    <div className="sd-desc" data-english-jobs>{(d.jobs||[]).map(j=><span key={j.job}>{j.job} ({j.schedule}{j.active?'':', paused'}{j.last_run?`, last ${fmtDateTime(j.last_run.at)}: ${j.last_run.status}`:''}) · </span>)}</div>
  </div>
}
