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
import{ExpandList,Pill,XlField,XlToolbar}from'./ExpandList'
import{plainError}from'./lib/errors'

const errText=e=>plainError(e) // v2.15.341 (UI audit Phase 0): one plain reading, no internals
const HEALTH={healthy:'success',degraded:'warning',blocked:'danger',unverified:'neutral',retired:'neutral'}
const COUNTRY={ALL:'All countries',AU:'Australia',NZ:'New Zealand',CA:'Canada'}
// UI audit Phase 1 (24 Oct 2026): what the last check found, in words; the HTTP number stays on hover.
export function httpWords(code){const n=Number(code);if(!Number.isFinite(n)||n<=0)return'Not checked';if(n>=200&&n<300)return'Reachable';if(n===401||n===403)return'Refuses automated reads';if(n===404||n===410)return'Page gone';if(n===429)return'Asked us to slow down';if(n>=500)return'Site error';return'Not checked'}
// The "never a university website" rule stays; its chip reads "Not a university site".
const USE_CHIP={not_provider_site:'Not a university site'}

// v2.15.246 (Platform Admin bugs 11/10-3, Fix 7: "input field / explanation and list columns do not match up"): one list whose
// filters sit in the same order as its columns (Site, Uses, Category, Country, Status, On). Each row opens in place with the same
// fields as Add site, so what is shown, filtered, added and edited always matches.
export default function ReferenceSources({onError}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(false),[done,setDone]=useState(''),[err,setErr]=useState('')
  const[q,setQ]=useState(''),[cat,setCat]=useState(''),[use,setUse]=useState(''),[country,setCountry]=useState(''),[status,setStatus]=useState(''),[showRetired,setShowRetired]=useState(false),[adding,setAdding]=useState(false),[open,setOpen]=useState(null)
  const apply=d=>{setData(d||{});return d}
  const load=async()=>{setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_reference_sources_read');if(error)throw error;apply(d)}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  useEffect(()=>{load()},[])
  const any=(data?.items||[]).some(x=>x.checking)
  useEffect(()=>{if(!any)return;const t=setTimeout(load,4000);return()=>clearTimeout(t)},[any,data])
  const call=async(fn,args,msg)=>{setBusy(true);setErr('');setDone('');try{const{data:d,error}=await supabase.rpc(fn,args);if(error)throw error;apply(d);if(msg)setDone(msg);return d}catch(e){setErr(errText(e));return null}finally{setBusy(false)}}
  const save=async(item,fields,label,needsReason)=>{let reason=null;if(needsReason){reason=window.prompt(`${label}\n\nReason (kept in the change log):`,'');if(reason===null)return false;if(reason.trim().length<3){setErr('Give a short reason.');return false}}
    return Boolean(await call('admin_reference_source_save',{p_id:item?.id||null,p_fields:fields,p_reason:reason},item?`${item.name} saved.`:'Site added.'))}
  const uses=data?.uses||[],cats=data?.categories||[],useLabel=Object.fromEntries(uses.map(u=>[u.key,u.label])),catLabel=Object.fromEntries(cats.map(c=>[c.key,c.label]))
  const stateOf=x=>x.retired?'retired':x.checking?'checking':x.health==='healthy'?'reachable':x.health==='degraded'?'unreachable':'unchecked'
  const items=useMemo(()=>(data?.items||[]).filter(x=>(showRetired||!x.retired)&&(!cat||x.category===cat)&&(!use||(x.uses||[]).includes(use))&&(!country||x.country===country)&&(!status||stateOf(x)===status)&&(!q||`${x.name} ${x.url} ${x.domain||''} ${x.purpose||''}`.toLowerCase().includes(q.toLowerCase()))).map(x=>({...x,__label:x.name,__muted:x.retired||!x.enabled})),[data,q,cat,use,country,status,showRetired])
  if(!data)return <section className="m-panel"><Loading label="Loading reference sources…"/></section>
  const can=Boolean(data.can_edit),manage=Boolean(data.can_manage),all=data.items||[],live=all.filter(x=>!x.retired)
  const countries=[...new Set(all.map(x=>x.country).filter(Boolean))]
  const columns=[
    {key:'site',label:'Site',width:'minmax(220px,2fr)',render:x=><span><strong>{x.name}</strong><span className="xl-sub">{x.domain||x.url}</span></span>},
    {key:'uses',label:'Uses',width:'minmax(180px,2fr)',render:x=>(x.uses||[]).map(u=><Pill key={u} tone="violet" title={useLabel[u]||u}>{USE_CHIP[u]||useLabel[u]||u}</Pill>)},
    {key:'category',label:'Category',width:'minmax(140px,1.2fr)',render:x=><Pill>{catLabel[x.category]||x.category}</Pill>},
    {key:'country',label:'Country',width:'110px',render:x=><Pill>{COUNTRY[x.country]||x.country}</Pill>},
    {key:'status',label:'Status',width:'minmax(130px,1fr)',render:x=>{const st=stateOf(x);return <><Pill tone={{reachable:'success',unreachable:'danger',retired:'neutral',checking:'info'}[st]||'warning'}>{{reachable:'Reachable',unreachable:'Not reachable',retired:'Retired',checking:'Checking…',unchecked:'Not checked yet'}[st]}</Pill>{x.checked_at&&<span className="xl-sub" title={x.http?`HTTP ${x.http}`:undefined} data-http={x.http||undefined}>{x.http?`${httpWords(x.http)} · `:''}{fmtDateTime(x.checked_at)}</span>}</>}},
    {key:'on',label:'On',width:'70px',align:'end',render:x=>x.retired?<Pill>Retired</Pill>:<Switch on={Boolean(x.enabled)} label={`${x.enabled?'Switch off':'Switch on'} ${x.name}`} disabled={!manage||busy} onChange={on=>save(x,{enabled:on},`Switch ${on?'on':'off'} ${x.name}?${on?'':' The platform will stop using it.'}`,true)}/>},
  ]
  return <>
    <div className="cf-metric-grid">
      <Metric label="Sites in use" value={fmtNumber(live.filter(x=>x.enabled).length)} detail={`${fmtNumber(live.filter(x=>!x.enabled).length)} switched off`} icon={Globe}/>
      <Metric label="Not a university site" value={fmtNumber(live.filter(x=>x.enabled&&x.uses?.includes('not_provider_site')).length)} icon={Globe}/>
      <Metric label="Not checked yet or not reachable" value={fmtNumber(live.filter(x=>x.health!=='healthy').length)} detail={`${fmtNumber(live.filter(x=>x.health==='degraded').length)} not reachable`} icon={RefreshCw} tone={live.some(x=>x.health==='degraded')?'warning':'neutral'}/>
    </div>
    <section className="m-panel" data-reference-sources>
      <SectionTitle icon={Globe} title="Reference sources" subtitle="Third-party sites the platform refers to, and how each one is used. The platform reads this list; nothing about these sites is fixed in code. Open a row to edit it."/>
      <XlToolbar actions={<>{can&&<Button compact onClick={()=>call('admin_reference_source_action',{p_id:null,p_action:'check_all',p_reason:null},'Checking every site; results appear in a few seconds.')} disabled={busy}><RefreshCw size={14}/>Check all</Button>}
          {manage&&<Button compact variant="primary" onClick={()=>setAdding(x=>!x)}><Plus size={14}/>Add site</Button>}</>}>
        <XlField label="Site"><span className="pq-search sl-search"><Search size={14}/><input type="search" value={q} onChange={e=>setQ(e.target.value)} placeholder="Name, address or domain" aria-label="Find a site"/></span></XlField>
        <XlField label="Uses"><select value={use} onChange={e=>setUse(e.target.value)} aria-label="Use"><option value="">All uses</option>{uses.map(u=><option key={u.key} value={u.key}>{u.label}</option>)}</select></XlField>
        <XlField label="Category"><select value={cat} onChange={e=>setCat(e.target.value)} aria-label="Category"><option value="">All categories</option>{cats.map(c=><option key={c.key} value={c.key}>{c.label}</option>)}</select></XlField>
        <XlField label="Country"><select value={country} onChange={e=>setCountry(e.target.value)} aria-label="Country"><option value="">All</option>{countries.map(c=><option key={c} value={c}>{COUNTRY[c]||c}</option>)}</select></XlField>
        <XlField label="Status"><select value={status} onChange={e=>setStatus(e.target.value)} aria-label="Status"><option value="">Any</option><option value="reachable">Reachable</option><option value="unreachable">Not reachable</option><option value="unchecked">Not checked yet</option></select></XlField>
        <label className="rs-check"><input type="checkbox" checked={showRetired} onChange={e=>setShowRetired(e.target.checked)}/>Show retired</label>
      </XlToolbar>
      {!can&&<p className="xl-note">You can view these. A Curator or above can edit names and addresses; a PIM Operator or above can change how a site is used.</p>}
      {err&&<p className="fr-error" role="alert">{err}</p>}
      {done&&<p className="sb-done" role="status">{done}</p>}
      {adding&&<SiteForm uses={uses} cats={cats} onCancel={()=>setAdding(false)} onSave={async f=>{if(await save(null,f,`Add ${f.name}?`,true))setAdding(false)}}/>}
      <details className="rs-help"><summary>What each use means</summary><ul>{uses.map(u=><li key={u.key}><strong>{u.label}</strong>: {u.help}</li>)}</ul>
        <p>A domain with a dot (education.gov.au) matches that site and its subdomains. A single name with no dot (google) matches any site whose name starts with it, such as google.com and google.com.au.</p></details>
      <ExpandList columns={columns} rows={items} rowKey={x=>x.id} openKey={open} onOpen={setOpen} dataAttr="data-site" empty="No sites match these filters."
        renderBody={x=><SiteBody x={x} uses={uses} cats={cats} can={can} manage={manage} busy={busy} useLabel={useLabel}
          onSave={(fields,needsReason)=>save(x,fields,`Save the changes to ${x.name}?`,needsReason)}
          onCheck={()=>call('admin_reference_source_action',{p_id:x.id,p_action:'check',p_reason:null})}
          onRetire={()=>{const r=window.prompt(`${x.retired?'Restore':'Retire'} ${x.name}?\n\nReason (kept in the change log):`,'');if(r!==null)call('admin_reference_source_action',{p_id:x.id,p_action:x.retired?'restore':'retire',p_reason:r},`${x.name} ${x.retired?'restored':'retired'}.`)}}/>}/>
    </section>
    {(data.events||[]).length>0&&<section className="m-panel"><SectionTitle icon={History} title="Recent changes"/>
      <ul className="ms-events">{data.events.map((e,i)=><li key={i}><strong>{e.target}</strong> {e.action==='change'?`changed (${(e.detail?.fields||[]).join(', ')})`:e.action==='add'?'added':e.action==='retire'?'retired':e.action==='restore'?'restored':e.action}{e.detail?.reason?` — ${e.detail.reason}`:''}<span className="l3v-code">{[e.by,fmtDateTime(e.at)].filter(Boolean).join(' · ')}</span></li>)}</ul></section>}
  </>
}

// An opened row: the same fields as Add site. Names, addresses and purpose are Curator edits; domain, uses, category and country
// change how the platform behaves, so they are PIM Operator edits with a reason.
function SiteBody({x,uses,cats,can,manage,busy,useLabel,onSave,onCheck,onRetire}){
  return <>
    {x.purpose&&<p className="xl-note">{x.purpose}</p>}
    <div className="xl-facts">{x.scholarships!=null&&<Pill tone="warning">{fmtNumber(x.scholarships)} scholarships sourced only here</Pill>}{x.ref_key&&<Pill tone="info">Ranking publisher: {x.ref_key}</Pill>}<a className="cf-link" href={x.url} target="_blank" rel="noreferrer"><ExternalLink size={12}/> Open {x.url}</a></div>
    {(can||manage)&&!x.retired?<SiteForm key={x.id} item={x} uses={uses} cats={cats} can={can} manage={manage} onSave={f=>{const behaviour=['domain','uses','category','country'].some(k=>k in f&&JSON.stringify(f[k])!==JSON.stringify(x[k]));return onSave(f,behaviour)}}/>
      :<p className="xl-note">{(x.uses||[]).map(u=>useLabel[u]||u).join(', ')}</p>}
    <div className="xl-actions">{can&&!x.retired&&<Button compact onClick={onCheck} disabled={busy||x.checking}><RefreshCw size={13}/>Check now</Button>}{manage&&<Button compact onClick={onRetire} disabled={busy}>{x.retired?'Restore':'Retire'}</Button>}</div>
  </>
}

function SiteForm({item,uses,cats,onSave,onCancel,can=true,manage=true}){
  const[f,setF]=useState(()=>item?{name:item.name||'',url:item.url||'',domain:item.domain||'',category:item.category,country:item.country||'ALL',purpose:item.purpose||'',uses:item.uses||[]}:{name:'',url:'https://',domain:'',category:'third_party_directory',country:'ALL',purpose:'',uses:['reference']})
  const set=(k,v)=>setF(x=>({...x,[k]:v}))
  const ok=f.name.trim().length>1&&/^https?:\/\/.+/.test(f.url)&&f.uses.length
  const changed=item?Object.fromEntries(Object.entries(f).filter(([k,v])=>JSON.stringify(v)!==JSON.stringify(item[k]??(k==='country'?'ALL':'')))):f
  return <div className="rs-add" data-site-form={item?item.id:'new'}>
    <div className="xl-form">
      <XlField label="Name"><input value={f.name} disabled={!can} onChange={e=>set('name',e.target.value)} placeholder="e.g. Uni Compare"/></XlField>
      <XlField label="Address" wide><input value={f.url} disabled={!can} onChange={e=>{set('url',e.target.value);if(!item&&!f.domain){try{set('domain',new URL(e.target.value).hostname.replace(/^www\./,''))}catch{}}}}/></XlField>
      <XlField label="Domain it covers"><input value={f.domain} disabled={!manage} onChange={e=>set('domain',e.target.value.toLowerCase())} placeholder="e.g. unicompare.com.au"/></XlField>
      <XlField label="Category"><select value={f.category} disabled={!manage} onChange={e=>set('category',e.target.value)}>{cats.map(c=><option key={c.key} value={c.key}>{c.label}</option>)}</select></XlField>
      <XlField label="Country"><select value={f.country} disabled={!manage} onChange={e=>set('country',e.target.value)}>{Object.entries(COUNTRY).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></XlField>
      <XlField label="Purpose" wide><input value={f.purpose} disabled={!can} onChange={e=>set('purpose',e.target.value)} placeholder="What it is and how we use it"/></XlField>
    </div>
    <fieldset className="sl-choice"><legend>Uses</legend>{uses.map(u=><label key={u.key} title={u.help}><input type="checkbox" disabled={!manage} checked={f.uses.includes(u.key)} onChange={()=>set('uses',f.uses.includes(u.key)?f.uses.filter(x=>x!==u.key):[...f.uses,u.key])}/>{u.label}</label>)}</fieldset>
    <div className="l3c-actions">{onCancel&&<Button compact onClick={onCancel}>Cancel</Button>}<Button compact variant="primary" disabled={!ok||(item&&!Object.keys(changed).length)} onClick={()=>onSave(item?changed:f)}>{item?<><Check size={13}/>Save changes</>:<><Plus size={13}/>Add site</>}</Button></div>
  </div>
}
