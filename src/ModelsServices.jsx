// Models & services (v2.15.118): one admin page with an on/off switch for every AI model and every external page-fetching
// service. Platform Admin, 1 Oct 2026: "Model or external should have toggle button to enable /disable. Disable should
// grey out or not available in operation but only in admin menu."
// Anything switched off stays listed here, greyed; operation screens (Layer 3 Control, Send back to AI, Layer 2 routing)
// only offer what is switched on. Switching a model off also switches off its cascade steps; switching it back on does
// not put it back into a cascade (that stays a Layer 3 Control decision). Retired models are listed separately.
// Read: public.admin_services_read(); write: public.admin_services_control(kind, id, enabled, reason)
// (migration 20260930160000_cf247_models_services_toggles).
import React,{useEffect,useState}from'react'
import{BrainCircuit,Globe,History,Power,RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,Metric,SectionTitle,StatusChip,fmtDateTime,fmtNumber,humanLabel}from'./ui-kit'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const usd=v=>`US$${Number(v||0).toFixed(2)}`

export function Switch({on,label,disabled,onChange}){
  return <button type="button" role="switch" aria-checked={on} aria-label={label} className={`ms-switch${on?' on':''}`} disabled={disabled} onClick={()=>onChange(!on)}><span/></button>
}

export default function ModelsServices({onError}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(false),[done,setDone]=useState('')
  const load=async()=>{setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_services_read');if(error)throw error;setData(d||{})}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  useEffect(()=>{load()},[])
  if(!data)return <section className="m-panel"><Loading label="Loading models and services…"/></section>
  const can=Boolean(data.can_control),models=data.models||[],services=data.services||[]
  const live=models.filter(m=>!m.retired),retired=models.filter(m=>m.retired)
  const flip=async(kind,x,on)=>{
    const name=kind==='model'?x.model:x.name
    const active=(x.steps||[]).filter(s=>s.active)
    const msg=on?`Switch on ${name}?${kind==='model'?' It will be offered again in Layer 3 Control, but is not added back to any cascade.':''}`
      :kind==='model'?`Switch off ${name}?${active.length?` It is used in ${active.length} active cascade step${active.length===1?'':'s'} (${active.map(s=>`${humanLabel(s.task)} step ${s.step}`).join(', ')}); ${active.length===1?'that step':'those steps'} will be switched off too.`:''} It will not be offered in any operation screen.`
      :`Switch off ${name}?${x.routes?` ${fmtNumber(x.routes)} source routes use it; pages will be fetched by the next service on each route.`:''}`
    const reason=window.prompt(`${msg}\n\nReason (optional, kept in the change log):`,'')
    if(reason===null)return
    setBusy(true);setDone('')
    try{const{data:d,error}=await supabase.rpc('admin_services_control',{p_kind:kind,p_id:x.id,p_enabled:on,p_reason:reason.trim()||null});if(error)throw error
      setData(d||{});setDone(`${name} switched ${on?'on':'off'}${d?.steps_switched_off?`; ${d.steps_switched_off} cascade step${d.steps_switched_off===1?'':'s'} switched off`:''}.`)}
    catch(e){onError?.(errText(e))}finally{setBusy(false)}
  }
  const modelRow=m=><tr key={m.id} className={m.enabled?'':'ms-off'} data-model={m.code}>
    <td><strong>{m.model}</strong><span className="l3v-code">{m.provider}</span></td>
    <td>{(m.tasks||[]).map(humanLabel).join(', ')||'—'}</td>
    <td>{(m.steps||[]).length?(m.steps||[]).map(s=><StatusChip key={s.task+s.step} value={s.active?'active':'off'} tone={s.active?'success':'neutral'} label={`${humanLabel(s.task)} · step ${s.step}`}/>):<span className="l3v-code">Not in a cascade</span>}</td>
    <td className="num">{fmtNumber(m.calls_7d||0)}<span className="l3v-code">{usd(m.cost_7d_usd)}</span></td>
    <td>{m.qualified?<StatusChip value="passed" tone="success" label="Passed"/>:<span className="l3v-code">Not tested</span>}</td>
    <td>{m.retired?<span className="l3v-code">{m.retired_reason||'Retired'}</span>:<Switch on={Boolean(m.enabled)} label={`${m.enabled?'Switch off':'Switch on'} ${m.model}`} disabled={!can||busy} onChange={on=>flip('model',m,on)}/>}</td>
  </tr>
  const head=<thead><tr><th>Model</th><th>Used for</th><th>Cascade steps</th><th className="num">Last 7 days</th><th>Tests</th><th>On</th></tr></thead>
  return <>
    <div className="cf-metric-grid">
      <Metric label="AI models on" value={`${live.filter(m=>m.enabled).length} of ${live.length}`} icon={BrainCircuit}/>
      <Metric label="Fetching services on" value={`${services.filter(s=>s.enabled).length} of ${services.length}`} icon={Globe}/>
      <Metric label="Retired models" value={retired.length} icon={Power}/>
    </div>
    {!can&&<p className="l3v-note">You can view these. A PIM Operator or above can switch them on or off.</p>}
    {done&&<p className="sb-done" role="status">{done}</p>}
    <section className="m-panel">
      <SectionTitle icon={Globe} title="Page-fetching services" subtitle="External services that fetch web pages for Layer 2. A service that is off is skipped on every route and is not offered anywhere else." action={<Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Updating…':'Refresh'}</Button>}/>
      <div className="cf-table-wrap"><table className="cf-table ms-table"><thead><tr><th>Service</th><th>Type</th><th>Key</th><th className="num">Routes</th><th>Last test</th><th>On</th></tr></thead><tbody>
        {services.map(s=><tr key={s.id} className={s.enabled?'':'ms-off'} data-service={s.key}>
          <td><strong>{s.name}</strong><span className="l3v-code">{s.key}</span></td>
          <td>{humanLabel(s.type)}</td>
          <td>{s.credential?'Saved':<span className="l3v-code">None</span>}</td>
          <td className="num">{fmtNumber(s.routes||0)}</td>
          <td>{s.last_test?.at?<><StatusChip value={s.last_test.status||'unknown'}/><span className="l3v-code">{fmtDateTime(s.last_test.at)}</span></>:<span className="l3v-code">Never</span>}</td>
          <td><Switch on={Boolean(s.enabled)} label={`${s.enabled?'Switch off':'Switch on'} ${s.name}`} disabled={!can||busy} onChange={on=>flip('service',s,on)}/></td>
        </tr>)}
      </tbody></table></div>
      <p className="l3v-note">Keys and limits for each service are on Platform settings › Scrapers & fetchers.</p>
    </section>
    <section className="m-panel">
      <SectionTitle icon={BrainCircuit} title="AI models" subtitle="Models Layer 3 can use to read course and scholarship pages. Switching a model off also switches off its cascade steps. Switching it back on makes it available again; add it to a cascade in Layer 3 › Control."/>
      {live.length?<div className="cf-table-wrap"><table className="cf-table ms-table">{head}<tbody>{live.map(modelRow)}</tbody></table></div>:<Empty text="No models."/>}
      {retired.length>0&&<details className="ms-retired"><summary>Retired models ({retired.length}) — failed their tests and cannot be switched on</summary>
        <div className="cf-table-wrap"><table className="cf-table ms-table">{head}<tbody>{retired.map(modelRow)}</tbody></table></div></details>}
    </section>
    {(data.events||[]).length>0&&<section className="m-panel">
      <SectionTitle icon={History} title="Recent changes"/>
      <ul className="ms-events">{data.events.map((e,i)=><li key={i}><strong>{e.target}</strong> switched {e.action==='switch_on'?'on':'off'}<span className="l3v-code">{[e.by,fmtDateTime(e.at)].filter(Boolean).join(' · ')}</span></li>)}</ul>
    </section>}
  </>
}
