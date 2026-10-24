// Settings register and policy tables (v2.15.269, CF-247). Platform Admin, 13 Oct 2026 21:43: "Bring all controls to UI and make sure in future
// it's not getting hard coded. All controls need to be reflected and control in UI. Use current recommended settings and choices."
// Every job size, re-read and retry time and onboarding rule the platform runs on is a setting here (toolset "pipeline" in the same settings
// table as Toolsets & limits); the jobs and functions read it each time they run, so a change applies on the next run. Each setting says what
// uses it. The controls check lists any running job that still has a number written into it (it should be empty). Policy tables (capacity,
// evidence storage, retention, provider fee rules) are changed here too. Every change needs a reason and is logged.
// Reads: admin_settings_register_read(), admin_policy_tables_read(). Writes: admin_toolsets_write('setting'), admin_policy_tables_write
// (Platform Admin). Migration 20261013012900.
import React,{useEffect,useState}from'react'
import{Check,Save,ShieldCheck,TriangleAlert}from'lucide-react'
import{supabase}from'./lib/supabase'
import Card from'./Card'
import{Button,Empty,Loading,fmtDateTime}from'./ui-kit'
import{fmtNumber}from'./lib/format.js'
import{plainError}from'./lib/errors'

const errText=e=>plainError(e) // v2.15.341 (UI audit Phase 0): one plain reading, no internals
const slug=s=>String(s||'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'')
const SECTION_HELP={'Job sizes':'How much each scheduled job takes in a run. The job reads the value each time it runs.',
  'Re-read and retry':'How often pages are read again, and when failed work is tried again.',
  'Onboarding':'The rules the onboarding journey follows for each university.',
  'Housekeeping':'The weekly hygiene check: when something counts as unused, and how long a retired component is kept before it is dropped (Decision 260). Storage & retention: how long job logs, adapter screenshots and hourly resource readings are kept, and how much each clean-up run removes.',
  'Admission checks':'Checks a value must pass before it is admitted automatically: adapter fees against the registered course total, and AI readings of central pages (English policy, academic calendar) for the top providers.',
  'Waste rules':'Stops work that keeps failing or finds nothing: pauses idle jobs, caps retries by how often they still succeed, freezes values two automatic jobs keep changing, reuses stored pages, and limits course-page search to the providers that matter most. What is stopped is recorded and flagged.',
  'Flags':'The flag unit: how many tries before a soft reason holds an item, the free recheck and trial-run back-offs, when a worker job counts as running empty, and who may raise or release flags (Coverage & completeness › Flags).',
  'Logos':'Provider logos: who may upload or find one, and how the logo finder works through providers with no logo (job logo-find).',
  'Website API':'What the website (Wix) is given: whether rankings and logos may be displayed, how long logo links last, the sync page size, and calls a minute per key on the website-api-v2 URL.',
  'Zoho API':'Zoho API v2 (zoho-api-v2): calls a minute per key, page sizes, how long logo links last, the countries in the Zoho change stream and CSV export, and how long single calls stay in the request log (Operations › API usage).'}

// One setting: value, range and unit, what uses it, the last change; Save asks for a reason inline.
function SettingRow({s,can,onSave}){
  // CF-247 16 Oct 2026: a list setting (for example the Zoho countries) is edited as comma-separated values
  const shown=x=>Array.isArray(x)?x.join(', '):String(x??'')
  const[v,setV]=useState(shown(s.value)),[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[err,setErr]=useState('')
  useEffect(()=>{setV(shown(s.value))},[s.value])
  // v2.15.277: a yes/no setting (kind boolean) is chosen from Yes or No; numbers as before
  const yn=s.kind==='boolean',ls=s.kind==='list',n=Number(v)
  const list=v.split(',').map(x=>x.trim()).filter(Boolean)
  const changed=yn?v!==String(s.value):ls?v.trim()!==shown(s.value):v!==''&&n!==Number(s.value)
  const valid=yn||(ls?list.length>0:(Number.isFinite(n)&&(s.min==null||n>=Number(s.min))&&(s.max==null||n<=Number(s.max))))
  const save=async()=>{setBusy(true);setErr('');try{await onSave(s.key,yn?v==='true':ls?list:n,reason.trim());setReason('')}catch(e){setErr(errText(e))}finally{setBusy(false)}}
  return <div className="sr-row" data-register-setting={s.key}>
    <div className="sr-text"><strong>{s.label}</strong>{s.help&&<small>{s.help}</small>}<small className="sr-used">Used by: {s.used_by||'—'}</small>
      {s.updated_at&&<small className="sr-meta">{s.reason||'—'} · {fmtDateTime(s.updated_at)}</small>}</div>
    <div className="sr-edit">
      {can?<>
        <label className="sr-value"><span className="sr-hide">{s.label}</span>{yn?<select className="fv-input" value={v} onChange={e=>setV(e.target.value)}><option value="true">Yes</option><option value="false">No</option></select>
          :ls?<input className="fv-input" type="text" value={v} onChange={e=>setV(e.target.value)}/>
          :<input className="fv-input" type="number" inputMode="numeric" min={s.min??undefined} max={s.max??undefined} value={v} onChange={e=>setV(e.target.value)}/>}{!yn&&!ls&&<span>{s.unit}</span>}</label>
        {changed&&<label className="sr-reason"><span className="sr-hide">Reason</span><input className="fv-input" placeholder="Reason (kept in the log)" value={reason} onChange={e=>setReason(e.target.value)}/></label>}
        {changed&&<Button compact variant="primary" disabled={busy||!valid||reason.trim().length<4} onClick={save}><Save size={13}/>Save</Button>}
        {changed&&!valid&&<small className="fr-error">{ls?'At least one value.':<>Between {fmtNumber(Number(s.min))} and {fmtNumber(Number(s.max))}.</>}</small>}
        {err&&<small className="fr-error" role="alert">{err}</small>}
      </>:<strong>{yn?(String(s.value)==='true'?'Yes':'No'):ls?shown(s.value):<>{fmtNumber(Number(s.value))} {s.unit}</>}</strong>}
      <small className="sr-range">{!yn&&!ls&&s.min!=null?`${fmtNumber(Number(s.min))} to ${fmtNumber(Number(s.max))}`:''}</small>
    </div>
  </div>
}

export default function SettingsRegister({onError}){
  const[d,setD]=useState(null),[failed,setFailed]=useState('')
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_settings_register_read');if(error)throw error;setD(data||{})}catch(e){setFailed(errText(e));onError?.(errText(e))}}
  useEffect(()=>{load()},[])
  const save=async(key,value,reason)=>{const{error}=await supabase.rpc('admin_toolsets_write',{p_action:'setting',p_args:{toolset:'pipeline',key,value,reason}});if(error)throw error;await load()}
  if(!d)return <section className="m-panel" data-settings-register>{failed?<Empty text={`Settings could not be loaded: ${failed}`}/>:<Loading label="Loading settings…"/>}</section>
  const can=Boolean(d.can_manage),check=d.check||[]
  return <div className="m-page-stack" data-settings-register data-anchor="settings-register">
    <div className={`sr-check ${check.length?'is-bad':'is-ok'}`} data-controls-check={check.length?'fixed':'ok'} role="status">
      {check.length?<TriangleAlert size={16} aria-hidden/>:<ShieldCheck size={16} aria-hidden/>}
      {check.length?<span><strong>{check.length} running job{check.length===1?' has':'s have'} a number written into it.</strong> It should read a setting here: {check.map(c=>c.job).join(', ')}.</span>
        :<span><strong>Controls check: all {fmtNumber(Number(d.jobs||0))} running jobs read their sizes from settings.</strong> Nothing is fixed in a job.</span>}
    </div>
    {!can&&<p className="l3v-note">You can see every setting. Only a Platform Admin can change one.</p>}
    {(d.sections||[]).map(sec=><Card key={sec.section} id={`settings.register.${slug(sec.section)}`} title={sec.section} subtitle={SECTION_HELP[sec.section]||''}
        data-register-section={sec.section} data-anchor={`register:${sec.section}`} meta={<span className="cf-chip tone-neutral">{fmtNumber(sec.settings.length)} settings</span>}>
      {sec.settings.map(s=><SettingRow key={s.key} s={s} can={can} onSave={save}/>)}
    </Card>)}
    <PolicyTables can={can} onError={onError}/>
  </div>
}

// ---- policy tables: the safe columns of each, editable with a reason --------------------------------------------------------------------
const TABLE={platform_capacity_policy:['Capacity thresholds','When database size, temporary files and integrity findings raise a warning, high or critical.'],
  evidence_capacity_policy:['Evidence storage thresholds','Planned evidence storage and the levels that raise a warning.'],
  retention_class_policies:['Retention rules','How long each kind of record is kept, and the most removed at a time. Purging itself is on Platform health › Storage & retention.'],
  provider_fee_profiles:['Provider fee profiles','Approved fee rules per provider. Switch one off, or set when it is reviewed. New rules come through approvals.'],
  provider_fee_basis_rules:['Provider fee basis rules','Approved rules that admit tuition by its basis. Switch one off, or set when it is reviewed.']}
const ROW_LABEL={platform_capacity_policy:r=>r.environment,evidence_capacity_policy:()=>'Evidence storage',retention_class_policies:r=>r.class_key,
  provider_fee_profiles:(r,p)=>`${p[r.provider_id]||r.provider_id} · ${r.rule_code||''}`,provider_fee_basis_rules:(r,p)=>`${p[r.provider_id]||r.provider_id} · ${r.rule_code}`}

function PolicyCell({t,row,col,can,onSave}){
  const cur=row[col.col],isBool=col.type==='boolean',isDate=col.type==='date'
  const[v,setV]=useState(cur==null?'':String(cur)),[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[err,setErr]=useState('')
  useEffect(()=>{setV(cur==null?'':String(cur))},[cur])
  const changed=v!==(cur==null?'':String(cur))
  const save=async()=>{setBusy(true);setErr('');try{await onSave(t.table,String(row[t.key]),col.col,isBool?v==='true':isDate?v:Number(v),reason.trim());setReason('')}catch(e){setErr(errText(e))}finally{setBusy(false)}}
  if(!can)return <span>{isBool?(cur?'Yes':'No'):cur==null?'—':isDate?cur:fmtNumber(Number(cur))}</span>
  return <span className="sr-cell" data-policy-cell={`${t.table}.${col.col}:${row[t.key]}`}>
    {isBool?<label><input type="checkbox" checked={v==='true'} onChange={e=>setV(String(e.target.checked))}/> {v==='true'?'Yes':'No'}</label>
      :<input className="fv-input" aria-label={col.label} type={isDate?'date':'number'} min={isDate?undefined:0} value={v} onChange={e=>setV(e.target.value)}/>}
    {changed&&<><input className="fv-input" aria-label="Reason" placeholder="Reason" value={reason} onChange={e=>setReason(e.target.value)}/>
      <Button compact variant="primary" disabled={busy||reason.trim().length<4||(!isBool&&v==='')} onClick={save}><Check size={13}/>Save</Button></>}
    {err&&<small className="fr-error" role="alert">{err}</small>}
  </span>
}

function PolicyTables({can,onError}){
  const[d,setD]=useState(null)
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_policy_tables_read');if(error)throw error;setD(data||{})}catch(e){onError?.(errText(e))}}
  useEffect(()=>{load()},[])
  const save=async(table,row,column,value,reason)=>{const{data,error}=await supabase.rpc('admin_policy_tables_write',{p_table:table,p_row:row,p_column:column,p_value:value,p_reason:reason});if(error)throw error;setD(data||{})}
  if(!d)return null
  return <>{(d.tables||[]).map(t=><Card key={t.table} id={`settings.policy.${t.table}`} title={TABLE[t.table]?.[0]||t.table} subtitle={TABLE[t.table]?.[1]||''}
      data-policy-table={t.table} data-anchor={`policy:${t.table}`} meta={<span className="cf-chip tone-neutral">{fmtNumber((t.rows||[]).length)} row{(t.rows||[]).length===1?'':'s'}</span>}>
    {(t.rows||[]).length===0?<Empty text="No rows."/>:
    <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Row</th>{t.columns.map(c=><th key={c.col}>{c.label}{c.unit&&c.unit!=='date'?` (${c.unit})`:''}</th>)}</tr></thead><tbody>
      {t.rows.map(r=><tr key={String(r[t.key])}><td>{(ROW_LABEL[t.table]||(x=>x[t.key]))(r,d.providers||{})}</td>
        {t.columns.map(c=><td key={c.col}><PolicyCell t={t} row={r} col={c} can={can&&Boolean(d.can_manage)} onSave={save}/></td>)}</tr>)}
    </tbody></table></div>}
  </Card>)}</>
}
