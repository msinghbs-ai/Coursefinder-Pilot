// CF-247 s931 (Decision 279, Platform Admin 21 Nov 2026 10:53; spec admin docs/design/2026-11-21-layer4-human-ui-and-guide-spec.md §4.1, §5.1): Layer 4 Review's
// primary filter row. It replaces the kind toolbar in place: Module / Field (the queues with their counts, grouped by module; descriptions split into
// Course description and University description), University (type-ahead, provider id), Destination country (the live target countries), Source country
// (entry requirements only: the student's country of prior education) and Decision bucket. Every filter maps to an existing server argument
// (kind, provider_id, country, source_country: D3 migration 20261121200000); it emits {kind, provider_id, country, source_country, bucket}.
import React,{useEffect,useRef,useState}from'react'
import{ChevronDown,Search,X}from'lucide-react'
import{supabase}from'./lib/supabase'
import{fmtNumber}from'./ui-kit'
import{countryPairs,useLookups}from'./lib/lookups.js'
import{BUCKETS,DESC_PART,MODULES}from'./lib/l4-rules.js'

const rpc=async(action,args)=>{const{data,error}=await supabase.rpc('admin_layer4_inbox',{p_action:action,p_args:args||{}});if(error)throw new Error(error.message);return data||{}}
const aer=async(action,args={})=>{const{data,error}=await supabase.rpc('admin_aer',{p_action:action,p_args:args});if(error)throw error;return data}

/** The label and count of the chosen queue (and description part) as the Module / Field button shows it. */
export function moduleLabel(kind,part,kinds,countOf,split){
  if(!kind)return 'Choose a queue'
  if(kind==='provider_description'&&part)return `${DESC_PART[part]} (${fmtNumber(Number(split?.[part])||0)})`
  return `${kinds?.[kind]?.label||kind} (${fmtNumber(countOf(kind))})`}

export default function Layer4PrimaryFilters({kinds,order,kind,part,split,countOf,onKind,provider,onProvider,country,onCountry,source,onSource,bucket,onBucket,showAll=false,total=0}){
  const lk=useLookups(),[open,setOpen]=useState(false),ref=useRef(null)
  useEffect(()=>{const close=e=>{if(ref.current&&!ref.current.contains(e.target))setOpen(false)};addEventListener('mousedown',close);return()=>removeEventListener('mousedown',close)},[])
  const shown=order.filter(k=>countOf(k)>0),named=new Set(MODULES.flatMap(([,ks])=>ks))
  const groups=[...MODULES.map(([m,ks])=>[m,ks.filter(k=>shown.includes(k))]),['Other',shown.filter(k=>!named.has(k))]].filter(([,ks])=>ks.length)
  const pick=(k,p='')=>{onKind(k,p);setOpen(false)}
  const descOpts=()=>{const c=Number(split?.course)||0,u=Number(split?.university)||0,on=kind==='provider_description'
    if(!split)return [<button key="pd" type="button" className={on?'on':''} data-l4-kind="provider_description" onClick={()=>pick('provider_description','')}>{kinds?.provider_description?.label||'Descriptions'} ({fmtNumber(countOf('provider_description'))})</button>]
    const first=c>0?'course':'university'
    return [c>0&&<button key="c" type="button" className={on&&part==='course'?'on':''} data-l4-kind={first==='course'?'provider_description':undefined} data-l4-kind-part="provider_description:course" onClick={()=>pick('provider_description','course')}>{DESC_PART.course} ({fmtNumber(c)})</button>,
      u>0&&<button key="u" type="button" className={on&&part==='university'?'on':''} data-l4-kind={first==='university'?'provider_description':undefined} data-l4-kind-part="provider_description:university" onClick={()=>pick('provider_description','university')}>{DESC_PART.university} ({fmtNumber(u)})</button>].filter(Boolean)}
  const aerOnly=kind==='aer_review'
  return <div className="l4p" role="toolbar" aria-label="Filters" data-l4-primary>
    <div className="l4p-field l4p-module" ref={ref}><small>Module / Field</small>
      <button type="button" className="m-filter-button has-value" aria-expanded={open} onClick={()=>setOpen(v=>!v)} data-l4-module-toggle><strong>{moduleLabel(kind,part,kinds,countOf,split)}</strong><ChevronDown size={14}/></button>
      <div className="l4p-pop" hidden={!open} data-l4-module-list>
        {showAll&&<button type="button" className={!kind?'on':''} onClick={()=>pick('','')} data-l4-kind-all>All ({fmtNumber(total)})</button>}
        {groups.map(([m,ks])=><div key={m} className="l4p-group" data-l4-module={m}><p>{m}</p>{ks.flatMap(k=>k==='provider_description'?descOpts():[<button key={k} type="button" className={kind===k?'on':''} data-l4-kind={k} onClick={()=>pick(k,'')}>{kinds[k]?.label||k} ({fmtNumber(countOf(k))})</button>])}</div>)}
      </div></div>
    <UniversityPick kind={kind} provider={provider} onProvider={onProvider}/>
    <div className="l4p-field"><small>Destination country</small>
      <div className="l4p-pills" role="group" aria-label="Destination country" data-l4-dest>{[['','All'],...countryPairs(lk)].map(([v,l])=><button key={v||'all'} type="button" className={country===v?'on':''} aria-pressed={country===v} onClick={()=>onCountry(v)} data-l4-dest-country={v||'all'} title={v?l:'Every country'}>{v||'All'}</button>)}</div></div>
    <SourceCountry on={aerOnly} value={source} onChange={onSource}/>
    <label className="l4p-field"><small>Decision bucket</small>
      <select value={bucket} onChange={e=>onBucket(e.target.value)} aria-label="Decision bucket" data-l4-bucket>{BUCKETS.map(([v,l])=><option key={v} value={v}>{l}</option>)}</select></label>
  </div>
}

/** University: type-ahead over the universities with waiting items (the existing universities read), chosen by provider id. */
function UniversityPick({kind,provider,onProvider}){
  const[q,setQ]=useState(''),[list,setList]=useState([]),[open,setOpen]=useState(false)
  useEffect(()=>{if(!open||q.trim().length<2){setList([]);return}const t=setTimeout(()=>rpc('universities',{kind,q:q.trim(),limit:10,offset:0}).then(d=>setList(d.items||[])).catch(()=>setList([])),250);return()=>clearTimeout(t)},[q,kind,open])
  if(provider?.provider_id)return <div className="l4p-field"><small>University</small><span className="l4p-chosen" data-l4-uni-chosen={provider.provider_id}><strong>{provider.name}</strong><button type="button" aria-label="Clear the university" onClick={()=>{onProvider(null);setQ('')}} data-l4-uni-clear><X size={13}/></button></span></div>
  return <div className="l4p-field l4p-uni"><small>University</small>
    <label className="l4i-search"><Search size={14}/><input value={q} onFocus={()=>setOpen(true)} onChange={e=>{setQ(e.target.value);setOpen(true)}} placeholder="Find a university…" aria-label="University" data-l4-uni-search/></label>
    {open&&list.length>0&&<ul className="l4p-pop" data-l4-uni-results>{list.map(u=><li key={u.provider_id}><button type="button" onClick={()=>{onProvider({provider_id:u.provider_id,name:u.name});setOpen(false);setQ('')}} data-l4-uni-pick={u.provider_id}>{u.name}<small> · {u.country||''} · {fmtNumber(u.total||Object.values(u.by_kind||{}).reduce((a,b)=>a+Number(b||0),0))} waiting</small></button></li>)}</ul>}</div>
}

/** Source country: entry requirements only (the student's country of prior education), from the countries the entry rows hold. */
function SourceCountry({on,value,onChange}){
  const[list,setList]=useState(null)
  useEffect(()=>{if(!on||list)return;let live=true;aer('options').then(o=>live&&setList(o?.countries||[])).catch(()=>live&&setList([]));return()=>{live=false}},[on])
  return <label className="l4p-field" title={on?'':'Source country applies to entry requirements (AER) only'}><small>Source country</small>
    <select value={on?value:''} disabled={!on} onChange={e=>onChange(e.target.value)} aria-label="Source country" data-l4-source><option value="">Any</option>{(list||[]).map(c=><option key={c.code} value={c.code}>{c.name} ({c.code})</option>)}</select></label>
}
