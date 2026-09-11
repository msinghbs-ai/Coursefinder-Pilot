import React,{useEffect,useMemo,useRef,useState}from'react'
import{createRoot}from'react-dom/client'
import{Play,SearchCheck,Workflow,ExternalLink}from'lucide-react'
import{supabase,api}from'./lib/supabase'
import'./scheduler-workflow-builder.css'

const WORKFLOW_KEY='course_facts_l2'
const AU='AU'

function OptionSelect({label,value,onChange,items,disabled=false}){return <label className="cf-workflow-builder__field"><span>{label}</span><select value={value} disabled={disabled} onChange={e=>onChange(e.target.value)}><option value="">Select…</option>{items.map(x=><option key={x.value} value={x.value}>{x.label}{x.meta?` — ${x.meta}`:''}</option>)}</select></label>}

function Builder(){
 const[scopeType,setScopeType]=useState('country'),[scopeId,setScopeId]=useState(''),[states,setStates]=useState([]),[universities,setUniversities]=useState([]),[universityQuery,setUniversityQuery]=useState(''),[preview,setPreview]=useState(null),[mode,setMode]=useState('acquisition_only'),[reason,setReason]=useState(''),[previewBusy,setPreviewBusy]=useState(false),[dispatchBusy,setDispatchBusy]=useState(false),[rank,setRank]=useState(0),[contextLoaded,setContextLoaded]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState('')
 const optionGeneration=useRef(0),previewGeneration=useRef(0)
 const needsTarget=scopeType!=='country'
 const operator=contextLoaded&&rank>=4
 const locked=dispatchBusy||!operator
 const canPreview=operator&&!previewBusy&&!dispatchBusy&&(!needsTarget||Boolean(scopeId))
 const modes=useMemo(()=>Array.isArray(preview?.processing_modes)?preview.processing_modes:[],[preview])
 const canRun=operator&&Boolean(preview?.preview_token)&&preview?.executable===true&&!previewBusy&&!dispatchBusy&&mode==='acquisition_only'

 const invalidatePreview=()=>{previewGeneration.current+=1;setPreview(null);setMessage('');setPreviewBusy(false)}
 useEffect(()=>{let live=true;api.context().then(context=>{if(!live)return;setRank(Number(context?.role_rank||0));setContextLoaded(true)}).catch(e=>{if(!live)return;setError(e?.message||String(e));setContextLoaded(true)});return()=>{live=false}},[])
 useEffect(()=>{setScopeId('');setError('');invalidatePreview()},[scopeType])
 useEffect(()=>{invalidatePreview()},[scopeId])
 useEffect(()=>{if(scopeType!=='state')return;const generation=++optionGeneration.current;supabase.rpc('scheduler_workflow_scope_options_v1',{p_country_code:AU,p_kind:'state',p_state_id:null,p_query:null,p_limit:10,p_offset:0}).then(({data,error})=>{if(generation!==optionGeneration.current)return;if(error)setError(error.message);else setStates(Array.isArray(data?.items)?data.items:[])});return()=>{optionGeneration.current+=1}},[scopeType])
 useEffect(()=>{if(scopeType!=='university')return;const generation=++optionGeneration.current;const timer=setTimeout(()=>{supabase.rpc('scheduler_workflow_scope_options_v1',{p_country_code:AU,p_kind:'university',p_state_id:null,p_query:universityQuery||null,p_limit:10,p_offset:0}).then(({data,error})=>{if(generation!==optionGeneration.current)return;if(error)setError(error.message);else setUniversities(Array.isArray(data?.items)?data.items:[])})},200);return()=>{clearTimeout(timer);optionGeneration.current+=1}},[scopeType,universityQuery])

 async function doPreview(){if(!operator)return;const generation=++previewGeneration.current;setPreviewBusy(true);setError('');setMessage('');try{const{data,error}=await supabase.rpc('scheduler_workflow_preview_v1',{p_workflow_key:WORKFLOW_KEY,p_country_code:AU,p_scope_type:scopeType,p_scope_id:needsTarget?scopeId:null});if(generation!==previewGeneration.current)return;if(error)throw error;setPreview(data);setMode('acquisition_only')}catch(e){if(generation!==previewGeneration.current)return;setPreview(null);setError(e?.message||String(e))}finally{if(generation===previewGeneration.current)setPreviewBusy(false)}}
 async function run(){if(!operator)return;if(reason.trim().length<5){setError('A governance reason of at least 5 characters is required.');return}if(!preview?.preview_token){setError('Preview the governed scope before running it.');return}if(preview?.executable!==true){setError(preview?.execution_block_reason||'The previewed scope has no executable Layer 2 work.');return}setDispatchBusy(true);setError('');setMessage('');try{const{data,error}=await supabase.rpc('scheduler_workflow_run_now_v2',{p_preview_token:preview.preview_token,p_workflow_key:WORKFLOW_KEY,p_country_code:AU,p_scope_type:scopeType,p_scope_id:needsTarget?scopeId:null,p_processing_mode:mode,p_reason:reason.trim()});if(error)throw error;const replay=data?.idempotent_replay||data?.existing_recent_dispatch;setMessage(`${replay?'Existing recent governed dispatch reused':'Governed Layer 2 dispatch accepted'}. Preview receipt ${data?.preview_token||preview.preview_token}. Follow Jobs/Evidence for underlying work status.`);setPreview(null);setReason('')}catch(e){setError(e?.message||String(e))}finally{setDispatchBusy(false)}}
 const changeUniversityQuery=value=>{if(dispatchBusy)return;setUniversityQuery(value);if(scopeId)setScopeId('')}

 return <section className="m23-panel cf-workflow-builder" data-cf-workflow-builder="true">
  <div className="cf-workflow-builder__head"><div><span className="m-eyebrow">CF-093 · Target builder</span><h3>New governed run</h3><p>Build a new server-authorised Layer 2 Course Facts run. Unsupported layers, modes and recurring scopes stay unavailable rather than being simulated in the browser.</p></div><Workflow size={22}/></div>
  {contextLoaded&&!operator&&<div className="cf-workflow-builder__notice">Read-only. Pipeline Operator rank 4 or higher is required to preview or dispatch a new governed run.</div>}
  {error&&<div className="cf-workflow-builder__notice" data-error="true">{error}</div>}{message&&<div className="cf-workflow-builder__notice">{message}</div>}
  <div className="cf-workflow-builder__grid">
   <label className="cf-workflow-builder__field"><span>Job / Dataset</span><select value={WORKFLOW_KEY} disabled><option value={WORKFLOW_KEY}>Course Facts enrichment · Layer 2</option></select></label>
   <label className="cf-workflow-builder__field"><span>Country</span><select value={AU} disabled><option value={AU}>Australia</option></select><small>NZ first-party Course enrichment remains deferred.</small></label>
   <label className="cf-workflow-builder__field"><span>Scope type</span><select value={scopeType} disabled={locked} onChange={e=>setScopeType(e.target.value)}><option value="country">Country</option><option value="state">State / territory</option><option value="university">University / provider</option></select></label>
   {scopeType==='state'&&<OptionSelect label="State / territory" value={scopeId} onChange={setScopeId} items={states} disabled={locked}/>} 
   {scopeType==='university'&&<div className="cf-workflow-builder__target-search"><label className="cf-workflow-builder__field"><span>Find university / provider</span><div className="cf-workflow-builder__search"><SearchCheck size={15}/><input value={universityQuery} disabled={locked} onChange={e=>changeUniversityQuery(e.target.value)} placeholder="Search up to 10 server-authorised matches"/></div></label><OptionSelect label="University / provider" value={scopeId} onChange={setScopeId} items={universities} disabled={locked}/></div>}
  </div>
  <div className="cf-workflow-builder__actions"><button disabled={!canPreview} onClick={doPreview}>Preview governed scope</button></div>
  {preview&&<div className="cf-workflow-builder__preview">
    <div className="cf-workflow-builder__metrics"><article><strong>{preview.university_count??0}</strong><span>Universities</span></article><article><strong>{preview.catalogue_count??0}</strong><span>Courses in scope</span></article><article><strong>{preview.queueable_count??0}</strong><span>Queueable now</span></article><article><strong>{preview.needs_discovery_count??0}</strong><span>Need discovery</span></article><article><strong>{preview.active_run_count??0}</strong><span>Active runs</span></article></div>
    {preview.executable===false&&<div className="cf-workflow-builder__notice" data-error="true">{preview.execution_block_reason||'No executable Layer 2 work is available for this scope.'}</div>}
    {preview.preview_token&&<div className="cf-workflow-builder__schedule"><strong>Server preview receipt</strong><span>Bound to this exact target and valid for up to 15 minutes. Changing scope or target requires a new preview.</span></div>}
    <div className="cf-workflow-builder__modes"><h4>Processing mode</h4>{modes.map(x=><label key={x.key} data-disabled={!x.enabled}><input type="radio" name="cf-workflow-mode" value={x.key} checked={mode===x.key} disabled={!x.enabled||dispatchBusy} onChange={()=>setMode(x.key)}/><span><strong>{x.label}</strong>{x.reason&&<small>{x.reason}</small>}</span></label>)}</div>
    <div className="cf-workflow-builder__schedule"><strong>Schedule</strong><span>{preview.schedule_supported?'This target may be schedule-eligible after a verified single-profile mapping; creation is not enabled in this slice.':preview.schedule_reason}</span></div>
    <label className="cf-workflow-builder__field"><span>Governance reason</span><input value={reason} disabled={dispatchBusy||!operator} onChange={e=>setReason(e.target.value)} placeholder="Required for consequential dispatch"/></label>
    <div className="cf-workflow-builder__actions"><button data-primary disabled={!canRun} onClick={run}><Play size={14}/> Run acquisition + deterministic Layer 2</button><button onClick={()=>{location.hash='#jobs'}}><ExternalLink size={14}/> Open Jobs</button><button onClick={()=>{location.hash='#evidence'}}><ExternalLink size={14}/> Open Evidence</button></div>
   </div>}
  <div className="cf-workflow-builder__guard"><strong>Authority boundary</strong><span>Automatic L2 → conditional L3/L4 and Evidence reprocessing remain disabled here. Layer 3 continues through its Evidence/profile/model-qualified workspace; Search/Publication are downstream governed consequences.</span></div>
 </section>
}

let root=null,mount=null
function reconcile(){
 if(!location.hash.startsWith('#scheduled-tasks')){if(root){root.unmount();root=null}mount?.remove();mount=null;return}
 const workspace=document.querySelector('.cf-scheduler-v2-native');if(!workspace||document.querySelector('[data-cf-workflow-builder-host]'))return
 mount=document.createElement('div');mount.dataset.cfWorkflowBuilderHost='true';const panels=workspace.querySelectorAll(':scope > section');if(panels.length>1)workspace.insertBefore(mount,panels[1]);else workspace.appendChild(mount);root=createRoot(mount);root.render(<Builder/>)
}
let pending=false
function schedule(){if(pending)return;pending=true;setTimeout(()=>{pending=false;reconcile()},40)}
new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true});addEventListener('hashchange',schedule);if(document.readyState==='loading')addEventListener('DOMContentLoaded',schedule,{once:true});else schedule()
