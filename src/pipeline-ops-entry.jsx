import React,{useEffect,useState}from'react'
import{createRoot}from'react-dom/client'
import{
  Activity,AlertTriangle,ArrowLeft,BookOpen,ChevronDown,ChevronRight,Database,
  ExternalLink,FileCheck2,Filter,Layers3,RefreshCw,Search,SearchCheck,ShieldCheck,Workflow,X
}from'lucide-react'
import{adminRead,api,supabase}from'./lib/supabase'
import'./pipeline-ops.css'

const OPS_VERSION='1.0.0'
const OPS_CHANGE='CF-CHG-20260821-016'
const OPS_UAT='M1-PIPELINE-OPS-2026-08-21'
const PAGE_SIZE=50
const LAYERS=['L1','L2','L3','L4']

function PipelineOpsEntry(){
  const[rank,setRank]=useState(0),[open,setOpen]=useState(false),[tab,setTab]=useState('overview')
  useEffect(()=>{
    let mounted=true
    const resolve=async()=>{try{const{data}=await supabase.auth.getSession();if(!data.session){if(mounted)setRank(0);return}const ctx=await api.context();if(mounted)setRank(Number(ctx?.role_rank||0))}catch{if(mounted)setRank(0)}}
    resolve();const{data}=supabase.auth.onAuthStateChange(()=>resolve());return()=>{mounted=false;data.subscription.unsubscribe()}
  },[])
  useEffect(()=>{
    const sync=()=>{const slug=location.hash.replace(/^#/,'').split('?')[0];if(rank>=4&&['jobs','sources'].includes(slug)){setTab(slug);setOpen(true)}}
    sync();addEventListener('hashchange',sync);return()=>removeEventListener('hashchange',sync)
  },[rank])
  if(rank<4)return null
  const close=()=>{setOpen(false);const slug=location.hash.replace(/^#/,'').split('?')[0];if(['jobs','sources'].includes(slug))location.hash='#dashboard'}
  return <>
    <button className="ops-launcher" onClick={()=>{setTab('overview');setOpen(true)}} title="Open Layer 1–4 operations console"><Workflow size={15}/><span>Pipeline Ops</span></button>
    {open&&<OpsConsole tab={tab} setTab={setTab} onClose={close}/>} 
  </>
}

function OpsConsole({tab,setTab,onClose}){
  return <div className="ops-shell" role="dialog" aria-modal="true" aria-label="CourseFinder pipeline operations console">
    <header className="ops-topbar">
      <div className="ops-brand"><span className="ops-mark"><Workflow size={18}/></span><div><span className="ops-kicker">M1-PIPELINE-OPS · governed read console</span><h1>Pipeline Operations</h1><p>Regulatory → deterministic enrichment → AI suggestions → human resolution → Search → Publication</p></div></div>
      <div className="ops-top-actions"><span className="ops-version">v{OPS_VERSION}</span><button className="ops-icon" onClick={onClose} aria-label="Close operations console"><X size={18}/></button></div>
    </header>
    <nav className="ops-tabs" aria-label="Pipeline operations views">
      {[["overview","Pipeline Control",Layers3],["jobs","Jobs",Workflow],["sources","Sources",Database]].map(([key,label,Icon])=><button key={key} className={tab===key?'active':''} onClick={()=>setTab(key)}><Icon size={15}/>{label}</button>)}
    </nav>
    <main className="ops-main">
      {tab==='overview'&&<PipelineOverview setTab={setTab}/>} 
      {tab==='jobs'&&<JobsWorkspace/>}
      {tab==='sources'&&<SourcesWorkspace/>}
    </main>
  </div>
}

function PipelineOverview({setTab}){
  const[data,setData]=useState(null),[latest,setLatest]=useState({}),[busy,setBusy]=useState(true),[error,setError]=useState('')
  const load=async()=>{setBusy(true);setError('');try{const[overview,...jobs]=await Promise.all([adminRead('pipeline_overview'),...LAYERS.map(layer=>adminRead('pipeline_jobs_page',{limit:1,offset:0,layer,sort:'created',direction:'desc'}))]);setData(overview);const map={};LAYERS.forEach((l,i)=>map[l]=pageItems(jobs[i])[0]||null);setLatest(map)}catch(e){setError(e.message)}finally{setBusy(false)}}
  useEffect(()=>{load()},[])
  if(busy&&!data)return <Loading label="Loading real pipeline volumes…"/>
  if(error&&!data)return <ErrorState error={error} onRetry={load}/>
  const layers=data?.layers||[]
  const classifiedSources=layers.reduce((n,l)=>n+Number(l.source_count||0),0)
  const classifiedJobs=layers.reduce((n,l)=>n+Number(l.job_count||0),0)
  const unclassifiedSources=Math.max(0,Number(data?.observed_volumes?.sources||0)-classifiedSources)
  const unclassifiedJobs=Math.max(0,Number(data?.observed_volumes?.jobs||0)-classifiedJobs)
  return <div className="ops-stack">
    <section className="ops-command"><div><span className="ops-health"><span/>Operational authority remains layer-specific</span><h2>Layer 1 → Layer 4 operational journey</h2><p>Pipeline completion, Search admission and Publication are deliberately reported as separate states.</p></div><button className="ops-secondary" onClick={load}><RefreshCw size={14}/>Refresh</button></section>
    <Journey data={data}/>
    {(unclassifiedSources>0||unclassifiedJobs>0)&&<section className="ops-inline-warning"><AlertTriangle size={15}/><span><strong>Classification attention:</strong> {num(unclassifiedSources)} source(s) and {num(unclassifiedJobs)} job(s) currently sit outside L1–L4 classification. They are not silently folded into another authority layer.</span></section>}
    <div className="ops-layer-grid">{layers.map(layer=><LayerCard key={layer.code} layer={layer} latest={latest[layer.code]} onJobs={()=>setTab('jobs')} onSources={()=>setTab('sources')}/>)}</div>
    <div className="ops-grid-2"><SearchAdmission data={data?.search_admission}/><Publication data={data?.publication}/></div>
    <div className="ops-grid-2">
      <PolicyPanel title="Layer 3 authority" icon={Activity} tone="violet" rows={[["Suggestions",data?.layer3?.suggestions_total],["Claims",data?.layer3?.claims_total],["Policy",data?.layer3?.overwrite_policy||'Suggestion-only; no silent overwrite.']]}/>
      <PolicyPanel title="Layer 4 audit" icon={ShieldCheck} tone="green" rows={[["Review queue",data?.layer4?.review_queue_total],["Open",data?.layer4?.review_open],["Actions",data?.layer4?.review_actions_total],["Policy",data?.layer4?.audit_policy]]}/>
    </div>
    <section className="ops-guardrail"><ShieldCheck size={18}/><div><strong>Destructive controls are not generic operations.</strong><span>Retry, replay and reset remain disabled here. Any future mutation requires adapter-specific scope, idempotency proof, explicit confirmation and an auditable action contract.</span></div></section>
    <section className="ops-volume-strip">{Object.entries(data?.observed_volumes||{}).map(([k,v])=><div key={k}><span>{human(k)}</span><strong>{num(v)}</strong></div>)}</section>
  </div>
}

function Journey({data}){const stages=data?.journey||['Layer 1 Regulatory','Layer 2 Deterministic/Structured Enrichment','Layer 3 AI Suggestions','Layer 4 Human Resolution','Search Admission','Publication'];return <section className="ops-journey" aria-label="Pipeline journey">{stages.map((s,i)=><React.Fragment key={s}><div className={`ops-stage stage-${i+1}`}><span>{i+1}</span><strong>{s}</strong></div>{i<stages.length-1&&<ChevronRight className="ops-journey-arrow" size={17}/>}</React.Fragment>)}</section>}

function LayerCard({layer,latest,onJobs,onSources}){
  const blocked=Boolean(layer.blocker),running=Number(layer.running_jobs||0),failed=Number(layer.failed_jobs||0),stale=Number(layer.stale_running_jobs||0)
  const health=blocked||stale?'danger':failed?'warning':running?'active':'healthy'
  return <section className={`ops-layer-card health-${health}`}>
    <div className="ops-layer-head"><div><span className="ops-layer-code">{layer.code}</span><h3>{layer.name}</h3><p>{human(layer.authority)}</p></div><span className={`ops-status-dot ${health}`}><span/>{health==='healthy'?'Healthy':health==='active'?'Running':health==='warning'?'Attention':'Blocked'}</span></div>
    <div className="ops-layer-facts"><Fact label="Sources / configuration" value={num(layer.source_count)} action="View" onClick={onSources}/><Fact label="Last successful run" value={dateTime(layer.last_success_at)}/><Fact label="Current job" value={layer.current_job?`${layer.current_job.job_type} · ${human(layer.current_job.status)}`:'None'}/><Fact label="Evidence" value={num(layer.evidence_count)}/><Fact label="Jobs" value={`${num(layer.job_count)} total · ${num(layer.failed_jobs)} failed`}/><Fact label="Blocker" value={layer.blocker?human(layer.blocker):'None'}/></div>
    <RunMetrics job={latest}/>
    <div className="ops-next"><small>Next allowed action</small><p>{layer.next_allowed_action||'No action declared.'}</p></div>
    <div className="ops-ref-row"><span>Console CC <strong>{OPS_CHANGE}</strong></span><span>Console UAT <strong>{OPS_UAT}</strong></span></div>
    <div className="ops-ref-row secondary"><span>Run CC <strong>{latest?.change_control_ref||layer.governance_ref||'Not persisted'}</strong></span><span>Run UAT <strong>{latest?.uat_ref||layer.uat_ref||'Not persisted'}</strong></span></div>
    <button className="ops-link-button" onClick={onJobs}>Inspect {layer.code} jobs <ChevronRight size={14}/></button>
  </section>
}

function RunMetrics({job}){if(!job)return <div className="ops-run-empty">No classified run is available for this layer.</div>;return <div className="ops-run-block"><div className="ops-run-title"><div><small>Latest classified run</small><strong>{job.job_type||'Job'}</strong></div><div><Badge value={job.run_mode||'UNSPECIFIED'}/><Badge value={job.completion_class||job.status}/></div></div><div className="ops-metric-matrix"><Metric label="Discovered" value={job.discovered_count}/><Metric label="Selected" value={job.selected_count}/><Metric label="Processed" value={job.processed_count}/><Metric label="Accepted" value={job.accepted_count}/><Metric label="Rejected" value={job.rejected_count}/><Metric label="Ambiguity" value={job.ambiguity_count}/><Metric label="Creates" value={job.creates_count}/><Metric label="Updates" value={job.updates_count}/><Metric label="Unchanged" value={job.unchanged_count}/><Metric label="Conflicts" value={job.conflicts_count}/><Metric label="Duration" value={duration(job.duration_ms)}/><Metric label="Resume" value={cursor(job)}/></div></div>}

function JobsWorkspace(){
  const[filters,setFilters]=useState({query:'',layer:'',status:'',mode:'',country_code:'',job_type:'',failure_class:'',completion_class:''}),[opts,setOpts]=useState({}),[data,setData]=useState(null),[offset,setOffset]=useState(0),[busy,setBusy]=useState(false),[error,setError]=useState(''),[expanded,setExpanded]=useState(null),[detail,setDetail]=useState(null),[detailBusy,setDetailBusy]=useState(false)
  useEffect(()=>{adminRead('pipeline_filters').then(setOpts).catch(e=>setError(e.message))},[])
  const query=useDebounce(filters.query,250)
  useEffect(()=>{setOffset(0)},[query,filters.layer,filters.status,filters.mode,filters.country_code,filters.job_type,filters.failure_class,filters.completion_class])
  useEffect(()=>{let live=true;setBusy(true);setError('');adminRead('pipeline_jobs_page',{limit:PAGE_SIZE,offset,query:query||null,layer:filters.layer||null,status:filters.status||null,mode:filters.mode||null,country_code:filters.country_code||null,job_type:filters.job_type||null,failure_class:filters.failure_class||null,completion_class:filters.completion_class||null,sort:'created',direction:'desc'}).then(x=>live&&setData(x)).catch(e=>live&&setError(e.message)).finally(()=>live&&setBusy(false));return()=>{live=false}},[offset,query,filters.layer,filters.status,filters.mode,filters.country_code,filters.job_type,filters.failure_class,filters.completion_class])
  const rows=pageItems(data),total=Number(data?.total||0)
  const openJob=async id=>{if(expanded===id){setExpanded(null);setDetail(null);return}setExpanded(id);setDetail(null);setDetailBusy(true);try{setDetail(await adminRead('pipeline_job_detail',{id}))}catch(e){setError(e.message)}finally{setDetailBusy(false)}}
  return <div className="ops-stack"><WorkspaceHeader title="Jobs" subtitle="Server-paged execution history with governed run semantics and expandable evidence/error detail." total={total}/><section className="ops-panel"><div className="ops-filter-grid"><label className="ops-search"><Search size={15}/><input value={filters.query} onChange={e=>setFilters(f=>({...f,query:e.target.value}))} placeholder="Search job, source, worker or error…"/></label><Select label="Layer" value={filters.layer} onChange={v=>setFilters(f=>({...f,layer:v}))} options={opts.layers}/><Select label="Status" value={filters.status} onChange={v=>setFilters(f=>({...f,status:v}))} options={opts.statuses}/><Select label="Mode" value={filters.mode} onChange={v=>setFilters(f=>({...f,mode:v}))} options={opts.modes}/><Select label="Country" value={filters.country_code} onChange={v=>setFilters(f=>({...f,country_code:v}))} options={opts.countries}/><Select label="Job type" value={filters.job_type} onChange={v=>setFilters(f=>({...f,job_type:v}))} options={opts.job_types}/><Select label="Completion" value={filters.completion_class} onChange={v=>setFilters(f=>({...f,completion_class:v}))} options={['partial_batch','source_or_scope_complete','completed_scope_unknown','incomplete_failure','blocked','stale_running']}/><Select label="Failure class" value={filters.failure_class} onChange={v=>setFilters(f=>({...f,failure_class:v}))} options={['technical_failure','technical_runtime','technical_defect','source_validation','governed_rejection','governed_blocker','historical_superseded','stale_runtime']}/></div>{error&&<InlineError error={error}/>}<div className="ops-table-wrap"><table className="ops-table"><thead><tr><th/><th>Layer / mode</th><th>Job</th><th>Source</th><th>Status</th><th>Records</th><th>Changes</th><th>Evidence</th><th>Duration / cursor</th><th>Created</th></tr></thead><tbody>{busy&&rows.length===0?<SkeletonRows cols={10}/>:rows.length?rows.map(row=><React.Fragment key={row.id}><tr className={expanded===row.id?'expanded':''} onClick={()=>openJob(row.id)}><td><button className="ops-row-toggle" aria-label="Expand job">{expanded===row.id?<ChevronDown size={15}/>:<ChevronRight size={15}/>}</button></td><td><div className="ops-cell-stack"><Badge value={row.layer_code}/><Badge value={row.run_mode||'UNSPECIFIED'}/></div></td><td><div className="ops-cell-title"><strong>{row.job_type}</strong><span>{row.worker_version||row.run_scope||shortId(row.id)}</span></div></td><td><div className="ops-cell-title"><strong>{row.source_label||'Unlinked source'}</strong><span>{row.country_code||row.source_type||'—'}</span></div></td><td><div className="ops-cell-stack"><Badge value={row.status}/>{row.failure_class&&<small>{human(row.failure_class)}</small>}{row.ambiguity_count>0&&<small>{num(row.ambiguity_count)} unresolved ambiguity</small>}</div></td><td><MiniCounts row={row} keys={['discovered_count','selected_count','processed_count','accepted_count','rejected_count']}/></td><td><MiniCounts row={row} keys={['creates_count','updates_count','unchanged_count','conflicts_count']}/></td><td>{num(row.evidence_count)}</td><td><div className="ops-cell-title"><strong>{duration(row.duration_ms)}</strong><span>{cursor(row)}</span><span>{human(row.completion_class||'')}</span></div></td><td>{dateTime(row.created_at)}</td></tr>{expanded===row.id&&<tr className="ops-detail-row"><td colSpan="10"><JobDetail data={detail} busy={detailBusy}/></td></tr>}</React.Fragment>):<tr><td colSpan="10"><Empty label="No matching jobs"/></td></tr>}</tbody></table></div><Pager offset={offset} total={total} onOffset={setOffset}/></section></div>
}

function JobDetail({data,busy}){
  const[evidenceDetail,setEvidenceDetail]=useState(null),[evidenceEntities,setEvidenceEntities]=useState(null),[evidenceBusy,setEvidenceBusy]=useState(false)
  if(busy)return <Loading label="Loading job detail…" compact/>
  if(!data?.job)return <Empty label="Job detail is unavailable."/>
  const j=data.job,s=data.run_semantics||{},impact=data.entity_impact||{},actions=data.safe_actions||{},evidence=data.evidence||[]
  const linkedIds=new Set(evidence.map(e=>e.id));const referencedIds=[j?.result?.evidenceId,j?.result?.evidence_id,j?.payload?.evidence_id,j?.payload?.evidenceId].filter(Boolean).filter(id=>!linkedIds.has(id));const evidenceItems=[...evidence,...referencedIds.map(id=>({id,evidence_type:'Referenced replay evidence',captured_at:null,referenced:true}))]
  const loadEvidence=async id=>{setEvidenceBusy(true);try{const[d,e]=await Promise.all([adminRead('evidence_detail',{id}),adminRead('evidence_entities',{id,limit:50,offset:0})]);setEvidenceDetail(d);setEvidenceEntities(e)}finally{setEvidenceBusy(false)}}
  return <div className="ops-job-detail"><div className="ops-detail-grid"><DetailCard title="Run semantics" rows={[["Authority",human(s.authority)],["Mode",s.mode||'Unspecified'],["Completion",human(s.completion_class)],["Search action",s.search_action||'No Search action persisted'],["Change Control",s.change_control_ref||'Not persisted'],["UAT",s.uat_ref||'Not persisted']]}/><DetailCard title="Scope & impact" rows={[["Provider",impact.direct_provider?.name||'Batch/source scoped'],["Entity",impact.direct_entity?`${impact.direct_entity.entity_type} · ${impact.direct_entity.stable_key}`:'No direct entity persisted'],["Scope note",impact.scope_note]]}/><DetailCard title="Execution" rows={[["Started",dateTime(j.started_at)],["Completed",dateTime(j.completed_at)],["Attempts",j.attempt_count],["Duration",duration(j.duration_ms)],["Requested by",j.requested_by?shortId(j.requested_by):'—']]}/></div>{j.error_text&&<section className="ops-error-detail"><AlertTriangle size={17}/><div><strong>Error detail</strong><pre>{j.error_text}</pre></div></section>}<section className="ops-detail-section"><div className="ops-section-head"><div><FileCheck2 size={16}/><div><strong>Evidence linked or referenced by this job</strong><span>{num(evidenceItems.length)} artifact/reference(s) · click for affected entities and downstream state</span></div></div></div>{evidenceItems.length?<div className="ops-evidence-list">{evidenceItems.map(e=><button key={e.id} onClick={()=>loadEvidence(e.id)}><div><strong>{e.evidence_type||'Evidence'}</strong><span>{shortId(e.id)} · {e.referenced?'referenced by run':dateTime(e.captured_at)}</span></div><ChevronRight size={15}/></button>)}</div>:<Empty label="No evidence is linked or referenced by this job."/>}</section>{(evidenceBusy||evidenceDetail)&&<EvidenceImpact detail={evidenceDetail} entities={evidenceEntities} busy={evidenceBusy}/>}<section className="ops-detail-section"><div className="ops-section-head"><div><ShieldCheck size={16}/><div><strong>Safe action policy</strong><span>No generic mutation is exposed by this console.</span></div></div></div><div className="ops-action-grid">{['retry','replay','reset'].map(k=><button key={k} disabled title={actions[k]?.reason||'Not enabled'}><span>{human(k)}</span><small>{actions[k]?.reason||'Not enabled by the governed contract.'}</small></button>)}</div></section></div>
}

function EvidenceImpact({detail,entities,busy}){if(busy)return <Loading label="Resolving evidence impact…" compact/>;const a=detail?.artifact||{},source=detail?.source||{},rows=pageItems(entities);return <section className="ops-evidence-impact"><div className="ops-section-head"><div><BookOpen size={16}/><div><strong>Evidence → entity impact</strong><span>{a.evidence_type||'Evidence'} · {source.label||source.authority_url||shortId(a.id)}</span></div></div></div><div className="ops-impact-meta"><span>Layer <strong>{a.layer||'—'}</strong></span><span>Status <strong>{human(a.status||'')}</strong></span><span>Hash <strong>{a.content_hash?`${a.content_hash.slice(0,12)}…`:'—'}</strong></span><span>Observations <strong>{num(a.observation_count)}</strong></span><span>Affected entities <strong>{num(entities?.total)}</strong></span></div>{rows.length?<div className="ops-impact-list">{rows.map(r=><div key={`${r.entity_type}-${r.entity_id}`}><div><strong>{r.entity_label||r.entity_code||shortId(r.entity_id)}</strong><span>{human(r.entity_type)}{r.provider_label?` · ${r.provider_label}`:''}</span></div><div className="ops-impact-state"><span>Canonical: {human(r.canonical_publication_status||'n/a')}</span>{r.entity_type==='course'&&<span>Search: {r.search_projected?human(r.search_publication_status||'projected'):'not projected'}</span>}</div></div>)}</div>:<Empty label="No canonical entity links were resolved for this evidence artifact."/>}<p className="ops-consequence-note">{entities?.consequence_note}</p></section>}

function SourcesWorkspace(){
  const[filters,setFilters]=useState({query:'',layer:'',country_code:'',status:'',source_type:'',health:''}),[opts,setOpts]=useState({}),[data,setData]=useState(null),[offset,setOffset]=useState(0),[busy,setBusy]=useState(false),[error,setError]=useState('')
  useEffect(()=>{adminRead('pipeline_filters').then(setOpts).catch(e=>setError(e.message))},[])
  const query=useDebounce(filters.query,250)
  useEffect(()=>setOffset(0),[query,filters.layer,filters.country_code,filters.status,filters.source_type,filters.health])
  useEffect(()=>{let live=true;setBusy(true);adminRead('pipeline_sources_page',{limit:PAGE_SIZE,offset,query:query||null,layer:filters.layer||null,country_code:filters.country_code||null,status:filters.status||null,source_type:filters.source_type||null,health:filters.health||null,sort:'source',direction:'asc'}).then(x=>live&&setData(x)).catch(e=>live&&setError(e.message)).finally(()=>live&&setBusy(false));return()=>{live=false}},[offset,query,filters.layer,filters.country_code,filters.status,filters.source_type,filters.health])
  const rows=pageItems(data),total=Number(data?.total||0)
  return <div className="ops-stack"><WorkspaceHeader title="Sources" subtitle="Governed source/configuration inventory with health, freshness, workload and evidence coverage." total={total}/><section className="ops-panel"><div className="ops-filter-grid source-filters"><label className="ops-search"><Search size={15}/><input value={filters.query} onChange={e=>setFilters(f=>({...f,query:e.target.value}))} placeholder="Search source, provider or authority URL…"/></label><Select label="Layer" value={filters.layer} onChange={v=>setFilters(f=>({...f,layer:v}))} options={opts.layers}/><Select label="Country" value={filters.country_code} onChange={v=>setFilters(f=>({...f,country_code:v}))} options={opts.countries}/><Select label="Status" value={filters.status} onChange={v=>setFilters(f=>({...f,status:v}))} options={['active','inactive','blocked','retired']}/><Select label="Source type" value={filters.source_type} onChange={v=>setFilters(f=>({...f,source_type:v}))} options={opts.source_types}/><Select label="Health" value={filters.health} onChange={v=>setFilters(f=>({...f,health:v}))} options={['healthy','unhealthy','untested']}/></div>{error&&<InlineError error={error}/>}<div className="ops-source-grid">{busy&&rows.length===0?Array.from({length:6}).map((_,i)=><div className="ops-source-skeleton" key={i}/>):rows.length?rows.map(r=><SourceCard key={r.source_id} row={r}/>):<Empty label="No matching sources"/>}</div><Pager offset={offset} total={total} onOffset={setOffset}/></section></div>
}

function SourceCard({row}){return <article className="ops-source-card"><div className="ops-source-head"><div><Badge value={row.layer_code}/><h3>{row.source_label}</h3><p>{row.source_type} · {row.country_name||row.country_code||'Unscoped'}</p></div><Badge value={row.health}/></div><div className="ops-source-facts"><Fact label="Status" value={human(row.status)}/><Fact label="Trust rank" value={row.trust_rank??'—'}/><Fact label="Last success" value={dateTime(row.last_success_at||row.last_job_success_at)}/><Fact label="Freshness" value={row.freshness_age_days==null?human(row.freshness_class):`${row.freshness_age_days} days`}/><Fact label="Running jobs" value={num(row.running_jobs)}/><Fact label="Problem jobs" value={num(row.problem_jobs)}/><Fact label="Evidence" value={num(row.evidence_count)}/><Fact label="Provider" value={row.provider_name||'Source scoped'}/></div>{row.last_error&&<details className="ops-source-error"><summary><AlertTriangle size={14}/>Last source error</summary><pre>{row.last_error}</pre></details>}<SourceConfiguration metadata={row.metadata}/>{row.source_url&&<a className="ops-source-link" href={row.source_url} target="_blank" rel="noreferrer">Authority / source <ExternalLink size={13}/></a>}</article>}
function SourceConfiguration({metadata}){const rows=configSummary(metadata);if(!rows.length)return null;return <details className="ops-source-config"><summary><Filter size={13}/>Configuration</summary><div>{rows.map(([k,v])=><Fact key={k} label={human(k)} value={typeof v==='boolean'?(v?'Yes':'No'):Array.isArray(v)?v.join(', '):String(v)}/>)}</div></details>}

function SearchAdmission({data}){const gates=data?.country_gates||[];return <section className="ops-panel"><SectionTitle icon={SearchCheck} title="Search Admission" subtitle="Independent from ingestion/enrichment success"/><div className="ops-big-stat"><strong>{num(data?.documents)}</strong><span>Search documents</span></div><div className="ops-detail-list"><Fact label="Generation" value={data?.projection?.generation??'—'}/><Fact label="Projection rows" value={num(data?.projection?.row_count)}/><Fact label="Rebuilt" value={dateTime(data?.projection?.rebuilt_at)}/><Fact label="Blocked enrichment gates" value={num(data?.blocked_enrichment_gates)}/></div><div className="ops-gates">{gates.map((g,i)=><span key={i}><strong>{g.country_code||'—'}</strong><Badge value={g.gate_status}/></span>)}</div><p className="ops-definition">{data?.definition}</p></section>}
function Publication({data}){return <section className="ops-panel"><SectionTitle icon={ExternalLink} title="Publication" subtitle="Downstream channel state"/><div className="ops-big-stat"><strong>{num(data?.entity_states_total)}</strong><span>Entity publication states</span></div><div className="ops-publication-counts">{Object.entries(data?.status_counts||{}).map(([k,v])=><span key={k}><small>{human(k)}</small><strong>{num(v)}</strong></span>)}</div><div className="ops-channel-list">{(data?.channels||[]).map(c=><span key={c.code}>{c.name||c.code}</span>)}</div><p className="ops-definition">{data?.definition}</p></section>}
function PolicyPanel({title,icon:Icon,rows,tone}){return <section className={`ops-panel policy-${tone}`}><SectionTitle icon={Icon} title={title}/><div className="ops-detail-list">{rows.map(([l,v])=><Fact key={l} label={l} value={typeof v==='number'?num(v):v}/>)}</div></section>}
function WorkspaceHeader({title,subtitle,total}){return <section className="ops-workspace-head"><div><span className="ops-kicker">Operational console</span><h2>{title}</h2><p>{subtitle}</p></div><div className="ops-result-count"><strong>{num(total)}</strong><span>matching</span></div></section>}
function SectionTitle({icon:Icon,title,subtitle}){return <div className="ops-section-title"><span><Icon size={16}/></span><div><h3>{title}</h3>{subtitle&&<p>{subtitle}</p>}</div></div>}
function DetailCard({title,rows}){return <section className="ops-detail-card"><h4>{title}</h4>{rows.map(([l,v])=><Fact key={l} label={l} value={v}/>)}</section>}
function Fact({label,value,action,onClick}){return <div className="ops-fact"><span>{label}</span><div><strong title={String(value??'—')}>{value??'—'}</strong>{action&&<button onClick={onClick}>{action}</button>}</div></div>}
function Metric({label,value}){return <div className="ops-metric"><span>{label}</span><strong>{value==null?'—':typeof value==='number'?num(value):value}</strong></div>}
function MiniCounts({row,keys}){return <div className="ops-mini-counts">{keys.map(k=><span key={k} title={human(k)}><small>{human(k).replace(' count','').split(' ')[0]}</small><strong>{row[k]==null?'—':num(row[k])}</strong></span>)}</div>}
function Badge({value}){const v=String(value||'unknown');return <span className={`ops-badge b-${slug(v)}`}>{human(v)}</span>}
function Select({label,value,onChange,options}){const list=normalise(options);return <label className="ops-select"><span>{label}</span><select value={value} onChange={e=>onChange(e.target.value)}><option value="">All</option>{list.map(o=><option value={o.value} key={o.value}>{o.label}</option>)}</select></label>}
function Pager({offset,total,onOffset}){const page=Math.floor(offset/PAGE_SIZE)+1,pages=Math.max(1,Math.ceil(total/PAGE_SIZE));return <div className="ops-pager"><span>Page {num(page)} of {num(pages)} · {num(total)} records</span><div><button disabled={offset<=0} onClick={()=>onOffset(Math.max(0,offset-PAGE_SIZE))}><ArrowLeft size={14}/>Previous</button><button disabled={offset+PAGE_SIZE>=total} onClick={()=>onOffset(offset+PAGE_SIZE)}>Next<ChevronRight size={14}/></button></div></div>}
function Loading({label,compact=false}){return <div className={`ops-loading ${compact?'compact':''}`}><RefreshCw size={17}/><span>{label}</span></div>}
function ErrorState({error,onRetry}){return <section className="ops-error-state"><AlertTriangle size={22}/><h2>Operations data could not be loaded</h2><p>{error}</p><button onClick={onRetry}><RefreshCw size={14}/>Retry</button></section>}
function InlineError({error}){return <div className="ops-inline-error"><AlertTriangle size={15}/><span>{error}</span></div>}
function Empty({label}){return <div className="ops-empty">{label}</div>}
function SkeletonRows({cols}){return Array.from({length:7}).map((_,i)=><tr key={i}>{Array.from({length:cols}).map((_,j)=><td key={j}><span className="ops-skeleton-line"/></td>)}</tr>)}
function useDebounce(v,ms){const[x,setX]=useState(v);useEffect(()=>{const t=setTimeout(()=>setX(v),ms);return()=>clearTimeout(t)},[v,ms]);return x}
function pageItems(v){return v?.items??v?.rows??(Array.isArray(v)?v:[])}
function normalise(values){return(values||[]).map(v=>typeof v==='object'?{value:String(v.code??v.value??v.id??''),label:String(v.name??v.label??v.code??v.value??v.id??'')}:{value:String(v),label:human(v)}).filter(x=>x.value)}
function human(v){return String(v??'').replace(/[_-]+/g,' ').replace(/\b\w/g,c=>c.toUpperCase())}
function slug(v){return String(v||'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'')}
function num(v){const n=Number(v);return Number.isFinite(n)?n.toLocaleString('en-AU'):'—'}
function dateTime(v){if(!v)return'—';const d=new Date(v);return Number.isNaN(d.getTime())?'—':new Intl.DateTimeFormat('en-AU',{dateStyle:'medium',timeStyle:'short'}).format(d)}
function duration(ms){const n=Number(ms);if(!Number.isFinite(n))return'—';if(n<1000)return`${Math.round(n)} ms`;if(n<60000)return`${(n/1000).toFixed(1)} s`;return`${Math.floor(n/60000)}m ${Math.round((n%60000)/1000)}s`}
function cursor(j){if(j?.next_cursor!=null)return`next ${num(j.next_cursor)}${j.has_more?' · more':''}`;if(j?.cursor_offset!=null)return`offset ${num(j.cursor_offset)}`;return'No cursor persisted'}
function configSummary(metadata){const m=metadata||{};const keys=['configured_worker_version','worker_version','scope','coverage_role','apply_gate','apply_enabled','identity_scheme','course_identity_scheme','transport','acquisition_method','coverage_complete_for_country'];return keys.filter(k=>m[k]!=null).slice(0,7).map(k=>[k,m[k]])}
function shortId(v){const s=String(v||'');return s.length>12?`${s.slice(0,8)}…`:s||'—'}

const host=document.getElementById('pipeline-ops-root')
if(host)createRoot(host).render(<PipelineOpsEntry/>)
