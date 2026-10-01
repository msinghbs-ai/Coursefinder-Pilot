// Scholarship publishing (v2.15.110): what is published on the website, what is ready to publish and why the rest is
// not. A Platform Admin can publish the ready list as one batch (an approval note is required, and the batch only goes
// ahead if the list has not changed since it was shown: Decision 139), hold a scholarship (takes it off the website and
// keeps it off future batches, with a reason) and release a hold. Every change is logged; each batch keeps a
// before-and-after snapshot of the website API.
// Read: public.admin_scholarship_publishing_read(); write: public.admin_scholarship_publishing(action, args)
// (migration 20260930050000_cf247_ui_control_sweep).
// Decision 212 (v2.15.139): Domestic only lists scholarships whose provider page names domestic students only; they are
// not published until a Platform Admin confirms that international students can apply (action confirm_international).
import React,{useEffect,useState}from'react'
import{Globe,Lock,RefreshCw,Send,Unlock}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,Metric,SectionTitle,fmtDateTime,fmtNumber}from'./ui-kit'

const REASON={'no stated award value':'No award value on the page','no provider page':'No page on the provider website','no linked course':'Not linked to a course',
  'held after hand-check':'Held after a hand check','provider page limits it to citizens and residents':'For citizens and residents only',
  'provider page does not mention international students':'Page does not mention international students','course link broader than the scholarship':'Linked to more courses than it covers',
  'not currently offered (provider page)':'Not currently offered','eligibility lists domestic students only':'Eligibility lists domestic students only'}
// v2.15.131 (pub-reasons-dead): where each reason is fixed.
const FIX_AT={'no stated award value':['#scholarships','Scholarships › Edit in list'],'no provider page':['#scholarships','Scholarships › Edit in list'],'no linked course':['#scholarships?tab=links','Course links'],'course link broader than the scholarship':['#scholarships?tab=links','Course links']}
const ACTION={publish_batch:'Batch published',hold:'Held',release:'Hold released',withdraw:'Withdrawn',confirm_international:'International students confirmed'}

export default function ScholarshipPublishing({onError}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(false),[failed,setFailed]=useState(''),[view,setView]=useState('eligible'),[note,setNote]=useState(''),[q,setQ]=useState('')
  const load=async()=>{setBusy(true);setFailed('');try{const{data:d,error}=await supabase.rpc('admin_scholarship_publishing_read');if(error)throw error;setData(d||{})}catch(e){setFailed(e.message||String(e))}finally{setBusy(false)}}
  const act=async(action,args,confirmText)=>{if(confirmText&&!window.confirm(confirmText))return;setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_scholarship_publishing',{p_action:action,p_args:args});if(error)throw error;setData(d||{});if(action==='publish_batch')setNote('')}catch(e){onError?.(e.message||String(e))}finally{setBusy(false)}}
  // Decision 212: a domestic-only reading that is wrong is corrected by a Platform Admin, with a note
  const confirmIntl=s=>{const r=window.prompt(`International students can apply to "${s.name}"? Note what the provider page says (required).`);if(r&&r.trim())act('confirm_international',{id:s.id,note:r.trim()})}
  const hold=s=>{const r=window.prompt(`Why hold "${s.name}"? It will be taken off the website and kept off future batches.`);if(r&&r.trim())act('hold',{id:s.id,reason:r.trim()})}
  useEffect(()=>{load()},[])
  if(!data&&!failed)return <section className="m-panel"><Loading label="Loading publishing…"/></section>
  if(failed&&!data)return <section className="m-panel"><Empty text={`Publishing could not be loaded: ${failed}`}/><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></section>
  const c=data.counts||{},can=Boolean(data.can_control)&&!busy,list=(data[view]||[]).filter(s=>!q||`${s.name} ${s.provider}`.toLowerCase().includes(q.toLowerCase()))
  const reasons=Object.entries(data.not_publishable_reasons||{}).sort((a,b)=>b[1]-a[1])
  return <>
    <div className="cf-metric-grid">
      <Metric label="Published on the website" value={fmtNumber(c.published||0)} detail={`of ${fmtNumber(c.active||0)} active scholarships`} icon={Globe} tone="success"/>
      <Metric label="Ready to publish" value={fmtNumber(c.eligible||0)} detail="Pass every publishing check" icon={Send} tone={Number(c.eligible)?'warning':'neutral'}/>
      <Metric label="Held" value={fmtNumber(c.held||0)} detail="Kept off the website" icon={Lock}/>
    </div>
    {data.can_control&&<section className="m-panel">
      <SectionTitle icon={Send} title="Publish the ready list" subtitle={`Publishes all ${fmtNumber(c.eligible||0)} ready scholarships in one batch. If the list changes before you publish, nothing is published and you are asked to refresh.`}/>
      <form className="sp-publish" onSubmit={e=>{e.preventDefault();act('publish_batch',{approval:note.trim(),expected:Number(c.eligible||0)},`Publish ${fmtNumber(c.eligible||0)} scholarships to the website?`)}}>
        <label><small>Approval note</small><input value={note} onChange={e=>setNote(e.target.value)} placeholder="Who approved this and why" disabled={!can} aria-label="Approval note"/></label>
        <Button type="submit" variant="primary" disabled={!can||!note.trim()||!Number(c.eligible)}><Send size={14}/>Publish {fmtNumber(c.eligible||0)}</Button>
      </form>
    </section>}
    <section className="m-panel">
      <SectionTitle icon={Globe} title="Scholarships" action={<div className="l3c-actions">
        <select className="fv-filter" value={view} onChange={e=>setView(e.target.value)} aria-label="Show">
          <option value="eligible">Ready to publish ({fmtNumber(c.eligible||0)})</option><option value="published">Published ({fmtNumber(c.published||0)})</option><option value="held">Held ({fmtNumber(c.held||0)})</option><option value="domestic_only">Domestic only ({fmtNumber(c.domestic_only||0)})</option></select>
        <input className="au-search" type="search" placeholder="Find" value={q} onChange={e=>setQ(e.target.value)} aria-label="Find a scholarship"/>
        <Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Updating…':'Refresh'}</Button></div>}/>
      {!data.can_control&&<p className="l3v-note">You can view publishing. Only a Platform Admin can publish or hold.</p>}
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Scholarship</th><th>Provider</th>{view==='eligible'&&<><th>Value</th><th className="num">Courses</th></>}{view==='held'&&<th>Reason</th>}{view==='domestic_only'&&<th>What the page says</th>}{data.can_control&&<th>Action</th>}</tr></thead><tbody>
        {list.length?list.map(s=><tr key={s.id}>
          <td><strong>{s.name}</strong>{s.page&&<a className="l3v-code" href={s.page} target="_blank" rel="noreferrer">Open the page</a>}{view==='held'&&<span className="l3v-code">{fmtDateTime(s.at)}</span>}</td>
          <td>{s.provider||'—'}</td>
          {view==='eligible'&&<><td>{s.value||'—'}</td><td className="num">{fmtNumber(s.courses||0)}</td></>}
          {view==='held'&&<td>{s.reason}</td>}
          {view==='domestic_only'&&<td data-domestic-words>{s.words?`“${s.words}”`:'—'}{s.published&&<span className="l3v-code">Published: taken off at the next daily review</span>}</td>}
          {data.can_control&&<td>{view==='domestic_only'?<Button compact onClick={()=>confirmIntl(s)} disabled={!can} aria-label={`International students can apply to ${s.name}`}><Globe size={14}/>International students can apply</Button>
            :view==='held'?<Button compact onClick={()=>act('release',{id:s.id},`Release the hold on "${s.name}"? It can be published in the next batch if it passes the checks.`)} disabled={!can} aria-label={`Release ${s.name}`}><Unlock size={14}/>Release</Button>
            :<Button compact onClick={()=>hold(s)} disabled={!can} aria-label={`Hold ${s.name}`}><Lock size={14}/>Hold</Button>}</td>}
        </tr>):<tr><td colSpan={6} className="cf-empty-cell">None.</td></tr>}
      </tbody></table></div>
    </section>
    <section className="m-panel">
      <SectionTitle title="Why the others are not published" subtitle="Active scholarships that fail a publishing check. One scholarship can fail more than one."/>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Reason</th><th className="num">Scholarships</th></tr></thead><tbody>
        {reasons.length?reasons.map(([k,v])=><tr key={k} data-reason={k}><td>{REASON[k]||k}{FIX_AT[k]&&<a className="sp-fix" href={FIX_AT[k][0]}>Fix on {FIX_AT[k][1]}</a>}</td><td className="num">{fmtNumber(v)}</td></tr>):<tr><td colSpan={2} className="cf-empty-cell">None.</td></tr>}
      </tbody></table></div>
    </section>
    {(data.events||[]).length>0&&<section className="m-panel"><SectionTitle title="Recent changes"/>
      <ul className="l3c-events">{data.events.map((e,i)=><li key={i}><span>{fmtDateTime(e.at)}</span><strong>{ACTION[e.action]||e.action}</strong><small>{[e.detail?.result?.published!=null&&`${fmtNumber(e.detail.result.published)} published`,e.detail?.reason,e.detail?.approval].filter(Boolean).join(' · ')}</small></li>)}</ul></section>}
  </>
}
