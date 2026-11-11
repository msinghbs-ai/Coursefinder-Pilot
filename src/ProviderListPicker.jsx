// CF-247 F-OPS (11 Nov 2026, Platform Admin 14:38 "RMIT added, there has to be better way in UI rather that using the provider's ID"): a list setting of
// provider ids is chosen by provider name. The chosen providers are shown as named chips (remove with x); typing two letters or more finds active providers
// by name (public.admin_provider_pick_v1). The value handed back is the same comma-separated list of ids the setting row saves with a reason.
import React,{useEffect,useRef,useState}from'react'
import{Plus,Search,X}from'lucide-react'
import{supabase}from'./lib/supabase'
import{parseList}from'./lib/settings-list.js'

const pick=async args=>{const{data,error}=await supabase.rpc('admin_provider_pick_v1',args);if(error)throw error;return data||{}}
const label=p=>p?`${p.name}${p.country?` (${p.country})`:''}`:''

// The names of provider ids, looked up once per id.
export function useProviderNames(ids){
  const[names,setNames]=useState({})
  const key=ids.join(',')
  useEffect(()=>{
    const want=ids.filter(id=>!(id in names));if(!want.length)return
    let live=true
    pick({p_ids:want}).then(d=>{if(!live)return;const m={};for(const id of want)m[id]=null;for(const p of d.named||[])m[p.id]=p;setNames(n=>({...n,...m}))}).catch(()=>{})
    return()=>{live=false}
  },[key])// eslint-disable-line react-hooks/exhaustive-deps
  return names
}

// Read-only: the providers of a list setting by name.
export function ProviderNames({value}){
  const ids=parseList(Array.isArray(value)?value.join(','):value),names=useProviderNames(ids)
  if(!ids.length)return<span>None</span>
  return<span className="plp-names">{ids.map(id=><span key={id} className="plp-chip is-static" title={id}>{names[id]?label(names[id]):names[id]===null?`Unknown provider ${id.slice(0,8)}`:'…'}</span>)}</span>
}

export default function ProviderListPicker({value,onChange,label:fieldLabel,emptyText}){
  const ids=parseList(value),names=useProviderNames(ids)
  const[q,setQ]=useState(''),[found,setFound]=useState([]),[busy,setBusy]=useState(false),[err,setErr]=useState('')
  const seq=useRef(0)
  useEffect(()=>{
    const t=q.trim();if(t.length<2){setFound([]);setErr('');return}
    const n=++seq.current;setBusy(true)
    const h=setTimeout(()=>{pick({p_query:t}).then(d=>{if(n===seq.current){setFound(d.found||[]);setErr('')}}).catch(()=>{if(n===seq.current)setErr('Providers could not be searched just now.')}).finally(()=>{if(n===seq.current)setBusy(false)})},250)
    return()=>clearTimeout(h)
  },[q])
  const add=p=>{if(!ids.includes(p.id))onChange([...ids,p.id].join(', '));setQ('');setFound([])}
  const remove=id=>onChange(ids.filter(x=>x!==id).join(', '))
  const shown=found.filter(p=>!ids.includes(p.id))
  return<div className="plp" data-provider-picker>
    <div className="plp-names" aria-label={`${fieldLabel||'Providers'} chosen`}>
      {ids.length?ids.map(id=><span key={id} className={`plp-chip${names[id]===null?' is-unknown':''}`} title={id} data-provider-chip={id}>
        {names[id]?label(names[id]):names[id]===null?`Unknown provider ${id.slice(0,8)}`:'…'}
        <button type="button" className="plp-x" aria-label={`Remove ${names[id]?names[id].name:id}`} onClick={()=>remove(id)}><X size={12}/></button>
      </span>):<span className="plp-empty">{emptyText||'None chosen'}</span>}
    </div>
    <label className="plp-search"><Search size={13} aria-hidden="true"/><span className="sr-hide">Add a provider to {fieldLabel||'the list'}</span>
      <input className="fv-input" type="search" placeholder="Add a provider: type its name" value={q} onChange={e=>setQ(e.target.value)}/></label>
    {q.trim().length>=2&&<ul className="plp-found" role="listbox" aria-label="Matching providers">
      {shown.map(p=><li key={p.id}><button type="button" role="option" aria-selected="false" onClick={()=>add(p)}><Plus size={12}/>{label(p)}</button></li>)}
      {!busy&&!err&&!shown.length&&<li className="plp-none">No provider found</li>}
      {busy&&<li className="plp-none">Searching…</li>}
      {err&&<li className="plp-none" role="alert">{err}</li>}
    </ul>}
  </div>
}
