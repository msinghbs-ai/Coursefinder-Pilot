// Layer 4 › Inbox › Grid › Clusters (v2.16.43, Platform Admin 18 Nov 2026 19:20: "grouping held items by (queue_kind, provider_id,
// refusal_reason, normalized_quote) so any future recurring clusters can be inspected or settled in one click alongside the automated Boost
// rules"). Reads the Inbox's own pages (public.admin_layer4_inbox 'items', and 'detail' for a kind with a hook), page by page as the person
// asks, and groups them in the browser (src/lib/layer4-clusters.js). Settling a cluster decides each item through the Inbox's own decision
// ('decide'), exactly as its card would, at the rank that item needs and with the hook's own allowed actions; nothing is decided on the
// server in bulk and no rule changes. A recurring cluster is the evidence for a Boost or reader rule (Platform Admin 18 Nov 2026 19:20,
// closed-loop promotion): the export names it so it can be codified with a test, not settled again and again.
import React,{useEffect,useMemo,useState}from'react'
import{supabase}from'./lib/supabase'
import{Button,EmptyInline,fmtNumber}from'./ui-kit'
import{NEVER_SETTLE,clusterItems,confirmPhrase,settleChoices}from'./lib/layer4-clusters'

const rpc=async(action,args)=>{const{data,error}=await supabase.rpc('admin_layer4_inbox',{p_action:action,p_args:args||{}});if(error)throw new Error(error.message);return data||{}}

export default function Layer4Clusters({kinds,rank,onDecided}){
  const kindList=useMemo(()=>Object.entries(kinds||{}).sort((a,b)=>Number(a[1]?.order||0)-Number(b[1]?.order||0)),[kinds])
  const[kind,setKind]=useState(''),[items,setItems]=useState([]),[hooks,setHooks]=useState({}),[page,setPage]=useState(null),[busy,setBusy]=useState(false),[err,setErr]=useState(''),[note,setNote]=useState('')
  const[open,setOpen]=useState(''),[pick,setPick]=useState([]),[choice,setChoice]=useState(''),[reason,setReason]=useState(''),[confirm,setConfirm]=useState('')
  const k=kinds?.[kind],hooked=!!(k&&k.detail===true&&(k.hook||k.extension))
  const scan=async(after)=>{if(!kind)return;setBusy(true);setErr('')
    try{const d=await rpc('items',{kind,...(after||{})});const got=d.items||[]
      let h={};if(hooked&&got.length){const dd=await rpc('detail',{items:got.map(i=>({kind:i.kind,ref:i.ref}))});for(const x of dd.items||[])h[`${x.kind}:${x.ref}`]=x.hook_detail||{}}
      setItems(p=>after?[...p,...got]:got);setHooks(p=>after?{...p,...h}:h);setPage({total:Number(d.total||0),more:!!d.more,last:got[got.length-1]||null})}
    catch(e){setErr(e.message)}setBusy(false)}
  useEffect(()=>{setItems([]);setHooks({});setPage(null);setPick([]);setOpen('');setNote('');setConfirm('');const c=settleChoices(kind,kinds?.[kind],rank);setChoice(c[0]?.key||'');if(kind)scan()},[kind])
  const clusters=useMemo(()=>clusterItems(items,hooks),[items,hooks])
  const choices=settleChoices(kind,k,rank),chosen=clusters.filter(c=>pick.includes(c.key)),total=chosen.reduce((n,c)=>n+c.items.length,0),phrase=confirmPhrase(choice,total)
  const next=()=>{const l=page?.last;if(l)scan({after_o:l.o,after_at:l.created_at,after_kind:l.kind,after_ref:l.ref})}
  const settle=async()=>{setBusy(true);setErr('');let ok=0,skipped=0,bad=0;const lines=[]
    for(const c of chosen)for(const it of c.items){
      const h=hooks[`${it.kind}:${it.ref}`],acts=Array.isArray(h?.actions)?Object.fromEntries(h.actions.map(a=>[a.key,a.allowed===true])):null
      if(hooked&&acts&&acts[choice]!==true){skipped++;continue}
      try{const r=await rpc('decide',{kind:it.kind,ref:it.ref,choice,reason:reason.trim()});if(r&&r.ok===false){bad++;lines.push(`${it.subject||it.ref}: ${r.request||'more is needed'}`)}else ok++}
      catch(e){bad++;lines.push(`${it.subject||it.ref}: ${e.message}`)}}
    setBusy(false);setConfirm('');setPick([])
    setNote(`${fmtNumber(ok)} decided${skipped?`, ${fmtNumber(skipped)} skipped (this choice is not open on them)`:''}${bad?`, ${fmtNumber(bad)} not decided`:''}.${lines.length?' '+lines.slice(0,5).join(' · '):''}`)
    onDecided?.();scan()}
  const csv=()=>{const rows=[['kind','university','items','reason','quote'],...clusters.map(c=>[c.kind,c.provider,c.items.length,c.why,c.quote])]
    const blob=new Blob([rows.map(r=>r.map(v=>{const s=String(v??'');return/[",\n\r]/.test(s)?`"${s.replace(/"/g,'""')}"`:s}).join(',')).join('\r\n')],{type:'text/csv;charset=utf-8'})
    const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=`layer4-clusters-${kind}.csv`;a.click();URL.revokeObjectURL(a.href)}
  return <section className="l4g-groups l4c" data-l4c>
    <p className="l4g-help">Items of one kind that share a university, a reason and the same quote (numbers, spacing and links ignored). Inspect a cluster, or settle the clusters you tick with one choice and one reason: each item is decided exactly as on its own card, at the rank it needs, and logged. A cluster that keeps coming back is the case for a Boost or reader rule: export it so the rule can be written and tested.</p>
    <div className="l4g-bar">
      <label>Kind<select value={kind} onChange={e=>setKind(e.target.value)} data-l4c-kind><option value="">Choose…</option>{kindList.map(([key,x])=><option key={key} value={key}>{x?.label||key}</option>)}</select></label>
      {kind&&choices.length>0&&<><label>Choice<select value={choice} onChange={e=>setChoice(e.target.value)} data-l4c-choice>{choices.map(c=><option key={c.key} value={c.key}>{c.label||c.key}</option>)}</select></label>
        <label>Reason<input value={reason} onChange={e=>setReason(e.target.value)} maxLength={300} placeholder="Kept with every decision (8 characters or more)" data-l4c-reason/></label></>}
      <div className="l4g-actions">{page?.more&&<Button compact onClick={next} disabled={busy} data-l4c-more>Scan the next page</Button>}{clusters.length>0&&<Button compact onClick={csv} data-l4c-export>Export clusters</Button>}</div>
    </div>
    {kind&&NEVER_SETTLE.includes(kind)&&<p className="l4g-note" data-l4c-inspect-only>{k?.label||kind}: inspect only. These items are decided one at a time on their own cards.</p>}
    {kind&&!NEVER_SETTLE.includes(kind)&&!choices.length&&<p className="l4g-note" data-l4c-no-choice>No choice of this kind can be taken on a whole cluster (each needs a value or a page, or a higher role).</p>}
    {err&&<p className="l4g-err" role="alert">{err}</p>}
    {note&&<p className="l4g-note" role="status" data-l4c-note>{note}</p>}
    {!kind?<EmptyInline text="Choose a kind to group its waiting items."/>:busy&&!page?<EmptyInline text="Reading the waiting items…"/>:<>
      <p className="l4g-muted" data-l4c-scanned>{fmtNumber(items.length)} of {fmtNumber(page?.total||0)} waiting items read; {fmtNumber(clusters.length)} cluster{clusters.length===1?'':'s'} of two or more.</p>
      {!clusters.length?<EmptyInline text="No two waiting items share a university, a reason and a quote in what has been read."/>:<div className="cf-table-wrap"><table className="cf-table" data-l4c-table><thead><tr><th></th><th>Items</th><th>University</th><th>Reason</th><th>Quote</th></tr></thead><tbody>
        {clusters.map(c=><React.Fragment key={c.key}><tr data-l4c-cluster={c.items.length}>
          <td>{choices.length>0&&<input type="checkbox" aria-label={`Choose ${c.provider} cluster`} checked={pick.includes(c.key)} onChange={e=>setPick(p=>e.target.checked?[...p,c.key]:p.filter(x=>x!==c.key))} data-l4c-pick/>}</td>
          <td><button type="button" className="cf-link" onClick={()=>setOpen(open===c.key?'':c.key)} aria-expanded={open===c.key} data-l4c-open>{fmtNumber(c.items.length)}</button></td>
          <td>{c.provider||'—'}</td><td>{c.why}</td><td>{c.quote?<q>{c.quote.length>200?c.quote.slice(0,200)+'…':c.quote}</q>:<small className="l4g-muted">No quote</small>}</td></tr>
          {open===c.key&&<tr data-l4c-items><td></td><td colSpan={4}><ul className="l4c-items">{c.items.map(it=><li key={it.ref}>{it.subject||it.ref}</li>)}</ul></td></tr>}</React.Fragment>)}
      </tbody></table></div>}
      {chosen.length>0&&<div className="l4g-confirm" data-l4c-confirm>
        <p>Settle {fmtNumber(chosen.length)} cluster{chosen.length===1?'':'s'} ({fmtNumber(total)} items) as <b>{choices.find(c=>c.key===choice)?.label||choice}</b>. Type <code>{phrase}</code> to confirm.</p>
        <input value={confirm} onChange={e=>setConfirm(e.target.value)} aria-label="Type the confirmation" data-l4c-confirm-input/>
        <Button compact disabled={busy||confirm!==phrase||reason.trim().length<8} onClick={settle} data-l4c-settle>Settle {fmtNumber(total)} items</Button></div>}
    </>}
  </section>
}
