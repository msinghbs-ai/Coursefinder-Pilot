// Shared accessible overlay (CF-247, Platform Admin mandate 29 Oct 2026 12:23, A1 and A5): one primitive for side drawers and the
// full-height evidence panel. It is a labelled dialog (role="dialog", aria-modal); on open the focus moves into it and on close it
// returns to the control that opened it; Escape and the close button close it (Escape is kept from reaching a drawer underneath);
// Tab stays inside; the page behind does not scroll while it is open; its body scrolls on its own. At phone width the panel fills the
// screen (overlay.css). Consumers: the Entry requirements row drawer (AerWorkspace.jsx) and the course evidence overlay (CourseAudit.jsx).
import React,{useId,useLayoutEffect,useRef}from'react'
import{X}from'lucide-react'
import'./overlay.css'

const FOCUSABLE='a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),summary,[tabindex]:not([tabindex="-1"])'
let locks=0,saved=''
function lockScroll(){if(locks++===0){saved=document.body.style.overflow;document.body.style.overflow='hidden';document.body.dataset.overlayOpen='true'}}
function unlockScroll(){if(--locks<=0){locks=0;document.body.style.overflow=saved;delete document.body.dataset.overlayOpen}}

// variant: 'drawer' (right-hand side, the m-drawer look) or 'panel' (wide, full height). Extra props (data-*) go on the dialog.
export function Overlay({open=true,onClose,title,eyebrow,variant='drawer',className='',closeLabel='Close',head=null,bodyClassName='',children,...rest}){
  const ref=useRef(null),opener=useRef(null),titleId=useId()
  useLayoutEffect(()=>{if(!open)return;opener.current=document.activeElement;lockScroll()
    const el=ref.current,first=el?.querySelector('[data-overlay-close]')||el;first?.focus({preventScroll:true})
    // focus that wanders outside (a click on the page behind) comes back in; another overlay on top keeps its own
    const onFocus=e=>{if(el&&el.isConnected&&!el.contains(e.target)&&!e.target.closest?.('[data-overlay]'))el.focus({preventScroll:true})}
    document.addEventListener('focusin',onFocus)
    // the guard goes first, so giving the focus back to the opener is not pulled into the closing dialog
    return()=>{document.removeEventListener('focusin',onFocus);unlockScroll();const o=opener.current;if(o&&o.isConnected&&typeof o.focus==='function')o.focus({preventScroll:true})}},[open])
  if(!open)return null
  const key=e=>{
    if(e.key==='Escape'){e.stopPropagation();e.nativeEvent?.stopImmediatePropagation?.();onClose?.();return}
    if(e.key!=='Tab')return
    const items=[...ref.current.querySelectorAll(FOCUSABLE)].filter(x=>x.offsetParent!==null||x===document.activeElement)
    if(!items.length){e.preventDefault();return}
    const a=items[0],z=items[items.length-1]
    if(e.shiftKey&&(document.activeElement===a||document.activeElement===ref.current)){e.preventDefault();z.focus()}
    else if(!e.shiftKey&&document.activeElement===z){e.preventDefault();a.focus()}
  }
  return <>
    <div className={`cf-overlay-backdrop${variant==='panel'?' is-panel':''}`} onClick={onClose} aria-hidden="true" data-overlay-backdrop/>
    <section ref={ref} role="dialog" aria-modal="true" aria-labelledby={titleId} tabIndex={-1} onKeyDown={key} data-overlay={variant}
      className={`${variant==='drawer'?'m-drawer ':''}cf-overlay cf-overlay-${variant}${className?' '+className:''}`} {...rest}>
      <div className="m-drawer-head cf-overlay-head"><div className="cf-overlay-title">{eyebrow&&<small>{eyebrow}</small>}<h2 id={titleId}>{title}</h2></div>
        <div className="cf-overlay-actions">{head}<button type="button" onClick={onClose} aria-label={closeLabel} data-overlay-close><X size={18}/></button></div></div>
      <div className={`m-drawer-body cf-overlay-body${bodyClassName?' '+bodyClassName:''}`}>{children}</div>
    </section>
  </>
}
