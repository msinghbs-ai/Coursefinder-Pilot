// CourseFinder shared UI kit (UI-2).
// One home for building blocks used across screens. Components keep their existing
// markup and CSS classes, so moving a screen onto the kit does not change how it looks.
import { useEffect, useState } from 'react'
import { ArrowLeft, ChevronRight, Database } from 'lucide-react'

export function fmtNumber(v){const n=Number(v);return Number.isFinite(n)?n.toLocaleString():'—'}

export function PanelTitle({icon:Icon,title,subtitle,action}){return <div className="m-panel-title"><div className="m-panel-heading">{Icon&&<span className="m-panel-icon"><Icon size={16}/></span>}<div><h2>{title}</h2>{subtitle&&<p>{subtitle}</p>}</div></div>{action}</div>}
export function Pulse({label,value,tone,icon:Icon}){return <div className={`m-pulse tone-${tone}`}><span><Icon size={15}/></span><div><small>{label}</small><strong>{fmtNumber(value)}</strong></div></div>}
export function SummaryCard({icon:Icon,label,value,tone}){return <div className={`m-summary-card tone-${tone}`}><Icon size={18}/><div><small>{label}</small><strong>{value}</strong></div></div>}
export function EmptyState({icon:Icon,title,text}){return <div className="m-empty-state"><span><Icon size={24}/></span><h2>{title}</h2><p>{text}</p></div>}
export function EmptyInline({text}){return <div className="m-empty-inline"><Database size={18}/><span>{text}</span></div>}

// One pager for every screen. className/withIcons let a screen keep its existing look.
export function Pager({offset,limit=50,total,onOffset,className='m-pager',withIcons=false}){
  const page=Math.floor(offset/limit)+1,pages=Math.max(1,Math.ceil(total/limit))
  return <div className={className}><span>Page <strong>{page}</strong> of {pages} · {fmtNumber(total)} records</span><div>
    <button disabled={offset<=0} onClick={()=>onOffset(Math.max(0,offset-limit))}>{withIcons&&<ArrowLeft size={14}/>}Previous</button>
    <button disabled={offset+limit>=total} onClick={()=>onOffset(offset+limit)}>Next{withIcons&&<ChevronRight size={14}/>}</button>
  </div></div>
}

// Remembered screen choices (filters, sort, tab, search).
// Opening order: the address bar wins (a shared link shows what the sender saw), then this
// user's last choices for this screen, then the defaults. Unreadable or wrongly typed saved
// values are ignored. The key format matches the Catalogue's existing saved state
// (coursefinder:pim:screen-state:v1:<user>:<screen>), so saved choices carry over.
// userId may arrive after first render: pass null until it is known; nothing is read or
// written until then, and the saved state is loaded once when it arrives.
const STATE_PREFIX='coursefinder:pim:screen-state:v1:'
function sameType(v,def){
  if(def===null||def===undefined)return true
  if(Array.isArray(def))return Array.isArray(v)
  if(typeof def==='object')return v!==null&&typeof v==='object'&&!Array.isArray(v)
  return typeof v===typeof def
}
function coerce(raw,def){
  if(typeof def==='number'){const n=Number(raw);return Number.isFinite(n)?n:def}
  if(typeof def==='boolean')return raw==='true'||raw==='1'
  if(def!==null&&typeof def==='object'){try{const v=JSON.parse(raw);return sameType(v,def)?v:def}catch{return def}}
  return raw
}
export function rememberedStateKey(screen,userId){return `${STATE_PREFIX}${userId||'anonymous'}:${screen}`}
export function readRememberedState(screen,defaults,userId,urlParams=null){
  const next={...defaults}
  try{const saved=JSON.parse(localStorage.getItem(rememberedStateKey(screen,userId))||'null');if(saved&&typeof saved==='object'&&!Array.isArray(saved))for(const k of Object.keys(defaults))if(k in saved&&sameType(saved[k],defaults[k]))next[k]=saved[k]}catch{}
  if(urlParams&&typeof urlParams.get==='function')for(const k of Object.keys(defaults)){const raw=urlParams.get(k);if(raw!==null&&raw!=='')next[k]=coerce(raw,defaults[k])}
  return next
}
export function useRememberedState(screen,defaults,{userId=null,urlParams=null}={}){
  const ready=userId!==null&&userId!==undefined
  const key=ready?rememberedStateKey(screen,userId):null
  const [state,setState]=useState(()=>ready?readRememberedState(screen,defaults,userId,urlParams):{...defaults})
  const [loadedKey,setLoadedKey]=useState(ready?key:null)
  useEffect(()=>{if(key&&key!==loadedKey){setState(readRememberedState(screen,defaults,userId,urlParams));setLoadedKey(key)}},[key])
  const serialised=JSON.stringify(state)
  useEffect(()=>{if(key&&key===loadedKey){try{localStorage.setItem(key,serialised)}catch{}}},[key,loadedKey,serialised])
  const update=patch=>setState(s=>({...s,...(typeof patch==='function'?patch(s):patch)}))
  const reset=()=>{try{if(key)localStorage.removeItem(key)}catch{};setState({...defaults})}
  return [state,update,reset,Boolean(key&&key===loadedKey)]
}
// Only the choices that differ from the defaults, for a shareable address-bar link.
export function shareableParams(state,defaults){
  const out={}
  for(const k of Object.keys(defaults)){const v=state[k],d=defaults[k];if(JSON.stringify(v)===JSON.stringify(d)||v===''||v==null)continue;out[k]=typeof v==='object'?JSON.stringify(v):String(v)}
  return out
}
