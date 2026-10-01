// Layer 3 AI validation (v2.15.108): three tabs.
//   Control     per task: running or paused, daily limit, today's spend, and the model cascade in order (cheapest
//               first; a page moves to the next step only when the answer fails the automatic checks). Platform
//               Admins can pause or resume, change the limit, switch a step on or off, reorder, add a qualified
//               model or remove one. Every change is logged.
//   Models      only the models in a cascade or qualified to join one, with their test scores and cost.
//   Work queue  Layer3Work.jsx (v2.15.127): work by task, course-page pattern requests, recent results.
// v2.15.110: each task card can send the items the AI raised for review back to Layer 3 (public.admin_requeue,
// migration 20260930050000_cf247_ui_control_sweep); grouped by reason on Layer 4 Review > Send back to AI.
// Read: public.admin_layer3_control_read(); write: public.admin_layer3_control(action, args) (migration
// 20260930030000_cf247_l3_control_and_requeue).
import React,{useEffect,useState}from'react'
import{ArrowDown,ArrowUp,BrainCircuit,CircleDollarSign,Pause,Play,Plus,RefreshCw,Route,Trash2,Undo2}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,Metric,SectionTitle,StatusChip,fmtDateTime,fmtMoney,fmtNumber}from'./ui-kit'
import Layer3Work from'./Layer3Work'
import{FailedWork}from'./SendBackToAI'

const usd=(v,d=2)=>fmtMoney(Number(v||0),'USD',{decimals:d})
const pct=v=>v==null?'—':`${Number(v).toFixed(1)}%`
const EVENT_LABEL={admin_run_task:'Task paused or resumed',admin_run_all:'All tasks paused or resumed',admin_budget:'Daily limit changed',admin_tier_active:'Step switched on or off',
  admin_tier_move:'Step moved',admin_tier_add:'Model added',admin_tier_remove:'Model removed',cascade_activated:'Cascade switched on',routes_paused_key_limit:'Paused: OpenRouter key limit',
  routes_resumed:'Resumed',requeued_parked:'Parked work sent back to Layer 3',tier_paused_audit:'Step paused by audit',cascade_suspended:'Cascade suspended'}

export default function Layer3Operations({tab='routing',rank,onError}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(false),[failed,setFailed]=useState('')
  const load=async()=>{setBusy(true);setFailed('');try{const{data:d,error}=await supabase.rpc('admin_layer3_control_read');if(error)throw error;setData(d||{})}catch(e){setFailed(e.message||String(e))}finally{setBusy(false)}}
  const act=async(action,args,confirmText)=>{if(confirmText&&!window.confirm(confirmText))return;setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_layer3_control',{p_action:action,p_args:args});if(error)throw error;setData(d||{})}catch(e){onError?.(e.message||String(e))}finally{setBusy(false)}}
  const sendBack=async(field,n,label)=>{if(!window.confirm(`Send the ${label} items the AI raised for review back to Layer 3 to be tried again? Items that differ from a value already held stay with a person.`))return;setBusy(true);try{const{error}=await supabase.rpc('admin_requeue',{p_action:'send_back',p_args:{field}});if(error)throw error}catch(e){onError?.(e.message||String(e))}finally{setBusy(false)}load()}
  useEffect(()=>{if(tab!=='work'&&!data)load()},[tab])
  if(tab==='work')return <Layer3Work rank={rank} onError={onError}/>
  if(!data&&!failed)return <section className="m-panel"><Loading label="Loading Layer 3…"/></section>
  if(failed&&!data)return <section className="m-panel"><Empty text={`Layer 3 could not be loaded: ${failed}`}/><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></section>
  const refresh=<Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Updating…':'Refresh'}</Button>
  return <><Control data={data} act={act} busy={busy} action={refresh} sendBack={sendBack}/><FailedWork onError={e=>onError?.(e)}/></>
}

function Control({data,act,busy,action,sendBack}){
  const tasks=data.tasks||[],can=Boolean(data.can_control)&&!busy,running=tasks.filter(t=>t.running).length
  const spent=tasks.reduce((n,t)=>n+Number(t.spent_today_usd||0),0),limit=tasks.reduce((n,t)=>n+Number(t.daily_usd||0),0)
  return <>
    <div className="cf-metric-grid">
      <Metric label="Tasks running" value={`${running} of ${tasks.length}`} icon={Route} tone={running===tasks.length?'success':'warning'}/>
      <Metric label="Spent today" value={usd(spent)} detail={`Daily limits total ${usd(limit)}`} icon={CircleDollarSign}/>
      <Metric label="OpenRouter credit" value={data.credit?usd(data.credit.remaining_usd):'—'} detail={data.credit?`Checked ${fmtDateTime(data.credit.observed_at)}`:''} icon={BrainCircuit} tone={Number(data.credit?.remaining_usd)<10?'warning':'neutral'}/>
    </div>
    <section className="m-panel">
      <SectionTitle icon={Route} title="How Layer 3 works" subtitle="Each page goes to step 1, the cheapest model. The next step is used only when that answer fails the automatic checks (no exact quote from the page, or a clear value it missed). The last step also spot-checks 5% of cheaper answers." action={<div className="l3c-actions">{action}
        {data.can_control&&<><Button compact onClick={()=>act('run_all',{running:false},'Pause all Layer 3 work?')} disabled={!can||!running}><Pause size={14}/>Pause all</Button>
        <Button compact variant="primary" onClick={()=>act('run_all',{running:true})} disabled={!can||running===tasks.length}><Play size={14}/>Run all</Button></>}</div>}/>
      {!data.can_control&&<p className="l3v-note">You can view Layer 3. Only a Platform Admin can change it.</p>}
    </section>
    {tasks.map(t=><TaskCard key={t.task_class} t={t} can={can} admin={data.can_control} act={act} sendBack={sendBack}/>)}
    <section className="m-panel"><SectionTitle title="Recent changes"/>
      {(data.events||[]).length?<ul className="l3c-events">{data.events.map((e,i)=><li key={i}><span>{fmtDateTime(e.at)}</span><strong>{EVENT_LABEL[e.kind]||e.kind}</strong><small>{[e.detail?.task&&e.detail.task.replace('provider_','').replace('_validation','').replace('current_',''),e.detail?.profile,e.detail?.tier&&`step ${e.detail.tier}`,e.detail?.daily_usd!=null&&usd(e.detail.daily_usd),e.detail?.reason].filter(Boolean).join(' · ')}</small></li>)}</ul>:<Empty text="No changes recorded."/>}
    </section>
  </>
}

const shortModel=m=>{const s=String(m||'').split('/').pop().replace(/-instruct|-a\d+b|-\d{4}$/gi,'').replace(/-/g,' ');return s.replace(/\b(\w)/g,c=>c.toUpperCase())}
const FIELD_OF={provider_intake_validation:'course_intake',provider_english_validation:'course_english',provider_current_tuition_validation:'provider_current_tuition_validation'}

function TaskCard({t,can,admin,act,sendBack}){
  const[limit,setLimit]=useState(String(t.daily_usd??'')),[add,setAdd]=useState('')
  useEffect(()=>setLimit(String(t.daily_usd??'')),[t.daily_usd])
  const tiers=t.tiers||[],active=tiers.filter(x=>x.active).length,l=t.last_24h||{},over=Number(t.daily_usd)>0&&Number(t.spent_today_usd||0)>=Number(t.daily_usd)
  return <section className="m-panel l3c-task">
    <SectionTitle icon={BrainCircuit} title={t.label} subtitle={t.cascade?`Cascade of ${tiers.length} model${tiers.length===1?'':'s'}, cheapest first`:'One model (cascade not set up for this task yet)'}
      action={<div className="l3c-actions"><StatusChip value={t.running?'running':'paused'} tone={t.running?'success':'warning'} label={t.running?'Running':'Paused'}/>
        {admin&&(t.running?<Button compact onClick={()=>act('run_task',{task:t.task_class,running:false},`Pause ${t.label}?`)} disabled={!can}><Pause size={14}/>Pause</Button>
          :<Button compact variant="primary" onClick={()=>act('run_task',{task:t.task_class,running:true})} disabled={!can}><Play size={14}/>Run</Button>)}</div>}/>
    <div className="l3c-facts">
      <div className={over?'l3c-over':''}><small>Spent today</small><strong>{usd(t.spent_today_usd)}</strong><span>{over?<>Daily limit of {usd(t.daily_usd)} reached: <b>stopped for today</b></>:<>of {usd(t.daily_usd)} daily limit</>}</span></div>
      <div><small>Last 24 hours</small><strong>{fmtNumber(l.admitted||0)} admitted</strong><span>{fmtNumber(l.not_stated||0)} not on the page · {fmtNumber(l.to_review||0)} to review · {fmtNumber(l.retrying||0)} retrying</span></div>
      <div><small>Waiting for a person</small><strong>{fmtNumber(t.in_review||0)}</strong><span>in Layer 4 review</span>
        {admin&&FIELD_OF[t.task_class]&&Number(t.in_review)>0&&<Button compact onClick={()=>sendBack(FIELD_OF[t.task_class],Number(t.in_review),t.label)} disabled={!can}><Undo2 size={14}/>Send these back to the AI</Button>}<a className="cf-link l3c-more" href="#layer-4-review?tab=sendback">By reason: Layer 4 › Send back to AI</a></div>
      {admin&&<form className="l3c-limit" onSubmit={e=>{e.preventDefault();act('budget',{task:t.task_class,daily_usd:Number(limit)})}}>
        <label><small>Daily limit (US$)</small><input type="number" min="0" max="100" step="0.5" value={limit} onChange={e=>setLimit(e.target.value)} disabled={!can}/></label>
        <Button compact type="submit" disabled={!can||Number(limit)===Number(t.daily_usd)}>Save</Button></form>}
    </div>
    <div className="cf-table-wrap"><table className="cf-table l3c-tiers"><thead><tr><th>Step</th><th>Model</th><th className="num">Test score</th><th className="num"><span title="Cost per 1,000 pages">Per 1,000 pages</span></th><th className="num"><span title="Settled in the last 24 hours">Settled 24h</span></th><th className="num"><span title="Passed up to the next step in the last 24 hours">Passed up 24h</span></th><th className="num">Spot checks</th><th>State</th>{admin&&t.cascade&&<th>Change</th>}</tr></thead><tbody>
      {tiers.length?tiers.map((x,i)=><tr key={x.profile} className={x.active?'':'l3c-off'}>
        <td><strong>{x.tier}</strong>{x.final&&<span className="l3v-code">last step</span>}</td>
        <td><span className="l3v-model" title={x.model}>{shortModel(x.model)}</span></td>
        <td className="num">{pct(x.test_right_pct)}<span className={`l3v-code ${Number(x.test_wrong)>0?'l3v-bad':''}`}>{fmtNumber(x.test_wrong||0)} wrong</span></td>
        <td className="num">{usd(x.cost_per_1000_usd)}</td>
        <td className="num">{fmtNumber(x.answered_24h||0)}</td>
        <td className="num">{t.cascade?fmtNumber(x.passed_up_24h||0):'—'}</td>
        <td className="num">{x.audits?.checked?`${fmtNumber(x.audits.disagreed)} of ${fmtNumber(x.audits.checked)} differed`:'—'}</td>
        <td><StatusChip value={x.active?'on':'off'} tone={x.active?'success':'neutral'} label={x.active?'On':'Off'}/></td>
        {admin&&t.cascade&&<td><div className="l3c-row-actions">
          <Button compact onClick={()=>act('tier_move',{task:t.task_class,tier:x.tier,direction:'up'})} disabled={!can||i===0} title="Move up" aria-label={`Move ${x.model} up`}><ArrowUp size={14}/></Button>
          <Button compact onClick={()=>act('tier_move',{task:t.task_class,tier:x.tier,direction:'down'})} disabled={!can||i===tiers.length-1} title="Move down" aria-label={`Move ${x.model} down`}><ArrowDown size={14}/></Button>
          <Button compact onClick={()=>act('tier_active',{task:t.task_class,tier:x.tier,active:!x.active},x.active?`Switch off ${x.model} for ${t.label}?`:null)} disabled={!can||(x.active&&active<=1)}>{x.active?'Switch off':'Switch on'}</Button>
          <Button compact variant="danger" onClick={()=>act('tier_remove',{task:t.task_class,tier:x.tier},`Remove ${x.model} from the ${t.label} cascade?`)} disabled={!can||(x.active&&active<=1)} title="Remove" aria-label={`Remove ${x.model}`}><Trash2 size={14}/></Button>
        </div></td>}
      </tr>):<tr><td colSpan={9} className="cf-empty-cell">No model is set up for this task.</td></tr>}
    </tbody></table></div>
    {admin&&t.cascade&&<form className="l3c-add" onSubmit={e=>{e.preventDefault();if(add)act('tier_add',{task:t.task_class,profile:add});setAdd('')}}>
      <label><small>Add a model</small><select value={add} onChange={e=>setAdd(e.target.value)} disabled={!can||!(t.addable||[]).length}>
        <option value="">{(t.addable||[]).length?'Choose a qualified model…':'No other switched-on model has passed the test for this task'}</option>
        {(t.addable||[]).map(m=><option key={m.profile} value={m.profile}>{m.model} — {pct(m.test_right_pct)} right, {usd(m.cost_per_1000_usd)} per 1,000</option>)}
      </select></label><Button compact type="submit" disabled={!can||!add}><Plus size={14}/>Add as last step</Button>
      <span className="l3v-note">Only models that are switched on in <a href="#models-services">Models &amp; services</a> and have at least 80% right and no wrong answers on the test pages can be added.</span></form>}
  </section>
}

