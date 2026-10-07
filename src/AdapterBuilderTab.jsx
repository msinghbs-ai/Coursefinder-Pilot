// Layer 2 › Adapter builder (v2.15.211, CF-247, Platform Admin 7 Oct 2026 18:23). One simple screen to build or change an adapter:
// pick a provider (with or without an adapter), see its basics from evidence already held, recognise course attributes on sample
// pages (Firecrawl capture, marks, model proposal), check them against the admit rule, then save and admit. Central pages (key dates,
// fee schedule, English) are attached here and read by the provider-facts job into the existing approval queues.
// Reads: admin_adapter_builder_basics (rank 5). Writes go through the existing functions, each with its own server-side rank check.
import React,{useEffect,useState}from'react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,fmtNumber}from'./ui-kit'
import{AdapterEditor,AdapterReview}from'./FirecrawlWork'

const errText=e=>e?.message||String(e)
const ask=t=>{const r=window.prompt(`${t}\n\nReason (kept in the log):`);return r&&r.trim().length>=4?r.trim():null}
const KIND={intake_calendar:'Key dates (intakes)',fee_schedule:'International fee schedule',english_policy:'English requirements'}
const FIELD={intakes:'Intakes',english:'English (IELTS)',fee:'Fees',delivery:'Delivery'}
const pct=v=>v==null?'—':`${Math.round(Number(v)*100)}%`
const stateLabel=a=>!a?'No adapter yet':!a.enabled?'Switched off':a.admit?`Admitting: ${(a.admit_fields||[]).map(f=>FIELD[f]||f).join(', ')||'none'}`:'Testing (not admitting)'

function Step({n,title,children,hint}){return <section className="ab-step" data-builder-step={n}><h3 className="sl-h4"><span className="ab-num">{n}</span> {title}</h3>{hint&&<p className="sl-sub">{hint}</p>}{children}</section>}

function PickProvider({onPick,onError}){
  const[q,setQ]=useState(''),[list,setList]=useState(null)
  useEffect(()=>{if(q.trim().length<2){setList(null);return}const t=setTimeout(async()=>{try{const{data,error}=await supabase.rpc('admin_adapter_builder_basics',{p_action:'search',p_args:{q:q.trim()}});if(error)throw error;setList(data?.providers||[])}catch(e){onError?.(errText(e))}},350);return()=>clearTimeout(t)},[q])
  return <div className="ab-pick"><input type="search" aria-label="Find a provider" placeholder="Type a provider name or website" value={q} onChange={e=>setQ(e.target.value)}/>
    {list&&(list.length?<ul className="ab-results">{list.map(p=><li key={p.provider_id}><button type="button" className="ab-result" onClick={()=>onPick(p.provider_id)}><strong>{p.name}</strong> <small className="sl-sub">{p.country} · {fmtNumber(p.courses)} courses · {p.adapter?`adapter ${p.adapter}`:'new (no adapter)'}</small></button></li>)}</ul>:<Empty text="No active provider matches."/>)}</div>
}

function CentralPages({b,onDone,onError}){
  const[kind,setKind]=useState('intake_calendar'),[url,setUrl]=useState(''),[busy,setBusy]=useState(false)
  const add=async(k,u)=>{const reason=ask(`Attach this ${KIND[k].toLowerCase()} page for ${b.name}?\n${u}\nIt is read through Firecrawl within about 10 minutes and its proposal waits for approval (Layer 4 › Attributes).`);if(!reason)return
    setBusy(true);try{const{error}=await supabase.rpc('admin_provider_central_page',{p_action:'add',p_args:{provider_id:b.provider_id,kind:k,url:u,reason}});if(error)throw error;setUrl('');onDone()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const have=b.central||[],sug=b.suggested||[]
  return <div className="ab-central">
    {have.length>0?<ul className="tn-list">{have.slice(0,8).map((c,i)=><li key={i}><strong>{KIND[c.kind]||c.kind}</strong> <small className="sl-sub">{c.status}{c.decision?` · ${c.decision}`:''} · <a href={c.url} target="_blank" rel="noreferrer">{c.url}</a></small></li>)}</ul>:<p className="sl-sub">No central page attached yet.</p>}
    {b.can_manage&&sug.length>0&&<><p className="sl-sub">Found among this provider’s stored links:</p><ul className="tn-list">{sug.map((s,i)=><li key={i}><Button compact disabled={busy} onClick={()=>add(s.kind,s.url)}>Attach</Button> <strong>{KIND[s.kind]}</strong> <small className="sl-sub"><a href={s.url} target="_blank" rel="noreferrer">{s.url}</a></small></li>)}</ul></>}
    {b.can_manage&&<div className="ab-add"><select aria-label="Central page kind" value={kind} onChange={e=>setKind(e.target.value)}>{Object.entries(KIND).map(([k,l])=><option key={k} value={k}>{l}</option>)}</select>
      <input aria-label="Central page address" placeholder="https://…" value={url} onChange={e=>setUrl(e.target.value)}/><Button compact disabled={busy||!/^https?:\/\/\S{8,}$/.test(url.trim())} onClick={()=>add(kind,url.trim())}>Attach</Button></div>}
  </div>
}

function Qualify({q}){
  const f=q?.fields||{}
  const rows=Object.keys(FIELD).filter(k=>f[k])
  if(!rows.length)return <p className="sl-sub">Nothing measured yet: save the adapter and apply it to the stored pages first.</p>
  return <div className="cf-table-wrap"><table className="cf-table" data-builder-qualify><thead><tr><th>Field</th><th>Pages read</th><th>Read on</th><th>Agrees with held value</th><th>Result</th></tr></thead><tbody>
    {rows.map(k=><tr key={k}><td>{FIELD[k]}</td><td>{fmtNumber(f[k].read)}</td><td>{pct(f[k].read_share)}</td><td>{pct(f[k].agree_share)}</td><td>{f[k].pass?<span className="cf-chip tone-success">Passes</span>:<span className="cf-chip tone-neutral">{f[k].why}</span>}</td></tr>)}
  </tbody></table><p className="sl-sub">Admit rule: read on at least half the pages, at least 3 pages, and at least 90% agreement (or checked by hand). A pass is a measure, not a switch: admitting is the separate step below.</p></div>
}

// v2.15.215 (Platform Admin, 7 Oct 2026 22:12): guided build. One button per step, each run by the Platform Admin under their own sign-in
// through the existing functions and their own server checks: find pages (Firecrawl target), capture samples, the pinned OpenRouter model
// proposes the settings, save in testing and apply, qualify, then admit only the fields ready to admit. Nothing runs on a schedule and a
// passing check never admits by itself. Ready to admit: passes the admit rule AND agrees with held values (90%+ on 3+ courses, read on 5+ pages).
export function readyFields(q){const f=q?.fields||{},ready=[],held={}
  for(const k of Object.keys(FIELD)){const x=f[k];if(!x)continue
    const why=!x.pass?(x.why||'does not pass'):Number(x.read||0)<5?'read on fewer than 5 pages':(Number(x.agree||0)<3||x.agree_share==null)?'not enough held values to check against (needs 3 agreeing courses)':Number(x.agree_share)<0.9?'agrees on under 90% of checked courses':null
    if(why)held[k]=why;else ready.push(k)}
  return{ready,held}}
function GStep({n,title,state,children}){return <li className={`ab-g-step is-${state}`} data-guided-step={n}><div className="ab-g-head"><span className="ab-num">{state==='done'?'✓':n}</span><strong>{title}</strong>{state==='busy'&&<span className="m-spinner tiny"/>}</div><div className="ab-g-body">{children}</div></li>}
// v2.15.218 (Platform Admin, 8 Oct 2026 10:31): the model for this adapter, chosen by a Platform Admin from the models enabled and qualified for
// intake work (Models & services). One fixed model per adapter; the default is the builder setting.
function ModelPick({r,pid,name,busy,onDone,onError}){
  const m=r?.model,list=r?.models||[]
  if(!m)return null
  const change=async code=>{const reason=window.prompt(`Use ${code?list.find(x=>x.code===code)?.model:'the default model'} for ${name}'s adapter proposals?\n\nReason (kept in the log):`);if(!reason||reason.trim().length<4)return;try{const{error}=await supabase.rpc('admin_adapter_builder',{p_action:'model',p_args:{provider_id:pid,profile_code:code,reason:reason.trim()}});if(error)throw error;await onDone()}catch(e){onError?.(errText(e))}}
  return <div className="ab-model" data-adapter-model><small className="sl-sub">Model: <strong>{m.model}</strong> {m.chosen?'(chosen for this adapter)':'(default)'}</small>
    {r.can_manage&&list.length>0&&<select aria-label="Model for this adapter" disabled={busy} value={m.chosen?m.code:''} onChange={e=>change(e.target.value)}><option value="">Default ({list.find(x=>x.code===m.code)?.model||m.model})</option>{list.map(x=><option key={x.code} value={x.code}>{x.model}</option>)}</select>}</div>
}
// v2.15.218: pick any of the provider's stored course pages as a sample (Platform Admin), e.g. a course whose page prints the fee
function SamplePick({r,pid,busy,onDone,onError}){
  const[q,setQ]=useState(''),[msg,setMsg]=useState('')
  const pages=r?.pages||[],dr=(r?.drafts||[])[0],have=new Set((dr?.samples||[]).map(s=>s.url))
  if(!r?.can_manage||!pages.length)return null
  const t=q.trim().toLowerCase(),hits=t.length<2?[]:pages.filter(p=>`${p.course} ${p.code||''} ${p.url}`.toLowerCase().includes(t)).slice(0,8)
  const add=async p=>{const reason=window.prompt(`Add ${p.course} as a sample? Firecrawl captures it (about 1 credit).\n\nReason (kept in the log):`);if(!reason||reason.trim().length<4)return;try{const{error}=await supabase.rpc('admin_adapter_builder',{p_action:'add_sample',p_args:{provider_id:pid,url:p.url,reason:reason.trim()}});if(error)throw error;setMsg(`${p.course} added; it is captured in about a minute.`);setQ('');await onDone()}catch(e){onError?.(errText(e))}}
  return <div className="ab-sample-pick" data-sample-pick>
    {dr&&(dr.samples||[]).length>0&&<small className="sl-sub">Samples: {(dr.samples||[]).map(s=>s.course).join(' · ')}</small>}
    <input type="search" aria-label="Add a course as a sample" placeholder={`Add a course as a sample (${pages.length} pages)`} value={q} disabled={busy} onChange={e=>setQ(e.target.value)}/>
    {hits.length>0&&<ul className="ab-results">{hits.map(p=><li key={p.url}><button type="button" className="ab-result" disabled={busy||have.has(p.url)} onClick={()=>add(p)}><strong>{p.course}</strong> <small className="sl-sub">{p.code||''}{p.read?'':' · not read yet'}{have.has(p.url)?' · already a sample':''}</small></button></li>)}</ul>}
    {msg&&<small className="cf-chip tone-info">{msg}</small>}
  </div>
}
function GuidedBuild({b,onChanged,onError}){
  const[r,setR]=useState(null),[busy,setBusy]=useState('')
  const pid=b.provider_id,read=b.pages?.read||0,can=Boolean(b.can_manage)
  const loadDraft=async()=>{try{const{data,error}=await supabase.rpc('admin_adapter_builder',{p_action:'read',p_args:{provider_id:pid}});if(error)throw error;setR(data||{})}catch(e){onError?.(errText(e))}}
  useEffect(()=>{loadDraft()},[pid])
  const dr=(r?.drafts||[])[0],last=(dr?.proposals||[]).slice(-1)[0],captured=(dr?.captures||[]).some(c=>!c.error)
  useEffect(()=>{if(!dr||!['capturing','proposing'].includes(dr.status))return;const t=setTimeout(loadDraft,5000);return()=>clearTimeout(t)},[r])
  const run=async(key,q,fn)=>{const reason=ask(q);if(!reason)return;setBusy(key);try{await fn(reason)}catch(e){onError?.(errText(e))}finally{setBusy('')}}
  const rpc=async(name,args)=>{const{data,error}=await supabase.rpc(name,args);if(error)throw error;return data}
  const a=b.adapter,{ready,held}=readyFields(b.qualify),admitted=a?.admit?(a.admit_fields||[]):[],toAdmit=ready.filter(f=>!admitted.includes(f))
  const proposalOk=last&&last.kind!=='error'&&last.adapter
  const savedAfter=a&&last&&a.updated_at&&new Date(a.updated_at)>=new Date(last.at)
  const st={find:read>=3?'done':'todo',capture:dr&&dr.status==='capturing'?'busy':captured?'done':read>=3?'todo':'wait',
    propose:dr?.status==='proposing'?'busy':proposalOk?'done':captured?'todo':'wait',save:savedAfter?'done':proposalOk?'todo':'wait',
    qualify:savedAfter&&b.qualify?'done':savedAfter?'todo':'wait',admit:toAdmit.length===0&&admitted.length>0?'done':toAdmit.length?'todo':'wait'}
  return <section className="ab-auto" data-guided-build>
    <div className="ab-auto-head"><div><strong>Guided build</strong><p className="sl-sub">Six steps, one button each. The model for this adapter ({r?.model?.model||r?.budget?.model||'not set'}) proposes the settings; you run every step and admit only the fields that pass the checks. AI today US$ {Number(r?.budget?.used_usd||0).toFixed(3)} of {r?.budget?.limit_usd??'—'}.</p></div></div>
    {!can&&<p className="sl-sub">Running the steps is for Platform Admins; you can follow the progress here.</p>}
    <ol className="ab-guided">
      <GStep n={1} title="Find course pages" state={st.find}><small className="sl-sub">{fmtNumber(read)} read of {fmtNumber(b.pages?.stored||0)} stored (3 needed).</small>
        {can&&read<3&&<Button compact disabled={Boolean(busy)} onClick={()=>run('find',`Add ${b.name} to the Firecrawl targets so the next Find pages run looks for and reads its course pages (credits are used)?`,async reason=>{await rpc('admin_firecrawl_write',{p_action:'target',p_args:{provider_id:pid,included:true,reason}});onChanged?.()})}>Add to Firecrawl targets</Button>}</GStep>
      <GStep n={2} title="Capture sample pages" state={st.capture}><small className="sl-sub">{dr?`${(dr.captures||[]).filter(c=>!c.error).length} of ${(dr.captures||[]).length} captured (${dr.status}).`:'Firecrawl captures 6 course pages spread across course types (about 1 credit each). Add a particular course with Use as sample in the course list below.'}</small>
        <SamplePick r={r} pid={pid} busy={Boolean(busy)||st.capture==='busy'} onDone={loadDraft} onError={onError}/>
        {can&&st.capture!=='wait'&&<Button compact disabled={Boolean(busy)||st.capture==='busy'} onClick={()=>run('capture',`Capture sample pages of ${b.name} with Firecrawl? About 1 credit a page.`,async reason=>{await rpc('admin_adapter_builder',{p_action:'start',p_args:{provider_id:pid,reason}});await loadDraft()})}>{captured?'Capture again':'Capture samples'}</Button>}</GStep>
      <GStep n={3} title="Model proposes the settings" state={st.propose}>
        <ModelPick r={r} pid={pid} name={b.name} busy={Boolean(busy)} onDone={loadDraft} onError={onError}/><small className="sl-sub">{last?(last.kind==='error'?`Last proposal failed: ${last.error}`:`${last.model} · US$ ${Number(last.cost||0).toFixed(4)} · ${last.reason||''}`):'The pinned model reads the samples and suggests where each attribute is.'}</small>
        {can&&st.propose!=='wait'&&<Button compact disabled={Boolean(busy)||st.propose==='busy'} onClick={()=>run('propose',`Ask the pinned model to propose settings for ${b.name} from the captured samples (uses the AI allowance)?`,async reason=>{await rpc('admin_adapter_builder',{p_action:'propose',p_args:{provider_id:pid,draft_id:dr.id,marks:dr.marks||[],comments:dr.comments||'Propose settings that read international intakes (months), IELTS overall, the international annual fee and delivery from these course pages.',reason}});await loadDraft()})}>{proposalOk?'Propose again':'Ask for a proposal'}</Button>}</GStep>
      <GStep n={4} title="Save in testing and apply" state={st.save}><small className="sl-sub">Saves the proposed settings switched on but not admitting, then reads the stored pages with them.</small>
        {can&&st.save!=='wait'&&<Button compact disabled={Boolean(busy)} onClick={()=>run('save',`Save the proposed settings for ${b.name} (switched on, testing, nothing admitted) and apply them to its stored pages?`,async reason=>{const cur=(await rpc('admin_uni_adapter_read',{p_provider_id:pid}))?.adapter||{};const p=last.adapter||{};const adapter={...cur,...(p.json_source!=null?{json_source:p.json_source}:{}),json_paths:{...(cur.json_paths||{}),...(p.json_paths||{})},patterns:{...(cur.patterns||{}),...(p.patterns||{})},pick:{...(cur.pick||{}),...(p.pick||{})},enabled:true};delete adapter.updated_at;delete adapter.reason;await rpc('admin_uni_adapter_write',{p_action:'save',p_args:{provider_id:pid,adapter,reason}});await rpc('admin_uni_adapter_write',{p_action:'apply',p_args:{provider_id:pid,reason}});onChanged?.()})}>{savedAfter?'Save and apply again':'Save and apply'}</Button>}</GStep>
      <GStep n={5} title="Qualify" state={st.qualify}><small className="sl-sub">Applying takes a few minutes on large sites. Refresh to measure each field against the values already held.</small>
        {st.qualify!=='wait'&&<Button compact disabled={Boolean(busy)} onClick={()=>onChanged?.()}>Refresh the measures</Button>}
        {b.qualify&&<ul className="tn-list" data-guided-qualify>{Object.keys(FIELD).filter(k=>b.qualify.fields?.[k]).map(k=><li key={k}><strong>{FIELD[k]}</strong> <small className="sl-sub">{ready.includes(k)?'ready to admit':`held: ${held[k]}`}{admitted.includes(k)?' · admitting':''}</small></li>)}</ul>}</GStep>
      <GStep n={6} title="Admit the ready fields" state={st.admit}><small className="sl-sub">{toAdmit.length?`Ready: ${toAdmit.map(f=>FIELD[f]).join(', ')}.`:admitted.length?`Admitting: ${admitted.map(f=>FIELD[f]||f).join(', ')}.`:'Nothing is ready to admit yet.'}</small>
        {can&&toAdmit.length>0&&<Button compact variant="primary" disabled={Boolean(busy)} onClick={()=>run('admit',`Admit ${toAdmit.map(f=>FIELD[f]).join(', ')} for ${b.name}? Values read from its pages are written to the catalogue; values entered by hand are never changed.`,async reason=>{await rpc('admin_uni_adapter_control',{p_action:'admit',p_args:{provider_id:pid,admit:true,fields:[...new Set([...admitted,...toAdmit])].sort(),reason}});onChanged?.()})}>Admit these</Button>}</GStep>
    </ol>
  </section>
}

export default function AdapterBuilderTab({rank,onError,initialProvider=''}){
  const[pid,setPid]=useState(initialProvider||null),[b,setB]=useState(null),[busy,setBusy]=useState(false),[key,setKey]=useState(0)
  const load=async(id=pid)=>{if(!id)return;try{const{data,error}=await supabase.rpc('admin_adapter_builder_basics',{p_action:'basics',p_args:{provider_id:id}});if(error)throw error;setB(data)}catch(e){onError?.(errText(e))}}
  useEffect(()=>{setB(null);load(pid)},[pid])
  useEffect(()=>{if(initialProvider&&initialProvider!==pid)setPid(initialProvider)},[initialProvider])
  if(rank<5)return <Empty text="The adapter builder is for PIM Admins and Platform Admins."/>
  const find=async()=>{const reason=ask(`Add ${b.name} to the Firecrawl targets so its course pages are found and read (Firecrawl credits are used)?`);if(!reason)return
    setBusy(true);try{const{error}=await supabase.rpc('admin_firecrawl_write',{p_action:'target',p_args:{provider_id:b.provider_id,included:true,reason}});if(error)throw error;await load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const read=b?.pages?.read||0
  return <div className="m-page-stack ab-builder" data-adapter-builder-tab>
    <p className="sl-sub">Build or change an adapter with the guided build (one button per step), or adjust it by hand below. Each step uses evidence from the provider’s own pages; nothing is admitted until you admit it.</p>
    <Step n={1} title="Provider">{b?<p><strong>{b.name}</strong> <small className="sl-sub">{b.country}</small> <Button compact onClick={()=>{setPid(null);setB(null)}}>Change</Button></p>:<PickProvider onPick={setPid} onError={onError}/>}</Step>
    {pid&&!b&&<Loading label="Reading the provider…"/>}
    {b&&<>
      <GuidedBuild b={b} onChanged={()=>{setKey(k=>k+1);load()}} onError={onError}/>
      <Step n={2} title="Basics">
        <ul className="ab-facts">
          <li><span>Website</span>{b.website?<a href={b.website} target="_blank" rel="noreferrer">{b.website}</a>:'not recorded'}</li>
          <li><span>Active courses</span>{fmtNumber(b.courses)}</li>
          <li><span>Course pages</span>{fmtNumber(read)} read of {fmtNumber(b.pages?.stored||0)} stored{b.pages?.needs_render?` · ${fmtNumber(b.pages.needs_render)} need a browser`:''}</li>
          <li><span>Adapter</span>{stateLabel(b.adapter)}</li>
        </ul>
        {read<3&&<p className="cf-chip tone-warning">Fewer than 3 course pages are read, so there is nothing to build from yet.</p>}
        {read<3&&b.can_manage&&<Button compact disabled={busy} onClick={find}>Find course pages with Firecrawl</Button>}
      </Step>
      <Step n={3} title="Central pages" hint="Key dates, the international fee schedule and English requirements cover every course at once. Attached pages are read and wait for approval in Layer 4 › Attributes.">
        <CentralPages b={b} onDone={()=>load()} onError={onError}/>
      </Step>
      {read>=3&&<Step n={4} title="Recognise course attributes" hint="Capture sample pages, mark which text block or page-data value holds each attribute, and ask for a proposal. Use it, preview it on the stored pages, then save and apply.">
        <AdapterEditor key={key} providerId={b.provider_id} hideReview onError={onError}/>
        <Button compact onClick={()=>{setKey(k=>k+1);load()}}>Refresh the measures</Button>
      </Step>}
      {b.adapter&&<Step n={5} title="Validate and admit" hint="Measured on every read page against the values already held.">
        <Qualify q={b.qualify}/>
        <AdapterReview providerId={b.provider_id} can={Boolean(b.can_manage)} onError={onError}/>
      </Step>}
    </>}
  </div>
}
