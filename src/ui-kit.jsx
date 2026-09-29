// CourseFinder shared UI kit (UI-2, B2 UI uniformity).
// One home for building blocks used across screens: status chips, badges, buttons, metrics,
// empty states, filter chips, loading rows, section titles and the pager. Look and feel come
// from ui-kit.css and tokens.css; numbers and dates from lib/format.js.
import { useEffect, useState } from 'react'
import { ArrowLeft, ChevronRight, Database, RefreshCw, X } from 'lucide-react'
import { fmtNumber } from './lib/format.js'

export { fmtNumber, fmtDate, fmtDateTime, fmtDayMonth, fmtTime, fmtMoney, fmtPercent, fmtShare, fmtRelative, fmtBytes } from './lib/format.js'

// "layer2_run" -> "Layer2 run"; keeps the words, drops underscores.
export function humanLabel(v){const s=String(v??'').replaceAll('_',' ').replaceAll('-',' ').trim();return s?s.charAt(0).toUpperCase()+s.slice(1):''}

// One mapping from a record status to a colour tone, used by every status chip.
const TONES={
  success:['completed','complete','succeeded','success','published','active','resolved','captured','current','admitted','approved','enabled','healthy','passed','pass','qualified','applied','validated','accepted','verified','ok','ready','live','extracted'],
  danger:['failed','failure','error','rejected','blocked','conflict','stuck','unhealthy','critical','disabled','deleted','cancelled','canceled','revoked'],
  warning:['open','draft','review','warning','stale','expired','source_null','needs_review','partial','superseded','held','paused','degraded','attention','overdue','missing'],
  info:['regulatory','running','processing','queued','pending','in_review','in_progress','scheduled','reserved','retry','retrying','candidate','awaiting_l3','missing_extraction','uploaded','parsed'],
  violet:['ai','layer3','model','statistics'],
}
export function statusTone(value){const s=String(value??'').toLowerCase().trim().replaceAll(' ','_');for(const[t,list]of Object.entries(TONES))if(list.includes(s))return t;return'neutral'}

/** Status chip. tone overrides the automatic tone; label overrides the shown text. */
export function StatusChip({value,tone,label,title,className=''}){const t=tone||statusTone(value);return <span className={`cf-chip tone-${t}${className?' '+className:''}`} title={title} data-state={String(value??'').toLowerCase()||undefined}>{label??humanLabel(value||'unknown')}</span>}
/** Quiet outlined badge (tags, types, Layer badges). */
export function Badge({children,tone,title,className=''}){return <span className={`cf-badge${tone?' tone-'+tone:''}${className?' '+className:''}`} title={title}>{children}</span>}
/** "Layer 2" badge, the one way a Layer is labelled. */
export function LayerBadge({layer,title}){const n=String(layer??'').replace(/\D/g,'');return n?<Badge className="cf-layer-badge" title={title||`Layer ${n}`}>Layer {n}</Badge>:null}
/** Button. variant: 'primary' | 'danger' | undefined (secondary). */
export function Button({children,variant,compact=false,className='',type='button',...rest}){return <button type={type} className={`cf-btn${variant?' '+variant:''}${compact?' compact':''}${className?' '+className:''}`} {...rest}>{children}</button>}
/** Metric tile: label, value, optional detail and icon. Numbers are formatted en-AU. */
export function Metric({label,value,detail,icon:Icon,tone='neutral',className=''}){const shown=typeof value==='number'?fmtNumber(value):(value??'—');return <div className={`cf-metric tone-${tone}${className?' '+className:''}`}>{Icon&&<span className="cf-metric-icon"><Icon size={16}/></span>}<div><small>{label}</small><strong>{shown}</strong>{detail&&<span className="cf-metric-detail">{detail}</span>}</div></div>}
/** Small empty message (inside panels and lists). */
export function Empty({children,text,icon:Icon}){return <div className="cf-empty">{Icon&&<Icon size={17}/>}<span>{children??text}</span></div>}
/** Empty table row. */
export function EmptyRow({colSpan,children,text}){return <tr><td colSpan={colSpan} className="cf-empty-cell">{children??text}</td></tr>}
/** Applied-filter chip with a remove button. */
export function FilterChip({label,onRemove}){return <span className="cf-filter-chip">{label}<button type="button" aria-label={`Remove ${typeof label==='string'?label:'filter'}`} onClick={onRemove}><X size={12}/></button></span>}
/** Loading line. */
export function Loading({label='Loading…',compact=false}){return <div className={`cf-loading${compact?' compact':''}`}><RefreshCw size={16}/><span>{label}</span></div>}
/** Placeholder table rows while a page loads. */
export function SkeletonRows({cols,rows=7}){return Array.from({length:rows}).map((_,i)=><tr key={i}>{Array.from({length:cols}).map((_,j)=><td key={j}><span className="cf-skeleton-line"/></td>)}</tr>)}
/** Section title: icon, heading, optional subtitle and action. */
export function SectionTitle({icon:Icon,title,subtitle,action,level=3}){const H=level===2?'h2':'h3';return <div className="cf-section-title"><div className="cf-section-heading">{Icon&&<span className="cf-section-icon"><Icon size={16}/></span>}<div><H>{title}</H>{subtitle&&<p>{subtitle}</p>}</div></div>{action}</div>}

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

// ---------------------------------------------------------------------------
// Standard page layout (v2.15.107). Every menu destination renders inside the app shell:
// the shell draws PageHeader (breadcrumbs, one title, subtitle, actions) and each page
// draws PageLayout (optional tabs, optional toolbar, content). No screen draws its own
// shell, side menu or second title.

/** Page header used by the app shell: breadcrumbs, one title, a plain subtitle, actions on the right. */
export function PageHeader({breadcrumbs,title,subtitle,actions,leading}){return <header className="m-topbar cf-page-header">
  <div className="m-title-wrap">{leading}<div>{breadcrumbs}<h1>{title}</h1>{subtitle&&<p>{subtitle}</p>}</div></div>
  {actions&&<div className="m-topbar-actions">{actions}</div>}
 </header>}

/** Sub-navigation for one page. tabs: [{key,label,count?}]. Keyboard: left/right arrows move between tabs. */
export function PageTabs({tabs,active,onChange,label='Page sections'}){
  if(!tabs?.length)return null
  const move=(e,i)=>{if(e.key!=='ArrowRight'&&e.key!=='ArrowLeft')return;e.preventDefault();const n=tabs[(i+(e.key==='ArrowRight'?1:tabs.length-1))%tabs.length];onChange?.(n.key);requestAnimationFrame(()=>document.getElementById(`cf-tab-${n.key}`)?.focus())}
  return <div className="cf-page-tabs" role="tablist" aria-label={label}>{tabs.map((t,i)=><button key={t.key} id={`cf-tab-${t.key}`} type="button" role="tab" aria-selected={active===t.key} tabIndex={active===t.key?0:-1} className={active===t.key?'active':''} onClick={()=>onChange?.(t.key)} onKeyDown={e=>move(e,i)}>{t.label}{t.count!=null&&<span className="cf-tab-count">{fmtNumber(t.count)}</span>}</button>)}</div>
}

/** Page body: optional tabs, optional toolbar row, then the content. */
export function PageLayout({tabs,active,onTab,toolbar,children,className='',label}){
  return <div className={`cf-page${className?' '+className:''}`}>
    {tabs?.length>1&&<PageTabs tabs={tabs} active={active} onChange={onTab} label={label}/>}
    {toolbar&&<div className="cf-page-toolbar">{toolbar}</div>}
    <div className="cf-page-body" role={tabs?.length>1?'tabpanel':undefined} aria-labelledby={tabs?.length>1&&active?`cf-tab-${active}`:undefined}>{children}</div>
  </div>
}

/** Small coloured status dot with a text label for screen readers. tone: ok | warning | critical | unknown */
export function StatusDot({tone='unknown',label}){return <span className={`cf-status-dot tone-${tone}`} role="img" aria-label={label||tone} title={label}/>}

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
