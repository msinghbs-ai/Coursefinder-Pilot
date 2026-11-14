// v2.15.200 (CF-247 Decision 254, Platform Admin 6 Oct 15:25: "All Card should be collapsed if not expanded, default is
// collapse, card expansion is remembered through session"; 15:31 "Per browser session"). A card shows its title line
// only until it is opened. Whether it is open is remembered for this browser tab's session (sessionStorage), per screen
// and card, so moving between screens keeps it and closing the tab forgets it. Its body is drawn only while it is open,
// so a closed card reads nothing from the database.
import React,{useState}from'react'
import{ChevronRight}from'lucide-react'

const KEY='cf.card.'
export function cardOpen(id){try{return window.sessionStorage.getItem(KEY+id)==='1'}catch{return false}}
// A card that starts open (defaultOpen) remembers being closed as '0'; every other card keeps no entry while closed, as before.
function stored(id){try{return window.sessionStorage.getItem(KEY+id)}catch{return null}}
function remember(id,open,initial=false){try{if(open)window.sessionStorage.setItem(KEY+id,'1');else if(initial)window.sessionStorage.setItem(KEY+id,'0');else window.sessionStorage.removeItem(KEY+id)}catch{}}

export function rememberOpen(id){remember(id,true)}

export function useCardOpen(id,initial=false){
  const[open,setOpen]=useState(()=>{const v=id?stored(id):null;return v==='1'?true:v==='0'?false:initial})
  const set=v=>{const next=typeof v==='function'?v(open):v;setOpen(next);if(id)remember(id,next,initial)}
  return[open,set]
}

// id: unique per screen and card, for example 'services.ai-models'. title, subtitle: the heading. meta: a short line or
// chips shown on the closed card (counts, state). action: buttons kept in the heading (shown when open). Other props
// (data-*) go on the section.
// defaultOpen: only for a page the Platform Admin has said opens expanded (Models & services › AI on desktop, 13 Nov 2026 22:10); every other card starts closed.
export default function Card({id,title,subtitle,meta,action,icon:Icon,children,className='',level=3,defaultOpen=false,...rest}){
  const[open,setOpen]=useCardOpen(id,defaultOpen)
  const H=level===2?'h2':'h3'
  return <section className={`m-panel cf-card${open?' is-open':''}${className?' '+className:''}`} data-card={id} data-card-open={open?'true':'false'} {...rest}>
    <div className="cf-card-head">
      <button type="button" className="cf-card-toggle" aria-expanded={open} onClick={()=>setOpen(!open)}>
        <ChevronRight size={16} className="cf-card-chev" aria-hidden/>
        {Icon&&<Icon size={16} aria-hidden/>}
        <span className="cf-card-titles"><H className="cf-card-title">{title}</H>{subtitle&&open&&<small className="cf-card-sub">{subtitle}</small>}</span>
      </button>
      {meta&&<span className="cf-card-meta">{meta}</span>}
      {open&&action&&<span className="cf-card-action">{action}</span>}
    </div>
    {open&&<div className="cf-card-body">{children}</div>}
  </section>
}
