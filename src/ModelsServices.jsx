// Models & services (v2.15.118): one admin page with an on/off switch for every AI model and every external page-fetching
// service. Platform Admin, 1 Oct 2026: "Model or external should have toggle button to enable /disable. Disable should
// grey out or not available in operation but only in admin menu."
// Anything switched off stays listed here, greyed; operation screens only offer what is switched on. Switching a model
// off also switches off its cascade steps; switching it back on does not put it back into a cascade. Retired models are
// listed separately. v2.15.252 (Platform Admin, 12 Oct 2026): Layer 3 Control and the AI send-back tab retired.
// Read: public.admin_services_read(); write: public.admin_services_control(kind, id, enabled, reason)
// (migration 20260930160000_cf247_models_services_toggles).
// v2.15.200 (Decision 254, Platform Admin 6 Oct): each panel is a collapsed card, remembered for the browser session.
import React,{useEffect,useState}from'react'
import{Globe,History,RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import Card from'./Card'
import{Button,Loading,Metric,StatusChip,fmtDateTime,fmtNumber,humanLabel}from'./ui-kit'
import{plainError}from'./lib/errors'
import{isRetiredFetcher}from'./retired-services'

const errText=e=>plainError(e) // v2.15.341 (UI audit Phase 0): one plain reading, no internals
const usd=v=>`US$${Number(v||0).toFixed(2)}`

// UI audit Phase 1 (24 Oct 2026): a model identifier ("qwen/qwen3-30b-a3b-instruct-2507") reads as a name in lists; the identifier
// sits behind the row's Show fold and on hover. Nothing about which model is called changes.
const WORD={gpt:'GPT',ai:'AI',llm:'LLM',vl:'VL',moe:'MoE'}
export function modelLabel(id){const s=String(id||'').trim();if(!s)return'—';const name=s.split('/').pop().split(':')[0]
  return name.split('-').filter(Boolean).map(w=>WORD[w.toLowerCase()]||(/^\d+(\.\d+)?[bBkKmM]$/.test(w)?w.toUpperCase():/^[a-z]\d+[a-z]$/i.test(w)?w.toUpperCase():/^\d/.test(w)?w:w.charAt(0).toUpperCase()+w.slice(1))).join(' ')}
export function Switch({on,label,disabled,onChange}){
  return <button type="button" role="switch" aria-checked={on} aria-label={label} className={`ms-switch${on?' on':''}`} disabled={disabled} onClick={()=>onChange(!on)}><span/></button>
}

// SS-020 step 3 (Decision 269, 3 Nov 2026): draws the page-service switches on Services & limits.
// v2.16.0 (Platform Admin 13 Nov 2026 19:14): the AI model switches (the "AI models" card: models that read scholarship pages, cascade steps,
// tests, retired models) are retired from this screen. The one model list, allowed or not, is Models & services › AI (AiModelsServices.jsx).
export default function ModelsServices({onError,only=null,except=null}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(false),[done,setDone]=useState('')
  const load=async()=>{setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_services_read');if(error)throw error;setData(d||{})}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  useEffect(()=>{load()},[])
  if(!data)return <section className="m-panel"><Loading label="Loading models and services…"/></section>
  const can=Boolean(data.can_control),services=(data.services||[]).filter(x=>!isRetiredFetcher({provider_key:x.key})&&(!only||only.includes(x.key))&&(!except||!except.includes(x.key)))
  const flip=async(x,on)=>{
    const msg=on?`Switch on ${x.name}?`:`Switch off ${x.name}?${x.routes?` ${fmtNumber(x.routes)} source routes use it; pages will be fetched by the next service on each route.`:''}`
    const reason=window.prompt(`${msg}\n\nReason (optional, kept in the change log):`,'')
    if(reason===null)return
    setBusy(true);setDone('')
    try{const{data:d,error}=await supabase.rpc('admin_services_control',{p_kind:'service',p_id:x.id,p_enabled:on,p_reason:reason.trim()||null});if(error)throw error
      setData(d||{});setDone(`${x.name} switched ${on?'on':'off'}.`)}
    catch(e){onError?.(errText(e))}finally{setBusy(false)}
  }
  return <>
    {!only&&!except&&<div className="cf-metric-grid">
      <Metric label="Page services on" value={`${services.filter(s=>s.enabled).length} of ${services.length}`} icon={Globe}/>
    </div>}
    {!can&&<p className="l3v-note">You can view these. A PIM Operator or above can switch them on or off.</p>}
    {done&&<p className="sb-done" role="status">{done}</p>}
    {(only||except)&&<div className="cf-table-wrap" data-service-switches={(only||[]).join(' ')||'other'}><table className="cf-table ms-table"><tbody>{services.map(s=><tr key={s.id} className={s.enabled?'':'ms-off'} data-service={s.key}><td><strong>{s.name}</strong><span className="l3v-code">{s.credential?'Key saved':'No key'} · {fmtNumber(s.routes||0)} routes</span></td><td><Switch on={Boolean(s.enabled)} label={`${s.enabled?'Switch off':'Switch on'} ${s.name}`} disabled={!can||busy} onChange={on=>flip(s,on)}/></td></tr>)}</tbody></table></div>}
    {!only&&!except&&<Card id="services.fetching" icon={Globe} title="Page-fetching services" subtitle="External services that fetch web pages for Layer 2. A service that is off is skipped on every route and is not offered anywhere else."
      meta={<span>{services.filter(s=>s.enabled).length} of {services.length} on</span>} action={<Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Updating…':'Refresh'}</Button>}>
      <div className="cf-table-wrap"><table className="cf-table ms-table"><thead><tr><th>Service</th><th>Type</th><th>Key</th><th className="num">Routes</th><th>Last test</th><th>On</th></tr></thead><tbody>
        {services.map(s=><tr key={s.id} className={s.enabled?'':'ms-off'} data-service={s.key}>
          <td><strong>{s.name}</strong><span className="l3v-code">{s.key}</span></td>
          <td>{humanLabel(s.type)}</td>
          <td>{s.credential?'Saved':<span className="l3v-code">None</span>}</td>
          <td className="num">{fmtNumber(s.routes||0)}</td>
          <td>{s.last_test?.at?<><StatusChip value={s.last_test.status||'unknown'}/><span className="l3v-code">{fmtDateTime(s.last_test.at)}</span></>:<span className="l3v-code">Never</span>}</td>
          <td><Switch on={Boolean(s.enabled)} label={`${s.enabled?'Switch off':'Switch on'} ${s.name}`} disabled={!can||busy} onChange={on=>flip(s,on)}/></td>
        </tr>)}
      </tbody></table></div>
      <p className="l3v-note">Keys are on <a href="#environment">Settings</a>. Address, limits and routing are under Fetchers below.</p>
    </Card>}
    {(data.events||[]).length>0&&<Card id="services.recent-changes" icon={History} title="Recent changes" meta={<span>{data.events.length}</span>}>
      <ul className="ms-events">{data.events.map((e,i)=><li key={i}><strong>{e.target}</strong> switched {e.action==='switch_on'?'on':'off'}<span className="l3v-code">{[e.by,fmtDateTime(e.at)].filter(Boolean).join(' · ')}</span></li>)}</ul>
    </Card>}
  </>
}
