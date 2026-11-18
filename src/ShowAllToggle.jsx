// CF-247 s697 (Platform Admin 18 Nov 2026 23:02): a long list shows its first few items, then "Show all (N) <noun>" / "Show less",
// instead of a cramped box that scrolls inside the drawer. Used by the scholarship lists in the Course and Provider detail.
import React,{useState}from'react'
export const SHOW_FIRST=3 // fixed: presentation only (first three, as the Platform Admin set)
export function useShowAll(items,{first=SHOW_FIRST,noun='scholarships',id='list'}={}){
  const[all,setAll]=useState(false)
  const list=Array.isArray(items)?items:[],more=list.length>first
  const shown=all||!more?list:list.slice(0,first)
  const toggle=more?<button type="button" className="m-secondary compact show-all-toggle" aria-expanded={all} data-show-all={id} onClick={()=>setAll(x=>!x)}>
    {all?'Show less':`Show all (${list.length}) ${noun}`}</button>:null
  return{shown,toggle,all,more}
}
