// Models & services › AI & OpenRouter (v2.15.264, CF-247). Platform Admin, 13 Oct 2026 00:09: "Layer 3 has removed the configuration
// of OpenAI and access to toolsets and limits; restore them as a tab in Models & services." When Layer 3 was retired (v2.15.252) its
// Control tab and the Settings section "Extract values (Layer 3)" went with it. The AI that runs now is configured here in one place:
//   OpenRouter    balance, mode (Observe only / Stop at limits), credit floor and the one OpenRouter key every profile shares
//                 (set and verify through layer3-provider-control, Platform Admin);
//   AI uses       scholarship pages, adapter proposals, central pages and course-page matching: model, daily guard (editable),
//                 spent and calls today (UTC), running or stopped; central pages model and on/off (admin_ai_config);
//   Scholarship models  order, qualify and make active (the same section as Scholarships › Extraction);
//   Model profiles      every profile not retired, with its prompt version and hash (read only; a prompt is never edited in place).
// Reads admin_ai_config_read(); writes admin_ai_config(action, args), admin_toolsets_write(action, args) — Platform Admin, with a reason.
import React,{useEffect,useState}from'react'
import{RefreshCw,KeyRound}from'lucide-react'
import{supabase}from'./lib/supabase'
import Card from'./Card'
import{Button,Loading,fmtDateTime,fmtNumber}from'./ui-kit'
import{ScholarshipAiModels}from'./ScholarshipExtraction'
import{plainError}from'./lib/errors'

const errText=e=>plainError(e) // v2.15.341 (UI audit Phase 0): one plain reading, no internals
const ask=t=>{const r=window.prompt(`${t}\n\nReason (kept in the log):`);return r&&r.trim().length>=4?r.trim():null}
const money=v=>v==null?'—':`US$${Number(v).toFixed(2)}`
const SET_ON={scholarship_ai:'Scholarship models below',adapter_builder:'Model setting below',central_ai:'Choose below',course_match:'Fixed in the worker'}

export default function AiConfig({onError}){
  const[d,setD]=useState(null),[busy,setBusy]=useState(false),[guards,setGuards]=useState({}),[key,setKey]=useState(''),[msg,setMsg]=useState(''),[builder,setBuilder]=useState(null)
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_ai_config_read');if(error)throw error;setD(data||{})}catch(e){onError?.(errText(e))}}
  useEffect(()=>{load()},[])
  const run=async(fn,done)=>{setBusy(true);setMsg('');try{await fn();await load();if(done)setMsg(done)}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const toolsets=(action,args,question,done)=>{const reason=ask(question);if(!reason)return;run(async()=>{const{error}=await supabase.rpc('admin_toolsets_write',{p_action:action,p_args:{...args,reason}});if(error)throw error},done)}
  const ai=(action,args,question,done)=>{const reason=ask(question);if(!reason)return;run(async()=>{const{error}=await supabase.rpc('admin_ai_config',{p_action:action,p_args:{...args,reason}});if(error)throw error},done)}
  const saveKey=()=>{const reason=ask('Replace the OpenRouter key used by every AI model?');if(!reason)return
    run(async()=>{const{data:r,error}=await supabase.functions.invoke('layer3-provider-control',{body:{action:'set_credential',profile_id:d.openrouter.key.profile_id,credential:key,reason}});if(error)throw error;if(r?.error)throw new Error(r.error);setKey('')},'The OpenRouter key is stored in the vault. Press Verify to test it.')}
  const verify=()=>run(async()=>{const{data:r,error}=await supabase.functions.invoke('layer3-provider-control',{body:{action:'verify_credential',profile_id:d.openrouter.key.profile_id}});if(error)throw error;setMsg(r?.ok?`Key verified: ${r.provider_model||''} answered.`:`Key not accepted: ${r?.message||r?.error||'no answer'}`)})
  if(!d)return <section className="m-panel"><Loading label="Loading AI settings…"/></section>
  const can=Boolean(d.can_manage)&&!busy,or=d.openrouter||{},b=or.balance||{},low=b.remaining_usd!=null&&Number(b.remaining_usd)<Number(or.credit_floor_usd||0)
  const central=(d.uses||[]).find(u=>u.use==='central_ai')?.models?.[0]||{},adapter=(d.uses||[]).find(u=>u.use==='adapter_builder')?.models?.[0]||{}
  return <div className="m-page-stack" data-ai-config>
    <Card id="services.ai.openrouter" title="OpenRouter account" subtitle="Every AI model is called through OpenRouter with one key. The balance is read every 15 minutes."
      meta={<><span className={`cf-chip tone-${low?'danger':'success'}`}>{money(b.remaining_usd)} left</span><span className={`cf-chip tone-${or.mode==='observe'?'warning':'success'}`}>{or.mode==='observe'?'Observe only':'Stop at limits'}</span></>}>
      <div className="ai-grid" data-ai-openrouter>
        <div><small>Balance</small><strong>{money(b.remaining_usd)}</strong><span>of {money(b.total_credits)} bought · read {b.observed_at?fmtDateTime(b.observed_at):'never'}</span></div>
        <div><small>Credit floor</small><strong>{money(or.credit_floor_usd)}</strong><span>warning below {money(or.low_balance_warn_usd)}</span></div>
        <div><small>Mode</small><strong>{or.mode==='observe'?'Observe only':'Stop at limits'}</strong><span>{or.mode==='observe'?'AI keeps running past guards and the floor; notices only':'AI stops at its daily guard or the credit floor'}</span></div>
      </div>
      {d.can_manage&&<div className="ai-row">
        <Button compact disabled={!can} onClick={()=>toolsets('enforcement',{toolset:'openrouter',enforcement:or.mode==='observe'?'stop':'observe'},or.mode==='observe'?'Make AI stop at its daily guards and the credit floor?':'Let AI run past its guards and the floor (observe only)?')}>{or.mode==='observe'?'Switch to stop at limits':'Switch to observe only'}</Button>
        <label className="ai-inline">Credit floor US$<input aria-label="Credit floor" inputMode="decimal" value={guards.credit_floor_usd??String(or.credit_floor_usd??'')} disabled={!can} onChange={e=>setGuards(x=>({...x,credit_floor_usd:e.target.value}))}/></label>
        {guards.credit_floor_usd!=null&&guards.credit_floor_usd!==String(or.credit_floor_usd)&&<Button compact variant="primary" disabled={!can} onClick={()=>toolsets('setting',{toolset:'openrouter',key:'credit_floor_usd',value:guards.credit_floor_usd},`Change the credit floor to US$${guards.credit_floor_usd}?`)}>Save</Button>}
      </div>}
      <div className="ai-key" data-ai-key><strong><KeyRound size={14}/> OpenRouter key</strong> <span className="sl-sub">{or.key?.secret} · shared by {fmtNumber(or.key?.shared_by_profiles||0)} model profiles · never shown</span>
        {d.can_manage&&<span className="ai-row"><input type="password" autoComplete="new-password" aria-label="New OpenRouter key" placeholder="Write-only; replaces the key" value={key} onChange={e=>setKey(e.target.value)} disabled={!can}/>
          <Button compact variant="primary" disabled={!can||key.trim().length<20||!or.key?.profile_id} onClick={saveKey}>Save key</Button>
          <Button compact disabled={!can||!or.key?.profile_id} onClick={verify}>Verify</Button></span>}</div>
      {msg&&<p role="status" className="sc-note" data-ai-msg>{msg}</p>}
    </Card>

    <Card id="services.ai.uses" title="AI uses, models and daily guards" subtitle="What the platform uses AI for now (Layer 3 was retired on 12 Oct 2026), the model each uses, and its daily guard (UTC day). Spend is counted from each use's own records."
      action={<Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>Refresh</Button>}>
      <div className="cf-table-wrap"><table className="cf-table" data-ai-uses><thead><tr><th>AI use</th><th>Model</th><th className="num">Calls today</th><th className="num">Spent today</th><th>Daily guard</th><th>State</th></tr></thead><tbody>
        {(d.uses||[]).map(u=>{const gk=`guard_${u.use}`,gv=guards[gk]??String(u.guard??''),over=Number(u.guard)>0&&Number(u.spent_today)>=Number(u.guard)
          return <tr key={u.use} data-ai-use={u.use}><td><strong>{u.label}</strong></td>
            <td>{(u.models||[]).map(m=><div key={m.model||m.code}><code>{m.model}</code>{m.enabled===false?' (off)':''}</div>)}{!(u.models||[]).length&&'—'}<small className="sl-sub">{SET_ON[u.use]}</small></td>
            <td className="num">{fmtNumber(u.calls||0)}</td><td className="num">{money(u.spent_today)}</td>
            <td><span className="ai-row">US$<input aria-label={`Daily guard ${u.label}`} inputMode="decimal" value={gv} disabled={!can} onChange={e=>setGuards(x=>({...x,[gk]:e.target.value}))}/>
              {can&&gv!==String(u.guard??'')&&<Button compact variant="primary" onClick={()=>toolsets('setting',{toolset:'openrouter',key:gk,value:gv},`Change the daily guard of "${u.label}" to US$${gv}?`)}>Save</Button>}</span></td>
            <td>{u.allowed===false?<span className="cf-chip tone-danger">Stopped</span>:over?<span className="cf-chip tone-warning">Past its guard (observed)</span>:<span className="cf-chip tone-success">Running</span>}</td></tr>})}
      </tbody></table></div>
      <div className="ai-row" data-ai-central><strong>Central pages model</strong>
        <select aria-label="Central pages model" value={central.code||''} disabled={!can} onChange={e=>{const c=(d.central_choices||[]).find(x=>x.code===e.target.value);if(c)ai('central_model',{code:c.code},`Read central pages with ${c.label}? Every result is still approved by a person.`)}}>
          {(d.central_choices||[]).map(c=><option key={c.code} value={c.code}>{c.label} ({c.model})</option>)}</select>
        <Button compact disabled={!can} onClick={()=>ai('central_on',{on:!central.enabled},central.enabled?'Switch central pages AI off?':'Switch central pages AI on?')}>{central.enabled?'Switch off':'Switch on'}</Button>
        <small className="sl-sub">{central.reason}{central.changed_at?` · ${fmtDateTime(central.changed_at)}`:''}</small></div>
      <div className="ai-row" data-ai-adapter><strong>Adapter proposal model</strong>
        <input aria-label="Adapter proposal model" className="tn-wide" value={builder??String(adapter.model||'')} disabled={!can} onChange={e=>setBuilder(e.target.value)}/>
        {can&&builder!=null&&builder!==String(adapter.model||'')&&<Button compact variant="primary" onClick={()=>toolsets('setting',{toolset:'firecrawl',key:'builder_model',value:builder},`Pin adapter proposals to ${builder}? It is the one model asked, by name.`,'Saved.')}>Save</Button>}
        <small className="sl-sub">Pinned by name (no automatic routing); profile {adapter.profile}.</small></div>
    </Card>

    <Card id="services.ai.scholarship-models" title="Scholarship AI models" subtitle="The order the models read scholarship pages in, their qualification on the sample, and which is active. Qualifying never makes a model active.">
      <ScholarshipAiModels onError={onError}/>
    </Card>

    <Card id="services.ai.profiles" title="Model profiles and prompts" subtitle="Every profile that is not retired, with its prompt version and hash. A prompt is never edited in place; a new version is tested first."
      meta={<span>{fmtNumber((d.profiles||[]).length)}</span>}>
      <div className="cf-table-wrap"><table className="cf-table" data-ai-profiles><thead><tr><th>Profile</th><th>Model</th><th>State</th><th>Prompt</th><th>Hash</th><th className="num">Requests a day</th><th>Holdout</th></tr></thead><tbody>
        {(d.profiles||[]).map(p=><tr key={p.id} data-ai-profile={p.code}><td><code>{p.code}</code>{p.used_now&&<span className="cf-chip tone-info"> in use</span>}<small className="sl-sub">{(p.tasks||[]).join(', ')}</small></td><td>{p.model}</td>
          <td>{p.enabled?p.paused?'Paused':'On':'Off'}</td><td>{p.prompt_version||'—'} · {fmtNumber(p.prompt_chars||0)} chars</td><td><code>{p.prompt_hash}</code></td>
          <td className="num">{fmtNumber(p.requests_per_day||0)}</td><td>{p.holdout?`${p.holdout.right??p.holdout.correct??'?'} of ${p.holdout.cases??p.holdout.total??'?'} right`:'—'}</td></tr>)}
      </tbody></table></div>
    </Card>

    {(d.events||[]).length>0&&<Card id="services.ai.events" title="Recent AI changes" meta={<span>{d.events.length}</span>}>
      <ul className="ai-events">{d.events.map((e,i)=><li key={i}><small>{fmtDateTime(e.at)}</small> {e.area} · {e.action} · {e.target}{e.reason?` — ${e.reason}`:''}</li>)}</ul></Card>}
  </div>
}
