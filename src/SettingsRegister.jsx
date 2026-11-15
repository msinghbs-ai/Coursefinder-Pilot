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
import{listShown,parseList,listValid,listError,listPlaceholder,isProviderIdList}from'./lib/settings-list.js'
import ProviderListPicker,{ProviderNames}from'./ProviderListPicker'
import{plainError}from'./lib/errors'
import{hrefFor}from'./nav-map'
import{isAiHome}from'./lib/ai-overview'

const errText=e=>plainError(e) // v2.15.341 (UI audit Phase 0): one plain reading, no internals
const slug=s=>String(s||'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'')
const SECTION_HELP={'Alerts':'How platform health issues become alerts (StudySearch SS-014C). Delivery outside the platform stays off until the Platform Admin approves a destination.','Operating targets':'Targets T1 to T8 measured by the weekly operational scorecard on Platform health.','Job sizes':'How much each scheduled job takes in a run. The job reads the value each time it runs.',
  'Re-read and retry':'How often pages are read again, and when failed work is tried again.',
  'Onboarding':'The rules the onboarding journey follows for each university.',
  'Housekeeping':'The weekly hygiene check: when something counts as unused, and how long a retired component is kept before it is dropped (Decision 260). Storage & retention: how long job logs, adapter screenshots and hourly resource readings are kept, and how much each clean-up run removes.',
  'Admission checks':'Checks a value must pass before it is admitted automatically: adapter fees against the registered course total, and AI readings of central pages (English policy, academic calendar) for the top providers.',
  'Waste rules':'Stops work that keeps failing or finds nothing: pauses idle jobs, caps retries by how often they still succeed, freezes values two automatic jobs keep changing, reuses stored pages, and limits course-page search to the providers that matter most. What is stopped is recorded and flagged.',
  'Flags':'The flag unit: how many tries before a soft reason holds an item, the free recheck and trial-run back-offs, when a worker job counts as running empty, and who may raise or release flags (Coverage & completeness › Flags).',
  'Logos':'Provider logos: who may upload or find one, and how the logo finder works through providers with no logo (job logo-find).',
  'Website API':'What the website (Wix) is given: whether rankings and logos may be displayed, how long logo links last, the sync page size, and calls a minute per key on the website-api-v2 URL.',
  'Zoho API':'Zoho API v2 (zoho-api-v2): calls a minute per key, page sizes, how long logo links last, the countries in the Zoho change stream and CSV export, and how long single calls stay in the request log (Operations › API usage).'}

// Settings Hub (v2.16.8, Platform Admin 16 Nov 2026 05:12 decisions 2 and 4): the sections sit in five groups. The group of a section comes from
// the register read (pipeline.settings_hub_groups); Website API and Zoho API are Consumer APIs, read-only until the Platform Admin unlocks an
// approved change (the write is refused without it, and the unlock is kept in the change log).
export const HUB_GROUPS=[['AI & Models','AI answer limits and evaluation. Models, prompts, caps and the OpenRouter key are on Models & services.'],
  ['Schedulers & Cadence','Job sizes, re-reads and retries, the schedulers, retention and housekeeping.'],
  ['Circuit Breakers','Guards that stop or hold work: waste rules, flags, alerts, operating targets and health checks.'],
  ['Consumer APIs','What the website and Zoho are given. Read-only: unlock an approved change first; the unlock is recorded.'],
  ['Pipeline steps','Each step of the pipeline: onboarding, enrichment, entry requirements, scholarships, descriptions and the rest.']]
const CONSUMER_SECTIONS=['Website API','Zoho API']
export const hubOf=sec=>sec.hub_group||(CONSUMER_SECTIONS.includes(sec.section)?'Consumer APIs':'Pipeline steps')
const matches=(s,q)=>!q||[s.key,s.label,s.help,s.used_by].some(x=>String(x||'').toLowerCase().includes(q))

// One setting: value, range and unit, what uses it, the last change; Save asks for a reason inline.
function SettingRow({s,can,onSave}){
  // CF-247 16 Oct 2026: a list setting (for example the Zoho countries) is edited as comma-separated values
  const shown=listShown
  const[v,setV]=useState(shown(s.value)),[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[err,setErr]=useState('')
  useEffect(()=>{setV(shown(s.value))},[s.value])
  // v2.15.277: a yes/no setting (kind boolean) is chosen from Yes or No; numbers as before
  // v2.16.0 (Platform Admin 13 Nov 2026 19:23): a text setting (kind 'text', for example a model name) is a text box. It used to be drawn as a
  // number box with "Between 0 and 0", so it could not be changed.
  const yn=s.kind==='boolean',ls=s.kind==='list',tx=s.kind==='text',n=Number(v)
  // CF-247 F-OPS (11 Nov 2026): a list of provider ids is chosen by provider name, not typed as ids
  const pv=isProviderIdList(s)
  const list=parseList(v)
  const changed=yn?v!==String(s.value):ls?v.trim()!==shown(s.value):tx?v.trim()!==String(s.value??'').trim():v!==''&&n!==Number(s.value)
  const valid=yn||(ls?listValid(s,v):tx?v.trim()!=='':(Number.isFinite(n)&&(s.min==null||n>=Number(s.min))&&(s.max==null||n<=Number(s.max))))
  const save=async()=>{setBusy(true);setErr('');try{await onSave(s.key,yn?v==='true':ls?list:tx?v.trim():n,reason.trim());setReason('')}catch(e){setErr(errText(e))}finally{setBusy(false)}}
  return <div className="sr-row" data-register-setting={s.key}>
    <div className="sr-text"><strong>{s.label}</strong>{s.help&&<small>{s.help}</small>}<small className="sr-used">Used by: {s.used_by||'—'}</small>
      {s.updated_at&&<small className="sr-meta">{s.reason||'—'} · {fmtDateTime(s.updated_at)}</small>}</div>
    <div className="sr-edit">
      {can?<>
        {pv?<div className="sr-value is-providers"><ProviderListPicker value={v} onChange={setV} label={s.label} emptyText={listPlaceholder(s)||undefined}/></div>
        :<label className="sr-value"><span className="sr-hide">{s.label}</span>{yn?<select className="fv-input" value={v} onChange={e=>setV(e.target.value)}><option value="true">Yes</option><option value="false">No</option></select>
          :ls?<input className="fv-input" type="text" placeholder={listPlaceholder(s)||undefined} value={v} onChange={e=>setV(e.target.value)}/>
          :tx?<input className="fv-input sr-text" type="text" data-setting-kind="text" value={v} onChange={e=>setV(e.target.value)}/>
          :<input className="fv-input" type="number" inputMode="numeric" min={s.min??undefined} max={s.max??undefined} value={v} onChange={e=>setV(e.target.value)}/>}{!yn&&!ls&&!tx&&<span>{s.unit}</span>}</label>}
        {changed&&<label className="sr-reason"><span className="sr-hide">Reason</span><input className="fv-input" placeholder="Reason (kept in the log)" value={reason} onChange={e=>setReason(e.target.value)}/></label>}
        {changed&&<Button compact variant="primary" disabled={busy||!valid||reason.trim().length<4} onClick={save}><Save size={13}/>Save</Button>}
        {changed&&!valid&&<small className="fr-error">{ls?listError(s):tx?'Enter a value.':<>Between {fmtNumber(Number(s.min))} and {fmtNumber(Number(s.max))}.</>}</small>}
        {err&&<small className="fr-error" role="alert">{err}</small>}
      </>:<strong>{yn?(String(s.value)==='true'?'Yes':'No'):pv?<ProviderNames value={s.value}/>:ls?shown(s.value):tx?(String(s.value??'')||'Not set'):<>{fmtNumber(Number(s.value))} {s.unit}</>}</strong>}
      <small className="sr-range">{!yn&&!ls&&!tx&&s.min!=null?`${fmtNumber(Number(s.min))} to ${fmtNumber(Number(s.max))}`:''}</small>
    </div>
  </div>
}

// CF-247 F-OPS.05 (Platform Admin, 10 Nov 2026, "Simplify production controls"): settings a person decides come first; the ones the software tunes inside their own
// range (control_class 'automatic') sit in a collapsed group, still visible and editable with a reason; 'retiring' ones are collapsed apart. No class (null) is
// shown with the human ones, as before. The range columns (min and max) clamp an automatic value on every write, so a change here can never leave its safe limits.
const GROUPS=[['automatic','Automatically managed (software-tuned within safe limits)','The platform keeps these within the safe range shown on each row. They stay editable here with a reason.'],
  ['retiring','Retiring','Switched off in favour of a newer control. Kept for the housekeeping period, then listed for removal.']]
function SectionRows({settings,can,onSave}){
  const cls=s=>s.control_class==='automatic'||s.control_class==='retiring'?s.control_class:'human'
  const row=s=><SettingRow key={s.key} s={s} can={can} onSave={onSave}/>
  return <>
    {settings.filter(s=>cls(s)==='human').map(row)}
    {GROUPS.map(([c,title,note])=>{const rows=settings.filter(s=>cls(s)===c);return rows.length>0&&<details key={c} className="sr-group" data-control-group={c}>
      <summary><span>{title}</span><span className="cf-chip tone-neutral">{fmtNumber(rows.length)}</span></summary>
      <small className="sr-group-note">{note}</small>
      {rows.map(s=>c==='retiring'&&s.replaced_by?<React.Fragment key={s.key}>{row(s)}<small className="sr-replaced" data-replaced-by={s.key}>Replaced by {s.replaced_by}</small></React.Fragment>:row(s))}
    </details>})}
  </>
}

export default function SettingsRegister({onError}){
  const[d,setD]=useState(null),[failed,setFailed]=useState(''),[q,setQ]=useState(''),[changedOnly,setChangedOnly]=useState(false),[unlocked,setUnlocked]=useState({})
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_settings_register_read');if(error)throw error;setD(data||{})}catch(e){setFailed(errText(e));onError?.(errText(e))}}
  useEffect(()=>{load()},[])
  // a Consumer APIs setting is sent with the unlock only when the Platform Admin ticked it for that section; without it the write is refused
  const save=async(key,value,reason,unlock)=>{const{data,error}=await supabase.rpc('admin_toolsets_write',{p_action:'setting',p_args:{toolset:'pipeline',key,value,reason,...(unlock?{unlock:'consumer_api'}:{})}});if(error)throw error
    if(data&&data.ok===false)throw new Error('This Consumer APIs setting is read-only. Tick "Unlock: this is an approved change" first.');await load()}
  if(!d)return <section className="m-panel" data-settings-register>{failed?<Empty text={`Settings could not be loaded: ${failed}`}/>:<Loading label="Loading settings…"/>}</section>
  const can=Boolean(d.can_manage),check=d.check||[]
  // v2.16.0 (Platform Admin 13 Nov 2026 19:23): a setting whose home is Models & services is listed and changed there only. Every other
  // setting stays here; a section left with none is not drawn.
  const sections=(d.sections||[]).map(sec=>({...sec,hub:hubOf(sec),settings:(sec.settings||[]).filter(x=>!isAiHome(x))})).filter(sec=>sec.settings.length)
  const query=q.trim().toLowerCase(),finding=Boolean(query)||changedOnly
  const found=finding?sections.map(sec=>({...sec,settings:sec.settings.filter(s=>matches(s,query)&&(!changedOnly||s.changed))})).filter(sec=>sec.settings.length):[]
  const locked=sec=>sec.hub==='Consumer APIs'&&!unlocked[sec.section]
  const rowsOf=sec=><>
    {sec.hub==='Consumer APIs'&&can&&<label className="sr-unlock" data-consumer-unlock={sec.section}><input type="checkbox" checked={Boolean(unlocked[sec.section])}
      onChange={e=>setUnlocked(u=>({...u,[sec.section]:e.target.checked}))}/> Unlock: this is an approved change (it is recorded)</label>}
    <SectionRows settings={sec.settings} can={can&&!locked(sec)} onSave={(k,v,r)=>save(k,v,r,sec.hub==='Consumer APIs'&&Boolean(unlocked[sec.section]))}/>
  </>
  return <div className="m-page-stack" data-settings-register data-anchor="settings-register">
    <div className={`sr-check ${check.length?'is-bad':'is-ok'}`} data-controls-check={check.length?'fixed':'ok'} role="status">
      {check.length?<TriangleAlert size={16} aria-hidden/>:<ShieldCheck size={16} aria-hidden/>}
      {check.length?<span><strong>{check.length} running job{check.length===1?' has':'s have'} a number written into it.</strong> It should read a setting here: {check.map(c=>c.job).join(', ')}.</span>
        :<span><strong>Controls check: all {fmtNumber(Number(d.jobs||0))} running jobs read their sizes from settings.</strong> Nothing is fixed in a job.</span>}
    </div>
    {!can&&<p className="l3v-note">You can see every setting. Only a Platform Admin can change one.</p>}
    <p className="l3v-note" data-ai-settings-moved><a className="cf-link" href={hrefFor('services','ai')}>AI models, prompts, caps and the OpenRouter key are in Models &amp; services</a></p>
    <div className="sr-find" data-hub-find>
      <label className="sr-find-q"><span className="sr-hide">Find a setting</span><input className="fv-input" type="search" placeholder="Find a setting (name, key or what uses it)" value={q} onChange={e=>setQ(e.target.value)}/></label>
      <label className="sr-find-changed"><input type="checkbox" checked={changedOnly} onChange={e=>setChangedOnly(e.target.checked)}/> Changed by a person only</label>
    </div>
    {finding?<section className="m-panel sr-results" data-hub-results>
      {found.length===0?<Empty text="No setting matches."/>:found.map(sec=><div key={sec.section} className="sr-result-section" data-hub-result-section={sec.section}>
        <h4>{sec.hub} › {sec.section}</h4>{rowsOf(sec)}</div>)}
    </section>
    :HUB_GROUPS.map(([g,help])=>{const secs=sections.filter(sec=>sec.hub===g);return secs.length>0&&<section key={g} className="sr-hub-group" data-hub-group={g}>
      <div className="sr-hub-head"><h3>{g}</h3><span className="cf-chip tone-neutral">{fmtNumber(secs.reduce((n,sec)=>n+sec.settings.length,0))} settings</span>{g==='Consumer APIs'&&<span className="cf-chip tone-warning">Read-only</span>}</div>
      <small className="sr-hub-help">{help}</small>
      {secs.map(sec=><Card key={sec.section} id={`settings.register.${slug(sec.section)}`} title={sec.section} subtitle={SECTION_HELP[sec.section]||''}
          data-register-section={sec.section} data-anchor={`register:${sec.section}`} meta={<span className="cf-chip tone-neutral">{fmtNumber(sec.settings.length)} settings</span>}>
        {rowsOf(sec)}
      </Card>)}
    </section>})}
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
