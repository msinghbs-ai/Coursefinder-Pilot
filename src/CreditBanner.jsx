// Credit and limit banner on every page (v2.15.253, Platform Admin 12 Oct 2026). Reads public.admin_credit_notices() once after sign-in
// and every five minutes (Curator and above; the function returns [] for anyone else): Firecrawl credits, OpenRouter credit, the adapter
// AI allowance and the scholarship scraper cap. Nothing shows when all is fine. Critical notices use the danger tone, warnings the warning
// tone. Text that does not fit scrolls sideways (or wraps when the viewer asks for reduced motion). × hides it until the page is reloaded
// (kept in memory only).
import React,{useEffect,useLayoutEffect,useRef,useState}from'react'
import{AlertTriangle,X}from'lucide-react'
import{supabase}from'./lib/supabase'

let dismissedThisSession=false
const reducedMotion=()=>{try{return window.matchMedia('(prefers-reduced-motion: reduce)').matches}catch{return false}}

export default function CreditBanner({rank=0,canOpenServices=false}){
  const[notes,setNotes]=useState([]),[hidden,setHidden]=useState(dismissedThisSession),[scroll,setScroll]=useState(false)
  const track=useRef(null),items=useRef(null)
  useEffect(()=>{if(rank<3){setNotes([]);return}let live=true
    const read=()=>supabase.rpc('admin_credit_notices').then(({data,error})=>{if(live&&!error)setNotes(Array.isArray(data)?data.filter(n=>n&&n.text):[])}).catch(()=>{})
    read();const t=setInterval(read,300000);return()=>{live=false;clearInterval(t)}},[rank])
  const key=notes.map(n=>`${n.level}|${n.tool}|${n.text}`).join('\n')
  // scroll only when the notices do not fit on one line, and never for reduced motion
  useLayoutEffect(()=>{setScroll(false)},[key])
  useLayoutEffect(()=>{if(scroll||!track.current||!items.current||reducedMotion())return;if(items.current.scrollWidth>track.current.clientWidth+2)setScroll(true)},[key,scroll])
  if(hidden||!notes.length)return null
  const level=notes.some(n=>n.level==='critical')?'critical':'warning'
  const list=copy=>notes.map((n,i)=><span key={`${copy}-${i}`} className={`cf-credit-notice is-${n.level==='critical'?'critical':'warning'}`} data-credit-notice={copy?undefined:(n.level||'warning')}><strong>{n.tool||'Limit'}:</strong> {n.text}</span>)
  return <div className={`cf-credit-banner tone-${level==='critical'?'danger':'warning'}${scroll?' is-scrolling':''}`} role="status" data-credit-banner={level}>
    <AlertTriangle size={14} aria-hidden="true"/>
    <div className="cf-credit-track" ref={track}><div className="cf-credit-items" ref={items} style={scroll?{'--cf-credit-seconds':`${Math.max(20,Math.round(key.length/6))}s`}:undefined}>{list('')}{scroll&&<span className="cf-credit-copy" aria-hidden="true">{list('copy')}</span>}</div></div>
    {canOpenServices&&<a className="cf-credit-link" href="#models-services">Models &amp; services</a>}
    <button type="button" className="cf-credit-close" aria-label="Hide the credit notices until the page is reloaded" title="Hide until the page is reloaded" onClick={()=>{dismissedThisSession=true;setHidden(true)}}><X size={14}/></button>
  </div>
}
