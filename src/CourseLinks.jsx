// Course links and who can apply (v2.15.133, Decisions 200–201). Every kind of course link — official course page,
// handbook entry, international students page, how to apply, admission centre listing, regulator listing — can be
// added, changed and removed by hand here. A link entered or removed by hand wins: automation (page search, portal
// harvest, link refresh) leaves that link type alone for the course until someone chooses "Let automation update this".
// "Who can apply" records whether the course is open to international and to domestic students; an English
// requirement is expected only where international students can apply.
// Read/write: public.admin_course_links_read / admin_course_link_edit / admin_course_applicants_edit
// (migration 20261001170000_cf247_course_links_and_applicants).
import React,{useEffect,useState}from'react'
import{Check,ExternalLink,Link2,Lock,Pencil,Plus,Trash2,Unlock,Users,X}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Loading,StatusChip,fmtDateTime}from'./ui-kit'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
export const CURRENCY_BY_COUNTRY={AU:'AUD',NZ:'NZD',CA:'CAD',GB:'GBP',US:'USD',IE:'EUR'}
const YES_NO=[['true','Yes'],['false','No'],['','Not known']]
const yn=v=>v===true?'Yes':v===false?'No':'Not known'
const STATUS={active:['Current','success'],unverified:['Not confirmed','warning'],inactive:['Removed','neutral'],deprecated:['Old','neutral']}

function LinkForm({types,initial,onSave,onCancel,busy}){
  const[v,setV]=useState({link_type:initial?.link_type||types[0]?.code||'official_course',url:initial?.url||'',label:initial?.label||''})
  const ok=/^https?:\/\/[^\s/]+\.[^\s]+$/i.test(v.url.trim())
  return <div className="cl-form" data-link-form>
    {!initial&&<select className="fv-input" value={v.link_type} onChange={e=>setV({...v,link_type:e.target.value})} aria-label="Link type">{types.map(t=><option key={t.code} value={t.code}>{t.label}</option>)}</select>}
    <input className="fv-input cl-url" type="url" value={v.url} onChange={e=>setV({...v,url:e.target.value})} placeholder="https://" aria-label="Web address" autoFocus/>
    <input className="fv-input" value={v.label} onChange={e=>setV({...v,label:e.target.value})} placeholder="Label (optional)" aria-label="Label"/>
    <div className="re-foot"><Button compact variant="primary" disabled={busy||!ok} onClick={()=>onSave({...v,url:v.url.trim()})}><Check size={13}/>{busy?'Saving…':'Save'}</Button><Button compact onClick={onCancel} disabled={busy}><X size={13}/>Cancel</Button></div>
  </div>
}

export function CourseLinks({courseId,reason='',onChanged,onError}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(false),[adding,setAdding]=useState(false),[editing,setEditing]=useState(''),[appEdit,setAppEdit]=useState(false)
  const[app,setApp]=useState({open_to_international:'',open_to_domestic:''})
  const load=async()=>{setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_course_links_read',{p_course_id:courseId});if(error)throw error;setData(d)}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  useEffect(()=>{if(courseId)load()},[courseId])
  if(!data)return busy?<Loading label="Loading links…"/>:null
  // The official course page has its own row above (with the page search and reader behind it); this list holds the other link types.
  const can=Boolean(data.can_edit)&&!busy,locks=data.locks||{},types=(data.types||[]).filter(t=>t.code!=='official_course'),a=data.applicants||{}
  const withReason=args=>({...args,...(reason.trim()?{reason:reason.trim()}:{})})
  const edit=async(action,args,confirmText)=>{if(confirmText&&!window.confirm(confirmText))return;setBusy(true)
    try{const{data:d,error}=await supabase.rpc('admin_course_link_edit',{p_course_id:courseId,p_action:action,p_args:withReason(args)});if(error)throw error;setData(d);setAdding(false);setEditing('');onChanged?.()}
    catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const saveApplicants=async(args)=>{setBusy(true)
    try{const{data:d,error}=await supabase.rpc('admin_course_applicants_edit',{p_course_id:courseId,p_args:withReason(args)});if(error)throw error;setData(d);setAppEdit(false);onChanged?.()}
    catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const lockOf=t=>t==='official_course'?locks.official_url:locks[`link:${t}`]
  const byType=types.map(t=>({...t,links:(data.links||[]).filter(l=>l.link_type===t.code)})).filter(t=>t.links.length||lockOf(t.code))
  const appLocked=locks.open_to_international||locks.open_to_domestic
  const parse=v=>v===''?null:v==='true'
  return <div className="cl-panel" data-course-links>
    <div className="cl-applicants" data-applicants>
      <div className="re-row-head"><strong><Users size={13}/> Who can apply</strong>
        {appLocked?<span className="re-lock"><Lock size={11}/>Entered by hand{can&&<button type="button" className="re-link" onClick={()=>saveApplicants({action:'release'})}><Unlock size={11}/>Let automation update this</button>}</span>
          :<span className="re-auto">{a.basis?`From ${a.basis}`:'Not yet known'}</span>}</div>
      {appEdit?<div className="cl-form">
          <label><small>International students</small><select className="fv-input" value={app.open_to_international} onChange={e=>setApp({...app,open_to_international:e.target.value})} aria-label="Open to international students">{YES_NO.map(([k,l])=><option key={k} value={k}>{l}</option>)}</select></label>
          <label><small>Domestic students</small><select className="fv-input" value={app.open_to_domestic} onChange={e=>setApp({...app,open_to_domestic:e.target.value})} aria-label="Open to domestic students">{YES_NO.map(([k,l])=><option key={k} value={k}>{l}</option>)}</select></label>
          <div className="re-foot"><Button compact variant="primary" disabled={busy} onClick={()=>saveApplicants({open_to_international:parse(app.open_to_international),open_to_domestic:parse(app.open_to_domestic)})}><Check size={13}/>Save</Button><Button compact onClick={()=>setAppEdit(false)}><X size={13}/>Cancel</Button></div>
        </div>
        :<div className="re-row-body"><div className="re-value">International students: <strong>{yn(a.open_to_international)}</strong> · Domestic students: <strong>{yn(a.open_to_domestic)}</strong>
          <small className="cl-note">{a.open_to_international===false?'Domestic only: an English requirement is not expected.':a.open_to_international===true?'An English requirement is expected for international applicants.':'Set this to show whether an English requirement is expected.'}</small></div>
          {can&&<div className="re-actions"><Button compact onClick={()=>{setApp({open_to_international:a.open_to_international==null?'':String(a.open_to_international),open_to_domestic:a.open_to_domestic==null?'':String(a.open_to_domestic)});setAppEdit(true)}} aria-label="Change who can apply"><Pencil size={13}/>Change</Button></div>}</div>}
    </div>

    <div className="cl-links">
      <div className="re-row-head"><strong><Link2 size={13}/> Other course links</strong>{can&&!adding&&<Button compact onClick={()=>setAdding(true)}><Plus size={13}/>Add link</Button>}</div>
      {adding&&<LinkForm types={types} busy={busy} onCancel={()=>setAdding(false)} onSave={v=>edit('add',v)}/>}
      {byType.length===0&&!adding&&<p className="cl-empty">No links yet.</p>}
      {byType.map(t=><div className="cl-type" key={t.code} data-link-type={t.code}>
        <div className="cl-type-head"><span>{t.label}</span>
          {lockOf(t.code)?<span className="re-lock"><Lock size={11}/>{lockOf(t.code).mode==='removed'?'Removed by hand':'Entered by hand'}{can&&<button type="button" className="re-link" onClick={()=>edit('release',{link_type:t.code},`Let automation update the ${t.label.toLowerCase()} again?`)}><Unlock size={11}/>Let automation update this</button>}</span>:null}</div>
        {t.links.map(l=>editing===l.id?<LinkForm key={l.id} types={types} initial={l} busy={busy} onCancel={()=>setEditing('')} onSave={v=>edit('change',{link_id:l.id,url:v.url,label:v.label})}/>
          :<div className={`cl-link${l.status!=='active'?' muted':''}`} key={l.id}>
            <a href={l.url} target="_blank" rel="noreferrer" className="cf-link">{l.label&&l.label!==t.label?`${l.label} · `:''}{l.url}<ExternalLink size={11}/></a>
            <span className="cl-meta"><StatusChip value={l.status} tone={(STATUS[l.status]||[])[1]||'neutral'} label={(STATUS[l.status]||[])[0]||l.status}/>
              {l.by_hand?'Entered by hand':l.source||'Automation'}{l.last_verified_at?` · checked ${fmtDateTime(l.last_verified_at)}`:''}</span>
            {can&&l.status==='active'&&<span className="re-actions"><Button compact onClick={()=>setEditing(l.id)} aria-label={`Change ${t.label}`}><Pencil size={13}/>Change</Button>
              <Button compact variant="danger" onClick={()=>edit('remove',{link_id:l.id},`Remove this ${t.label.toLowerCase()}? Automation will not add it back unless you let it.`)} aria-label={`Remove ${t.label}`}><Trash2 size={13}/>Remove</Button></span>}
          </div>)}
      </div>)}
    </div>
  </div>
}

// Provider setting: does this provider enrol international students? Applies to its courses that nobody set by hand.
// Read/write: public.admin_provider_applicants_read / admin_provider_applicants_edit (Pipeline Operator and above edit).
export function ProviderApplicants({providerId,onChanged,onError}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(false),[editing,setEditing]=useState(false),[val,setVal]=useState('')
  const load=async()=>{try{const{data:d,error}=await supabase.rpc('admin_provider_applicants_read',{p_provider_id:providerId});if(error)throw error;setData(d)}catch(e){onError?.(errText(e))}}
  useEffect(()=>{if(providerId)load()},[providerId])
  if(!data)return null
  const n=data.courses||{}
  const save=async()=>{if(!window.confirm('Apply this to the provider and to its courses that nobody has set by hand?'))return;setBusy(true)
    try{const{error}=await supabase.rpc('admin_provider_applicants_edit',{p_provider_id:providerId,p_args:{enrols_international:val===''?null:val==='true',apply_to_courses:true}});if(error)throw error;setEditing(false);await load();onChanged?.()}
    catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  return <div className="re-row" data-provider-applicants>
    <div className="re-row-head"><strong>Enrols international students</strong>{data.locked?<span className="re-lock"><Lock size={11}/>Entered by hand</span>:<span className="re-auto">{data.basis?`From ${data.basis}`:'Not yet known'}</span>}</div>
    {editing?<div className="cl-form"><select className="fv-input" value={val} onChange={e=>setVal(e.target.value)} aria-label="Enrols international students">{YES_NO.map(([k,l])=><option key={k} value={k}>{l}</option>)}</select>
        <div className="re-foot"><Button compact variant="primary" onClick={save} disabled={busy}><Check size={13}/>{busy?'Saving…':'Save'}</Button><Button compact onClick={()=>setEditing(false)}><X size={13}/>Cancel</Button></div></div>
      :<div className="re-row-body"><div className="re-value"><strong>{yn(data.enrols_international)}</strong>
        <small className="cl-note">Courses: {n.open_to_international||0} open to international students · {n.domestic_only||0} domestic only · {n.not_known||0} not yet known{n.set_by_hand?` · ${n.set_by_hand} set by hand`:''}</small></div>
        {data.can_edit&&<div className="re-actions"><Button compact onClick={()=>{setVal(data.enrols_international==null?'':String(data.enrols_international));setEditing(true)}} aria-label="Change enrols international students"><Pencil size={13}/>Change</Button></div>}</div>}
  </div>
}
