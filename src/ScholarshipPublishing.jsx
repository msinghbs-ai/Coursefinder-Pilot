// Scholarship publishing (v2.15.110): what is published on the website, what is ready to publish and why the rest is
// not. A Platform Admin can publish the ready list as one batch (an approval note is required, and the batch only goes
// ahead if the list has not changed since it was shown: Decision 139), hold a scholarship (takes it off the website and
// keeps it off future batches, with a reason) and release a hold. Every change is logged; each batch keeps a
// before-and-after snapshot of the website API.
// Read: public.admin_scholarship_publishing_read(); write: public.admin_scholarship_publishing(action, args)
// (migration 20260930050000_cf247_ui_control_sweep).
// Decision 212 (v2.15.139): Domestic only lists scholarships whose provider page names domestic students only; they are
// not published until a Platform Admin confirms that international students can apply (action confirm_international).
// v2.15.171 (Platform Admin, 3 Oct 2026 23:30: follow the mockup): four tiles (published, ready, held, published but now
// failing a check), and the reasons as a list with what each one means and who fixes it beside it.
import React,{useEffect,useState}from'react'
import{AlertTriangle,Globe,Lock,RefreshCw,Send,Unlock}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,Metric,SectionTitle,fmtDateTime,fmtNumber}from'./ui-kit'

const REASON={'no stated award value':'No award value on the page','no provider page':'No page on the provider website','no linked course':'Not linked to a course',
  'held after hand-check':'Held after a hand check','provider page limits it to citizens and residents':'For citizens and residents only',
  'provider page does not mention international students':'Page does not mention international students','course link broader than the scholarship':'Linked to more courses than it covers',
  'not currently offered (provider page)':'Not currently offered','eligibility lists domestic students only':'Eligibility lists domestic students only',
  'not for international students':'Not for international students'}
// v2.15.171 (mockup): what each reason means and who fixes it, shown beside the reasons list.
const EXPLAIN={
  'not for international students':['The page wording reads as domestic only, or names nobody (Decision 244).','Not stated: open the scholarship and set who it is for from its page. Domestic only stays held.'],
  'no stated award value':['The page states no amount or percentage that could be taken as the value.','A Curator enters the value as the page states it, from the scholarship record; otherwise it stays held.'],
  'eligibility lists domestic students only':['The eligibility section names Australian citizens or residents only.','A Platform Admin can record that international students can apply, with a note (Show › Domestic only).'],
  'provider page limits it to citizens and residents':['The page restricts it to citizens and permanent residents.','Stays held unless the page says otherwise.'],
  'no provider page':['No page of the provider’s own was found for it.','A Curator adds the page address in the scholarship record; the reader then reads it.'],
  'no linked course':['It applies to no course in CourseFinder yet.','Course links: decide which courses it applies to.'],
  'held after hand-check':['A person held it after checking.','Release it here (Show › Held after a hand check) when it is fixed.'],
  'provider page does not mention international students':['The page never mentions international students.','A Curator decides from the page and sets who it is for in the scholarship record.'],
  'course link broader than the scholarship':['It is linked to more courses than its page names.','Course links: narrow it to the courses the page names.'],
  'not currently offered (provider page)':['The page says it is not currently offered.','Stays held until the page offers it again.'],
}
// v2.15.131 (pub-reasons-dead): where each reason is fixed.
const FIX_AT={'no stated award value':['#scholarships','Scholarships › Edit in list'],'no provider page':['#scholarships','Scholarships › Edit in list'],'no linked course':['#scholarships?tab=links','Course links'],'course link broader than the scholarship':['#scholarships?tab=links','Course links']}
const ACTION={publish_batch:'Batch published',hold:'Held',release:'Hold released',withdraw:'Withdrawn',confirm_international:'International students confirmed'}

export default function ScholarshipPublishing({onError}){
  const[pick,setPick]=useState(''),[data,setData]=useState(null),[busy,setBusy]=useState(false),[failed,setFailed]=useState(''),[view,setView]=useState('eligible'),[note,setNote]=useState(''),[q,setQ]=useState('')
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
  const sel=reasons.find(([k])=>k===pick)||reasons[0],[what,who]=sel?(EXPLAIN[sel[0]]||['',''] ):['','']
  // v2.15.171 (mockup): Held is every active scholarship that is neither published nor ready (the list's Held pill)
  const notOut=Math.max(0,Number(c.active||0)-Number(c.published||0)-Number(c.eligible||0))
  return <>
    <div className="cf-metric-grid sp-tiles">
      <Metric label="Published" value={fmtNumber(c.published||0)} detail="On the website and in Zoho" icon={Globe} tone="success"/>
      <Metric label="Ready to publish" value={fmtNumber(c.eligible||0)} detail="International, or international and domestic; pass every check" icon={Send} tone={Number(c.eligible)?'warning':'neutral'}/>
      <Metric label="Held" value={fmtNumber(notOut)} detail="Kept off; reasons below" icon={Lock}/>
      <Metric label="Published but now failing a check" value={fmtNumber(c.published_failing||0)} detail="Taken off at the daily review (06:17)" icon={AlertTriangle} tone={Number(c.published_failing)?'danger':'neutral'}/>
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
          <option value="eligible">Ready to publish ({fmtNumber(c.eligible||0)})</option><option value="published">Published ({fmtNumber(c.published||0)})</option><option value="published_failing">Published but now failing a check ({fmtNumber(c.published_failing||0)})</option><option value="held">Held after a hand check ({fmtNumber(c.held||0)})</option><option value="domestic_only">Domestic only ({fmtNumber(c.domestic_only||0)})</option></select>
        <input className="au-search" type="search" placeholder="Find" value={q} onChange={e=>setQ(e.target.value)} aria-label="Find a scholarship"/>
        <Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Updating…':'Refresh'}</Button></div>}/>
      {!data.can_control&&<p className="l3v-note">You can view publishing. Only a Platform Admin can publish or hold.</p>}
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Scholarship</th><th>Provider</th>{view==='eligible'&&<><th>Value</th><th className="num">Courses</th></>}{['held','published_failing'].includes(view)&&<th>Reason</th>}{view==='domestic_only'&&<th>What the page says</th>}{data.can_control&&<th>Action</th>}</tr></thead><tbody>
        {list.length?list.map(s=><tr key={s.id}>
          <td><strong>{s.name}</strong>{s.page&&<a className="l3v-code" href={s.page} target="_blank" rel="noreferrer">Open the page</a>}{view==='held'&&<span className="l3v-code">{fmtDateTime(s.at)}</span>}</td>
          <td>{s.provider||'—'}</td>
          {view==='eligible'&&<><td>{s.value||'—'}</td><td className="num">{fmtNumber(s.courses||0)}</td></>}
          {['held','published_failing'].includes(view)&&<td>{view==='published_failing'?String(s.reason||'').split('; ').map(x=>REASON[x]||x).join('; '):s.reason}</td>}
          {view==='domestic_only'&&<td data-domestic-words>{s.words?`“${s.words}”`:'—'}{s.published&&<span className="l3v-code">Published: taken off at the next daily review</span>}</td>}
          {data.can_control&&<td>{view==='domestic_only'?<Button compact onClick={()=>confirmIntl(s)} disabled={!can} aria-label={`International students can apply to ${s.name}`}><Globe size={14}/>International students can apply</Button>
            :view==='held'?<Button compact onClick={()=>act('release',{id:s.id},`Release the hold on "${s.name}"? It can be published in the next batch if it passes the checks.`)} disabled={!can} aria-label={`Release ${s.name}`}><Unlock size={14}/>Release</Button>
            :<Button compact onClick={()=>hold(s)} disabled={!can} aria-label={`Hold ${s.name}`}><Lock size={14}/>Hold</Button>}</td>}
        </tr>):<tr><td colSpan={6} className="cf-empty-cell">None.</td></tr>}
      </tbody></table></div>
    </section>
    <div className="sp-why" data-publishing-reasons>
      <section className="m-panel sp-why-list">
        <SectionTitle title="Why scholarships are held" subtitle="A scholarship can be held for more than one reason."/>
        {reasons.length?reasons.map(([k,v])=><button key={k} type="button" data-reason={k} className={`sp-reason${sel&&sel[0]===k?' on':''}`} aria-pressed={Boolean(sel&&sel[0]===k)} onClick={()=>setPick(k)}><span>{REASON[k]||k}</span><b>{fmtNumber(v)}</b></button>):<Empty text="None."/>}
      </section>
      {sel&&<section className="m-panel sp-why-detail" data-reason-detail>
        <small>{REASON[sel[0]]||sel[0]} · {fmtNumber(sel[1])}</small>
        {what&&<p>{what}</p>}{who&&<p className="sp-who">{who}</p>}
        {FIX_AT[sel[0]]&&<a className="sp-fix" href={FIX_AT[sel[0]][0]}>Fix on {FIX_AT[sel[0]][1]}</a>}
      </section>}
    </div>
    {(data.events||[]).length>0&&<section className="m-panel"><SectionTitle title="Recent changes"/>
      <ul className="l3c-events">{data.events.map((e,i)=><li key={i}><span>{fmtDateTime(e.at)}</span><strong>{ACTION[e.action]||e.action}</strong><small>{[e.detail?.result?.published!=null&&`${fmtNumber(e.detail.result.published)} published`,e.detail?.reason,e.detail?.approval].filter(Boolean).join(' · ')}</small></li>)}</ul></section>}
  </>
}
