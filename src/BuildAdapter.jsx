// Layer 2 › Build adapter (v2.15.287, CF-247 Decision 267). Platform Admin, 17 Oct 2026 18:56: "click and generate the adapter and
// configure it for all fields available in the db and seek value for enrichment or foundation fill"; 18 Oct 11:58 "position and plan it
// on right ui" (choice: Build adapter added to Layer 2, the Adapter builder kept); 14:05 "Proceed with next step".
//
// Three views on one tab:
// - Universities: every university with active courses, its stage (tested, admitted, building, needs pages, stopped, no adapter) and,
//   for those with an adapter, how many of the eight fields are Ready, for Review or Not ready and what the Ready ones would add.
//   Tick universities to build them (onboarding starts, or is retried) and, if wanted, name the wave they belong to.
// - University: the eight fields measured now, with why each is where it is, and one Admit button for the Ready fields only.
// - Waves: universities grouped by the wave they were built in.
// Rules kept: measuring never admits anything. Admit is a Platform Admin's click with a reason and admits Ready fields only, each through
// its existing route (the adapter for intakes, fee, English and delivery; an Enrichment task that fills only what is missing for
// duration, campus and study level; the majors list). Thresholds come from Settings, not from this file.
// Reads and writes: public.admin_adapter_build('list' | 'waves' | 'read' | 'build' | 'set_wave' | 'admit').
import React,{useEffect,useState}from'react'
import{ArrowLeft,Hammer,Layers,ListChecks,RefreshCw,Search,ShieldCheck,X}from'lucide-react'
import{supabase}from'./lib/supabase'
import{hrefFor}from'./nav-map'
import{Button,Empty,Loading,Pager,fmtDateTime,fmtNumber}from'./ui-kit'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const call=async(action,args)=>{const{data,error}=await supabase.rpc('admin_adapter_build',{p_action:action,p_args:args||{}});if(error)throw error;return data}
const ask=t=>{const r=window.prompt(`${t}\n\nReason (kept in the log):`);return r&&r.trim().length>=4?r.trim():null}
const PAGE=50
export const FIELDS=[['intakes','Intakes'],['fee','International fee'],['english','English'],['delivery','Delivery mode'],['duration','Duration'],['campus','Campus'],['study_level','Study level'],['majors','Majors and specialisations']]
const FIELD_LABEL=Object.fromEntries(FIELDS)
export const STAGE={tested:['Tested','info'],admitted:['Admitted','success'],building:['Building','info'],needs_pages:['Needs pages','warning'],stopped:['Stopped','danger'],no_adapter:['No adapter','neutral']}
const STATE={ready:['Ready','success'],review:['Review','warning'],not_ready:['Not ready','danger']}
const ROUTE={intakes:'Adapter',fee:'Adapter',english:'Adapter',delivery:'Adapter',duration:'Enrichment (fills gaps)',campus:'Enrichment (fills gaps)',study_level:'Enrichment (fills gaps)',majors:'Majors list'}
const pct=v=>v==null?'—':`${Math.round(Number(v)*100)}%`
const Chip=({value,map})=>{const[l,t]=map[value]||[value||'—','neutral'];return <span className={`cf-chip tone-${t}`} data-chip={value}>{l}</span>}

export default function BuildAdapter({rank=0,onError,initialProvider=''}){
  const[view,setView]=useState(initialProvider?'university':'list'),[pid,setPid]=useState(initialProvider),[wave,setWave]=useState('')
  const open=id=>{setPid(id);setView('university')}
  return <div className="m-page-stack ba" data-build-adapter>
    <div className="ba-views" role="tablist" aria-label="Build adapter views">
      <button type="button" role="tab" aria-selected={view!=='waves'} className={view!=='waves'?'is-on':''} onClick={()=>setView(pid&&view==='university'?'university':'list')}><ListChecks size={14}/>Universities</button>
      <button type="button" role="tab" aria-selected={view==='waves'} className={view==='waves'?'is-on':''} onClick={()=>setView('waves')}><Layers size={14}/>Waves</button>
    </div>
    {view==='list'&&<Universities rank={rank} onError={onError} onOpen={open} wave={wave} onWave={setWave}/>}
    {view==='university'&&pid&&<University pid={pid} rank={rank} onError={onError} onBack={()=>setView('list')}/>}
    {view==='waves'&&<Waves onError={onError} onPick={w=>{setWave(w);setView('list')}}/>}
  </div>
}

function Bar({r}){
  const tot=Number(r.ready||0)+Number(r.review||0)+Number(r.not_ready||0)
  if(!tot)return <span className="ba-muted">Not measured</span>
  const w=x=>`${Math.round(Number(x||0)/tot*100)}%`
  return <span className="ba-barwrap"><span className="ba-bar" role="img" aria-label={`${r.ready} ready, ${r.review} for review, ${r.not_ready} not ready`}><i className="is-ready" style={{width:w(r.ready)}}/><i className="is-review" style={{width:w(r.review)}}/><i className="is-not" style={{width:w(r.not_ready)}}/></span><small>{r.ready} · {r.review} · {r.not_ready}</small></span>
}

function Universities({rank,onError,onOpen,wave,onWave}){
  const[country,setCountry]=useState('AU'),[stage,setStage]=useState(''),[q,setQ]=useState(''),[offset,setOffset]=useState(0)
  const[data,setData]=useState(null),[busy,setBusy]=useState(false),[picked,setPicked]=useState([]),[msg,setMsg]=useState('')
  const load=()=>{setBusy(true);return call('list',{country,stage,query:q.trim()||null,wave:wave||null,limit:PAGE,offset}).then(setData).catch(e=>onError?.(errText(e))).finally(()=>setBusy(false))}
  useEffect(()=>{const t=setTimeout(load,q?260:0);return()=>clearTimeout(t)},[country,stage,q,wave,offset])
  useEffect(()=>{setOffset(0)},[country,stage,q,wave])
  const s=data?.summary||{},by=s.by_stage||{},items=data?.items||[]
  const flip=id=>setPicked(p=>p.includes(id)?p.filter(x=>x!==id):[...p,id])
  const build=async()=>{const reason=ask(`Build adapters for ${picked.length} universit${picked.length===1?'y':'ies'}? Each one is onboarded (website, course pages, sample pages, AI proposal, apply and measure) in the background; a stopped one is retried.`);if(!reason)return
    const w=window.prompt('Wave name (optional, groups these universities on the Waves view):',wave||'')
    try{const r=await call('build',{provider_ids:picked,reason,wave:(w||'').trim()||null});setMsg(`Building: ${fmtNumber(r?.started||0)} started, ${fmtNumber(r?.retried||0)} retried, ${fmtNumber(r?.already_building||0)} already building. Progress is in Task manager and on Onboarding.`);setPicked([]);load()}catch(e){onError?.(errText(e))}}
  return <>
    <section className="m-panel" data-build-summary>
      <div className="m-workspace-head"><div><h2>Build adapter</h2><p>One adapter per university reads its course pages. Each university's eight fields are measured every hour: <b>Ready</b> fields can be admitted with one click, <b>Review</b> fields need a look first, <b>Not ready</b> fields are not read yet. Measuring never admits anything.</p></div></div>
      <div className="ba-tiles">
        <span><small>Universities</small><b>{fmtNumber(s.universities||0)}</b><em>{fmtNumber(s.courses||0)} courses</em></span>
        <span><small>Tested, not admitted</small><b>{fmtNumber(by.tested||0)}</b><em>{fmtNumber(by.admitted||0)} admitted</em></span>
        <span><small>Building now</small><b>{fmtNumber(by.building||0)}</b><em>{fmtNumber(by.needs_pages||0)} need pages first</em></span>
        <span><small>Ready fields</small><b>{fmtNumber(s.ready||0)}</b><em>{fmtNumber(s.review||0)} for review · {fmtNumber(s.not_ready||0)} not ready</em></span>
        <span><small>Values the Ready fields add</small><b>+{fmtNumber(s.adds||0)}</b><em>only where the catalogue has none</em></span>
      </div>
    </section>
    <section className="m-panel" data-build-list>
      <div className="m-search-row"><label className="m-searchbox"><Search size={16}/><input value={q} onChange={e=>setQ(e.target.value)} placeholder="Search university…" aria-label="Search university"/>{q&&<button type="button" aria-label="Clear search" onClick={()=>setQ('')}><X size={14}/></button>}</label></div>
      <div className="m-filter-bar ba-filters">
        <label>Country<select className="fv-input" value={country} onChange={e=>setCountry(e.target.value)}><option value="AU">Australia</option><option value="NZ">New Zealand</option><option value="CA">Canada</option><option value="">All countries</option></select></label>
        <label>Stage<select className="fv-input" value={stage} onChange={e=>setStage(e.target.value)} aria-label="Stage"><option value="">Every stage</option>{Object.entries(STAGE).map(([k,[l]])=><option key={k} value={k}>{l}{by[k]!=null?` (${fmtNumber(by[k])})`:''}</option>)}</select></label>
        {wave&&<span className="cf-filter-chip">Wave: {wave}<button type="button" aria-label="Remove wave filter" onClick={()=>onWave('')}><X size={12}/></button></span>}
        <Button compact onClick={load} disabled={busy}><RefreshCw size={13}/>Refresh</Button>
        {rank>=5&&picked.length>0&&<Button compact variant="primary" onClick={build} data-build-picked><Hammer size={13}/>Build {picked.length} selected</Button>}
      </div>
      {msg&&<p className="ba-note" role="status">{msg}</p>}
      {!data?<Loading label="Loading universities…"/>:items.length===0?<Empty text="No university matches these filters."/>:
      <div className="dense-table-wrap"><table className="dense-table ba-table"><thead><tr>{rank>=5&&<th><span className="sr-only">Pick</span></th>}<th><span>University</span></th><th><span>Stage</span></th><th className="num"><span>Courses</span></th><th className="num"><span>Pages read</span></th><th><span>Fields: ready · review · not ready</span></th><th className="num"><span>Adds</span></th><th><span>Measured</span></th></tr></thead>
        <tbody>{items.map(r=><tr key={r.provider_id} data-build-row={r.provider_id}>
          {rank>=5&&<td><input type="checkbox" aria-label={`Pick ${r.name}`} checked={picked.includes(r.provider_id)} onChange={()=>flip(r.provider_id)}/></td>}
          <td><button type="button" className="cf-link ba-name" onClick={()=>onOpen(r.provider_id)}>{r.name}</button><small className="ba-muted">{r.country}{r.wave?` · wave ${r.wave}`:''}{r.stage==='needs_pages'||r.stage==='stopped'?` · ${String(r.stop_reason||'').replaceAll('_',' ')}`:''}</small></td>
          <td><Chip value={r.stage} map={STAGE}/></td>
          <td className="num">{fmtNumber(r.courses||0)}</td>
          <td className="num">{r.pages_read==null?'—':fmtNumber(r.pages_read)}</td>
          <td><Bar r={r}/></td>
          <td className="num">{r.adds?`+${fmtNumber(r.adds)}`:'—'}</td>
          <td className="ba-muted">{r.checked_at?fmtDateTime(r.checked_at):'—'}</td>
        </tr>)}</tbody></table></div>}
      {data&&<Pager offset={offset} limit={PAGE} total={Number(data.total||0)} onOffset={setOffset}/>}
    </section>
  </>
}

function University({pid,rank,onError,onBack}){
  const[d,setD]=useState(null),[busy,setBusy]=useState(''),[done,setDone]=useState(null)
  const load=()=>call('read',{provider_id:pid}).then(setD).catch(e=>onError?.(errText(e)))
  useEffect(()=>{setD(null);setDone(null);load()},[pid])
  if(!d)return <section className="m-panel"><Loading label="Measuring the eight fields…"/></section>
  const f=d.fields||{},ready=(d.ready||[]).filter(k=>!(['intakes','fee','english','delivery'].includes(k)&&f[k]?.admitted)),pages=d.pages||{}
  const admit=async()=>{const reason=ask(`Admit the ${ready.length} Ready field${ready.length===1?'':'s'} for ${d.university?.name}: ${ready.map(k=>FIELD_LABEL[k]).join(', ')}? Review and Not ready fields are left alone.`);if(!reason)return
    setBusy('admit');try{const r=await call('admit',{provider_id:pid,reason});setDone(r?.admitted?.[0]||{});await load()}catch(e){onError?.(errText(e))}finally{setBusy('')}}
  const build=async()=>{const reason=ask(`Build the adapter for ${d.university?.name} again? Onboarding runs in the background (sample pages, AI proposal, apply, measure).`);if(!reason)return
    setBusy('build');try{const r=await call('build',{provider_id:pid,reason});setDone({built:r});await load()}catch(e){onError?.(errText(e))}finally{setBusy('')}}
  const b=d.build
  return <>
    <section className="m-panel" data-build-university={pid}>
      <button type="button" className="cf-link ba-back" onClick={onBack}><ArrowLeft size={14}/>All universities</button>
      <div className="m-workspace-head"><div><h2>{d.university?.name}</h2><p>{d.university?.country}{d.university?.website?<> · <a className="cf-link" href={d.university.website} target="_blank" rel="noreferrer">{d.university.website}</a></>:null}{d.wave?` · wave ${d.wave}`:''} · measured {fmtDateTime(d.measured_at)}</p></div>
        <div className="ba-actions">
          {rank>=5&&<Button compact onClick={build} disabled={!!busy||(b&&!['done','cancelled','stopped'].includes(b.status))}><Hammer size={13}/>{d.has_adapter?'Build again':'Build adapter'}</Button>}
          {rank>=6&&<Button compact variant="primary" onClick={admit} disabled={!!busy||ready.length===0} data-build-admit><ShieldCheck size={13}/>{ready.length?`Admit ${ready.length} Ready field${ready.length===1?'':'s'}`:'Nothing Ready to admit'}</Button>}
        </div></div>
      <div className="ba-tiles">
        <span><small>Courses</small><b>{fmtNumber(d.courses||0)}</b><em>active</em></span>
        <span><small>Pages read</small><b>{fmtNumber(d.pages_read||0)}</b><em>of {fmtNumber(pages.bound||0)} linked</em></span>
        <span><small>Pages of another course</small><b>{fmtNumber(pages.other_course||0)}</b><em>{fmtNumber(pages.unreadable||0)} could not be read</em></span>
        <span><small>Links fixed</small><b>{fmtNumber(d.links_fixed||0)}</b><em>by rule or by hand</em></span>
        <span><small>Adds when admitted</small><b>+{fmtNumber(d.adds||0)}</b><em>AI so far US${Number(d.ai_cost_usd||0).toFixed(2)}</em></span>
      </div>
      {b&&<p className="ba-note" data-build-onboarding>Build: <b>{String(b.status||'').replaceAll('_',' ')}</b>{b.stop_reason?` (${String(b.stop_reason).replaceAll('_',' ')})`:''}{b.note?` — ${b.note}`:''}</p>}
      {done&&<p className="ba-note is-done" role="status" data-build-done>{done.built?`Build: ${fmtNumber(done.built.started||0)} started, ${fmtNumber(done.built.retried||0)} retried, ${fmtNumber(done.built.already_building||0)} already building.`:
        `Admitted. Adapter fields: ${(done.adapter_fields||[]).map(k=>FIELD_LABEL[k]).join(', ')||'none'}. Enrichment task: ${(done.enrich_fields||[]).map(k=>FIELD_LABEL[k]).join(', ')||'none'}. Majors written: ${fmtNumber(done.majors_written||0)}. Left for review: ${(done.left_for_review||[]).map(k=>FIELD_LABEL[k]).join(', ')||'none'}.`}</p>}
    </section>
    <section className="m-panel" data-build-fields>
      <div className="dense-table-wrap"><table className="dense-table ba-table"><thead><tr><th><span>Field</span></th><th><span>State</span></th><th className="num"><span>Read on</span></th><th className="num"><span>Agrees</span></th><th className="num"><span>Adds</span></th><th><span>Admitted through</span></th><th><span>Why</span></th></tr></thead>
        <tbody>{FIELDS.map(([k,label])=>{const x=f[k]||{};return <tr key={k} data-build-field={k} data-state={x.state}>
          <td><b>{label}</b></td>
          <td><Chip value={x.state} map={STATE}/>{x.admitted&&<span className="cf-chip tone-success ba-admitted">Admitted</span>}</td>
          <td className="num">{fmtNumber(x.read||0)} <small className="ba-inline">({pct(x.read_share)})</small></td>
          <td className="num">{x.agree_share==null?'—':pct(x.agree_share)}{x.differ?<small className="ba-inline"> · {fmtNumber(x.differ)} differ</small>:null}</td>
          <td className="num">{x.new?`+${fmtNumber(x.new)}`:'—'}</td>
          <td className="ba-muted">{ROUTE[k]}</td>
          <td>{x.why||'—'}</td></tr>})}</tbody></table></div>
      <p className="ba-note">Ready: read on at least {pct(d.min_read)} of the pages read and, where the catalogue already holds a value, agreeing on at least {pct(d.min_agree)} (Settings › Toolsets & limits). Admitting never replaces a value entered or locked by hand. <a className="cf-link" href={hrefFor('layer2','builder',{provider:pid})}>Open in Adapter builder</a> · <a className="cf-link" href={hrefFor('layer2','adapters',{provider:pid})}>Open adapter</a></p>
    </section>
  </>
}

function Waves({onError,onPick}){
  const[d,setD]=useState(null)
  useEffect(()=>{call('waves',{country:null}).then(setD).catch(e=>onError?.(errText(e)))},[])
  if(!d)return <section className="m-panel"><Loading label="Loading waves…"/></section>
  const w=d.waves||[]
  return <section className="m-panel" data-build-waves>
    <div className="m-workspace-head"><div><h2>Waves</h2><p>Universities built together. Name a wave when you build selected universities; open a wave to see its universities.</p></div></div>
    {w.length===0?<Empty text="No wave yet. Tick universities on the Universities view and build them with a wave name."/>:
    <div className="dense-table-wrap"><table className="dense-table ba-table"><thead><tr><th><span>Wave</span></th><th className="num"><span>Universities</span></th><th className="num"><span>Courses</span></th><th><span>Stages</span></th><th><span>Fields: ready · review · not ready</span></th><th className="num"><span>Adds</span></th></tr></thead>
      <tbody>{w.map(x=><tr key={x.wave} data-build-wave={x.wave}>
        <td><button type="button" className="cf-link ba-name" onClick={()=>onPick(x.wave)}>{x.wave}</button></td>
        <td className="num">{fmtNumber(x.universities||0)}</td><td className="num">{fmtNumber(x.courses||0)}</td>
        <td>{Object.entries(x.by_stage||{}).map(([k,n])=><span key={k} className="ba-stage"><Chip value={k} map={STAGE}/> {fmtNumber(n)}</span>)}</td>
        <td><Bar r={x}/></td><td className="num">{x.adds?`+${fmtNumber(x.adds)}`:'—'}</td></tr>)}</tbody></table></div>}
  </section>
}
