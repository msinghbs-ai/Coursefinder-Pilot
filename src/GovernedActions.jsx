// CF-247 v2.15.360 (Decision 268, Platform Admin 27 Oct 2026 21:57 and 22:00): governed actions on Layer 2/3 › Operations. Routine operations
// that were SQL pastes are run here instead: one allowlisted action at a time, Platform Admin only. The page previews the action against the
// live system (every precondition with its expected and actual value, a rolled-back dry run, the action hash and when the approval expires),
// then runs it once on an explicit approval with a reason. A repeated click sends the same idempotency key and gets the first result back.
// Success, refusal and failure are shown as recorded, with the post-checks and the audit event. Reads and runs public.admin_governed_action;
// the server checks the role and every precondition again. First and only action: close the AER PR A recovery (adopts the recovery that is
// already open; it starts nothing).
import React,{useEffect,useState}from'react'
import{RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Loading,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'
import{ReasonAction}from'./ProviderOnboarding'
import{plainError}from'./lib/errors'

const ACTION='aer_pr_a_recovery_close'
const SLUG={norway:'Norway',qatar:'Qatar',singapore:'Singapore','sri-lanka':'Sri Lanka',thailand:'Thailand','united-kingdom':'United Kingdom',vietnam:'Vietnam',nigeria:'Nigeria',
  'foundation-equivalencies':'Foundation equivalencies','global-assessment-certificate':'Global Assessment Certificate','international-baccalaureate':'International Baccalaureate'}
const SCOPE={'9d22a19e-c3f7-4012-b738-17bc0b481e7f':'UTS','1719c3ba-1ddf-483e-935e-c750124ba99c':'WSU','8e1adb6c-e069-43db-9584-bd054255e702':'RMIT'}
const names=list=>(Array.isArray(list)?list:[]).map(id=>SCOPE[id]||id).join(', ')||'—'
const outcome=r=>r.state==='done'?`Complete ${fmtNumber(r.matched)}/${fmtNumber(r.expected)} · Layer 4 ${r.item_status||'—'}`:String(r.error||r.state||'').replace(/^held_unparsed: /,'Held before any AI read: ').replace(/^held_incomplete: /,'Held after its last attempt: ')
const newKey=()=>globalThis.crypto?.randomUUID?globalThis.crypto.randomUUID():'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,c=>{const r=Math.random()*16|0;return(c==='x'?r:(r&3|8)).toString(16)})

function Checks({checks}){
  return <table className="cf-table" data-governed-checks><thead><tr><th>Precondition</th><th>Expected</th><th>Now</th><th>Result</th></tr></thead>
    <tbody>{(checks||[]).map(c=><tr key={c.check} data-governed-check={c.ok?'pass':'fail'}><td>{c.check}</td>
      <td><small>{typeof c.expected==='object'?(Array.isArray(c.expected)?names(c.expected):'unchanged'):String(c.expected)}</small></td>
      <td><small>{typeof c.actual==='object'?(Array.isArray(c.actual)?names(c.actual):(c.ok?'unchanged':'changed')):String(c.actual)}</small></td>
      <td><StatusChip tone={c.ok?'success':'danger'} label={c.ok?'Pass':'Fails'}/></td></tr>)}</tbody></table>
}

export default function GovernedActions({onError}){
  const[d,setD]=useState(null),[p,setP]=useState(null),[res,setRes]=useState(null),[busy,setBusy]=useState(false),[key,setKey]=useState('')
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_governed_action',{p_action:'read',p_args:{}});if(error)throw error;setD(data||{})}catch(e){onError?.(plainError(e))}}
  useEffect(()=>{load()},[])
  const preview=async()=>{setBusy(true);setRes(null);try{const{data,error}=await supabase.rpc('admin_governed_action',{p_action:'preview',p_args:{action:ACTION}});if(error)throw error;setP(data||null);setKey(newKey())}catch(e){onError?.(plainError(e))}finally{setBusy(false)}}
  // the key is made with the preview and sent with every click on its approval, so a repeated click or a retry cannot run the action twice
  const approve=async reason=>{setBusy(true);try{const{data,error}=await supabase.rpc('admin_governed_action',{p_action:'approve',p_args:{action:ACTION,preview_id:p.preview_id,action_hash:p.action_hash,idempotency_key:key,reason}});if(error)throw error;setRes(data||{});await load()}catch(e){onError?.(plainError(e));throw e}finally{setBusy(false)}}
  if(!d)return <Loading label="Reading governed actions…"/>
  const a=(d.actions||[])[0]||{},s=(p?.snapshot)||d.snapshot||{},expired=p&&new Date(p.expires_at)<new Date()
  return <section className="m-panel" data-governed-actions>
    <h3 className="sl-h4">Governed actions</h3>
    <p className="sd-desc">Operations approved here instead of run as SQL (Decision 268). Each is checked against the live system, tried in a dry run that is rolled back, and runs once on your approval; the server checks everything again before it runs.</p>
    <div className="cf-card" data-governed-action={ACTION}>
      <div className="sd-actions"><strong>{a.label}</strong>
        <StatusChip tone={a.done?'success':a.paused?'danger':'warning'} label={a.done?'Done':a.paused?`Paused after ${fmtNumber(a.failed_attempts)} failed attempts`:'Ready to review'}/>
        <Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>Refresh</Button></div>
      <p className="sd-desc">{a.what}</p>
      <table className="cf-table" data-governed-outcomes><thead><tr><th>Recovery run</th><th>Outcome</th><th className="num">Attempts</th><th className="num">Cost since it opened (US$)</th></tr></thead>
        <tbody>{(s.runs||[]).map(r=><tr key={r.run} data-governed-run={r.slug}><td>{SLUG[r.slug]||r.slug}</td><td><small>{outcome(r)}</small></td><td className="num">{fmtNumber(r.attempts)}</td><td className="num">{Number(r.cost_since_open||0).toFixed(4)}</td></tr>)}</tbody></table>
      <ul className="sd-desc" data-governed-counts>
        <li>RMIT entry rows: {fmtNumber(s.counts?.active)} active, {fmtNumber(s.counts?.proposed)} proposed (in {fmtNumber(s.counts?.items_pending)} Layer 4 items, not admitted by this action), {fmtNumber(s.counts?.quarantined)} quarantined.</li>
        <li>Cost of the recovery: US${Number(s.cost_usd_since_open||0).toFixed(4)} <small>({s.cost_basis})</small></li>
        <li data-governed-scope>Reading scope now: {names(s.scope?.now)}. After this action: {names(s.scope?.after)}.</li>
        <li>Left as they are: {(s.untouched||[]).map(u=>SLUG[u.slug]||u.slug).join(', ')}.</li>
        {s.refresh_due&&<li>Until it runs, no RMIT page is read again before {fmtDateTime(s.refresh_due)} (the 30-day refresh).</li>}
      </ul>
      {!a.done&&<div className="sd-actions"><Button compact variant="primary" onClick={preview} disabled={busy||a.paused} data-governed-preview>{p?'Preview again':'Preview against the live system'}</Button></div>}
      {p&&!a.done&&<div data-governed-preview-result>
        <Checks checks={s.checks}/>
        <p className="sd-desc" data-governed-dry-run>Dry run: {p.dry_run?.ok?`scope would become ${names(p.dry_run.scope_after)}; RMIT ${p.dry_run.rmit_in_scope_after?'still in scope':'out of scope'}; rolled back.`:`failed: ${p.dry_run?.error||'unknown'}`}</p>
        <p className="sd-desc"><small>Action hash {p.action_hash} · preview {p.preview_id} · approval valid until {fmtDateTime(p.expires_at)}</small></p>
        {p.ok&&!expired?<ReasonAction label="Approve and run" confirm="Run once" variant="primary" testid="governed-approve" disabled={busy} onDo={approve}/>
          :<p className="sd-desc" role="status" data-governed-blocked>{expired?'This preview has expired; preview again.':'Cannot be approved: a precondition fails or the action is paused.'}</p>}
      </div>}
      {res&&<div role="status" data-governed-result={res.state}>
        <StatusChip tone={res.state==='done'?'success':res.state==='cancelled'?'warning':'danger'} label={res.state==='done'?'Done':res.state==='cancelled'?'Refused':'Failed; nothing changed'}/>
        {res.repeated&&<small className="sd-desc"> Already ran with this approval; nothing was run again.</small>}
        {res.why&&<p className="sd-desc">{res.why}</p>}
        {res.error&&<p className="sd-desc">{res.error}</p>}
        {res.post_checks&&<ul className="sd-desc" data-governed-post>{Object.entries(res.post_checks).map(([k,v])=><li key={k}>{k.replace(/_/g,' ')}: {v?'yes':'no'}</li>)}</ul>}
        {res.audit_event&&<small className="sd-desc">Audit event {res.audit_event} · task {res.id}</small>}
      </div>}
      {(d.history||[]).length>0&&<details className="sd-desc"><summary>History ({fmtNumber(d.history.length)})</summary><ul data-governed-history>{d.history.map(h=><li key={h.id}>{fmtDateTime(h.at)} · {h.state==='cancelled'?'refused':h.state} · {h.reason}{h.result?.why?` · ${h.result.why}`:''}</li>)}</ul></details>}
    </div>
  </section>
}
