// Layer 2 › Adapter builder (v2.15.211, CF-247, Platform Admin 7 Oct 2026 18:23). One simple screen to build or change an adapter:
// pick a provider (with or without an adapter), see its basics from evidence already held, recognise course attributes on sample
// pages (Firecrawl capture, marks, model proposal), check them against the admit rule, then save and admit. Central pages (key dates,
// fee schedule, English) are attached here, read by the provider-facts job and (v2.15.253) approved here in step 1.3.
// Reads: admin_adapter_builder_basics (rank 5). Writes go through the existing functions, each with its own server-side rank check.
import React,{useEffect,useState}from'react'
import{Search,Globe,FileSearch}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,fmtNumber,fmtDate,fmtDateTime}from'./ui-kit'
import JobButton from'./JobButton'
import{AdapterEditor,AdapterReview}from'./FirecrawlWork'
import FeeSchedules from'./FeeSchedules'
import ProviderPolicies from'./ProviderPolicies'

const errText=e=>e?.message||String(e)
// v2.15.232 (Platform Admin, 10 Oct 2026, Fix 5): no reason prompt. Each step writes a standard log line instead (the servers keep
// requiring one). Steps that spend Firecrawl credits or the AI allowance still ask a plain yes/no first.
const ask=(t,{confirm=false}={})=>{if(confirm&&!window.confirm(t))return null;return `Adapter builder: ${String(t).split('\n')[0].replace(/\?$/,'').slice(0,200)}`}
const KIND={intake_calendar:'Key dates (intakes)',fee_schedule:'International fee schedule',english_policy:'English requirements'}
const FIELD={intakes:'Intakes',english:'English (IELTS)',fee:'Fees',delivery:'Delivery'}
const pct=v=>v==null?'—':`${Math.round(Number(v)*100)}%`
const stateLabel=a=>!a?'No adapter yet':!a.enabled?'Switched off':a.admit?`Admitting: ${(a.admit_fields||[]).map(f=>FIELD[f]||f).join(', ')||'none'}`:'Testing (not admitting)'

function Step({n,title,children,hint}){return <section className="ab-step" data-builder-step={n}><h3 className="sl-h4"><span className="ab-num">{n}</span> {title}</h3>{hint&&<p className="ab-text">{hint}</p>}{children}</section>}
// v2.15.245 (Platform Admin bugs 11/10-2, Fix 6): one numbering for the whole build. 1 Provider (1.1 Website, 1.2 Contacts, 1.3 Central
// pages), 2 Course pages (2.1 Find, 2.2 Capture samples), 3 Adapter (3.1 Propose, 3.2 Save and apply, 3.3 Qualify, 3.4 Admit), 4 Adjust by hand.
function SubStep({n,title,state,children}){return <div className={`ab-sub is-${state||'todo'}`} data-builder-step={n}><div className="ab-sub-head"><span className="ab-num">{state==='done'?'✓':n}</span><strong>{title}</strong>{state==='busy'&&<span className="m-spinner tiny"/>}</div><div className="ab-sub-body">{children}</div></div>}
const SITE_SOURCE={search_verified_cricos_code:'found by search and verified: its CRICOS code is on the site',search_verified_name_on_home_page:'found by search and verified: its name is on the home page',search_verified_name_in_page_and_domain:'found by search and verified: its name is on the site and in the address',search_verified_dli_number:'found by search and verified: its DLI number is on the site',manual:'entered by hand'}
// 1.1 Website (Fix 3, Features 2 and 3). A website found and verified by search goes on the record by itself; with none, the search runs
// on its own (every provider without a website is queued), Fill in from website runs it now, or a person enters it.
function WebsiteStep({b,onChanged,onError}){
  const[url,setUrl]=useState(''),[msg,setMsg]=useState(''),[busy,setBusy]=useState(false)
  const w=b.website_found||{},can=Boolean(b.can_manage)
  const save=async()=>{setBusy(true);setMsg('');try{const{error}=await supabase.rpc('admin_provider_website_set',{p_provider_id:b.provider_id,p_url:url.trim()});if(error)throw error;setMsg('Website saved (entered by hand). Its course pages, contacts and central pages are now looked for; refresh in a few minutes.');setUrl('');onChanged?.()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const src=b.website&&w.website&&b.website.replace(/\/$/,'')===String(w.website).replace(/\/$/,'')?SITE_SOURCE[w.source]:null
  return <div data-website-step>
    {b.website?<p className="ab-text"><a href={b.website} target="_blank" rel="noreferrer"><strong>{b.website}</strong></a>{src&&<span className="ab-muted"> · {src}</span>}</p>
      :<p className="ab-text">No website is recorded yet. {w.status==='no_website'?(w.searched_at?`The last search found none that could be verified${w.note?` (${w.note})`:''}.`:'It is waiting its turn in the website search.'):'It is searched for automatically.'} Everything after this step (course pages, contacts, central pages) depends on it.</p>}
    <div className="ab-actions">
      <JobButton kind="provider_fill" scope={b.provider_id} args={{provider_id:b.provider_id}} icon={Globe} disabled={!can} label={b.website?'Fill in from website again':'Fill in from website'} onFinished={onChanged}
        question={`Fill in ${b.name} from its website?${b.website?'':' Its website is searched for and verified first (about 2 Firecrawl credits).'} Its public contacts are read and its central pages are looked for (about 1 credit).`}/>
    </div>
    {!b.website&&can&&<div className="ab-add"><input aria-label="Provider's own website" type="url" placeholder="https://www.provider.edu.au" value={url} disabled={busy} onChange={e=>setUrl(e.target.value)}/>
      <Button compact disabled={busy||!/^https?:\/\/\S+\.\S+$/.test(url.trim())} onClick={save}>Save website (entered by hand)</Button></div>}
    {b.website&&<small className="ab-muted">Contacts, central pages and course pages are read by themselves after the website is set or changed; press Fill in from website again only to read them again now.</small>}
    {msg&&<p className="cf-chip tone-info" role="status">{msg}</p>}
    <WebsiteCheck b={b} onChanged={onChanged} onError={onError}/>
  </div>
}
// v2.15.288 (bug 18/10-01, Platform Admin 18 Oct 2026 20:35 "validate or change the website in the adapter builder"): Check website reads
// the home page now (it answers, it is not a third-party site, the provider's CRICOS code or name is on it, or it is the site the register
// lists). Change website (Platform Admin) is checked the same way and saved only when Verified or Likely; course-page searches, a stopped
// or held search, contacts and central pages then start again. A second site of the same provider is kept as an extra source.
// Reads and writes: admin_provider_website_check (list, check, change).
const VERDICT={verified:['Verified','success'],likely:['Likely','warning'],failed:['Failed','danger']}
const yes=v=>v===true?'yes':v===false?'no':'—'
function WebsiteCheck({b,onChanged,onError}){
  const[d,setD]=useState(null),[open,setOpen]=useState(false),[url,setUrl]=useState(''),[extra,setExtra]=useState(''),[reason,setReason]=useState(''),[busy,setBusy]=useState(false)
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_provider_website_check',{p_action:'list',p_args:{provider_id:b.provider_id}});if(error)throw error;setD(data&&typeof data==='object'&&'checks' in data?data:null)}catch{setD(null)}} // quiet: the panel simply does not show
  useEffect(()=>{setD(null);load()},[b.provider_id])
  const last=d?.checks?.[0],running=Boolean(last&&last.state!=='done')
  useEffect(()=>{if(!running)return;const t=setTimeout(async()=>{await load();},5000);return()=>clearTimeout(t)},[d])
  useEffect(()=>{if(last?.applied)onChanged?.()},[last?.id,last?.applied])
  const go=async(action)=>{setBusy(true);try{
      const args={provider_id:b.provider_id,...(action==='change'?{url:url.trim(),extra_site:extra.trim()||null,reason:reason.trim()||ask(`Change website of ${b.name} to ${url.trim()}`)}:{})}
      const{error}=await supabase.rpc('admin_provider_website_check',{p_action:action,p_args:args});if(error)throw error
      if(action==='change'){setOpen(false);setUrl('');setExtra('');setReason('')}
      await load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  if(!d)return null
  const sites=d.sites||[],r=last?.result||{},v=VERDICT[last?.verdict],n=last?.apply_note||{}
  return <div className="ab-sitecheck" data-website-check>
    {sites.length>1&&<p className="cf-chip tone-warning" data-website-multi>This record holds {sites.length} addresses ({sites.join(', ')}). Keep one main website with Change website; the other is kept as an extra source.</p>}
    <div className="ab-actions">
      {d.website&&<Button compact disabled={busy||running} onClick={()=>go('check')} data-website-check-run>{running&&last?.action==='check'?'Checking…':'Check website'}</Button>}
      {d.can_change&&<Button compact disabled={busy||running} onClick={()=>{setOpen(!open);if(!url&&sites.length>1){setUrl(sites[0]);setExtra(sites[1])}}} data-website-change-open>Change website</Button>}
    </div>
    {open&&d.can_change&&<div className="ab-add" data-website-change-form>
      <input aria-label="New website" type="url" placeholder="https://www.provider.edu.au" value={url} disabled={busy} onChange={e=>setUrl(e.target.value)}/>
      <input aria-label="Other site of this provider (optional)" type="url" placeholder="Other site of this provider (optional)" value={extra} disabled={busy} onChange={e=>setExtra(e.target.value)}/>
      <input aria-label="Reason" type="text" placeholder="Reason (for the log)" value={reason} disabled={busy} onChange={e=>setReason(e.target.value)}/>
      <Button compact disabled={busy||!/^(https?:\/\/)?[^\s,;]+\.[^\s,;]+$/.test(url.trim())} onClick={()=>go('change')} data-website-change-save>Check and save</Button>
      <small className="ab-muted">The new address is checked first (its home page is read now; about 1 Firecrawl credit only if the site refuses a direct read) and saved only when Verified or Likely. Course-page searches, a stopped or held search, contacts and central pages then start again.</small>
    </div>}
    {last&&<div className="ab-checkresult" data-website-result={last.verdict||last.state}>
      <p className="ab-text">{last.action==='change'?'Change to':'Check of'} <strong>{last.url}</strong>{' · '}{fmtDateTime(last.checked_at||last.requested_at)}{' · '}
        {running?<span className="cf-chip tone-info">Checking…</span>:v?<span className={`cf-chip tone-${v[1]}`}>{v[0]}</span>:null}{last.why&&<span> {last.why}</span>}</p>
      {!running&&last.result&&<ul className="ab-facts" data-website-evidence>
        <li>Answers: {yes(r.answers)}{r.http?` (HTTP ${r.http}${r.via==='scraper'?', read through the scraper':''})`:''}{r.redirected?` · goes to ${r.final_url}`:''}</li>
        <li>Third-party site: {yes(r.third_party)}</li>
        {r.cricos_code&&<li>CRICOS code {r.cricos_code} on the home page: {yes(r.cricos_on_site)}</li>}
        {r.register_site&&<li>The site the register lists ({r.register_site}): {yes(r.register_match)}</li>}
        <li>Provider's name on the home page: {r.name_basis?'yes':'no'} · address fits the name: {yes(r.domain_fits)}</li>
        {r.title&&<li>Page title: {r.title}</li>}
      </ul>}
      {last.action==='change'&&!running&&(last.applied?<p className="cf-chip tone-success" data-website-applied>Saved {n.saved}{n.before?` (was ${n.before})`:''}. Course-page searches queued again: {fmtNumber(n.searches_queued||0)}; search resumed; contacts and central pages queued{n.extra_site?`; ${n.extra_site} kept as an extra source`:''}{n.pages_on_old_address?`; ${fmtNumber(n.pages_on_old_address)} course pages on the old address are left for relinking`:''}. All of this runs by itself: follow it in the guide at the top; nothing to press.</p>
        :<p className="cf-chip tone-warning">Not saved{n.error?`: ${n.error}`:last.verdict==='failed'?': the check failed':''}.</p>)}
    </div>}
  </div>
}
function ContactsStep({b}){
  const c=b.contacts||{}
  return <ul className="ab-facts" data-contacts-step>
    <li><span>Public phone</span>{c.phone||'not found yet'}</li>
    <li><span>Public email</span>{c.email||'not found yet'}</li>
    <li><span>Last read from the site</span>{c.checked_at&&c.outcome!=='requested'?fmtDateTime(c.checked_at):'not yet'}{c.outcome&&!['leased','requested'].includes(c.outcome)?` · ${c.outcome.replace(/_/g,' ')}`:''}</li>
  </ul>
}
const PAGE_STATE={read:['Read','tone-success'],stored:['Stored, not read yet','tone-info'],searching:['Searching','tone-info'],not_found:['Not found on the site','tone-warning'],no_page:['No page yet','tone-neutral']}
// 2.1 (Feature 1): every course and where its page stands, from the CRICOS course list; the ones without a page are searched on the
// provider's own site with Firecrawl as a task (Task manager), or entered by hand below.
function CourseList({b,onChanged}){
  const[show,setShow]=useState('need'),[pick,setPick]=useState([])
  const list=b.course_list||[],count=k=>list.filter(c=>c.state===k).length
  const need=list.filter(c=>c.state!=='read'&&c.state!=='stored'),rows=(show==='need'?list.filter(c=>c.state!=='read'):list).slice(0,200)
  const toggle=id=>setPick(p=>p.includes(id)?p.filter(x=>x!==id):[...p,id])
  if(!list.length)return <p className="ab-text">No active courses.</p>
  return <div className="ab-courses" data-course-list>
    <p className="ab-text">{Object.keys(PAGE_STATE).filter(k=>count(k)).map(k=><span key={k} className={`cf-chip ${PAGE_STATE[k][1]}`}>{PAGE_STATE[k][0]}: {fmtNumber(count(k))}</span>)}</p>
    <div className="ab-actions">
      {b.website?<JobButton kind="course_page_find" scope={b.provider_id} icon={FileSearch} disabled={!b.can_manage||(!pick.length&&!need.length)} onFinished={()=>{setPick([]);onChanged?.()}}
          args={{provider_id:b.provider_id,...(pick.length?{course_ids:pick}:{})}}
          label={pick.length?`Find ${fmtNumber(pick.length)} ticked with Firecrawl`:`Find every missing page with Firecrawl (${fmtNumber(need.length)})`}
          question={`Search ${b.website} for the official page of ${pick.length?`${pick.length} ticked course(s)`:`${need.length} course(s) without a page`}? About 2 Firecrawl credits a course.`}/>
        :<small className="ab-text">Record the website in step 1.1 first: course pages are searched on it.</small>}
      <label className="tn-check"><input type="checkbox" checked={show==='all'} onChange={e=>setShow(e.target.checked?'all':'need')}/> Show courses already read</label>
    </div>
    <div className="cf-table-wrap ab-course-table"><table className="cf-table"><thead><tr><th aria-label="Tick"/><th>Course</th><th>Page</th></tr></thead><tbody>
      {rows.map(c=><tr key={c.course_id}><td><input type="checkbox" aria-label={`Tick ${c.title}`} checked={pick.includes(c.course_id)} disabled={c.state==='read'} onChange={()=>toggle(c.course_id)}/></td>
        <td><strong>{c.title}</strong>{c.code&&<span className="ab-muted"> · {c.code}</span>}</td>
        <td><span className={`cf-chip ${PAGE_STATE[c.state]?.[1]||'tone-neutral'}`}>{PAGE_STATE[c.state]?.[0]||c.state}</span>{c.url&&<> <a href={c.url} target="_blank" rel="noreferrer" className="ab-muted">{c.url.replace(/^https?:\/\//,'').slice(0,70)}</a></>}</td></tr>)}
    </tbody></table></div>
    {rows.length<(show==='need'?list.filter(c=>c.state!=='read').length:list.length)&&<small className="ab-muted">The first 200 are shown.</small>}
  </div>
}

function PickProvider({onPick,onError}){
  const[q,setQ]=useState(''),[list,setList]=useState(null)
  useEffect(()=>{if(q.trim().length<2){setList(null);return}const t=setTimeout(async()=>{try{const{data,error}=await supabase.rpc('admin_adapter_builder_basics',{p_action:'search',p_args:{q:q.trim()}});if(error)throw error;setList(data?.providers||[])}catch(e){onError?.(errText(e))}},350);return()=>clearTimeout(t)},[q])
  return <div className="ab-pick"><input type="search" aria-label="Find a provider" placeholder="Type a provider name or website" value={q} onChange={e=>setQ(e.target.value)}/>
    {list&&(list.length?<ul className="ab-results">{list.map(p=><li key={p.provider_id}><button type="button" className="ab-result" onClick={()=>onPick(p.provider_id)}><strong>{p.name}</strong> <small className="sl-sub">{p.country} · {fmtNumber(p.courses)} courses · {p.adapter?`adapter ${p.adapter}`:'new (no adapter)'}</small></button></li>)}</ul>:<Empty text="No active provider matches."/>)}</div>
}

function CentralPages({b,onDone,onError}){
  const[kind,setKind]=useState('intake_calendar'),[url,setUrl]=useState(''),[busy,setBusy]=useState(false)
  const add=async(k,u)=>{const reason=ask(`Attach the ${KIND[k].toLowerCase()} page ${u} for ${b.name}`);if(!reason)return
    setBusy(true);try{const{error}=await supabase.rpc('admin_provider_central_page',{p_action:'add',p_args:{provider_id:b.provider_id,kind:k,url:u,reason}});if(error)throw error;setUrl('');onDone()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const have=b.central||[],sug=b.suggested||[],cs=b.central_search
  return <div className="ab-central">
    {have.length>0?<ul className="tn-list">{have.slice(0,8).map((c,i)=><li key={i}><strong>{KIND[c.kind]||c.kind}</strong> <small className="sl-sub">{c.decision||CENTRAL_STATE[c.status]||c.status} · <a href={c.url} target="_blank" rel="noreferrer">{c.url}</a></small></li>)}</ul>:<p className="sl-sub">No central page attached yet.</p>}
    {cs&&<p className="ab-text" data-central-search>{cs.state==='done'?`Searched with Firecrawl ${cs.searched_at?fmtDate(cs.searched_at):''}: ${fmtNumber(cs.found)} likely page(s) among ${fmtNumber(cs.addresses||0)} addresses on the site.`:cs.state==='failed'?`The Firecrawl search failed${cs.error?` (${cs.error})`:''}.`:cs.state==='leased'?'Searching the site with Firecrawl now…':'Waiting its turn in the Firecrawl search of the site.'}</p>}
    {b.can_manage&&sug.length>0&&<><p className="ab-text">Suggested (attach the right one):</p><ul className="tn-list">{sug.map((s,i)=><li key={i}><Button compact disabled={busy} onClick={()=>add(s.kind,s.url)}>Attach</Button> <strong>{KIND[s.kind]}</strong> <span className="ab-muted">{s.source==='map'?'found by Firecrawl':'from stored links'} · <a href={s.url} target="_blank" rel="noreferrer">{s.url}</a></span></li>)}</ul></>}
    {b.can_manage&&<div className="ab-add"><select aria-label="Central page kind" value={kind} onChange={e=>setKind(e.target.value)}>{Object.entries(KIND).map(([k,l])=><option key={k} value={k}>{l}</option>)}</select>
      <input aria-label="Central page address" placeholder="https://…" value={url} onChange={e=>setUrl(e.target.value)}/><Button compact disabled={busy||!/^https?:\/\/\S{8,}$/.test(url.trim())} onClick={()=>add(kind,url.trim())}>Attach</Button></div>}
  </div>
}

// v2.15.253: this university's fee schedules, English policies and academic calendars waiting for approval (Approve or Reject). The same
// lists, unfiltered, are on Providers › Onboarding › Approvals waiting.
function CentralApprovals({b}){
  const provider={id:b.provider_id,name:b.name}
  return <div className="ab-approvals" data-builder-approvals><p className="ab-text"><strong>Waiting for approval</strong> <span className="ab-muted">Approval fills only courses with no value and none entered by hand.</span></p>
    <FeeSchedules provider={provider}/><ProviderPolicies provider={provider}/></div>
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
// v2.15.218 (Platform Admin, 8 Oct 2026 10:31): the model for this adapter, chosen by a Platform Admin from the models enabled and qualified for
// intake work (Models & services). One fixed model per adapter; the default is the builder setting.
function ModelPick({r,pid,name,busy,onDone,onError}){
  const m=r?.model,list=r?.models||[]
  if(!m)return null
  const change=async code=>{const reason=ask(`Use ${code?list.find(x=>x.code===code)?.model:'the default model'} for ${name}'s adapter proposals`);try{const{error}=await supabase.rpc('admin_adapter_builder',{p_action:'model',p_args:{provider_id:pid,profile_code:code,reason}});if(error)throw error;await onDone()}catch(e){onError?.(errText(e))}}
  return <div className="ab-model" data-adapter-model><small className="sl-sub">Model: <strong>{m.model}</strong> {m.chosen?'(chosen for this adapter)':'(default)'}</small>
    {r.can_manage&&list.length>0&&<select aria-label="Model for this adapter" disabled={busy} value={m.chosen?m.code:''} onChange={e=>change(e.target.value)}><option value="">Default ({list.find(x=>x.code===m.code)?.model||m.model})</option>{list.map(x=><option key={x.code} value={x.code}>{x.model}</option>)}</select>}</div>
}
// v2.15.218: pick any of the provider's stored course pages as a sample (Platform Admin), e.g. a course whose page prints the fee
function SamplePick({r,pid,busy,onDone,onError}){
  const[q,setQ]=useState(''),[msg,setMsg]=useState('')
  const pages=r?.pages||[],dr=(r?.drafts||[])[0],have=new Set((dr?.samples||[]).map(s=>s.url))
  if(!r?.can_manage||!pages.length)return null
  const t=q.trim().toLowerCase(),hits=t.length<2?[]:pages.filter(p=>`${p.course} ${p.code||''} ${p.url}`.toLowerCase().includes(t)).slice(0,8)
  const add=async p=>{const reason=ask(`Add ${p.course} as a sample (Firecrawl, about 1 credit)`);try{const{error}=await supabase.rpc('admin_adapter_builder',{p_action:'add_sample',p_args:{provider_id:pid,url:p.url,reason}});if(error)throw error;setMsg(`${p.course} added; it is captured in about a minute.`);setQ('');await onDone()}catch(e){onError?.(errText(e))}}
  return <div className="ab-sample-pick" data-sample-pick>
    {dr&&(dr.samples||[]).length>0&&<small className="sl-sub">Samples: {(dr.samples||[]).map(s=>s.course).join(' · ')}</small>}
    <input type="search" aria-label="Add a course as a sample" placeholder={`Add a course as a sample (${pages.length} pages)`} value={q} disabled={busy} onChange={e=>setQ(e.target.value)}/>
    {hits.length>0&&<ul className="ab-results">{hits.map(p=><li key={p.url}><button type="button" className="ab-result" disabled={busy||have.has(p.url)} onClick={()=>add(p)}><strong>{p.course}</strong> <small className="sl-sub">{p.code||''}{p.read?'':' · not read yet'}{have.has(p.url)?' · already a sample':''}</small></button></li>)}</ul>}
    {msg&&<small className="cf-chip tone-info">{msg}</small>}
  </div>
}
// v2.15.245: the v2.15.232 FindPages step is replaced by 1.1 Website (search, Fill in from website, entered by hand) and 2.1 (course list, Find with Firecrawl).
// v2.15.232 (Feature 2): a course page entered by hand. It must be on the provider's own website; it becomes the course's official page
// (entered by hand) and is captured as a sample.
function ManualPage({r,pid,busy,onDone,onError}){
  const[q,setQ]=useState(''),[cid,setCid]=useState(''),[url,setUrl]=useState(''),[msg,setMsg]=useState(''),[saving,setSaving]=useState(false)
  if(!r?.can_manage)return null
  const courses=r.courses||[],t=q.trim().toLowerCase(),hits=t.length<2?[]:courses.filter(c=>`${c.course} ${c.code||''}`.toLowerCase().includes(t)).slice(0,8),picked=courses.find(c=>c.id===cid)
  const save=async()=>{setSaving(true);setMsg('');try{const{error}=await supabase.rpc('admin_adapter_builder',{p_action:'add_page',p_args:{provider_id:pid,course_id:cid,url:url.trim(),reason:`Adapter builder: course page entered by hand for ${picked?.course}`}});if(error)throw error;setMsg(`${picked?.course}: page saved as its official page and added as a sample; it is captured in about a minute.`);setQ('');setCid('');setUrl('');await onDone()}catch(e){onError?.(errText(e))}finally{setSaving(false)}}
  return <div className="ab-manual-page" data-manual-page>
    <small className="sl-sub">Or enter a course page by hand{r.website?` (on ${r.website})`:''}:</small>
    {!r.website?<small className="ab-text">Record the provider's own website in step 1.1 first.</small>:<>
      {picked?<p className="sl-sub"><strong>{picked.course}</strong>{picked.code?` · ${picked.code}`:''} <Button compact onClick={()=>setCid('')}>Change course</Button></p>
        :<><input type="search" aria-label="Course for the page" placeholder={`Find the course (${courses.length} active)`} value={q} disabled={busy||saving} onChange={e=>setQ(e.target.value)}/>
          {hits.length>0&&<ul className="ab-results">{hits.map(c=><li key={c.id}><button type="button" className="ab-result" onClick={()=>{setCid(c.id);setQ('')}}><strong>{c.course}</strong> <small className="sl-sub">{c.code||''}</small></button></li>)}</ul>}</>}
      <div className="ab-add"><input aria-label="Course page address" type="url" placeholder="https://… the course's own page" value={url} disabled={busy||saving} onChange={e=>setUrl(e.target.value)}/>
        <Button compact disabled={busy||saving||!cid||!/^https?:\/\/\S+\.\S+$/.test(url.trim())} onClick={save}>Capture this page</Button></div></>}
    {msg&&<small className="cf-chip tone-info" role="status">{msg}</small>}
  </div>
}
// v2.15.289 (Platform Admin 18 Oct 2026 22:03: "flow was not clear ... no movement or clear indication for next step ... find course pages
// are running without me pressing anything ... this has to be intuitive"): one guide at the top says what runs by itself now, what is done,
// and the one next thing for a person, with a button that goes to that step. The page refreshes by itself while work runs.
const CENTRAL_STATE={found:'found, waiting to be read (automatic)',read:'read: approve it in 1.3 if it shows values',parsed:'read'}
export function builderFlow(b,st={}){
  if(!b)return null
  const list=b.course_list||[],searching=list.filter(c=>c.state==='searching').length,read=b.pages?.read||0,stored=b.pages?.stored||0
  const need=list.filter(c=>!['read','stored','searching'].includes(c.state)).length,cs=b.central_search||{},central=b.central||[],c=b.contacts||{}
  const running=[]
  if(!b.website&&b.website_found?.status==='no_website'&&!b.website_found?.searched_at)running.push({step:'1.1',text:'Searching for the website'})
  if(['requested','leased'].includes(c.outcome))running.push({step:'1.2',text:'Reading contacts from the website'})
  if(b.website&&['queued','leased'].includes(cs.state))running.push({step:'1.3',text:'Looking for central pages (key dates, fees, English) on the site'})
  const unread=central.filter(x=>x.status==='found').length
  if(unread)running.push({step:'1.3',text:`Reading ${unread} attached central page(s)`})
  if(searching)running.push({step:'2.1',text:`Finding course pages: ${fmtNumber(searching)} of ${fmtNumber(list.length)} courses being searched`})
  if(stored>read)running.push({step:'2.1',text:`Reading ${fmtNumber(stored-read)} stored course page(s)`})
  if(st.capture==='busy')running.push({step:'2.2',text:'Capturing sample pages'})
  if(st.propose==='busy')running.push({step:'3.1',text:'The model is proposing the settings'})
  const approve=central.filter(x=>x.status==='read'&&!x.decision).length
  const also=approve?{step:'1.3',text:`${approve} central page(s) read: approve or reject the values in 1.3 (optional for the adapter).`}:null
  let next
  if(!b.website)next={step:'1.1',text:'Record the provider’s own website: press Fill in from website (search) or enter it by hand.',you:true}
  else if(read<3&&(searching||stored>read))next={step:'2.1',text:'Nothing to press: course pages are being found and read by themselves. This page refreshes on its own; step 2.2 opens at 3 read pages.',you:false}
  else if(read<3&&need)next={step:'2.1',text:`Find the missing course pages: press Find every missing page with Firecrawl (${fmtNumber(need)}), or enter a page by hand.`,you:true}
  else if(read<3)next={step:'2.1',text:'Fewer than 3 course pages could be read: enter a course page by hand in 2.1, or check the website (1.1).',you:true}
  else if(st.capture==='busy')next={step:'2.2',text:'Nothing to press: sample pages are being captured.',you:false}
  else if(st.capture==='todo')next={step:'2.2',text:'Press Capture samples.',you:true}
  else if(st.propose==='busy')next={step:'3.1',text:'Nothing to press: the model is proposing the settings.',you:false}
  else if(st.propose==='todo')next={step:'3.1',text:'Press Ask for a proposal.',you:true}
  else if(st.save==='todo')next={step:'3.2',text:'Press Save and apply.',you:true}
  else if(st.qualify==='todo')next={step:'3.3',text:'Applying runs by itself for a few minutes; then press Refresh the measures.',you:true}
  else if(st.admit==='todo')next={step:'3.4',text:'Press Admit these.',you:true}
  else if(st.admit==='done')next={step:'3.4',text:'Done: the adapter is admitting. Nothing else to do.',you:false}
  else next={step:'3.3',text:'Nothing passes the checks yet: adjust by hand (step 4) or add better samples (2.2).',you:true}
  const steps=[['1.1','Website',b.website?'done':'you'],['1.2','Contacts',running.some(r=>r.step==='1.2')?'auto':c.phone||c.email?'done':'optional'],
    ['1.3','Central pages',running.some(r=>r.step==='1.3')?'auto':approve?'optional':central.length?'done':'optional'],
    ['2.1','Course pages',read>=3?'done':running.some(r=>r.step==='2.1')?'auto':'you'],['2.2','Samples',st.capture==='done'?'done':st.capture==='busy'?'auto':st.capture==='todo'?'you':'wait'],
    ['3.1','Proposal',st.propose==='done'?'done':st.propose==='busy'?'auto':st.propose==='todo'?'you':'wait'],['3.2','Save and apply',st.save==='done'?'done':st.save==='todo'?'you':'wait'],
    ['3.3','Qualify',st.qualify==='done'?'done':st.qualify==='todo'?'you':'wait'],['3.4','Admit',st.admit==='done'?'done':st.admit==='todo'?'you':'wait']]
  return{running,next,also,steps}
}
const FLOW_CHIP={done:['Done','tone-success'],auto:['Running by itself','tone-info'],you:['Your turn','tone-warning'],optional:['Optional','tone-neutral'],wait:['Later','tone-neutral']}
const goTo=n=>{const el=document.querySelector(`[data-builder-step="${n}"]`);if(el)el.scrollIntoView({behavior:'smooth',block:'start'})}
function BuilderGuide({flow}){
  if(!flow)return null
  const{running,next,also,steps}=flow
  return <div className="ab-guide" data-builder-guide>
    <ol className="ab-flow" aria-label="Steps">{steps.map(([n,label,state])=><li key={n} className={`is-${state}`} data-flow-step={n}><button type="button" className="cf-link" onClick={()=>goTo(n)}><span className="ab-num">{state==='done'?'✓':n}</span> {label}</button> <small className={`cf-chip ${FLOW_CHIP[state][1]}`}>{FLOW_CHIP[state][0]}</small></li>)}</ol>
    <div className={`ab-next ${next.you?'is-you':'is-auto'}`} data-builder-next={next.step}><strong>{next.you?'Next for you':'Now'}</strong> <span>({next.step}) {next.text}</span> <Button compact onClick={()=>goTo(next.step)}>Go to step {next.step}</Button></div>
    {also&&<p className="ab-text" data-builder-also>Also: {also.text} <button type="button" className="cf-link" onClick={()=>goTo(also.step)}>Go to 1.3</button></p>}
    {running.length>0&&<div className="ab-running" data-builder-running><strong>Running by itself</strong> <span className="ab-muted">(refreshes every 15 seconds)</span><ul>{running.map((r,i)=><li key={i}><span className="m-spinner tiny"/> {r.text} <button type="button" className="cf-link" onClick={()=>goTo(r.step)}>{r.step}</button></li>)}</ul></div>}
  </div>
}
function GuidedBuild({b,find,onChanged,onError,onStage}){
  const[r,setR]=useState(null),[busy,setBusy]=useState('')
  const pid=b.provider_id,read=b.pages?.read||0,can=Boolean(b.can_manage)
  const loadDraft=async()=>{try{const{data,error}=await supabase.rpc('admin_adapter_builder',{p_action:'read',p_args:{provider_id:pid}});if(error)throw error;setR(data||{})}catch(e){onError?.(errText(e))}}
  useEffect(()=>{loadDraft()},[pid])
  const dr=(r?.drafts||[])[0],last=(dr?.proposals||[]).slice(-1)[0],captured=(dr?.captures||[]).some(c=>!c.error)
  useEffect(()=>{if(!dr||!['capturing','proposing'].includes(dr.status))return;const t=setTimeout(loadDraft,5000);return()=>clearTimeout(t)},[r])
  const run=async(key,q,fn)=>{const reason=ask(q,{confirm:['capture','propose'].includes(key)});if(!reason)return;setBusy(key);try{await fn(reason)}catch(e){onError?.(errText(e))}finally{setBusy('')}}
  const rpc=async(name,args)=>{const{data,error}=await supabase.rpc(name,args);if(error)throw error;return data}
  const a=b.adapter,{ready,held}=readyFields(b.qualify),admitted=a?.admit?(a.admit_fields||[]):[],toAdmit=ready.filter(f=>!admitted.includes(f))
  const proposalOk=last&&last.kind!=='error'&&last.adapter
  const savedAfter=a&&last&&a.updated_at&&new Date(a.updated_at)>=new Date(last.at)
  const st={find:read>=3?'done':'todo',capture:dr&&dr.status==='capturing'?'busy':captured?'done':read>=3?'todo':'wait',
    propose:dr?.status==='proposing'?'busy':proposalOk?'done':captured?'todo':'wait',save:savedAfter?'done':proposalOk?'todo':'wait',
    qualify:savedAfter&&b.qualify?'done':savedAfter?'todo':'wait',admit:toAdmit.length===0&&admitted.length>0?'done':toAdmit.length?'todo':'wait'}
  // Fix 5: the capture line counts captures only; a failed proposal is reported at 3.1, not here
  const caps=dr?.captures||[],okCaps=caps.filter(c=>!c.error).length,badCaps=caps.length-okCaps
  const att=(last?.attempts||[])
  const stKey=JSON.stringify(st)
  useEffect(()=>{onStage?.(st)},[stKey])
  return <>
    <Step n="2" title="Course pages" hint="Every course from the register, and whether its page on the provider's own site is found and read. At least 3 read pages are needed to build an adapter.">
      <SubStep n="2.1" title="Find course pages" state={st.find==='done'?'done':(b.course_list||[]).some(c=>c.state==='searching')?'busy':st.find}>
        {(b.course_list||[]).some(c=>c.state==='searching')&&<p className="cf-chip tone-info" data-find-auto>Searching by itself now (started by the website change or the course-page job): nothing to press. Results appear here as each course is done.</p>}
        <p className="ab-text"><strong>{fmtNumber(read)}</strong> read of <strong>{fmtNumber(b.pages?.stored||0)}</strong> stored, for <strong>{fmtNumber(b.courses)}</strong> active courses (3 read pages needed).</p>
        {find}
        <ManualPage r={r} pid={pid} busy={Boolean(busy)||st.capture==='busy'} onDone={async()=>{await loadDraft();onChanged?.()}} onError={onError}/>
      </SubStep>
      <SubStep n="2.2" title="Capture sample pages" state={st.capture}>
        <p className="ab-text" data-capture-status>{dr?<><strong>{fmtNumber(okCaps)}</strong> of {fmtNumber(caps.length)} sample pages captured{badCaps?` · ${fmtNumber(badCaps)} could not be captured`:''}{dr.status==='capturing'?' · capturing now':''}.</>:'Firecrawl captures 6 course pages spread across course types (about 1 credit each). Add a particular course below.'}</p>
        <SamplePick r={r} pid={pid} busy={Boolean(busy)||st.capture==='busy'} onDone={loadDraft} onError={onError}/>
        {can&&st.capture!=='wait'&&<Button compact disabled={Boolean(busy)||st.capture==='busy'} onClick={()=>run('capture',`Capture sample pages of ${b.name} with Firecrawl? About 1 credit a page.`,async reason=>{await rpc('admin_adapter_builder',{p_action:'start',p_args:{provider_id:pid,reason}});await loadDraft()})}>{captured?'Capture again':'Capture samples'}</Button>}
      </SubStep>
    </Step>
    <Step n="3" title="Adapter" hint={`The model for this adapter (${r?.model?.model||r?.budget?.model||'not set'}) proposes the settings; you run every step and admit only the fields that pass the checks. AI today US$ ${Number(r?.budget?.used_usd||0).toFixed(3)} of ${r?.budget?.limit_usd??'—'}.`}>
      {!can&&<p className="ab-text">Running the steps is for Platform Admins; you can follow the progress here.</p>}
      <SubStep n="3.1" title="Model proposes the settings" state={st.propose}>
        <ModelPick r={r} pid={pid} name={b.name} busy={Boolean(busy)} onDone={loadDraft} onError={onError}/>
        <p className={`ab-text${last?.kind==='error'?' ab-error':''}`} data-proposal-status>{last?(last.kind==='error'?<>Last proposal failed: {last.error}</>:`${last.model} · US$ ${Number(last.cost||0).toFixed(4)} · ${last.reason||''}`):'The pinned model reads the samples and suggests where each attribute is.'}</p>
        {att.length>0&&<p className="ab-muted" data-proposal-attempts>{att.map((a,i)=>`${i?'then ':''}limit ${fmtNumber(a.max_tokens)} tokens: ${a.finish==='length'?'cut off':a.finish||'no answer'}${a.completion_tokens!=null?`, ${fmtNumber(a.completion_tokens)} answer tokens`:''}`).join('; ')} · US$ {Number(att.reduce((t,a)=>t+Number(a.cost||0),0)).toFixed(4)} in all. A cut-off answer is asked again once, automatically, with a larger limit.</p>}
        {can&&st.propose!=='wait'&&<Button compact disabled={Boolean(busy)||st.propose==='busy'} onClick={()=>run('propose',`Ask the pinned model to propose settings for ${b.name} from the captured samples (uses the AI allowance)?`,async reason=>{await rpc('admin_adapter_builder',{p_action:'propose',p_args:{provider_id:pid,draft_id:dr.id,marks:dr.marks||[],comments:dr.comments||'Propose settings that read international intakes (months), IELTS overall, the international annual fee and delivery from these course pages.',reason}});await loadDraft()})}>{proposalOk?'Propose again':'Ask for a proposal'}</Button>}
      </SubStep>
      <SubStep n="3.2" title="Save in testing and apply" state={st.save}><p className="ab-text">Saves the proposed settings switched on but not admitting, then reads the stored pages with them.</p>
        {can&&st.save!=='wait'&&<Button compact disabled={Boolean(busy)} onClick={()=>run('save',`Save the proposed settings for ${b.name} (switched on, testing, nothing admitted) and apply them to its stored pages?`,async reason=>{const cur=(await rpc('admin_uni_adapter_read',{p_provider_id:pid}))?.adapter||{};const p=last.adapter||{};const adapter={...cur,...(p.json_source!=null?{json_source:p.json_source}:{}),json_paths:{...(cur.json_paths||{}),...(p.json_paths||{})},patterns:{...(cur.patterns||{}),...(p.patterns||{})},pick:{...(cur.pick||{}),...(p.pick||{})},enabled:true};delete adapter.updated_at;delete adapter.reason;await rpc('admin_uni_adapter_write',{p_action:'save',p_args:{provider_id:pid,adapter,reason}});await rpc('admin_uni_adapter_write',{p_action:'apply',p_args:{provider_id:pid,reason}});onChanged?.()})}>{savedAfter?'Save and apply again':'Save and apply'}</Button>}
      </SubStep>
      <SubStep n="3.3" title="Qualify" state={st.qualify}><p className="ab-text">Applying takes a few minutes on large sites. Refresh to measure each field against the values already held.</p>
        {st.qualify!=='wait'&&<Button compact disabled={Boolean(busy)} onClick={()=>onChanged?.()}>Refresh the measures</Button>}
        {b.qualify&&<ul className="tn-list" data-guided-qualify>{Object.keys(FIELD).filter(k=>b.qualify.fields?.[k]).map(k=><li key={k}><strong>{FIELD[k]}</strong> <span className="ab-muted">{ready.includes(k)?'ready to admit':`held: ${held[k]}`}{admitted.includes(k)?' · admitting':''}</span></li>)}</ul>}
      </SubStep>
      <SubStep n="3.4" title="Admit the ready fields" state={st.admit}><p className="ab-text">{toAdmit.length?`Ready: ${toAdmit.map(f=>FIELD[f]).join(', ')}.`:admitted.length?`Admitting: ${admitted.map(f=>FIELD[f]||f).join(', ')}.`:'Nothing is ready to admit yet.'}</p>
        {can&&toAdmit.length>0&&<Button compact variant="primary" disabled={Boolean(busy)} onClick={()=>run('admit',`Admit ${toAdmit.map(f=>FIELD[f]).join(', ')} for ${b.name}? Values read from its pages are written to the catalogue; values entered by hand are never changed.`,async reason=>{await rpc('admin_uni_adapter_control',{p_action:'admit',p_args:{provider_id:pid,admit:true,fields:[...new Set([...admitted,...toAdmit])].sort(),reason}});onChanged?.()})}>Admit these</Button>}
      </SubStep>
    </Step>
  </>
}

export default function AdapterBuilderTab({rank,onError,initialProvider=''}){
  const[pid,setPid]=useState(initialProvider||null),[b,setB]=useState(null),[busy,setBusy]=useState(false),[key,setKey]=useState(0),[stage,setStage]=useState({})
  const load=async(id=pid)=>{if(!id)return;try{const{data,error}=await supabase.rpc('admin_adapter_builder_basics',{p_action:'basics',p_args:{provider_id:id}});if(error)throw error;setB(data)}catch(e){onError?.(errText(e))}}
  useEffect(()=>{setB(null);load(pid)},[pid])
  useEffect(()=>{if(initialProvider&&initialProvider!==pid)setPid(initialProvider)},[initialProvider])
  const flow=builderFlow(b,stage),auto=Boolean(flow?.running?.length)
  useEffect(()=>{if(!auto||!pid)return;const t=setTimeout(()=>load(),15000);return()=>clearTimeout(t)},[b,auto]) // fixed: screen refresh while work runs
  if(rank<5)return <Empty text="The adapter builder is for PIM Admins and Platform Admins."/>
  const read=b?.pages?.read||0
  return <div className="m-page-stack ab-builder" data-adapter-builder-tab>
    <p className="ab-text">Build or change an adapter step by step. Everything depends on the provider's own website (1.1); each step uses evidence from its own pages, and nothing is admitted until you admit it.</p>
    <Step n="1" title="Provider">{b?<p className="ab-text"><strong>{b.name}</strong> <span className="ab-muted">{b.country} · {fmtNumber(b.courses)} active courses · adapter: {stateLabel(b.adapter).toLowerCase()}</span> <Button compact onClick={()=>{setPid(null);setB(null);setStage({})}}>Change</Button></p>:<PickProvider onPick={setPid} onError={onError}/>}
      {b&&<BuilderGuide flow={flow}/>}
      {b&&<>
        <SubStep n="1.1" title="Website" state={b.website?'done':'todo'}><WebsiteStep b={b} onChanged={()=>load()} onError={onError}/></SubStep>
        <SubStep n="1.2" title="Contacts" state={['requested','leased'].includes(b.contacts?.outcome)?'busy':b.contacts?.phone||b.contacts?.email?'done':'todo'}><ContactsStep b={b}/><p className="ab-muted">Optional for the adapter. Read by itself from the provider's own site after the website is set or changed (and by Fill in from website). The Principal Executive Officer comes from the register (CRICOS) where there is one.</p></SubStep>
        {/* v2.15.253 (Platform Admin, 12 Oct 2026): central pages are approved here (Layer 4 › Attributes retired); across universities on Providers › Onboarding */}
        <SubStep n="1.3" title="Central pages" state={['queued','leased'].includes(b.central_search?.state)||(b.central||[]).some(x=>x.status==='found')?'busy':(b.central||[]).length?'done':'todo'}><p className="ab-text">Optional for the adapter, done in parallel with step 2. Key dates, the international fee schedule and English requirements cover every course at once: the site is searched for them by itself, a page found is attached and read by itself, and its values wait for your approval below. Attach a page by hand only if the search missed it.</p><CentralPages b={b} onDone={()=>load()} onError={onError}/>
          <CentralApprovals b={b}/></SubStep>
      </>}
    </Step>
    {pid&&!b&&<Loading label="Reading the provider…"/>}
    {b&&<>
      <GuidedBuild b={b} find={<CourseList b={b} onChanged={()=>load()}/>} onChanged={()=>{setKey(k=>k+1);load()}} onError={onError} onStage={setStage}/>
      <details className="ab-step ab-hand" data-builder-step="4"><summary className="sl-h4"><span className="ab-num">4</span> Adjust by hand</summary>
        {read>=3?<><p className="ab-text">Mark which text block or page-data value holds each attribute and ask for a proposal; preview it on the stored pages, then save and apply.</p>
          <AdapterEditor key={key} providerId={b.provider_id} hideReview onError={onError}/>
          <Button compact onClick={()=>{setKey(k=>k+1);load()}}>Refresh the measures</Button></>:<p className="ab-text">Needs at least 3 read course pages (step 2.1).</p>}
        {b.adapter&&<><h4 className="sl-h4">Validate and admit</h4><Qualify q={b.qualify}/><AdapterReview providerId={b.provider_id} can={Boolean(b.can_manage)} onError={onError}/></>}
      </details>
    </>}
  </div>
}
