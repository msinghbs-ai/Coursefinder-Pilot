import React,{useEffect,useMemo,useState}from'react'
import{
  Activity,AlertTriangle,Archive,Blocks,CheckCircle2,Database,HardDrive,RefreshCw,
  Search,ServerCog,ShieldCheck,SlidersHorizontal,TestTube2,Workflow
}from'lucide-react'
import{adminRead,supabase}from'./lib/supabase'
import'./platform-maturity.css'

const TABS=[
  ['overview','Overview',ServerCog],
  ['capacity','Capacity & integrity',HardDrive],
  ['gates','Environment gates',ShieldCheck],
  ['uat','UAT catalogue',TestTube2],
  ['performance','Performance & retention',Activity],
  ['blocks','Layer 4 blocks',Blocks],
]
const BLOCK_SCOPES=[['operational','Operational'],['publication','Publication'],['search','Search'],['data_quality_quarantine','Data quality quarantine']]
const ENTITY_TYPES=[['provider','Provider'],['course','Course'],['campus','Campus'],['scholarship','Scholarship']]
const num=v=>Number(v||0)
const fmtNumber=v=>new Intl.NumberFormat('en-AU').format(num(v))
const fmtBytes=v=>{const n=num(v);if(!n)return'0 B';const u=['B','KB','MB','GB','TB'],i=Math.min(Math.floor(Math.log(n)/Math.log(1024)),u.length-1);return (n/1024**i).toFixed(i<2?0:2)+' '+u[i]}
const fmtDate=v=>{if(!v)return'—';const d=new Date(v);return Number.isNaN(d.valueOf())?'—':d.toLocaleString('en-AU',{dateStyle:'medium',timeStyle:'short'})}
const title=v=>String(v||'').replace(/[_-]+/g,' ').replace(/\b\w/g,x=>x.toUpperCase())
const toneFor=v=>{const x=String(v||'').toLowerCase();if(['pass','passed','pilot_uat_pass','pilot_qualified','accepted_baseline','healthy','enabled','published'].includes(x))return'success';if(['warning','designed','registered','internal','active'].includes(x))return'warning';if(['critical','error','failed','blocked','not_run','disabled'].includes(x))return'danger';return'neutral'}
const list=v=>v?.items??v?.rows??(Array.isArray(v)?v:[])
const itemId=x=>x?.id||x?.entity_id||x?.provider_id||x?.course_id||x?.campus_id||x?.scholarship_id||''
const itemLabel=x=>x?.display_name||x?.canonical_name||x?.display_title||x?.canonical_title||x?.name||x?.title||x?.entity_name||x?.stable_key||itemId(x)

function Pill({children,tone='neutral'}){return <span className={'pm-pill tone-'+tone}>{children}</span>}
function Metric({label,value,detail,tone='neutral',Icon=Database}){return <div className={'pm-metric tone-'+tone}><span className="pm-metric-icon"><Icon size={18}/></span><div><small>{label}</small><strong>{value}</strong>{detail&&<span>{detail}</span>}</div></div>}
function SectionTitle({icon:Icon=ServerCog,title:heading,subtitle,action}){return <div className="pm-section-title"><div className="pm-section-heading"><span className="pm-section-icon"><Icon size={17}/></span><div><h3>{heading}</h3>{subtitle&&<p>{subtitle}</p>}</div></div>{action}</div>}
function Empty({children}){return <div className="pm-empty">{children}</div>}

export default function PlatformMaturity({rank,onError}){
  const[tab,setTab]=useState('overview')
  const[environment,setEnvironment]=useState('pilot')
  const[data,setData]=useState({readiness:null,capacity:null,gates:null,uat:null,workloads:null,retention:null,blocks:null})
  const[busy,setBusy]=useState(true),[error,setError]=useState('')
  const load=async()=>{
    setBusy(true);setError('')
    try{
      const[readiness,capacity,gates,uat,workloads,retention,blocks]=await Promise.all([
        adminRead('platform_readiness'),
        adminRead('platform_capacity',{environment}),
        adminRead('platform_environment_gates',{environment}),
        adminRead('platform_uat_catalogue',{limit:100,offset:0}),
        adminRead('platform_workloads'),
        adminRead('platform_retention',{environment}),
        adminRead('platform_active_blocks',{limit:100,offset:0}),
      ])
      setData({readiness,capacity,gates,uat,workloads,retention,blocks})
    }catch(e){const msg=e?.message||String(e);setError(msg);onError?.(msg)}finally{setBusy(false)}
  }
  useEffect(()=>{load()},[environment])

  const uatItems=list(data.uat)
  const prodOpen=uatItems.filter(x=>(x.environment_scope==='production'||x.environment_scope==='both')&&x.hard_gate&&x.status!=='pass')
  const acceptedPilot=uatItems.filter(x=>x.environment_scope==='pilot'&&x.status==='accepted_baseline')
  const cap=data.capacity||{},integrity=cap.integrity_classification||{},policy=cap.platform_capacity_policy||{},evidencePolicy=cap.evidence_capacity_policy||{}
  const productionEnabled=num(data.readiness?.production_source_capabilities_enabled)+num(data.readiness?.production_scrapers_enabled)+num(data.readiness?.production_ai_profiles_enabled)

  return <div className="pm-shell" data-platform-maturity="true">
    <section className="pm-hero">
      <div className="pm-hero-copy"><span className="pm-eyebrow">M2.5 · Platform maturity</span><h2>Platform operations & readiness</h2><p>Environment gates, capacity, UAT, retention, workload budgets and reversible Layer 4 blocking in one governed Administration surface.</p></div>
      <div className="pm-hero-actions"><label className="pm-env-control"><span>View environment</span><select value={environment} onChange={e=>setEnvironment(e.target.value)}><option value="pilot">Pilot</option><option value="production">Production</option></select></label><button className="pm-button secondary" onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Refreshing…':'Refresh'}</button></div>
    </section>

    <section className="pm-boundary-banner">
      <ShieldCheck size={18}/>
      <div><strong>Production boundary remains closed</strong><span>No Production project is provisioned. This workspace is read-first; it cannot enable Production sources, scrapers, AI profiles, PITR or destructive purge.</span></div>
      <Pill tone={productionEnabled?'danger':'success'}>{productionEnabled?'Unexpected Production enablement':'0 Production enablement expected'}</Pill>
    </section>

    {error&&<div className="pm-alert"><AlertTriangle size={16}/><span>{error}</span></div>}

    <nav className="pm-tabs" aria-label="Platform maturity sections">
      {TABS.map(([key,label,Icon])=><button key={key} className={tab===key?'active':''} onClick={()=>setTab(key)}><Icon size={15}/><span>{label}</span></button>)}
    </nav>

    {busy&&!data.readiness?<div className="pm-loading"><span className="pm-spinner"/>Loading governed platform state…</div>:<>
      {tab==='overview'&&<Overview readiness={data.readiness} capacity={cap} acceptedPilot={acceptedPilot} prodOpen={prodOpen}/>}
      {tab==='capacity'&&<Capacity capacity={cap} integrity={integrity} policy={policy} evidencePolicy={evidencePolicy}/>}
      {tab==='gates'&&<Gates gates={data.gates} environment={environment}/>}
      {tab==='uat'&&<Uat items={uatItems}/>}
      {tab==='performance'&&<Performance workloads={list(data.workloads)} retention={data.retention}/>}
      {tab==='blocks'&&<BlockConsole rank={rank} blocks={list(data.blocks)} reload={load}/>}
    </>}
  </div>
}

function Overview({readiness,capacity,acceptedPilot,prodOpen}){
  const wave=readiness?.current_layer2_wave||{}
  return <div className="pm-stack">
    <div className="pm-metric-grid">
      <Metric Icon={ShieldCheck} label="Production source capabilities" value={fmtNumber(readiness?.production_source_capabilities_enabled)} detail="Expected 0 before provisioning" tone={num(readiness?.production_source_capabilities_enabled)?'danger':'success'}/>
      <Metric Icon={SlidersHorizontal} label="Production scrapers" value={fmtNumber(readiness?.production_scrapers_enabled)} detail="Environment-gated" tone={num(readiness?.production_scrapers_enabled)?'danger':'success'}/>
      <Metric Icon={Activity} label="Production AI profiles" value={fmtNumber(readiness?.production_ai_profiles_enabled)} detail="Separate benchmark required" tone={num(readiness?.production_ai_profiles_enabled)?'danger':'success'}/>
      <Metric Icon={TestTube2} label="Open Production hard gates" value={fmtNumber(readiness?.production_uat_open)} detail={prodOpen.length+' visible in catalogue'} tone={num(readiness?.production_uat_open)?'warning':'success'}/>
      <Metric Icon={HardDrive} label="Evidence storage" value={fmtBytes(capacity?.evidence_object_bytes)} detail={fmtNumber(capacity?.evidence_object_count)+' objects · '+num(capacity?.evidence_planning_capacity_pct).toFixed(2)+'% planning envelope'} tone={toneFor(capacity?.severity)}/>
      <Metric Icon={CheckCircle2} label="Accepted Pilot UAT domains" value={fmtNumber(acceptedPilot.length)} detail="M2.4.4 permanent baseline" tone="success"/>
    </div>

    <section className="pm-panel"><SectionTitle icon={Workflow} title="Current Layer 2 wave" subtitle="Latest governed wave state; not a request to start new work."/>
      {wave?.id?<div className="pm-kv-grid">
        <div><span>Status</span><strong><Pill tone={toneFor(wave.status)}>{title(wave.status)}</Pill></strong></div>
        <div><span>Country / scope</span><strong>{wave.country_code||'—'} · {title(wave.scope_type||'—')}</strong></div>
        <div><span>Accepted wave</span><strong>{fmtNumber(wave.accepted_wave_size)}</strong></div>
        <div><span>Total / dispatched</span><strong>{fmtNumber(wave.total_items)} / {fmtNumber(wave.dispatched_items)}</strong></div>
        <div><span>Completed / failed</span><strong>{fmtNumber(wave.completed_items)} / {fmtNumber(wave.failed_items)}</strong></div>
        <div><span>Updated</span><strong>{fmtDate(wave.updated_at)}</strong></div>
      </div>:<Empty>No Layer 2 wave state is currently recorded.</Empty>}
    </section>

    <section className="pm-panel"><SectionTitle icon={Archive} title="Governance inventory" subtitle="Foundation counts from the accepted M2.5 platform model."/>
      <div className="pm-inline-stats"><span><strong>{fmtNumber(readiness?.retention_policy_classes)}</strong> retention classes</span><span><strong>{fmtNumber(readiness?.performance_profiles)}</strong> workload profiles</span><span><strong>{fmtNumber(prodOpen.length)}</strong> Production UAT entries not passed</span></div>
    </section>
  </div>
}

function Capacity({capacity,integrity,policy,evidencePolicy}){
  return <div className="pm-stack">
    <div className="pm-metric-grid">
      <Metric Icon={Database} label="Logical database" value={fmtBytes(capacity?.database_bytes)} detail={'Warn '+fmtBytes(policy?.database_warn_bytes)+' · High '+fmtBytes(policy?.database_high_bytes)} tone={num(capacity?.database_bytes)>=num(policy?.database_warn_bytes)?'warning':'success'}/>
      <Metric Icon={HardDrive} label="Evidence storage" value={fmtBytes(capacity?.evidence_object_bytes)} detail={fmtNumber(capacity?.evidence_object_count)+' objects'} tone={toneFor(capacity?.severity)}/>
      <Metric Icon={Activity} label="Planning utilisation" value={num(capacity?.evidence_planning_capacity_pct).toFixed(2)+'%'} detail="Governed 60 GiB planning envelope · not vendor hard quota" tone={num(capacity?.evidence_planning_capacity_pct)>=num(evidencePolicy?.warn_pct)?'warning':'success'}/>
      <Metric Icon={AlertTriangle} label="Integrity severity" value={title(capacity?.severity||'unknown')} detail={'Severity input '+fmtNumber(capacity?.integrity_count_for_severity)} tone={toneFor(capacity?.severity)}/>
    </div>

    <section className="pm-panel"><SectionTitle icon={AlertTriangle} title="Evidence lineage classification" subtitle="CF-055 separates duplicate objects from unresolved provenance. No cleanup is authorised here."/>
      <div className="pm-kv-grid">
        <div><span>Raw unlinked Storage objects</span><strong>{fmtNumber(capacity?.unlinked_storage_object_count_raw)}</strong></div>
        <div><span>Proven duplicates</span><strong>{fmtNumber(capacity?.duplicate_unlinked_storage_object_count)}</strong></div>
        <div><span>Unresolved orphan objects</span><strong>{fmtNumber(integrity?.unresolved_orphan_objects)}</strong></div>
        <div><span>Missing Storage objects</span><strong>{fmtNumber(capacity?.missing_storage_object_count)}</strong></div>
        <div><span>Virtual/external Evidence refs</span><strong>{fmtNumber(capacity?.virtual_evidence_reference_count)}</strong></div>
        <div><span>Evidence artifact rows</span><strong>{fmtNumber(capacity?.evidence_artifact_count)}</strong></div>
      </div>
    </section>

    <div className="pm-two-col">
      <section className="pm-panel"><SectionTitle icon={Activity} title="Database/temp activity" subtitle="Temp counters are cumulative; the latest delta is the useful interval signal."/>
        <div className="pm-kv-list"><div><span>Temp since previous observation</span><strong>{fmtBytes(capacity?.temp_bytes_since_previous_observation)}</strong></div><div><span>Cumulative temp bytes</span><strong>{fmtBytes(capacity?.cumulative_temp_bytes)}</strong></div><div><span>Cumulative temp files</span><strong>{fmtNumber(capacity?.cumulative_temp_files)}</strong></div><div><span>Observed</span><strong>{fmtDate(capacity?.observed_at)}</strong></div></div>
      </section>
      <section className="pm-panel"><SectionTitle icon={ShieldCheck} title="Recovery & notifications" subtitle="Product capability is not the same as configured/restore proof."/>
        <div className="pm-kv-list"><div><span>Backup state</span><strong><Pill tone="warning">{title(capacity?.backup_status||'unverified')}</Pill></strong></div><div><span>PITR state</span><strong><Pill tone="warning">{title(capacity?.pitr_status||'unverified')}</Pill></strong></div><div><span>Notification target</span><strong>{policy?.notification_target||'Not configured'}</strong></div><div><span>Observation retention</span><strong>{fmtNumber(policy?.observation_retention_days)} days</strong></div></div>
        <p className="pm-note">CF-056: actual backup inventory/PITR configuration and an executed restore remain separate control-plane/Production gates.</p>
      </section>
    </div>

    <section className="pm-panel"><SectionTitle icon={Database} title="Largest relations" subtitle="Current database footprint contributors."/>
      <div className="pm-table-wrap"><table className="pm-table"><thead><tr><th>Schema</th><th>Relation</th><th>Size</th></tr></thead><tbody>{(capacity?.largest_relations||[]).map((x,i)=><tr key={x.schema+'.'+x.relation+'.'+i}><td>{x.schema}</td><td>{x.relation}</td><td>{fmtBytes(x.bytes)}</td></tr>)}</tbody></table></div>
    </section>
  </div>
}

function GateTable({heading,items,kind}){
  return <section className="pm-panel"><SectionTitle icon={ShieldCheck} title={heading} subtitle={items.length+' configured gate(s)'}/>
    {!items.length?<Empty>No gates exist for this environment.</Empty>:<div className="pm-table-wrap"><table className="pm-table"><thead><tr><th>{kind==='source'?'Source':kind==='scraper'?'Acquisition provider':'AI profile'}</th>{kind==='source'&&<th>Capability</th>}<th>State</th><th>Enabled</th><th>UAT / benchmark</th><th>Reason</th><th>Updated</th></tr></thead><tbody>{items.map((x,i)=><tr key={x.source_id||x.provider_id||x.profile_id||i}><td><strong>{x.source_label||x.provider_name||x.profile_code||'—'}</strong>{kind==='ai'&&x.model_identifier&&<small>{x.model_identifier}</small>}</td>{kind==='source'&&<td>{title(x.capability)}</td>}<td><Pill tone={toneFor(x.state)}>{title(x.state)}</Pill></td><td><Pill tone={x.enabled?'success':'neutral'}>{x.enabled?'Enabled':'Disabled'}</Pill></td><td>{x.uat_ref||x.benchmark_ref||'—'}</td><td className="pm-reason">{x.reason||'—'}</td><td>{fmtDate(x.updated_at)}</td></tr>)}</tbody></table></div>}
  </section>
}
function Gates({gates,environment}){const g=gates||{};return <div className="pm-stack"><section className="pm-panel pm-environment-head"><div><span>Environment</span><strong>{title(environment)}</strong></div>{environment==='production'&&<Pill tone="warning">Read-only until Production provisioning</Pill>}</section><GateTable heading="Layer 1 source capabilities" items={g.source_gates||[]} kind="source"/><GateTable heading="Layer 2 acquisition providers" items={g.scraper_gates||[]} kind="scraper"/><GateTable heading="Layer 3 model profiles" items={g.ai_gates||[]} kind="ai"/></div>}

function Uat({items}){
  const production=items.filter(x=>x.environment_scope==='production'||x.environment_scope==='both')
  const pilot=items.filter(x=>x.environment_scope==='pilot')
  return <div className="pm-stack"><section className="pm-panel"><SectionTitle icon={TestTube2} title="Production & maturity gates" subtitle="Designed/not-run remains open; a catalogue row is not proof by itself."/><UatTable items={production}/></section><section className="pm-panel"><SectionTitle icon={CheckCircle2} title="Accepted Pilot permanent domains" subtitle="Frozen M2.4.4 acceptance references retained for traceability."/><UatTable items={pilot}/></section></div>
}
function UatTable({items}){
  if(!items.length)return <Empty>No UAT entries match this view.</Empty>
  return <div className="pm-table-wrap"><table className="pm-table"><thead><tr><th>Code</th><th>Domain</th><th>Environment</th><th>Class</th><th>Status</th><th>Hard gate</th><th>Evidence</th></tr></thead><tbody>{items.map(x=><tr key={x.test_code}><td><strong>{x.test_code}</strong></td><td>{x.domain}<small>{x.description}</small></td><td>{title(x.environment_scope)}</td><td>{title(x.gate_class)}</td><td><Pill tone={toneFor(x.status)}>{title(x.status)}</Pill></td><td>{x.hard_gate?'Yes':'No'}</td><td>{x.evidence_ref||'—'}</td></tr>)}</tbody></table></div>
}

function Performance({workloads,retention}){
  const classes=retention?.classes||[],dry=retention?.dry_run||{}
  return <div className="pm-stack">
    <section className="pm-panel"><SectionTitle icon={Activity} title="Workload profiles" subtitle="Serving, ingestion and concurrency are measured separately under unchanged hard budgets."/><div className="pm-table-wrap"><table className="pm-table"><thead><tr><th>Profile</th><th>Workload</th><th>Traffic shape</th><th>RPC</th><th>Management payload</th><th>Filter payload</th><th>Sizing role</th></tr></thead><tbody>{workloads.map(x=><tr key={x.profile_key}><td><strong>{title(x.profile_key)}</strong></td><td>{title(x.workload_class)}</td><td><div className="pm-pill-row">{x.serving_traffic&&<Pill tone="success">Serving</Pill>}{x.background_ingestion&&<Pill tone="warning">Ingestion</Pill>}{x.concurrent_admin_uat&&<Pill tone="neutral">Admin/UAT</Pill>}</div></td><td>{fmtNumber(x.rpc_detail_budget_ms)} ms</td><td>{fmtBytes(x.management_payload_budget_bytes)}</td><td>{fmtBytes(x.filter_payload_budget_bytes)}</td><td>{title(x.sizing_role)}<small>{x.notes}</small></td></tr>)}</tbody></table></div></section>
    <section className="pm-panel"><SectionTitle icon={Archive} title="Retention policy" subtitle="Dry-run first. No destructive purge action exists in this workspace."/><div className="pm-inline-stats"><span><strong>{fmtNumber(dry.terminal_job_candidates_older_than_90d)}</strong> terminal jobs older than 90d</span><span><strong>{fmtNumber(dry.immutable_policy_classes)}</strong> immutable classes</span><span><strong>0</strong> Evidence delete candidates</span><span><strong>{dry.delete_performed?'Unexpected':'No'}</strong> deletion performed</span></div><div className="pm-table-wrap"><table className="pm-table"><thead><tr><th>Class</th><th>Object scope</th><th>Immutable</th><th>Purge allowed</th><th>Retention</th><th>Bound</th><th>Safeguards</th></tr></thead><tbody>{classes.map(x=><tr key={x.class_key}><td><strong>{title(x.class_key)}</strong></td><td>{x.object_scope}</td><td><Pill tone={x.immutable?'success':'neutral'}>{x.immutable?'Yes':'No'}</Pill></td><td><Pill tone={x.purge_allowed?'warning':'success'}>{x.purge_allowed?'Policy allows':'No'}</Pill></td><td>{x.default_retention_days?x.default_retention_days+' days':'Retain'}</td><td>{x.bounded_delete_limit?fmtNumber(x.bounded_delete_limit):'—'}</td><td>{x.dry_run_required?'Dry-run · ':''}{x.post_delete_integrity_required?'integrity check':''}<small>{x.notes}</small></td></tr>)}</tbody></table></div></section>
  </div>
}

function BlockConsole({rank,blocks,reload}){
  const[entityType,setEntityType]=useState('provider'),[query,setQuery]=useState(''),[results,setResults]=useState([]),[selected,setSelected]=useState(null)
  const[scope,setScope]=useState('operational'),[reason,setReason]=useState(''),[comment,setComment]=useState(''),[expires,setExpires]=useState(''),[review,setReview]=useState('')
  const[state,setState]=useState(null),[busy,setBusy]=useState(false),[message,setMessage]=useState('')
  const current=useMemo(()=>state?.states?.find(x=>x.scope===scope),[state,scope])

  const searchTargets=async()=>{
    setBusy(true);setMessage('')
    try{
      const operation={provider:'providers_page',course:'courses_page',campus:'campuses_page',scholarship:'scholarships_page'}[entityType]
      const r=await adminRead(operation,{query:query||null,limit:10,offset:0,sort:'updated',direction:'desc'})
      setResults(list(r))
    }catch(e){setMessage(e?.message||String(e))}finally{setBusy(false)}
  }
  useEffect(()=>{setResults([]);setSelected(null);setState(null)},[entityType])

  const choose=async x=>{
    setSelected(x);setState(null);setMessage('')
    try{
      const{data,error}=await supabase.rpc('layer4_block_state',{p_entity_type:entityType,p_entity_id:itemId(x),p_block_scope:null})
      if(error)throw error
      setState(data)
    }catch(e){setMessage(e?.message||String(e))}
  }

  const decide=async eventType=>{
    if(!selected||!reason.trim())return setMessage('Select an entity and enter a reason code.')
    setBusy(true);setMessage('')
    try{
      const{error}=await supabase.rpc('layer4_block_decide',{
        p_entity_type:entityType,p_entity_id:itemId(selected),p_block_scope:scope,p_event_type:eventType,
        p_reason_code:reason.trim(),p_comment:comment.trim()||null,
        p_expires_at:expires?new Date(expires).toISOString():null,
        p_review_at:review?new Date(review).toISOString():null,
        p_approval_context:{surface:'m2.5-platform-admin',change_control:'CF-CHG-20260901-058'},
      })
      if(error)throw error
      setMessage((eventType==='block'?'Block':'Unblock')+' recorded. No canonical data was deleted or rewritten.')
      setReason('');setComment('');setExpires('');setReview('')
      const{data:next,error:nextError}=await supabase.rpc('layer4_block_state',{p_entity_type:entityType,p_entity_id:itemId(selected),p_block_scope:null})
      if(nextError)throw nextError
      setState(next)
      await reload()
    }catch(e){setMessage(e?.message||String(e))}finally{setBusy(false)}
  }

  return <div className="pm-stack">
    <section className="pm-panel"><SectionTitle icon={Blocks} title="Reversible Layer 4 block control" subtitle="Independent operational, publication, Search and quarantine state. Blocking is never deletion."/>
      <div className="pm-block-layout">
        <div className="pm-block-picker">
          <label><span>Entity type</span><select value={entityType} onChange={e=>setEntityType(e.target.value)}>{ENTITY_TYPES.map(([v,l])=><option key={v} value={v}>{l}</option>)}</select></label>
          <label className="pm-search-field"><span>Find target</span><div><input value={query} onChange={e=>setQuery(e.target.value)} placeholder={'Search '+entityType+'s'} onKeyDown={e=>{if(e.key==='Enter'){e.preventDefault();searchTargets()}}}/><button className="pm-button secondary" onClick={searchTargets} disabled={busy}><Search size={14}/>Search</button></div></label>
          <div className="pm-target-results">{results.length?results.map(x=><button key={itemId(x)} className={selected&&itemId(selected)===itemId(x)?'selected':''} onClick={()=>choose(x)}><strong>{itemLabel(x)}</strong><small>{x.stable_key||x.course_code||x.country_code||itemId(x)}</small></button>):<Empty>Search for a governed catalogue entity.</Empty>}</div>
        </div>

        <div className="pm-block-form">
          <div className="pm-selected-target"><span>Selected target</span><strong>{selected?itemLabel(selected):'None selected'}</strong>{selected&&<small>{itemId(selected)}</small>}</div>
          <label><span>Block scope</span><select value={scope} onChange={e=>setScope(e.target.value)}>{BLOCK_SCOPES.map(([v,l])=><option key={v} value={v}>{l}</option>)}</select></label>
          <div className="pm-current-state"><span>Current state</span>{current?<Pill tone={current.blocked?'danger':'success'}>{current.blocked?'Blocked':'Unblocked'}</Pill>:<Pill>Never decided</Pill>}</div>
          <label><span>Reason code *</span><input value={reason} onChange={e=>setReason(e.target.value)} placeholder="e.g. DATA_QUALITY_REVIEW"/></label>
          <label><span>Comment</span><textarea value={comment} onChange={e=>setComment(e.target.value)} rows="3" placeholder="Decision context or Evidence reference"/></label>
          <div className="pm-two-col compact"><label><span>Review at</span><input type="datetime-local" value={review} onChange={e=>setReview(e.target.value)}/></label><label><span>Expires at</span><input type="datetime-local" value={expires} onChange={e=>setExpires(e.target.value)}/></label></div>
          {message&&<div className="pm-inline-message">{message}</div>}
          <div className="pm-action-row"><button className="pm-button danger" onClick={()=>decide('block')} disabled={busy||rank<5||!selected}><Blocks size={14}/>Block scope</button><button className="pm-button secondary" onClick={()=>decide('unblock')} disabled={busy||rank<5||!selected}><CheckCircle2 size={14}/>Unblock scope</button></div>
          <p className="pm-note">Server enforcement from CF-057 remains authoritative. Provider blocks can inherit to child Courses/Campuses/Provider-owned Scholarships depending on scope.</p>
        </div>
      </div>
    </section>

    <section className="pm-panel"><SectionTitle icon={Blocks} title="Active blocks" subtitle={blocks.length+' currently effective block decision(s)'}/>
      {!blocks.length?<Empty>No active Layer 4 blocks.</Empty>:<div className="pm-table-wrap"><table className="pm-table"><thead><tr><th>Entity</th><th>Scope</th><th>Reason</th><th>Review</th><th>Expiry</th><th>Created</th></tr></thead><tbody>{blocks.map(x=><tr key={x.decision_id}><td><strong>{x.entity_name}</strong><small>{title(x.entity_type)+(x.provider_name&&x.entity_type!=='provider'?' · '+x.provider_name:'')}</small></td><td><Pill tone="danger">{title(x.scope)}</Pill></td><td>{x.reason_code}<small>{x.comment}</small></td><td>{fmtDate(x.review_at)}</td><td>{fmtDate(x.expires_at)}</td><td>{fmtDate(x.created_at)}</td></tr>)}</tbody></table></div>}
    </section>
  </div>
}
