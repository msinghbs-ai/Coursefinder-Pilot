// Enrich fields (v2.15.273, CF-247). Platform Admin, 14 Oct 2026 10:41: "create a job to enrich data for specific or multiple fields across
// uni or countries using scraper and ai in layer 2 and layer 3. Keep it simple" (plan docs/platform/FIELD-GAPS-AND-ENRICHMENT-PLAN.md).
// Choose countries or universities and fields, see what is missing and what stored pages can fill, then start a task. The task fills
// only missing values, never a value entered or locked by hand; each value keeps its source and quote. Field sources (which sources fill
// each field, per country, and in what order) are changed here by a Platform Admin, with a reason.
// Reads and writes: public.admin_enrich_fields('fields' | 'preview' | 'start' | 'jobs' | 'items' | 'rule_set').
import React,{useEffect,useState}from'react'
import{Activity,ListChecks,Play,RefreshCw,Search,X}from'lucide-react'
import{api,supabase}from'./lib/supabase'
import Card from'./Card'
import{Button,Empty,Loading,StatusChip,fmtDateTime}from'./ui-kit'
import{fmtNumber}from'./lib/format.js'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const call=async(action,args)=>{const{data,error}=await supabase.rpc('admin_enrich_fields',{p_action:action,p_args:args||{}});if(error)throw error;return data}
export const SOURCE_LABEL={adapter:'Adapter reading (stored page)',institution_rule:'Institution rule',ai_stored:'AI reads the stored page',ai_title:'AI from title and level',scraper:'New read (scraper)'}
const COUNTRY={AU:'Australia',NZ:'New Zealand',CA:'Canada'}
const TONE={filled:'success',review:'warning',skipped:'neutral',failed:'danger'}
const STATE_LABEL={filled:'Filled',review:'For review',skipped:'Skipped',failed:'Failed',queued:'Waiting',waiting:'Waiting',ai:'With AI',leased:'With AI'}
const FIELD_LABEL={campus_list:'Campus list'}

export default function EnrichFields({rank=0,onError}){
  const[meta,setMeta]=useState(null),[jobs,setJobs]=useState([]),[open,setOpen]=useState('')
  const load=async()=>{try{const[m,j]=await Promise.all([call('fields'),call('jobs')]);setMeta(m||{});setJobs(j?.jobs||[])}catch(e){onError?.(errText(e))}}
  useEffect(()=>{load()},[])
  useEffect(()=>{if(!jobs.some(j=>['queued','running'].includes(j.state)))return;const t=setInterval(()=>call('jobs').then(j=>setJobs(j?.jobs||[])).catch(()=>{}),15000);return()=>clearInterval(t)},[jobs])
  if(!meta)return <section className="m-panel"><Loading label="Loading Enrich fields…"/></section>
  const label=f=>FIELD_LABEL[f]||(meta.fields||[]).find(x=>x.field===f)?.label||f
  return <div className="m-page-stack" data-enrich-fields>
    <Telemetry label={label}/>
    <StartCard meta={meta} label={label} onStarted={()=>load()} onError={onError}/>
    <Card id="layer2.enrich.tasks" title="Enrich fields tasks" subtitle="The last 20 tasks. Each value keeps its source and the words it was read from." icon={ListChecks}
      meta={<span className="cf-chip tone-neutral">{fmtNumber(jobs.length)} task{jobs.length===1?'':'s'}</span>}>
      {jobs.length===0?<Empty text="No Enrich fields task yet."/>:<div className="ef-jobs">{jobs.map(j=><JobRow key={j.id} j={j} label={label} open={open===j.id} onOpen={()=>setOpen(o=>o===j.id?'':j.id)}/>)}</div>}
    </Card>
    <FieldSources meta={meta} label={label} onSaved={m=>setMeta(m)} onError={onError}/>
  </div>
}

function UniversityPicker({value,onChange}){
  const[q,setQ]=useState(''),[hits,setHits]=useState([])
  useEffect(()=>{if(q.trim().length<2){setHits([]);return}let live=true;const t=setTimeout(()=>api.catalogueFilterPage({kind:'provider',query:q,limit:8}).then(x=>live&&setHits(x?.items||[])).catch(()=>{}),250);return()=>{live=false;clearTimeout(t)}},[q])
  return <div className="ef-unis">
    <label className="ef-search"><Search size={14}/><input value={q} onChange={e=>setQ(e.target.value)} placeholder="Add a university (type 2 letters)" aria-label="Add a university"/></label>
    {hits.length>0&&<div className="ef-hits">{hits.filter(h=>!value.some(v=>v.value===h.value)).map(h=><button type="button" key={h.value} onClick={()=>{onChange([...value,{value:h.value,label:h.label}]);setQ('')}}>{h.label}</button>)}</div>}
    {value.length>0&&<div className="ef-chips">{value.map(v=><span key={v.value} className="cf-filter-chip">{v.label}<button type="button" aria-label={`Remove ${v.label}`} onClick={()=>onChange(value.filter(x=>x.value!==v.value))}><X size={12}/></button></span>)}</div>}
  </div>
}

function StartCard({meta,label,onStarted,onError}){
  const[cc,setCc]=useState([]),[unis,setUnis]=useState([]),[fields,setFields]=useState([]),[ai,setAi]=useState(true),[scraper,setScraper]=useState(false),[reason,setReason]=useState('')
  const[preview,setPreview]=useState(null),[busy,setBusy]=useState(''),[err,setErr]=useState(''),[done,setDone]=useState('')
  const args=()=>({countries:unis.length?[]:cc,provider_ids:unis.map(u=>u.value),fields,ai,scraper})
  const flip=(arr,set,v)=>set(arr.includes(v)?arr.filter(x=>x!==v):[...arr,v])
  useEffect(()=>{setPreview(null)},[cc,unis,fields])
  const runPreview=async()=>{setBusy('preview');setErr('');try{setPreview(await call('preview',args()))}catch(e){setErr(errText(e))}finally{setBusy('')}}
  const start=async()=>{setBusy('start');setErr('');setDone('');try{const r=await call('start',{...args(),reason:reason.trim()});setDone(`Task started: ${fmtNumber(r?.items||0)} item(s) to settle. Progress is below and in Task manager.`);setReason('');onStarted?.()}catch(e){setErr(errText(e))}finally{setBusy('')}}
  const scope=unis.length>0||cc.length>0,ok=scope&&fields.length>0
  return <Card id="layer2.enrich.start" title="Enrich fields" subtitle="Fill missing fields for chosen countries or universities from stored pages, rules and AI; a new read through the scraper only when you allow it." icon={Play} data-enrich-start>
    <div className="ef-form">
      <div className="ef-row"><span className="ef-k">Countries</span>{(meta.countries||[]).map(c=><label key={c} className="rs-check"><input type="checkbox" checked={cc.includes(c)} disabled={unis.length>0} onChange={()=>flip(cc,setCc,c)}/>{COUNTRY[c]||c}</label>)}
        <small className="sl-sub">or choose universities (they replace the countries)</small></div>
      <div className="ef-row"><span className="ef-k">Universities</span><UniversityPicker value={unis} onChange={setUnis}/></div>
      <div className="ef-row"><span className="ef-k">Fields</span>{(meta.fields||[]).map(f=><label key={f.field} className="rs-check" data-enrich-field={f.field}><input type="checkbox" checked={fields.includes(f.field)} onChange={()=>flip(fields,setFields,f.field)}/>{f.label}</label>)}</div>
      <div className="ef-row"><span className="ef-k">Sources</span>
        <label className="rs-check"><input type="checkbox" checked={ai} onChange={e=>setAi(e.target.checked)}/>AI may read stored pages and titles (Layer 3, within its daily guard)</label>
        <label className="rs-check"><input type="checkbox" checked={scraper} onChange={e=>setScraper(e.target.checked)}/>New reads through the scraper (Layer 2, Firecrawl credits within the daily shares)</label></div>
      <div className="ef-actions"><Button compact disabled={!ok||busy!==''} onClick={runPreview}><RefreshCw size={13}/>Preview</Button></div>
      {preview&&<div className="cf-table-wrap" data-enrich-preview><table className="cf-table"><thead><tr><th>Field</th><th className="num">Missing</th><th className="num">Stored page</th><th className="num">Adapter already read</th></tr></thead><tbody>
        {(preview.fields||[]).map(r=><tr key={r.field} data-preview-field={r.field}><td>{label(r.field)}</td><td className="num">{fmtNumber(r.missing||0)}</td><td className="num">{fmtNumber(r.stored_page||0)}</td><td className="num">{r.adapter_value==null?'—':fmtNumber(r.adapter_value)}</td></tr>)}
      </tbody></table><small className="sl-sub">{fmtNumber(preview.courses||0)} active course(s) at {fmtNumber(preview.universities||0)} universit{preview.universities===1?'y':'ies'}. Values entered or locked by hand are never changed.</small></div>}
      {meta.can_start?<div className="ef-actions"><label className="sr-reason"><span className="sr-hide">Reason</span><input className="fv-input" placeholder="Reason (kept with the task)" value={reason} onChange={e=>setReason(e.target.value)}/></label>
        <Button compact variant="primary" disabled={!ok||busy!==''||reason.trim().length<4} onClick={start}><Play size={13}/>Start task</Button></div>
        :<p className="l3v-note">Only a Pipeline Operator or above can start a task.</p>}
      {err&&<small className="fr-error" role="alert">{err}</small>}
      {done&&<p className="sb-done" role="status">{done}</p>}
    </div>
  </Card>
}

function JobRow({j,label,open,onOpen}){
  const p=j.progress||{},by=j.result?.by_field||{},pct=p.total?Math.round(100*Number(p.done||0)/Number(p.total)):0
  return <div className="ef-job" data-enrich-job={j.id}>
    <button type="button" className="ef-job-head" onClick={onOpen} aria-expanded={open}>
      <strong>{j.title}</strong><StatusChip value={j.state} label={j.state==='running'?`${p.phase||'Running'} · ${pct}%`:j.state}/>
      <small>{fmtDateTime(j.created_at)} · {fmtNumber(p.done||0)} of {fmtNumber(p.total||0)}{j.result?.cost_usd?` · AI US$${Number(j.result.cost_usd).toFixed(2)}`:''}</small></button>
    <div className="ef-byfield">{Object.entries(by).map(([f,s])=><span key={f} className="ef-field"><b>{label(f)}</b>{Object.entries(s).map(([k,n])=><StatusChip key={k} tone={TONE[k]||'info'} label={`${STATE_LABEL[k]||k} ${fmtNumber(n)}`}/>)}</span>)}</div>
    {open&&<JobItems jobId={j.id} fields={Object.keys(by)} label={label}/>}
  </div>
}

function JobItems({jobId,fields,label}){
  const[field,setField]=useState(''),[state,setState]=useState('filled'),[items,setItems]=useState(null)
  useEffect(()=>{let live=true;setItems(null);call('items',{job_id:jobId,field,state,limit:50}).then(d=>live&&setItems(d?.items||[])).catch(()=>live&&setItems([]));return()=>{live=false}},[jobId,field,state])
  return <div className="ef-items" data-enrich-items>
    <div className="ef-row"><select className="fv-filter" aria-label="Field" value={field} onChange={e=>setField(e.target.value)}><option value="">All fields</option>{fields.map(f=><option key={f} value={f}>{label(f)}</option>)}</select>
      <select className="fv-filter" aria-label="Result" value={state} onChange={e=>setState(e.target.value)}><option value="">Any result</option>{['filled','review','skipped','failed'].map(s=><option key={s} value={s}>{STATE_LABEL[s]}</option>)}</select></div>
    {!items?<Loading compact/>:items.length===0?<Empty text="Nothing here."/>:<div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Course or university</th><th>Field</th><th>Value</th><th>From</th><th>Words on the page</th></tr></thead><tbody>
      {items.map(i=><tr key={i.id}><td><strong>{i.course||i.provider}</strong>{i.course&&<span className="l3v-code">{i.provider}</span>}</td><td>{label(i.field)}</td>
        <td>{valueText(i)}</td><td>{SOURCE_LABEL[i.source]||i.source||'—'}</td><td className="ef-quote">{i.quote||i.reason||'—'}</td></tr>)}
    </tbody></table></div>}
  </div>
}
function valueText(i){const v=i.value||{};if(i.field==='duration')return v.value!=null?`${v.value} ${v.unit||''}`:'—';if(i.field==='delivery')return v.mode||'—';if(i.field==='international')return v.open==null?'—':v.open?'Yes':'No'
  if(i.field==='campus')return (v.campuses||[]).map(c=>c.name).join(', ')||'—';if(i.field==='campus_list')return (v.admitted||v.campuses||[]).map(c=>c.name).join(', ')||'—'
  if(i.field==='provider_address')return [v.street,v.city,v.postcode].filter(Boolean).join(', ')||'—';return i.state==='filled'?'Set':'—'}

function FieldSources({meta,label,onSaved,onError}){
  const fields=meta.fields||[],rules=meta.rules||[]
  const[edit,setEdit]=useState(null),[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[err,setErr]=useState('')
  const countries=['ALL',...new Set(rules.map(r=>r.country).filter(c=>c!=='ALL'))]
  const rule=(c,f)=>rules.find(r=>r.country===c&&r.field===f)
  const save=async()=>{setBusy(true);setErr('');try{onSaved?.(await call('rule_set',{country:edit.country,field:edit.field,sources:edit.sources,reason:reason.trim()}));setEdit(null);setReason('')}catch(e){setErr(errText(e))}finally{setBusy(false)}}
  const toggle=s=>setEdit(x=>({...x,sources:x.sources.includes(s)?x.sources.filter(y=>y!==s):[...x.sources,s]}))
  const move=(s,d)=>setEdit(x=>{const a=[...x.sources],i=a.indexOf(s),k=i+d;if(i<0||k<0||k>=a.length)return x;[a[i],a[k]]=[a[k],a[i]];return{...x,sources:a}})
  return <Card id="layer2.enrich.sources" title="Field sources" subtitle="Which sources may fill each field, in order. A country row replaces All countries for that country." data-field-sources>
    <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Field</th>{countries.map(c=><th key={c}>{c==='ALL'?'All countries':COUNTRY[c]||c}</th>)}{meta.can_manage&&<th/>}</tr></thead><tbody>
      {fields.map(f=><tr key={f.field} data-source-rule={f.field}><td>{f.label}</td>{countries.map(c=>{const r=rule(c,f.field);return <td key={c} title={r?.reason||''}>{r?r.sources.map((s,i)=><span key={s} className="ef-src">{i+1}. {SOURCE_LABEL[s]||s}</span>):<span className="sch-muted">as All countries</span>}</td>})}
        {meta.can_manage&&<td><Button compact onClick={()=>setEdit({country:'ALL',field:f.field,allowed:f.allowed,sources:[...(rule('ALL',f.field)?.sources||[])]})}>Change</Button></td>}</tr>)}
    </tbody></table></div>
    {!meta.can_manage&&<p className="l3v-note">Only a Platform Admin can change the sources.</p>}
    {edit&&<div className="ef-edit" data-source-edit={edit.field}>
      <div className="ef-row"><span className="ef-k">{label(edit.field)} for</span><select className="fv-filter" aria-label="Country" value={edit.country} onChange={e=>{const c=e.target.value;setEdit(x=>({...x,country:c,sources:[...(rule(c,x.field)?.sources||rule('ALL',x.field)?.sources||[])]}))}}>
        <option value="ALL">All countries</option>{(meta.countries||[]).map(c=><option key={c} value={c}>{COUNTRY[c]||c}</option>)}</select></div>
      {edit.allowed.map(s=><div key={s} className="ef-row"><label className="rs-check"><input type="checkbox" checked={edit.sources.includes(s)} onChange={()=>toggle(s)}/>{SOURCE_LABEL[s]||s}</label>
        {edit.sources.includes(s)&&<><span className="sch-muted">#{edit.sources.indexOf(s)+1}</span><Button compact onClick={()=>move(s,-1)} aria-label={`Move ${SOURCE_LABEL[s]} up`}>Up</Button><Button compact onClick={()=>move(s,1)} aria-label={`Move ${SOURCE_LABEL[s]} down`}>Down</Button></>}</div>)}
      <div className="ef-actions"><input className="fv-input" aria-label="Reason" placeholder="Reason (kept in the log)" value={reason} onChange={e=>setReason(e.target.value)}/>
        <Button compact variant="primary" disabled={busy||reason.trim().length<4} onClick={save}>Save</Button><Button compact onClick={()=>setEdit(null)}>Cancel</Button></div>
      {err&&<small className="fr-error" role="alert">{err}</small>}
    </div>}
  </Card>
}

// v2.15.275 (Platform Admin, 14 Oct 2026 12:04: "maintain stats and telemetry"): field coverage per country now, at the first
// snapshot and a day ago (hourly job enrich-coverage-snapshot), the job's last 24 hours, and the limits in force with where to change them.
function Telemetry({label}){
  const[cc,setCc]=useState('NZ,CA'),[d,setD]=useState(null)
  const load=()=>call('stats',{countries:cc?cc.split(','):[]}).then(setD).catch(()=>setD({}))
  useEffect(()=>{load();const t=setInterval(load,60000);return()=>clearInterval(t)},[cc])
  const pct=(a,b)=>b?`${Math.round(100*Number(a||0)/Number(b))}%`:'—'
  const l=d?.limits||{},h=d?.last_24h||{}
  return <Card id="layer2.enrich.telemetry" title="Coverage and telemetry" subtitle="Share of active courses with each field, how it moved, and what the job did in the last 24 hours." icon={Activity} data-enrich-telemetry>
    {!d?<Loading compact/>:<>
      <div className="ef-row"><span className="ef-k">Countries</span><select className="fv-filter" aria-label="Countries" value={cc} onChange={e=>setCc(e.target.value)}>
        <option value="NZ,CA">New Zealand and Canada</option><option value="NZ">New Zealand</option><option value="CA">Canada</option><option value="AU">Australia</option><option value="">All</option></select>
        <small className="sl-sub">Snapshot {d.snapshot_at?fmtDateTime(d.snapshot_at):'—'} · first {d.first_snapshot_at?fmtDateTime(d.first_snapshot_at):'—'}</small></div>
      <div className="cf-table-wrap"><table className="cf-table" data-coverage-table><thead><tr><th>Country</th><th>Field</th><th className="num">Have it</th><th className="num">Share</th><th className="num">Since first</th><th className="num">Last 24 hours</th></tr></thead><tbody>
        {(d.coverage||[]).map(r=><tr key={r.country+r.field} data-coverage-row={`${r.country}:${r.field}`}><td>{COUNTRY[r.country]||r.country}</td><td>{label(r.field)}</td>
          <td className="num">{fmtNumber(r.filled)} of {fmtNumber(r.courses)}</td><td className="num">{pct(r.filled,r.courses)}</td>
          <td className="num">{r.first==null?'—':`+${fmtNumber(r.filled-r.first)}`}</td><td className="num">{r.day_ago==null?'—':`+${fmtNumber(r.filled-r.day_ago)}`}</td></tr>)}
      </tbody></table></div>
      <div className="ef-tiles" data-enrich-last24>
        <span><b>{fmtNumber(h.last_hour||0)}</b>settled in the last hour</span><span><b>{fmtNumber(h.filled||0)}</b>values filled (24 h)</span>
        <span><b>{fmtNumber(h.ai_calls||0)}</b>AI calls · {fmtNumber(h.ai_failed||0)} failed</span><span><b>US${Number(h.ai_cost_usd||0).toFixed(2)}</b>AI spend (24 h)</span>
        <span><b>{fmtNumber(h.scraper_credits||0)}</b>scraper credits · {fmtNumber(h.pages_requested||0)} pages asked to be read</span></div>
      <p className="l3v-note" data-enrich-limits>Model {l.model||'—'} (Models &amp; services › AI &amp; OpenRouter, central pages model) · AI daily guard US${l.ai_guard_usd??'—'}, spent today US${Number(l.ai_spent_today_usd||0).toFixed(2)}, OpenRouter {l.openrouter_mode==='stop'?'stops at limits':'observes only'} (Toolsets › OpenRouter) · {l.calls_at_once} AI calls at once, {l.items_per_call} items a call, {l.items_a_minute} items a minute, campus admitted at {l.campus_min_pages} pages (Settings › Pipeline settings) · scraper shares: other {fmtNumber(l.scraper_share||0)}, reads {fmtNumber(l.reads_share||0)} credits a day (Toolsets › Firecrawl).</p>
    </>}
  </Card>
}
