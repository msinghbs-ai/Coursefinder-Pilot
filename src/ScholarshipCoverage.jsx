// Scholarships › Coverage (v2.15.240, CF-247; Platform Admin, 11 Oct 2026: "how do I make sure the scholarships published on the
// platform are complete and correct ... present the mechanism in UI"; "all operational and configuration for scholarship available
// in UI with full control, like Providers Adapters; keep it simple and modern").
// Each provider is measured against its own scholarship listing page: what the page lists, which of those we hold and publish,
// what is missing, and our records the page does not list. Opening a provider shows each listed scholarship beside our record
// (value, who it is for, linked courses, why it is held) with the actions to publish, hold, confirm international or sign off.
// Scholarships published automatically are listed at the top for review. Settings and jobs are under "Settings and jobs".
// Read: admin_scholarship_coverage_read / admin_scholarship_coverage_provider. Write: admin_scholarship_coverage_write.
import React,{useEffect,useState}from'react'
import{CheckCircle2,ExternalLink,Eye,EyeOff,Plus,RefreshCw,Search,ShieldCheck,X}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Loading,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'
import ScholarshipLayer from'./ScholarshipLayer'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const STATE={no_listing:['No listing page','neutral'],waiting:['Reading','info'],to_check:['To check','warning'],changed:['Changed since check','warning'],checked:['Checked','success']}
const PUB={published:['Published','success'],unpublished:['Not published','neutral'],withdrawn:['Withdrawn','warning']}
const HOLD_REASONS=['Not for international students','Not a scholarship (a sponsorship or general page)','Wrong provider','Value or details wrong on our record','Closed or no longer offered','Duplicate of another record']
function value(r){if(!r)return'—';if(r.value_type==='percentage'&&r.percentage!=null)return `${Number(r.percentage)}% of tuition${r.value_is_maximum?' (maximum)':''}`;if(r.value_type==='fixed_amount'&&r.amount!=null)return `${r.currency||''} ${fmtNumber(r.amount)}${r.value_is_maximum?' (maximum)':''}`.trim();return 'Not read'}
const host=u=>{try{return new URL(u).hostname.replace(/^www\./,'')}catch{return u}}

export default function ScholarshipCoverage({rank=3,onError,navigate}){
  const[scope,setScope]=useState('watch'),[query,setQuery]=useState(''),[q,setQ]=useState(''),[data,setData]=useState(null),[busy,setBusy]=useState(false),[open,setOpen]=useState(null)
  useEffect(()=>{const t=setTimeout(()=>setQ(query.trim()),280);return()=>clearTimeout(t)},[query])
  const load=async()=>{setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_scholarship_coverage_read',{p_scope:scope,p_query:q||null,p_limit:300,p_offset:0});if(error)throw error;setData(d)}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  useEffect(()=>{load()},[scope,q])
  const t=data?.totals||{},ap=data?.auto_publish||{},rows=data?.rows||[]
  return <div className="m-page-stack sc-cov" data-scholarship-coverage>
    <section className="m-panel">
      <div className="m-workspace-head"><div><h2>Coverage</h2><p>Each provider measured against its own scholarship listing page: what it lists, what we hold and publish, what is missing.</p></div>
        <Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>Refresh</Button></div>
      <div className="sc-tiles">
        <div><small>Published</small><strong>{fmtNumber(t.published||0)}</strong><span>of {fmtNumber(t.active||0)} held</span></div>
        <div><small>Watch list</small><strong>{fmtNumber(t.watch||0)}</strong><span>providers</span></div>
        <div><small>With a listing page</small><strong>{fmtNumber(t.with_listing||0)}</strong><span>{t.suggested?`${fmtNumber(t.suggested)} suggested to confirm`:'providers'}</span></div>
        <div><small>Signed off</small><strong>{fmtNumber(t.checked||0)}</strong><span>providers</span></div>
      </div>
      <AutoPublished ap={ap} can={Boolean(data?.can_manage)} onError={onError} onChanged={load}/>
      <div className="sc-bar">
        <div className="ar-tabs" role="tablist" aria-label="Which providers">
          <button role="tab" aria-selected={scope==='watch'} className={scope==='watch'?'active':''} onClick={()=>setScope('watch')}>Watch list</button>
          <button role="tab" aria-selected={scope==='all'} className={scope==='all'?'active':''} onClick={()=>setScope('all')}>All with scholarships</button>
        </div>
        <label className="m-searchbox"><Search size={16}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search provider" aria-label="Search provider"/></label>
      </div>
      {busy&&!data?<Loading label="Loading coverage…"/>:<div className="cf-table-wrap"><table className="cf-table sc-table">
        <thead><tr><th>Provider</th><th className="num" title="Scholarships named on the provider's listing page">Listed</th><th className="num" title="Listed scholarships we hold a record for">Found</th><th className="num">Published</th><th className="num" title="Listed with no record of ours">Missing</th><th className="num" title="Our records the listing page does not name">Other records</th><th>State</th></tr></thead>
        <tbody>{rows.length===0?<tr><td colSpan={7}>{busy?'Loading…':'No providers match.'}</td></tr>:rows.map(r=>{const[sl,st]=STATE[r.state]||[r.state,'neutral'];return <tr key={r.provider_id} data-cov-row={r.provider_id} className={open===r.provider_id?'is-selected':''} onClick={()=>setOpen(r.provider_id)} style={{cursor:'pointer'}}>
          <td><strong>{r.name}</strong>{r.watch&&<span className="sc-dot" title="On the watch list"/>}</td>
          <td className="num">{r.listing_pages?fmtNumber(r.listed):'—'}</td><td className="num">{r.listing_pages?fmtNumber(r.found):'—'}</td>
          <td className="num">{fmtNumber(r.records_published)}</td>
          <td className="num">{r.listing_pages&&r.missing?<b className="sc-bad">{fmtNumber(r.missing)}</b>:r.listing_pages?'0':'—'}</td>
          <td className="num">{fmtNumber(r.extra)}</td>
          <td><StatusChip value={r.state} tone={st} label={sl}/>{r.suggested_pages&&!r.listing_pages?<small className="sc-sub"> suggestion</small>:null}</td></tr>})}</tbody>
      </table></div>}
    </section>
    {open&&<ProviderCoverage providerId={open} rank={rank} onClose={()=>setOpen(null)} onError={onError} onChanged={load}/>}
    <details className="m-panel sc-controls" data-scholarship-controls><summary>Settings and jobs</summary>
      <p className="sc-sub">Every scholarship job and setting: switch a job on or off, change how many it handles per run. Platform Admin.</p>
      <ScholarshipLayer layer={2} rank={rank} onError={onError} only="controls"/>
      <ScholarshipLayer layer={4} rank={rank} onError={onError} only="controls"/>
    </details>
  </div>
}

function AutoPublished({ap,can,onError,onChanged}){
  const items=ap.recent||[],[show,setShow]=useState(false)
  if(!ap.on&&!items.length)return <p className="sc-note">Automatic publishing is off. Turn it on under Settings and jobs.</p>
  return <div className="sc-auto" data-auto-published>
    <div><ShieldCheck size={16}/><span><strong>{fmtNumber(items.length)}</strong> published automatically in the last 3 days{ap.on?'':' (now switched off)'}. Each passed every check; hold any that is wrong.</span>
      {items.length>0&&<Button compact onClick={()=>setShow(s=>!s)}>{show?'Hide':'Review'}</Button>}</div>
    {show&&<ul>{items.map(i=><li key={i.id}><span><strong>{i.name}</strong> <small>{i.provider} · {i.value||'value not shown'} · {fmtNumber(i.courses)} courses · {fmtDateTime(i.at)}</small></span>
      {i.status==='published'?(can&&<HoldButton id={i.id} onError={onError} onDone={onChanged}/>):<StatusChip value={i.status} tone="warning" label={PUB[i.status]?.[0]||i.status}/>}</li>)}</ul>}
  </div>
}

function HoldButton({id,onError,onDone,compactLabel='Hold'}){
  const[pick,setPick]=useState(false),[busy,setBusy]=useState(false)
  const go=async reason=>{setBusy(true);try{const{error}=await supabase.rpc('admin_scholarship_coverage_write',{p_action:'hold',p_args:{scholarship_id:id,reason}});if(error)throw error;setPick(false);onDone?.()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  if(!pick)return <Button compact onClick={e=>{e.stopPropagation();setPick(true)}} disabled={busy}>{compactLabel}</Button>
  return <select className="fv-input sc-pick" autoFocus aria-label="Why hold it" defaultValue="" onChange={e=>e.target.value&&go(e.target.value)} onBlur={()=>!busy&&setPick(false)}>
    <option value="" disabled>Why?</option>{HOLD_REASONS.map(r=><option key={r}>{r}</option>)}</select>
}

function ProviderCoverage({providerId,rank,onClose,onError,onChanged}){
  const[d,setD]=useState(null),[busy,setBusy]=useState(false),[url,setUrl]=useState('')
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_scholarship_coverage_provider',{p_provider_id:providerId});if(error)throw error;setD(data)}catch(e){onError?.(errText(e))}}
  useEffect(()=>{setD(null);load()},[providerId])
  const act=async(action,args)=>{setBusy(true);try{const{data,error}=await supabase.rpc('admin_scholarship_coverage_write',{p_action:action,p_args:{provider_id:providerId,...args}});if(error)throw error;if(data?.row)setD(data);else await load();onChanged?.()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  if(!d)return <section className="m-panel"><Loading label="Loading provider…"/></section>
  const r=d.row||{},can=Boolean(d.can_manage)&&!busy,canWatch=Number(rank)>=5&&!busy
  const pages=d.listing_pages||[],real=pages.filter(p=>p.source!=='suggested'),sugg=pages.filter(p=>p.source==='suggested')
  return <section className="m-panel sc-provider" data-cov-provider={providerId}>
    <div className="m-workspace-head"><div><h2>{r.name}</h2><p>{real.length?`${fmtNumber(r.listed)} listed on its page · ${fmtNumber(r.found)} found · ${fmtNumber(r.published)} of those published · ${fmtNumber(r.missing)} missing`:'No listing page yet: add the page that lists its scholarships for international students.'}{r.checked_at?` · Signed off ${fmtDateTime(r.checked_at)}${r.checked_by?` by ${r.checked_by}`:''}`:''}</p></div>
      <div className="sc-actions">
        {canWatch&&<Button compact onClick={()=>act(r.watch?'unwatch':'watch',{})}>{r.watch?<><EyeOff size={14}/>Remove from watch list</>:<><Eye size={14}/>Watch</>}</Button>}
        {can&&real.length>0&&<Button compact onClick={()=>act('read_now',{})}><RefreshCw size={14}/>Read again now</Button>}
        {can&&real.length>0&&<Button compact variant="primary" onClick={()=>act('sign_off',{})}><CheckCircle2 size={14}/>Sign off</Button>}
        <Button compact onClick={onClose} aria-label="Close provider"><X size={14}/></Button>
      </div></div>

    <div className="sc-pages" data-listing-pages>
      {real.map(p=><div key={p.id} className="sc-page"><a href={p.url} target="_blank" rel="noreferrer" className="cf-link">{host(p.url)}{new URL(p.url).pathname} <ExternalLink size={11}/></a>
        <small>{p.status==='read'?`${fmtNumber(p.items)} scholarships named · read ${fmtDateTime(p.read_at)}`:p.status==='failed'?`Could not be read (${p.error||'error'})`:'Waiting to be read (within 15 minutes)'}{p.source==='manual'?' · entered by hand':' · found automatically'}</small>
        {can&&<Button compact onClick={()=>act('remove_listing',{id:p.id})}>Remove</Button>}</div>)}
      {sugg.map(p=><div key={p.id} className="sc-page sc-sugg"><span>Suggested: <a href={p.url} target="_blank" rel="noreferrer" className="cf-link">{host(p.url)}{new URL(p.url).pathname}</a></span><small>Several of its scholarship pages sit under this page.</small>
        {can&&<Button compact variant="primary" onClick={()=>act('use_suggested',{id:p.id})}>Use this page</Button>}</div>)}
      {can&&<form className="sc-add" onSubmit={e=>{e.preventDefault();if(url.trim())act('add_listing',{url:url.trim()}).then(()=>setUrl(''))}}>
        <input className="fv-input" value={url} onChange={e=>setUrl(e.target.value)} placeholder="https:// the provider's international scholarships page" aria-label="Listing page address"/>
        <Button compact type="submit" disabled={!/^https?:\/\/\S+\.\S+/.test(url.trim())}><Plus size={14}/>Add listing page</Button></form>}
    </div>

    {(d.listed||[]).length>0&&<Records title="On the provider's list" rows={d.listed} listed can={can} act={act} onError={onError} reload={()=>{load();onChanged?.()}}/>}
    {(d.extra||[]).length>0&&<Records title={real.length?'Our other records (not on its list)':'Our records'} rows={(d.extra||[]).map(x=>({record:x}))} can={can} act={act} onError={onError} reload={()=>{load();onChanged?.()}}/>}
  </section>
}

function Records({title,rows,listed=false,can,act,onError,reload}){
  return <div className="sc-records"><h3>{title}</h3><div className="cf-table-wrap"><table className="cf-table">
    <thead><tr>{listed&&<th>On its page</th>}<th>Our record</th><th>Value</th><th>Courses</th><th>Why not published</th><th></th></tr></thead>
    <tbody>{rows.map((x,i)=>{const s=x.record,[pl,pt]=s?PUB[s.status]||[s.status,'neutral']:['Missing','danger'];return <tr key={(s?.id||'')+i} data-cov-record={s?.id||'missing'}>
      {listed&&<td>{x.url?<a href={x.url} target="_blank" rel="noreferrer" className="cf-link">{x.name}</a>:x.name}</td>}
      <td>{s?<><StatusChip value={s.status} tone={pt} label={pl}/> <span className="sc-name">{s.name}</span></>:<StatusChip value="missing" tone="danger" label="Not found"/>}</td>
      <td>{s?value(s):'—'}</td>
      <td>{s?<>{fmtNumber(s.courses)}{s.all_courses?<small className="sc-sub"> · all courses (page names no restriction)</small>:(s.levels||[]).length?<small className="sc-sub"> · {(s.levels||[]).join(', ')}</small>:null}</>:'—'}</td>
      <td className="sc-why">{s?(s.status==='published'?'—':(s.reasons||[]).length?(s.reasons||[]).join('; '):'Passes every check'):'No record of ours yet; read the page again or add it by hand'}</td>
      <td className="sc-row-actions">{s&&can&&<>
        {s.status!=='published'&&s.publishable&&<Button compact variant="primary" onClick={()=>act('publish',{scholarship_id:s.id})}>Publish</Button>}
        {(s.reasons||[]).some(r=>/international/.test(r))&&listed&&<Button compact onClick={()=>act('confirm_international',{scholarship_id:s.id})} title="Listed on the provider's international scholarships page">International</Button>}
        {s.held?<Button compact onClick={()=>act('release',{scholarship_id:s.id})}>Release</Button>:<HoldButton id={s.id} onError={onError} onDone={reload} compactLabel={s.status==='published'?'Withdraw':'Hold'}/>}
      </>}</td></tr>})}</tbody></table></div></div>
}
