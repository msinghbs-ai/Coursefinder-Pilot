// Toolsets and limits (v2.15.177, Decision 252). Platform Admin, 4 Oct 2026 13:37: OpenRouter is not capped by the
// platform (observe, collect logs, top up when required); each layer shows a notice when a toolset it depends on hits a
// limit or times out; Serper and ScrapingBee are tested on trial keys across every country before any use; and every
// variable is a setting the Platform Admin changes here — nothing fixed in code.
// Reads: admin_toolsets_read(), admin_platform_notices_read(layer), admin_toolset_trials_read(run).
// Writes: admin_toolsets_write(action,args), admin_toolset_trial_write(action,args) — Platform Admin with a reason;
// the trial worker is the toolset-trial edge function (migrations 20261004000600 and 20261004000700).
import React,{useEffect,useState}from'react'
import{RefreshCw,BellRing,Check}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,SectionTitle,fmtDateTime,fmtNumber}from'./ui-kit'

const errText=e=>e?.message||String(e)
const ask=t=>{const r=window.prompt(`${t}\n\nReason (kept in the log):`);return r&&r.trim().length>=4?r.trim():null}
const LAYER={0:'Platform',1:'Layer 1',2:'Layer 2',3:'Layer 3',4:'Layer 4'}
const SEV={high:'danger',warning:'warning',info:'neutral'}
const PURPOSE={find_course_page:'Find course pages',find_provider_site:'Find provider websites',render_page:'Read pages that need a browser'}
const TRIALS={serper:['find_course_page','find_provider_site'],scrapingbee:['render_page']}
const STATUS={ready:'Ready',running:'Running',paused_time_limit:'Paused at the time limit',done:'Finished',stopped:'Stopped',stopped_credit_cap:'Stopped at its credit allowance',stopped_vendor_limit:'Stopped: the service refused calls'}
const OUT={found_on_provider_site:'Found on the provider’s site',provider_site_no_title_match:'Provider’s site, title did not match',other_sites_only:'Other sites only',no_results:'No results',
  likely_official_site:'Likely official website',directories_only:'Directories only',no_confident_match:'No confident match',
  rendered_course_page:'Rendered: the course page',rendered_other_page:'Rendered: a different page',blocked:'Still blocked',error:'Error'}
const GOOD=new Set(['found_on_provider_site','likely_official_site','rendered_course_page'])
const money=v=>v==null?'—':`US$${Number(v).toFixed(2)}`
const pct=(a,b)=>b?`${Math.round(100*a/b)}%`:'—'

// ---- notices on each layer page -------------------------------------------------------------------------------------
export function LayerNotices({layer}){
  const[d,setD]=useState(null),[open,setOpen]=useState(false),[busy,setBusy]=useState(false)
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_platform_notices_read',{p_layer:layer});if(!error)setD(data||{})}catch{/* notices are advisory */}}
  useEffect(()=>{setD(null);load()},[layer])
  if(!d)return null
  const all=d.notices||[],live=all.filter(n=>!n.acknowledged),seen=all.filter(n=>n.acknowledged)
  if(!all.length)return null
  const ack=async n=>{const reason=ask(`Acknowledge “${n.title}”? It comes back if it happens again.`);if(!reason)return;setBusy(true);try{const{error}=await supabase.rpc('admin_toolsets_write',{p_action:'ack',p_args:{notice_key:n.key,reason}});if(error)throw error;await load()}catch(e){window.alert(errText(e))}finally{setBusy(false)}}
  return <section className="tn-strip" data-layer-notices={layer} aria-label="Toolset notices">
    {live.map(n=><Notice key={n.key} n={n} can={d.can_manage&&!busy} onAck={()=>ack(n)}/>)}
    {seen.length>0&&<details className="tn-seen" open={open} onToggle={e=>setOpen(e.currentTarget.open)}><summary>{seen.length} acknowledged</summary>{seen.map(n=><Notice key={n.key} n={n}/>)}</details>}
  </section>
}
function Notice({n,can,onAck}){
  return <div className={`tn-item tn-${n.severity||'info'}`} data-notice={n.key}>
    <BellRing size={15} aria-hidden/>
    <div className="tn-text"><strong>{n.title}</strong>{n.detail&&<span>{n.detail}</span>}{n.hint&&<small>{n.hint}</small>}
      <small className="tn-meta">{LAYER[n.layer]} · {n.toolset?.replace(/_/g,' ')} · last {fmtDateTime(n.last_at)}{n.acknowledged?` · acknowledged ${fmtDateTime(n.acknowledged_at)}`:''} · <a href="#models-services">Toolsets and limits</a></small></div>
    {can&&!n.acknowledged&&<Button compact onClick={onAck}><Check size={13}/>Acknowledge</Button>}
  </div>
}

// ---- Models & services › Toolsets and limits ------------------------------------------------------------------------
export default function Toolsets({onError}){
  const[d,setD]=useState(null),[n,setN]=useState(null),[failed,setFailed]=useState(''),[busy,setBusy]=useState(false)
  const load=async()=>{setFailed('');try{const[a,b]=await Promise.all([supabase.rpc('admin_toolsets_read'),supabase.rpc('admin_platform_notices_read',{p_layer:null})]);if(a.error)throw a.error;setD(a.data||{});setN(b.data||{})}catch(e){setFailed(errText(e))}}
  useEffect(()=>{load()},[])
  const write=async(action,args,question)=>{const reason=ask(question);if(!reason)return;setBusy(true);try{const{error}=await supabase.rpc('admin_toolsets_write',{p_action:action,p_args:{...args,reason}});if(error)throw error;await load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  if(failed&&!d)return <section className="m-panel"><Empty text={`Toolsets could not be loaded: ${failed}`}/><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></section>
  if(!d)return <section className="m-panel"><Loading label="Loading toolsets…"/></section>
  const can=Boolean(d.can_manage)&&!busy
  const notices=(n?.notices||[])
  return <div className="m-page-stack" data-toolsets>
    <section className="m-panel"><SectionTitle title="Toolsets and limits" subtitle="The outside services and platform limits each layer depends on. A notice appears on the layer’s page when one of them hits a limit or times out."/>
      {!d.can_manage&&<p className="l3v-note">You can view this. Only a Platform Admin can change it.</p>}
      <div className="tn-all" data-toolset-notices>{notices.length?notices.map(x=><Notice key={x.key} n={x}/>):<p className="sl-sub">No notices on any layer.</p>}</div>
    </section>
    {(d.toolsets||[]).map(t=><Toolset key={t.key} t={t} d={d} can={can} write={write}/>)}
    <Trials toolsets={d.toolsets||[]} can={Boolean(d.can_manage)} onError={onError}/>
  </div>
}

function Toolset({t,d,can,write}){
  const[vals,setVals]=useState({})
  const or=t.key==='openrouter'?d.openrouter||{}:null
  return <section className="m-panel" data-toolset={t.key}>
    <SectionTitle title={t.label} subtitle={`${(t.layers||[]).map(l=>LAYER[l]).join(', ')}. ${t.help}`}/>
    {t.enforcement&&<div className="tn-mode" data-toolset-mode={t.key}>
      <span className={`cf-chip tone-${t.enforcement==='observe'?'warning':'success'}`}>{t.enforcement==='observe'?'Observe only — not stopped by the platform':'Stop at limits'}</span>
      {can&&<Button compact onClick={()=>write('enforcement',{toolset:t.key,enforcement:t.enforcement==='observe'?'stop':'observe'},t.enforcement==='observe'?`Make ${t.label} stop at its spend guards and credit floor?`:`Let ${t.label} run past its spend guards and credit floor (observe only)?`)}>{t.enforcement==='observe'?'Switch to stop at limits':'Switch to observe only'}</Button>}
      <small className="sl-sub">{t.reason}{t.updated_at?` · ${fmtDateTime(t.updated_at)}`:''}</small></div>}
    {t.key in TRIALS&&<p className="sl-sub" data-toolset-key={t.key}>{t.key_saved?'Key saved in the vault.':'No key yet — save it on '}{!t.key_saved&&<a href="#environment">Environment &amp; integrations</a>}</p>}
    {or&&<OpenRouter or={or}/>}
    {(t.settings||[]).length>0&&<div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Setting</th><th>Value</th><th>Last change</th></tr></thead><tbody>
      {t.settings.map(s=>{const shown=s.kind==='list'?(s.value||[]).join(', '):String(s.value??'');const v=vals[s.key]??shown;const changed=String(v)!==shown
        const value=s.kind==='list'?v.split(',').map(x=>x.trim()).filter(Boolean):s.kind==='boolean'?v==='true':v
        return <tr key={s.key} data-toolset-setting={`${t.key}.${s.key}`}><td><strong>{s.label}</strong><small className="sl-sub">{s.help}</small></td>
          <td><span className="sl-val tn-val">{s.kind==='boolean'?<select aria-label={s.label} value={v} disabled={!can} onChange={e=>setVals(x=>({...x,[s.key]:e.target.value}))}><option value="true">Yes</option><option value="false">No</option></select>
            :<input aria-label={s.label} className={s.kind==='number'?'':'tn-wide'} inputMode={s.kind==='number'?'decimal':'text'} value={v} disabled={!can} onChange={e=>setVals(x=>({...x,[s.key]:e.target.value}))}/>}
            <small>{s.unit}{s.kind==='number'&&s.min!=null?` (${fmtNumber(s.min)} to ${fmtNumber(s.max)})`:''}</small>
            {can&&changed&&<Button compact variant="primary" onClick={()=>write('setting',{toolset:t.key,key:s.key,value},`Change "${s.label}" to ${v}?`)}>Save</Button>}</span></td>
          <td><small>{s.reason||'—'}{s.updated_at?` · ${fmtDateTime(s.updated_at)}`:''}</small></td></tr>})}
    </tbody></table></div>}
  </section>
}

function OpenRouter({or}){
  const b=or.balance||{}
  return <div className="tn-or" data-openrouter>
    <p><strong>Balance {money(b.remaining_usd)}</strong> of {money(b.total_credits)} bought · read {fmtDateTime(b.observed_at)}</p>
    <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Task</th><th className="num">Spent today (UTC)</th><th className="num">Daily guard</th><th className="num">Credit floor</th></tr></thead><tbody>
      {(or.guards||[]).map(g=><tr key={g.task_class} data-or-guard={g.task_class}><td>{g.task_class.replace(/_/g,' ')}</td><td className="num">{money(g.spent_today)}</td><td className="num">{money(g.daily_usd_max)}</td><td className="num">{money(g.credit_floor_usd)}</td></tr>)}
    </tbody></table></div>
    <small className="sl-sub">The guards and the floor are changed on Environment &amp; integrations › Pipeline settings. Spend by day (last 14 days): {(or.spend_by_day||[]).map(x=>`${x.day} ${money(x.usd)} (${fmtNumber(x.calls)} calls)`).join(' · ')||'none'}</small>
  </div>
}

// ---- trials ----------------------------------------------------------------------------------------------------------
function Trials({toolsets,can,onError}){
  const[d,setD]=useState(null),[run,setRun]=useState(''),[busy,setBusy]=useState(false)
  const load=async(r=run)=>{try{const{data,error}=await supabase.rpc('admin_toolset_trials_read',{p_run_id:r||null});if(error)throw error;setD(data||{})}catch(e){onError?.(errText(e))}}
  useEffect(()=>{load()},[run])
  useEffect(()=>{const live=(d?.runs||[]).some(r=>r.status==='running');if(!live)return;const t=setTimeout(()=>load(),8000);return()=>clearTimeout(t)},[d])
  const kick=async id=>{const{data,error}=await supabase.functions.invoke('toolset-trial',{body:{action:'run',run_id:id}});if(error)throw error;if(data?.error)throw new Error(data.error)}
  const start=async(toolset,purpose)=>{const reason=ask(`Start a ${toolset} trial: ${PURPOSE[purpose]}? It samples each country set below and uses trial credits. Nothing it finds is admitted.`);if(!reason)return
    setBusy(true);try{const{data,error}=await supabase.rpc('admin_toolset_trial_write',{p_action:'start',p_args:{toolset,purpose,reason}});if(error)throw error;await kick(data.run_id);setRun(data.run_id);await load(data.run_id)}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const resume=async id=>{setBusy(true);try{await kick(id);await load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const stop=async id=>{const reason=ask('Stop this trial run?');if(!reason)return;setBusy(true);try{const{error}=await supabase.rpc('admin_toolset_trial_write',{p_action:'stop',p_args:{run_id:id,reason}});if(error)throw error;await load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  if(!d)return <section className="m-panel"><Loading label="Loading trials…"/></section>
  const keys=Object.fromEntries(toolsets.map(t=>[t.key,t]))
  const sel=(d.runs||[]).find(r=>r.id===run)
  return <section className="m-panel" data-toolset-trials><SectionTitle title="Trials" subtitle="Each run samples real cases from every country listed in the toolset’s settings, calls the service and records what came back. Results are for review; nothing is admitted or written to a course, provider or page."/>
    {can&&<div className="tn-starts">{Object.entries(TRIALS).map(([k,ps])=>ps.map(p=><Button key={k+p} compact disabled={busy||!keys[k]?.key_saved} onClick={()=>start(k,p)} title={keys[k]?.key_saved?'':'Save the key first'}>{`Start ${k==='serper'?'Serper':'ScrapingBee'}: ${PURPOSE[p]}`}</Button>))}</div>}
    <h4 className="sl-h4">Backlog the trials sample from</h4>
    <div className="cf-table-wrap"><table className="cf-table" data-trial-backlog><thead><tr><th>Trial</th>{[...new Set((d.backlog||[]).map(b=>b.country))].map(c=><th key={c} className="num">{c}</th>)}</tr></thead><tbody>
      {Object.keys(PURPOSE).map(p=><tr key={p}><td>{PURPOSE[p]}</td>{[...new Set((d.backlog||[]).map(b=>b.country))].map(c=>{const b=(d.backlog||[]).find(x=>x.purpose===p&&x.country===c);return <td key={c} className="num">{b?fmtNumber(b.n):'—'}</td>})}</tr>)}
    </tbody></table></div>
    <h4 className="sl-h4">Runs</h4>
    {(d.runs||[]).length===0?<Empty text="No trial runs yet."/>:<div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Started</th><th>Service</th><th>Trial</th><th>Countries</th><th>Status</th><th className="num">Cases done</th><th className="num">Credits</th><th></th></tr></thead><tbody>
      {d.runs.map(r=><tr key={r.id} data-trial-run={r.id} className={r.id===run?'tn-sel':''}><td>{fmtDateTime(r.created_at)}</td><td>{r.toolset}</td><td>{PURPOSE[r.purpose]}</td><td>{(r.countries||[]).join(', ')}</td>
        <td>{STATUS[r.status]||r.status}{r.status_note&&<small className="sl-sub">{r.status_note}</small>}</td><td className="num">{fmtNumber(r.done)} of {fmtNumber(r.cases)}</td><td className="num">{fmtNumber(r.credits_used)}</td>
        <td><span className="sl-state"><Button compact onClick={()=>setRun(r.id===run?'':r.id)}>{r.id===run?'Hide':'Results'}</Button>
          {can&&['ready','paused_time_limit'].includes(r.status)&&<Button compact variant="primary" disabled={busy} onClick={()=>resume(r.id)}>Continue</Button>}
          {can&&['ready','running','paused_time_limit'].includes(r.status)&&<Button compact disabled={busy} onClick={()=>stop(r.id)}>Stop</Button>}</span></td></tr>)}
    </tbody></table></div>}
    <Results d={d} sel={sel}/>
  </section>
}

function Results({d,sel}){
  const rows=(d.summary||[])
  if(!rows.length)return null
  const groups=[...new Set(rows.map(r=>`${r.toolset}|${r.purpose}`))]
  return <div className="tn-results" data-trial-results>{groups.map(g=>{const[toolset,purpose]=g.split('|');const rs=rows.filter(r=>r.toolset===toolset&&r.purpose===purpose)
    const countries=[...new Set(rs.map(r=>r.country))],outcomes=[...new Set(rs.map(r=>r.outcome))]
    const run=sel||(d.runs||[]).find(r=>r.toolset===toolset),price=Number(run?.usd_per_1k_credits??0)
    return <div key={g}><h4 className="sl-h4">{sel?'This run':'All runs'}: {toolset} — {PURPOSE[purpose]}</h4>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Outcome</th>{countries.map(c=><th key={c} className="num">{c}</th>)}</tr></thead><tbody>
        {outcomes.map(o=><tr key={o} data-trial-outcome={o} className={GOOD.has(o)?'tn-good':''}><td>{OUT[o]||o}</td>{countries.map(c=>{const tot=rs.filter(r=>r.country===c).reduce((a,r)=>a+Number(r.n),0),x=rs.find(r=>r.country===c&&r.outcome===o);return <td key={c} className="num">{x?`${fmtNumber(x.n)} (${pct(x.n,tot)})`:'—'}</td>})}</tr>)}
        <tr><td><strong>Credits per case</strong></td>{countries.map(c=>{const r2=rs.filter(r=>r.country===c),n=r2.reduce((a,r)=>a+Number(r.n),0),cr=r2.reduce((a,r)=>a+Number(r.credits||0),0);return <td key={c} className="num">{n?(cr/n).toFixed(1):'—'}</td>})}</tr>
        <tr data-trial-projection><td><strong>Projected cost for the whole backlog</strong><small className="sl-sub">Backlog × credits per case × price per 1,000 credits (from the settings).</small></td>{countries.map(c=>{const r2=rs.filter(r=>r.country===c),n=r2.reduce((a,r)=>a+Number(r.n),0),cr=r2.reduce((a,r)=>a+Number(r.credits||0),0),b=(d.backlog||[]).find(x=>x.purpose===purpose&&x.country===c)?.n;return <td key={c} className="num">{n&&b!=null?money(b*(cr/n)*price/1000):'—'}</td>})}</tr>
      </tbody></table></div></div>})}
    {sel&&(d.items||[]).length>0&&<details className="tn-items"><summary>Every case in this run ({d.items.length})</summary><div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Country</th><th>Case</th><th>Outcome</th><th>What came back</th><th className="num">Credits</th></tr></thead><tbody>
      {d.items.map((i,k)=><tr key={k}><td>{i.country}</td><td>{i.input?.course||i.input?.provider}<small className="sl-sub">{i.input?.provider&&i.input?.course?i.input.provider:''}{i.input?.url?` · ${i.input.url}`:''}</small></td><td>{OUT[i.outcome]||i.outcome}</td>
        <td><small className="sl-sub">{i.result?.found_url||i.result?.suggested_site||i.result?.h1||i.result?.message||(i.result?.top||[]).map(t=>t.link).slice(0,1).join('')||'—'}{i.result?.same_as_earlier_candidate?' · same page the identity check refused earlier':''}{i.result?.markers?` · intake ${i.result.markers.intake?'yes':'no'}, English ${i.result.markers.english?'yes':'no'}, tuition ${i.result.markers.tuition?'yes':'no'}`:''}</small></td><td className="num">{fmtNumber(i.credits)}</td></tr>)}
    </tbody></table></div></details>}
  </div>
}
