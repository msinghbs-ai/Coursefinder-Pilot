// Settings (v2.15.160, Decision 238; Platform Admin 3 Oct 2026 09:26: "All these hardcoded values … need to be reflected
// in UI; UI needs to provide complete control"). One page, a section per pipeline step. Every number a Platform Admin
// has asked to change by migration this week is here: matcher and search throughput, page reading, Layer 3 limits
// and daily spend, Firecrawl budget, and which page identities admit each attribute per country. A number applies at
// once and writes an audit row. Prompts and rules are listed with their version and hash; they change as versions,
// tested on the holdout and switched on separately (Layer 3 Control), never edited in place here.
// Read: public.admin_pipeline_settings_read() (Pipeline Operator and above); write: admin_pipeline_settings_write(key,
// value) (Platform Admin) — migrations 20261003001200 (cron helper), 20261003001210 (read), 20261003001230 (write).
import React,{useEffect,useState}from'react'
import{Save,Sliders}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Loading,SectionTitle,fmtDateTime}from'./ui-kit'
import{fmtNumber}from'./lib/format.js'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const ATTRS=[['official_url','Official page'],['english','English'],['intakes','Intakes'],['tuition','Tuition']]
const IDENTITIES=[['cricos_code','CRICOS code'],['nzqa_code','NZQA code'],['exact_title','Exact title'],['title_level','Title with level'],['field_award','Field and award'],['degree_name','Degree name']]
const TASK={provider_intake_validation:'Intakes',provider_english_validation:'English',provider_current_tuition_validation:'Tuition'}

function NumberRow({label,help,value,min,max,step=1,unit,can,onSave,busy,confirm}){
  const[v,setV]=useState(value==null?'':String(value))
  useEffect(()=>{setV(value==null?'':String(value))},[value])
  const n=Number(v),changed=v!==''&&n!==Number(value),valid=Number.isFinite(n)&&n>=min&&n<=max
  return <div className="ps-row" data-setting={label}><div className="ps-row-text"><strong>{label}</strong>{help&&<small>{help}</small>}</div>
    <div className="ps-row-edit">{can?<><input className="fv-input ps-input" type="number" min={min} max={max} step={step} value={v} onChange={e=>setV(e.target.value)} aria-label={label}/>{unit&&<span className="ps-unit">{unit}</span>}
      <Button compact variant="primary" disabled={busy||!changed||!valid} onClick={()=>{if(!confirm||window.confirm(confirm.replace('{v}',fmtNumber(n))))onSave(n)}}><Save size={13}/>Save</Button>
      {changed&&!valid&&<small className="fr-error">Between {fmtNumber(min)} and {fmtNumber(max)}.</small>}</>
      :<strong className="ps-value">{value==null?'—':fmtNumber(Number(value))}{unit?` ${unit}`:''}</strong>}</div></div>
}

export default function PipelineSettings({onError}){
  const[s,setS]=useState(null),[err,setErr]=useState(''),[busy,setBusy]=useState(false),[saved,setSaved]=useState('')
  const load=async()=>{setErr('');const{data,error}=await supabase.rpc('admin_pipeline_settings_read');if(error)throw error;setS(data)}
  useEffect(()=>{load().catch(e=>{setErr(errText(e));onError?.(errText(e))})},[])
  const write=async(key,value,label)=>{setBusy(true);setSaved('');setErr('');try{const{data,error}=await supabase.rpc('admin_pipeline_settings_write',{p_key:key,p_value:value});if(error)throw error;setS(data);setSaved(`Saved: ${label||key}.`)}catch(e){setErr(errText(e))}finally{setBusy(false)}}
  if(!s)return <section className="m-panel" data-pipeline-settings>{err?<p className="fr-error" role="alert">{err}</p>:<Loading label="Loading settings…"/>}</section>
  const can=Boolean(s.can_change)&&!busy,cp=s.course_pages||{},rd=s.reading||{},l3=s.layer3||{},bg=s.budgets||{},ids=s.identity||{}
  const fcLeft=Math.max(0,Number(bg.firecrawl_monthly_limit||0)-Number(bg.firecrawl_used_this_month||0))
  return <div className="m-page-stack" data-pipeline-settings>
    <style>{`.ps-row{display:grid;grid-template-columns:minmax(0,1.4fr) minmax(0,1fr);gap:10px;align-items:center;padding:9px 0;border-top:1px solid var(--cf-slate-100)}.ps-row:first-of-type{border-top:0}.ps-row-text{display:grid;gap:2px}.ps-row-text small{color:var(--cf-slate-500)}.ps-row-edit{display:flex;gap:8px;align-items:center;flex-wrap:wrap;justify-content:flex-end}.ps-input{width:120px}.ps-unit{color:var(--cf-slate-500);font-size:var(--cf-fs-xs)}.ps-value{font-size:var(--cf-fs-md)}.ps-id-table{width:100%;border-collapse:collapse;font-size:var(--cf-fs-sm)}.ps-id-table th,.ps-id-table td{padding:6px 8px;border-top:1px solid var(--cf-slate-100);text-align:left;vertical-align:top}.ps-id-table label{display:inline-flex;gap:4px;align-items:center;margin-right:10px;white-space:nowrap}.ps-profiles td code{font-size:11px}.ps-note{color:var(--cf-slate-500);font-size:var(--cf-fs-xs);margin:4px 0 0}`}</style>
    {!s.can_change&&<p className="l3v-note">You can see every setting. Only a Platform Admin can change one.</p>}
    {saved&&<p className="sd-desc" role="status">{saved}</p>}{err&&<p className="fr-error" role="alert">{err}</p>}

    <section className="m-panel" data-settings-section="course_pages">
      <SectionTitle icon={Sliders} title="2 · Find the course page" subtitle={`Queued now: ${fmtNumber(Number(cp.queued?.matcher_ready||0))} for the AI matcher, ${fmtNumber(Number(cp.queued?.matcher_never_offered||0))} courses never offered, ${fmtNumber(Number(cp.queued?.searches_queued||0))} searches waiting. Priority countries: ${(cp.priority_countries||[]).join(', ')||'none'}.`}/>
      <NumberRow label="Universities prepared for the matcher, per run (every 2 minutes)" help="Each run offers this many universities' site maps to the AI link matcher. 4 a run was the throttle found on 3 Oct." value={cp.matcher_prepare_universities} min={1} max={500} can={can} busy={busy} onSave={v=>write('course_pages.matcher_prepare_universities',v,'universities per matcher run')}/>
      <NumberRow label="Courses prepared per run" value={cp.matcher_prepare_courses} min={1} max={5000} can={can} busy={busy} onSave={v=>write('course_pages.matcher_prepare_courses',v,'courses per matcher run')}/>
      <NumberRow label="Matcher items a minute" help="Pages the AI link matcher judges each minute (about US$0.25 an hour at 90)." value={cp.matcher_items_per_minute} min={1} max={200} can={can} busy={busy} onSave={v=>write('course_pages.matcher_items_per_minute',v,'matcher items a minute')}/>
      <NumberRow label="Matcher concurrency" value={cp.matcher_concurrency} min={1} max={24} can={can} busy={busy} onSave={v=>write('course_pages.matcher_concurrency',v,'matcher concurrency')}/>
      <NumberRow label="Course-page searches a minute" help="Firecrawl searches (2 credits each) for courses whose site map has no page." value={cp.search_per_minute} min={1} max={120} can={can} busy={busy} onSave={v=>write('course_pages.search_per_minute',v,'searches a minute')}/>
      <NumberRow label="Course-page search cap, credits a month" help="Searches wait when the cap would be passed; they resume when it is raised or the month ends." value={cp.search_monthly_credit_cap} min={1000} max={500000} step={1000} unit="credits" can={can} busy={busy} confirm="Set the course-page search cap to {v} credits a month?" onSave={v=>write('course_pages.search_monthly_credit_cap',v,'search cap')}/>
    </section>

    <section className="m-panel" data-settings-section="reading">
      <SectionTitle icon={Sliders} title="3 · Read the page" subtitle={`${fmtNumber(Number(rd.pages_waiting||0))} bound pages waiting to be read. Direct fetch first (free); a blocked or script-drawn page is read once through Firecrawl (1 credit). robots.txt is respected.`}/>
      <NumberRow label="Pages read per batch (every 30 seconds)" value={rd.read_batch_per_30s} min={10} max={200} can={can} busy={busy} onSave={v=>write('reading.read_batch_per_30s',v,'read batch')}/>
    </section>

    <section className="m-panel" data-settings-section="identity">
      <SectionTitle icon={Sliders} title="4 · Identify the page" subtitle="Which proofs on a page admit each attribute, per country. A page that shows none of the ticked proofs for an attribute is rejected for it. Every change is logged with its date; the decisions behind the current setting are kept on the row."/>
      <table className="ps-id-table"><thead><tr><th>Country</th>{ATTRS.map(([k,l])=><th key={k}>{l}</th>)}</tr></thead><tbody>
        {Object.entries(ids).sort().map(([cc,row])=><tr key={cc} data-identity-country={cc}><td><strong>{cc}</strong><div className="ps-note">{row.currency}{row.active?'':' · off'}</div></td>
          {ATTRS.map(([attr])=>{const cur=row.identities?.[attr]||[];return <td key={attr}>{IDENTITIES.map(([id,label])=>{const on=cur.includes(id);const relevant=cc==='AU'?['cricos_code','exact_title','title_level'].includes(id):cc==='NZ'?id!=='field_award':id!=='nzqa_code'&&id!=='degree_name';if(!relevant&&!on)return null;return <label key={id}><input type="checkbox" checked={on} disabled={!can} aria-label={`${cc} ${attr} ${label}`} onChange={e=>{const next=e.target.checked?[...cur,id]:cur.filter(x=>x!==id);if(window.confirm(`${cc}: ${e.target.checked?'admit':'stop admitting'} ${ATTRS.find(a=>a[0]===attr)[1].toLowerCase()} by ${label.toLowerCase()}?`))write('identity.attribute',{country:cc,attribute:attr,identities:next},`${cc} ${attr}`)}}/>{label}</label>})}</td>})}
        </tr>)}</tbody></table>
    </section>

    <section className="m-panel" data-settings-section="layer3">
      <SectionTitle icon={Sliders} title="5 · Extract values (Layer 3)" subtitle={`Spent today: ${Object.entries(l3.spent_today_usd||{}).map(([k,v])=>`${TASK[k]||k} US$${v}`).join(', ')||'nothing yet'}. Steps, order and switching a model on or off stay on Layer 3 Control.`}/>
      <NumberRow label="Requests a day (intake and English profiles)" help="Counted across all steps of a task together; 6,000 stopped both cascades on 3 Oct. The daily spend guard below is the cost control." value={l3.requests_per_day} min={1000} max={100000} step={1000} can={can} busy={busy} onSave={v=>write('layer3.requests_per_day',v,'requests a day')}/>
      <NumberRow label="Items claimed per route run (every minute)" value={l3.route_limit} min={1} max={200} can={can} busy={busy} onSave={v=>write('layer3.route_limit',v,'route limit')}/>
      <NumberRow label="Route concurrency" value={l3.route_concurrency} min={1} max={16} can={can} busy={busy} onSave={v=>write('layer3.route_concurrency',v,'route concurrency')}/>
      {(l3.budgets||[]).map(b=><NumberRow key={b.task_class} label={`Daily spend guard · ${TASK[b.task_class]||b.task_class}`} help={`Route: ${b.route_mode}. The task stops for the UTC day when this is reached.`} value={b.daily_usd_max} min={0} max={200} unit="US$ a day" can={can} busy={busy} onSave={v=>write('layer3.daily_usd_max',{task_class:b.task_class,value:v},`${TASK[b.task_class]||b.task_class} daily spend`)}/>)}
      <NumberRow label="Credit floor" help="No model call when the OpenRouter balance is below this." value={(l3.budgets||[])[0]?.credit_floor_usd} min={0} max={100} unit="US$" can={can} busy={busy} onSave={v=>write('layer3.credit_floor_usd',v,'credit floor')}/>
      <details className="m-admin-adv"><summary>Prompts and models ({(l3.profiles||[]).length}) — versions, hashes and holdout results</summary>
        <table className="ps-id-table ps-profiles"><thead><tr><th>Profile</th><th>Model</th><th>Prompt</th><th>Hash</th><th>Steps</th><th>Holdout</th><th>Requests a day</th></tr></thead><tbody>
          {(l3.profiles||[]).map(p=><tr key={p.code}><td><code>{p.code}</code><div className="ps-note">{p.enabled?p.paused?'paused':'on':'off'}</div></td><td>{p.model}</td><td>{p.prompt_version} · {fmtNumber(Number(p.prompt_chars||0))} chars</td><td><code>{String(p.prompt_hash||'').slice(0,12)}</code></td>
            <td>{(p.tiers||[]).map(t=>`${TASK[t.task]||t.task} step ${t.tier}${t.active?'':' (off)'}${t.final?' final':''}`).join('; ')||'—'}</td>
            <td>{p.holdout?`${p.holdout.right??p.holdout.correct??'?'} of ${p.holdout.cases??p.holdout.total??'?'} right, ${p.holdout.wrong_admitted??p.holdout.wrong??'?'} wrong`:'—'}</td><td>{fmtNumber(Number(p.requests_per_day||0))}</td></tr>)}
        </tbody></table>
        <p className="ps-note">A prompt is never edited in place: a new version is tested on the frozen holdout and switched on from Layer 3 Control (Decision 238).</p></details>
    </section>

    <section className="m-panel" data-settings-section="budgets">
      <SectionTitle icon={Sliders} title="9 · Budgets" subtitle={`Firecrawl this month: ${fmtNumber(Number(bg.firecrawl_used_this_month||0))} of ${fmtNumber(Number(bg.firecrawl_monthly_limit||0))} credits used, ${fmtNumber(fcLeft)} left. OpenRouter balance: ${bg.openrouter?.remaining_usd!=null?`US$${Number(bg.openrouter.remaining_usd).toFixed(2)} (seen ${fmtDateTime(bg.openrouter.observed_at)})`:'not read yet'}.`}/>
      <NumberRow label="Firecrawl monthly limit" help="Credits the pipeline may use this calendar month, across page reads, searches, maps and extraction. Changed on Scrapers & fetchers › Firecrawl until that record's control moves here." value={bg.firecrawl_monthly_limit} min={1000} max={2000000} unit="credits" can={false} busy={busy} onSave={()=>{}}/>
      <NumberRow label="Firecrawl safety reserve" help="The pipeline stops when this many credits are left, so the account never runs dry. Changed on Scrapers & fetchers › Firecrawl." value={bg.firecrawl_stop_at_remaining} min={0} max={100000} unit="credits" can={false} busy={busy} onSave={()=>{}}/>
      {bg.firecrawl_by_purpose&&<p className="ps-note">By purpose: {Object.entries(bg.firecrawl_by_purpose).sort((a,b)=>b[1]-a[1]).map(([k,v])=>`${k} ${fmtNumber(Number(v))}`).join(' · ')}</p>}
    </section>

    <section className="m-panel" data-settings-section="changes">
      <SectionTitle icon={Sliders} title="Recent changes" subtitle="Every change made here, on Layer 3 Control, Automations or by a recorded migration."/>
      {(s.recent_changes||[]).length?<ul className="m-plain-list">{s.recent_changes.map((c,i)=><li key={i}><small>{fmtDateTime(c.at)}</small> <strong>{c.area} · {c.action}</strong> {c.target}</li>)}</ul>:<p className="sd-desc">No changes recorded yet.</p>}
    </section>
  </div>
}
