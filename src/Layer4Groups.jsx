// CF-247 Layer 4 operational groups (Platform Admin mandate 4 Nov 2026 16:32 §2 and §7): the Inbox by what a person must do.
// Ready for my decision (C), Information needed from me (D) and Technical recovery (B), from public.admin_layer4_groups; group A (settled by an
// existing rule) is shown as counts with its rules only. Each group pages oldest first, in the Inbox's own cards (renderItem), so every card keeps
// its choices, its Progress block and its role checks. Detailed classes stay in each card's expandable sections.
import React,{useEffect,useState}from'react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,fmtNumber}from'./ui-kit'

const call=async args=>{const{data,error}=await supabase.rpc('admin_layer4_groups',{p_args:args||{}});if(error)throw new Error(error.message);return data||{}}
export const GROUPS=[['C','Ready for my decision','Evidence complete; your decision is needed'],['D','Information needed from me','A page, document, identity or value only a person can give'],
  ['B','Technical recovery','The platform is recovering it; nothing is needed from you yet']]

/** The three choices, with counts, and group A as counts and rules. onPick(group) opens a group. */
export function GroupBar({active,onPick,refresh}){
  const[s,setS]=useState(null)
  useEffect(()=>{call({action:'summary'}).then(setS).catch(()=>setS(null))},[refresh])
  if(!s||Array.isArray(s)||!s.groups)return null
  const a=Number(s.groups.A||0)
  return <div className="l4i-groups" data-l4-groups>
    <div className="l4i-view" role="group" aria-label="What is needed from me">
      {GROUPS.map(([g,l,h])=><button key={g} type="button" className={active===g?'on':''} aria-pressed={active===g} title={h} onClick={()=>onPick(g)} data-l4-group-pick={g}>{l} ({fmtNumber(Number(s.groups[g]||0))})</button>)}</div>
    {a>0&&<p className="l4i-why" data-l4-group-a><small>Settled by existing rules: {fmtNumber(a)} · {(s.rules||[]).map(r=>`${fmtNumber(r.n)} by ${r.rule||r.class}`).join(' · ')}</small></p>}
  </div>}

/** One group's items, paged oldest first; renderItem draws the Inbox card. */
export function GroupList({group,renderItem,refresh}){
  const[d,setD]=useState(null),[off,setOff]=useState(0),[err,setErr]=useState('')
  const load=o=>{setD(null);setErr('');call({action:'items',group,offset:o}).then(setD).catch(e=>setErr(e.message))}
  useEffect(()=>{setOff(0);load(0)},[group,refresh])
  if(err)return <p className="l4i-err" role="alert">{err}</p>
  if(!d)return <Loading compact/>
  const items=d.items||[],lim=Number(d.limit||25),t=Number(d.total||0),label=(GROUPS.find(x=>x[0]===group)||[])[1]
  return <section className="l4i-items" aria-label={label} data-l4-group-list={group}>
    <header className="l4i-items-head"><h3>{label}</h3><small data-l4-group-total>{fmtNumber(t)} waiting, oldest first</small></header>
    {items.length===0?<Empty text="Nothing waits here."/>:items.map(it=><React.Fragment key={`${it.kind}:${it.ref}`}>{renderItem(it)}</React.Fragment>)}
    {t>lim&&<div className="l4i-pager" data-l4-group-pager><Button compact disabled={off===0} onClick={()=>{const o=Math.max(0,off-lim);setOff(o);load(o)}}>Previous</Button>
      <small>{fmtNumber(off+1)}–{fmtNumber(off+items.length)} of {fmtNumber(t)}</small>
      <Button compact disabled={off+items.length>=t} onClick={()=>{const o=off+lim;setOff(o);load(o)}}>Next</Button></div>}
  </section>}

/** A choice that opens another screen is recorded before the screen opens (mandate 16:32 §8); a failure never blocks the navigation. */
export const recordNavigation=(kind,ref,choice)=>supabase.rpc('admin_layer4_navigate',{p_args:{kind,ref,choice}}).then(()=>{},()=>{})
