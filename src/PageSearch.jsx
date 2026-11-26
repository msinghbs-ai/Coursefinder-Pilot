// s1270 (SS-Programme-Control 26 Nov 2026 17:47, Platform Admin: "a search bar at the top of long Admin pages to locate settings, controls and sections without
// excessive scrolling"; Operating Model v1.26 UAT). One reusable search-and-jump bar. PageLayout draws it for a page that opts in (nav-map SEARCH_PAGES).
//
// What it searches (nothing is read from the database by this file; no backend, no new setting, no Consumer API):
//   1. the page's tabs (already limited to the signed-in role by shownTabs), with the plain words each tab is also known by (`find` in nav-map);
//   2. the sections it finds on the open tab: cards, folds (details), headings and setting rows;
//   3. entries a screen registers itself with usePageSearchEntries: Settings registers every setting from the read it already loaded (label, key, what uses
//      it, section and group); Data Delivery and the Autonomous PIM block register their streams and views. A closed fold's inner controls are only found
//      when the screen registers them, because a closed fold draws nothing.
// Choosing a result opens its tab, expands the card, fold or view that holds it, scrolls to it, highlights it for a few seconds and moves keyboard focus
// there. It changes nothing and writes nothing. A role sees only what its screens drew or loaded, so the search never offers a control a role cannot see.
import React,{createContext,useCallback,useContext,useEffect,useId,useMemo,useReducer,useRef,useState}from'react'
import{Search,X}from'lucide-react'
import{dedupe,KIND_WORD,norm,prepare,rank}from'./lib/page-search.js'
import{TAB_FIND}from'./nav-map.js'
import'./page-search.css'

const Registry=createContext(null)

/** A screen offers entries to the page search. Pass a memoised array; entries leave the search when the screen unmounts.
 *  Entry: {id, kind: 'view'|'section'|'setting', label, path?, keywords?, help?, key?, jump?: () => selector|Element|void, target?: selector, open?: [selector]} */
export function usePageSearchEntries(entries){
  const reg=useContext(Registry),owner=useId()
  useEffect(()=>{if(!reg||!entries)return undefined;reg.set(owner,entries);return()=>reg.clear(owner)},[reg,owner,entries])
}

const MAX_WAIT_MS=6000,HIT_MS=4200
const reducedMotion=()=>typeof matchMedia==='function'&&matchMedia('(prefers-reduced-motion: reduce)').matches
const cleanText=el=>(el?.textContent||'').replace(/\s+/g,' ').trim()
const short=(s,n=90)=>s.length>n?`${s.slice(0,n-1).trim()}…`:s
const visible=el=>Boolean(el&&(el.offsetParent||el.getClientRects().length))

/** The nearest heading above an element, so "Details" under the Firecrawl card reads "Firecrawl › Details". */
function contextOf(el,root){
  const parts=[]
  for(let p=el.parentElement;p&&p!==root&&parts.length<2;p=p.parentElement){
    let t=''
    if(p.matches?.('[data-card]'))t=cleanText(p.querySelector('.cf-card-title'))
    else if(p.matches?.('section,.m-panel,details')){const h=p.querySelector(':scope > h2, :scope > h3, :scope > .cf-section-title h2, :scope > .cf-section-title h3, :scope > summary strong, :scope > .cf-card-head h3');t=cleanText(h)}
    if(t&&!parts.includes(t))parts.push(t)
  }
  return parts.reverse().join(' › ')
}

/** What the open tab has drawn: cards, folds, headings and setting rows. Each entry keeps its element; a fold or card is opened when chosen. */
function scanDom(root){
  if(!root)return[]
  const out=[]
  const push=(kind,label,el,extra={})=>{label=short(label);if(norm(label).length<2)return;out.push(prepare({id:`dom:${kind}:${norm(label)}:${out.length}`,kind,label,path:contextOf(el,root),el,...extra}))}
  root.querySelectorAll('[data-card]').forEach(c=>push('section',cleanText(c.querySelector('.cf-card-title')),c,{help:cleanText(c.querySelector('.cf-card-sub'))}))
  root.querySelectorAll('details').forEach(d=>{
    const s=d.querySelector(':scope > summary');if(!s)return
    const strong=s.querySelector('strong');const label=cleanText(strong)||cleanText(s)
    push('section',label,d,{help:cleanText(s).slice(0,200)})
  })
  root.querySelectorAll('h2,h3,h4,h5').forEach(h=>{
    if(h.closest('summary,.cf-card-head,[role="tablist"],.cf-page-search'))return
    push('section',cleanText(h),h)
  })
  root.querySelectorAll('[data-setting]').forEach(r=>push('setting',r.getAttribute('data-setting')||'',r,{help:cleanText(r.querySelector('small'))}))
  return out
}

/** Open what hides the target: a closed card (it draws nothing until opened) and every closed fold around it. */
function openOne(o){
  if(!o)return false
  if(o.matches?.('[data-card]')&&o.getAttribute('data-card-open')==='false'){o.querySelector('.cf-card-toggle')?.click();return true}
  if(o.tagName==='DETAILS'&&!o.open){o.open=true;return true}
  return false
}
const openAncestors=el=>{let changed=false;for(let p=el.parentElement;p;p=p.parentElement){if(p.tagName==='DETAILS'&&!p.open){p.open=true;changed=true}}return changed}

function resolve(t){
  if(!t)return null
  if(typeof t==='string'){try{return document.querySelector(t)}catch{return null}}
  return t.isConnected?t:null
}

/** Move to a result: tab first, then poll (a tab, a fold or a lazy section draws a moment later) until the element is drawn, then open, scroll, highlight and focus. */
function jumpTo(entry,{active,onTab,offset,done}){
  let stop=false
  const started=Date.now()
  if(entry.kind==='tab'){onTab(entry.tabKey);document.querySelector('.m-main')?.scrollTo?.({top:0,behavior:reducedMotion()?'auto':'smooth'});done?.(true);return()=>{}}
  if(entry.tabKey&&entry.tabKey!==active)onTab(entry.tabKey)
  let target=entry.target||entry.el
  try{const r=entry.jump?.();if(r)target=r}catch{/* the screen that owned this entry is gone; keep polling for the selector */}
  const step=()=>{
    if(stop)return
    ;(entry.open||[]).forEach(sel=>openOne(resolve(sel)))
    const el=resolve(target)
    // opening a card or fold draws its content on the next tick, so look again before moving
    const changed=el?Boolean(openOne(el))||openAncestors(el):false
    if(el&&!changed&&(visible(el)||Date.now()-started>MAX_WAIT_MS-1500)){
      el.style.scrollMarginTop=`${offset}px`
      el.scrollIntoView?.({block:'start',behavior:reducedMotion()?'auto':'smooth'})
      el.classList.add('ps-hit')
      const ctl=el.matches?.('input,select,textarea,button,a')?el:el.querySelector?.('input:not([type=hidden]),select,textarea')
      if(ctl)ctl.focus?.({preventScroll:true});else{if(!el.hasAttribute('tabindex'))el.setAttribute('tabindex','-1');el.focus?.({preventScroll:true})}
      setTimeout(()=>el.classList.remove('ps-hit'),HIT_MS)
      done?.(true);return
    }
    if(Date.now()-started<MAX_WAIT_MS)setTimeout(step,120);else done?.(false)
  }
  step()
  return()=>{stop=true}
}

/** The search bar and the registry of entries below it. PageLayout renders this around the page body. */
export function PageSearchScope({tabs,active,onTab,pageLabel,pageKey,children}){
  const store=useRef(new Map()),[version,bump]=useReducer(x=>x+1,0)
  // entries are prepared (normalised) once, when a screen registers them, not on every keystroke
  const reg=useMemo(()=>({set:(o,e)=>{store.current.set(o,(e||[]).map(x=>x._f?x:prepare(x)));bump()},clear:o=>{if(store.current.delete(o))bump()}}),[])
  return <Registry.Provider value={reg}>
    <PageSearch tabs={tabs} active={active} onTab={onTab} pageLabel={pageLabel} pageKey={pageKey} store={store} version={version}/>
    {children}
  </Registry.Provider>
}

function PageSearch({tabs,active,onTab,pageLabel,pageKey,store,version}){
  const[q,setQ]=useState(''),[open,setOpen]=useState(false),[idx,setIdx]=useState(0),[dom,setDom]=useState([]),[msg,setMsg]=useState(''),[top,setTop]=useState(0)
  const inputRef=useRef(null),wrapRef=useRef(null),cancel=useRef(()=>{}),listId=useId()
  // tabs of this page for this role (shownTabs already removed the ones above the role)
  const tabEntries=useMemo(()=>(tabs||[]).filter(t=>t.key!==active).map(t=>prepare({id:`tab:${t.key}`,kind:'tab',label:t.label,path:pageLabel||'',keywords:TAB_FIND[`${pageKey}.${t.key}`]||'',tabKey:t.key})),[tabs,active,pageLabel])
  const rescan=useCallback(()=>{const root=wrapRef.current?.closest('.cf-page')?.querySelector('.cf-page-body');setDom(scanDom(root))},[])
  // topbar height, so the bar sticks under it and a jump lands below both
  useEffect(()=>{
    const tb=document.querySelector('.m-topbar');if(!tb)return undefined
    const set=()=>setTop(Math.round(tb.getBoundingClientRect().height))
    set();const ro=typeof ResizeObserver==='function'?new ResizeObserver(set):null;ro?.observe(tb);addEventListener('resize',set)
    return()=>{ro?.disconnect();removeEventListener('resize',set)}
  },[])
  // "/" focuses the search when no field has focus
  useEffect(()=>{
    const k=e=>{if(e.key!=='/'||e.ctrlKey||e.metaKey||e.altKey)return;const t=e.target;if(t?.closest?.('input,textarea,select,[contenteditable="true"]'))return;e.preventDefault();inputRef.current?.focus()}
    addEventListener('keydown',k);return()=>removeEventListener('keydown',k)
  },[])
  useEffect(()=>()=>cancel.current(),[])
  // re-read the page as the person types (debounced), so a section that has just drawn is found
  useEffect(()=>{if(!q.trim())return undefined;const t=setTimeout(rescan,120);return()=>clearTimeout(t)},[q,rescan])
  const registered=useMemo(()=>[...store.current.values()].flat(),[store,version])
  const results=useMemo(()=>q.trim()?rank(dedupe([...registered,...tabEntries,...dom]),q,12):[],[q,registered,tabEntries,dom])
  useEffect(()=>{setIdx(0)},[q])
  const offset=top+(wrapRef.current?.offsetHeight||56)+36 // 36: the bar grows by the one-line status ('Opened …') once a jump is made, so the target must clear that too
  const choose=e=>{
    cancel.current();setOpen(false);setMsg(`Opening ${e.label}.`)
    cancel.current=jumpTo(e,{active,onTab,offset,done:ok=>setMsg(ok?`Opened ${e.label}.`:`Could not find ${e.label} on this screen. It may be hidden for your role.`)})
  }
  const onKey=e=>{
    if(e.key==='ArrowDown'){e.preventDefault();setOpen(true);setIdx(i=>Math.min(i+1,Math.max(results.length-1,0)))}
    else if(e.key==='ArrowUp'){e.preventDefault();setIdx(i=>Math.max(i-1,0))}
    else if(e.key==='Enter'){if(results[idx]){e.preventDefault();choose(results[idx])}}
    else if(e.key==='Escape'){if(q){setQ('');setOpen(false)}else inputRef.current?.blur()}
  }
  const shown=open&&q.trim()
  return <div className="cf-page-search" ref={wrapRef} style={{'--ps-top':`${top}px`}} data-page-search role="search" aria-label={`Search this page${pageLabel?`: ${pageLabel}`:''}`}>
    <div className="ps-box">
      <Search size={16} aria-hidden className="ps-icon"/>
      <input ref={inputRef} className="ps-input" type="search" inputMode="search" autoComplete="off" spellCheck="false" enterKeyHint="go" data-page-search-input
        placeholder="Search this page: a setting, section or control (press / to search)" aria-label="Search this page for a setting, section or control"
        role="combobox" aria-expanded={Boolean(shown)} aria-controls={listId} aria-autocomplete="list" aria-activedescendant={shown&&results[idx]?`${listId}-${idx}`:undefined}
        value={q} onChange={e=>{cancel.current();setQ(e.target.value);setOpen(true);setMsg('')}} onFocus={()=>{rescan();if(q.trim())setOpen(true)}} onBlur={()=>setTimeout(()=>{if(document.activeElement!==inputRef.current)setOpen(false)},160)} onKeyDown={onKey}/>
      {q&&<button type="button" className="ps-clear" aria-label="Clear search" onMouseDown={e=>e.preventDefault()} onClick={()=>{setQ('');setOpen(false);setMsg('');inputRef.current?.focus()}}><X size={15} aria-hidden/></button>}
    </div>
    {shown&&<ul className="ps-results" id={listId} role="listbox" aria-label="Search results" data-page-search-results>
      {results.length===0?<li className="ps-none" role="presentation" data-page-search-none>Nothing on this page matches “{q.trim()}”. Try another word, or part of a setting name.</li>
      :results.map((e,i)=><li key={e.id} id={`${listId}-${i}`} role="option" aria-selected={i===idx} className={i===idx?'is-on':''} data-ps-kind={e.kind} data-ps-id={e.id}>
        <button type="button" tabIndex={-1} onMouseDown={ev=>ev.preventDefault()} onClick={()=>choose(e)} onMouseEnter={()=>setIdx(i)}>
          <span className="ps-kind">{KIND_WORD[e.kind]||'Section'}</span>
          <span className="ps-text"><strong>{e.label}</strong>{(e.path||e.key)&&<small>{[e.path,e.key&&e.kind==='setting'?e.key:''].filter(Boolean).join(' · ')}</small>}</span>
        </button></li>)}
    </ul>}
    <div className="ps-sr" role="status" aria-live="polite">{shown?(results.length?`${results.length} result${results.length===1?'':'s'}`:'No results'):msg}</div>
    {!shown&&msg&&<small className="ps-msg" data-page-search-msg>{msg}</small>}
  </div>
}
