// Send back to AI (v2.15.110): Layer 4 items that the Layer 3 AI raised (a new value, not a difference from a value
// already held), grouped by field and by reason with the amounts taken out. A Platform Admin can send a whole group back
// to Layer 3 to be tried again through the model cascade: the review items are closed as superseded and the pages go
// back into the Layer 3 queue. Items that compare against an existing value, and items raised without the AI, stay with
// a person. Also shows what is waiting in Layer 3 and lets an admin retry Layer 3 work that failed.
// Read: public.admin_requeue_read(); write: public.admin_requeue(action, args)
// (migrations 20260930050000, 20260930051000 and 20260930052000, cf247_ui_control_sweep).
import React,{useEffect,useState}from'react'
import{RefreshCw,RotateCcw,Undo2}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,Metric,SectionTitle,fmtDateTime,fmtNumber}from'./ui-kit'

export const FIELD_LABEL={course_intake:'Intakes',course_english:'English requirements',provider_current_tuition_validation:'Tuition',official_course_url:'Official course page',scope_resolution:'Course scope'}
const TASK_OF={provider_intake_validation:'course_intake',provider_english_validation:'course_english',provider_current_tuition_validation:'provider_current_tuition_validation'}
const reasonText=r=>String(r||'').replaceAll('[amount]','a fee').replaceAll('Layer [n]','Layer 2').replaceAll('[n]','a number')

export default function SendBackToAI({onError}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(false),[failed,setFailed]=useState(''),[done,setDone]=useState('')
  const load=async()=>{setBusy(true);setFailed('');try{const{data:d,error}=await supabase.rpc('admin_requeue_read');if(error)throw error;setData(d||{})}catch(e){setFailed(e.message||String(e))}finally{setBusy(false)}}
  const act=async(action,args,confirmText,label)=>{if(!window.confirm(confirmText))return;setBusy(true);setDone('');try{const{data:d,error}=await supabase.rpc('admin_requeue',{p_action:action,p_args:args});if(error)throw error;setData(d||{});setDone(`${label}: ${fmtNumber(d?.moved||0)} item${Number(d?.moved)===1?'':'s'} moved.`)}catch(e){onError?.(e.message||String(e))}finally{setBusy(false)}}
  useEffect(()=>{load()},[])
  if(!data&&!failed)return <section className="m-panel"><Loading label="Loading…"/></section>
  if(failed&&!data)return <section className="m-panel"><Empty text={`Could not be loaded: ${failed}`}/><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></section>
  const groups=data.groups||[],can=Boolean(data.can_control)&&!busy,fields=[...new Set(groups.map(g=>g.field))]
  const total=groups.reduce((n,g)=>n+Number(g.items||0),0),stays=Object.values(data.stays_with_person||{}).reduce((n,v)=>n+Number(v),0),waiting=data.layer3_waiting||{},failedWork=data.layer3_failed||{}
  return <>
    <div className="cf-metric-grid">
      <Metric label="Raised by the AI, waiting for a person" value={fmtNumber(total)} detail="Can be sent back to Layer 3" icon={Undo2} tone={total?'warning':'success'}/>
      <Metric label="Stays with a person" value={fmtNumber(stays)} detail="Differences from a value already held, or not from the AI" icon={Undo2}/>
      <Metric label="Waiting in Layer 3" value={fmtNumber(Object.values(waiting).reduce((n,v)=>n+Number(v),0))} detail={Object.entries(waiting).map(([k,v])=>`${FIELD_LABEL[TASK_OF[k]]||k} ${fmtNumber(v)}`).join(' · ')} icon={RotateCcw}/>
    </div>
    <section className="m-panel">
      <SectionTitle icon={Undo2} title="Send back to AI" subtitle="Review items the Layer 3 AI could not settle, grouped by reason. Sending a group back closes those review items and puts the pages back in the Layer 3 queue, to go through the model cascade again." action={<Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Updating…':'Refresh'}</Button>}/>
      {!data.can_control&&<p className="l3v-note">You can view this. Only a Platform Admin can send items back.</p>}
      {done&&<p className="sb-done" role="status">{done}</p>}
    </section>
    {fields.map(f=>{const gs=groups.filter(g=>g.field===f),n=gs.reduce((s,g)=>s+Number(g.items||0),0);return <section key={f} className="m-panel sb-field" data-field={f}>
      <SectionTitle title={FIELD_LABEL[f]||f} subtitle={`${fmtNumber(n)} item${n===1?'':'s'} in ${gs.length} group${gs.length===1?'':'s'}`} action={data.can_control&&<Button compact variant="primary" onClick={()=>act('send_back',{field:f},`Send all ${fmtNumber(n)} ${FIELD_LABEL[f]||f} items back to Layer 3?`,`${FIELD_LABEL[f]||f} sent back`)} disabled={!can}><Undo2 size={14}/>Send all {fmtNumber(n)} back</Button>}/>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Reason</th><th className="num">Items</th><th>Oldest</th>{data.can_control&&<th>Action</th>}</tr></thead><tbody>
        {gs.map((g,i)=><tr key={i}><td>{reasonText(g.reason)}</td><td className="num">{fmtNumber(g.items)}</td><td>{fmtDateTime(g.oldest)}</td>
          {data.can_control&&<td><Button compact onClick={()=>act('send_back',{field:f,reason:g.reason},`Send these ${fmtNumber(g.items)} items back to Layer 3?`,'Group sent back')} disabled={!can} aria-label={`Send ${g.items} back`}><Undo2 size={14}/>Send back</Button></td>}</tr>)}
      </tbody></table></div>
    </section>})}
    {!fields.length&&<section className="m-panel"><Empty text="Nothing raised by the AI is waiting for a person."/></section>}
    <section className="m-panel">
      <SectionTitle icon={RotateCcw} title="Layer 3 work that failed" subtitle="Intake and English pages that fail are released and retried automatically. Work that stopped without being released can be retried here."/>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Task</th><th className="num">Failed, not retried</th>{data.can_control&&<th>Action</th>}</tr></thead><tbody>
        {Object.keys(TASK_OF).map(t=><tr key={t}><td>{FIELD_LABEL[TASK_OF[t]]}</td><td className="num">{fmtNumber(failedWork[t]||0)}</td>
          {data.can_control&&<td><Button compact onClick={()=>act('retry_failed',{task:t},`Retry failed ${FIELD_LABEL[TASK_OF[t]]} work?`,'Retry')} disabled={!can||!Number(failedWork[t]||0)}><RotateCcw size={14}/>Retry</Button></td>}</tr>)}
      </tbody></table></div>
    </section>
    {(data.events||[]).length>0&&<section className="m-panel"><SectionTitle title="Recent changes"/>
      <ul className="l3c-events">{data.events.map((e,i)=><li key={i}><span>{fmtDateTime(e.at)}</span><strong>{e.action==='send_back'?'Sent back to Layer 3':'Retried'}</strong><small>{[FIELD_LABEL[e.target]||FIELD_LABEL[TASK_OF[e.target]]||e.target,e.detail?.moved!=null&&`${fmtNumber(e.detail.moved)} items`].filter(Boolean).join(' · ')}</small></li>)}</ul></section>}
  </>
}
