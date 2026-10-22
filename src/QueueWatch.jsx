// Platform health › Work queues (v2.15.319, Platform Admin 22 Oct 2026 19:42/19:53): the progress watchdog.
// "I wanted the platform to self maintain work job or queue until it completes the data enrichment or notify when it runs out of
// toolset or get stuck." Every 15 minutes (job queue-watch) each enrichment queue gets one state; Stuck and Out of toolset are sent
// to the Platform Admin's phone and email; Done and Nothing left to try go in the daily report; items that gave up on a passing
// error get one more try by themselves (logged below). Server: public.admin_queue_watch('list' | 'report' | 'run').
import React,{useEffect,useMemo,useState}from'react'
import{Activity,AlertTriangle,Bell,CheckCircle2,RefreshCw,Wrench}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,Metric,SectionTitle,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'
import Stats15m from'./Stats15m'

export const QUEUE_STATES={
  moving:{label:'Moving',tone:'success',help:'Work is waiting and items are finishing.'},
  waiting:{label:'Waiting for budget',tone:'info',help:'Today\'s budget for one of its tools is used up; it carries on by itself when the budget comes back.'},
  stuck:{label:'Stuck',tone:'danger',help:'Work is waiting but nothing has finished for a while. Sent to phone and email.'},
  failing:{label:'Failing',tone:'warning',help:'Most of what it tried in the last hour failed.'},
  out_of_toolset:{label:'Out of toolset',tone:'danger',help:'Work is waiting but a tool it needs cannot be used until a person acts (credit or balance used up). Sent to phone and email.'},
  nothing_left:{label:'Nothing left to try',tone:'neutral',help:'Nothing is waiting; some items have had every tool tried and need a person or a new tool. In the daily report.'},
  done:{label:'Done',tone:'success',help:'Nothing is waiting and nothing is left over. In the daily report.'},
  paused:{label:'Paused',tone:'neutral',help:'Its jobs were switched off by a person.'},
}
const ORDER=['out_of_toolset','stuck','failing','waiting','moving','nothing_left','done','paused']
export const stateOf=s=>QUEUE_STATES[s]||{label:s||'Not checked yet',tone:'neutral',help:''}
const errText=e=>e?.message||String(e)
const hours=h=>h==null?'—':h<1?`${Math.max(1,Math.round(h*60))} min`:h<48?`${fmtNumber(Math.round(h*10)/10)} h`:`${fmtNumber(Math.round(h/24))} days`

export default function QueueWatch({onError}){
  const[d,setD]=useState(null),[busy,setBusy]=useState(false),[msg,setMsg]=useState('')
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_queue_watch',{p_action:'list',p_args:{}});if(error)throw error;setD(data||{})}catch(e){onError?.(errText(e));setD({queues:[]})}}
  useEffect(()=>{load()},[])
  const run=async()=>{setBusy(true);setMsg('');try{const{data,error}=await supabase.rpc('admin_queue_watch',{p_action:'run',p_args:{reason:'Platform health › Work queues: Check now'}});if(error)throw error;setMsg(`Checked ${fmtNumber((data?.queues||[]).length)} queues · ${fmtNumber(data?.changes||0)} changed · ${fmtNumber(data?.fixed||0)} items given one more try`);await load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const queues=useMemo(()=>[...(d?.queues||[])].sort((a,b)=>ORDER.indexOf(a.state)-ORDER.indexOf(b.state)),[d])
  const count=k=>queues.filter(q=>q.state===k).length
  if(!d)return <section className="m-panel"><Loading label="Reading the work queues…"/></section>
  const needs=count('stuck')+count('out_of_toolset')
  return <>
    <Stats15m onError={onError}/>
    <section className="m-panel">
      <SectionTitle icon={Activity} title="Work queues" subtitle={`Checked every 15 minutes. Stuck means work is waiting and nothing finished in ${fmtNumber(d.settings?.stuck_minutes||120)} minutes. Stuck and Out of toolset are sent to phone and email; Done and Nothing left to try go in the daily report.`}
        action={d.can_run&&<Button compact onClick={run} disabled={busy} data-queue-run><RefreshCw size={14}/>{busy?'Checking…':'Check now'}</Button>}/>
      {msg&&<p className="qw-msg" role="status">{msg}</p>}
      <div className="cf-metric-grid">
        <Metric label="Need a person" value={needs} icon={AlertTriangle} tone={needs?'danger':'neutral'} detail="Stuck or out of toolset"/>
        <Metric label="Moving" value={count('moving')+count('waiting')} icon={Activity} tone="success" detail={count('waiting')?`${count('waiting')} waiting for today's budget`:'Finishing items'}/>
        <Metric label="Failing" value={count('failing')} icon={AlertTriangle} tone={count('failing')?'warning':'neutral'} detail="Most tries failed in the last hour"/>
        <Metric label="Done or nothing left" value={count('done')+count('nothing_left')} icon={CheckCircle2} tone="neutral" detail="In the daily report"/>
      </div>
    </section>
    <section className="m-panel">
      <div className="cf-table-wrap"><table className="cf-table qw-table"><thead><tr><th>Queue</th><th>State</th><th className="num">Waiting</th><th className="num">Finished / hour</th><th>Time to finish</th><th className="num">Nothing left to try</th><th>Last finished</th></tr></thead><tbody>
        {queues.length?queues.map(q=>{const st=stateOf(q.state);return <tr key={q.key} data-queue={q.key}>
          <td><strong>{q.label}</strong><small className="qw-sub">{q.area} · {q.purpose}</small></td>
          <td><StatusChip value={q.state} tone={st.tone} label={st.label} title={st.help}/>{q.reason&&<small className="qw-sub">{q.reason}</small>}
            {(q.tools_out||[]).length>0&&<small className="qw-sub">Tool out: {q.tools_out.join(', ')}</small>}
            {(q.tools_waiting||[]).length>0&&<small className="qw-sub">Budget used today: {q.tools_waiting.join(', ')}</small>}
            {q.since&&<small className="qw-sub">Since {fmtDateTime(q.since)}</small>}
            {q.fix_at&&['stuck','failing','out_of_toolset','nothing_left'].includes(q.state)&&<a className="ph-fix" href={q.fix_at}>Go to the screen</a>}</td>
          <td className="num">{q.pending==null?'—':fmtNumber(q.pending)}</td>
          <td className="num">{q.per_hour==null?'—':fmtNumber(q.per_hour)}{Number(q.failed_window||0)>0&&<small className="qw-sub">{fmtNumber(q.failed_window)} failed in the hour</small>}</td>
          <td>{q.state==='moving'?hours(q.eta_hours):'—'}</td>
          <td className="num" title={q.nothing_left_is||''}>{Number(q.exhausted||0)?fmtNumber(q.exhausted):'—'}{Number(q.exhausted||0)>0&&q.nothing_left_is&&<small className="qw-sub">{q.nothing_left_is}</small>}</td>
          <td>{q.last_progress?fmtDateTime(q.last_progress):'—'}</td>
        </tr>}):<tr><td colSpan={7} className="cf-empty-cell">The watchdog has not run yet.</td></tr>}
      </tbody></table></div>
    </section>
    <div className="qw-grid">
      <section className="m-panel">
        <SectionTitle icon={Wrench} title="Fixed by itself" subtitle="Items that gave up on a passing error (time-out, busy server, cut-off AI answer) got one more try. Never course data, never while a tool is out."/>
        {(d.fixes||[]).length?<ul className="qw-list">{d.fixes.map(f=><li key={f.id}><strong>{fmtNumber(f.items)}</strong> · {queueLabel(queues,f.key)}<small>{f.detail?.what} · {fmtDateTime(f.at)}</small></li>)}</ul>:<Empty icon={CheckCircle2} text="Nothing needed fixing yet."/>}
      </section>
      <section className="m-panel">
        <SectionTitle icon={Bell} title="Alerts" subtitle="Phone and email for Stuck and Out of toolset; the rest in the daily report."/>
        {(d.alerts||[]).length?<ul className="qw-list">{d.alerts.map(a=><li key={a.id}><StatusChip value={a.state} tone={stateOf(a.state).tone} label={a.channel==='notify'?'Phone and email':'Daily report'}/> <strong>{a.title}</strong><small>{a.body} · raised {fmtDateTime(a.raised_at)} · {a.sent_at?`sent ${fmtDateTime(a.sent_at)}`:'not sent yet'}</small></li>)}</ul>:<Empty icon={CheckCircle2} text="No alerts."/>}
      </section>
    </div>
    <section className="m-panel">
      <SectionTitle title="Changes" subtitle="Each time a queue changed state, newest first."/>
      {(d.events||[]).length?<div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>When</th><th>Queue</th><th>From</th><th>To</th><th>Why</th></tr></thead><tbody>
        {d.events.map(e=><tr key={e.id}><td>{fmtDateTime(e.at)}</td><td>{queueLabel(queues,e.key)}</td><td>{e.from_state?stateOf(e.from_state).label:'—'}</td><td><StatusChip value={e.to_state} tone={stateOf(e.to_state).tone} label={stateOf(e.to_state).label}/></td><td>{e.reason||'—'}</td></tr>)}
      </tbody></table></div>:<Empty text="No changes yet."/>}
    </section>
  </>
}
function queueLabel(qs,k){return qs.find(q=>q.key===k)?.label||k}
