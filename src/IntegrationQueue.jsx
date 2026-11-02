// Platform health › Integration queue (CF-247 continuous validation mandate, Platform Admin 2 Nov 2026 16:58, §3, §9, §13).
// The persistent integration feedback queue: every failure the scheduled checks (V4), the deployment checks (V3), Platform health and the
// work-queue watchdog find, grouped by fingerprint, with its owner, fix, deployment and verification, and the current operating mode.
// Read only; PIM Admin and above (checked again on the server: public.admin_integration_queue). Issues are moved and closed by the
// Integration Controller, never from this screen.
import React,{useEffect,useMemo,useState}from'react'
import{AlertTriangle,CheckCircle2,GitBranch,History,RefreshCw,RotateCcw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,Metric,SectionTitle,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'
import{plainError}from'./lib/errors'

export const IQ_STATUS={
  detected:{label:'Detected',tone:'warning'},triaged:{label:'Triaged',tone:'warning'},assigned:{label:'Assigned',tone:'info'},
  in_progress:{label:'In progress',tone:'info'},code_ready:{label:'Code ready',tone:'info'},integration_testing:{label:'Integration testing',tone:'info'},
  deployed:{label:'Deployed',tone:'info'},production_verification:{label:'Production verification',tone:'info'},closed:{label:'Closed',tone:'success'},
  reopened:{label:'Reopened (regression)',tone:'danger'},
}
const STATUS_ORDER=['detected','triaged','assigned','in_progress','code_ready','integration_testing','deployed','production_verification','reopened','closed']
const SEV_TONE={P0:'danger',P1:'warning',P2:'neutral'}
export const WORKSTREAMS={A1:'Root cause',A2:'Layer 2',A3:'Adapters',A4:'Layer 4',A5:'Provider lifecycle',A6:'Country lifecycle',A7:'Scheduling',A8:'Integration',A9:'UI and monitoring',A10:'Quality and governance'}
const MODES={1:'Mode 1 — Active remediation',2:'Mode 2 — Steady-state monitoring'}
const SCOPES=[['open','Open'],['reopened','Reopened'],['closed','Closed'],['all','All']]
const st=s=>IQ_STATUS[s]||{label:s||'—',tone:'neutral'}

export default function IntegrationQueue({onError}){
  const[d,setD]=useState(null),[scope,setScope]=useState('open'),[open,setOpen]=useState(null),[hist,setHist]=useState(null)
  const load=async(sc=scope)=>{try{const{data,error}=await supabase.rpc('admin_integration_queue',{p_action:'summary',p_args:{scope:sc}});if(error)throw error;setD(data||{})}catch(e){onError?.(plainError(e));setD({issues:[]})}}
  useEffect(()=>{load(scope)},[scope])
  const show=async id=>{if(open===id){setOpen(null);setHist(null);return}setOpen(id);setHist(null);try{const{data,error}=await supabase.rpc('admin_integration_queue',{p_action:'issue',p_args:{id}});if(error)throw error;setHist(data||{})}catch(e){onError?.(plainError(e));setHist({events:[]})}}
  const issues=d?.issues||[]
  const bySt=d?.by_status||{},bySev=d?.by_severity||{},byWs=d?.by_workstream||{}
  const openTotal=useMemo(()=>Object.entries(bySt).filter(([k])=>k!=='closed').reduce((a,[,n])=>a+Number(n||0),0),[d])
  const verifying=Number(bySt.deployed||0)+Number(bySt.production_verification||0)
  if(!d)return <section className="m-panel"><Loading label="Reading the integration queue…"/></section>
  return <>
    <section className="m-panel" data-iq-summary>
      <SectionTitle icon={GitBranch} title="Integration queue" subtitle="Every failure the scheduled checks, deployment checks, Platform health and the work-queue watchdog find, one item per fingerprint. An item closes only after its fix is verified in production; if it comes back, the same item reopens as a regression."
        action={<Button compact onClick={()=>load(scope)}><RefreshCw size={14}/>Refresh</Button>}/>
      <p className="iq-mode" data-iq-mode={d.mode?.mode||''}><strong>{MODES[d.mode?.mode]||'Operating mode not recorded'}</strong>{d.mode&&<small> · set by {d.mode.set_by} on {fmtDateTime(d.mode.set_at)} · {d.mode.reason}</small>}</p>
      <div className="cf-metric-grid">
        <Metric label="Open" value={openTotal} icon={AlertTriangle} tone={openTotal?'warning':'neutral'} detail={`P0 ${fmtNumber(bySev.P0||0)} · P1 ${fmtNumber(bySev.P1||0)} · P2 ${fmtNumber(bySev.P2||0)}`}/>
        <Metric label="Verifying" value={verifying} icon={History} tone="info" detail="Deployed or in production verification"/>
        <Metric label="Reopened" value={Number(d.reopened||0)} icon={RotateCcw} tone={Number(d.reopened||0)?'danger':'neutral'} detail={`${fmtNumber(d.regressions_total||0)} regression(s) recorded`}/>
        <Metric label="Closed" value={Number(bySt.closed||0)} icon={CheckCircle2} tone="success" detail="Verified in production"/>
      </div>
      <div className="iq-counts">
        <div><h4>By status</h4><ul data-iq-by="status">{STATUS_ORDER.filter(k=>bySt[k]).map(k=><li key={k}><StatusChip value={k} tone={st(k).tone} label={st(k).label}/> {fmtNumber(bySt[k])}</li>)}</ul></div>
        <div><h4>Open by workstream</h4><ul data-iq-by="workstream">{Object.keys(WORKSTREAMS).filter(k=>byWs[k]).map(k=><li key={k}><strong>{k}</strong> {WORKSTREAMS[k]} · {fmtNumber(byWs[k])}</li>)}{!Object.keys(byWs).length&&<li>None open</li>}</ul></div>
        <div><h4>Checks</h4><ul><li>Scheduled checks {d.job_active?'on':'off'}{d.last_check?.at&&` · last run ${fmtDateTime(d.last_check.at)} (${fmtNumber(d.last_check.found||0)} seen)`}</li>
          {d.last_deploy_check&&<li>Last deployment check: {d.last_deploy_check.release} · {d.last_deploy_check.ok?'passed':'found problems'} · {fmtDateTime(d.last_deploy_check.at)}</li>}</ul></div>
      </div>
    </section>
    <section className="m-panel">
      <div className="iq-scopes" role="tablist">{SCOPES.map(([k,l])=><button key={k} type="button" role="tab" aria-selected={scope===k} className={scope===k?'m-primary compact':'m-secondary compact'} onClick={()=>{setScope(k);setOpen(null)}} data-iq-scope={k}>{l}</button>)}</div>
      {issues.length?<div className="cf-table-wrap"><table className="cf-table iq-table"><thead><tr><th>Issue</th><th>Severity</th><th>Status</th><th>Workstream</th><th>Layer</th><th className="num">Seen</th><th>Last seen</th></tr></thead><tbody>
        {issues.map(i=><React.Fragment key={i.id}><tr data-iq-issue={i.ref} onClick={()=>show(i.id)} className="iq-row">
          <td><strong>{i.ref}</strong> {i.title}<small className="qw-sub">{i.source} · {i.validation_layer}{i.root_cause&&i.root_cause!=='unclassified'?` · ${i.root_cause.replace(/_/g,' ')}`:''}{(i.providers||i.courses)?` · ${fmtNumber(i.providers)} provider(s), ${fmtNumber(i.courses)} course(s)${i.more_entities?' and more':''}`:''}{i.cleared_at?` · not seen since ${fmtDateTime(i.cleared_at)}`:''}</small></td>
          <td><StatusChip value={i.severity} tone={SEV_TONE[i.severity]||'neutral'} label={i.severity}/></td>
          <td><StatusChip value={i.status} tone={st(i.status).tone} label={st(i.status).label}/>{i.regressions>0&&<small className="qw-sub">{fmtNumber(i.regressions)} regression(s)</small>}</td>
          <td title={WORKSTREAMS[i.workstream]||''}>{i.workstream}</td>
          <td>{i.layer}</td>
          <td className="num">{fmtNumber(1+Number(i.retry_count||0))}</td>
          <td>{fmtDateTime(i.last_observed_at)}</td>
        </tr>
        {open===i.id&&<tr className="iq-detail"><td colSpan={7}>{!hist?<Loading label="Reading its history…"/>:<IssueDetail h={hist}/>}</td></tr>}</React.Fragment>)}
      </tbody></table></div>:<Empty icon={CheckCircle2} text={scope==='open'?'Nothing open.':'Nothing here.'}/>}
    </section>
  </>
}

function IssueDetail({h}){
  const i=h.issue||{}
  return <div className="iq-history" data-iq-history={i.issue_ref}>
    <dl className="iq-facts">
      <dt>Failure</dt><dd>{i.failure}</dd><dt>Expected</dt><dd>{i.expected}</dd>
      {i.impact&&<><dt>Impact</dt><dd>{i.impact}</dd></>}
      <dt>Detected</dt><dd>{fmtDateTime(i.detected_at)} by {i.detection_source}</dd>
      {(i.depends_on||[]).length>0&&<><dt>Depends on</dt><dd>{i.depends_on.join('; ')}</dd></>}
      {(i.blocked_by||[]).length>0&&<><dt>Blocked by</dt><dd>{i.blocked_by.map(b=>`IQ-${String(b).padStart(5,'0')}`).join(', ')}</dd></>}
      {(i.fix_commit||i.fix_migration)&&<><dt>Fix</dt><dd>{[i.fix_commit,i.fix_migration].filter(Boolean).join(' · ')}</dd></>}
      {i.deployed_version&&<><dt>Deployed</dt><dd>{i.deployed_version}</dd></>}
      {i.verification_outcome&&<><dt>Verification</dt><dd>{i.verification_outcome}{i.verified_by?` by ${i.verified_by}`:''}{i.verified_at?` on ${fmtDateTime(i.verified_at)}`:''}</dd></>}
      {(i.country_codes||[]).length>0&&<><dt>Countries</dt><dd>{i.country_codes.join(', ')}</dd></>}
      {(i.evidence_refs||[]).length>0&&<><dt>Evidence</dt><dd>{i.evidence_refs.join('; ')}</dd></>}
      {i.aer_root_cause_ref&&<><dt>AER root cause</dt><dd>{i.aer_root_cause_ref}</dd></>}
    </dl>
    <h4>History</h4>
    {(h.events||[]).length?<ul className="qw-list">{h.events.map(e=><li key={e.id} data-iq-event={e.kind}><strong>{e.kind.replace(/_/g,' ')}</strong>{e.to_status&&e.from_status!==e.to_status?` · ${st(e.from_status).label} → ${st(e.to_status).label}`:''}<small>{e.actor} · {fmtDateTime(e.at)}{e.note?` · ${e.note}`:''}</small></li>)}</ul>:<Empty text="No history yet."/>}
  </div>
}
