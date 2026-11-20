// CF-247 S1-UX s827 (Platform Admin 20 Nov 2026 10:31, 10:46 and 11:24): the contextual ? help drawer. A ? on each main screen header (Dashboard, Platform
// Health, Layer 4 Review, Catalogue) opens a slide-over with that screen's three steps, who may do what, and a link to
// the full section in Guides › Platform guide (#platform-guide). The text lives in src/lib/ops-pulse.js (HELP_GUIDES) and is reviewed with the guide
// each release. No server read.
import React,{useEffect,useRef,useState}from'react'
import{X}from'lucide-react'
import{helpFor}from'./lib/ops-pulse.js'
import'./ops-pulse.css'

export function HelpDrawer({topic,onClose}){
  const g=helpFor(topic),close=useRef(null)
  useEffect(()=>{close.current?.focus();const k=e=>{if(e.key==='Escape')onClose?.()};window.addEventListener('keydown',k);return()=>window.removeEventListener('keydown',k)},[])
  return <div className="hd-layer" data-help-drawer={topic}>
    <button type="button" className="hd-scrim" aria-label="Close help" onClick={onClose}/>
    <aside className="hd-drawer" role="dialog" aria-modal="false" aria-labelledby={`hd-title-${topic}`}>
      <button ref={close} type="button" className="hd-close" onClick={onClose} data-help-close><X size={16}/> Close</button>
      <p className="hd-kicker">Help · {g.title}</p>
      <h2 id={`hd-title-${topic}`}>{g.what}</h2>
      <ol className="hd-steps" data-help-steps={g.steps.length}>{g.steps.map((s,i)=><li key={i}><span className="hd-num" aria-hidden="true">{i+1}</span><span>{s}</span></li>)}</ol>
      <p className="hd-who" data-help-who>{g.who}</p>
      <p className="hd-more"><a href={g.guide} data-help-guide onClick={onClose}>Open the full Platform guide</a></p>
    </aside>
  </div>
}

export default function HelpButton({topic='dashboard',label}){
  const[open,setOpen]=useState(false),g=helpFor(topic)
  return <>
    <button type="button" className={`hd-btn${open?' on':''}`} aria-label={label||`Help: ${g.title}`} aria-expanded={open} onClick={()=>setOpen(v=>!v)} data-help-open={topic}>?</button>
    {open&&<HelpDrawer topic={topic} onClose={()=>setOpen(false)}/>}
  </>
}
