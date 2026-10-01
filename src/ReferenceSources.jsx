// Reference sources (v2.15.121): the third-party sites the platform refers to, and how each one is used.
// Platform Admin, 1 Oct 2026: "notable third party links maintained and used for reference like hot courses and govt
// regulatory website, UI should maintain and control profiles how they are used. Not hard coded in script or functions."
// Each site has a domain, an on/off switch and ticked uses. The platform reads this list: the coverage sweep skips sites
// that are never a university website, course page binding refuses sites that are never a course page, scholarships
// sourced only from a placeholder site need a university page before publishing, and Ranking imports takes its default
// publisher addresses from here.
// Curators edit names, addresses and purpose and run "Check now"; PIM Operators add or retire sites and change domains,
// uses, categories and switches (with a reason). Every change is logged.
// Read: public.admin_reference_sources_read(); write: public.admin_reference_source_save(id, fields, reason),
// public.admin_reference_source_action(id, action, reason) (migration 20261001110000_cf247_reference_sources).
import React,{useEffect,useMemo,useRef,useState}from'react'
import{Check,ExternalLink,Globe,History,Plus,RefreshCw,Search}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,Metric,SectionTitle,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'
import{Switch}from'./ModelsServices'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const HEALTH={healthy:'success',degraded:'warning',blocked:'danger',unverified:'neutral',retired:'neutral'}
const COUNTRY={ALL:'All countries',AU:'Australia',NZ:'New Zealand'}

export default function ReferenceSources({onError}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(false),[done,setDone]=useState(''),[err,setErr]=useState('')
  const[q,setQ]=useState(''),[cat,setCat]=useState(''),[use,setUse]=useState(''),[showRetired,setShowRetired]=useState(false),[adding,setAdding]=useState(false)
  const apply=d=>{setData(d||{});return d}
  const load=async()=>{setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_reference_sources_read');if(error)throw error;apply(d)}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  useEffect(()=>{load()},[])
  const any=(data?.items||[]).some(x=>x.checking)
  useEffect(()=>{if(!any)return;const t=setTimeout(load,4000);return()=>clearTimeout(t)},[any,data])
  const call=async(fn,args,msg)=>{setBusy(true);setErr('');setDone('');try{const{data:d,error}=await supabase.rpc(fn,args);if(error)throw error;apply(d);if(msg)setDone(msg);return d}catch(e){setErr(errText(e));return null}finally{setBusy(false)}}
  const save=async(item,fields,label,needsReason)=>{let reason=null;if(needsReason){reason=window.prompt(`${label}\n\nReason (kept in the change log):`,'');if(reason===null)return false;if(reason.trim().length<3){setErr('Give a short reason.');return false}}
    return Boolean(await call('admin_reference_source_save',{p_id:item?.id||null,p_fields:fields,p_reason:reason},item?`${item.name} saved.`:'Site added.'))}
  const uses=data?.uses||[],cats=data?.categories||[],useLabel=Object.fromEntries(uses.map(u=>[u.key,u.label])),catLabel=Object.fromEntries(cats.map(c=>[c.key,c.label]))
  const items=useMemo(()=>(data?.items||[]).filter(x=>(showRetired||!x.retired)&&(!cat||x.category===cat)&&(!use||(x.uses||[]).includes(use))&&(!q||`${x.name} ${x.url} ${x.domain||''}`.toLowerCase().includes(q.toLowerCase()))),[data,q,cat,use,showRetired])
  if(!data)return <section className="m-panel"><Loading label="Loading reference sources…"/></section>
  const can=Boolean(data.can_edit),manage=Boolean(data.can_manage),all=data.items||[]
  return <>
    <div className="cf-metric-grid">
      <Metric label="Sites in use" value={fmtNumber(all.filter(x=>!x.retired&&x.enabled).length)} detail={`${fmtNumber(all.filter(x=>!x.retired&&!x.enabled).length)} switched off`} icon={Globe}/>
      <Metric label="Never a university website" value={fmtNumber(all.filter(x=>!x.retired&&x.enabled&&x.uses?.includes('not_provider_site')).length)} icon={Globe}/>
      <Metric label="Need a check" value={fmtNumber(all.filter(x=>!x.retired&&x.health!=='healthy').length)} icon={RefreshCw} tone={all.some(x=>!x.retired&&x.health==='degraded')?'warning':'neutral'}/>
    </div>
    <section className="m-panel">
      <SectionTitle icon={Globe} title="Reference sources" subtitle="Third-party sites the platform refers to, and how each one is used. The platform reads this list; nothing about these sites is fixed in code." action={<div className="l3c-actions">
        <span className="pq-search sl-search"><Search size={14}/><input type="search" value={q} onChange={e=>setQ(e.target.value)} placeholder="Find a site" aria-label="Find a site"/></span>
        <select className="fv-filter" value={cat} onChange={e=>setCat(e.target.value)} aria-label="Category"><option value="">All categories</option>{cats.map(c=><option key={c.key} value={c.key}>{c.label}</option>)}</select>
        <select className="fv-filter" value={use} onChange={e=>setUse(e.target.value)} aria-label="Use"><option value="">All uses</option>{uses.map(u=><option key={u.key} value={u.key}>{u.label}</option>)}</select>
        <label className="rs-check"><input type="checkbox" checked={showRetired} onChange={e=>setShowRetired(e.target.checked)}/>Show retired</label>
        {can&&<Button compact onClick={()=>call('admin_reference_source_action',{p_id:null,p_action:'check_all',p_reason:null},'Checking every site; results appear in a few seconds.')} disabled={busy}><RefreshCw size={14}/>Check all</Button>}
        {manage&&<Button compact variant="primary" onClick={()=>setAdding(x=>!x)}><Plus size={14}/>Add site</Button>}
      </div>}/>
      {!can&&<p className="l3v-note">You can view these. A Curator or above can edit names and addresses; a PIM Operator or above can change how a site is used.</p>}
      {err&&<p className="fr-error" role="alert">{err}</p>}
      {done&&<p className="sb-done" role="status">{done}</p>}
      {adding&&<AddSite uses={uses} cats={cats} onCancel={()=>setAdding(false)} onSave={async f=>{if(await save(null,f,`Add ${f.name}?`,true))setAdding(false)}}/>}
      <details className="rs-help"><summary>What each use means</summary><ul>{uses.map(u=><li key={u.key}><strong>{u.label}</strong>: {u.help}</li>)}</ul>
        <p>A domain with a dot (education.gov.au) matches that site and its subdomains. A single name with no dot (google) matches any site whose name starts with it, such as google.com and google.com.au.</p></details>
      {items.length?<div className="cf-table-wrap"><table className="cf-table rs-table" data-reference-sources>
        <thead><tr><th>Site</th><th>Domain</th><th>Uses</th><th>Category</th><th>Status</th><th>On</th><th/></tr></thead>
        <tbody>{items.map(x=><tr key={x.id} className={x.retired||!x.enabled?'ms-off':''} data-site={x.name}>
          <td className="rs-site"><Cell value={x.name} can={can} label={`Name of ${x.name}`} onSave={v=>save(x,{name:v})} strong/>
            <Cell value={x.url} can={can} label={`Address of ${x.name}`} onSave={v=>save(x,{url:v})} link/>
            <Cell value={x.purpose||''} can={can} label={`Purpose of ${x.name}`} onSave={v=>save(x,{purpose:v})} muted placeholder="Add a purpose"/></td>
          <td><Cell value={x.domain||''} can={manage} label={`Domain of ${x.name}`} onSave={v=>save(x,{domain:v},`Change the domain of ${x.name} to "${v}"?`,true)} mono placeholder="No domain"/></td>
          <td><Uses item={x} uses={uses} label={useLabel} can={manage&&!x.retired} onSave={list=>save(x,{uses:list},`Change how ${x.name} is used?`,true)}/>
            {x.scholarships!=null&&<span className="l3v-code">{fmtNumber(x.scholarships)} scholarships sourced only here</span>}</td>
          <td>{manage&&!x.retired?<select className="fv-filter" value={x.category} aria-label={`Category of ${x.name}`} onChange={e=>save(x,{category:e.target.value},`Change the category of ${x.name}?`,true)}>{cats.map(c=><option key={c.key} value={c.key}>{c.label}</option>)}</select>:catLabel[x.category]||x.category}
            <span className="l3v-code">{COUNTRY[x.country]||x.country}{x.ref_key?` · ranking ${x.ref_key}`:''}</span></td>
          <td><StatusChip value={x.checking?'checking':x.health} tone={x.checking?'neutral':HEALTH[x.health]||'neutral'} label={x.checking?'Checking…':x.health==='healthy'?'Reachable':x.health==='degraded'?'Not reachable':x.health==='retired'?'Retired':'Not checked'}/>
            {x.checked_at&&<span className="l3v-code">{x.http?`HTTP ${x.http} · `:''}{fmtDateTime(x.checked_at)}</span>}</td>
          <td>{x.retired?<span className="l3v-code">Retired</span>:<Switch on={Boolean(x.enabled)} label={`${x.enabled?'Switch off':'Switch on'} ${x.name}`} disabled={!manage||busy} onChange={on=>save(x,{enabled:on},`Switch ${on?'on':'off'} ${x.name}?${on?'':' The platform will stop using it.'}`,true)}/>}</td>
          <td className="rs-actions">{can&&!x.retired&&<Button compact onClick={()=>call('admin_reference_source_action',{p_id:x.id,p_action:'check',p_reason:null})} disabled={busy||x.checking} aria-label={`Check ${x.name} now`}><RefreshCw size={13}/>Check</Button>}
            {manage&&<Button compact onClick={()=>{const r=window.prompt(`${x.retired?'Restore':'Retire'} ${x.name}?\n\nReason (kept in the change log):`,'');if(r!==null)call('admin_reference_source_action',{p_id:x.id,p_action:x.retired?'restore':'retire',p_reason:r},`${x.name} ${x.retired?'restored':'retired'}.`)}} disabled={busy}>{x.retired?'Restore':'Retire'}</Button>}</td>
        </tr>)}</tbody></table></div>:<Empty text="No sites match."/>}
    </section>
    {(data.events||[]).length>0&&<section className="m-panel"><SectionTitle icon={History} title="Recent changes"/>
      <ul className="ms-events">{data.events.map((e,i)=><li key={i}><strong>{e.target}</strong> {e.action==='change'?`changed (${(e.detail?.fields||[]).join(', ')})`:e.action==='add'?'added':e.action==='retire'?'retired':e.action==='restore'?'restored':e.action}{e.detail?.reason?` — ${e.detail.reason}`:''}<span className="l3v-code">{[e.by,fmtDateTime(e.at)].filter(Boolean).join(' · ')}</span></li>)}</ul></section>}
  </>
}

function Uses({item,uses,label,can,onSave}){
  const[open,setOpen]=useState(false),[sel,setSel]=useState(item.uses||[]),ref=useRef(null)
  useEffect(()=>{if(!open)setSel(item.uses||[])},[open,JSON.stringify(item.uses)])
  useEffect(()=>{if(!open)return;const h=e=>{if(ref.current&&!ref.current.contains(e.target))setOpen(false)};document.addEventListener('mousedown',h);return()=>document.removeEventListener('mousedown',h)},[open])
  const chips=<span className="rs-uses">{(item.uses||[]).map(u=><span key={u} className="cf-chip tone-violet">{label[u]||u}</span>)}</span>
  if(!can)return chips
  return <span className="rs-uses-edit" ref={ref}>
    <button type="button" className="le-btn rs-uses-btn" aria-label={`Change uses of ${item.name}`} onClick={()=>setOpen(o=>!o)}>{chips}</button>
    {open&&<div className="rs-pop" role="dialog" aria-label={`Uses of ${item.name}`}>
      {uses.map(u=><label key={u.key}><input type="checkbox" checked={sel.includes(u.key)} onChange={()=>setSel(s=>s.includes(u.key)?s.filter(x=>x!==u.key):[...s,u.key])}/>{u.label}</label>)}
      <div className="rs-pop-actions"><Button compact onClick={()=>setOpen(false)}>Cancel</Button><Button compact variant="primary" disabled={!sel.length} onClick={async()=>{if(await onSave(sel))setOpen(false)}}><Check size={13}/>Save</Button></div>
    </div>}
  </span>
}

function Cell({value,can,label,onSave,strong,muted,mono,link,placeholder}){
  const[edit,setEdit]=useState(false),[draft,setDraft]=useState(value),ref=useRef(null)
  useEffect(()=>{if(!edit)setDraft(value)},[value,edit])
  useEffect(()=>{if(edit)ref.current?.focus()},[edit])
  const cls=['rs-cell',strong&&'rs-strong',muted&&'rs-muted',mono&&'rs-mono'].filter(Boolean).join(' ')
  const commit=async()=>{const v=String(draft).trim();if(v===String(value||'')){setEdit(false);return}if(await onSave(v))setEdit(false)}
  if(edit)return <input ref={ref} className="fv-input le-input" aria-label={label} value={draft} onChange={e=>setDraft(e.target.value)} onBlur={commit} onKeyDown={e=>{if(e.key==='Enter'){e.preventDefault();commit()}if(e.key==='Escape')setEdit(false)}}/>
  const text=value||<span className="le-empty">{placeholder||'—'}</span>
  return <span className={cls}>{can?<button type="button" className="le-btn" aria-label={`Edit ${label}`} onClick={()=>setEdit(true)}>{text}</button>:<span>{text}</span>}
    {link&&value&&<a className="cf-link" href={value} target="_blank" rel="noreferrer" aria-label={`Open ${value}`}><ExternalLink size={12}/></a>}</span>
}

function AddSite({uses,cats,onSave,onCancel}){
  const[f,setF]=useState({name:'',url:'https://',domain:'',category:'third_party_directory',country:'ALL',purpose:'',uses:['reference']})
  const set=(k,v)=>setF(x=>({...x,[k]:v}))
  const ok=f.name.trim().length>1&&/^https?:\/\/.+/.test(f.url)&&f.uses.length
  return <div className="rs-add" data-add-site>
    <div className="rs-add-grid">
      <label><small>Name</small><input className="fv-input" value={f.name} onChange={e=>set('name',e.target.value)} placeholder="e.g. Uni Compare"/></label>
      <label><small>Address</small><input className="fv-input" value={f.url} onChange={e=>{set('url',e.target.value);if(!f.domain){try{set('domain',new URL(e.target.value).hostname.replace(/^www\./,''))}catch{}}}}/></label>
      <label><small>Domain it covers</small><input className="fv-input" value={f.domain} onChange={e=>set('domain',e.target.value.toLowerCase())} placeholder="e.g. unicompare.com.au"/></label>
      <label><small>Category</small><select className="fv-filter" value={f.category} onChange={e=>set('category',e.target.value)}>{cats.map(c=><option key={c.key} value={c.key}>{c.label}</option>)}</select></label>
      <label><small>Country</small><select className="fv-filter" value={f.country} onChange={e=>set('country',e.target.value)}>{Object.entries(COUNTRY).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></label>
      <label className="rs-wide"><small>Purpose</small><input className="fv-input" value={f.purpose} onChange={e=>set('purpose',e.target.value)} placeholder="What it is and how we use it"/></label>
    </div>
    <fieldset className="sl-choice"><legend>How it is used</legend>{uses.map(u=><label key={u.key} title={u.help}><input type="checkbox" checked={f.uses.includes(u.key)} onChange={()=>set('uses',f.uses.includes(u.key)?f.uses.filter(x=>x!==u.key):[...f.uses,u.key])}/>{u.label}</label>)}</fieldset>
    <div className="l3c-actions"><Button compact onClick={onCancel}>Cancel</Button><Button compact variant="primary" disabled={!ok} onClick={()=>onSave(f)}><Plus size={13}/>Add site</Button></div>
  </div>
}
