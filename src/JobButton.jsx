// CF-247 Decision 254, job system Phase B (Platform Admin 6 Oct 06:59: "mature the pressing button across ui to have same
// experience. That once pressed it updates progress, status updates even when page is refresh and admin action cancellation
// power"). One button for every long-running admin action. Pressing it asks for a reason and starts a task
// (public.admin_jobs 'start'); from then on the button shows the task's progress read from the database every few seconds,
// so a refreshed page finds the same task again by its kind and scope, and offers Cancel. When the task finishes the button
// says so for a moment and goes back to its label. The task's full result is under Scheduled jobs › Jobs.
import React,{useEffect,useRef,useState}from'react'
import{Play,Square,Loader2,CheckCircle2,XCircle}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button}from'./ui-kit'

const errText=e=>e?.message||String(e)
const ask=t=>{const r=window.prompt(`${t}\n\nReason (kept in the log):`);return r&&r.trim().length>=4?r.trim():null}
const pct=p=>{const t=Number(p?.total||0),d=Number(p?.done||0);return t?Math.round(d/t*100):0}

export function useTask({kind,scope}){
  const[task,setTask]=useState(undefined),[err,setErr]=useState('')
  const timer=useRef(null)
  const read=async()=>{try{const{data,error}=await supabase.rpc('admin_jobs',{p_action:'read',p_args:{kind,scope:scope||null,limit:1}});if(error)throw error;setTask(data?.match||null);setErr('');return data?.match||null}catch(e){setErr(errText(e));return null}}
  useEffect(()=>{let stop=false;read();const tick=()=>{if(!stop&&document.visibilityState==='visible')read()};timer.current=setInterval(tick,task?5000:30000);return()=>{stop=true;clearInterval(timer.current)}},[kind,scope,Boolean(task)])
  return{task,err,read}
}

// kind, args, scope: what to start. label: the button's text. question: what the reason prompt asks.
// onStarted(id): optional. disabled: the usual. compact, variant: passed to Button.
export default function JobButton({kind,args,scope,label,question,disabled=false,compact=true,variant='primary',icon:Icon=Play,onStarted,onFinished,className=''}){
  const{task,err,read}=useTask({kind,scope})
  const[busy,setBusy]=useState(false),[note,setNote]=useState(''),[fail,setFail]=useState('')
  const wasLive=useRef(false)
  useEffect(()=>{if(task){wasLive.current=true}else if(wasLive.current){wasLive.current=false;setNote('Finished. The result is under Scheduled jobs › Jobs.');onFinished?.();const t=setTimeout(()=>setNote(''),12000);return()=>clearTimeout(t)}},[task])
  const start=async()=>{const reason=ask(question||`Start "${label}"?`);if(!reason)return;setBusy(true);setFail('');try{const{data,error}=await supabase.rpc('admin_jobs',{p_action:'start',p_args:{kind,args:{...(args||{}),scope:scope||undefined},reason}});if(error)throw error;onStarted?.(data?.id);await read()}catch(e){setFail(errText(e))}finally{setBusy(false)}}
  const cancel=async()=>{if(!task)return;const reason=ask(`Cancel "${task.title}"? Work done so far is kept.`);if(!reason)return;setBusy(true);try{const{error}=await supabase.rpc('admin_jobs',{p_action:'cancel',p_args:{id:task.id,reason}});if(error)throw error;await read()}catch(e){setFail(errText(e))}finally{setBusy(false)}}
  if(task){const v=pct(task.progress);return <span className={`jb jb-live ${className}`} data-job-button={kind} data-job-state={task.state}>
    <span className="jb-progress" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={v} aria-label={`${task.title}: ${v}% done`}><span style={{width:`${v}%`}}/></span>
    <span className="jb-text"><Loader2 size={13} className="jb-spin"/> {task.state==='paused'?'Paused':task.cancel_requested?'Cancelling':task.state==='queued'?'Waiting':'Running'} · {Number(task.progress?.done||0)} of {Number(task.progress?.total||0)}</span>
    <Button compact disabled={busy||task.cancel_requested} onClick={cancel} aria-label={`Cancel ${task.title}`}><Square size={12}/> Cancel</Button>
  </span>}
  return <span className={`jb ${className}`} data-job-button={kind} data-job-state="idle">
    <Button compact={compact} variant={variant} disabled={disabled||busy||task===undefined} onClick={start}><Icon size={13}/> {label}</Button>
    {note&&<small className="jb-note"><CheckCircle2 size={12}/> {note}</small>}
    {(fail||err)&&<small className="jb-note jb-fail"><XCircle size={12}/> {fail||err}</small>}
  </span>
}
