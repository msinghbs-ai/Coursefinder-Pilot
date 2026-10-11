import React,{useEffect,useState}from'react'
import{StatusChip,Metric as KitMetric,SectionTitle as KitSectionTitle,Empty}from'./ui-kit'
import{
  Activity,AlertTriangle,Archive,CheckCircle2,Database,HardDrive,RefreshCw,
  ServerCog,ShieldCheck,SlidersHorizontal,TestTube2
}from'lucide-react'
import{fmtDateTime,fmtNumber as fmtNum,fmtPercent}from'./lib/format.js'
import{adminRead,supabase}from'./lib/supabase'
import'./platform-maturity.css'

// Clean-up batch 2 (9 Oct 2026): the unused fallback tab navigation (no view) and the Current Layer 2 wave panel were removed.
// v2.15.253 (Platform Admin, 12 Oct 2026): view 'blocks' (Layer 4 › Blocks) retired with its tab; blocks already recorded stay enforced by the server.
const num=v=>Number(v||0)
const fmtNumber=v=>fmtNum(num(v))
const fmtDate=v=>fmtDateTime(v)
const fmtBytes=v=>{const n=num(v);if(!n)return'0 B';const u=['B','KB','MB','GB','TB'],i=Math.min(Math.floor(Math.log(n)/Math.log(1024)),u.length-1);return (n/1024**i).toFixed(i<2?0:2)+' '+u[i]}
const title=v=>String(v||'').replace(/[_-]+/g,' ').replace(/\b\w/g,x=>x.toUpperCase())
const toneFor=v=>{const x=String(v||'').toLowerCase();if(['pass','passed','pilot_uat_pass','pilot_qualified','accepted_baseline','healthy','enabled','published'].includes(x))return'success';if(['warning','designed','registered','internal','active'].includes(x))return'warning';if(['critical','error','failed','blocked','not_run','disabled'].includes(x))return'danger';return'neutral'}
const list=v=>v?.items??v?.rows??(Array.isArray(v)?v:[])

function Pill({children,tone='neutral'}){return <StatusChip tone={tone} label={children}/>}
function Metric({label,value,detail,tone='neutral',Icon=Database}){return <KitMetric icon={Icon} label={label} value={value} detail={detail} tone={tone}/>}
function SectionTitle({icon=ServerCog,title,subtitle,action}){return <KitSectionTitle icon={icon} title={title} subtitle={subtitle} action={action}/>}


// v2.15.123 (screen review: no tabs inside tabs; readiness gates and UAT belong with the go-live checklist; Layer 4 blocks
// belong in Layer 4): view 'capacity' = Platform health › Capacity (overview, capacity, performance as sections);
// view 'golive' = Platform settings › Go-live checklist (environment gates, UAT).
const VIEW_TITLE={capacity:['Capacity and integrity','Database size, evidence storage, workloads and retention.'],golive:['Readiness gates and UAT','What must pass before Production is switched on.']}
export default function PlatformMaturity({rank,onError,view=''}){
  const[environment,setEnvironment]=useState('pilot')
  const[data,setData]=useState({readiness:null,capacity:null,gates:null,uat:null,workloads:null,retention:null})
  const[busy,setBusy]=useState(true),[error,setError]=useState('')
  const load=async()=>{
    setBusy(true);setError('')
    try{
      const[readiness,capacity,gates,uat,workloads,retention]=await Promise.all([
        adminRead('platform_readiness'),
        adminRead('platform_capacity',{environment}),
        adminRead('platform_environment_gates',{environment}),
        adminRead('platform_uat_catalogue',{limit:100,offset:0}),
        adminRead('platform_workloads'),
        adminRead('platform_retention',{environment}),
      ])
      setData({readiness,capacity,gates,uat,workloads,retention})
    }catch(e){const msg=e?.message||String(e);setError(msg);onError?.(msg)}finally{setBusy(false)}
  }
  useEffect(()=>{load()},[environment])

  const uatItems=list(data.uat)
  const prodOpen=uatItems.filter(x=>(x.environment_scope==='production'||x.environment_scope==='both')&&x.hard_gate&&x.status!=='pass')
  const acceptedPilot=uatItems.filter(x=>x.environment_scope==='pilot'&&x.status==='accepted_baseline')
  const cap=data.capacity||{},integrity=cap.integrity_classification||{},policy=cap.platform_capacity_policy||{},evidencePolicy=cap.evidence_capacity_policy||{}
  const productionEnabled=num(data.readiness?.production_source_capabilities_enabled)+num(data.readiness?.production_scrapers_enabled)+num(data.readiness?.production_ai_profiles_enabled)

  const[vt,vs]=VIEW_TITLE[view]||['Platform operations & readiness','Environment gates, capacity, UAT, retention, and workload budgets.']
  return <div className="pm-shell" data-platform-maturity="true" data-view={view||'all'}>
    <section className="pm-hero">
      <div className="pm-hero-copy"><h2>{vt}</h2><p>{vs}</p></div>
      <div className="pm-hero-actions"><label className="pm-env-control"><span>View environment</span><select value={environment} onChange={e=>setEnvironment(e.target.value)}><option value="pilot">Pilot</option><option value="production">Production</option></select></label><button className="pm-button secondary" onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Refreshing…':'Refresh'}</button></div>
    </section>

    <section className="pm-boundary-banner">
      <ShieldCheck size={18}/>
      <div><strong>Production boundary remains closed</strong><span>No Production project is provisioned. This view is read-only; it cannot enable Production sources, scrapers, AI profiles, PITR or destructive purge.</span></div>
      <Pill tone={productionEnabled?'danger':'success'}>{productionEnabled?'Unexpected Production enablement':'0 Production enablement expected'}</Pill>
    </section>

    {error&&<div className="pm-alert"><AlertTriangle size={16}/><span>{error}</span></div>}

    {busy&&!data.readiness?<div className="pm-loading"><span className="pm-spinner"/>Loading…</div>:view==='capacity'?<>
      <Overview readiness={data.readiness} capacity={cap} acceptedPilot={acceptedPilot} prodOpen={prodOpen}/>
      <Capacity capacity={cap} integrity={integrity} policy={policy} evidencePolicy={evidencePolicy}/>
      <Performance workloads={list(data.workloads)} retention={data.retention}/>
    </>:view==='golive'?<>
      <Gates gates={data.gates} environment={environment}/>
      <Uat items={uatItems}/>
    </>:null}
  </div>
}

function Overview({readiness,capacity,acceptedPilot,prodOpen}){
  return <div className="pm-stack">
    <div className="pm-metric-grid">
      <Metric Icon={ShieldCheck} label="Production source capabilities" value={fmtNumber(readiness?.production_source_capabilities_enabled)} detail="Expected 0 before provisioning" tone={num(readiness?.production_source_capabilities_enabled)?'danger':'success'}/>
      <Metric Icon={SlidersHorizontal} label="Production scrapers" value={fmtNumber(readiness?.production_scrapers_enabled)} detail="Environment-gated" tone={num(readiness?.production_scrapers_enabled)?'danger':'success'}/>
      <Metric Icon={Activity} label="Production AI profiles" value={fmtNumber(readiness?.production_ai_profiles_enabled)} detail="Separate benchmark required" tone={num(readiness?.production_ai_profiles_enabled)?'danger':'success'}/>
      <Metric Icon={TestTube2} label="Open Production hard gates" value={fmtNumber(readiness?.production_uat_open)} detail={prodOpen.length+' visible in catalogue'} tone={num(readiness?.production_uat_open)?'warning':'success'}/>
      <Metric Icon={HardDrive} label="Evidence storage" value={fmtBytes(capacity?.evidence_object_bytes)} detail={fmtNumber(capacity?.evidence_object_count)+' objects · '+fmtPercent(num(capacity?.evidence_planning_capacity_pct))+' planning envelope'} tone={toneFor(capacity?.severity)}/>
      <Metric Icon={CheckCircle2} label="Accepted Pilot UAT domains" value={fmtNumber(acceptedPilot.length)} detail="Accepted at the Pilot baseline" tone="success"/>
    </div>

    <section className="pm-panel"><SectionTitle icon={Archive} title="Governance inventory" subtitle="Counts of the main records the platform keeps."/>
      <div className="pm-inline-stats"><span><strong>{fmtNumber(readiness?.retention_policy_classes)}</strong> retention classes</span><span><strong>{fmtNumber(readiness?.performance_profiles)}</strong> workload profiles</span><span><strong>{fmtNumber(prodOpen.length)}</strong> Production UAT entries not passed</span></div>
    </section>
  </div>
}

function Capacity({capacity,integrity,policy,evidencePolicy}){
  return <div className="pm-stack">
    <div className="pm-metric-grid">
      <Metric Icon={Database} label="Logical database" value={fmtBytes(capacity?.database_bytes)} detail={'Warn '+fmtBytes(policy?.database_warn_bytes)+' · High '+fmtBytes(policy?.database_high_bytes)} tone={num(capacity?.database_bytes)>=num(policy?.database_warn_bytes)?'warning':'success'}/>
      <Metric Icon={HardDrive} label="Evidence storage" value={fmtBytes(capacity?.evidence_object_bytes)} detail={fmtNumber(capacity?.evidence_object_count)+' objects'} tone={toneFor(capacity?.severity)}/>
      <Metric Icon={Activity} label="Planning utilisation" value={fmtPercent(num(capacity?.evidence_planning_capacity_pct))} detail="Against a 60 GiB planning figure (not the hosting limit)" tone={num(capacity?.evidence_planning_capacity_pct)>=num(evidencePolicy?.warn_pct)?'warning':'success'}/>
      <Metric Icon={AlertTriangle} label="Integrity severity" value={title(capacity?.severity||'unknown')} detail={'Severity input '+fmtNumber(capacity?.integrity_count_for_severity)} tone={toneFor(capacity?.severity)}/>
    </div>

    <section className="pm-panel"><SectionTitle icon={AlertTriangle} title="Evidence lineage classification" subtitle="Stored pages counted as fetched, with proven duplicates, past corrections and open problems shown separately. Nothing is cleaned up from here."/>
      <div className="pm-kv-grid">
        <div><span>Raw unlinked Storage objects</span><strong>{fmtNumber(capacity?.unlinked_storage_object_count_raw)}</strong></div>
        <div><span>Proven duplicates</span><strong>{fmtNumber(capacity?.duplicate_unlinked_storage_object_count)}</strong></div>
        <div><span>Reconciled historical orphans</span><strong>{fmtNumber(capacity?.reconciled_historical_orphan_count)}</strong></div>
        <div><span>Unresolved orphan objects</span><strong>{fmtNumber(integrity?.unresolved_orphan_objects)}</strong></div>
        <div><span>Raw missing Storage refs</span><strong>{fmtNumber(capacity?.missing_storage_object_count_raw)}</strong></div>
        <div><span>Reconciled legacy refs</span><strong>{fmtNumber(capacity?.reconciled_legacy_reference_count)}</strong></div>
        <div><span>Unresolved missing Storage objects</span><strong>{fmtNumber(capacity?.missing_storage_object_count)}</strong></div>
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
