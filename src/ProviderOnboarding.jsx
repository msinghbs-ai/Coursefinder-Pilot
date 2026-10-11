// Providers › Onboarding (v2.15.253, Platform Admin 12 Oct 2026). Universities without an admitting adapter are onboarded automatically by a
// database job (cron 'provider-onboarding'): website → course pages → 6 sample pages → the AI proposes the adapter → save in testing and apply →
// qualify → attach central pages → find scholarships → stop at Ready to admit. Admitting stays a person's step on Layer 2 › Adapters; nothing here
// admits. Reads: admin_provider_onboarding('read') (Curator and above). Start, stop, retry and settings: the same function (Platform Admin, with a reason).
// Central pages waiting for approval (fee schedules, English policies, academic calendars) can be approved across universities at the bottom.
import React,{useEffect,useRef,useState}from'react'
import{ClipboardCheck,Clock3,ExternalLink,Hourglass,ListChecks,OctagonAlert,RefreshCw,Settings2,Sparkles,Workflow,CheckCircle2,Building2}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Loading,Metric,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'
import{hrefFor}from'./nav-map'
import FeeSchedules from'./FeeSchedules'
import ProviderPolicies from'./ProviderPolicies'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
export const IN_PROGRESS=['website','course_pages','capturing','proposing','applying','qualifying','scholarships']
export const STEP={queued:['Queued','neutral'],website:['Website','info'],course_pages:['Course pages','info'],capturing:['Capturing samples','info'],proposing:['Proposing','info'],
  applying:['Applying','info'],qualifying:['Qualifying','info'],scholarships:['Scholarships','info'],waiting_admit:['Ready to admit','success'],waiting_courses:['Waiting for courses','warning'],
  stopped:['Stopped','danger'],done:['Done','success'],cancelled:['Cancelled','neutral']}
// What each stop means and what a person does about it (plain words; the backend note says what happened to this university)
export const STOP={no_website:['No website','Enter the website in the Adapter builder (1.1). Onboarding carries on by itself once a website is recorded, or press Retry.'],
  too_few_pages:['Too few course pages','Find or add course pages in the Adapter builder (2.1), then Retry.'],
  capture_failed:['Sample pages not captured','Check the site opens and Firecrawl credits remain (Models & services), then Retry.'],
  proposal_failed:['AI proposal failed','Check the OpenRouter credit and the adapter AI allowance, then Retry; or build the adapter by hand in the Adapter builder.'],
  adapter_off:['Adapter switched off','Someone switched this adapter off. Switch it on in Layer 2 › Adapters if that was a mistake, then Retry.'],
  error:['Unexpected error','Read the note, then Retry. If it stops again, open the Adapter builder.']}
const FIELD={intakes:'Intakes',english:'English',fee:'Fee',delivery:'Delivery'}
const SOURCE={manual:'started by a person',new_provider:'new university',backfill:'without an adapter'}
const FILTERS=[['','All'],['active','In progress'],['stopped','Stopped'],['waiting_admit','Ready to admit'],['waiting_courses','Waiting for courses'],['queued','Queued'],['done','Done']]
const ORDER=s=>s==='stopped'?0:s==='waiting_admit'?1:2
const builderHref=id=>hrefFor('layer2','builder',id?{provider:id}:{})

// A Platform Admin action that asks for a reason in place (same pattern as Scholarships › Extraction)
function ReasonAction({label,confirm='Confirm',variant,disabled,onDo,placeholder='Reason (kept in the log)',testid}){
  const[open,setOpen]=useState(false),[r,setR]=useState(''),[busy,setBusy]=useState(false)
  if(!open)return <Button compact variant={variant} disabled={disabled} onClick={()=>setOpen(true)} data-po-action={testid}>{label}</Button>
  return <span className="po-reason"><input value={r} onChange={e=>setR(e.target.value)} placeholder={placeholder} aria-label={`Reason: ${label}`} autoFocus/>
    <Button compact variant="primary" disabled={busy||r.trim().length<4} onClick={async()=>{setBusy(true);try{await onDo(r.trim());setOpen(false);setR('')}catch{}finally{setBusy(false)}}} data-po-confirm={testid}>{busy?'Working…':confirm}</Button>
    <Button compact onClick={()=>{setOpen(false);setR('')}}>Cancel</Button></span>
}

function Settings({s,actorId,act}){
  const[f,setF]=useState(null)
  const cur={enabled:Boolean(s?.enabled),auto_start_new:Boolean(s?.auto_start_new),max_active:Number(s?.max_active??0)}
  const v=f||{...cur,run_as_me:false}
  const set=(k,x)=>setF({...v,[k]:x})
  const changed=Object.fromEntries(Object.entries(v).filter(([k,x])=>k==='run_as_me'?x:x!==cur[k]))
  const okMax=Number.isInteger(v.max_active)&&v.max_active>=0&&v.max_active<=200
  return <details className="m-panel po-settings" data-onboarding-settings><summary><Settings2 size={15}/> Onboarding settings <small className="sd-desc">{cur.enabled?`On · ${fmtNumber(cur.max_active)} at once`:'Off'}{cur.auto_start_new?' · new universities start by themselves':''}</small></summary>
    <div className="po-settings-body">
      <label className="tn-check"><input type="checkbox" checked={v.enabled} onChange={e=>set('enabled',e.target.checked)}/> Onboarding is switched on</label>
      <label className="tn-check"><input type="checkbox" checked={v.auto_start_new} onChange={e=>set('auto_start_new',e.target.checked)}/> Start new universities by themselves when they are added</label>
      <label className="po-max">How many at once <input type="number" min="0" max="200" value={Number.isNaN(v.max_active)?'':v.max_active} onChange={e=>set('max_active',e.target.value===''?NaN:Number(e.target.value))} aria-label="How many at once"/> <small className="sd-desc">0 to 200; 0 pauses new starts</small></label>
      <label className="tn-check"><input type="checkbox" checked={v.run_as_me} onChange={e=>set('run_as_me',e.target.checked)}/> Run the steps under my sign-in{s?.run_as?(String(s.run_as)===String(actorId)?' (already mine)':' (now another Platform Admin)'):''}</label>
      <p className="sd-desc">Each step runs under a Platform Admin's sign-in, so the usual checks and logs apply.{s?.changed_at?` Last changed ${fmtDateTime(s.changed_at)}${s.reason?`: ${s.reason}`:''}.`:''}</p>
      <div className="sd-actions"><ReasonAction label="Save settings" variant="primary" testid="settings" disabled={!Object.keys(changed).length||!okMax} onDo={async r=>{await act('settings',{...changed,reason:r},'Onboarding settings saved.');setF(null)}}/>
        {f&&<Button compact onClick={()=>setF(null)}>Undo changes</Button>}</div>
    </div>
  </details>
}

// The country filter narrows both lists, as the retired Layer 4 › Attributes tab did.
const COUNTRIES=[['','All countries'],['AU','Australia'],['NZ','New Zealand'],['CA','Canada']]
function Approvals({count}){
  const[open,setOpen]=useState(false),[country,setCountry]=useState('')
  return <details className="m-panel po-approvals" data-onboarding-approvals onToggle={e=>setOpen(e.currentTarget.open)}>
    <summary><ClipboardCheck size={15}/> Approvals waiting (all universities): {fmtNumber(count||0)}</summary>
    <div className="fs-bar"><p className="sd-desc">Fee schedules, English policies and academic calendars read from each university's central pages. For one university, approve them in the Adapter builder (1.3).</p>
      <label><small>Country</small><select className="fv-filter" aria-label="Approvals country" value={country} onChange={e=>setCountry(e.target.value)}>{COUNTRIES.map(([v,l])=><option key={v} value={v}>{l}</option>)}</select></label></div>
    {open&&<div className="m-page-stack"><FeeSchedules country={country}/><ProviderPolicies country={country}/></div>}
  </details>
}

function Fields({r}){
  const ready=Array.isArray(r.ready)?r.ready:[],held=r.held&&typeof r.held==='object'?Object.entries(r.held):[]
  if(!ready.length&&!held.length)return <span className="sd-desc">—</span>
  return <div className="po-fields">{ready.map(f=><StatusChip key={f} value="ready" tone="success" label={FIELD[f]||f}/>)}
    {held.map(([f,why])=><small key={f} className="po-held" data-held={f}><strong>{FIELD[f]||f}:</strong> {String(why)}</small>)}</div>
}

export default function ProviderOnboarding({rank=0,actorId='',onError}){
  const[d,setD]=useState(null),[status,setStatus]=useState(''),[q,setQ]=useState(''),[query,setQuery]=useState(''),[sel,setSel]=useState(()=>new Set()),[busy,setBusy]=useState(false),[msg,setMsg]=useState(''),[fail,setFail]=useState('')
  const args=useRef({});args.current={...(status?{status}:{}),...(query?{q:query}:{})}
  const shape=x=>x&&!Array.isArray(x)&&typeof x==='object'?x:{rows:[],counts:{},stops:{}}
  const load=async()=>{setBusy(true);try{const{data,error}=await supabase.rpc('admin_provider_onboarding',{p_action:'read',p_args:args.current});if(error)throw error;setD(shape(data))}catch(e){setFail(errText(e));onError?.(errText(e))}finally{setBusy(false)}}
  const act=async(action,a,done)=>{setFail('');setMsg('');try{const{data,error}=await supabase.rpc('admin_provider_onboarding',{p_action:action,p_args:a});if(error)throw error;setSel(new Set());if(done)setMsg(done);await load()}catch(e){setFail(errText(e));throw e}}
  useEffect(()=>{const t=setTimeout(()=>setQuery(q.trim()),350);return()=>clearTimeout(t)},[q])
  useEffect(()=>{setSel(new Set());load()},[status,query])
  const counts=d?.counts||{},active=IN_PROGRESS.reduce((n,k)=>n+Number(counts[k]||0),0)
  // refresh every 30 seconds while anything is in progress
  useEffect(()=>{if(!active)return;const t=setInterval(load,30000);return()=>clearInterval(t)},[active,status,query])
  if(!d)return fail?<p className="fr-error" role="alert">{fail}</p>:<Loading label="Loading onboarding…"/>
  const can=Boolean(d.can_manage)
  const rows=[...(d.rows||[])].sort((a,b)=>ORDER(a.status)-ORDER(b.status)||String(b.updated_at||'').localeCompare(String(a.updated_at||'')))
  const picked=rows.filter(r=>sel.has(r.id)),stoppedPicked=picked.filter(r=>r.status==='stopped'),stoppable=picked.filter(r=>!['done','cancelled'].includes(r.status))
  const toggle=id=>setSel(s=>{const n=new Set(s);n.has(id)?n.delete(id):n.add(id);return n})
  const tickable=rows.filter(r=>!['done','cancelled'].includes(r.status)),allPicked=tickable.length>0&&tickable.every(r=>sel.has(r.id))
  const stops=Object.entries(d.stops||{}).filter(([,n])=>Number(n))
  // a tile with a filter shows those rows when pressed (pressed again: all rows)
  const tile=(key,label,value,detail,icon,tone,filter)=>{const m=<Metric label={label} value={fmtNumber(value||0)} detail={detail} icon={icon} tone={tone}/>
    return filter===undefined?<div key={key} className="po-tile" data-onboarding-tile={key}>{m}</div>
      :<button type="button" key={key} className={`db-tile po-tile${status===filter?' is-on':''}`} data-onboarding-tile={key} onClick={()=>setStatus(status===filter?'':filter)} aria-pressed={status===filter}>{m}</button>}
  return <div className="m-page-stack po" data-provider-onboarding>
    <p className="sd-desc po-lead">Universities without an admitting adapter are onboarded automatically, step by step, up to <strong>Ready to admit</strong>. Admitting stays a person's step on <a className="cf-link" href={hrefFor('layer2','adapters')}>Layer 2 › Adapters</a>.</p>
    <div className="cf-metric-grid po-tiles">
      {tile('queued','Waiting (queued)',counts.queued,d.settings?.enabled===false?'Onboarding is switched off':`Up to ${fmtNumber(d.settings?.max_active||0)} run at once`,Clock3,'neutral','queued')}
      {tile('active','In progress',active,'Website to scholarships',Workflow,'info','active')}
      {tile('stopped','Stopped',counts.stopped,stops.length?stops.map(([k,n])=>`${STOP[k]?.[0]||k}: ${fmtNumber(n)}`).join(' · '):'Nothing stopped',OctagonAlert,Number(counts.stopped)?'danger':'success','stopped')}
      {tile('waiting_admit','Ready to admit',counts.waiting_admit,'A person admits on Layer 2 › Adapters',ListChecks,Number(counts.waiting_admit)?'warning':'neutral','waiting_admit')}
      {tile('done','Done',counts.done,'Admitted',CheckCircle2,'success','done')}
      {tile('without','Still without an adapter',d.without_adapter,'Active universities with courses',Building2,'neutral')}
      <a className="db-tile po-tile" data-onboarding-tile="approvals" href={builderHref()}><Metric label="Approvals waiting" value={fmtNumber(d.approvals_waiting||0)} detail="Central pages · open the Adapter builder" icon={Hourglass} tone={Number(d.approvals_waiting)?'warning':'neutral'}/></a>
    </div>

    <section className="m-panel" data-onboarding-list>
      <div className="fs-bar po-bar">
        <div className="pp-kind" role="group" aria-label="Show">{FILTERS.map(([k,l])=><Button key={k||'all'} compact variant={status===k?'primary':undefined} aria-pressed={status===k} onClick={()=>setStatus(k)} data-onboarding-filter={k||'all'}>{l}</Button>)}</div>
        <input type="search" className="po-search" aria-label="Find a university" placeholder="Find a university" value={q} onChange={e=>setQ(e.target.value)}/>
        <Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>Refresh</Button>
        {active>0&&<small className="sd-desc" data-onboarding-auto>Refreshes every 30 seconds while universities are in progress.</small>}
      </div>
      {can&&<div className="sd-actions po-actions" data-onboarding-actions>
        <span className="sd-desc">{fmtNumber(picked.length)} ticked</span>
        <ReasonAction label={`Retry selected (${fmtNumber(stoppedPicked.length)})`} testid="retry" disabled={!stoppedPicked.length} onDo={r=>act('retry',{ids:stoppedPicked.map(x=>x.id),reason:r},`Retrying ${stoppedPicked.length}. They start again at the step that stopped.`)}/>
        <ReasonAction label={`Stop selected (${fmtNumber(stoppable.length)})`} testid="stop" disabled={!stoppable.length} onDo={r=>act('stop',{ids:stoppable.map(x=>x.id),reason:r},`Stopped ${stoppable.length}. Nothing already saved is undone.`)}/>
        <ReasonAction label={`Onboard all without an adapter (${fmtNumber(d.without_adapter||0)})`} variant="primary" testid="start-all" disabled={!Number(d.without_adapter)} onDo={r=>act('start',{scope:'no_adapter',reason:r},'Queued, largest universities first. Universities already in onboarding are not queued twice.')}/>
      </div>}
      {msg&&<p role="status" className="sd-desc" data-onboarding-note>{msg}</p>}
      {fail&&<p role="alert" className="fr-error" data-onboarding-fail>{fail}</p>}
      {!rows.length?<p className="sd-desc">{status||query?'No university matches.':'No university is in onboarding.'}</p>:
      <div className="cf-table-wrap"><table className="cf-table po-table" data-onboarding-rows><thead><tr>
        {can&&<th>{tickable.length>0&&<input type="checkbox" aria-label="Tick every row shown" checked={allPicked} onChange={()=>setSel(allPicked?new Set():new Set(tickable.map(r=>r.id)))}/>}</th>}
        <th>University</th><th>Country</th><th>Step</th><th>Note</th><th>Pages read / courses</th><th>Fields</th><th>New scholarships</th><th>Updated</th></tr></thead>
        <tbody>{rows.map(r=>{const[l,t]=STEP[r.status]||[r.status,'neutral'],stop=r.status==='stopped'?STOP[r.stop_reason]:null
          return <tr key={r.id} data-onboarding-row={r.id} data-status={r.status}>
            {can&&<td>{!['done','cancelled'].includes(r.status)&&<input type="checkbox" aria-label={`Tick ${r.name}`} checked={sel.has(r.id)} onChange={()=>toggle(r.id)}/>}</td>}
            <td><a className="cf-link" href={builderHref(r.provider_id)} title="Open in the Adapter builder" data-onboarding-builder>{r.name}</a>{r.website&&<a href={r.website} target="_blank" rel="noreferrer" className="cf-link" aria-label={`Open ${r.name}'s website`}> <ExternalLink size={12}/></a>}
              {r.source&&<small className="sd-desc po-sub">{SOURCE[r.source]||r.source}</small>}</td>
            <td>{r.country||'—'}</td>
            <td><StatusChip value={r.status} tone={t} label={l}/>{stop&&<small className="sd-desc po-sub" data-stop-reason={r.stop_reason}>{stop[0]}</small>}</td>
            <td className="po-note">{r.note||'—'}{stop&&<small className="sd-desc po-sub" data-stop-help>What to do: {stop[1]}</small>}</td>
            <td>{fmtNumber(r.pages_read||0)} / {fmtNumber(r.courses||0)}</td>
            <td><Fields r={r}/></td>
            <td>{r.scholarships==null?'—':fmtNumber(r.scholarships)}</td>
            <td>{fmtDateTime(r.updated_at)}</td>
          </tr>})}</tbody></table></div>}
      {rows.length>=200&&<small className="sd-desc">The first {fmtNumber(rows.length)} are shown; use the filter or search to narrow.</small>}
    </section>

    {can&&<Settings s={d.settings} actorId={actorId} act={act}/>}
    {rank>=4&&<Approvals count={d.approvals_waiting}/>}
    <p className="sd-desc"><Sparkles size={13}/> Each step uses the same functions and checks as the Adapter builder; a passing check never admits by itself.</p>
  </div>
}
