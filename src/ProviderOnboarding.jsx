// Providers › Onboarding (v2.15.253, Platform Admin 12 Oct 2026). Universities without an admitting adapter are onboarded automatically by a
// database job (cron 'provider-onboarding'): website → course pages → 6 sample pages → the AI proposes the adapter → save in testing and apply →
// qualify → attach central pages → find scholarships → stop at Ready to admit. Admitting stays a person's step on Layer 2 › Adapters; nothing here
// admits. Reads: admin_provider_onboarding('read') (Curator and above). Start, stop, retry and settings: the same function (Platform Admin, with a reason).
// Central pages waiting for approval (fee schedules, English policies, academic calendars) can be approved across universities at the bottom.
// v2.15.255: when no field passes, the AI proposes again (an old adapter included; 6 then 10 sample pages); nothing ready after that is
// "Needs a person" (stopped, nothing_ready), not Ready to admit. Each row opens its journey: steps, tasks, AI drafts, qualification and
// the scholarships found with their state (admin_provider_onboarding('journey')). New scholarships are counted live.
// v2.15.258 (Platform Admin bug 12/10-01): moved to Layer 2 › Onboarding, and the journey is seven stages: 1 Provider in (Layer 1 register,
// another database or our search) → 2 Prepare (website, course pages) → 3 Create adapter (the AI builds and tests) → 4 Admit (a person) →
// 5 Enrich courses (the admitted adapter writes its values) → 6 Scholarship adapter (the scholarship search starts only now) →
// 7 Admit scholarships (the AI reads and checks; held pages go to a person) → Done. Each row shows its stage on a stepper; the stage tiles
// filter the list. "Onboard universities not yet queued" adds only those not already in onboarding; the pace and an estimate are shown.
// v2.15.259 (Platform Admin, 12 Oct 2026 17:43: "Auto-admit everything that passes"): Admit can be automatic (a setting, switched with a reason):
// exactly the fields that passed the admit rule are admitted, then the later stages run by themselves. A pilot group (60 AU / 25 NZ / 15 CA)
// is measured hourly against its completeness when picked (Pilot panel; admin_provider_onboarding('pilot')).
// v2.15.260 (Platform Admin, 12 Oct 2026 20:00, "keep moving to the next wave"): Too few course pages and AI allowance used carry on by themselves.
import React,{useEffect,useRef,useState}from'react'
import{ClipboardCheck,Clock3,ExternalLink,Hourglass,ListChecks,OctagonAlert,RefreshCw,Settings2,Sparkles,Workflow,CheckCircle2,Building2,UserRoundCheck,ChevronDown,ChevronRight}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Loading,Metric,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'
import{hrefFor}from'./nav-map'
import FeeSchedules from'./FeeSchedules'
import ProviderPolicies from'./ProviderPolicies'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
export const IN_PROGRESS=['website','course_pages','capturing','proposing','applying','qualifying','scholarships']
export const STEP={queued:['Queued','neutral'],website:['Website','info'],course_pages:['Course pages','info'],capturing:['Capturing samples','info'],proposing:['Proposing','info'],
  applying:['Applying','info'],qualifying:['Qualifying','info'],scholarships:['Scholarships','info'],waiting_admit:['Ready to admit','success'],waiting_courses:['Waiting for courses','warning'],
  stopped:['Stopped','danger'],done:['Done','success'],cancelled:['Cancelled','neutral'],
  // v2.15.258: stages 5 to 7 run under status 'scholarships' with a phase (the journey events record the phase)
  enrich:['Enriching courses','info'],scholarship_search:['Finding scholarships','info'],scholarship_admit:['Admitting scholarships','info']}
// v2.15.258: the seven journey stages (security.provider_onboarding_stage_v1), with what happens in each
export const JOURNEY=[
  ['provider_in','Provider in','In the platform: from the Layer 1 register, another database or our search; queued for onboarding.'],
  ['prepare','Prepare','Website, contacts and central pages found; course pages found and read.'],
  ['create_adapter','Create adapter','The pinned AI proposes the settings from sample pages; saved in testing, applied and qualified.'],
  ['admit','Admit','A Platform Admin admits the fields that pass on Layer 2 › Adapters (or approves central pages).'],
  ['enrich','Enrich courses','The admitted adapter writes its values to the courses, with approved central pages.'],
  ['scholarship_adapter','Scholarship adapter','The scholarship search (map, screen, read) starts only now.'],
  ['admit_scholarships','Admit scholarships','The AI reads and checks each page before publishing; held pages are decided by a person.']]
const STAGE_INDEX=Object.fromEntries(JOURNEY.map(([k],i)=>[k,i]))
// What each stop means and what a person does about it (plain words; the backend note says what happened to this university)
export const STOP={no_website:['No website','Enter the website in the Adapter builder (1.1). Onboarding carries on by itself once a website is recorded, or press Retry.'],
  too_few_pages:['Too few course pages','The next university has started. This one carries on by itself once enough of its pages are read (v2.15.260); or add course pages in the Adapter builder (2.1), then Retry.'],
  ai_allowance:['AI allowance used','The adapter AI allowance for today is used (Adapter builder settings). The next university has started; this one carries on by itself when the allowance renews at midnight, Melbourne time.'],
  capture_failed:['Sample pages not captured','Check the site opens and Firecrawl credits remain (Models & services), then Retry.'],
  proposal_failed:['AI proposal failed','Check the OpenRouter credit and the adapter AI allowance, then Retry; or build the adapter by hand in the Adapter builder.'],
  recipe_off:['Course-page search switched off','A person switched off the course-page search for this website. Check the website in the Adapter builder (1.1); a different website replaces the search. Then Retry.'],
  adapter_off:['Adapter switched off','Someone switched this adapter off. Switch it on in Layer 2 › Adapters if that was a mistake, then Retry.'],
  approve_central:['Approve central pages','The AI read its English language policy or academic calendar. Approve or reject each in the Adapter builder (1.3) or under Approvals waiting below; approved values fill courses that have none. Once they are decided and one is approved, onboarding moves on to Enrich courses.'],
  nothing_ready:['Needs a person','Nothing passed after the AI attempts. Open the Adapter builder: mark the values on the sample pages, or approve its central pages (1.3); then Retry. Admitting by hand also moves it on to Enrich courses.'],
  error:['Unexpected error','Read the note, then Retry. If it stops again, open the Adapter builder.']}
const FIELD={intakes:'Intakes',english:'English',fee:'Fee',delivery:'Delivery'}
const SOURCE={manual:'started by a person',new_provider:'new university',backfill:'without an adapter'}
const origin=r=>`${r.in_register===false?'Added outside the register':r.in_register?'From the Layer 1 register':''}${r.source?`${r.in_register==null?'':' · '}${SOURCE[r.source]||r.source}`:''}`
const FILTERS=[['','All'],['active','In progress'],['stopped','Stopped'],['needs_person','Needs a person'],['waiting_admit','Ready to admit'],['waiting_courses','Waiting for courses'],['queued','Queued'],['done','Done']]
const ORDER=s=>s==='stopped'?0:s==='waiting_admit'?1:2
const needsPerson=r=>r.status==='stopped'&&['nothing_ready','approve_central'].includes(r.stop_reason)
const stepOf=r=>needsPerson(r)?[r.stop_reason==='approve_central'?'Approve central pages':'Needs a person','warning']:(r.status==='scholarships'&&STEP[r.phase])||STEP[r.status]||[r.status,'neutral']
// One row's place in the journey: seven dots, done ones filled, the current one ringed (red when stopped there)
export function Stepper({stage,status}){
  const at=stage==='done'?JOURNEY.length:STAGE_INDEX[stage]??-1
  return <ol className="po-stepper" aria-label={`Stage ${Math.min(at+1,JOURNEY.length)} of ${JOURNEY.length}: ${stage==='done'?'Done':JOURNEY[at]?.[1]||stage}`} data-stage={stage}>
    {JOURNEY.map(([k,l],i)=><li key={k} title={`${i+1}. ${l}`} className={i<at?'is-done':i===at?(status==='stopped'?'is-stopped':'is-now'):''}/>)}</ol>
}
// Hours left at the current pace: universities finished a stage in the last 6 hours, against those still queued
const estimate=(queued,pace)=>{const per=Number(pace?.finished_last_6_hours||0)/6;if(!Number(queued))return'';if(!per)return'No pace yet to estimate from.';const h=Number(queued)/per;return h<48?`About ${Math.ceil(h)} hours for the ${fmtNumber(queued)} queued at this pace.`:`About ${Math.ceil(h/24)} days for the ${fmtNumber(queued)} queued at this pace.`}
const builderHref=id=>hrefFor('layer2','builder',id?{provider:id}:{})

// A Platform Admin action that asks for a reason in place (same pattern as Scholarships › Extraction)
export function ReasonAction({label,confirm='Confirm',variant,disabled,onDo,placeholder='Reason (kept in the log)',testid}){
  const[open,setOpen]=useState(false),[r,setR]=useState(''),[busy,setBusy]=useState(false)
  if(!open)return <Button compact variant={variant} disabled={disabled} onClick={()=>setOpen(true)} data-po-action={testid}>{label}</Button>
  return <span className="po-reason"><input value={r} onChange={e=>setR(e.target.value)} placeholder={placeholder} aria-label={`Reason: ${label}`} autoFocus/>
    <Button compact variant="primary" disabled={busy||r.trim().length<4} onClick={async()=>{setBusy(true);try{await onDo(r.trim());setOpen(false);setR('')}catch{}finally{setBusy(false)}}} data-po-confirm={testid}>{busy?'Working…':confirm}</Button>
    <Button compact onClick={()=>{setOpen(false);setR('')}}>Cancel</Button></span>
}

function Settings({s,actorId,act}){
  const[f,setF]=useState(null)
  const cur={enabled:Boolean(s?.enabled),auto_start_new:Boolean(s?.auto_start_new),auto_admit:Boolean(s?.auto_admit),max_active:Number(s?.max_active??0)}
  const v=f||{...cur,run_as_me:false}
  const set=(k,x)=>setF({...v,[k]:x})
  const changed=Object.fromEntries(Object.entries(v).filter(([k,x])=>k==='run_as_me'?x:x!==cur[k]))
  const okMax=Number.isInteger(v.max_active)&&v.max_active>=0&&v.max_active<=200
  return <details className="m-panel po-settings" data-onboarding-settings><summary><Settings2 size={15}/> Onboarding settings <small className="sd-desc">{cur.enabled?`On · ${fmtNumber(cur.max_active)} at once`:'Off'}{cur.auto_start_new?' · new universities start by themselves':''}{cur.auto_admit?' · Admit automatic':''}</small></summary>
    <div className="po-settings-body">
      <label className="tn-check"><input type="checkbox" checked={v.enabled} onChange={e=>set('enabled',e.target.checked)}/> Onboarding is switched on</label>
      <label className="tn-check" data-onboarding-auto-admit-setting><input type="checkbox" checked={v.auto_admit} onChange={e=>set('auto_admit',e.target.checked)}/> Admit automatically (stage 4): only the fields that pass the admit rule; undo for one university on Layer 2 › Adapters</label>
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

// New scholarships, counted live: found since onboarding started, published, and pages still with the AI
export function Scholarships({r}){
  const s=r.scholarships_live
  if(!s)return r.scholarships==null?<span className="sd-desc">—</span>:<span>{fmtNumber(r.scholarships)}</span>
  if(!s.searched&&!Number(s.found))return <span className="sd-desc" data-sch-live="not-yet">Not searched yet</span>
  return <div className="po-sch" data-sch-live>
    <strong>{fmtNumber(s.found||0)} found</strong>
    {Number(s.published)>0&&<small className="sd-desc po-sub">{fmtNumber(s.published)} published</small>}
    {Number(s.waiting_ai)>0&&<small className="sd-desc po-sub" data-sch-waiting>{fmtNumber(s.waiting_ai)} page{Number(s.waiting_ai)===1?'':'s'} with the AI</small>}
  </div>
}

const TASK={course_page_find:'Course-page search',provider_fill:'Fill in from website',scholarship_provider_scan:'Scholarship search'}
const PUB={published:['Published','success'],unpublished:['Not published','neutral'],withdrawn:['Withdrawn','warning'],held:['Held','warning']}
const VERDICT={scholarship:'scholarship',not_scholarship:'not a scholarship',listing:'listing page',unproven:'not proven',failed:'failed'}
const money=n=>n==null?'':`US$${Number(n).toFixed(4)}`
// One university's journey: every step change, the tasks it ran, the AI drafts, the qualification and the scholarships found
export function Journey({id}){
  const[j,setJ]=useState(null),[fail,setFail]=useState('')
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_provider_onboarding',{p_action:'journey',p_args:{id}});if(error)throw error;setJ(data||{})}catch(e){setFail(errText(e))}}
  useEffect(()=>{load()},[id])
  if(fail)return <p className="fr-error" role="alert">{fail}</p>
  if(!j)return <Loading label="Loading the journey…"/>
  const items=[
    ...(j.events||[]).map(e=>({at:e.at,kind:'step',label:needsPerson(e)?'Needs a person':(STEP[e.status]?.[0]||e.status),text:e.note})),
    ...(j.tasks||[]).map(t=>({at:t.created_at,kind:'task',label:TASK[t.kind]||t.title||t.kind,text:`${t.state}${t.finished_at?` · finished ${fmtDateTime(t.finished_at)}`:''}${t.note?` · ${t.note}`:''}`})),
    ...(j.drafts||[]).map(d=>({at:d.created_at,kind:'ai',label:'AI draft',text:`${fmtNumber(d.samples||0)} sample pages · ${d.status}${d.proposals?` · ${fmtNumber(d.proposals)} proposal${d.proposals===1?'':'s'}`:''}${d.model?` · ${d.model}`:''}${d.cost_usd!=null?` · ${money(d.cost_usd)}`:''}`}))
  ].sort((a,b)=>String(a.at||'').localeCompare(String(b.at||'')))
  const fields=Object.entries(j.qualify?.fields||{}),sch=j.scholarships||[],ai=Object.entries(j.ai_read||{}),en=Object.entries(j.enriched||{}),sa=j.scholarship_admit
  return <div className="po-journey" data-onboarding-journey={id}>
    <div className="po-j-col">
      <h4>Journey</h4>
      {j.stage&&<div className="po-j-stage" data-journey-stage={j.stage}><Stepper stage={j.stage} status={j.status}/><span>{j.stage==='done'?'Done':`Stage ${STAGE_INDEX[j.stage]+1} of ${JOURNEY.length}: ${JOURNEY[STAGE_INDEX[j.stage]]?.[1]||j.stage}`}</span></div>}
      <p className="sd-desc">AI attempts in this onboarding: {fmtNumber(j.ai_attempts||0)} of 2.{j.admitted_at?` Admitted ${fmtDateTime(j.admitted_at)}${j.auto_admitted?` automatically (${(j.auto_admitted.fields||[]).map(f=>FIELD[f]||f).join(', ')})`:''}.`:''}</p>
      {!items.length?<p className="sd-desc">Nothing recorded yet.</p>:<ol className="po-timeline">{items.map((x,i)=><li key={i} className={`po-t-${x.kind}`} data-journey-item={x.kind}>
        <time>{fmtDateTime(x.at)}</time><strong>{x.label}</strong>{x.text&&<span>{x.text}</span>}</li>)}</ol>}
    </div>
    <div className="po-j-col">
      <h4>Qualification</h4>
      {!fields.length?<p className="sd-desc">Not qualified yet.</p>:<table className="cf-table po-q" data-journey-qualify><thead><tr><th>Field</th><th>Read on</th><th>Agrees</th><th>Result</th></tr></thead>
        <tbody>{fields.map(([f,x])=><tr key={f}><td>{FIELD[f]||f}</td><td>{Math.round(Number(x.read_share||0)*100)}%</td><td>{x.agree_share==null?'—':`${Math.round(Number(x.agree_share)*100)}%`}</td>
          <td>{x.pass?<StatusChip value="pass" tone="success" label="Passes"/>:<small className="sd-desc">{x.why}</small>}</td></tr>)}</tbody></table>}
      <h4>Courses enriched</h4>
      <p className="sd-desc" data-journey-enriched>{!j.admitted_at?'After it is admitted.':!j.enriched?'Writing the admitted values to its courses.':en.length?en.map(([f,n])=>`${FIELD[f]||f} on ${fmtNumber(n)} course${Number(n)===1?'':'s'}`).join(', ')+'.':'No value changed (its courses already had them).'}</p>
      <h4>Scholarships</h4>
      {sa&&<p className="sd-desc" data-journey-sch-admit>Finished: {fmtNumber(sa.found||0)} found, {fmtNumber(sa.published||0)} published{Number(sa.waiting_ai)+Number(sa.waiting_person)>0?`; ${fmtNumber(Number(sa.waiting_ai)+Number(sa.waiting_person))} pages still waiting`:''}.</p>}
      <p className="sd-desc" data-journey-ai>{j.scholarship_search?`Search: ${j.scholarship_search.note||'done'}.`:j.phase==='scholarship_search'?'Searching now.':'Not searched yet; the search starts after its courses are enriched.'}{Number(j.ai_waiting)>0?` ${fmtNumber(j.ai_waiting)} page${Number(j.ai_waiting)===1?'':'s'} waiting for the AI.`:''}{ai.length?` AI read so far: ${ai.map(([k,n])=>`${fmtNumber(n)} ${VERDICT[k]||k}`).join(', ')}.`:''}</p>
      {sch.length>0&&<ul className="po-sch-list" data-journey-scholarships>{sch.map(s=>{const[l,t]=PUB[s.publication_status]||[s.publication_status||'—','neutral']
        return <li key={s.id}><StatusChip value={s.publication_status} tone={t} label={l}/> {s.url?<a className="cf-link" href={s.url} target="_blank" rel="noreferrer">{s.name}</a>:s.name}</li>})}</ul>}
    </div>
  </div>
}

// v2.15.266: the Pilot panel is retired (Coverage & completeness › Progress shows the pilot and the top 50 by group).

export default function ProviderOnboarding({rank=0,actorId='',onError}){
  const[d,setD]=useState(null),[status,setStatus]=useState(''),[q,setQ]=useState(''),[query,setQuery]=useState(''),[sel,setSel]=useState(()=>new Set()),[busy,setBusy]=useState(false),[msg,setMsg]=useState(''),[fail,setFail]=useState('')
  const[stage,setStage]=useState(''),[pilot,setPilot]=useState(false)
  const args=useRef({});args.current={...(status?{status:status==='needs_person'?'stopped':status}:{}),...(stage?{stage}:{}),...(pilot?{pilot:true}:{}),...(query?{q:query}:{})}
  const[open,setOpen]=useState(()=>new Set())
  const flip=id=>setOpen(s=>{const n=new Set(s);n.has(id)?n.delete(id):n.add(id);return n})
  const shape=x=>x&&!Array.isArray(x)&&typeof x==='object'?x:{rows:[],counts:{},stops:{}}
  const load=async()=>{setBusy(true);try{const{data,error}=await supabase.rpc('admin_provider_onboarding',{p_action:'read',p_args:args.current});if(error)throw error;setD(shape(data))}catch(e){setFail(errText(e));onError?.(errText(e))}finally{setBusy(false)}}
  const act=async(action,a,done)=>{setFail('');setMsg('');try{const{data,error}=await supabase.rpc('admin_provider_onboarding',{p_action:action,p_args:a});if(error)throw error;setSel(new Set());if(done)setMsg(done);await load()}catch(e){setFail(errText(e));throw e}}
  useEffect(()=>{const t=setTimeout(()=>setQuery(q.trim()),350);return()=>clearTimeout(t)},[q])
  useEffect(()=>{setSel(new Set());load()},[status,stage,pilot,query])
  const counts=d?.counts||{},active=IN_PROGRESS.reduce((n,k)=>n+Number(counts[k]||0),0)
  // refresh every 30 seconds while anything is in progress
  useEffect(()=>{if(!active)return;const t=setInterval(load,30000);return()=>clearInterval(t)},[active,status,stage,query])
  if(!d)return fail?<p className="fr-error" role="alert">{fail}</p>:<Loading label="Loading onboarding…"/>
  const can=Boolean(d.can_manage)
  const auto=Boolean(d.settings?.auto_admit)
  const rows=[...(d.rows||[])].filter(r=>status==='needs_person'?needsPerson(r):status==='stopped'?!needsPerson(r):true).sort((a,b)=>ORDER(a.status)-ORDER(b.status)||String(b.updated_at||'').localeCompare(String(a.updated_at||'')))
  const picked=rows.filter(r=>sel.has(r.id)),stoppedPicked=picked.filter(r=>r.status==='stopped'),stoppable=picked.filter(r=>!['done','cancelled'].includes(r.status))
  const toggle=id=>setSel(s=>{const n=new Set(s);n.has(id)?n.delete(id):n.add(id);return n})
  const tickable=rows.filter(r=>!['done','cancelled'].includes(r.status)),allPicked=tickable.length>0&&tickable.every(r=>sel.has(r.id))
  const central=Number(d.stops?.approve_central||0),stops=Object.entries(d.stops||{}).filter(([k,n])=>Number(n)&&!['nothing_ready','approve_central'].includes(k)),needs=Number(d.stops?.nothing_ready||0)+central,stoppedN=Math.max(Number(counts.stopped||0)-needs,0)
  // a tile with a filter shows those rows when pressed (pressed again: all rows)
  const tile=(key,label,value,detail,icon,tone,filter)=>{const m=<Metric label={label} value={fmtNumber(value||0)} detail={detail} icon={icon} tone={tone}/>
    return filter===undefined?<div key={key} className="po-tile" data-onboarding-tile={key}>{m}</div>
      :<button type="button" key={key} className={`db-tile po-tile${status===filter?' is-on':''}`} data-onboarding-tile={key} onClick={()=>{setStage('');setStatus(status===filter?'':filter)}} aria-pressed={status===filter}>{m}</button>}
  return <div className="m-page-stack po" data-provider-onboarding>
    <p className="sd-desc po-lead">Universities without an admitting adapter are onboarded automatically in seven stages. {auto?<>Admit is <strong>automatic</strong>: the fields that pass the admit rule are admitted by themselves (undo for one university on <a className="cf-link" href={hrefFor('layer2','adapters')}>Layer 2 › Adapters</a>)</>:<>Admitting is a person's step on <a className="cf-link" href={hrefFor('layer2','adapters')}>Layer 2 › Adapters</a></>}; once admitted, its courses are enriched and only then are its scholarships found and checked.</p>
    {auto&&<p className="sd-desc po-auto" data-onboarding-auto-admit>Admit automatically has been on since {fmtDateTime(d.settings?.auto_admit_at)}{d.settings?.auto_admit_reason?`: ${d.settings.auto_admit_reason}`:''}. Universities where nothing passed still need a person.</p>}
    {/* v2.15.266 (Platform Admin, 13 Oct 2026): the Pilot panel is retired; the pilot and the top 50 are followed on Coverage & completeness › Progress */}
    <p className="sd-desc" data-onboarding-progress-link>Follow the pilot and the top 50 Australian universities, stage by stage and hour by hour, on <a className="cf-link" href={hrefFor('coverage','progress',{group:'pilot'})}>Coverage &amp; completeness › Progress</a>.</p>
    <section className="m-panel po-stages" data-onboarding-stages aria-label="Journey stages">
      <ol className="po-stage-strip">{[...JOURNEY,['done','Done','Every stage finished.']].map(([k,l,what],i)=>{const n=Number(d.stages?.[k]||0)
        return <li key={k}><button type="button" className={`po-stage${stage===k?' is-on':''}`} aria-pressed={stage===k} onClick={()=>{setStatus('');setStage(stage===k?'':k)}} data-onboarding-stage={k} title={what}>
          <small>{k==='done'?'':`${i+1}. `}{l}{k==='admit'&&auto?' (automatic)':''}</small><strong>{fmtNumber(n)}</strong></button></li>})}</ol>
      <p className="sd-desc" data-onboarding-pace>{d.pace?`Pace: ${fmtNumber(d.pace.finished_last_hour||0)} universities finished a stage in the last hour (${fmtNumber(d.pace.finished_last_6_hours||0)} in 6 hours), up to ${fmtNumber(d.settings?.max_active||0)} at once. `:''}{estimate(counts.queued,d.pace)}{stage?<> Showing stage: <strong>{JOURNEY.find(x=>x[0]===stage)?.[1]||'Done'}</strong>. <button type="button" className="cf-link po-clear" onClick={()=>setStage('')}>Show all</button></>:''}</p>
    </section>
    <div className="cf-metric-grid po-tiles">
      {tile('queued','Waiting (queued)',counts.queued,d.settings?.enabled===false?'Onboarding is switched off':`Up to ${fmtNumber(d.settings?.max_active||0)} run at once`,Clock3,'neutral','queued')}
      {tile('active','In progress',active,'Prepare to scholarships (stages 2 to 7)',Workflow,'info','active')}
      {tile('stopped','Stopped',stoppedN,stops.length?stops.map(([k,n])=>`${STOP[k]?.[0]||k}: ${fmtNumber(n)}`).join(' · '):'Nothing stopped',OctagonAlert,stoppedN?'danger':'success','stopped')}
      {tile('needs_person','Needs a person',needs,central?`${fmtNumber(central)} with central pages to approve`:'Nothing passed after 2 AI attempts',UserRoundCheck,needs?'warning':'neutral','needs_person')}
      {tile('waiting_admit','Ready to admit',counts.waiting_admit,'A person admits on Layer 2 › Adapters',ListChecks,Number(counts.waiting_admit)?'warning':'neutral','waiting_admit')}
      {tile('done','Done',counts.done,'Admitted, enriched and scholarships checked',CheckCircle2,'success','done')}
      {tile('without','Still without an adapter',d.without_adapter,'Active universities with courses',Building2,'neutral')}
      <a className="db-tile po-tile" data-onboarding-tile="approvals" href={builderHref()}><Metric label="Approvals waiting" value={fmtNumber(d.approvals_waiting||0)} detail="Central pages · open the Adapter builder" icon={Hourglass} tone={Number(d.approvals_waiting)?'warning':'neutral'}/></a>
    </div>

    <section className="m-panel" data-onboarding-list>
      <div className="fs-bar po-bar">
        <div className="pp-kind" role="group" aria-label="Show">{FILTERS.map(([k,l])=><Button key={k||'all'} compact variant={status===k?'primary':undefined} aria-pressed={status===k} onClick={()=>{setStage('');setStatus(k)}} data-onboarding-filter={k||'all'}>{l}</Button>)}</div>
        <input type="search" className="po-search" aria-label="Find a university" placeholder="Find a university" value={q} onChange={e=>setQ(e.target.value)}/>
        <Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>Refresh</Button>
        {active>0&&<small className="sd-desc" data-onboarding-auto>Refreshes every 30 seconds while universities are in progress.</small>}
      </div>
      {can&&<div className="sd-actions po-actions" data-onboarding-actions>
        <span className="sd-desc">{fmtNumber(picked.length)} ticked</span>
        <ReasonAction label={`Retry selected (${fmtNumber(stoppedPicked.length)})`} testid="retry" disabled={!stoppedPicked.length} onDo={r=>act('retry',{ids:stoppedPicked.map(x=>x.id),reason:r},`Retrying ${stoppedPicked.length}. They start again at the step that stopped.`)}/>
        <ReasonAction label={`Stop selected (${fmtNumber(stoppable.length)})`} testid="stop" disabled={!stoppable.length} onDo={r=>act('stop',{ids:stoppable.map(x=>x.id),reason:r},`Stopped ${stoppable.length}. Nothing already saved is undone.`)}/>
        {/* v2.15.258: counts only universities not in onboarding yet (the old label counted every university without an adapter) */}
        <ReasonAction label={`Onboard universities not yet queued (${fmtNumber(d.not_queued??0)})`} variant="primary" testid="start-all" disabled={!Number(d.not_queued)} onDo={r=>act('start',{scope:'no_adapter',reason:r},'Queued, largest universities first. Universities already in onboarding are not queued twice.')}/>
        {!Number(d.not_queued)&&<small className="sd-desc" data-onboarding-all-queued>Every university without an adapter is already in onboarding.</small>}
      </div>}
      {msg&&<p role="status" className="sd-desc" data-onboarding-note>{msg}</p>}
      {fail&&<p role="alert" className="fr-error" data-onboarding-fail>{fail}</p>}
      {!rows.length?<p className="sd-desc">{status||stage||query?'No university matches.':'No university is in onboarding.'}</p>:
      <div className="cf-table-wrap"><table className="cf-table po-table" data-onboarding-rows><thead><tr>
        {can&&<th>{tickable.length>0&&<input type="checkbox" aria-label="Tick every row shown" checked={allPicked} onChange={()=>setSel(allPicked?new Set():new Set(tickable.map(r=>r.id)))}/>}</th>}
        <th>University</th><th>Country</th><th>Stage</th><th>Note</th><th>Pages read / courses</th><th>Fields</th><th>New scholarships</th><th>Updated</th></tr></thead>
        <tbody>{rows.map(r=>{const[l,t]=stepOf(r),stop=r.status==='stopped'?STOP[r.stop_reason]:null,isOpen=open.has(r.id)
          return <React.Fragment key={r.id}><tr data-onboarding-row={r.id} data-status={r.status}>
            {can&&<td>{!['done','cancelled'].includes(r.status)&&<input type="checkbox" aria-label={`Tick ${r.name}`} checked={sel.has(r.id)} onChange={()=>toggle(r.id)}/>}</td>}
            <td><a className="cf-link" href={builderHref(r.provider_id)} title="Open in the Adapter builder" data-onboarding-builder>{r.name}</a>{r.website&&<a href={r.website} target="_blank" rel="noreferrer" className="cf-link" aria-label={`Open ${r.name}'s website`}> <ExternalLink size={12}/></a>}
              {(r.source||r.in_register!=null)&&<small className="sd-desc po-sub" data-onboarding-origin>{origin(r)}</small>}
              {r.status!=='queued'&&<button type="button" className="po-j-toggle" aria-expanded={isOpen} onClick={()=>flip(r.id)} data-onboarding-journey-toggle={r.id}>{isOpen?<ChevronDown size={13}/>:<ChevronRight size={13}/>}Journey</button>}</td>
            <td>{r.country||'—'}</td>
            <td>{r.stage&&<Stepper stage={r.stage} status={r.status}/>}<StatusChip value={r.status} tone={t} label={l}/>{stop&&<small className="sd-desc po-sub" data-stop-reason={r.stop_reason}>{stop[0]}</small>}</td>
            <td className="po-note">{r.note||'—'}{stop&&<small className="sd-desc po-sub" data-stop-help>What to do: {stop[1]}</small>}</td>
            <td>{fmtNumber(r.pages_read||0)} / {fmtNumber(r.courses||0)}</td>
            <td><Fields r={r}/>{r.auto_admitted&&<small className="sd-desc po-sub" data-auto-admitted>Admitted automatically: {(r.auto_admitted.fields||[]).map(f=>FIELD[f]||f).join(', ')}</small>}</td>
            <td><Scholarships r={r}/></td>
            <td>{fmtDateTime(r.updated_at)}</td>
          </tr>
          {isOpen&&<tr className="po-journey-row"><td colSpan={can?9:8}><Journey id={r.id}/></td></tr>}</React.Fragment>})}</tbody></table></div>}
      {rows.length>=200&&<small className="sd-desc">The first {fmtNumber(rows.length)} are shown; use the filter or search to narrow.</small>}
    </section>

    {can&&<Settings s={d.settings} actorId={actorId} act={act}/>}
    {rank>=4&&<Approvals count={d.approvals_waiting}/>}
    <p className="sd-desc"><Sparkles size={13}/> Each step uses the same functions and checks as the Adapter builder; a passing check never admits by itself.</p>
  </div>
}
