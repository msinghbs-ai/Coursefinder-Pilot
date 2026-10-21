// Enrichment plan (v2.15.306, CF-247). Platform Admin, 21 Oct 2026 12:03: "build a functionality to tackle end to end data enrichment for
// universities ... automation is gated by toolset configurable limits but manual should decide on screen of required toolset usage but can
// do it on demand." Choices: "Own on-demand allowance", "All, most missing first", "Universities row + plan tab".
// Each university's plan comes from its own gaps: website, contacts and central pages; course pages; adapter (onboarding); admit (a person);
// missing fields (Enrich fields); scholarships. Each step shows why, the fields it fills and its estimate in Firecrawl credits and AI US$
// (from what the same step used in the last 30 days). Run now (Pipeline Operator) runs the ticked steps at once from the on-demand allowance;
// automatic plans (most missing first) wait for room in each toolset share. Reads and writes: public.admin_enrich_plan.
import React,{useEffect,useState}from'react'
import{Gauge,ListChecks,Play,RefreshCw,Route,UserCheck}from'lucide-react'
import{supabase}from'./lib/supabase'
import Card from'./Card'
import{Button,Empty,Loading,StatusChip,fmtDateTime}from'./ui-kit'
import{fmtNumber}from'./lib/format.js'
import{hrefFor}from'./nav-map.js'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const call=async(action,args)=>{const{data,error}=await supabase.rpc('admin_enrich_plan',{p_action:action,p_args:args||{}});if(error)throw error;return data}
const COUNTRY={AU:'Australia',NZ:'New Zealand',CA:'Canada'}
const GROUP={course_search:'Finding course pages',reads:'Reading pages',central:'Central pages',scholarships:'Scholarships',other:'Other'}
const STATUS={pending:['Waiting to start','neutral'],waiting:['Waiting for budget','warning'],running:['Running','info'],done:['Done','success'],person:['A person admits','warning'],
  skipped:['Skipped','neutral'],failed:['Failed','danger'],cancelled:['Cancelled','neutral'],stopped:['Stopped','danger'],timed_out:['Timed out','warning'],queued:['Queued','neutral']}
const usd=v=>`US$${Number(v||0).toFixed(Number(v||0)<1?3:2)}`
const cr=v=>`${fmtNumber(Math.round(Number(v||0)))} credits`

export default function EnrichPlan({rank=0,onError,initialProvider=''}){
  const[ov,setOv]=useState(null),[pid,setPid]=useState(initialProvider||'')
  const load=()=>call('overview').then(setOv).catch(e=>onError?.(errText(e)))
  useEffect(()=>{load()},[])
  if(!ov)return <section className="m-panel"><Loading label="Loading enrichment plans…"/></section>
  return <div className="m-page-stack" data-enrich-plan>
    <Overview ov={ov} onSaved={setOv} onReload={load} onError={onError}/>
    <NeedsPerson items={ov.needs_person||[]} onOpen={id=>{setPid(id);window.scrollTo?.({top:0,behavior:'smooth'})}}/>
    {pid&&<PlanPanel pid={pid} onClose={()=>setPid('')} onRan={load} onError={onError}/>}
    <PlanList onOpen={id=>{setPid(id);window.scrollTo?.({top:0,behavior:'smooth'})}} onError={onError}/>
  </div>
}

function Overview({ov,onSaved,onReload,onError}){
  const[reason,setReason]=useState(''),[busy,setBusy]=useState(false)
  const a=ov.auto||{},od=ov.on_demand||{}
  const toggle=async()=>{setBusy(true);try{onSaved(await call('control',{auto:!a.enabled,reason:reason.trim()}));setReason('')}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  return <Card id="layer2.plan.limits" title="Enrichment plan: limits today" icon={Gauge}
    subtitle="Automatic plans start for the universities with the most missing values and each step waits for room in its toolset share. Run now on a university's plan uses the on-demand allowance instead, so manual and automatic work never use up each other's credits. Limits are on Models & services › Toolsets & limits and Settings › Pipeline settings › Onboarding."
    meta={<StatusChip value={a.enabled?'on':'off'} tone={a.enabled?'success':'neutral'} label={`Automatic ${a.enabled?'on':'off'}`}/>} data-plan-limits>
    <div className="fc-queue-metrics">
      <span><strong>{fmtNumber(od.credits_left)} of {fmtNumber(od.credits)}</strong><small>On-demand Firecrawl credits left today</small></span>
      <span><strong>{usd(od.usd_left)} of {usd(od.usd)}</strong><small>On-demand AI left today</small></span>
      <span><strong>{fmtNumber(ov.open?.auto||0)} of {fmtNumber(ov.limits?.open_max)}</strong><small>Automatic plans open</small></span>
      <span><strong>{fmtNumber(ov.open?.manual||0)}</strong><small>Manual runs open</small></span>
    </div>
    <div className="dq-table-wrap"><table className="dq-table"><thead><tr><th>Toolset share (automatic)</th><th className="num">Daily share</th><th className="num">Left today</th></tr></thead>
      <tbody>{Object.entries(ov.shares||{}).map(([g,s])=><tr key={g}><td>{GROUP[g]||g}</td><td className="num">{fmtNumber(s.share)}</td><td className="num">{Number(s.left)>=1e6?'no daily budget':fmtNumber(Math.round(s.left))}</td></tr>)}</tbody></table></div>
    <div className="fc-actions">
      <Button compact onClick={onReload} title="Refresh"><RefreshCw size={14}/>Refresh</Button>
      {ov.can_manage&&<><input value={reason} onChange={e=>setReason(e.target.value)} placeholder={a.enabled?'Reason to switch automatic plans off':'Reason to switch automatic plans on'} aria-label="Reason"/>
        <Button compact onClick={toggle} disabled={busy||reason.trim().length<4}>{a.enabled?'Switch automatic off':'Switch automatic on'}</Button></>}
    </div>
  </Card>
}

// v2.15.307 (Platform Admin 21 Oct 2026 17:30, "proceed with task 2"): a plan can finish with a step a person has to pick up (the adapter
// built but no field passed its check, too few course pages, a failed or skipped step, an adapter ready to admit). Listed first, newest
// plan per university.
function NeedsPerson({items,onOpen}){
  return <Card id="layer2.plan.needs" title="Plans that need a person" icon={UserCheck}
    subtitle="These plans finished, but a step did not get through. The note says what stopped it; open the plan, or the Adapter builder for an adapter that read nothing."
    meta={<StatusChip value={items.length?'warning':'ok'} tone={items.length?'warning':'success'} label={`${fmtNumber(items.length)} to look at`}/>} data-plan-needs-person>
    {items.length===0?<Empty text="No finished plan is waiting for a person."/>:<div className="dq-table-wrap"><table className="dq-table"><thead><tr><th>University</th><th>What to do</th><th>Finished</th><th/></tr></thead>
      <tbody>{items.map(x=><tr key={x.run} data-needs-person-row>
        <td><strong>{x.name}</strong><small>{x.mode==='auto'?'Automatic plan':'Run now'}</small></td>
        <td><small>{x.note}</small></td><td><small>{fmtDateTime(x.finished_at)}</small></td>
        <td className="fc-actions"><Button compact onClick={()=>onOpen(x.provider_id)}><Route size={14}/>Open plan</Button>
          {/^Adapter/.test(x.note||'')&&<a className="cf-link" href={hrefFor('layer2','builder',{provider:x.provider_id})}>Adapter builder</a>}</td></tr>)}</tbody></table></div>}
  </Card>
}

function PlanList({onOpen,onError}){
  const[country,setCountry]=useState(''),[q,setQ]=useState(''),[items,setItems]=useState(null),[offset,setOffset]=useState(0)
  useEffect(()=>{setItems(null);const t=setTimeout(()=>call('list',{country,query:q.trim(),limit:50,offset}).then(r=>setItems(r?.items||[])).catch(e=>onError?.(errText(e))),q?250:0);return()=>clearTimeout(t)},[country,q,offset])
  return <Card id="layer2.plan.list" title="Universities by missing values" icon={ListChecks}
    subtitle="Every university with gaps, most missing values first (then world ranking): the order automatic plans follow. Open a plan to see its steps and estimate, and to run it now." data-plan-list>
    <section className="cf-filterbar"><span>Country</span>{[['','All'],['AU','Australia'],['NZ','New Zealand'],['CA','Canada']].map(([k,l])=><button key={k||'all'} className={country===k?'active':''} onClick={()=>{setOffset(0);setCountry(k)}}>{l}</button>)}
      <input className="au-search" type="search" value={q} onChange={e=>{setOffset(0);setQ(e.target.value)}} placeholder="Find a university" aria-label="Find a university"/></section>
    {items==null?<Loading compact/>:items.length===0?<Empty text="No university with gaps here."/>:<div className="dq-table-wrap"><table className="dq-table"><thead><tr><th>University</th><th>Country</th><th className="num">Courses</th><th className="num">Missing values</th><th className="num">Best world rank</th><th>Latest plan</th><th/></tr></thead>
      <tbody>{items.map(x=>{const r=x.last_run,[l,t]=STATUS[r?.state]||['—','neutral'];return <tr key={x.provider_id}><td><strong>{x.name}</strong></td><td>{COUNTRY[x.country]||x.country}</td>
        <td className="num">{fmtNumber(x.courses)}</td><td className="num">{fmtNumber(x.missing)}</td><td className="num">{x.best_rank?fmtNumber(x.best_rank):'—'}</td>
        <td>{r?<><StatusChip value={r.state} tone={t} label={`${r.mode==='auto'?'Automatic':'Manual'}: ${l}`}/><small>{r.step||fmtDateTime(r.finished_at||r.created_at)}</small>{r.needs_person&&<span data-plan-needs><StatusChip value="needs_person" tone="warning" label="Needs a person"/></span>}</>:<small>Not planned yet</small>}</td>
        <td><Button compact onClick={()=>onOpen(x.provider_id)}><Route size={14}/>Open plan</Button></td></tr>})}</tbody></table></div>}
    <footer className="dq-pager"><button disabled={offset===0} onClick={()=>setOffset(Math.max(0,offset-50))}>Previous</button><span>{fmtNumber(offset+1)}–{fmtNumber(offset+(items?.length||0))}</span><button disabled={(items?.length||0)<50} onClick={()=>setOffset(offset+50)}>Next</button></footer>
  </Card>
}

function PlanPanel({pid,onClose,onRan,onError}){
  const[p,setP]=useState(null),[pick,setPick]=useState([]),[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[note,setNote]=useState('')
  const load=()=>call('plan',{provider:pid}).then(d=>{setP(d);setPick((d?.steps||[]).filter(s=>!s.person&&!s.running).map(s=>s.step))}).catch(e=>onError?.(errText(e)))
  useEffect(()=>{setP(null);load()},[pid])
  useEffect(()=>{if(!p?.open_run)return;const t=setInterval(load,20000);return()=>clearInterval(t)},[p?.open_run?.id])
  if(!p)return <section className="m-panel"><Loading label="Working out the plan…"/></section>
  const steps=p.steps||[],chosen=steps.filter(s=>pick.includes(s.step))
  const estC=chosen.reduce((a,s)=>a+Number(s.est_credits||0),0),estU=chosen.reduce((a,s)=>a+Number(s.est_usd||0),0)
  const over=estC>Number(p.on_demand?.credits_left||0)||estU>Number(p.on_demand?.usd_left||0)
  const run=async()=>{setBusy(true);setNote('');try{const r=await call('run',{provider:pid,steps:pick,reason:reason.trim()});setNote(`Started. Estimate ${cr(r?.estimate?.credits)} and ${usd(r?.estimate?.usd)}; the steps run in order and this page updates.`);setReason('');load();onRan?.()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const cancel=async id=>{setBusy(true);try{await call('cancel',{run_id:id,reason:'Cancelled on the plan'});load();onRan?.()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const open=p.open_run&&p.open_run!=='null'?p.open_run:null
  return <Card id="layer2.plan.university" title={`Plan: ${p.name}`} icon={Route} level={2}
    subtitle={`${COUNTRY[p.country]||p.country} · ${fmtNumber(p.courses)} courses · ${fmtNumber(p.missing)} missing values. Steps run in order; each says why it is needed and what it is expected to use.`}
    meta={<Button compact onClick={onClose}>Close</Button>} data-plan-panel>
    {steps.length===0?<Empty text="Nothing left that a step can fill; remaining gaps need a reader or a person."/>:<div className="dq-table-wrap"><table className="dq-table"><thead><tr><th/><th>Step</th><th>Why</th><th>Fills</th><th className="num">Firecrawl</th><th className="num">AI</th></tr></thead>
      <tbody>{steps.map((s,i)=><tr key={s.step} data-plan-step={s.step}>
        <td>{s.person||s.running?null:<input type="checkbox" checked={pick.includes(s.step)} onChange={e=>setPick(e.target.checked?[...pick,s.step]:pick.filter(x=>x!==s.step))} aria-label={`Include ${s.label}`} disabled={!!open}/>}</td>
        <td><strong>{i+1}. {s.label}</strong>{s.person&&<small>A person admits it on Layer 2/3 › Universities</small>}{s.running&&<small>Already running (onboarding)</small>}{s.blocked&&<small>{s.blocked}</small>}</td>
        <td><small>{s.why}</small></td><td><small>{(s.fields||[]).join(', ')}</small></td>
        <td className="num">{cr(s.est_credits)}<small>{GROUP[s.group]||''}</small></td><td className="num">{usd(s.est_usd)}</td></tr>)}</tbody>
      <tfoot><tr><td/><td colSpan={3}><strong>Chosen steps</strong></td><td className="num"><strong>{cr(estC)}</strong></td><td className="num"><strong>{usd(estU)}</strong></td></tr></tfoot></table></div>}
    <p className="sd-desc">On-demand left today: {cr(p.on_demand?.credits_left)} and {usd(p.on_demand?.usd_left)}. Estimates are what the same steps used in the last 30 days; the run records what it actually used.</p>
    {open?<div className="fc-actions"><StatusChip value={open.state} tone={(STATUS[open.state]||[])[1]||'info'} label={`${open.mode==='auto'?'Automatic':'Manual'} run ${(STATUS[open.state]||[open.state])[0].toLowerCase()}`}/>
        {p.can_run&&<Button compact onClick={()=>cancel(open.id)} disabled={busy}>Cancel the run</Button>}</div>
      :p.can_run&&steps.length>0&&<div className="fc-actions">
        <input value={reason} onChange={e=>setReason(e.target.value)} placeholder="Reason (kept with the run)" aria-label="Reason for the run"/>
        <Button compact onClick={run} disabled={busy||pick.length===0||reason.trim().length<4||over} title={over?'More than the on-demand allowance left today':''}><Play size={14}/>Run now</Button>
        {over&&<small className="sd-desc">More than the on-demand allowance left today: untick a step, or raise the allowance on Models &amp; services › Toolsets &amp; limits.</small>}</div>}
    {note&&<p className="sd-desc" role="status">{note}</p>}
    <h3 className="sd-subhead">Runs</h3>
    {(p.runs||[]).length===0?<Empty text="No run yet."/>:(p.runs||[]).map(r=><div key={r.id} className="plan-run" data-plan-run={r.state}>
      <p><StatusChip value={r.state} tone={(STATUS[r.state]||[])[1]||'neutral'} label={`${r.mode==='auto'?'Automatic':'Manual'}: ${(STATUS[r.state]||[r.state])[0]}`}/> <small>{fmtDateTime(r.created_at)} · {r.reason}</small></p>
      <div className="dq-table-wrap"><table className="dq-table"><thead><tr><th>Step</th><th>Status</th><th className="num">Estimate</th><th>Note</th></tr></thead>
        <tbody>{(r.steps||[]).map(s=><tr key={s.step}><td>{s.label}</td><td><StatusChip value={s.status} tone={(STATUS[s.status]||[])[1]||'neutral'} label={(STATUS[s.status]||[s.status])[0]}/></td>
          <td className="num">{cr(s.est_credits)} · {usd(s.est_usd)}</td><td><small>{s.note||(s.started_at?`started ${fmtDateTime(s.started_at)}`:'')}</small></td></tr>)}</tbody></table></div>
      {r.needs_person&&<p className="sd-desc" data-run-needs-person><strong>Needs a person:</strong> {r.needs_person}</p>}
      {r.state==='done'&&<p className="sd-desc">Used {cr(r.actual?.credits)} ({cr(r.actual?.credits_on_demand)} on demand) and {usd(r.actual?.usd)}; estimate {cr(r.estimate?.credits)} and {usd(r.estimate?.usd)}. {gained(r)}</p>}
    </div>)}
  </Card>
}

function gained(r){const b=r.fields_before||{},a=r.fields_after||{};const g=Object.keys(a).map(k=>[k,Number(a[k]?.filled||0)-Number(b[k]?.filled||0)]).filter(([,n])=>n>0)
  return g.length?`Fields gained: ${g.map(([k,n])=>`${k.replace(/_/g,' ')} +${n}`).join(', ')} (hourly count).`:'No field gained yet in the hourly count.'}
