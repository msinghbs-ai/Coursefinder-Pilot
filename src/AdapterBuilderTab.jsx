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

export default function AdapterBuilderTab({rank,onError}){
  const[pid,setPid]=useState(null),[b,setB]=useState(null),[busy,setBusy]=useState(false),[key,setKey]=useState(0)
  const load=async(id=pid)=>{if(!id)return;try{const{data,error}=await supabase.rpc('admin_adapter_builder_basics',{p_action:'basics',p_args:{provider_id:id}});if(error)throw error;setB(data)}catch(e){onError?.(errText(e))}}
  useEffect(()=>{setB(null);load(pid)},[pid])
  if(rank<5)return <Empty text="The adapter builder is for PIM Operators and Platform Admins."/>
  const find=async()=>{const reason=ask(`Add ${b.name} to the Firecrawl targets so its course pages are found and read (Firecrawl credits are used)?`);if(!reason)return
    setBusy(true);try{const{error}=await supabase.rpc('admin_firecrawl_write',{p_action:'target',p_args:{provider_id:b.provider_id,included:true,reason}});if(error)throw error;await load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const read=b?.pages?.read||0
  return <div className="m-page-stack ab-builder" data-adapter-builder-tab>
    <p className="sl-sub">Build or change an adapter in five steps. Each step uses evidence from the provider’s own pages; nothing is admitted until the last step.</p>
    <Step n={1} title="Provider">{b?<p><strong>{b.name}</strong> <small className="sl-sub">{b.country}</small> <Button compact onClick={()=>{setPid(null);setB(null)}}>Change</Button></p>:<PickProvider onPick={setPid} onError={onError}/>}</Step>
    {pid&&!b&&<Loading label="Reading the provider…"/>}
    {b&&<>
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
